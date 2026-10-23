import Foundation
import WatchConnectivity
import WidgetKit

// MARK: - Watch sync (phone side)
//
// Pushes the widget snapshot + catalogs to the paired Apple Watch through
// `updateApplicationContext` — the fire-and-forget WatchConnectivity channel
// that always carries the LATEST state and survives the watch app being
// closed. Called from the same place the widget snapshot is written, so the
// watch can never drift from what the widgets show.
//
// The reverse channel makes the wrist ACT: the watch queues actions through
// `transferUserInfo` (guaranteed delivery, survives unreachability) and this
// service lands them in the exact pipeline the widget App Intents already
// use — pending queue + instant local catalog mutation + Supabase
// reconciliation on the app's next foreground beat.

final class WatchSyncService: NSObject, WCSessionDelegate {
    static let shared = WatchSyncService()

    private static let lastPushKey = "prvio.watch.lastPush"

    /// The payload that arrived before the session finished activating —
    /// pushed as soon as activation completes so a cold start isn't dropped.
    private var pending: WatchPayload?

    /// Snapshot of the phone↔watch link for the settings hub. nil when
    /// WatchConnectivity is unsupported or the session hasn't activated yet.
    struct LinkStatus {
        let paired: Bool
        let installed: Bool
        let reachable: Bool
    }

    var linkStatus: LinkStatus? {
        guard WCSession.isSupported() else { return nil }
        let session = WCSession.default
        guard session.activationState == .activated else { return nil }
        return LinkStatus(paired: session.isPaired,
                          installed: session.isWatchAppInstalled,
                          reachable: session.isReachable)
    }

    /// When the last payload actually left for the watch.
    var lastPushAt: Date? {
        let t = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .double(forKey: Self.lastPushKey) ?? 0
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func push(_ payload: WatchPayload) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pending = payload
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // applicationContext keeps only the newest value — exactly right for
        // a state snapshot; no queue to back up, nothing to retry.
        do {
            try session.updateApplicationContext(["payload": data])
            UserDefaults(suiteName: SharedDataStore.suiteName)?
                .set(Date().timeIntervalSince1970, forKey: Self.lastPushKey)
        } catch {
            // Never silent again: an oversized or rejected context left the
            // wrist on stale data with no trace anywhere.
            debugLog("Watch push failed (\(data.count) bytes):", error)
        }
    }

    /// Push a signed-out marker (empty snapshot, `accountId == nil`) so the watch
    /// wipes its cached glance data. Sent on logout and immediately on account
    /// switch, before the new account's fresh payload arrives, so the wrist
    /// never lingers on the previous account's data.
    func pushCleared() {
        push(WatchPayload(snapshot: PRVIOWidgetSnapshot(), accountId: nil))
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else { return }
        // Delegate callbacks arrive on a background queue; `pending` is
        // written by push() on main — touch it only there.
        DispatchQueue.main.async { [weak self] in
            guard let self, let payload = self.pending else { return }
            self.pending = nil
            self.push(payload)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // A watch switch deactivates the session; re-activate for the new watch.
        session.activate()
    }

    // MARK: On-demand refresh (watch asks, phone answers instantly)

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["action"] as? String == "refresh",
              let payload = SharedDataStore.currentWatchPayload(),
              let data = try? JSONEncoder().encode(payload) else {
            replyHandler([:])
            return
        }
        replyHandler(["payload": data])
    }

