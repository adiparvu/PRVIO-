import Foundation

// MARK: - Widget snapshot (shared between main app and widget extension via App Groups)

/// One upcoming deadline, flattened for the widgets and the watch. The app
/// owns the HouseAgenda aggregator; the extension processes can't see it, so
/// the phone projects the next few items down to these primitives. `date` is
/// the day the deadline falls on; `icon` is its category's SF Symbol.
struct WidgetDeadline: Codable, Hashable {
    var title: String
    var date: Date
    var icon: String
    var category: String
}

struct PRVIOWidgetSnapshot: Codable {
    var overdueTaskCount: Int = 0
    var openTaskCount: Int = 0
    var pendingSupplyCount: Int = 0
    var plantsNeedingWater: Int = 0
    var plantNames: [String] = []
    var unreadMessages: Int = 0
    var propertyName: String? = nil
    var propertyHealthScore: Int? = nil
    var criticalTaskTitle: String? = nil
    var nextMaintenanceTitle: String? = nil
    // Optional so snapshots written before this field existed still decode.
    var nextMaintenanceDue: String? = nil
    var activeDeliveryCount: Int = 0
    /// The next few dated things the house knows about (tasks, documents,
    /// warranties, birthdays, rents…), for the "Upcoming" lock-screen widget.
    var upcomingDeadlines: [WidgetDeadline] = []
    var updatedAt: Date = Date()

    init() {}

    /// Every field decodes leniently: a snapshot written by ANY app version
    /// must decode in every widget/watch process, or the widgets freeze on
    /// defaults. (activeDeliveryCount was added non-optional — old
    /// snapshots threw keyNotFound and the whole snapshot silently
    /// vanished.)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        overdueTaskCount     = try c.decodeIfPresent(Int.self,      forKey: .overdueTaskCount) ?? 0
        openTaskCount        = try c.decodeIfPresent(Int.self,      forKey: .openTaskCount) ?? 0
        pendingSupplyCount   = try c.decodeIfPresent(Int.self,      forKey: .pendingSupplyCount) ?? 0
        plantsNeedingWater   = try c.decodeIfPresent(Int.self,      forKey: .plantsNeedingWater) ?? 0
        plantNames           = try c.decodeIfPresent([String].self, forKey: .plantNames) ?? []
        unreadMessages       = try c.decodeIfPresent(Int.self,      forKey: .unreadMessages) ?? 0
        propertyName         = try c.decodeIfPresent(String.self,   forKey: .propertyName)
        propertyHealthScore  = try c.decodeIfPresent(Int.self,      forKey: .propertyHealthScore)
        criticalTaskTitle    = try c.decodeIfPresent(String.self,   forKey: .criticalTaskTitle)
        nextMaintenanceTitle = try c.decodeIfPresent(String.self,   forKey: .nextMaintenanceTitle)
        nextMaintenanceDue   = try c.decodeIfPresent(String.self,   forKey: .nextMaintenanceDue)
        activeDeliveryCount  = try c.decodeIfPresent(Int.self,      forKey: .activeDeliveryCount) ?? 0
        upcomingDeadlines    = try c.decodeIfPresent([WidgetDeadline].self, forKey: .upcomingDeadlines) ?? []
        updatedAt            = try c.decodeIfPresent(Date.self,     forKey: .updatedAt) ?? Date()
    }
}

// MARK: - Watch payload (pushed to the watch over WatchConnectivity)
//
// The watch is a different device — it cannot read the phone's App Group.
// The phone pushes this bundle (the same snapshot the widgets render, plus
// the task/plant catalogs for real lists) via updateApplicationContext,
// which WatchConnectivity persists and delivers even when the watch app
// launches later.

struct WatchPayload: Codable {
    var snapshot: PRVIOWidgetSnapshot
    /// The auth user id this payload belongs to. `nil` means a cleared /
    /// signed-out state — the watch wipes its cache when it receives it, so a
    /// logged-out or switched account never keeps showing the previous owner's
    /// data.
    var accountId: String? = nil
    /// `false` when the payload was scoped for an outsider (tenant/guest/worker)
    /// — the watch then keeps itself to the person's own surfaces only.
    var isFamilyScope: Bool = true
    var tasks: [TaskCatalogEntry] = []
    var plants: [PlantCatalogEntry] = []
    var supplies: [SupplyCatalogEntry] = []
    var deliveries: [DeliveryCatalogEntry] = []
    /// Pantry stock for the wrist — consume-one taps ride the action queue.
    var pantry: [PantryCatalogEntry] = []
    /// Property coordinates for the wrist map (nil until geocoded).
    var latitude: Double? = nil
    var longitude: Double? = nil
    /// The top ProactiveEngine insight — the phone's intelligence, delivered
    /// to the wrist and readable offline.
    var insightTitle: String? = nil
    var insightBody: String? = nil
    /// Apple Weather for the property (fetched on the phone). Advisory is a
    /// raw token ("frost" | "rain") — the watch localizes it.
    var weatherTemp: Double? = nil
    var weatherSymbol: String? = nil
    var weatherLo: Double? = nil
    var weatherHi: Double? = nil
    var weatherAdvisory: String? = nil
    /// Consecutive all-clear days (no overdue tasks, no thirsty plants) —
    /// the house streak, computed on the phone.
    var streakDays: Int? = nil
    /// This month's spending in the household currency, and the total
    /// monthly budget when one is set. Sums never mix currencies — records
    /// in other currencies are simply not included here.
    var budgetSpent: Double? = nil
    var budgetLimit: Double? = nil
    var budgetCurrency: String? = nil
    /// The owner's chosen watch pages, in their chosen order (page keys).
    /// nil means the default set — Today is always first and never listed.
    var pageOrder: [String]? = nil
    /// Live smart-home state for the wrist (empty until the user adds IoT
    /// devices).
    var sensors: [SensorCatalogEntry] = []
    var actuators: [ActuatorCatalogEntry] = []
    /// The property's emergency plan — shutoff steps + contacts — mirrored to
    /// the wrist for a real incident. Empty until the user fills it in.
    var emergencyContacts: [EmergencyContactEntry] = []
    var emergencySteps: [EmergencyStepEntry] = []
    /// The signed-in user's latest DM conversations (one row per peer), so
    /// the wrist can read the last exchange and dictate a reply. Personal
    /// mail, not a family surface — it rides outsider payloads too (it is
    /// THEIR mail). Empty until the phone's conversation heads load.
    var dmConversations: [DMConversationEntry] = []
    /// The resolved app mood at snapshot time ("morning"/"day"/"night" —
    /// mirrors the App Group key "app.mood.current"), so the wrist can
    /// breathe the same atmosphere. nil (older phone build, signed-out
    /// push) keeps the watch's neutral page tints.
    var mood: String? = nil
    /// The weather stage's sky at push time ([r,g,b] in 0…1, top/bottom of
    /// the gradient — F4), so the wrist wears the same sky the phone
    /// renders. nil = no fresh sky; the mood wash stays the honest fallback.
    var skyTop: [Double]? = nil
    var skyBottom: [Double]? = nil
}

