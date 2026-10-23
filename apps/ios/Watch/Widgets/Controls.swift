import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Controls
//
// One-tap actions for Control Center, the Smart Stack and the Action button
// (ControlWidget, watchOS 26+). Buttons, not toggles: both actions are
// fire-and-forget and carry no state worth showing. Their intents run in
// this extension and reach the phone through the watch app's relay, exactly
// like the interactive tasks face.
//
// Control kinds are new identifiers, independent of the frozen complication
// kinds; keep them stable once shipped, as placed controls are stored by kind.

private enum ControlKind {
    static let completeNextTask = "PRVIOWatchControlCompleteNextTask"
    static let waterAllPlants = "PRVIOWatchControlWaterAllPlants"
}

struct CompleteNextTaskControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.completeNextTask) {
            ControlWidgetButton(action: CompleteNextTaskControlIntent()) {
                Label("watch_siri_complete_short", systemImage: "checkmark.circle.fill")
            }
        }
        .displayName("watch_siri_complete_short")
        .description("watch_control_complete_desc")
    }
}

struct WaterAllPlantsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.waterAllPlants) {
            ControlWidgetButton(action: WaterAllPlantsControlIntent()) {
                Label("watch_siri_water_short", systemImage: "drop.fill")
            }
        }
        .displayName("watch_siri_water_short")
        .description("watch_control_water_desc")
    }
}
