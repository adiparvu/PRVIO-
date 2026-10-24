import SwiftUI
import WidgetKit

// MARK: - PRVIO watch extension
//
// The wrist-glance layer: accessory complications for watch faces and the
// Smart Stack, the "Now at home" relevance card, plus controls. Everything reads the payload the phone pushed
// (cached by the watch app in the App Group), so face, Smart Stack, app and
// iPhone widgets tell one story.

@main
struct PRVIOWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        PRVIOStatusComplication()
        PRVIOTasksComplication()
        PRVIOWaterComplication()
        PRVIOShoppingComplication()
        PRVIODeliveriesComplication()
        PRVIOHealthComplication()
        PRVIOWeatherComplication()
        PRVIOBudgetComplication()
        PRVIOSessionComplication()
        PRVIOChoiceComplication()
        PRVIONowWidget()
        CompleteNextTaskControl()
        WaterAllPlantsControl()
    }
}