// MARK: Tolerant decoding
//
// Property defaults do NOT make synthesized Codable lenient: a key missing
// from an already-cached payload throws keyNotFound and the WHOLE payload is
// discarded — so every field added to WatchPayload used to wipe the wrist's
// offline cache (and the watch-face complications) until the next phone push.
// This custom decoder defaults every absent key instead (the same guarantee
// PRVIOWidgetSnapshot already makes), so old caches keep decoding as fields
// are added. Declared in an extension so the memberwise initializer survives;
// encoding stays synthesized (`Keys` mirrors the property names 1:1).
extension WatchPayload {
    private enum Keys: String, CodingKey {
        case snapshot, accountId, isFamilyScope, tasks, plants, supplies
        case deliveries, pantry, latitude, longitude, insightTitle, insightBody
        case weatherTemp, weatherSymbol, weatherLo, weatherHi, weatherAdvisory
        case streakDays, budgetSpent, budgetLimit, budgetCurrency, pageOrder
        case sensors, actuators, emergencyContacts, emergencySteps, dmConversations
        case mood, skyTop, skyBottom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        snapshot          = try c.decodeIfPresent(PRVIOWidgetSnapshot.self,   forKey: .snapshot) ?? PRVIOWidgetSnapshot()
        accountId         = try c.decodeIfPresent(String.self,                forKey: .accountId)
        isFamilyScope     = try c.decodeIfPresent(Bool.self,                  forKey: .isFamilyScope) ?? true
        tasks             = try c.decodeIfPresent([TaskCatalogEntry].self,    forKey: .tasks) ?? []
        plants            = try c.decodeIfPresent([PlantCatalogEntry].self,   forKey: .plants) ?? []
        supplies          = try c.decodeIfPresent([SupplyCatalogEntry].self,  forKey: .supplies) ?? []
        deliveries        = try c.decodeIfPresent([DeliveryCatalogEntry].self, forKey: .deliveries) ?? []
        pantry            = try c.decodeIfPresent([PantryCatalogEntry].self,  forKey: .pantry) ?? []
        latitude          = try c.decodeIfPresent(Double.self,                forKey: .latitude)
        longitude         = try c.decodeIfPresent(Double.self,                forKey: .longitude)
        insightTitle      = try c.decodeIfPresent(String.self,                forKey: .insightTitle)
        insightBody       = try c.decodeIfPresent(String.self,                forKey: .insightBody)
        weatherTemp       = try c.decodeIfPresent(Double.self,                forKey: .weatherTemp)
        weatherSymbol     = try c.decodeIfPresent(String.self,                forKey: .weatherSymbol)
        weatherLo         = try c.decodeIfPresent(Double.self,                forKey: .weatherLo)
        weatherHi         = try c.decodeIfPresent(Double.self,                forKey: .weatherHi)
        weatherAdvisory   = try c.decodeIfPresent(String.self,                forKey: .weatherAdvisory)
        streakDays        = try c.decodeIfPresent(Int.self,                   forKey: .streakDays)
        budgetSpent       = try c.decodeIfPresent(Double.self,                forKey: .budgetSpent)
        budgetLimit       = try c.decodeIfPresent(Double.self,                forKey: .budgetLimit)
        budgetCurrency    = try c.decodeIfPresent(String.self,                forKey: .budgetCurrency)
        pageOrder         = try c.decodeIfPresent([String].self,              forKey: .pageOrder)
        sensors           = try c.decodeIfPresent([SensorCatalogEntry].self,  forKey: .sensors) ?? []
        actuators         = try c.decodeIfPresent([ActuatorCatalogEntry].self, forKey: .actuators) ?? []
        emergencyContacts = try c.decodeIfPresent([EmergencyContactEntry].self, forKey: .emergencyContacts) ?? []
        emergencySteps    = try c.decodeIfPresent([EmergencyStepEntry].self,  forKey: .emergencySteps) ?? []
        dmConversations   = try c.decodeIfPresent([DMConversationEntry].self, forKey: .dmConversations) ?? []
        mood              = try c.decodeIfPresent(String.self,                forKey: .mood)
        skyTop            = try c.decodeIfPresent([Double].self,              forKey: .skyTop)
        skyBottom         = try c.decodeIfPresent([Double].self,              forKey: .skyBottom)
    }
}

extension WatchPayload {
    /// A render-safe copy: every id-keyed collection deduplicated (first
    /// occurrence wins). Two ForEach/List rows with the same identity are
    /// undefined behavior that crashes at first render on a real watch —
    /// the "opens and instantly exits" symptom — and because the payload is
    /// CACHED on the wrist, a single poisoned delivery (e.g. written by an
    /// older build, or assembled from imperfect catalogs) reproduces the
    /// crash on EVERY launch until the cache is replaced. `pageOrder` was
    /// already deduped defensively for exactly this reason; this extends the
    /// same guarantee to every listed collection. Matters most on hardware
    /// that can never move past watchOS 10 (Series 4/5), where a
    /// crash-at-launch is permanent until the data changes.
    func sanitizedForRender() -> WatchPayload {
        func deduped<T>(_ items: [T], id: (T) -> UUID) -> [T] {
            var seen = Set<UUID>()
            return items.filter { seen.insert(id($0)).inserted }
        }
        var p = self
        p.tasks             = deduped(tasks)             { $0.id }
        p.plants            = deduped(plants)            { $0.id }
        p.supplies          = deduped(supplies)          { $0.id }
        p.deliveries        = deduped(deliveries)        { $0.id }
        p.pantry            = deduped(pantry)            { $0.id }
        p.sensors           = deduped(sensors)           { $0.id }
        p.actuators         = deduped(actuators)         { $0.id }
        p.emergencyContacts = deduped(emergencyContacts) { $0.id }
        p.emergencySteps    = deduped(emergencySteps)    { $0.id }
        p.dmConversations   = deduped(dmConversations)   { $0.id }
        return p
    }
}

// MARK: - Weather sky snapshot (F4 — app → widgets, and onto the watch payload)
//
// The weather stage's CPU-mirrored gradient at publish time: two [r,g,b]
// triplets (0…1) plus the scheme its luminance calls for. Written by
// WeatherStageEngine whenever the target sky materially changes; read by
// the widget ground at archive time and stamped onto every watch push.
// Freshness is enforced at READ time — the sky moves with the clock, so a
// stale snapshot is worse than the classic fallback.

struct WeatherSkySnapshot: Codable {
    var top: [Double]
    var bottom: [Double]
    /// True when the ground is dark → consumers render light content
    /// (`.dark` color scheme) for AA contrast, matching the mood contract.
    var darkGround: Bool
    var capturedAt: Date
}

extension SharedDataStore {
    private static let weatherSkyKey = "prvio.weather.sky"
    /// 45 min: long enough to bridge widget timeline gaps, short enough
    /// that a noon sky never lingers into the evening.
    private static let weatherSkyTTL: TimeInterval = 2700

