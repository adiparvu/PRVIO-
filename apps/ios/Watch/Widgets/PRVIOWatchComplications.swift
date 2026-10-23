import WidgetKit
import SwiftUI
import AppIntents
import RelevanceKit

// MARK: - PRVIO watch-face complications
//
// The wrist-glance layer: WidgetKit accessory widgets for the watch face
// and the Smart Stack. They read the payload the phone pushed (cached by
// the watch app in the shared App Group), so the face, the Smart Stack,
// the watch app and the iPhone widgets all tell one story.

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
    }
}

struct PRVIOStatusComplication: Widget {
    let kind = "PRVIOWatchStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchPayloadProvider()) { entry in
            ComplicationView(payload: entry.payload)
                .modifier(ComplicationBackground(tone: .of(.status, entry.payload)))
        }
        .configurationDisplayName("PRVIO")
        .description(NSLocalizedString("watch_complication_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Domain complications
//
// One complication per domain, so the watch face composes exactly what its
// owner cares about — each deep-links to its own page in the watch app.

struct PRVIOTasksComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchTasks", provider: WatchPayloadProvider(domain: .tasks)) { entry in
            let open = (entry.payload?.tasks ?? []).filter { !$0.isCompleted }
            DomainComplicationView(
                count: entry.payload?.snapshot.openTaskCount ?? 0,
                icon: "checklist",
                label: Text("watch_tasks"),
                urgent: (entry.payload?.snapshot.overdueTaskCount ?? 0) > 0,
                lines: Array(open.prefix(2).map(\.title)),
                topTaskId: open.first?.id,
                url: URL(string: "prvio://tasks")
            )
            .modifier(ComplicationBackground(tone: .of(.tasks, entry.payload)))
        }
        .configurationDisplayName("PRVIO · Tasks")
        .description(NSLocalizedString("watch_comp_tasks_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIOWaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchWater", provider: WatchPayloadProvider(domain: .water)) { entry in
            DomainComplicationView(
                count: entry.payload?.snapshot.plantsNeedingWater ?? 0,
                icon: "drop.fill",
                label: Text("watch_water"),
                urgent: false,
                lines: Array((entry.payload?.snapshot.plantNames ?? []).prefix(2)),
                url: URL(string: "prvio://plants")
            )
            .modifier(ComplicationBackground())
        }
        .configurationDisplayName("PRVIO · Water")
        .description(NSLocalizedString("watch_comp_water_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIOShoppingComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchShopping", provider: WatchPayloadProvider(domain: .shopping)) { entry in
            let pending = (entry.payload?.supplies ?? []).filter { !$0.isCompleted }
            DomainComplicationView(
                count: entry.payload?.snapshot.pendingSupplyCount ?? 0,
                icon: "cart.fill",
                label: Text("watch_shopping"),
                urgent: false,
                lines: Array(pending.prefix(2).map(\.name)),
                url: URL(string: "prvio://shopping")
            )
            .modifier(ComplicationBackground())
        }
        .configurationDisplayName("PRVIO · Shopping")
        .description(NSLocalizedString("watch_comp_shopping_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

struct PRVIODeliveriesComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchDeliveries", provider: WatchPayloadProvider(domain: .deliveries)) { entry in
            let next = entry.payload?.deliveries.first
            DomainComplicationView(
                count: entry.payload?.snapshot.activeDeliveryCount ?? 0,
                icon: "shippingbox.fill",
                label: Text("watch_deliveries"),
                urgent: false,
                lines: [next?.title, next?.eta].compactMap { $0 },
                url: URL(string: "prvio://deliveries")
            )
            .modifier(ComplicationBackground())
        }
        .configurationDisplayName("PRVIO · Deliveries")
        .description(NSLocalizedString("watch_comp_deliveries_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Interactive completion (watchOS 11: act from the face itself)

@available(watchOS 11.0, *)
struct CompleteTopTaskIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Task"
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Task")
    var taskId: String

    init() { taskId = "" }
    init(taskId: String) { self.taskId = taskId }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: taskId) else { return .result() }
        // Mutate the cached payload so every complication repaints done.
        let defaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
        if let data = defaults.data(forKey: "prvio.watch.payload"),
           var payload = try? JSONDecoder().decode(WatchPayload.self, from: data),
           let idx = payload.tasks.firstIndex(where: { $0.id == id }) {
            payload.tasks[idx].isCompleted = true
            payload.tasks[idx].isOverdue = false
            payload.snapshot.openTaskCount = payload.tasks.filter { !$0.isCompleted }.count
            payload.snapshot.overdueTaskCount = payload.tasks.filter { !$0.isCompleted && ($0.isOverdue ?? false) }.count
            if let encoded = try? JSONEncoder().encode(payload) {
                defaults.set(encoded, forKey: "prvio.watch.payload")
            }
        }
        WatchActionRelay.append(action: "completeTask", id: taskId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Health complication (the property's score as a face gauge)

struct PRVIOHealthComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchHealth", provider: WatchPayloadProvider(domain: .health)) { entry in
            HealthComplicationView(score: entry.payload?.snapshot.propertyHealthScore,
                                   name: entry.payload?.snapshot.propertyName)
                .modifier(ComplicationBackground())
        }
        .configurationDisplayName("PRVIO · Health")
        .description(NSLocalizedString("watch_comp_health_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

private struct HealthComplicationView: View {
    let score: Int?
    let name: String?

    @Environment(\.widgetFamily) private var family

    private var value: Double { Double(score ?? 0) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: value, in: 0...100) {
                    Image(systemName: "house.fill")
                } currentValueLabel: {
                    Text(verbatim: "\(score ?? 0)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                }
                .gaugeStyle(.accessoryCircular)
                .widgetAccentable()
            case .accessoryCorner:
                Text(verbatim: "\(score ?? 0)%")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel { Text("watch_health") }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(name ?? "PRVIO")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    Gauge(value: value, in: 0...100) { EmptyView() }
                        .gaugeStyle(.accessoryLinearCapacity)
                        .widgetAccentable()
                    Text(verbatim: "\(score ?? 0)%")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Text(verbatim: "PRVIO \(score ?? 0)%")
            }
        }
        .widgetURL(URL(string: "prvio://"))
    }
}

// MARK: - Domain complication faces

private struct DomainComplicationView: View {
    let count: Int
    let icon: String
    let label: Text
    let urgent: Bool
    /// Up to two content lines on the rectangular face — density without
    /// clutter: real titles, not just a number.
    var lines: [String] = []
    /// When set, the rectangular face grows a complete button (watchOS 11
    /// interactive widgets) that finishes this task from the face itself.
    var topTaskId: UUID? = nil
    let url: URL?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    HStack(spacing: 1) {
                        Image(systemName: icon)
                            .symbolRenderingMode(.hierarchical)
                            .widgetAccentable()
                        if urgent {
                            UrgentGlyph()
                        }
                    }
                    .font(.system(size: 12, weight: .semibold))
                    Text(verbatim: "\(count)")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .foregroundStyle(renderingMode.urgentStyle(urgent))
                        .widgetAccentable()
                }
            case .accessoryCorner:
                // The curved slot holds one text run, so urgency rides as a
                // trailing "!" — readable on every face tint.
                Text(verbatim: urgent ? "\(count)!" : "\(count)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(renderingMode.urgentStyle(urgent))
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel { label }
            case .accessoryRectangular:
                HStack(alignment: .center, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                                .widgetAccentable()
                            label
                                .font(.system(size: 13, weight: .semibold))
                        }
                        HStack(spacing: 4) {
                            Text(verbatim: "\(count)")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(renderingMode.urgentStyle(urgent))
                                .widgetAccentable()
                            if urgent {
                                UrgentGlyph()
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        ForEach(Array(lines.prefix(2).enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if let topTaskId, count > 0, #available(watchOS 11.0, *) {
                        Button(intent: CompleteTopTaskIntent(taskId: topTaskId.uuidString)) {
                            Image(systemName: "checkmark.circle")
                                .font(.system(size: 20, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                                .widgetAccentable()
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("watch_complete"))
                    }
                }
            default:
                HStack(spacing: 3) {
                    Image(systemName: urgent ? "exclamationmark.circle.fill" : icon)
                    Text(verbatim: "\(count)")
                    label
                }
            }
        }
        .widgetURL(url)
    }
}

// MARK: - Provider

struct WatchPayloadEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?
}

struct WatchPayloadProvider: TimelineProvider {
    /// Which complication this provider instance feeds — relevance clues are
    /// per domain, so the Smart Stack surfaces the RIGHT card, not all seven.
    enum Domain { case status, tasks, water, shopping, deliveries, health, weather, budget }
    var domain: Domain = .status

    private func load() -> WatchPayload? {
        guard let data = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .data(forKey: "prvio.watch.payload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    func placeholder(in context: Context) -> WatchPayloadEntry {
        WatchPayloadEntry(date: .now, payload: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPayloadEntry) -> Void) {
        completion(WatchPayloadEntry(date: .now, payload: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPayloadEntry>) -> Void) {
        // The watch app reloads timelines whenever a fresh payload lands, so
        // a slow hourly cadence is only the fallback heartbeat.
        let entry = WatchPayloadEntry(date: .now, payload: load())
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(3600))))
    }

    // MARK: Smart Stack relevance (watchOS 11 asks; earlier systems never call)
    //
    // Context clues teach the Smart Stack WHEN each complication matters:
    // plants surface in the morning while thirsty, deliveries while a parcel
    // is on the road today, tasks while something is overdue, weather early
    // and whenever a garden advisory is active. The availability gate matches
    // the protocol requirement's own — the deployment target is watchOS 10,
    // where this method simply never exists.

    @available(watchOS 11.0, *)
    func relevance() async -> WidgetRelevance<Void> {
        // The kind-carrying date context is watchOS 26 API — earlier systems
        // return no clues, and their Smart Stack simply ranks unadvised.
        guard #available(watchOS 26.0, *) else { return WidgetRelevance([]) }
        let payload = load()
        let cal = Calendar.current
        let now = Date()
        var attributes: [WidgetRelevanceAttribute<Void>] = []

        func morning(daysAhead: Int) -> DateInterval? {
            guard let day = cal.date(byAdding: .day, value: daysAhead, to: now),
                  let start = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day),
                  let end = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day),
                  end > now else { return nil }
            return DateInterval(start: max(start, now), end: end)
        }

        switch domain {
        case .tasks:
            if (payload?.snapshot.overdueTaskCount ?? 0) > 0 {
                attributes.append(WidgetRelevanceAttribute(
                    context: .date(interval: DateInterval(start: now, duration: 2 * 3600),
                                   kind: .scheduled)))
            }
        case .water:
            if (payload?.snapshot.plantsNeedingWater ?? 0) > 0 {
                for day in 0...1 {
                    if let interval = morning(daysAhead: day) {
                        attributes.append(WidgetRelevanceAttribute(
                            context: .date(interval: interval, kind: .scheduled)))
                    }
                }
            }
        case .deliveries:
            if payload?.deliveries.contains(where: { $0.status == "out_for_delivery" }) == true,
               let dayEnd = cal.date(bySettingHour: 21, minute: 0, second: 0, of: now),
               dayEnd > now {
                attributes.append(WidgetRelevanceAttribute(
                    context: .date(interval: DateInterval(start: now, end: dayEnd),
                                   kind: .scheduled)))
            }
        case .shopping:
            // Shopping lists matter on weekend mornings when items are pending.
            if (payload?.snapshot.pendingSupplyCount ?? 0) > 0 {
                for day in 0...6 {
                    guard let candidate = cal.date(byAdding: .day, value: day, to: now),
                          cal.component(.weekday, from: candidate) == 7,
                          let interval = morning(daysAhead: day) else { continue }
                    attributes.append(WidgetRelevanceAttribute(
                        context: .date(interval: interval, kind: .default)))
                    break
                }
            }
        case .weather:
            if payload?.weatherAdvisory != nil {
                attributes.append(WidgetRelevanceAttribute(
                    context: .date(interval: DateInterval(start: now, duration: 6 * 3600),
                                   kind: .scheduled)))
            }
            if let interval = morning(daysAhead: payload?.weatherTemp == nil ? 1 : 0) {
                attributes.append(WidgetRelevanceAttribute(
                    context: .date(interval: interval, kind: .informational)))
            }
        case .status, .health, .budget:
            break
        }
        return WidgetRelevance(attributes)
    }
}

// MARK: - Weather complication (Apple Weather at the property)

struct PRVIOWeatherComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchWeather",
                            provider: WatchPayloadProvider(domain: .weather)) { entry in
            WeatherComplicationView(payload: entry.payload)
                .modifier(ComplicationBackground(tone: .of(.weather, entry.payload)))
        }
        .configurationDisplayName("PRVIO · Weather")
        .description(NSLocalizedString("watch_comp_weather_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

private struct WeatherComplicationView: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family

    private var temp: Int? { payload?.weatherTemp.map { Int($0.rounded()) } }
    private var symbol: String { payload?.weatherSymbol ?? "cloud.sun.fill" }
    private var advisory: String? { payload?.weatherAdvisory }

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var advisoryText: Text? {
        switch advisory {
        case "frost": return Text("watch_adv_frost")
        case "rain":  return Text("watch_adv_rain")
        default:      return nil
        }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 0) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                    Text(verbatim: temp.map { "\($0)°" } ?? "–")
                        .font(.system(.body, design: .rounded).weight(.bold))
                        .widgetAccentable()
                }
            case .accessoryCorner:
                Text(verbatim: temp.map { "\($0)°" } ?? "–")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel { Text(payload?.snapshot.propertyName ?? "PRVIO") }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(payload?.snapshot.propertyName ?? "PRVIO")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        Text(verbatim: temp.map { "\($0)°" } ?? "–")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .widgetAccentable()
                        if let lo = payload?.weatherLo, let hi = payload?.weatherHi {
                            Text(verbatim: "\(Int(lo.rounded()))°–\(Int(hi.rounded()))°")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let advisoryText {
                        // The leading symbol keeps the advisory distinct
                        // when the face flattens the orange.
                        HStack(spacing: 3) {
                            Image(systemName: advisory == "frost" ? "snowflake" : "cloud.rain.fill")
                            advisoryText
                                .lineLimit(1)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(renderingMode == .fullColor
                                         ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    } else {
                        // 11 pt is the HIG floor for widget text, attribution
                        // included (it was 9 pt).
                        Text(verbatim: " Apple Weather")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Text(verbatim: temp.map { "PRVIO \($0)°" } ?? "PRVIO")
            }
        }
        .widgetURL(URL(string: "prvio://"))
    }
}

// MARK: - Budget complication (this month's spending, household currency)

struct PRVIOBudgetComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchBudget",
                            provider: WatchPayloadProvider(domain: .budget)) { entry in
            BudgetComplicationView(payload: entry.payload)
                .modifier(ComplicationBackground(tone: .of(.budget, entry.payload)))
        }
        .configurationDisplayName("PRVIO · Budget")
        .description(NSLocalizedString("watch_comp_budget_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

private struct BudgetComplicationView: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family

    private var spent: Double? { payload?.budgetSpent }
    private var limit: Double? { payload?.budgetLimit }
    private var code: String { payload?.budgetCurrency ?? "EUR" }

    @Environment(\.widgetRenderingMode) private var renderingMode
    private var over: Bool {
        guard let spent, let limit else { return false }
        return spent > limit
    }

    /// Full amount for the wide faces ("1.234 lei").
    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// Compact amount for the tiny faces. Manual thousands-compaction —
    /// the system's .compactName notation needs watchOS 11, and this
    /// complication serves watchOS 10 too.
    private func compact(_ value: Double) -> String {
        if value >= 10_000 {
            let thousands = (value / 1000).formatted(.number.precision(.fractionLength(0)))
            return "\(thousands)K \(code)"
        }
        return money(value)
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                if let spent, let limit, limit > 0 {
                    Gauge(value: min(spent, limit), in: 0...limit) {
                        Image(systemName: "banknote.fill")
                    } currentValueLabel: {
                        // Over budget: the trailing "!" says it on every face tint.
                        let percent = "\(Int((spent / limit * 100).rounded()))%"
                        Text(verbatim: over ? "\(percent)!" : percent)
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .foregroundStyle(renderingMode.urgentStyle(over))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .gaugeStyle(.accessoryCircularCapacity)
                    .widgetAccentable()
                } else {
                    VStack(spacing: 0) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text(verbatim: spent.map(compact) ?? "–")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            // Footnote may shrink, but never below the 11 pt floor.
                            .minimumScaleFactor(0.85)
                            .lineLimit(1)
                            .widgetAccentable()
                    }
                }
            case .accessoryCorner:
                Text(verbatim: spent.map { over ? "\(compact($0))!" : compact($0) } ?? "–")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(renderingMode.urgentStyle(over))
                    .widgetAccentable()
                    .widgetCurvesContent()
                    .widgetLabel { Text("watch_budget") }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "banknote.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                        Text("watch_budget_month")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    HStack(spacing: 4) {
                        Text(verbatim: spent.map(money) ?? "–")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(renderingMode.urgentStyle(over))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                            .widgetAccentable()
                        if over {
                            UrgentGlyph()
                                .font(.system(size: 13, weight: .semibold))
                        }
                    }
                    if let spent, let limit, limit > 0 {
                        Gauge(value: min(spent, limit), in: 0...limit) { EmptyView() }
                            .gaugeStyle(.accessoryLinearCapacity)
                            .tint(over ? .red : .green)
                            .widgetAccentable()
                    } else {
                        Text(payload?.snapshot.propertyName ?? "PRVIO")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default:
                Text(verbatim: spent.map { "PRVIO · \(money($0))" } ?? "PRVIO")
            }
        }
        .privacySensitive()
        .widgetURL(URL(string: "prvio://"))
    }
}

// MARK: - Faces

private struct ComplicationView: View {
    let payload: WatchPayload?
    @Environment(\.widgetFamily) private var family

    private var open: Int { payload?.snapshot.openTaskCount ?? 0 }
    private var overdue: Int { payload?.snapshot.overdueTaskCount ?? 0 }
    private var water: Int { payload?.snapshot.plantsNeedingWater ?? 0 }

    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            corner
        case .accessoryRectangular:
            rectangular
        default:
            inline
        }
    }

    // Ring of open tasks with the house at the center.
    private var circular: some View {
        Gauge(value: Double(min(open, 20)), in: 0...20) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text(verbatim: "\(open)")
                .font(.system(.body, design: .rounded).weight(.bold))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .widgetURL(URL(string: "prvio://"))
    }

    private var corner: some View {
        Text(verbatim: overdue > 0 ? "\(open)!" : "\(open)")
            .font(.system(.title3, design: .rounded).weight(.bold))
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel {
                Text("watch_tasks")
            }
            .widgetURL(URL(string: "prvio://tasks"))
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "house.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .widgetAccentable()
                Text(payload?.snapshot.propertyName ?? "PRVIO")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                statPair(icon: "checklist", value: open, urgent: overdue > 0)
                statPair(icon: "drop.fill", value: water, urgent: false)
                statPair(icon: "shippingbox.fill",
                         value: payload?.snapshot.activeDeliveryCount ?? 0, urgent: false)
            }
            if let critical = payload?.snapshot.criticalTaskTitle {
                Text(critical)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "prvio://"))
    }

    private var inline: some View {
        // Inline gets one line on the face: lead with what needs doing.
        Text(verbatim: "PRVIO · \(open)✓ \(water)💧")
            .widgetURL(URL(string: "prvio://tasks"))
    }

    private func statPair(icon: String, value: Int, urgent: Bool) -> some View {
        HStack(spacing: 2) {
            // Urgent swaps the domain glyph for the exclamation mark — the
            // cue survives accented faces, where red would not.
            Image(systemName: urgent ? "exclamationmark.circle.fill" : icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(urgent && renderingMode == .fullColor
                                 ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                .widgetAccentable(urgent)
            Text(verbatim: "\(value)")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .widgetAccentable()
        }
    }
}


// MARK: - Family-aware complication background
//
// AccessoryWidgetBackground is designed for the circular faces; in the Smart
// Stack's rectangular slot it rendered as a stray dark circle behind the
// content. The Smart Stack's default is plain black, and HIG asks for a
// background that adds meaning: the rectangular card carries the state as
// a quiet wash — warm when something is overdue/over, calm otherwise. The
// wash only paints in full color; accented/vibrant faces would flatten it
// into a grey slab, so they (and inline) keep a clear ground.

struct ComplicationBackground: ViewModifier {
    enum Tone {
        case calm, warning

        fileprivate var wash: LinearGradient {
            let color: Color = self == .warning ? .orange : .teal
            return LinearGradient(colors: [color.opacity(0.45), color.opacity(0.18)],
                                  startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    var tone: Tone = .calm

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            if family == .accessoryCircular || family == .accessoryCorner {
                AccessoryWidgetBackground()
            } else if family == .accessoryRectangular && renderingMode == .fullColor {
                tone.wash
            } else {
                Color.clear
            }
        }
    }
}

extension ComplicationBackground.Tone {
    /// The state a domain's Smart Stack card should wear.
    static func of(_ domain: WatchDomainOption, _ payload: WatchPayload?) -> Self {
        switch domain {
        case .status, .tasks:
            return (payload?.snapshot.overdueTaskCount ?? 0) > 0 ? .warning : .calm
        case .budget:
            guard let spent = payload?.budgetSpent, let limit = payload?.budgetLimit else {
                return .calm
            }
            return spent > limit ? .warning : .calm
        case .weather:
            return payload?.weatherAdvisory != nil ? .warning : .calm
        case .water, .shopping, .deliveries, .health:
            return .calm
        }
    }
}

// MARK: - Urgency without color
//
// Accented faces tint everything in one face color, and some wearers can't
// tell red from the rest anyway — so every urgent state also carries a
// glyph. Red is applied only where the face renders in full color.

private struct UrgentGlyph: View {
    var body: some View {
        Image(systemName: "exclamationmark.circle.fill")
            .symbolRenderingMode(.hierarchical)
            .widgetAccentable()
            .accessibilityHidden(true)
    }
}

private extension WidgetRenderingMode {
    func urgentStyle(_ urgent: Bool) -> AnyShapeStyle {
        urgent && self == .fullColor ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
    }
}

// MARK: - Configurable complication (one slot, your choice of domain)
//
// The system widget configurator (long-press → edit) offers the domain as a
// parameter — one "PRVIO" complication that becomes whichever face its owner
// wants, instead of forcing seven separate entries onto the picker.

enum WatchDomainOption: String, AppEnum {
    case status, tasks, water, shopping, deliveries, health, weather, budget

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "PRVIO"
    static var caseDisplayRepresentations: [WatchDomainOption: DisplayRepresentation] = [
        .status:     "PRVIO",
        .tasks:      DisplayRepresentation(title: LocalizedStringResource("watch_tasks")),
        .water:      DisplayRepresentation(title: LocalizedStringResource("watch_water")),
        .shopping:   DisplayRepresentation(title: LocalizedStringResource("watch_shopping")),
        .deliveries: DisplayRepresentation(title: LocalizedStringResource("watch_deliveries")),
        .health:     DisplayRepresentation(title: LocalizedStringResource("watch_health")),
        .weather:    DisplayRepresentation(title: LocalizedStringResource("watch_weather")),
        .budget:     DisplayRepresentation(title: LocalizedStringResource("watch_budget")),
    ]
}

struct PRVIODomainConfigIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "PRVIO"

    @Parameter(title: "Domain", default: .status)
    var domain: WatchDomainOption
}

struct ChoiceEntry: TimelineEntry {
    let date: Date
    let payload: WatchPayload?
    let domain: WatchDomainOption
}

struct ChoiceProvider: AppIntentTimelineProvider {
    private func load() -> WatchPayload? {
        guard let data = UserDefaults(suiteName: SharedDataStore.suiteName)?
            .data(forKey: "prvio.watch.payload") else { return nil }
        return try? JSONDecoder().decode(WatchPayload.self, from: data)
    }

    /// watchOS requires the pre-configured menu (there is no in-place widget
    /// editor on the watch face picker) — one entry per domain.
    func recommendations() -> [AppIntentRecommendation<PRVIODomainConfigIntent>] {
        WatchDomainOption.allCases.map { option in
            let intent = PRVIODomainConfigIntent()
            intent.domain = option
            return AppIntentRecommendation(
                intent: intent,
                description: Text(WatchDomainOption.caseDisplayRepresentations[option]?.title
                                  ?? "PRVIO"))
        }
    }

    func placeholder(in context: Context) -> ChoiceEntry {
        ChoiceEntry(date: .now, payload: nil, domain: .status)
    }

    func snapshot(for configuration: PRVIODomainConfigIntent, in context: Context) async -> ChoiceEntry {
        ChoiceEntry(date: .now, payload: load(), domain: configuration.domain)
    }

    func timeline(for configuration: PRVIODomainConfigIntent, in context: Context) async -> Timeline<ChoiceEntry> {
        Timeline(entries: [ChoiceEntry(date: .now, payload: load(), domain: configuration.domain)],
                 policy: .after(.now.addingTimeInterval(3600)))
    }
}

struct PRVIOChoiceComplication: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "PRVIOWatchChoice",
                               intent: PRVIODomainConfigIntent.self,
                               provider: ChoiceProvider()) { entry in
            ChoiceComplicationView(payload: entry.payload, domain: entry.domain)
                .modifier(ComplicationBackground(tone: .of(entry.domain, entry.payload)))
        }
        .configurationDisplayName("PRVIO +")
        .description(NSLocalizedString("watch_comp_choice_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

private struct ChoiceComplicationView: View {
    let payload: WatchPayload?
    let domain: WatchDomainOption

    var body: some View {
        switch domain {
        case .status:
            ComplicationView(payload: payload)
        case .health:
            HealthComplicationView(score: payload?.snapshot.propertyHealthScore,
                                   name: payload?.snapshot.propertyName)
        case .weather:
            WeatherComplicationView(payload: payload)
        case .budget:
            BudgetComplicationView(payload: payload)
        case .tasks:
            let open = (payload?.tasks ?? []).filter { !$0.isCompleted }
            DomainComplicationView(
                count: payload?.snapshot.openTaskCount ?? 0,
                icon: "checklist",
                label: Text("watch_tasks"),
                urgent: (payload?.snapshot.overdueTaskCount ?? 0) > 0,
                lines: Array(open.prefix(2).map(\.title)),
                topTaskId: open.first?.id,
                url: URL(string: "prvio://tasks"))
        case .water:
            DomainComplicationView(
                count: payload?.snapshot.plantsNeedingWater ?? 0,
                icon: "drop.fill",
                label: Text("watch_water"),
                urgent: false,
                lines: Array((payload?.snapshot.plantNames ?? []).prefix(2)),
                url: URL(string: "prvio://plants"))
        case .shopping:
            let pending = (payload?.supplies ?? []).filter { !$0.isCompleted }
            DomainComplicationView(
                count: payload?.snapshot.pendingSupplyCount ?? 0,
                icon: "cart.fill",
                label: Text("watch_shopping"),
                urgent: false,
                lines: Array(pending.prefix(2).map(\.name)),
                url: URL(string: "prvio://shopping"))
        case .deliveries:
            let next = payload?.deliveries.first
            DomainComplicationView(
                count: payload?.snapshot.activeDeliveryCount ?? 0,
                icon: "shippingbox.fill",
                label: Text("watch_deliveries"),
                urgent: false,
                lines: [next?.title, next?.eta].compactMap { $0 },
                url: URL(string: "prvio://deliveries"))
        }
    }
}
