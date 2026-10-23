import AppIntents
import Foundation

// Type names, parameter names and raw values in this file are part of the
// frozen contract: faces store configured intents by them, so renaming one
// resets every configured complication.

// MARK: - Configurable domain

enum WatchDomainOption: String, AppEnum, CaseIterable {
    case status, tasks, water, shopping, deliveries, health, weather, budget

    // Literal forms: the App Intents metadata extractor reads these at build
    // time and accepts only constant values.
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "watch_comp_param_domain"

    static let caseDisplayRepresentations: [WatchDomainOption: DisplayRepresentation] = [
        .status:     DisplayRepresentation(title: "PRVIO"),
        .tasks:      DisplayRepresentation(title: "watch_tasks"),
        .water:      DisplayRepresentation(title: "watch_water"),
        .shopping:   DisplayRepresentation(title: "watch_shopping"),
        .deliveries: DisplayRepresentation(title: "watch_deliveries"),
        .health:     DisplayRepresentation(title: "watch_health"),
        .weather:    DisplayRepresentation(title: "watch_weather"),
        .budget:     DisplayRepresentation(title: "watch_budget"),
    ]
}

struct PRVIODomainConfigIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "PRVIO"

    @Parameter(title: "watch_comp_param_domain", default: .status)
    var domain: WatchDomainOption

    /// A configuration for one domain, used to key Smart Stack relevance.
    static func showing(_ domain: WatchDomainOption) -> PRVIODomainConfigIntent {
        let intent = PRVIODomainConfigIntent()
        intent.domain = domain
        return intent
    }
}

// MARK: - Interactive tasks face

/// The check button on the tasks face. Runs in the extension: it edits the
/// cached payload so every face repaints at once, and relays the completion
/// to the phone through the watch app.
struct CompleteTopTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_complete"
    static let isDiscoverable = false

    @Parameter(title: "watch_tasks")
    var taskId: String

    init() { taskId = "" }
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        ComplicationStore.completeTask(id)
        return .result()
    }
}

// MARK: - Controls (Control Center, Smart Stack, Action button)
//
// The Siri intents live in the app target, which this extension cannot see;
// these mirror their behavior through the same relay. Not discoverable, so
// Shortcuts and Siri keep offering only the app's own intents.

struct CompleteNextTaskControlIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_complete_title"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        ComplicationStore.completeNextTask()
        return .result()
    }
}

struct WaterAllPlantsControlIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_water_title"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        ComplicationStore.waterAllPlants()
        return .result()
    }
}