    static func writeWeatherSky(_ snapshot: WeatherSkySnapshot) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        ud.set(data, forKey: weatherSkyKey)
    }

    /// The snapshot, only while it is still honest — nil past the TTL or
    /// when the triplets are malformed.
    static func freshWeatherSky(at date: Date = Date()) -> WeatherSkySnapshot? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: weatherSkyKey),
              let snapshot = try? JSONDecoder().decode(WeatherSkySnapshot.self, from: data),
              date.timeIntervalSince(snapshot.capturedAt) <= weatherSkyTTL,
              snapshot.top.count == 3, snapshot.bottom.count == 3 else { return nil }
        return snapshot
    }

    // The owner's CHOSEN backdrop (audit 2026-07-21): gradient endpoints or
    // the photo's measured thirds, published by BackgroundStyle. Unlike the
    // weather sky it carries NO TTL — a static choice stays honest until it
    // is changed, so widgets and the watch never fall back to a palette
    // that disagrees with the phone.
    private static let backdropSkyKey = "prvio.backdrop.sky"

    static func writeBackdropSky(_ snapshot: WeatherSkySnapshot) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        ud.set(data, forKey: backdropSkyKey)
    }

    static func readBackdropSky() -> WeatherSkySnapshot? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: backdropSkyKey),
              let snapshot = try? JSONDecoder().decode(WeatherSkySnapshot.self, from: data),
              snapshot.top.count == 3, snapshot.bottom.count == 3 else { return nil }
        return snapshot
    }
}

// MARK: - Intent catalogs (read by App Intents without Supabase)

struct TaskCatalogEntry: Codable {
    var id: UUID
    var title: String
    var priority: String
    var isCompleted: Bool
    // Optional so catalogs written before this field existed still decode.
    var isOverdue: Bool? = nil
}

struct PlantCatalogEntry: Codable {
    var id: UUID
    var name: String
    var emoji: String
    var needsWatering: Bool
    /// Last computed Plant Health Score (0–100), or nil when not computed yet.
    /// Optional so catalogs written before P6 still decode, and so a plant the
    /// user hasn't scored yet honestly shows no number on the widget/watch.
    var healthScore: Int? = nil
}

struct SupplyCatalogEntry: Codable {
    var id: UUID
    var name: String
    var isCompleted: Bool
}

struct PantryCatalogEntry: Codable {
    var id: UUID
    var name: String
    var quantity: Double
    var unit: String
}

struct DeliveryCatalogEntry: Codable {
    var id: UUID
    var title: String
    var carrier: String?
    /// Raw status ("expected", "out_for_delivery", …) — the watch localizes it.
    var status: String
    var eta: String?
}

// MARK: - Smart-home catalogs (sensors + actuators for the wrist)

/// A sensor reading, flattened for the wrist. Everything is pre-formatted on
/// the phone (which owns the units/thresholds) so the watch just renders.
struct SensorCatalogEntry: Codable {
    var id: UUID
    var name: String
    var icon: String          // SF Symbol for the sensor type
    var displayValue: String  // "21.4 °C" — already formatted
    var zone: String?
    var isAlerting: Bool
    var isCritical: Bool
}

/// A controllable actuator (relay or cover). `commands` is the raw
/// ActuatorCommand vocabulary the phone will execute; the watch never invents
/// a command the actuator doesn't declare, so a wrist tap always maps to a
/// real device write.
struct ActuatorCatalogEntry: Codable {
    var id: UUID
    var name: String
    var kind: String          // "relay" | "cover"
    var isOn: Bool?
    var commands: [String]    // ["on","off"] | ["open","close","stop"]
}

// MARK: - Emergency (SOS on the wrist)
//
// Decoded from the phone's own emergency store, so the wrist shows the SAME
// contacts and shutoff notes the user configured — nothing fabricated. `phone`
// drives a real tel: call straight from the watch.

struct EmergencyContactEntry: Codable {
    var id: UUID
    var name: String
    var role: String
    var phone: String
}

struct EmergencyStepEntry: Codable {
    var id: UUID
    var title: String
    var detail: String
}

// MARK: - DM conversations (the wrist's inbox)
//
// One row per direct-message peer, flattened from the server-side
// conversation heads on the phone. `id` is the PEER'S AUTH USER ID — the
// same durable thread identity DirectMessageService keys on, and exactly
// what a wrist reply targets ("dm:<peer-user-id>" through the pending
// chat-reply queue). Legacy threads whose rows carry no peer id can't be
// replied to by id, so they honestly don't ride to the watch.

struct DMConversationEntry: Codable {
    var id: UUID              // peer auth user id (thread identity)
    var peerName: String
    /// Last message text, nil when it was media or deleted-for-all.
    var lastBody: String? = nil
    /// True when the last message is an attachment (photo/audio/video) —
    /// the watch shows a localized "Attachment" label, never a raw path.
    var isMedia: Bool = false
    /// True when the signed-in user sent the last message ("Me: …").
    var lastIsMine: Bool = false
    var lastAt: Date? = nil
    var unread: Int = 0
}

// MARK: - Work session snapshot (watch app ↔ watch complications)
//
// The wrist's maintenance timer, persisted in the App Group by the watch APP
// and read by the watch WIDGET extension so the face can show the running
// session. Field names must never change: they are the on-disk JSON contract
// under `prvio.watch.session` (previously declared inside WatchStore).

struct WatchWorkSession: Codable, Equatable {
    var taskId: UUID
    var title: String
    var startedAt: Date
    /// Seconds banked from segments that already ran before each pause.
    var accumulated: TimeInterval = 0
    /// Start of the current running segment; nil while paused. Defaulted
    /// from `startedAt` so a session persisted by an older build resumes
    /// running rather than appearing paused.
    var segmentStart: Date? = nil

    var isPaused: Bool { segmentStart == nil && accumulated > 0 }

    /// Live elapsed, pauses excluded. Falls back to `startedAt` for
    /// sessions saved before pause support existed.
    func elapsed(at now: Date) -> TimeInterval {
        if let seg = segmentStart { return accumulated + max(0, now.timeIntervalSince(seg)) }
        if accumulated > 0 { return accumulated }
        return max(0, now.timeIntervalSince(startedAt))
    }

