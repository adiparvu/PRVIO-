import AppIntents
import RelevanceKit
import SwiftUI
import WidgetKit

// MARK: - "Now at home" (Smart Stack relevance card)
//
// A RelevanceConfiguration widget (watchOS 26+): it is never pinned, it only
// appears when one of NowRelevance's clues matches — a running work session,
// a parcel out for delivery, the morning watering window, the evening return
// home — and stays away otherwise. It shows the single Next Up item with its
// one-tap action, and the day's brief under it.
//
// `associatedKind` lets the card take the place of a pinned Status card
// instead of stacking a second household summary next to it.

struct PRVIONowWidget: Widget {
    var body: some WidgetConfiguration {
        RelevanceConfiguration(kind: ComplicationKind.now, provider: NowRelevanceProvider()) { entry in
            NowCard(entry: entry)
                .complicationGround(entry.sky)
        }
        .configurationDisplayName(Text("watch_now_title"))
        .description(Text("watch_now_desc"))
        .supportedFamilies([.accessoryRectangular])
        .associatedKind(ComplicationKind.status)
    }
}

// MARK: - Entry

/// What the card shows, resolved once in the provider so the view stays a
/// pure function of plain values.
enum NowItem: Equatable, Sendable {
    case task(id: UUID, title: String, isOverdue: Bool)
    case plant(id: UUID, name: String, othersThirsty: Int)
    case delivery(id: UUID, title: String, eta: String?)
    case session(WatchWorkSession)
}

struct NowEntry: RelevanceEntry {
    let date: Date
    let moment: NowMoment
    /// nil = nothing to do: the card says so warmly instead of hiding.
    let item: NowItem?
    let brief: String?
    let state: ComplicationHousehold
    let sky: ComplicationSky

    /// Shape-only content for the gallery and placeholders: no invented
    /// household names, just the calm state.
    static func sample(at date: Date) -> NowEntry {
        NowEntry(date: date, moment: .homecoming, item: nil, brief: nil,
                 state: .calm, sky: .fallback)
    }

    static func resolve(moment: NowMoment,
                        payload: WatchPayload?,
                        session: WatchWorkSession?,
                        at date: Date) -> NowEntry {
        NowEntry(date: date,
                 moment: moment,
                 item: item(for: moment, payload: payload, session: session),
                 brief: ComplicationBrief.line(payload?.briefHeadline),
                 state: ComplicationHousehold(payload),
                 sky: ComplicationSky.ground(payload, accent: nil))
    }

    /// The moment's own subject first; when it is already gone (plant
    /// watered, parcel in), the general Next Up order from WatchRoute:
    /// overdue task → thirsty plant → parcel out for delivery → next task.
    private static func item(for moment: NowMoment,
                             payload: WatchPayload?,
                             session: WatchWorkSession?) -> NowItem? {
        switch moment {
        case .session:
            if let session { return .session(session) }
        case .watering:
            if let plant = plantItem(payload) { return plant }
        case .delivery:
            if let parcel = deliveryItem(payload) { return parcel }
        case .homecoming:
            break
        }
        return nextUp(payload)
    }

    private static func nextUp(_ payload: WatchPayload?) -> NowItem? {
        guard let payload else { return nil }
        let open = payload.showsTasks ? payload.openTasksByUrgency : []
        if let overdue = open.first, overdue.isOverdue == true {
            return .task(id: overdue.id, title: overdue.title, isOverdue: true)
        }
        if let plant = plantItem(payload) { return plant }
        if let parcel = deliveryItem(payload) { return parcel }
        if let next = open.first {
            return .task(id: next.id, title: next.title, isOverdue: false)
        }
        return nil
    }

    private static func plantItem(_ payload: WatchPayload?) -> NowItem? {
        guard let payload, payload.showsPlants, let plant = payload.firstThirstyPlant else { return nil }
        let thirsty = payload.plants.filter(\.needsWatering).count
        return .plant(id: plant.id, name: plant.name, othersThirsty: max(0, thirsty - 1))
    }

    private static func deliveryItem(_ payload: WatchPayload?) -> NowItem? {
        guard let payload, payload.showsDeliveries, let parcel = payload.outForDelivery.first else { return nil }
        return .delivery(id: parcel.id, title: parcel.title, eta: parcel.eta)
    }
}

// MARK: - Provider

struct NowRelevanceProvider: RelevanceEntriesProvider {
    func relevance() async -> WidgetRelevance<PRVIONowIntent> {
        WidgetRelevance(NowRelevance.attributes(payload: ComplicationStore.payload(),
                                                session: ComplicationStore.session()))
    }

    func entry(configuration: PRVIONowIntent, context: Context) async throws -> NowEntry {
        let now = Date.now
        let payload = ComplicationStore.payload()
        if context.isPreview && payload == nil {
            return .sample(at: now)
        }
        return .resolve(moment: configuration.moment, payload: payload,
                        session: ComplicationStore.session(), at: now)
    }

    func placeholder(context: Context) -> NowEntry {
        .sample(at: .now)
    }
}

// MARK: - Card

struct NowCard: View {
    let entry: NowEntry

    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    /// Long enough for any real session; the timer stops counting after it.
    private static let timerSpan: TimeInterval = 24 * 3600

