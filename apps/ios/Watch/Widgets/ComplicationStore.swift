import Foundation
import WidgetKit

// MARK: - App Group access for the extension
//
// The extension's only door to shared state. The watch app owns the frozen
// keys (`prvio.watch.payload`, `prvio.watch.session`); the extension reads
// them and, for actions taken on a face or a control, applies the same
// optimistic edit the app would and queues the real action in
// `WatchActionRelay`. The extension cannot reach WCSession — the app forwards
// the queue to the phone on its next activation and re-reads the cache.

enum ComplicationStore {
    /// Frozen key written by the watch app's WatchStore.
    static let payloadKey = "prvio.watch.payload"

    /// Falls back to standard exactly like the app does (simulator without
    /// the group entitlement), so both processes read the same suite.
    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    /// The cached payload, deduplicated for rendering (duplicate ids in a
    /// ForEach are undefined behavior).
    static func payload() -> WatchPayload? {
        guard let data = defaults.data(forKey: payloadKey),
              let payload = try? JSONDecoder().decode(WatchPayload.self, from: data) else { return nil }
        return payload.sanitizedForRender()
    }

    static func session() -> WatchWorkSession? {
        SharedDataStore.readWatchWorkSession()
    }

    // MARK: Actions

    /// Completes one task. The action is queued even when the cached row is
    /// already gone: the face rendered that id, and the phone ignores a
    /// completion it has already applied.
    static func completeTask(_ id: UUID) {
        edit { payload in
            guard let index = payload.tasks.firstIndex(where: { $0.id == id && !$0.isCompleted }) else {
                return false
            }
            markCompleted(at: index, in: &payload)
            return true
        }
        WatchActionRelay.append(action: "completeTask", id: id.uuidString)
        reloadFaces()
    }

    /// Completes the task the faces lead with (overdue first). Returns false
    /// when nothing is open.
    @discardableResult
    static func completeNextTask() -> Bool {
        guard let next = payload()?.openTasksByUrgency.first else { return false }
        completeTask(next.id)
        return true
    }

    /// Waters every thirsty plant. Returns how many were watered.
    @discardableResult
    static func waterAllPlants() -> Int {
        var watered: [UUID] = []
        edit { payload in
            for index in payload.plants.indices where payload.plants[index].needsWatering {
                payload.plants[index].needsWatering = false
                watered.append(payload.plants[index].id)
            }
            guard !watered.isEmpty else { return false }
            payload.snapshot.plantsNeedingWater = 0
            payload.snapshot.plantNames = []
            return true
        }
        guard !watered.isEmpty else { return 0 }
        for id in watered {
            WatchActionRelay.append(action: "waterPlant", id: id.uuidString)
        }
        reloadFaces()
        return watered.count
    }

    // MARK: Private

    /// Decodes the raw cache (not the sanitized copy, so nothing the app
    /// wrote is dropped), applies `change`, and writes back only when the
    /// change reports it did something.
    @discardableResult
    private static func edit(_ change: (inout WatchPayload) -> Bool) -> Bool {
        let store = defaults
        guard let data = store.data(forKey: payloadKey),
              var payload = try? JSONDecoder().decode(WatchPayload.self, from: data),
              change(&payload),
              let encoded = try? JSONEncoder().encode(payload) else { return false }
        store.set(encoded, forKey: payloadKey)
        return true
    }

    private static func markCompleted(at index: Int, in payload: inout WatchPayload) {
        let title = payload.tasks[index].title
        payload.tasks[index].isCompleted = true
        payload.tasks[index].isOverdue = false
        let open = payload.tasks.filter { !$0.isCompleted }
        payload.snapshot.openTaskCount = open.count
        payload.snapshot.overdueTaskCount = open.filter { $0.isOverdue == true }.count
        // The status face shows the critical title; a finished task must not
        // linger there until the next phone push.
        if payload.snapshot.criticalTaskTitle == title {
            payload.snapshot.criticalTaskTitle = nil
        }
    }

    private static func reloadFaces() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Payload reading helpers

extension WatchPayload {
    /// Open tasks, overdue first, catalog order otherwise — the same order
    /// the watch app's Tasks page uses.
    var openTasksByUrgency: [TaskCatalogEntry] {
        let open = tasks.filter { !$0.isCompleted }
        return open.filter { $0.isOverdue == true } + open.filter { $0.isOverdue != true }
    }

    /// Thirsty plant names from the catalog, falling back to the snapshot's
    /// list for payloads that carry no catalog.
    var thirstyPlantNames: [String] {
        let names = plants.filter(\.needsWatering).map(\.name)
        return names.isEmpty ? snapshot.plantNames : names
    }

    var pendingSupplyNames: [String] {
        supplies.filter { !$0.isCompleted }.map(\.name)
    }

    /// Same vocabulary as WatchRoute.isDeliveryActive in the app.
    var activeDeliveries: [DeliveryCatalogEntry] {
        deliveries.filter { $0.status == "expected" || $0.status == "out_for_delivery" }
    }

    var hasOverdueTasks: Bool { snapshot.overdueTaskCount > 0 }

    var isOverBudget: Bool {
        guard let budgetSpent, let budgetLimit, budgetLimit > 0 else { return false }
        return budgetSpent > budgetLimit
    }

    /// Shape-only content for placeholders and the face gallery. Names stay
    /// empty: the system redacts placeholders, and the gallery must never
    /// show invented household data.
    static var complicationSample: WatchPayload {
        var snapshot = PRVIOWidgetSnapshot()
        snapshot.openTaskCount = 3
        snapshot.overdueTaskCount = 1
        snapshot.plantsNeedingWater = 2
        snapshot.pendingSupplyCount = 4
        snapshot.activeDeliveryCount = 1
        snapshot.propertyHealthScore = 86
        var payload = WatchPayload(snapshot: snapshot)
        payload.weatherTemp = 18
        payload.weatherLo = 11
        payload.weatherHi = 21
        payload.weatherSymbol = "cloud.sun.fill"
        return payload
    }
}
