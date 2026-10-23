import SwiftUI
import WidgetKit

// MARK: - Domain dispatcher
//
// One face per domain, shared by the per-domain complications and the
// configurable one, so both always render identically. Rendering-mode rules
// for every face: key content is `.widgetAccentable()` (the face color in
// accented mode), everything else stays primary/secondary (white), and
// urgency always carries a glyph or "!" besides any color.

struct DomainFace: View {
    let domain: WatchDomainOption
    let payload: WatchPayload?

    var body: some View {
        switch domain {
        case .status:     StatusFace(payload: payload)
        case .health:     HealthFace(payload: payload)
        case .weather:    WeatherFace(payload: payload)
        case .budget:     BudgetFace(payload: payload)
        case .tasks:      MetricFace(metric: .tasks(payload))
        case .water:      MetricFace(metric: .water(payload))
        case .shopping:   MetricFace(metric: .shopping(payload))
        case .deliveries: MetricFace(metric: .deliveries(payload))
        }
    }
}

extension ComplicationTone {
    /// The Smart Stack wash a domain wears.
    static func of(_ domain: WatchDomainOption, _ payload: WatchPayload?) -> ComplicationTone {
        switch domain {
        case .status, .tasks:
            return payload?.hasOverdueTasks == true ? .attention : .calm(domain.tint)
        case .weather:
            return payload?.weatherAdvisory != nil ? .attention : .calm(domain.tint)
        case .budget:
            // Never `.attention`: the amount is redacted while the wrist is
            // down, and a warning wash would still reveal "over budget".
            return .calm(domain.tint)
        case .water, .shopping, .deliveries, .health:
            return .calm(domain.tint)
        }
    }
}

// MARK: - Count faces (tasks, water, shopping, deliveries)

struct DomainMetric {
    let domain: WatchDomainOption
    let count: Int
    let isUrgent: Bool
    /// Up to two real titles on the rectangular face — names, not just a number.
    let lines: [String]
    /// Set on the tasks face: the open task its check button completes.
    let completableTaskId: UUID?

    static func tasks(_ payload: WatchPayload?) -> DomainMetric {
        let open = payload?.openTasksByUrgency ?? []
        return DomainMetric(domain: .tasks,
                            count: payload?.snapshot.openTaskCount ?? 0,
                            isUrgent: payload?.hasOverdueTasks ?? false,
                            lines: open.prefix(2).map(\.title),
                            completableTaskId: open.first?.id)
    }

    static func water(_ payload: WatchPayload?) -> DomainMetric {
        DomainMetric(domain: .water,
                     count: payload?.snapshot.plantsNeedingWater ?? 0,
                     isUrgent: false,
                     lines: Array((payload?.thirstyPlantNames ?? []).prefix(2)),
                     completableTaskId: nil)
    }

    static func shopping(_ payload: WatchPayload?) -> DomainMetric {
        DomainMetric(domain: .shopping,
                     count: payload?.snapshot.pendingSupplyCount ?? 0,
                     isUrgent: false,
                     lines: Array((payload?.pendingSupplyNames ?? []).prefix(2)),
                     completableTaskId: nil)
    }

    static func deliveries(_ payload: WatchPayload?) -> DomainMetric {
        let next = payload?.activeDeliveries.first
        return DomainMetric(domain: .deliveries,
                            count: payload?.snapshot.activeDeliveryCount ?? 0,
                            isUrgent: false,
                            lines: [next?.title, next?.eta].compactMap { $0 },
                            completableTaskId: nil)
    }
}

