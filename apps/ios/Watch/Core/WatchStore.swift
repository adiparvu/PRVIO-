import Foundation
import Observation
import WatchKit
import WidgetKit

// MARK: - The wrist's single source of truth
//
// Owns the payload the phone pushed, the work session, the atmosphere, and
// every optimistic edit. Views read it from the environment and call its
// intent methods; they never touch WCSession or UserDefaults.
//
// Optimistic by design: an action mutates the local payload immediately
// (the wrist must feel instant), persists it where the complications read
// it, repaints the faces, and queues the real action to the phone through
// transferUserInfo — which survives unreachability, so nothing is lost on a
// hike. The phone answers with a fresh authoritative payload.

@MainActor
@Observable
final class WatchStore {

    // MARK: State

    /// The last payload from the phone, sanitized for rendering (every
    /// id-keyed collection deduplicated). nil = waiting for the iPhone.
    private(set) var payload: WatchPayload? = nil

    /// The running (or paused) maintenance timer, persisted in the App Group
    /// so the session complication renders the same one.
    private(set) var session: WatchWorkSession? = nil

    /// The phone's mood at push time; nil keeps the plain page tints.
    /// Stored (not derived) so page grounds re-render only when it changes.
    private(set) var mood: WatchMood? = nil

    /// The phone's sky at push time; wins over the mood wash when present.
    private(set) var sky: WatchSky? = nil

    /// The previous launch's captured crash, shown on the waiting screen.
    private(set) var crashNote: String? = nil

    /// The link to the iPhone.
    private(set) var connectivity: WatchConnectivityState

    /// True while a live refresh request is in flight.
    private(set) var isRefreshing = false

    /// The last all-clear the person caused on this wrist (a local edit
    /// emptied tasks, thirsty plants, shopping, or all three). In memory
    /// only: a payload from the phone, a reload or a relaunch never sets
    /// it, so a celebration plays once per clear and never on reload.
    private(set) var allClearEvent: WatchAllClearEvent? = nil

    // MARK: Derived

    /// When the phone built the snapshot on screen — the honest freshness.
    var lastUpdated: Date? { payload?.snapshot.updatedAt }

    /// The account the payload belongs to.
    var accountId: String? { payload?.accountId }

    /// False for an outsider-scoped payload (tenant / guest / worker).
    var isFamilyScope: Bool { payload?.isFamilyScope ?? true }

    /// The pager's pages, in order (Today always first).
    var visiblePages: [WatchPage] { WatchRoute.visiblePages(for: payload) }

    /// The Home hub's modules, in order.
    var visibleModules: [WatchModule] { WatchRoute.visibleModules(for: payload) }

    func isVisible(_ page: WatchPage) -> Bool { visiblePages.contains(page) }
    func isVisible(_ module: WatchModule) -> Bool { visibleModules.contains(module) }

    /// Open tasks, overdue first, catalog order within each group.
    var openTasks: [TaskCatalogEntry] {
        let open = payload?.tasks.filter { !$0.isCompleted } ?? []
        return open.filter { $0.isOverdue == true } + open.filter { $0.isOverdue != true }
    }

    /// Plants asking for water, catalog order.
    var thirstyPlants: [PlantCatalogEntry] { payload?.plants.filter(\.needsWatering) ?? [] }

    /// Shopping-list items not yet bought, catalog order.
    var pendingSupplies: [SupplyCatalogEntry] { payload?.supplies.filter { !$0.isCompleted } ?? [] }

    /// Whether "Alert the family" can name the property.
    var canAlertFamily: Bool { payload.map(WatchRoute.canAlertFamily) ?? false }

    /// How the home is doing: calm / attention / alarm (sky warmth, dial).
    var householdState: WatchHouseholdState { WatchRoute.householdState(for: payload) }

    /// Things due now (overdue + thirsty + alerting); a rise wiggles the dial.
    var attentionCount: Int { WatchRoute.attentionCount(for: payload) }

    /// Open tasks + thirsty plants + unbought shopping items.
    var openItemCount: Int { WatchRoute.openItemCount(for: payload) }

    /// A payload is present and nothing is left to clear.
    var isAllClear: Bool { payload != nil && openItemCount == 0 }

    /// The single most useful thing right now (see `WatchRoute.nextUp`).
    var nextUp: WatchNextUp? { WatchRoute.nextUp(for: payload) }

