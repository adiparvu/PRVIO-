import SwiftUI
import WidgetKit

// MARK: - Payload complications
//
// One complication per domain, so a face composes exactly what its owner
// cares about, plus one configurable complication (`PRVIOWatchChoice`) that
// becomes whichever domain is picked in the system's face editor. All of them
// render through `DomainFace`, so the two paths never drift apart.

private enum DomainComplicationConfiguration {
    @MainActor
    static func make(kind: String,
                     domain: WatchDomainOption,
                     name: Text,
                     description: LocalizedStringKey) -> some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DomainTimelineProvider(domain: domain)) { entry in
            DomainFace(domain: entry.domain, payload: entry.payload)
                .complicationBackground(.of(entry.domain, entry.payload))
        }
        // The face picker already groups by app, so the name is the domain
        // itself rather than "PRVIO · …".
        .configurationDisplayName(name)
        .description(Text(description))
        .supportedFamilies(ComplicationTheme.families)
    }
}

struct PRVIOStatusComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.status, domain: .status,
                                             name: WatchDomainOption.status.label,
                                             description: "watch_complication_desc")
    }
}

struct PRVIOTasksComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.tasks, domain: .tasks,
                                             name: WatchDomainOption.tasks.label,
                                             description: "watch_comp_tasks_desc")
    }
}

struct PRVIOWaterComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.water, domain: .water,
                                             name: WatchDomainOption.water.label,
                                             description: "watch_comp_water_desc")
    }
}

struct PRVIOShoppingComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.shopping, domain: .shopping,
                                             name: WatchDomainOption.shopping.label,
                                             description: "watch_comp_shopping_desc")
    }
}

struct PRVIODeliveriesComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.deliveries, domain: .deliveries,
                                             name: WatchDomainOption.deliveries.label,
                                             description: "watch_comp_deliveries_desc")
    }
}

struct PRVIOHealthComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.health, domain: .health,
                                             name: WatchDomainOption.health.label,
                                             description: "watch_comp_health_desc")
    }
}

struct PRVIOWeatherComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.weather, domain: .weather,
                                             name: WatchDomainOption.weather.label,
                                             description: "watch_comp_weather_desc")
    }
}

struct PRVIOBudgetComplication: Widget {
    var body: some WidgetConfiguration {
        DomainComplicationConfiguration.make(kind: ComplicationKind.budget, domain: .budget,
                                             name: WatchDomainOption.budget.label,
                                             description: "watch_comp_budget_desc")
    }
}

struct PRVIOChoiceComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ComplicationKind.choice,
                               intent: PRVIODomainConfigIntent.self,
                               provider: ChoiceTimelineProvider()) { entry in
            DomainFace(domain: entry.domain, payload: entry.payload)
                .complicationBackground(.of(entry.domain, entry.payload))
        }
        .configurationDisplayName(Text(verbatim: "PRVIO +"))
        .description(Text("watch_comp_choice_desc"))
        .supportedFamilies(ComplicationTheme.families)
    }
}