    /// "1:20:05" past an hour, else "20:05" — the frozen readout the
    /// complication shows while paused (running state uses live timer text).
    func clockText(at now: Date) -> String {
        let total = Int(max(0, elapsed(at: now)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Watch action relay (widget extension → watch app → phone)
//
// Interactive complications run in the watch WIDGET extension, which cannot
// touch WCSession. Their actions queue here (App Group), and the watch APP
// forwards them to the phone on its next activation. Lives in this file
// because it must compile into both watch targets.

enum WatchActionRelay {
    private static let key = "prvio.watch.pendingRelay"

    static func append(action: String, id: String) {
        guard let data = try? JSONEncoder().encode(["action": action, "id": id]),
              let json = String(data: data, encoding: .utf8) else { return }
        SharedDataStore.coordinateQueue("watchRelay", legacyKey: nil) { queue in
            queue.append(json)
        }
    }

    static func drain() -> [[String: String]] {
        var drained = SharedDataStore.coordinateQueue("watchRelay", legacyKey: nil) { (queue: inout [String]) -> [[String: String]] in
            let entries = queue.compactMap { json -> [String: String]? in
                json.data(using: .utf8)
                    .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            }
            queue.removeAll()
            return entries
        } ?? []
        // One-time drain of actions a pre-coordination build queued in
        // UserDefaults (dictionary elements — the generic drain can't).
        if let ud = UserDefaults(suiteName: SharedDataStore.suiteName),
           let legacy = ud.array(forKey: key) as? [[String: String]], !legacy.isEmpty {
            ud.removeObject(forKey: key)
            drained = legacy + drained
        }
        return drained
    }
}

// MARK: - Store

enum SharedDataStore {
    static let suiteName = "group.com.prvio.app"

    private static let snapshotKey         = "prvio.widget.snapshot"
    private static let taskCatalogKey      = "prvio.catalog.tasks"
    private static let plantCatalogKey     = "prvio.catalog.plants"
    private static let supplyCatalogKey    = "prvio.catalog.supplies"
    private static let pendingWateringsKey = "prvio.pending.waterings"
    private static let pendingCompletionsKey = "prvio.pending.completions"
    private static let pendingSupplyChecksKey = "prvio.pending.supplyChecks"
    private static let accountStampKey     = "prvio.watch.accountStamp"

    // MARK: Account stamp (which account/role the current snapshot belongs to)
    //
    // Stored so `currentWatchPayload()` can tag every push with the owning
    // account id and role scope — the watch wipes itself when it receives a
    // payload for a different (or no) account, so a logged-out or switched
    // account never keeps showing the previous owner's glance data.

    static func writeAccountStamp(userId: String?, isFamily: Bool) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        let stamp: [String: Any] = ["userId": userId as Any, "isFamily": isFamily]
        ud.set(stamp, forKey: accountStampKey)
    }

    static func readAccountStamp() -> (userId: String?, isFamily: Bool) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let stamp = ud.dictionary(forKey: accountStampKey) else { return (nil, true) }
        return (stamp["userId"] as? String, stamp["isFamily"] as? Bool ?? true)
    }

    /// Wipe every glanceable surface the watch mirrors. Called on logout and on
    /// account switch so the App Group holds nothing from the previous account;
    /// a cleared payload is then pushed so the watch's own cache clears too.
    static func clearWatchData() {
        if let ud = UserDefaults(suiteName: suiteName) {
            for key in [snapshotKey, taskCatalogKey, plantCatalogKey, supplyCatalogKey,
                        deliveryCatalogKey, pantryCatalogKey, sensorCatalogKey,
                        actuatorCatalogKey, dmCatalogKey, watchExtrasKey, accountStampKey] {
                ud.removeObject(forKey: key)
            }
        }
        // The emergency plan is mirrored from UserDefaults.standard.
        UserDefaults.standard.removeObject(forKey: "prvio.emergency")
        UserDefaults.standard.removeObject(forKey: "prvio.emergency.notes")
    }

    // MARK: Widget snapshot

    static func write(_ snapshot: PRVIOWidgetSnapshot) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        ud.set(data, forKey: snapshotKey)
    }

    static func read() -> PRVIOWidgetSnapshot? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(PRVIOWidgetSnapshot.self, from: data)
    }

    // MARK: Task catalog

    static func writeTaskCatalog(_ tasks: [TaskCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(tasks) else { return }
        ud.set(data, forKey: taskCatalogKey)
    }

    static func readTaskCatalog() -> [TaskCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: taskCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([TaskCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Plant catalog

    static func writePlantCatalog(_ plants: [PlantCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(plants) else { return }
        ud.set(data, forKey: plantCatalogKey)
    }

    static func readPlantCatalog() -> [PlantCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: plantCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([PlantCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Pending actions (written by App Intents, processed by main app on foreground)
    //
    // Every pending queue used to be a UserDefaults array, but UserDefaults
    // read-modify-write is not atomic across processes: a widget tap (in the
    // extension process) racing the app's foreground drain could silently
    // drop actions. Each queue is now a JSON file in the App Group container
    // and every mutation runs inside NSFileCoordinator's writing block — the
    // system serializes coordinated access across all group processes. The
    // old UserDefaults key is drained into the file on first touch so no
    // action written by a previous build is lost.

    private static var queuesDirectory: URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: suiteName) else { return nil }
        let dir = container.appendingPathComponent("Queues", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            // Queue contents are opaque action ids — never sensitive — and
            // they must stay writable while the device is locked (watch
            // commands and Live Activity buttons arrive exactly then).
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.none],
                                                   ofItemAtPath: dir.path)
        }
        return dir
    }

    /// Atomically read-modify-write one queue. `body` mutates the queue in
    /// place; the file is rewritten only when it actually changed (and
    /// removed when it empties, so the directory never accumulates husks).
    ///
    /// Cross-process exclusion is a kernel `flock` on a stable sidecar
    /// lockfile — NOT `NSFileCoordinator`. The coordinator arbitrates through
    /// filecoordinationd, and a peer process suspended mid-claim (a widget /
    /// intent extension parked by the system) leaves every other caller
    /// blocked indefinitely — the build-1115 field crash: the app's main
    /// thread stuck in `coordinateWritingItemAtURL` while backgrounding,
    /// until UIKit's snapshot machinery aborted the process. A flock has no
    /// daemon and no callbacks: the kernel releases it the moment its holder
    /// exits, and hold times here are single-digit milliseconds (read +
    /// mutate + write of a tiny JSON array). The lock rides the sidecar, not
    /// the data file, because the atomic replace below swaps the data file's
    /// inode — a lock on the old inode would no longer exclude anyone.
    @discardableResult
    fileprivate static func coordinateQueue<T>(_ name: String,
                                           legacyKey: String?,
                                           _ body: (inout [String]) -> T) -> T? {
        guard let dir = queuesDirectory else { return nil }
        let url = dir.appendingPathComponent(name + ".json")
        let lockURL = dir.appendingPathComponent(name + ".lock")

        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }

        var queue = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        var dirty = false
        if let legacyKey, let ud = UserDefaults(suiteName: suiteName),
           let legacy = ud.array(forKey: legacyKey) as? [String], !legacy.isEmpty {
            queue = legacy + queue
            ud.removeObject(forKey: legacyKey)
            dirty = true
        }
        let before = queue
        let result = body(&queue)
        if queue != before { dirty = true }
        if dirty {
            if queue.isEmpty {
                try? FileManager.default.removeItem(at: url)
            } else if let data = try? JSONEncoder().encode(queue) {
                try? data.write(to: url, options: [.atomic, .noFileProtection])
            }
        }
        return result
    }

    /// Append once (the queue is idempotent — a second tap on the same
    /// button must not produce a second action).
    private static func coordinatedAppendUnique(_ name: String, legacyKey: String?, _ value: String) {
        coordinateQueue(name, legacyKey: legacyKey) { queue in
            if !queue.contains(value) { queue.append(value) }
        }
    }

    private static func coordinatedPop(_ name: String, legacyKey: String?) -> [String] {
        coordinateQueue(name, legacyKey: legacyKey) { queue in
            let drained = queue
            queue.removeAll()
            return drained
        } ?? []
    }

    // MARK: Watch action idempotency (wrist → phone)
    //
    // `transferUserInfo` guarantees delivery but not exactly-once processing:
    // a transfer can be handed to the delegate again after an ambiguous
    // hand-off (relaunch mid-callback, session re-activation), and for the
    // non-idempotent actions — alertFamily, sendMessage/sendDM, createTask,
    // consumePantry — a replay means a duplicate family alert, chat message,
    // task or pantry decrement. The watch stamps each transfer with a fresh
    // `actionId`; this ledger (a capped, NSFileCoordinator-serialized queue
    // file like every other pending queue) remembers the processed ids so a
    // re-delivered transfer is recognized and dropped. Payloads from older
    // watch builds carry no id and process exactly as before.

    private static let processedWatchActionsCap = 200

    /// Records a wrist-generated action id. Returns `false` when the id was
    /// already processed (duplicate delivery — the caller must ignore it).
    /// Unavailable container (no App Group) degrades to processing normally.
    static func registerProcessedWatchAction(_ actionId: String) -> Bool {
        coordinateQueue("processedWatchActions", legacyKey: nil) { queue -> Bool in
            guard !queue.contains(actionId) else { return false }
            queue.append(actionId)
            if queue.count > processedWatchActionsCap {
                queue.removeFirst(queue.count - processedWatchActionsCap)
            }
            return true
        } ?? true
    }

    static func appendPendingWatering(_ plantId: UUID) {
        coordinatedAppendUnique("waterings", legacyKey: pendingWateringsKey, plantId.uuidString)
    }

    static func popPendingWaterings() -> [UUID] {
        coordinatedPop("waterings", legacyKey: pendingWateringsKey).compactMap { UUID(uuidString: $0) }
    }

    /// "Mark returned" tapped on a loan-reminder notification (IMG_8612) —
    /// the same park-and-drain contract every other notification action uses.
    static func appendPendingLoanReturn(_ itemId: UUID) {
        coordinatedAppendUnique("loanReturns", legacyKey: nil, itemId.uuidString)
    }

    static func popPendingLoanReturns() -> [UUID] {
        coordinatedPop("loanReturns", legacyKey: nil).compactMap { UUID(uuidString: $0) }
    }

    // MARK: Supply catalog

    static func writeSupplyCatalog(_ items: [SupplyCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: supplyCatalogKey)
    }

    static func readSupplyCatalog() -> [SupplyCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: supplyCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([SupplyCatalogEntry].self, from: data)) ?? []
    }

    // MARK: Pantry catalog

    private static let pantryCatalogKey = "prvio.catalog.pantry"
    private static let pendingPantryConsumesKey = "prvio.pending.pantryConsumes"

    static func writePantryCatalog(_ items: [PantryCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: pantryCatalogKey)
    }

    static func readPantryCatalog() -> [PantryCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: pantryCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([PantryCatalogEntry].self, from: data)) ?? []
    }

    /// Each element is one "consume 1" tap — duplicates are meaningful,
    /// so this appends unconditionally (unlike the idempotent check queues).
    static func appendPendingPantryConsume(_ itemId: UUID) {
        coordinateQueue("pantryConsumes", legacyKey: pendingPantryConsumesKey) { queue in
            queue.append(itemId.uuidString)
        }
    }

    static func popPendingPantryConsumes() -> [UUID] {
        coordinatedPop("pantryConsumes", legacyKey: pendingPantryConsumesKey)
            .compactMap { UUID(uuidString: $0) }
    }

    static func applyLocalPantryConsume(_ id: UUID) {
        var catalog = readPantryCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].quantity = max(0, ((catalog[idx].quantity - 1) * 10).rounded() / 10)
        writePantryCatalog(catalog)
    }