    // MARK: Persistence (frozen keys)

    private enum Key {
        static let payload = "prvio.watch.payload"
        static let mood = "prvio.watch.mood"
        static let session = SharedDataStore.watchSessionKey   // "prvio.watch.session"
    }

    /// The App Group suite, so the complications read what the app renders.
    /// Falls back to standard when the group is unavailable (simulator
    /// without entitlements).
    private let defaults: UserDefaults

    /// The bytes last written to / read from the payload key — lets a
    /// foreground reload skip the decode when nothing changed underneath.
    @ObservationIgnored
    private var persistedPayloadData: Data? = nil

    private let connector: WatchConnector?

    // MARK: Lifecycle

    init() {
        // Forensics first — everything after this line is a crash suspect.
        WatchCrashRecorder.start()
        defaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
        crashNote = WatchCrashRecorder.peek()
        let connector = WatchConnector()
        self.connector = connector
        connectivity = connector.state
        // Render instantly from the last delivery; the live link refreshes.
        loadCachedPayload()
        session = SharedDataStore.readWatchWorkSession()
        connector.delegate = self
        connector.activate()
    }

    /// A store that renders `payload` without connectivity or persistence —
    /// for SwiftUI previews only.
    init(preview payload: WatchPayload?, session: WatchWorkSession? = nil) {
        defaults = UserDefaults(suiteName: "prvio.watch.preview") ?? .standard
        connector = nil
        connectivity = .unsupported
        self.payload = payload?.sanitizedForRender()
        self.session = session
        applyAtmosphere(from: self.payload)
        WatchHaptic.isEnabled = false
    }

    /// Re-reads the cached payload when another process changed it (an
    /// interactive complication or a Siri intent mutates the same key while
    /// the app sleeps). Call when the scene becomes active.
    func reloadFromCache() {
        guard connector != nil else { return }
        let data = defaults.data(forKey: Key.payload)
        guard data != persistedPayloadData else { return }
        loadCachedPayload()
    }

    private func loadCachedPayload() {
        guard let data = defaults.data(forKey: Key.payload),
              let cached = try? JSONDecoder().decode(WatchPayload.self, from: data) else {
            persistedPayloadData = nil
            return
        }
        persistedPayloadData = data
        // Sanitized: a cached payload with duplicate row identities would
        // crash at first render on every launch.
        payload = cached.sanitizedForRender()
        applyAtmosphere(from: payload)
    }

    // MARK: Ingest