    var body: some View {
        // Taller layouts first; the first one whose ideal height fits wins,
        // so a long title or brief gives way line by line instead of clipping.
        ViewThatFits(in: .vertical) {
            layout(titleLines: 2, briefLines: 2)
            layout(titleLines: 1, briefLines: 2)
            layout(titleLines: 1, briefLines: 1)
            layout(titleLines: 1, briefLines: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(link)
    }

    private func layout(titleLines: Int, briefLines: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            caption
            if let item = entry.item {
                itemRow(item, titleLines: titleLines)
            } else {
                allCalm
            }
            if briefLines > 0, let brief = entry.brief {
                Text(verbatim: brief)
                    .font(Theme.Typography.brief)
                    .foregroundStyle(.secondary)
                    .lineLimit(briefLines)
                    .truncationMode(.tail)
            }
        }
    }

    // MARK: Caption — what kind of moment, as a symbol and a word

    private var caption: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: captionSymbol)
                .font(Theme.Typography.glyph)
                .foregroundStyle(captionTint)
                .widgetAccentable()
                .accessibilityHidden(true)
            captionText
                .font(Theme.Typography.glyph)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: Theme.Spacing.s)
            if entry.state != .calm {
                Image(systemName: entry.state.systemImage)
                    .font(Theme.Typography.glyph)
                    .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(entry.state.tint) : AnyShapeStyle(.secondary))
                    .widgetAccentable()
                    .accessibilityLabel(entry.state.word)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var captionSymbol: String {
        switch entry.item {
        case .task(_, _, true):  return UrgencyCue.symbol
        case .task:              return "checklist"
        case .plant:             return "drop.fill"
        case .delivery:          return "shippingbox.fill"
        case .session(let s):    return s.isPaused ? "pause.fill" : "timer"
        case nil:                return "house.fill"
        }
    }

    private var captionTint: AnyShapeStyle {
        guard renderingMode == .fullColor else { return AnyShapeStyle(.primary) }
        switch entry.item {
        case .task(_, _, true):  return AnyShapeStyle(Theme.Tint.attention)
        case .task:              return AnyShapeStyle(Theme.Tint.tasks)
        case .plant:             return AnyShapeStyle(Theme.Tint.water)
        case .delivery:          return AnyShapeStyle(Theme.Tint.deliveries)
        case .session(let s):    return AnyShapeStyle(s.isPaused ? Theme.Tint.paused : Theme.Tint.session)
        case nil:                return AnyShapeStyle(Theme.Tint.calm)
        }
    }

    private var captionText: Text {
        switch entry.item {
        case .task(_, _, true):  return Text("watch_overdue")
        case .task:              return Text("watch_next_up")
        case .plant:             return Text("watch_water")
        case .delivery:          return Text("Out for delivery")
        case .session(let s):    return s.isPaused ? Text("watch_session_paused") : Text("Work session")
        case nil:                return Text("watch_now_title")
        }
    }

    // MARK: The one item, with its one action

    @ViewBuilder
    private func itemRow(_ item: NowItem, titleLines: Int) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title(item))
                    .font(Theme.Typography.nowTitle)
                    .lineLimit(titleLines)
                    .truncationMode(.tail)
                if let detail = detail(item) {
                    detail
                        .font(Theme.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            trailing(item)
        }
    }

    private func title(_ item: NowItem) -> String {
        switch item {
        case .task(_, let title, _):     return title
        case .plant(_, let name, _):     return name
        case .delivery(_, let title, _): return title
        case .session(let session):      return session.title
        }
    }

    private func detail(_ item: NowItem) -> Text? {
        switch item {
        case .plant(_, _, let others) where others > 0:
            return Text("watch_payload_plants \(others + 1)")
        case .delivery(_, _, let eta?):
            return Text(verbatim: eta)
        default:
            return nil
        }
    }

    @ViewBuilder
    private func trailing(_ item: NowItem) -> some View {
        switch item {
        case .task(let id, _, _):
            action(CompleteTopTaskIntent(taskId: id.uuidString),
                   symbol: "checkmark.circle", label: Text("watch_complete"))
        case .plant(let id, _, _):
            action(WaterPlantIntent(plantId: id.uuidString),
                   symbol: "drop.circle", label: Text("watch_water_now"))
        case .delivery(let id, _, _):
            action(MarkDeliveryReceivedIntent(deliveryId: id.uuidString),
                   symbol: "checkmark.circle", label: Text("watch_delivery_received"))
        case .session(let session):
            clock(session)
        }
    }

    private func action<I: AppIntent>(_ intent: I, symbol: String, label: Text) -> some View {
        Button(intent: intent) {
            Image(systemName: symbol)
                .font(Theme.Typography.action)
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Same clock as the session complication: live while running, frozen at
    /// the entry date while paused (the caption states the pause in words).
    private func clock(_ session: WatchWorkSession) -> some View {
        let start = entry.date.addingTimeInterval(-session.elapsed(at: entry.date))
        return Text(timerInterval: start...start.addingTimeInterval(Self.timerSpan),
                    pauseTime: session.isPaused ? entry.date : nil,
                    countsDown: false)
            .font(Theme.Typography.headerValue)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
            .foregroundStyle(renderingMode.emphasis(session.isPaused, color: Theme.Tint.paused))
            .widgetAccentable()
            .lineLimit(1)
            .fixedSize()
    }

    private var allCalm: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "checkmark.circle.fill")
                .font(Theme.Typography.glyph)
                .foregroundStyle(renderingMode == .fullColor ? AnyShapeStyle(Theme.Tint.calm) : AnyShapeStyle(.primary))
                .widgetAccentable()
                .accessibilityHidden(true)
            Text("watch_headline_clear")
                .font(Theme.Typography.nowTitle)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Deep link — the page that owns the item

    private var link: URL? {
        switch entry.item {
        case .task:            return ComplicationLink.tasks
        case .plant:           return ComplicationLink.plants
        case .delivery:        return ComplicationLink.deliveries
        case .session, nil:    return ComplicationLink.today
        }
    }
}
