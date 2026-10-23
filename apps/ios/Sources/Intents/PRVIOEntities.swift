import AppIntents
import CoreSpotlight
import Foundation

// MARK: - Task Entity

struct TaskEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task"
    static var defaultQuery = TaskEntityQuery()

    var id: UUID
    var title: String
    var priority: String

    var displayRepresentation: DisplayRepresentation {
        let icon: String = priority == "high" ? "🔴" : priority == "medium" ? "🟡" : "🟢"
        return DisplayRepresentation(title: "\(icon) \(title)")
    }
}

struct TaskEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [TaskEntity] {
        SharedDataStore.readTaskCatalog()
            .filter { identifiers.contains($0.id) }
            .map { TaskEntity(id: $0.id, title: $0.title, priority: $0.priority) }
    }

    func suggestedEntities() async throws -> [TaskEntity] {
        SharedDataStore.readTaskCatalog()
            .filter { !$0.isCompleted }
            .prefix(8)
            .map { TaskEntity(id: $0.id, title: $0.title, priority: $0.priority) }
    }

    /// Resolves a spoken or typed name ("complete the filter task") against the
    /// open tasks only — every intent taking a TaskEntity acts on open work, so
    /// a finished task with the same name must never win the match.
    func entities(matching string: String) async throws -> [TaskEntity] {
        SharedDataStore.readTaskCatalog()
            .filter { !$0.isCompleted && EntityNameMatch.matches($0.title, query: string) }
            .map { TaskEntity(id: $0.id, title: $0.title, priority: $0.priority) }
    }
}

// MARK: - Supply Item Entity

struct SupplyItemEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Shopping item"
    static var defaultQuery = SupplyItemEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SupplyItemEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [SupplyItemEntity] {
        SharedDataStore.readSupplyCatalog()
            .filter { identifiers.contains($0.id) }
            .map { SupplyItemEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [SupplyItemEntity] {
        SharedDataStore.readSupplyCatalog()
            .filter { !$0.isCompleted }
            .prefix(8)
            .map { SupplyItemEntity(id: $0.id, name: $0.name) }
    }

    /// Open items only, for the same reason as tasks: checking off an item
    /// that is already checked would be a silent no-op.
    func entities(matching string: String) async throws -> [SupplyItemEntity] {
        SharedDataStore.readSupplyCatalog()
            .filter { !$0.isCompleted && EntityNameMatch.matches($0.name, query: string) }
            .map { SupplyItemEntity(id: $0.id, name: $0.name) }
    }
}

// MARK: - Plant Entity

struct PlantEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Plant"
    static var defaultQuery = PlantEntityQuery()

    var id: UUID
    var name: String
    var emoji: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(emoji) \(name)")
    }
}

struct PlantEntityQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [PlantEntity] {
        SharedDataStore.readPlantCatalog()
            .filter { identifiers.contains($0.id) }
            .map { PlantEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }

    func suggestedEntities() async throws -> [PlantEntity] {
        let all = SharedDataStore.readPlantCatalog()
        let needsWater = all.filter { $0.needsWatering }
        return (needsWater.isEmpty ? all : needsWater)
            .prefix(6)
            .map { PlantEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }

    /// Every plant can be watered, so all plants are candidates.
    func entities(matching string: String) async throws -> [PlantEntity] {
        SharedDataStore.readPlantCatalog()
            .filter { EntityNameMatch.matches($0.name, query: string) }
            .map { PlantEntity(id: $0.id, name: $0.name, emoji: $0.emoji) }
    }
}

// MARK: - String matching

/// Shared name matching for the string queries: locale-aware, case- and
/// diacritic-insensitive (so "gradina" finds "Grădina"), in both directions so
/// a query that carries extra words around the name ("the filter task") still
/// resolves the entity named "Filter".
private enum EntityNameMatch {
    static func matches(_ name: String, query: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !query.isEmpty else { return false }
        return name.localizedStandardContains(query) || query.localizedStandardContains(name)
    }
}

// MARK: - Spotlight / semantic index

// IndexedEntity (iOS 18) lets Spotlight and Siri reason over these entities.
// The conformances live in availability-gated extensions so the types keep
// compiling for the app's iOS 17.1 deployment target; the default
// attribute set (title/subtitle/image from displayRepresentation) is enough,
// so no custom attributeSet is provided. SpotlightService associates them
// with the existing searchable items rather than indexing them separately,
// which keeps one Spotlight entry per piece of content.
@available(iOS 18.0, *)
extension TaskEntity: IndexedEntity {}

@available(iOS 18.0, *)
extension SupplyItemEntity: IndexedEntity {}

@available(iOS 18.0, *)
extension PlantEntity: IndexedEntity {}
