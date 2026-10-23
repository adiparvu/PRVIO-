import AppIntents
import Foundation
import WatchKit
import WidgetKit

// MARK: - Siri on the wrist
//
// "Hey Siri, complete my task" / "udă plantele" — hands-free while both
// hands hold the ladder. The intents act on the cached payload (instant,
// offline-capable) and queue the real action through WatchActionRelay, the
// same guaranteed-delivery path the interactive complications use; the app
// forwards the queue on its next activation and the phone reconciles.
//
// Phrases: the watch target does not compile Resources/AppShortcuts.xcstrings,
// so the Romanian phrases sit beside the English ones in each list.
//
// Frozen: `CompleteNextTaskSiriIntent`, `WaterAllPlantsSiriIntent`, their
// dialog keys, and the provider name `PRVIOWatchShortcuts` (one App
// Shortcuts provider per target).

// MARK: - Cached payload

/// The payload the app persisted in the App Group, edited the same way
/// WatchStore edits it so the app, the complications and Siri agree.
private enum WatchIntentCache {
    /// Frozen key, shared with WatchStore and the complications.
    private static let payloadKey = "prvio.watch.payload"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    static func payload() -> WatchPayload? {
        guard let data = defaults.data(forKey: payloadKey) else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    /// Persists the edit and repaints the faces.
    static func write(_ payload: WatchPayload) {
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: payloadKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Open tasks, overdue first — the order the Tasks page shows.
    static func openTasks(in payload: WatchPayload) -> [TaskCatalogEntry] {
        let open = payload.tasks.filter { !$0.isCompleted }
        return open.filter { $0.isOverdue == true } + open.filter { $0.isOverdue != true }
    }

    /// Completes an open task; returns its title, or nil when it is missing
    /// or already complete.
    static func completeTask(_ id: UUID, in payload: inout WatchPayload) -> String? {
        guard let i = payload.tasks.firstIndex(where: { $0.id == id }),
              !payload.tasks[i].isCompleted else { return nil }
        payload.tasks[i].isCompleted = true
        payload.tasks[i].isOverdue = false
        payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
        payload.snapshot.overdueTaskCount = payload.tasks
            .filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
        if payload.snapshot.criticalTaskTitle == payload.tasks[i].title {
            payload.snapshot.criticalTaskTitle = nil
        }
        return payload.tasks[i].title
    }

    /// Marks plants watered and recounts the thirsty snapshot.
    static func water(_ ids: Set<UUID>, in payload: inout WatchPayload) {
        for i in payload.plants.indices where ids.contains(payload.plants[i].id) {
            payload.plants[i].needsWatering = false
        }
        let thirsty = payload.plants.filter(\.needsWatering)
        payload.snapshot.plantsNeedingWater = thirsty.count
        payload.snapshot.plantNames = Array(thirsty.prefix(3).map(\.name))
    }
}

/// Spoken names arrive loosely ("the filter task", "gradina"): case- and
/// diacritic-insensitive containment, in both directions.
private enum WatchEntityMatch {
    static func matches(_ name: String, query: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !query.isEmpty else { return false }
        return name.localizedStandardContains(query) || query.localizedStandardContains(name)
    }
}

// MARK: - Entities

struct WatchTaskEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static let defaultQuery = WatchTaskEntityQuery()

    let id: UUID
    let title: String
    let isOverdue: Bool

    init(_ entry: TaskCatalogEntry) {
        id = entry.id
        title = entry.title
        isOverdue = entry.isOverdue == true
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = isOverdue ? "watch_overdue" : nil
        return DisplayRepresentation(
            title: "\(title)",
            subtitle: subtitle,
            image: .init(systemName: isOverdue ? "exclamationmark.circle.fill" : "circle"))
    }
}

struct WatchTaskEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [UUID]) async throws -> [WatchTaskEntity] {
        let wanted = Set(identifiers)
        return (WatchIntentCache.payload()?.tasks ?? [])
            .filter { wanted.contains($0.id) }
            .map(WatchTaskEntity.init)
    }

    /// Open work only: every intent taking a task completes it.
    func suggestedEntities() async throws -> [WatchTaskEntity] {
        guard let payload = WatchIntentCache.payload() else { return [] }
        return WatchIntentCache.openTasks(in: payload).prefix(12).map(WatchTaskEntity.init)
    }

    /// Open tasks only, so a finished task with the same name never wins.
    func entities(matching string: String) async throws -> [WatchTaskEntity] {
        guard let payload = WatchIntentCache.payload() else { return [] }
        return WatchIntentCache.openTasks(in: payload)
            .filter { WatchEntityMatch.matches($0.title, query: string) }
            .map(WatchTaskEntity.init)
    }
}

struct WatchPlantEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Plant"
    static let defaultQuery = WatchPlantEntityQuery()

    let id: UUID
    let name: String
    let emoji: String
    let needsWatering: Bool

    init(_ entry: PlantCatalogEntry) {
        id = entry.id
        name = entry.name
        emoji = entry.emoji
        needsWatering = entry.needsWatering
    }

    var displayRepresentation: DisplayRepresentation {
        let subtitle: LocalizedStringResource? = needsWatering ? "Needs water" : nil
        return DisplayRepresentation(title: "\(emoji) \(name)", subtitle: subtitle)
    }
}

struct WatchPlantEntityQuery: EntityStringQuery {
    init() {}

    func entities(for identifiers: [UUID]) async throws -> [WatchPlantEntity] {
        let wanted = Set(identifiers)
        return (WatchIntentCache.payload()?.plants ?? [])
            .filter { wanted.contains($0.id) }
            .map(WatchPlantEntity.init)
    }