    /// Applies a payload from the phone (encoded `WatchPayload` JSON).
    ///
    /// Account handling: `accountId == nil` (signed out / mid-switch) wipes
    /// everything; a DIFFERENT account than the cached one wipes payload,
    /// session, atmosphere and stored sensor alerts before applying, so one
    /// account never sees another's data. On activation the system's last
    /// context is re-read; when the local cache is at least as fresh (it
    /// carries optimistic edits the phone has not echoed yet) it wins.
    func ingest(_ data: Data, source: WatchIngestSource = .push) {
        guard let decoded = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return }
        guard let incomingAccount = decoded.accountId, !incomingAccount.isEmpty else {
            clearAll()
            return
        }
        if let current = payload {
            if current.accountId != incomingAccount {
                clearAll()
            } else if source == .activation,
                      decoded.snapshot.updatedAt <= current.snapshot.updatedAt {
                return
            }
        }
        let clean = decoded.sanitizedForRender()
        payload = clean
        defaults.set(data, forKey: Key.payload)
        persistedPayloadData = data
        applyAtmosphere(from: clean)
        // A hazard sensor that JUST went critical taps the wrist — the one
        // payload change that must never pass silently.
        WatchSensorAlerts.evaluate(clean, defaults: defaults)
        reloadComplications()
    }

    /// Wipes every trace of the current account on the wrist.
    private func clearAll() {
        payload = nil
        session = nil
        applyAtmosphere(from: nil)
        persistedPayloadData = nil
        defaults.removeObject(forKey: Key.payload)
        defaults.removeObject(forKey: Key.mood)
        defaults.removeObject(forKey: Key.session)
        WatchSensorAlerts.reset(defaults: defaults)
        reloadComplications()
    }

    private func applyAtmosphere(from payload: WatchPayload?) {
        let newMood = payload?.mood.flatMap(WatchMood.init(rawValue:))
        if newMood != mood { mood = newMood }
        let newSky = WatchSky(payload: payload)
        if newSky != sky { sky = newSky }
        // The frozen mood key mirrors the payload's mood for any reader.
        if let newMood {
            defaults.set(newMood.rawValue, forKey: Key.mood)
        } else {
            defaults.removeObject(forKey: Key.mood)
        }
    }

    // MARK: Refresh

    /// Asks the phone for a fresh payload over the live channel. When the
    /// phone is not reachable right now the failure haptic says so instead
    /// of pretending (a request that went out but came back empty plays
    /// retry); applicationContext still delivers eventually.
    func requestRefresh() {
        guard !isRefreshing else { return }
        guard let connector,
              connector.requestPayload({ [weak self] data in self?.finishRefresh(data) }) else {
            haptic(.unreachable)
            return
        }
        isRefreshing = true
    }

    private func finishRefresh(_ data: Data?) {
        isRefreshing = false
        guard let data else {
            haptic(.retry)
            return
        }
        ingest(data, source: .refresh)
        haptic(.tick)
    }

    // MARK: Tasks

    func completeTask(_ id: UUID) {
        applyTaskCompletion(id)
        dispatch(.completeTask(id), haptic: .done)
    }

    /// Dictated on the wrist; the phone creates the real task. Appears in
    /// the local list immediately.
    func createTask(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { payload in
            payload.tasks.insert(TaskCatalogEntry(id: UUID(), title: trimmed, priority: "medium",
                                                  isCompleted: false, isOverdue: false), at: 0)
            payload.snapshot.openTaskCount += 1
        }
        dispatch(.createTask(title: trimmed), haptic: .done)
    }

    private func applyTaskCompletion(_ id: UUID) {
        mutate { payload in
            guard let i = payload.tasks.firstIndex(where: { $0.id == id }),
                  !payload.tasks[i].isCompleted else { return }
            payload.tasks[i].isCompleted = true
            payload.tasks[i].isOverdue = false
            payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
            payload.snapshot.overdueTaskCount = payload.tasks
                .filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if payload.snapshot.criticalTaskTitle == payload.tasks[i].title {
                payload.snapshot.criticalTaskTitle = nil
            }
        }
    }

    // MARK: Plants

    func waterPlant(_ id: UUID) {
        applyWatering([id])
        dispatch(.waterPlant(id), haptic: .done)
    }

    /// One tap, every thirsty plant — each watering still syncs on its own
    /// (the phone's queue is per plant); one haptic for the gesture.
    func waterAllPlants() {
        let ids = thirstyPlants.map(\.id)
        guard !ids.isEmpty else { return }
        applyWatering(ids)
        for id in ids { dispatch(.waterPlant(id), haptic: nil) }
        haptic(.done)
    }

    private func applyWatering(_ ids: [UUID]) {
        let targets = Set(ids)
        mutate { payload in
            for i in payload.plants.indices where targets.contains(payload.plants[i].id) {
                payload.plants[i].needsWatering = false
            }
            let thirsty = payload.plants.filter(\.needsWatering)
            payload.snapshot.plantsNeedingWater = thirsty.count
            payload.snapshot.plantNames = Array(thirsty.prefix(3).map(\.name))
        }
    }

    // MARK: Shopping, pantry, deliveries

    func checkSupply(_ id: UUID) {
        mutate { payload in
            guard let i = payload.supplies.firstIndex(where: { $0.id == id }) else { return }
            payload.supplies[i].isCompleted = true
            payload.snapshot.pendingSupplyCount = payload.supplies.filter { !$0.isCompleted }.count
        }
        dispatch(.checkSupply(id), haptic: .tick)
    }

    /// One unit off the pantry stock. Repeats are meaningful (each tap is a
    /// unit), which is why every transfer carries its own actionId.
    func consumePantry(_ id: UUID) {
        guard let item = payload?.pantry.first(where: { $0.id == id }), item.quantity > 0 else { return }
        mutate { payload in
            guard let i = payload.pantry.firstIndex(where: { $0.id == id }) else { return }
            payload.pantry[i].quantity = max(0, ((payload.pantry[i].quantity - 1) * 10).rounded() / 10)
        }
        dispatch(.consumePantry(id), haptic: .tick)
    }

    /// Pantry → shopping list. No optimistic supply row: the real one is
    /// born server-side with its own id and arrives in the next payload.
    func addPantryItemToShoppingList(_ id: UUID) {
        dispatch(.pantryToList(id), haptic: .tick)
    }

    func markDeliveryReceived(_ id: UUID) {
        mutate { payload in
            guard let i = payload.deliveries.firstIndex(where: { $0.id == id }),
                  payload.deliveries[i].status != "delivered" else { return }
            payload.deliveries[i].status = "delivered"
            payload.deliveries[i].eta = nil
            payload.snapshot.activeDeliveryCount = payload.deliveries
                .filter(WatchRoute.isDeliveryActive).count
        }
        dispatch(.deliveryReceived(id), haptic: .done)
    }

    // MARK: Messages

    /// Dictated for the household chat; the phone sends the real message.
    func sendChatMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        dispatch(.sendMessage(text: trimmed, target: .group), haptic: .done)
    }

    /// Dictated reply to a direct thread (`peerId` = the conversation id).
    /// The inbox preview flips to the reply immediately.
    func sendDM(to peerId: UUID, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        mutate { payload in
            guard let i = payload.dmConversations.firstIndex(where: { $0.id == peerId }) else { return }
            payload.dmConversations[i].lastBody = trimmed
            payload.dmConversations[i].isMedia = false
            payload.dmConversations[i].lastIsMine = true
            payload.dmConversations[i].lastAt = Date()
            payload.dmConversations[i].unread = 0
        }
        dispatch(.sendMessage(text: trimmed, target: .direct(peerId)), haptic: .done)
    }

    // MARK: Emergency & smart home

    /// The phone sends the exact emergency message the iPhone's own button
    /// sends into the household chat. Callers confirm first.
    func alertFamily() {
        guard canAlertFamily else { return }
        dispatch(.alertFamily, haptic: .alarm)
    }

    /// Asks the phone to raise the Emergency Live Activity (it can only do
    /// so in the foreground, so it lands on the phone's next active beat).
    func startEmergency() {
        guard isFamilyScope else { return }
        dispatch(.startEmergency, haptic: .alarm)
    }

    /// A command the actuator declared (`ActuatorCatalogEntry.commands`) —
    /// anything else is refused, so a tap always maps to a real device
    /// write. A relay's on/off echoes instantly; the phone reports truth.
    func sendCommand(actuatorId: UUID, command: String) {
        guard isFamilyScope,
              let actuator = payload?.actuators.first(where: { $0.id == actuatorId }),
              actuator.commands.contains(command) else { return }
        if command == "on" || command == "off" {
            mutate { payload in
                guard let i = payload.actuators.firstIndex(where: { $0.id == actuatorId }) else { return }
                payload.actuators[i].isOn = (command == "on")
            }
        }
        dispatch(.iotCommand(actuatorId: actuatorId, command: command), haptic: .tick)
    }

    // MARK: Work session
    //
    // Elapsed time is computed from persisted dates, so the session survives
    // the app closing and the watch sleeping. The phone mirrors it as a Live
    // Activity on its next foreground beat (the start date rides along so
    // the Dynamic Island shows the true elapsed time).

    /// Starts timing `task`; replaces any running session.
    func startSession(task: TaskCatalogEntry) {
        let now = Date()
        session = WatchWorkSession(taskId: task.id, title: task.title, startedAt: now,
                                   accumulated: 0, segmentStart: now)
        persistSession()
        dispatch(.sessionStart(taskId: task.id, title: task.title, startedAt: now), haptic: .sessionStart)
    }

    /// Freezes the clock here and on the phone, banking the time.
    func pauseSession() {
        guard var current = session, let segment = current.segmentStart else { return }
        current.accumulated += max(0, Date().timeIntervalSince(segment))
        current.segmentStart = nil
        session = current
        persistSession()
        dispatch(.sessionPause, haptic: .sessionStop)
    }

    func resumeSession() {
        guard var current = session, current.segmentStart == nil else { return }
        current.segmentStart = Date()
        session = current
        persistSession()
        dispatch(.sessionResume, haptic: .sessionStart)
    }

    func toggleSessionPause() {
        if session?.isPaused == true { resumeSession() } else { pauseSession() }
    }

    /// Ends the session. "Complete" (`completingTask: true`) also completes
    /// the task; "End" banks the time and leaves the task open.
    ///
    /// Completing also sends `completeTask` on its own: the phone completes
    /// through the session only when it had adopted that session, and its
    /// single pending-session slot can lose the start to this end when both
    /// arrive before its next foreground beat. Completion is idempotent on
    /// the phone, so the pair never completes twice.
    func endSession(completingTask: Bool) {
        guard let ended = session else { return }
        session = nil
        persistSession()
        if completingTask {
            applyTaskCompletion(ended.taskId)
            dispatch(.completeTask(ended.taskId), haptic: nil)
        }
        dispatch(.sessionEnd(completesTask: completingTask),
                 haptic: completingTask ? .done : .sessionStop)
    }

    private func persistSession() {
        if let session, let data = try? JSONEncoder().encode(session) {
            defaults.set(data, forKey: Key.session)
        } else {
            defaults.removeObject(forKey: Key.session)
        }
        // The session complication reads this exact key.
        reloadComplications()
    }

    // MARK: Plumbing

    private func mutate(_ change: (inout WatchPayload) -> Void) {
        guard var current = payload else { return }
        let before = ClearCounts(current)
        change(&current)
        payload = current
        noteAllClear(from: before, to: ClearCounts(current))
        if let data = try? JSONEncoder().encode(current) {
            defaults.set(data, forKey: Key.payload)
            persistedPayloadData = data
        }
        reloadComplications()
    }

    /// Each action speaks the vocabulary in WatchHaptic (DESIGN.md) —
    /// done lands with success, checking off clicks, sessions start/stop.
    private func dispatch(_ action: WatchAction, haptic: WatchHaptic?) {
        if let haptic { self.haptic(haptic) }
        connector?.transfer(action.userInfo())
    }

    private func haptic(_ haptic: WatchHaptic) {
        guard connector != nil else { return }
        haptic.play()
    }

    /// The open counts an all-clear is measured on.
    private struct ClearCounts {
        let tasks: Int, plants: Int, shopping: Int
        init(_ payload: WatchPayload) {
            tasks = payload.tasks.filter { !$0.isCompleted }.count
            plants = payload.plants.filter(\.needsWatering).count
            shopping = payload.supplies.filter { !$0.isCompleted }.count
        }
        var household: Int { tasks + plants + shopping }
    }

    /// Records which lists this local edit just emptied (> 0 → 0).
    private func noteAllClear(from before: ClearCounts, to after: ClearCounts) {
        var scopes = Set<WatchClearScope>()
        if before.tasks > 0, after.tasks == 0 { scopes.insert(.tasks) }
        if before.plants > 0, after.plants == 0 { scopes.insert(.plants) }
        if before.shopping > 0, after.shopping == 0 { scopes.insert(.shopping) }
        if before.household > 0, after.household == 0 { scopes.insert(.household) }
        guard !scopes.isEmpty else { return }
        allClearEvent = WatchAllClearEvent(serial: (allClearEvent?.serial ?? 0) + 1, scopes: scopes)
    }

    private func reloadComplications() {
        guard connector != nil else { return }
        WidgetCenter.shared.reloadAllTimelines()
        // Siri's "Complete <task>" / "Water <plant>" phrases resolve against
        // the entity list the system cached; refresh it with the same data.
        PRVIOWatchShortcuts.updateAppShortcutParameters()
    }
}

// MARK: - Connector events

extension WatchStore: WatchConnectorDelegate {
    func connector(_ connector: WatchConnector, didReceivePayload data: Data, source: WatchIngestSource) {
        ingest(data, source: source)
    }

    func connector(_ connector: WatchConnector, didChangeState state: WatchConnectivityState) {
        if connectivity != state { connectivity = state }
    }

    func connectorDidActivate(_ connector: WatchConnector) {
        // Actions taken on the face (interactive complications) or through
        // Siri while the app was closed — forward them to the phone.
        for entry in WatchActionRelay.drain() {
            guard let action = entry["action"], let id = entry["id"] else { continue }
            connector.transfer(WatchAction.relayed(action: action, id: id).userInfo())
        }
        // A captured crash from a previous launch rides the same queue to
        // the iPhone's Watch settings page.
        if let crash = WatchCrashRecorder.drain() {
            connector.transfer(WatchAction.watchCrash(text: crash).userInfo())
        }
        // The widget may have mutated the cache while the app slept.
        reloadFromCache()
    }
}