struct MetricFace: View {
    let metric: DomainMetric

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    var body: some View {
        face.widgetURL(metric.domain.link)
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryCorner:      corner
        case .accessoryRectangular: rectangular
        default:                    inline
        }
    }

    private var countText: Text { Text(verbatim: "\(metric.count)") }

    private var circular: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.hairline) {
                Image(systemName: metric.domain.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .widgetAccentable()
                    .accessibilityLabel(metric.domain.label)
                if metric.isUrgent {
                    UrgentGlyph()
                }
            }
            .font(Theme.Typography.glyph)
            countText
                .font(Theme.Typography.circularValue)
                .foregroundStyle(renderingMode.emphasis(metric.isUrgent))
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }

    /// The curved slot holds one text run, so urgency rides as a trailing "!".
    private var corner: some View {
        Text(verbatim: metric.isUrgent ? "\(metric.count)!" : "\(metric.count)")
            .font(Theme.Typography.cornerValue)
            .foregroundStyle(renderingMode.emphasis(metric.isUrgent))
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel { metric.domain.label }
            .accessibilityLabel(metric.domain.label)
            .accessibilityValue(metric.isUrgent ? Text("\(metric.count) \(Text("watch_overdue"))") : countText)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.hairline) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: metric.domain.systemImage)
                    .font(Theme.Typography.glyph)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                metric.domain.label
                    .font(Theme.Typography.header)
                    .lineLimit(1)
                Spacer(minLength: Theme.Spacing.s)
                if metric.isUrgent {
                    UrgentGlyph()
                        .font(Theme.Typography.header)
                }
                countText
                    .font(Theme.Typography.headerValue)
                    .foregroundStyle(renderingMode.emphasis(metric.isUrgent))
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 0) {
                    if metric.count == 0 {
                        Text("watch_all_good")
                            .font(Theme.Typography.detail)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        ForEach(Array(metric.lines.prefix(2).enumerated()), id: \.offset) { index, line in
                            Text(verbatim: line)
                                .font(Theme.Typography.detail)
                                .foregroundStyle(index == 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let taskId = metric.completableTaskId, metric.count > 0 {
                    Button(intent: CompleteTopTaskIntent(taskId: taskId.uuidString)) {
                        Image(systemName: "checkmark.circle")
                            .font(Theme.Typography.action)
                            .symbolRenderingMode(.hierarchical)
                            .widgetAccentable()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("watch_complete"))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var inline: some View {
        Label {
            Text("\(metric.count) \(metric.domain.label)")
        } icon: {
            Image(systemName: metric.isUrgent ? UrgencyCue.symbol : metric.domain.systemImage)
        }
    }
}

// MARK: - Status (the household overview)

struct StatusFace: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    private var open: Int { payload?.snapshot.openTaskCount ?? 0 }
    private var water: Int { payload?.snapshot.plantsNeedingWater ?? 0 }
    private var parcels: Int { payload?.snapshot.activeDeliveryCount ?? 0 }
    private var isUrgent: Bool { payload?.hasOverdueTasks ?? false }
    private var propertyName: String { payload?.snapshot.propertyName ?? "PRVIO" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            circular.widgetURL(ComplicationLink.today)
        case .accessoryCorner:
            corner.widgetURL(ComplicationLink.tasks)
        case .accessoryRectangular:
            rectangular.widgetURL(ComplicationLink.today)
        default:
            inline.widgetURL(ComplicationLink.tasks)
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: isUrgent ? UrgencyCue.symbol : WatchDomainOption.status.systemImage)
                .font(Theme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
                .accessibilityLabel(isUrgent ? Text("watch_overdue") : Text("watch_tasks"))
            Text(verbatim: "\(open)")
                .font(Theme.Typography.circularValue)
                .foregroundStyle(renderingMode.emphasis(isUrgent))
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }

    private var corner: some View {
        Text(verbatim: isUrgent ? "\(open)!" : "\(open)")
            .font(Theme.Typography.cornerValue)
            .foregroundStyle(renderingMode.emphasis(isUrgent))
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel { Text("watch_tasks") }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: WatchDomainOption.status.systemImage)
                    .font(Theme.Typography.glyph)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                Text(verbatim: propertyName)
                    .font(Theme.Typography.header)
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Spacing.l) {
                stat(.tasks, value: open, isUrgent: isUrgent)
                stat(.water, value: water, isUrgent: false)
                stat(.deliveries, value: parcels, isUrgent: false)
            }
            if let critical = payload?.snapshot.criticalTaskTitle {
                Text(verbatim: critical)
                    .font(Theme.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One line on the face: what needs doing, with glyphs instead of words.
    private var inline: some View {
        Text("\(Image(systemName: isUrgent ? UrgencyCue.symbol : WatchDomainOption.tasks.systemImage)) \(open)  \(Image(systemName: WatchDomainOption.water.systemImage)) \(water)")
    }

    /// Urgent swaps the domain glyph for the exclamation mark, so the cue
    /// survives accented faces where red would not.
    private func stat(_ domain: WatchDomainOption, value: Int, isUrgent: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: isUrgent ? UrgencyCue.symbol : domain.systemImage)
                .font(Theme.Typography.glyph)
                .foregroundStyle(isUrgent && renderingMode == .fullColor
                                 ? AnyShapeStyle(Theme.Tint.critical) : AnyShapeStyle(.secondary))
                .widgetAccentable(isUrgent)
                .accessibilityLabel(domain.label)
            Text(verbatim: "\(value)")
                .font(Theme.Typography.statValue)
                .widgetAccentable()
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Health (the property's score)

struct HealthFace: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family

    private typealias Theme = ComplicationTheme

    private var score: Int? { payload?.snapshot.propertyHealthScore }
    private var value: Double { Double(min(max(score ?? 0, 0), 100)) }
    /// No score yet reads as a dash, never as a fake zero.
    private var scoreText: String { score.map { "\($0)" } ?? "–" }

    var body: some View {
        face.widgetURL(WatchDomainOption.health.link)
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: value, in: 0...100) {
                Image(systemName: WatchDomainOption.health.systemImage)
                    .accessibilityLabel(Text("watch_health"))
            } currentValueLabel: {
                Text(verbatim: scoreText)
                    .font(Theme.Typography.circularValue)
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
        case .accessoryCorner:
            Text(verbatim: scoreText)
                .font(Theme.Typography.cornerValue)
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { Text("watch_health") }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: WatchDomainOption.health.systemImage)
                        .font(Theme.Typography.glyph)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                    Text("watch_health")
                        .font(Theme.Typography.header)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.s)
                    Text(verbatim: scoreText)
                        .font(Theme.Typography.headerValue)
                        .widgetAccentable()
                }
                .accessibilityElement(children: .combine)
                Gauge(value: value, in: 0...100) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .widgetAccentable()
                    .accessibilityHidden(true)
                if let name = payload?.snapshot.propertyName {
                    Text(verbatim: name)
                        .font(Theme.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default:
            Label {
                Text(verbatim: scoreText)
            } icon: {
                Image(systemName: WatchDomainOption.health.systemImage)
            }
        }
    }
}

// MARK: - Weather (Apple Weather at the property)

struct WeatherFace: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    /// Required attribution for WeatherKit data; the leading glyph is the
    /// Apple logo character.
    static let attribution = "\u{F8FF} Apple Weather"

    private var temperature: String {
        payload?.weatherTemp.map { "\(Int($0.rounded()))°" } ?? "–"
    }
    private var symbol: String { payload?.weatherSymbol ?? WatchDomainOption.weather.systemImage }
    private var propertyName: String { payload?.snapshot.propertyName ?? "PRVIO" }

    private var advisory: (symbol: String, text: Text)? {
        switch payload?.weatherAdvisory {
        case "frost": return ("snowflake", Text("watch_adv_frost"))
        case "rain":  return ("cloud.rain.fill", Text("watch_adv_rain"))
        default:      return nil
        }
    }

    var body: some View {
        face.widgetURL(WatchDomainOption.weather.link)
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular:
            VStack(spacing: 0) {
                Image(systemName: advisory?.symbol ?? symbol)
                    .font(Theme.Typography.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text(verbatim: temperature)
                    .font(Theme.Typography.circularValue)
                    .widgetAccentable()
            }
        case .accessoryCorner:
            Text(verbatim: advisory == nil ? temperature : "\(temperature)!")
                .font(Theme.Typography.cornerValue)
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { Text(verbatim: propertyName) }
        case .accessoryRectangular:
            rectangular
        default:
            Label {
                Text(verbatim: temperature)
            } icon: {
                Image(systemName: advisory?.symbol ?? symbol)
            }
        }
    }

    /// An advisory takes the header line (it matters more than the place
    /// name), so the attribution line can stay on every rectangular face.
    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let advisory {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: advisory.symbol)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                    advisory.text
                        .lineLimit(1)
                }
                .font(Theme.Typography.header)
                .foregroundStyle(renderingMode.emphasis(true, color: Theme.Tint.attention))
            } else {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: symbol)
                        .font(Theme.Typography.glyph)
                        .symbolRenderingMode(.hierarchical)
                        .accessibilityHidden(true)
                    Text(verbatim: propertyName)
                        .font(Theme.Typography.header)
                        .lineLimit(1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Text(verbatim: temperature)
                    .font(Theme.Typography.metric)
                    .widgetAccentable()
                if let lo = payload?.weatherLo, let hi = payload?.weatherHi {
                    Text(verbatim: "\(Int(lo.rounded()))°–\(Int(hi.rounded()))°")
                        .font(Theme.Typography.detail)
                        .foregroundStyle(.secondary)
                }
            }
            Text(verbatim: Self.attribution)
                .font(Theme.Typography.detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Budget (this month's spending, household currency)

struct BudgetFace: View {
    let payload: WatchPayload?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    private var spent: Double? { payload?.budgetSpent }
    private var limit: Double? { payload?.budgetLimit.flatMap { $0 > 0 ? $0 : nil } }
    private var code: String { payload?.budgetCurrency ?? "EUR" }
    private var isOver: Bool { payload?.isOverBudget ?? false }

    var body: some View {
        face
            // Redacted while the wrist is down or the watch is locked.
            .privacySensitive()
            .widgetURL(WatchDomainOption.budget.link)
    }

    private func money(_ value: Double) -> String {
        value.formatted(.currency(code: code).precision(.fractionLength(0)))
    }

    /// Thousands compaction for the small slots ("12K EUR").
    private func compact(_ value: Double) -> String {
        guard value >= 10_000 else { return money(value) }
        let thousands = (value / 1000).formatted(.number.precision(.fractionLength(0)))
        return "\(thousands)K \(code)"
    }

    private var overLabel: Text { Text("over budget") }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular:
            circular
        case .accessoryCorner:
            Text(verbatim: spent.map { isOver ? "\(compact($0))!" : compact($0) } ?? "–")
                .font(Theme.Typography.cornerValue)
                .foregroundStyle(renderingMode.emphasis(isOver))
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel { Text("watch_budget") }
        case .accessoryRectangular:
            rectangular
        default:
            Label {
                Text(verbatim: spent.map(money) ?? "–")
            } icon: {
                Image(systemName: isOver ? UrgencyCue.symbol : WatchDomainOption.budget.systemImage)
            }
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let spent, let limit {
            Gauge(value: min(spent, limit), in: 0...limit) {
                Image(systemName: WatchDomainOption.budget.systemImage)
                    .accessibilityLabel(Text("watch_budget"))
            } currentValueLabel: {
                let percent = "\(Int((spent / limit * 100).rounded()))%"
                Text(verbatim: isOver ? "\(percent)!" : percent)
                    .font(Theme.Typography.circularCompact)
                    .foregroundStyle(renderingMode.emphasis(isOver))
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.compactMinimumScale)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        } else {
            VStack(spacing: 0) {
                Image(systemName: WatchDomainOption.budget.systemImage)
                    .font(Theme.Typography.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityLabel(Text("watch_budget"))
                Text(verbatim: spent.map(compact) ?? "–")
                    .font(Theme.Typography.circularCompact)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.compactMinimumScale)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: WatchDomainOption.budget.systemImage)
                    .font(Theme.Typography.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .accessibilityHidden(true)
                Text("watch_budget_month")
                    .font(Theme.Typography.header)
                    .lineLimit(1)
            }
            HStack(spacing: Theme.Spacing.s) {
                Text(verbatim: spent.map(money) ?? "–")
                    .font(Theme.Typography.metric)
                    .foregroundStyle(renderingMode.emphasis(isOver))
                    .lineLimit(1)
                    // 20 pt × 0.7 = 14 pt: still above the floor.
                    .minimumScaleFactor(0.7)
                    .widgetAccentable()
                if isOver {
                    UrgentGlyph(label: overLabel)
                        .font(Theme.Typography.header)
                }
            }
            if let spent, let limit {
                Gauge(value: min(spent, limit), in: 0...limit) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(isOver ? Theme.Tint.critical : Theme.Tint.budget)
                    .widgetAccentable()
                    .accessibilityHidden(true)
            } else if let name = payload?.snapshot.propertyName {
                Text(verbatim: name)
                    .font(Theme.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