    /// Thirsty plants first; every plant can be watered.
    func suggestedEntities() async throws -> [WatchPlantEntity] {
        let plants = WatchIntentCache.payload()?.plants ?? []
        let ordered = plants.filter(\.needsWatering) + plants.filter { !$0.needsWatering }
        return ordered.prefix(12).map(WatchPlantEntity.init)
    }

    func entities(matching string: String) async throws -> [WatchPlantEntity] {
        (WatchIntentCache.payload()?.plants ?? [])
            .filter { WatchEntityMatch.matches($0.name, query: string) }
            .map(WatchPlantEntity.init)
    }
}

// MARK: - Intents (frozen names)

struct CompleteNextTaskSiriIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_complete_title"

    init() {}

    /// The top of the Tasks page: the first overdue task, else the first open.
    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchIntentCache.payload(),
              let next = WatchIntentCache.openTasks(in: payload).first,
              let title = WatchIntentCache.completeTask(next.id, in: &payload) else {
            return .result(dialog: IntentDialog("watch_siri_no_tasks"))
        }
        WatchIntentCache.write(payload)
        WatchActionRelay.append(action: "completeTask", id: next.id.uuidString)
        WKInterfaceDevice.current().play(.success)
        return .result(dialog: IntentDialog("watch_siri_completed \(title)"))
    }
}

struct WaterAllPlantsSiriIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_water_title"

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchIntentCache.payload() else {
            return .result(dialog: IntentDialog("watch_siri_no_plants"))
        }
        let thirsty = payload.plants.filter(\.needsWatering).map(\.id)
        guard !thirsty.isEmpty else {
            return .result(dialog: IntentDialog("watch_siri_no_plants"))
        }
        WatchIntentCache.water(Set(thirsty), in: &payload)
        WatchIntentCache.write(payload)
        // The phone's queue is per plant: one relay entry each.
        for id in thirsty {
            WatchActionRelay.append(action: "waterPlant", id: id.uuidString)
        }
        WKInterfaceDevice.current().play(.directionUp)
        return .result(dialog: IntentDialog("watch_siri_watered \(thirsty.count)"))
    }
}

// MARK: - Intents on entities

struct CompleteWatchTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_task_title"

    @Parameter(title: "Task")
    var task: WatchTaskEntity

    init() {}

    init(task: WatchTaskEntity) {
        self.task = task
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchIntentCache.payload(),
              let title = WatchIntentCache.completeTask(task.id, in: &payload) else {
            return .result(dialog: IntentDialog("watch_siri_task_gone"))
        }
        WatchIntentCache.write(payload)
        WatchActionRelay.append(action: "completeTask", id: task.id.uuidString)
        WKInterfaceDevice.current().play(.success)
        return .result(dialog: IntentDialog("watch_siri_completed \(title)"))
    }
}

struct WaterWatchPlantIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_plant_title"

    @Parameter(title: "Plant")
    var plant: WatchPlantEntity

    init() {}

    init(plant: WatchPlantEntity) {
        self.plant = plant
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard var payload = WatchIntentCache.payload(),
              let entry = payload.plants.first(where: { $0.id == plant.id }) else {
            return .result(dialog: IntentDialog("watch_siri_plant_gone"))
        }
        // Watering a plant that is not marked thirsty is still a real event
        // for the phone's log, so it is never refused.
        WatchIntentCache.water([entry.id], in: &payload)
        WatchIntentCache.write(payload)
        WatchActionRelay.append(action: "waterPlant", id: entry.id.uuidString)
        WKInterfaceDevice.current().play(.directionUp)
        return .result(dialog: IntentDialog("watch_siri_watered_plant \(entry.name)"))
    }
}

// MARK: - App Shortcuts (the target's single provider)
//
// Phrases with an entity parameter are filled from the queries'
// `suggestedEntities()`; the system re-reads them when
// `PRVIOWatchShortcuts.updateAppShortcutParameters()` is called after the
// task or plant list changes.

struct PRVIOWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CompleteNextTaskSiriIntent(),
            phrases: [
                "Complete my task in \(.applicationName)",
                "Finalizează sarcina în \(.applicationName)",
            ],
            shortTitle: "watch_siri_complete_short",
            systemImageName: "checkmark.circle.fill")
        AppShortcut(
            intent: WaterAllPlantsSiriIntent(),
            phrases: [
                "Water the plants in \(.applicationName)",
                "Udă plantele în \(.applicationName)",
            ],
            shortTitle: "watch_siri_water_short",
            systemImageName: "drop.fill")
        AppShortcut(
            intent: CompleteWatchTaskIntent(),
            phrases: [
                "Complete \(\.$task) in \(.applicationName)",
                "Mark \(\.$task) done in \(.applicationName)",
                "Complete a task in \(.applicationName)",
                "Finalizează \(\.$task) în \(.applicationName)",
                "Bifează \(\.$task) în \(.applicationName)",
                "Finalizează o sarcină în \(.applicationName)",
            ],
            shortTitle: "watch_siri_task_short",
            systemImageName: "checklist")
        AppShortcut(
            intent: WaterWatchPlantIntent(),
            phrases: [
                "Water \(\.$plant) in \(.applicationName)",
                "Water a plant in \(.applicationName)",
                "Udă \(\.$plant) în \(.applicationName)",
                "Udă o plantă în \(.applicationName)",
            ],
            shortTitle: "watch_siri_plant_short",
            systemImageName: "drop")
    }
}
