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

// MARK: - Now card actions
//
// New type names (not part of the frozen list), used only by buttons on the
// "Now at home" card. They reuse the frozen relay actions `waterPlant` and
// `deliveryReceived`, so the phone needs nothing new.

struct WaterPlantIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_siri_plant_title"
    static let isDiscoverable = false

    @Parameter(title: "watch_plants")
    var plantId: String

    init() { plantId = "" }
    init(plantId: String) { self.plantId = plantId }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: plantId) else { return .result() }
        ComplicationStore.waterPlant(id)
        return .result()
    }
}

struct MarkDeliveryReceivedIntent: AppIntent {
    static let title: LocalizedStringResource = "watch_delivery_received"
    static let isDiscoverable = false

    @Parameter(title: "watch_deliveries")
    var deliveryId: String

    init() { deliveryId = "" }
    init(deliveryId: String) { self.deliveryId = deliveryId }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: deliveryId) else { return .result() }
        ComplicationStore.markDeliveryReceived(id)
        return .result()
    }
}

// MARK: - "Now at home" relevance configuration
//
// RelevanceEntriesProvider requires a WidgetConfigurationIntent: each moment
// is one configuration, so the Smart Stack can promote the card for exactly
// the moment whose clue matched. The person never edits it.

enum NowMoment: String, AppEnum, CaseIterable {
    case homecoming, watering, delivery, session

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "watch_comp_param_domain"

    static let caseDisplayRepresentations: [NowMoment: DisplayRepresentation] = [
        .homecoming: DisplayRepresentation(title: "watch_page_home"),
        .watering:   DisplayRepresentation(title: "watch_water"),
        .delivery:   DisplayRepresentation(title: "Out for delivery"),
        .session:    DisplayRepresentation(title: "Work session"),
    ]
}

struct PRVIONowIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "watch_now_title"
    static let isDiscoverable = false

    @Parameter(title: "watch_comp_param_domain", default: .homecoming)
    var moment: NowMoment

    static func showing(_ moment: NowMoment) -> PRVIONowIntent {
        let intent = PRVIONowIntent()
        intent.moment = moment
        return intent
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