    // MARK: Wrist actions

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let action = userInfo["action"] as? String else { return }
        // Idempotency: transferUserInfo can re-deliver a transfer after an
        // ambiguous hand-off, and actions like alertFamily or sendMessage are
        // not idempotent downstream. The watch stamps each transfer with a
        // fresh actionId; a previously processed id is a replay and is
        // dropped. Transfers from older watch builds carry no actionId and
        // process exactly as before.
        if let actionId = userInfo["actionId"] as? String,
           !SharedDataStore.registerProcessedWatchAction(actionId) {
            return
        }
        // A crash captured on the wrist by WatchCrashRecorder — the "opens
        // for a second and closes" black box. Persisted so the Watch
        // settings page can name the killer; also in the debug log.
        if action == "watchCrash", let text = userInfo["text"] as? String {
            debugLog("[WatchCrash]", text)
            UserDefaults.standard.set(text, forKey: "prvio.watch.crashReport")
            return
        }
        // Dictated from the wrist: park the title; the app creates the real
        // task through TaskService on its next foreground beat.
        if action == "createTask", let title = userInfo["title"] as? String,
           !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            DispatchQueue.main.async {
                SharedDataStore.appendPendingWatchTask(title)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        // Dictated on the wrist for the house chat or a direct thread — rides
        // the same queue the notification reply action uses, so one drain
        // path sends all of them. `target` speaks the queue's own dialect
        // ("dm:<peer-user-id>"); absent means the household chat, as before.
        if action == "sendMessage", let text = userInfo["text"] as? String,
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let target = userInfo["target"] as? String ?? "group"
            DispatchQueue.main.async {
                SharedDataStore.appendPendingChatReply(text, target: target)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        // "Alert the family" from the wrist — the EXACT message the Emergency
        // page's own button sends (same emg_alert_message body, same
        // MessageService.send into the household chat), delivered through the
        // guaranteed chat-reply queue so a pocketed phone still sends it on
        // its next beat. The DB trigger fans it out as pushes, as on iPhone.
        if action == "alertFamily" {
            DispatchQueue.main.async {
                guard let property = SharedDataStore.read()?.propertyName,
                      !property.isEmpty else { return }
                let body = String(format: String(localized: "emg_alert_message"), property)
                SharedDataStore.appendPendingChatReply(body)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        // The watch's work session, mirrored as a phone Live Activity. The
        // system only lets the app START one in the foreground, so both
        // events park in the App Group and drain on the next active beat.
        if action == "sessionStart", let idString = userInfo["id"] as? String,
           let id = UUID(uuidString: idString),
           let title = userInfo["title"] as? String {
            let startedAt = (userInfo["startedAt"] as? String).flatMap(Double.init)
                .map(Date.init(timeIntervalSince1970:)) ?? Date()
            DispatchQueue.main.async {
                SharedDataStore.writePendingSessionStart(taskId: id, title: title, startedAt: startedAt)
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        if action == "sessionEnd" {
            DispatchQueue.main.async {
                SharedDataStore.writePendingSessionEnd(
                    completingTask: (userInfo["complete"] as? String) != "0")
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        // Pause / resume taken on the wrist freeze the same phone session, so
        // its banner/row and the Dynamic Island match the watch exactly.
        if action == "sessionPause" {
            DispatchQueue.main.async { WorkSessionStore.shared.pause() }
            return
        }
        if action == "sessionResume" {
            DispatchQueue.main.async { WorkSessionStore.shared.resume() }
            return
        }
        // A smart-home command from the wrist (toggle a relay, open the
        // garage). Parked for the app to execute against the real device on
        // its next active beat; a relay also gets an optimistic echo so the
        // watch face reflects the tap immediately, reconciled when the phone
        // reports the true state back.
        if action == "iotCommand", let idString = userInfo["actuatorId"] as? String,
           let id = UUID(uuidString: idString), let cmd = userInfo["command"] as? String {
            DispatchQueue.main.async { [weak self] in
                SharedDataStore.appendPendingIoTCommand(actuatorId: id, command: cmd)
                if cmd == "on" || cmd == "off" {
                    SharedDataStore.applyLocalActuatorState(id: id, isOn: cmd == "on")
                }
                if let payload = SharedDataStore.currentWatchPayload() { self?.push(payload) }
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        // "Start emergency mode" from the wrist — parked, then the foreground
        // app raises the real Emergency Live Activity on its next active beat.
        if action == "startEmergency" {
            DispatchQueue.main.async {
                SharedDataStore.setPendingEmergencyStart()
                NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
            }
            return
        }
        guard let idString = userInfo["id"] as? String,
              let id = UUID(uuidString: idString) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.apply(action: action, id: id)
        }
    }

    private func apply(action: String, id: UUID) {
        switch action {
        case "completeTask":
            SharedDataStore.appendPendingCompletion(id)
            SharedDataStore.applyLocalTaskCompletion(id)
        case "waterPlant":
            SharedDataStore.appendPendingWatering(id)
            SharedDataStore.applyLocalWatering(id)
        case "checkSupply":
            SharedDataStore.appendPendingSupplyCheck(id)
            SharedDataStore.applyLocalSupplyCheck(id)
        case "consumePantry":
            SharedDataStore.appendPendingPantryConsume(id)
            SharedDataStore.applyLocalPantryConsume(id)
        case "deliveryReceived":
            // Same pending queue the Live Activity island uses — the app's
            // next beat lands it in DeliveryService.markDelivered.
            SharedDataStore.appendPendingDeliveryReceived(id)
            SharedDataStore.applyLocalDeliveryReceived(id)
        case "pantryToList":
            // No optimistic catalog echo: the real supply row (with its
            // server id) appears in the next authoritative payload after
            // SupplyService.addItem runs on the drain.
            SharedDataStore.appendPendingPantryToList(id)
        default:
            return
        }
        // Every glass repaints from the mutated catalogs: home-screen widgets,
        // the watch (fresh context push), and — if the app is live — Supabase
        // itself through the same reconciliation the widget buttons use.
        WidgetCenter.shared.reloadAllTimelines()
        if let payload = SharedDataStore.currentWatchPayload() { push(payload) }
        NotificationCenter.default.post(name: .prvioProcessPending, object: nil)
    }
}
