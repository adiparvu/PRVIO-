import SwiftUI
import UserNotifications
import WatchConnectivity
import WatchKit
import WidgetKit

// MARK: - PRVIO for Apple Watch
//
// A working companion: the phone pushes the same snapshot the widgets render
// (plus the task/plant/supply/delivery catalogs) over WatchConnectivity, and
// the watch shows it in vertical pages — Today, Tasks, Plants, Shopping,
// Deliveries. V2 acts from the wrist: completing a task, watering a plant or
// checking off a purchase mutates the local payload instantly and queues the
// action to the phone through transferUserInfo, which WatchConnectivity
// delivers even if the iPhone is unreachable right now.

@main
struct PRVIOWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

extension TimeInterval {
    /// "1:20:05" past an hour, else "20:05" — the wrist stopwatch readout.
    /// (The phone has its own copy in WorkSessionStore, which isn't compiled
    /// into the watch target.)
    var watchSessionClock: String {
        let total = Int(max(0, self))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// "1:20" / "0:20" — h:mm with no seconds, for the Always On state:
    /// a TimelineView demoted to minute cadence can't keep a seconds digit
    /// honest, so the readout drops it rather than showing a stale one.
    var watchSessionClockMinutes: String {
        let total = Int(max(0, self))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }
}

// MARK: - Wrist crash forensics (the 1069/1072 playbook, on the watch)
//
// "Opens for a second and closes" is a crash in the launch/first-render
// path — the class both historical wrist crashes belonged to (duplicate
// ForEach identities, undeclared Handoff type), and both were
// NSExceptions, exactly what this handler catches. The report survives in
// the App Group; the NEXT launch (even a one-second one) shows it on the
// waiting screen and forwards it to the iPhone over the guaranteed
// transferUserInfo queue, where the Watch settings page displays it.

enum WatchCrashRecorder {
    fileprivate static let key = "prvio.watch.lastCrash"
    fileprivate static let launchKey = "prvio.watch.launchInFlight"
    fileprivate static let deathCountKey = "prvio.watch.launchDeathCount"

    static func arm() {
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(exception.name.rawValue): \(exception.reason ?? "?")\n"
                + exception.callStackSymbols.prefix(8).joined(separator: "\n")
            (UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard)
                .set(text, forKey: WatchCrashRecorder.key)
        }
    }

    /// Launch breadcrumb — the NSException handler is blind to watchdog
    /// kills and hard (signal) crashes, which is exactly the "never opens"
    /// class. A sentinel set here and cleared only by the first rendered
    /// frame means: still present at the NEXT launch → the previous launch
    /// died silently. Counted, and synthesized into a report when the
    /// exception handler captured nothing, so the phone card names even
    /// the deaths it cannot see. (A death BEFORE this line — dyld/launch
    /// loader — stays invisible to the app; only the system .ips has it.)
    static func beginLaunch() {
        let defaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
        if defaults.bool(forKey: launchKey) {
            let died = defaults.integer(forKey: deathCountKey) + 1
            defaults.set(died, forKey: deathCountKey)
            if defaults.string(forKey: key) == nil {
                defaults.set(
                    "Launch died before first frame ×\(died) — no exception captured "
                    + "(watchdog kill or hard crash). The system .ips report has the cause.",
                    forKey: key)
            }
        }
        defaults.set(true, forKey: launchKey)
    }

    /// The first frame rendered — this launch survived; clear the sentinel
    /// so a later clean exit is never miscounted as a death.
    static func firstFrameRendered() {
        let defaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
        defaults.set(false, forKey: launchKey)
        defaults.removeObject(forKey: deathCountKey)
    }

    static func peek() -> String? {
        (UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard)
            .string(forKey: key)
    }

    static func drain() -> String? {
        let defaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
        guard let text = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return text
    }
}

// MARK: - Store (session delegate + cache)

@Observable
final class WatchStore: NSObject, WCSessionDelegate, UNUserNotificationCenterDelegate {
    private(set) var payload: WatchPayload?
    /// The app mood that rode the current payload ("morning"/"day"/"night") —
    /// nil until the phone actually sends one, and the pages then keep their
    /// plain tints. See WatchMood.swift for the whole honesty contract.
    private(set) var mood: WatchMood?