    // MARK: Delivery catalog

    private static let deliveryCatalogKey = "prvio.catalog.deliveries"

    static func writeDeliveryCatalog(_ items: [DeliveryCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: deliveryCatalogKey)
    }

    static func readDeliveryCatalog() -> [DeliveryCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: deliveryCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([DeliveryCatalogEntry].self, from: data)) ?? []
    }

    // MARK: DM conversation catalog (written by DirectMessageService)

    private static let dmCatalogKey = "prvio.catalog.dms"

    static func writeDMCatalog(_ items: [DMConversationEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: dmCatalogKey)
    }

    static func readDMCatalog() -> [DMConversationEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: dmCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([DMConversationEntry].self, from: data)) ?? []
    }

    // MARK: Smart-home catalogs + wrist commands

    private static let sensorCatalogKey   = "prvio.catalog.sensors"
    private static let actuatorCatalogKey = "prvio.catalog.actuators"
    private static let pendingIoTKey      = "prvio.watch.pendingIoT"

    static func writeSensorCatalog(_ items: [SensorCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: sensorCatalogKey)
    }
    static func readSensorCatalog() -> [SensorCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: sensorCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([SensorCatalogEntry].self, from: data)) ?? []
    }
    static func writeActuatorCatalog(_ items: [ActuatorCatalogEntry]) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(items) else { return }
        ud.set(data, forKey: actuatorCatalogKey)
    }
    static func readActuatorCatalog() -> [ActuatorCatalogEntry] {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: actuatorCatalogKey) else { return [] }
        return (try? JSONDecoder().decode([ActuatorCatalogEntry].self, from: data)) ?? []
    }

    /// A wrist-issued actuator command, parked for the app to execute on its
    /// next active beat. `transferUserInfo` already guaranteed delivery to the
    /// phone; this survives the phone being backgrounded when it arrives, so
    /// nothing is lost if the garage command lands while the app is closed.
    /// Rides the same NSFileCoordinator-serialized queue file as every other
    /// pending queue — the raw UserDefaults read-modify-write it used before
    /// could drop a command when two processes raced. Repeated commands are
    /// meaningful (open, stop, open again), so this appends unconditionally.
    static func appendPendingIoTCommand(actuatorId: UUID, command: String) {
        coordinateQueue("iotCommands", legacyKey: pendingIoTKey) { queue in
            queue.append("\(actuatorId.uuidString)|\(command)")
        }
    }
    static func drainPendingIoTCommands() -> [(actuatorId: UUID, command: String)] {
        coordinatedPop("iotCommands", legacyKey: pendingIoTKey).compactMap { entry in
            let parts = entry.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let id = UUID(uuidString: parts[0]) else { return nil }
            return (id, parts[1])
        }
    }

    /// Optimistic relay echo so a wrist toggle feels instant before the phone
    /// confirms the real device write — mirrors applyLocalTaskCompletion.
    static func applyLocalActuatorState(id: UUID, isOn: Bool?) {
        var cat = readActuatorCatalog()
        guard let i = cat.firstIndex(where: { $0.id == id }) else { return }
        cat[i].isOn = isOn
        writeActuatorCatalog(cat)
    }

    // MARK: Emergency plan (read from the phone's own store, called on-phone
    // when the payload is built — the watch just receives the result).

    static func readEmergencyContacts() -> [EmergencyContactEntry] {
        guard let d = UserDefaults.standard.data(forKey: "prvio.emergency") else { return [] }
        return (try? JSONDecoder().decode([EmergencyContactEntry].self, from: d)) ?? []
    }
    static func readEmergencySteps() -> [EmergencyStepEntry] {
        guard let d = UserDefaults.standard.data(forKey: "prvio.emergency.notes") else { return [] }
        return (try? JSONDecoder().decode([EmergencyStepEntry].self, from: d)) ?? []
    }

    /// A wrist-triggered "start emergency mode" — parked because ActivityKit
    /// only lets the app START a Live Activity in the foreground. Drained by
    /// MainTabView on the next active beat.
    private static let pendingEmergencyKey = "prvio.watch.pendingEmergency"
    static func setPendingEmergencyStart() {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: pendingEmergencyKey)
    }
    static func consumePendingEmergencyStart() -> Bool {
        guard let ud = UserDefaults(suiteName: suiteName),
              ud.bool(forKey: pendingEmergencyKey) else { return false }
        ud.removeObject(forKey: pendingEmergencyKey)
        return true
    }

    /// Deliveries marked received from the Live Activity island — drained into
    /// DeliveryService.markDelivered on the app's next foreground beat.
    /// Idempotent: a second tap on the same delivery must not re-mark it.
    static func appendPendingDeliveryReceived(_ deliveryId: UUID) {
        coordinatedAppendUnique("deliveryReceived", legacyKey: nil, deliveryId.uuidString)
    }

    static func popPendingDeliveryReceived() -> [UUID] {
        coordinatedPop("deliveryReceived", legacyKey: nil).compactMap { UUID(uuidString: $0) }
    }

    /// Optimistic echo for a wrist "package received" tap — the shared
    /// catalog and snapshot flip to delivered immediately, and the pending
    /// queue reconciles the real DeliveryService write on the next beat.
    static func applyLocalDeliveryReceived(_ id: UUID) {
        var catalog = readDeliveryCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }),
              catalog[idx].status != "delivered" else { return }
        catalog[idx].status = "delivered"
        catalog[idx].eta = nil
        writeDeliveryCatalog(catalog)
        if var snap = read() {
            snap.activeDeliveryCount = catalog
                .filter { $0.status == "expected" || $0.status == "out_for_delivery" }.count
            write(snap)
        }
    }

    // MARK: Pantry → shopping list (wrist "put it on the list")
    //
    // Pantry item ids the wrist asked to re-buy. Drained on the app's next
    // active beat into SupplyService.addItem — the same real insert the
    // supplies screen performs. Idempotent: asking twice for the same jar
    // before the drain must not produce two list rows.

    static func appendPendingPantryToList(_ itemId: UUID) {
        coordinatedAppendUnique("pantryToList", legacyKey: nil, itemId.uuidString)
    }

    static func popPendingPantryToList() -> [UUID] {
        coordinatedPop("pantryToList", legacyKey: nil).compactMap { UUID(uuidString: $0) }
    }

    // MARK: Watch extras (coordinates + top insight, set by writeWidgetSnapshot)

    private static let watchExtrasKey = "prvio.watch.extras"

    struct WatchExtras: Codable {
        var latitude: Double?
        var longitude: Double?
        var insightTitle: String?
        var insightBody: String?
        var weatherTemp: Double? = nil
        var weatherSymbol: String? = nil
        var weatherLo: Double? = nil
        var weatherHi: Double? = nil
        var weatherAdvisory: String? = nil
        var streakDays: Int? = nil
        var budgetSpent: Double? = nil
        var budgetLimit: Double? = nil
        var budgetCurrency: String? = nil
    }

    static func writeWatchExtras(_ extras: WatchExtras) {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = try? JSONEncoder().encode(extras) else { return }
        ud.set(data, forKey: watchExtrasKey)
    }

    static func readWatchExtras() -> WatchExtras {
        guard let ud = UserDefaults(suiteName: suiteName),
              let data = ud.data(forKey: watchExtrasKey),
              let extras = try? JSONDecoder().decode(WatchExtras.self, from: data) else {
            return WatchExtras()
        }
        return extras
    }

    /// The watch payload assembled from the store alone — used to answer a
    /// wrist action instantly (after the local mutations) without needing the
    /// app's services to be alive.
    static let watchTaskLimit = 60
    static let watchListLimit = 40

    /// Open entries first (in catalog order), then the most recent closed
    /// ones, capped — the watch shows what's actionable.
    static func watchSlice<T>(_ items: [T], isOpen: (T) -> Bool, limit: Int) -> [T] {
        let open = items.filter(isOpen)
        let closed = items.filter { !isOpen($0) }
        return Array((open + closed).prefix(limit))
    }

    static func currentWatchPayload() -> WatchPayload? {
        guard let snapshot = read() else { return nil }
        let extras = readWatchExtras()
        let stamp = readAccountStamp()
        return WatchPayload(snapshot: snapshot,
                            accountId: stamp.userId,
                            isFamilyScope: stamp.isFamily,
                            // Bounded for the wrist: WatchConnectivity rejects an
                            // oversized applicationContext outright, and the full
                            // catalogs (up to 500 tasks, every supply ever bought)
                            // grew past it — the push failed and the watch sat on
                            // stale or no data. Open items lead; widgets and
                            // intents keep reading the full catalogs.
                            tasks: watchSlice(readTaskCatalog(), isOpen: { !$0.isCompleted },
                                              limit: watchTaskLimit),
                            plants: Array(readPlantCatalog().prefix(watchListLimit)),
                            supplies: watchSlice(readSupplyCatalog(), isOpen: { !$0.isCompleted },
                                                 limit: watchListLimit),
                            deliveries: readDeliveryCatalog(),
                            pantry: readPantryCatalog(),
                            latitude: extras.latitude,
                            longitude: extras.longitude,
                            insightTitle: extras.insightTitle,
                            insightBody: extras.insightBody,
                            weatherTemp: extras.weatherTemp,
                            weatherSymbol: extras.weatherSymbol,
                            weatherLo: extras.weatherLo,
                            weatherHi: extras.weatherHi,
                            weatherAdvisory: extras.weatherAdvisory,
                            streakDays: extras.streakDays,
                            budgetSpent: extras.budgetSpent,
                            budgetLimit: extras.budgetLimit,
                            budgetCurrency: extras.budgetCurrency,
                            // Family-only wrist surfaces: an outsider's watch keeps to
                            // Today + their tasks; smart-home controls and the family's
                            // emergency plan never ride an outsider payload.
                            pageOrder: stamp.isFamily ? visibleWatchPages() : ["tasks"],
                            sensors: stamp.isFamily ? readSensorCatalog() : [],
                            actuators: stamp.isFamily ? readActuatorCatalog() : [],
                            emergencyContacts: stamp.isFamily ? readEmergencyContacts() : [],
                            emergencySteps: stamp.isFamily ? readEmergencySteps() : [],
                            // Personal mail: the DM catalog is written from the
                            // signed-in user's own conversation heads, so it is
                            // theirs on every role — family or outsider.
                            dmConversations: readDMCatalog(),
                            // The living backdrop's resolved mood, so the wrist
                            // breathes the same atmosphere as the phone.
                            mood: UserDefaults(suiteName: suiteName)?.string(forKey: "app.mood.current"),
                            // The owner's chosen backdrop first (no TTL — a
                            // static choice stays honest until changed); the
                            // weather sky remains only as the legacy fallback.
                            skyTop: (readBackdropSky() ?? freshWeatherSky())?.top,
                            skyBottom: (readBackdropSky() ?? freshWeatherSky())?.bottom)
    }

    // MARK: Watch page personalization (chosen on the iPhone)

    /// Every page the watch can show, in the default order. Today is not
    /// listed — it is always first and can't be hidden.
    static let allWatchPages = ["tasks", "plants", "shopping", "pantry", "deliveries", "map"]

    private static let watchPageOrderKey  = "prvio.watch.pageOrder"
    private static let watchHiddenPagesKey = "prvio.watch.hiddenPages"

    static func writeWatchPagePrefs(order: [String], hidden: [String]) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        ud.set(order, forKey: watchPageOrderKey)
        ud.set(hidden, forKey: watchHiddenPagesKey)
    }

    /// The stored order, sanitized: unknown keys dropped, pages added in a
    /// later version appended — so an old preference never hides new pages.
    static func readWatchPagePrefs() -> (order: [String], hidden: Set<String>) {
        guard let ud = UserDefaults(suiteName: suiteName) else {
            return (allWatchPages, [])
        }
        let stored = (ud.array(forKey: watchPageOrderKey) as? [String]) ?? []
        // Dedupe while filtering: a duplicated key in the stored order
        // becomes two ForEach rows with the same identity on the watch —
        // undefined behavior that can crash the app at first render.
        var seen = Set<String>()
        var order = stored.filter { allWatchPages.contains($0) && seen.insert($0).inserted }
        order += allWatchPages.filter { !seen.contains($0) }
        let hidden = Set((ud.array(forKey: watchHiddenPagesKey) as? [String]) ?? [])
            .intersection(allWatchPages)
        return (order, hidden)
    }

    /// The pages the watch should show, in order — what rides the payload.
    static func visibleWatchPages() -> [String] {
        let prefs = readWatchPagePrefs()
        return prefs.order.filter { !prefs.hidden.contains($0) }
    }

    // MARK: House streak (consecutive all-clear days)

    private static let streakCountKey = "prvio.streak.count"
    private static let streakDayKey   = "prvio.streak.lastDay"

    /// Rolls the streak forward from today's observed state and returns the
    /// current count. All-clear extends (once per day); a bad day resets to
    /// zero. A day the app never opened breaks the chain honestly — we only
    /// count days we actually verified.
    static func updateHouseStreak(allClear: Bool) -> Int {
        guard let ud = UserDefaults(suiteName: suiteName) else { return 0 }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Date().addingTimeInterval(-86_400))

        let lastDay = ud.string(forKey: streakDayKey)
        var count = ud.integer(forKey: streakCountKey)

        if allClear {
            if lastDay == today {
                count = max(count, 1)
            } else if lastDay == yesterday {
                count += 1
            } else {
                count = 1
            }
        } else {
            count = 0
        }
        ud.set(count, forKey: streakCountKey)
        ud.set(today, forKey: streakDayKey)
        return count
    }

    /// Read-only view of the streak — for screens that report it without
    /// rolling the day forward (updateHouseStreak stays the only writer).
    static func currentHouseStreak() -> Int {
        UserDefaults(suiteName: suiteName)?.integer(forKey: streakCountKey) ?? 0
    }

    // MARK: Pending work session (watch → phone Live Activity)
    //
    // The watch's session start/end land here because Live Activities can
    // only be requested while the app is in the foreground — the phone
    // mirrors the wrist's timer the next time it's active (or instantly
    // when it already is). startedAt rides along so the Dynamic Island
    // shows the TRUE elapsed time, not the time since the mirror appeared.

    private static let pendingSessionKey = "prvio.pending.session"

    /// Where the WATCH app persists its live work session (WatchWorkSession
    /// JSON). Public so the watch widget extension renders the same session
    /// the watch app is timing. Falls back to .standard exactly like the
    /// watch app's own store does (simulator without group entitlements).
    static let watchSessionKey = "prvio.watch.session"

    static func readWatchWorkSession() -> WatchWorkSession? {
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        guard let data = defaults.data(forKey: watchSessionKey) else { return nil }
        return try? JSONDecoder().decode(WatchWorkSession.self, from: data)
    }

    static func writePendingSessionStart(taskId: UUID, title: String, startedAt: Date) {
        writePendingSessionEvent(["id": taskId.uuidString, "title": title,
                                  "startedAt": String(startedAt.timeIntervalSince1970)])
    }

    static func writePendingSessionEnd() {
        writePendingSessionEvent(["end": "1"])
    }

    /// The session slot rides the coordinated queue as a single JSON-encoded
    /// element — the newest event replaces whatever was waiting, as before.
    private static func writePendingSessionEvent(_ event: [String: String]) {
        guard let data = try? JSONEncoder().encode(event),
              let json = String(data: data, encoding: .utf8) else { return }
        coordinateQueue("session", legacyKey: nil) { queue in
            queue = [json]
        }
        // The slot moved out of UserDefaults — clear any event an older
        // build left there so it can't resurrect after this one is consumed.
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: pendingSessionKey)
    }

    /// nil = nothing pending; (nil) start = the session should END.
    static func consumePendingSessionEvent() -> (start: (taskId: UUID, title: String, startedAt: Date)?, isEnd: Bool)? {
        var event: [String: String]?
        coordinateQueue("session", legacyKey: nil) { queue in
            if let json = queue.first, let data = json.data(using: .utf8) {
                event = try? JSONDecoder().decode([String: String].self, from: data)
            }
            queue.removeAll()
        }
        // One-time drain of a slot written by a pre-coordination build.
        if event == nil, let ud = UserDefaults(suiteName: suiteName),
           let legacy = ud.dictionary(forKey: pendingSessionKey) as? [String: String] {
            ud.removeObject(forKey: pendingSessionKey)
            event = legacy
        }
        guard let dict = event else { return nil }
        if dict["end"] == "1" { return (start: nil, isEnd: true) }
        guard let idStr = dict["id"], let id = UUID(uuidString: idStr),
              let title = dict["title"],
              let ts = dict["startedAt"].flatMap(Double.init) else { return nil }
        return (start: (taskId: id, title: title, startedAt: Date(timeIntervalSince1970: ts)), isEnd: false)
    }

    static func appendPendingSupplyCheck(_ itemId: UUID) {
        coordinatedAppendUnique("supplyChecks", legacyKey: pendingSupplyChecksKey, itemId.uuidString)
    }

    static func popPendingSupplyChecks() -> [UUID] {
        coordinatedPop("supplyChecks", legacyKey: pendingSupplyChecksKey)
            .compactMap { UUID(uuidString: $0) }
    }

    // MARK: App context for in-app intents (primary property + display name)

    private static let contextPropertyIdKey = "prvio.context.propertyId"
    private static let contextMyNameKey     = "prvio.context.myName"

    static func setContext(propertyId: UUID?, myName: String?) {
        guard let ud = UserDefaults(suiteName: suiteName) else { return }
        ud.set(propertyId?.uuidString, forKey: contextPropertyIdKey)
        ud.set(myName, forKey: contextMyNameKey)
    }

    static func contextPropertyId() -> UUID? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let s = ud.string(forKey: contextPropertyIdKey) else { return nil }
        return UUID(uuidString: s)
    }

    static func contextMyName() -> String? {
        UserDefaults(suiteName: suiteName)?.string(forKey: contextMyNameKey)
    }

    // MARK: Watch-dictated tasks (watch → phone → Supabase on next beat)

    private static let pendingWatchTasksKey = "prvio.pending.watchTasks"

    static func appendPendingWatchTask(_ title: String) {
        coordinateQueue("watchTasks", legacyKey: pendingWatchTasksKey) { queue in
            queue.append(title)
        }
    }

    static func popPendingWatchTasks() -> [String] {
        coordinatedPop("watchTasks", legacyKey: pendingWatchTasksKey)
    }

    // MARK: Chat replies typed on a notification (delegate → app → Supabase)

    private static let pendingChatRepliesKey = "prvio.pending.chatReplies"
    /// Separates the conversation target from the text inside a queue entry —
    /// the ASCII unit separator can't be typed on a keyboard.
    private static let chatReplyTargetSeparator: Character = "\u{1F}"

    /// A reply typed on a notification, with WHERE it belongs: "group" for
    /// the household chat, "dm:<peer-user-id>" for a direct thread,
    /// "grp:<chat-group-id>" for a community sub-group. Replies used to be
    /// text-only and every one of them landed in the group chat — answering
    /// a DM push delivered the message to the whole family.
    struct PendingChatReply {
        let target: String
        let text: String
    }

    /// Queue entry format: `<target>\u{1F}<text>`; the bare text (no
    /// separator) is the legacy household-chat form and still decodes.
    static func appendPendingChatReply(_ text: String, target: String = "group") {
        let entry = target == "group" ? text : "\(target)\(chatReplyTargetSeparator)\(text)"
        coordinateQueue("chatReplies", legacyKey: pendingChatRepliesKey) { queue in
            queue.append(entry)
        }
    }

    static func popPendingChatReplies() -> [PendingChatReply] {
        coordinatedPop("chatReplies", legacyKey: pendingChatRepliesKey).map { raw in
            // Bare strings (legacy queue entries, watch replies) are group chat.
            guard let sep = raw.firstIndex(of: chatReplyTargetSeparator) else {
                return PendingChatReply(target: "group", text: raw)
            }
            return PendingChatReply(target: String(raw[..<sep]),
                                    text: String(raw[raw.index(after: sep)...]))
        }
    }

    // MARK: Control Center hand-off (control tap → app navigation)
    //
    // Control Center intents run in the widget-extension process. The
    // OpenURLIntent chain they return has proven flaky across iOS versions
    // (app opens but the URL never arrives, or nothing opens on cold start),
    // so the tapped destination is ALSO parked here and consumed by the app
    // on its next activation — the same App Group hand-off the widget
    // buttons rely on, which does work.

    private static let controlPathKey = "prvio.intent.controlPath"

    static func setControlPath(_ path: String) {
        UserDefaults(suiteName: suiteName)?.set(path, forKey: controlPathKey)
    }

    static func consumeControlPath() -> String? {
        guard let ud = UserDefaults(suiteName: suiteName),
              let path = ud.string(forKey: controlPathKey) else { return nil }
        ud.removeObject(forKey: controlPathKey)
        return path
    }

    // MARK: Intent flags (widget/Shortcuts process → app process)
    //
    // Written from whichever process runs the App Intent. The app-group suite is
    // the only store both processes can see — flags written to .standard from
    // the widget extension were invisible to the app (the old bug: "New Task"
    // opened the app but never the form).

    static func setIntentFlag(_ key: String) {
        UserDefaults(suiteName: suiteName)?.set(true, forKey: key)
    }

    static func consumeIntentFlag(_ key: String) -> Bool {
        var flagged = false
        if let ud = UserDefaults(suiteName: suiteName), ud.bool(forKey: key) {
            ud.removeObject(forKey: key); flagged = true
        }
        // Legacy location (intent ran in the app process before this migration).
        if UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.removeObject(forKey: key); flagged = true
        }
        return flagged
    }

    // MARK: Instant widget feedback (applied by App Intents in the extension)
    //
    // Pending actions are only reconciled with Supabase when the app next
    // foregrounds — without these local mutations a widget button tap would
    // visibly do nothing.

    static func applyLocalTaskCompletion(_ id: UUID) {
        var catalog = readTaskCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].isCompleted = true
        catalog[idx].isOverdue = false
        writeTaskCatalog(catalog)
        if var snap = read() {
            snap.openTaskCount = catalog.filter { !$0.isCompleted }.count
            snap.overdueTaskCount = catalog.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if snap.criticalTaskTitle == catalog[idx].title { snap.criticalTaskTitle = nil }
            write(snap)
        }
    }

    static func applyLocalWatering(_ id: UUID) {
        var catalog = readPlantCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].needsWatering = false
        writePlantCatalog(catalog)
        if var snap = read() {
            let needing = catalog.filter { $0.needsWatering }
            snap.plantsNeedingWater = needing.count
            snap.plantNames = Array(needing.prefix(3).map(\.name))
            write(snap)
        }
    }

    static func applyLocalSupplyCheck(_ id: UUID) {
        var catalog = readSupplyCatalog()
        guard let idx = catalog.firstIndex(where: { $0.id == id }) else { return }
        catalog[idx].isCompleted = true
        writeSupplyCatalog(catalog)
        if var snap = read() {
            snap.pendingSupplyCount = catalog.filter { !$0.isCompleted }.count
            write(snap)
        }
    }

    static func appendPendingCompletion(_ taskId: UUID) {
        coordinatedAppendUnique("completions", legacyKey: pendingCompletionsKey, taskId.uuidString)
    }

    static func popPendingCompletions() -> [UUID] {
        coordinatedPop("completions", legacyKey: pendingCompletionsKey)
            .compactMap { UUID(uuidString: $0) }
    }

    // MARK: Chat mutation journal (failed pin/mark/reaction/edit/delete)

    /// Encoded `ChatMutationJournal` entries — recorded by the catch blocks
    /// that used to lose the intent, replayed on the next foreground beat.
    static func appendPendingChatMutation(_ json: String) {
        coordinatedAppendUnique("chatMutations", legacyKey: nil, json)
    }

    static func popPendingChatMutations() -> [String] {
        coordinatedPop("chatMutations", legacyKey: nil)
    }

    // MARK: - Pending expenses (Apple Pay → Shortcuts "Transaction" automation)

    /// One queued expense from `LogExpenseIntent`. The embedded `id` keeps two
    /// identical taps (same shop, same amount, same day) distinct in the
    /// unique-append store.
    struct PendingExpense: Codable {
        let id: UUID
        let merchant: String
        let amount: Double
        let card: String?
        let note: String?
        let date: String        // "yyyy-MM-dd"
        /// ISO code the card was actually charged in (IMG_9288 — lei taps
        /// were landing as euros). Optional: entries queued by older builds
        /// decode as nil and fall back to the preferred currency.
        var currency: String? = nil
    }

    static func appendPendingExpense(_ expense: PendingExpense) {
        guard let data = try? JSONEncoder().encode(expense),
              let json = String(data: data, encoding: .utf8) else { return }
        coordinatedAppendUnique("expenses", legacyKey: nil, json)
    }

    /// NON-DESTRUCTIVE read: the queue keeps every expense until it actually
    /// reaches the ledger (`removePendingExpenses`). The destructive pop this
    /// replaces is why card payments silently never appeared — a cold launch
    /// reaches `.active` before the property is resolved, the drain popped the
    /// queue anyway, found no property to write to, and the payments were gone
    /// for good. The same trap swallowed any insert that failed offline.
    static func peekPendingExpenses() -> [PendingExpense] {
        (coordinateQueue("expenses", legacyKey: nil) { $0 } ?? [])
            .compactMap(decodePendingExpense)
    }

    /// Drops the expenses that landed — plus any entry that no longer decodes,
    /// which would otherwise be retried on every foreground forever.
    static func removePendingExpenses(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        coordinateQueue("expenses", legacyKey: nil) { queue in
            queue.removeAll { json in
                guard let expense = decodePendingExpense(json) else { return true }
                return ids.contains(expense.id)
            }
        }
    }

    private static func decodePendingExpense(_ json: String) -> PendingExpense? {
        json.data(using: .utf8).flatMap {
            try? JSONDecoder().decode(PendingExpense.self, from: $0)
        }
    }
}