    private static let cacheKey = "prvio.watch.payload"
    /// Persisted separately from the payload blob: wrist-side mutations
    /// re-encode the cache through the frozen WatchPayload struct, which may
    /// not carry the mood field yet — this key survives that round trip.
    private static let moodKey = "prvio.watch.mood"
    /// The App Group suite, so the watch-face complications read the same
    /// payload the app renders. Falls back to standard if the group is
    /// unavailable (e.g. simulator without entitlements).
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    /// The previous launch's crash, when one was captured — shown on the
    /// waiting screen so the wrist itself names what killed it.
    private(set) var lastCrashNote: String?

    override init() {
        super.init()
        // Forensics FIRST — everything after this line is a crash suspect.
        WatchCrashRecorder.arm()
        WatchCrashRecorder.beginLaunch()
        lastCrashNote = WatchCrashRecorder.peek()
        // Render instantly from the last delivery, then refresh live.
        // sanitizedForRender: a cached payload with duplicate row identities
        // crashes at first render on EVERY launch (Series 4 stays on
        // watchOS 10 forever, so that device never outgrows the bug).
        if let data = Self.defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(WatchPayload.self, from: data) {
            payload = cached.sanitizedForRender()
            // The last delivery's mood — the same freshness as the cached
            // payload it arrived with (nil when none ever arrived).
            mood = Self.defaults.string(forKey: Self.moodKey)
                .flatMap(WatchMood.init(rawValue:))
        }
        // Local critical-sensor alerts must show even while the app is up —
        // the delegate's willPresent grants them the banner.
        UNUserNotificationCenter.current().delegate = self
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func ingest(_ context: [String: Any]) {
        guard let data = context["payload"] as? Data else { return }
        ingestData(data)
    }

    private func ingestData(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        // The frozen WatchPayload struct may not declare the mood field yet;
        // the probe reads it straight off the wire the moment the phone
        // starts sending it, and stays nil until then.
        let deliveredMood = WatchMood.fromPayloadData(data)
        Task { @MainActor in
            // A cleared push (accountId == nil) means the phone logged out or is
            // mid-switch — wipe the cache so the wrist stops showing the previous
            // account's data and falls back to the "waiting for iPhone" state.
            if decoded.accountId == nil {
                self.payload = nil
                self.mood = nil
                Self.defaults.removeObject(forKey: Self.cacheKey)
                Self.defaults.removeObject(forKey: Self.moodKey)
                Self.defaults.removeObject(forKey: Self.criticalSensorsKey)
                WidgetCenter.shared.reloadAllTimelines()
                return
            }
            self.payload = decoded.sanitizedForRender()
            Self.defaults.set(data, forKey: Self.cacheKey)
            // Each delivery is the mood's only honest source — a payload
            // without one (older phone build) clears it rather than letting
            // a stale atmosphere linger.
            self.mood = deliveredMood
            if let deliveredMood {
                Self.defaults.set(deliveredMood.rawValue, forKey: Self.moodKey)
            } else {
                Self.defaults.removeObject(forKey: Self.moodKey)
            }
            // A hazard sensor that JUST went critical taps the wrist — the
            // one payload change that must never pass silently.
            self.alertCriticalSensorTransitions(in: decoded)
            // Fresh state → repaint the watch-face complications too.
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Critical sensor alerts (local, on the wrist)
    //
    // Fires exactly on the TRANSITION into critical (smoke / gas / water
    // alerting), deduplicated across launches by persisting the set of
    // currently-critical sensor ids — a payload refresh while the leak is
    // still active must not re-alarm. Honest scope: detection runs when a
    // payload actually reaches the watch app (delivery or refresh); the
    // watch has no background channel of its own.

    private static let criticalSensorsKey = "prvio.watch.criticalSensorIds"

    private func alertCriticalSensorTransitions(in payload: WatchPayload) {
        let critical = payload.sensors.filter { $0.isCritical && $0.isAlerting }
        let previous = Set((Self.defaults.stringArray(forKey: Self.criticalSensorsKey) ?? [])
            .compactMap(UUID.init(uuidString:)))
        let currentIds = Set(critical.map(\.id))
        guard currentIds != previous else { return }
        Self.defaults.set(currentIds.map(\.uuidString), forKey: Self.criticalSensorsKey)
        let fresh = critical.filter { !previous.contains($0.id) }
        guard !fresh.isEmpty else { return }
        WKInterfaceDevice.current().play(.failure)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            for sensor in fresh {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "watch_sensor_alert_title")
                content.body = [sensor.name, sensor.zone, sensor.displayValue]
                    .compactMap { $0 }.joined(separator: " · ")
                content.sound = .default
                center.add(UNNotificationRequest(
                    identifier: "prvio.sensor.\(sensor.id.uuidString)",
                    content: content, trigger: nil))
            }
        }
    }

    /// Show our local sensor alarms as banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: On-demand refresh
    //
    // applicationContext delivers "eventually"; when the phone is reachable
    // RIGHT NOW, the live channel answers instantly — and when it isn't, the
    // retry haptic says so instead of pretending.

    private(set) var isRefreshing = false

    func requestRefresh() {
        let session = WCSession.default
        guard WCSession.isSupported(), session.isReachable else {
            WKInterfaceDevice.current().play(.retry)
            return
        }
        isRefreshing = true
        session.sendMessage(["action": "refresh"], replyHandler: { [weak self] reply in
            Task { @MainActor in
                self?.isRefreshing = false
                if let data = reply["payload"] as? Data {
                    self?.ingestData(data)
                    WKInterfaceDevice.current().play(.click)
                }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                self?.isRefreshing = false
                WKInterfaceDevice.current().play(.retry)
            }
        })
    }

    // MARK: Wrist actions
    //
    // Mutate the cached payload immediately (the wrist must feel instant),
    // then queue the action to the phone. transferUserInfo persists across
    // unreachability and app restarts, so nothing is lost on a hike; the
    // phone lands it in the same pending-action pipeline the widget buttons
    // use and answers with a fresh authoritative payload.

    func completeTask(_ id: UUID) {
        mutate { payload in
            guard let i = payload.tasks.firstIndex(where: { $0.id == id }) else { return }
            payload.tasks[i].isCompleted = true
            payload.tasks[i].isOverdue = false
            payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
            payload.snapshot.overdueTaskCount = payload.tasks.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if payload.snapshot.criticalTaskTitle == payload.tasks[i].title {
                payload.snapshot.criticalTaskTitle = nil
            }
        }
        queue(action: "completeTask", id: id, haptic: .success)
    }

    func waterPlant(_ id: UUID) {
        mutate { payload in
            guard let i = payload.plants.firstIndex(where: { $0.id == id }) else { return }
            payload.plants[i].needsWatering = false
            let thirsty = payload.plants.filter(\.needsWatering)
            payload.snapshot.plantsNeedingWater = thirsty.count
            payload.snapshot.plantNames = Array(thirsty.prefix(3).map(\.name))
        }
        queue(action: "waterPlant", id: id, haptic: .directionUp)
    }

    func checkSupply(_ id: UUID) {
        mutate { payload in
            guard let i = payload.supplies.firstIndex(where: { $0.id == id }) else { return }
            payload.supplies[i].isCompleted = true
            payload.snapshot.pendingSupplyCount = payload.supplies.filter { !$0.isCompleted }.count
        }
        queue(action: "checkSupply", id: id, haptic: .click)
    }

    /// Dictated on the wrist; the phone creates the real task. Optimistic:
    /// it appears in the local list immediately so the wrist feels instant.
    func createTask(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { payload in
            payload.tasks.insert(TaskCatalogEntry(id: UUID(), title: trimmed,
                                                  priority: "medium",
                                                  isCompleted: false,
                                                  isOverdue: false), at: 0)
            payload.snapshot.openTaskCount += 1
        }
        WKInterfaceDevice.current().play(.success)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "createTask", "title": trimmed,
                                            "actionId": UUID().uuidString])
    }

    /// One tap, every thirsty plant — each watering still syncs individually.
    func waterAllPlants() {
        let thirsty = payload?.plants.filter(\.needsWatering) ?? []
        for plant in thirsty { waterPlant(plant.id) }
    }

    /// One unit off the pantry stock, from the wrist.
    func consumePantry(_ id: UUID) {
        mutate { payload in
            guard let i = payload.pantry.firstIndex(where: { $0.id == id }) else { return }
            payload.pantry[i].quantity = max(0, ((payload.pantry[i].quantity - 1) * 10).rounded() / 10)
        }
        queue(action: "consumePantry", id: id, haptic: .click)
    }

    /// A smart-home command from the wrist. A relay's on/off echoes instantly
    /// on the face; the phone performs the real device write on its next active
    /// beat and reports the true state back. `command` is always one the
    /// actuator declared, so this never issues an action the device can't do.
    func sendCommand(actuatorId: UUID, command: String) {
        if command == "on" || command == "off" {
            mutate { payload in
                guard let i = payload.actuators.firstIndex(where: { $0.id == actuatorId }) else { return }
                payload.actuators[i].isOn = (command == "on")
            }
        }
        WKInterfaceDevice.current().play(.click)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "iotCommand",
                                            "actuatorId": actuatorId.uuidString,
                                            "command": command])
    }

    /// Pins the property's Emergency Live Activity from the wrist. The phone
    /// raises the real activity on its next foreground beat (ActivityKit only
    /// starts one in the foreground); the strong haptic confirms the request.
    func startEmergency() {
        WKInterfaceDevice.current().play(.notification)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "startEmergency"])
    }

    // MARK: Work session (a maintenance timer on the wrist)
    //
    // Honest scope: the elapsed time is computed from the persisted start
    // date, so the session survives the app closing and the watch sleeping —
    // but the quarter-hour haptic only fires while the session screen is up
    // (background haptics would require a workout session we can't justify).

    /// The session model now lives in SharedDataStore (same on-disk JSON,
    /// same key) so the watch WIDGET extension renders the identical session
    /// this store is timing — the typealias keeps every existing call site.
    typealias WorkSession = WatchWorkSession

    private static let sessionKey = SharedDataStore.watchSessionKey

    private(set) var activeSession: WorkSession? = {
        guard let data = (UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard)
            .data(forKey: sessionKey) else { return nil }
        return try? JSONDecoder().decode(WorkSession.self, from: data)
    }()

    func startSession(taskId: UUID, title: String) {
        let now = Date()
        let session = WorkSession(taskId: taskId, title: title, startedAt: now,
                                  accumulated: 0, segmentStart: now)
        activeSession = session
        persistSession()
        WKInterfaceDevice.current().play(.start)
        // Mirror on the iPhone as a Live Activity. The phone can only start
        // one while foregrounded, so this queues honestly via userInfo — the
        // Dynamic Island appears the next time the phone is active, showing
        // the TRUE elapsed time (the start date rides along).
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo([
            "action": "sessionStart",
            "id": taskId.uuidString,
            "title": title,
            "startedAt": String(session.startedAt.timeIntervalSince1970),
        ])
    }

    private func persistSession() {
        if let s = activeSession, let data = try? JSONEncoder().encode(s) {
            Self.defaults.set(data, forKey: Self.sessionKey)
        } else {
            Self.defaults.removeObject(forKey: Self.sessionKey)
        }
        // The session complication reads this exact key — repaint the face
        // on every start/pause/resume/end.
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Freezes the clock on the wrist and tells the phone to pause the same
    /// session, so the banked time stays identical on both.
    func pauseSession() {
        guard var s = activeSession, let seg = s.segmentStart else { return }
        s.accumulated += max(0, Date().timeIntervalSince(seg))
        s.segmentStart = nil
        activeSession = s
        persistSession()
        WKInterfaceDevice.current().play(.click)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sessionPause"])
    }

    func resumeSession() {
        guard var s = activeSession, s.segmentStart == nil else { return }
        s.segmentStart = Date()
        activeSession = s
        persistSession()
        WKInterfaceDevice.current().play(.start)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sessionResume"])
    }

    func toggleSessionPause() { activeSession?.isPaused == true ? resumeSession() : pauseSession() }

    /// Ends the session; optionally completes the task it timed.
    func endSession(completingTask: Bool) {
        let session = activeSession
        activeSession = nil
        persistSession()
        if completingTask, let session { completeTask(session.taskId) }
        else { WKInterfaceDevice.current().play(.stop) }
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sessionEnd"])
    }

    /// Dictated on the wrist for the house chat — the phone sends the real
    /// message on its next beat. transferUserInfo persists across
    /// unreachability, so nothing dictated is ever lost.
    func sendChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WKInterfaceDevice.current().play(.success)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sendMessage", "text": trimmed,
                                            "actionId": UUID().uuidString])
    }

    /// Dictated reply to a direct thread. Rides the same guaranteed queue as
    /// the house chat, with the "dm:<peer-user-id>" target the notification
    /// quick-reply pipeline already routes — the phone's DirectMessageService
    /// performs the real send on its next beat. Optimistic: the conversation
    /// preview flips to the reply so the inbox reflects the tap instantly.
    func sendDM(to peerId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { payload in
            guard let i = payload.dmConversations.firstIndex(where: { $0.id == peerId }) else { return }
            payload.dmConversations[i].lastBody = trimmed
            payload.dmConversations[i].isMedia = false
            payload.dmConversations[i].lastIsMine = true
            payload.dmConversations[i].lastAt = Date()
        }
        WKInterfaceDevice.current().play(.success)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "sendMessage",
                                            "text": trimmed,
                                            "target": "dm:\(peerId.uuidString)",
                                            "actionId": UUID().uuidString])
    }

    /// "Alert the family" — the phone sends the exact emergency message the
    /// iPhone Emergency page's own button sends, into the household chat
    /// (the DB trigger fans it out as pushes). Guaranteed delivery to the
    /// phone; the strong haptic confirms the request left the wrist.
    func alertFamily() {
        WKInterfaceDevice.current().play(.notification)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": "alertFamily",
                                            "actionId": UUID().uuidString])
    }

    /// Package received, confirmed from the wrist. The parcel flips locally,
    /// and the phone lands the real DeliveryService.markDelivered through
    /// the same pending queue the Live Activity island uses.
    func markDeliveryReceived(_ id: UUID) {
        mutate { payload in
            guard let i = payload.deliveries.firstIndex(where: { $0.id == id }),
                  payload.deliveries[i].status != "delivered" else { return }
            payload.deliveries[i].status = "delivered"
            payload.deliveries[i].eta = nil
            payload.snapshot.activeDeliveryCount = payload.deliveries
                .filter { $0.status == "expected" || $0.status == "out_for_delivery" }.count
        }
        queue(action: "deliveryReceived", id: id, haptic: .success)
    }

    /// Pantry → shopping list. No optimistic supply row (the real one is
    /// born server-side with its own id); the click confirms the queued
    /// request and the next authoritative payload shows it on the list.
    func addPantryItemToShoppingList(_ id: UUID) {
        queue(action: "pantryToList", id: id, haptic: .click)
    }

    private func mutate(_ change: (inout WatchPayload) -> Void) {
        guard var current = payload else { return }
        change(&current)
        payload = current
        if let data = try? JSONEncoder().encode(current) {
            Self.defaults.set(data, forKey: Self.cacheKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Each action speaks its own haptic dialect — completing lands with
    /// success, watering lifts, checking off clicks.
    ///
    /// Every transfer carries a fresh `actionId` so the phone can drop a
    /// re-delivered duplicate. This matters most for consumePantry, whose
    /// pending queue treats repeats as meaningful; two intentional taps get
    /// two different ids and both count, while one replayed transfer doesn't.
    private func queue(action: String, id: UUID, haptic: WKHapticType) {
        WKInterfaceDevice.current().play(haptic)
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(["action": action, "id": id.uuidString,
                                            "actionId": UUID().uuidString])
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // applicationContext is persisted by the system — the newest push is
        // already waiting here even if the watch app wasn't running for it.
        guard activationState == .activated else { return }
        ingest(session.receivedApplicationContext)
        // Actions performed on the face (interactive complications) queued in
        // the App Group while the app was closed — forward them to the phone.
        for entry in WatchActionRelay.drain() {
            guard let action = entry["action"], let id = entry["id"] else { continue }
            session.transferUserInfo(["action": action, "id": id])
        }
        // A captured crash from a previous launch rides the same guaranteed
        // queue to the iPhone, where the Watch settings page displays it.
        if let crash = WatchCrashRecorder.drain() {
            session.transferUserInfo(["action": "watchCrash", "text": crash,
                                      "actionId": UUID().uuidString])
        }
        Task { @MainActor [weak self] in
            // Re-read the cache: the widget may have mutated it while we slept.
            if let data = Self.defaults.data(forKey: Self.cacheKey),
               let cached = try? JSONDecoder().decode(WatchPayload.self, from: data) {
                self?.payload = cached.sanitizedForRender()
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }
}
