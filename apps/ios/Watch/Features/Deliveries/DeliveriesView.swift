import SwiftUI

// MARK: - Deliveries: every parcel as a journey
//
// A parcel is a short trip — ordered → out for delivery → delivered — so
// each one is drawn as that trip: a three-stop line in the list, a full
// timeline in the detail. Today's arrivals (out for delivery) lead, then
// what is still on its way, then the settled ones. Marking a parcel
// received completes its line in place (the store plays `.success`); the
// detail stays open so the person sees the trip finish.
//
// Status words reuse the phone's catalog keys (`Expected`, `Out for
// delivery`, `Delivered`, `Missed`, `Returned`); an unknown future status
// shows raw rather than disappearing.

/// Pushes one parcel's detail on whichever stack hosts Deliveries.
/// Feature-specific so it never collides on the shared Home stack.
struct DeliveryRoute: Hashable {
    let id: UUID
}

struct DeliveriesView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 10

    init() {}

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    private var all: [DeliveryCatalogEntry] { store.payload?.deliveries ?? [] }

    /// Today first, then on the way, then settled — capped as a whole so the
    /// most relevant parcels always make the cut.
    private var groups: [DeliveryGroup] {
        var budget = Self.rowLimit
        return DeliverySection.allCases.compactMap { section in
            let parcels = Array(all.filter(section.contains).prefix(budget))
            budget -= parcels.count
            return parcels.isEmpty ? nil : DeliveryGroup(section: section, parcels: parcels)
        }
    }

    var body: some View {
        let groups = groups
        let shown = groups.reduce(0) { $0 + $1.parcels.count }
        Group {
            if groups.isEmpty {
                AllClearView(systemImage: WatchModule.deliveries.systemImage)
            } else {
                List {
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.parcels, id: \.id) { parcel in
                                row(parcel)
                            }
                        } header: {
                            SectionHeader(group.section.titleKey)
                        }
                    }
                    if all.count > shown {
                        Text("watch_more_on_iphone \(all.count - shown)")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .watchAlwaysOnDimmed()
                    }
                }
            }
        }
        .navigationTitle(Text(WatchModule.deliveries.titleKey))
        .skyGround()
        .navigationDestination(for: DeliveryRoute.self) { route in
            DeliveryDetailView(id: route.id)
        }
    }

    private func row(_ parcel: DeliveryCatalogEntry) -> some View {
        NavigationLink(value: DeliveryRoute(id: parcel.id)) {
            DeliveryRow(parcel: parcel)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if WatchRoute.isDeliveryActive(parcel) {
                Button {
                    withAnimation(animation) { store.markDeliveryReceived(parcel.id) }
                } label: {
                    Label("watch_delivery_received", systemImage: "checkmark.circle.fill")
                }
                .tint(WatchTheme.Tint.success)
            }
        }
        .watchRowBackground(WatchTheme.Tint.deliveries)
    }
}

// MARK: - Sections

private struct DeliveryGroup: Identifiable {
    let section: DeliverySection
    let parcels: [DeliveryCatalogEntry]
    var id: DeliverySection { section }
}

private enum DeliverySection: CaseIterable, Hashable {
    case today, onTheWay, settled

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:    return "watch_menu_today"
        case .onTheWay: return "watch_delivery_on_the_way"
        case .settled:  return "watch_delivery_earlier"
        }
    }

    func contains(_ parcel: DeliveryCatalogEntry) -> Bool {
        switch self {
        case .today:    return WatchRoute.isOutForDelivery(parcel)
        case .onTheWay: return WatchRoute.isDeliveryActive(parcel) && !WatchRoute.isOutForDelivery(parcel)
        case .settled:  return !WatchRoute.isDeliveryActive(parcel)
        }
    }
}

// MARK: - The journey (shared by row and detail)

/// Where a parcel is on its three-stop trip, and how the trip ended.
private struct DeliveryJourney: Equatable {
    enum Ending: Equatable { case underway, delivered, missed, returned }

    /// Last stop reached: 0 ordered, 1 out for delivery, 2 the final stop.
    let reached: Int
    let ending: Ending
    let status: String

    static let stopCount = 3

    init(status: String) {
        self.status = status
        switch status {
        case "out_for_delivery": reached = 1; ending = .underway
        case "delivered":        reached = 2; ending = .delivered
        case "missed":           reached = 2; ending = .missed
        case "returned":         reached = 2; ending = .returned
        default:                 reached = 0; ending = .underway
        }
    }

    /// The trip's colour so far: deliveries blue on the way, green home,
    /// amber when the courier missed (stated plainly, never red shouting).
    var tint: Color {
        switch ending {
        case .underway:  return WatchTheme.Tint.deliveries
        case .delivered: return WatchTheme.Tint.success
        case .missed:    return WatchTheme.Tint.attention
        case .returned:  return WatchTheme.Tint.neutral
        }
    }

    /// The parcel's state as symbol + word.
    var state: StateLabel {
        StateLabel(statusKey, systemImage: statusSymbol, tint: tint)
    }

    var statusKey: LocalizedStringKey {
        switch status {
        case "expected":         return "Expected"
        case "out_for_delivery": return "Out for delivery"
        case "delivered":        return "Delivered"
        case "missed":           return "Missed"
        case "returned":         return "Returned"
        default:                 return LocalizedStringKey(status)
        }
    }

    var statusSymbol: String {
        switch status {
        case "out_for_delivery": return "box.truck.fill"
        case "delivered":        return "checkmark.circle.fill"
        case "missed":           return "exclamationmark.circle.fill"
        case "returned":         return "arrow.uturn.backward.circle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    /// The three stops, the last one named by how the trip ended.
    var stops: [Stop] {
        [
            Stop(index: 0, titleKey: "watch_delivery_ordered", systemImage: "shippingbox.fill"),
            Stop(index: 1, titleKey: "Out for delivery", systemImage: "box.truck.fill"),
            Stop(index: 2,
                 titleKey: ending == .missed ? "Missed" : ending == .returned ? "Returned" : "Delivered",
                 systemImage: ending == .missed ? "exclamationmark.circle.fill"
                     : ending == .returned ? "arrow.uturn.backward.circle.fill" : "house.fill"),
        ]
    }

    struct Stop: Identifiable {
        let index: Int
        let titleKey: LocalizedStringKey
        let systemImage: String
        var id: Int { index }
    }

    func isReached(_ index: Int) -> Bool { index <= reached }

    /// "Step 2 of 3" for VoiceOver.
    var progressText: Text {
        Text("watch_delivery_step_ax \(reached + 1) \(Self.stopCount)")
    }
}

// MARK: - Row

private struct DeliveryRow: View {
    let parcel: DeliveryCatalogEntry

    private var journey: DeliveryJourney { DeliveryJourney(status: parcel.status) }

    private var detail: String {
        [parcel.carrier, parcel.eta]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
            Text(verbatim: parcel.title)
                .font(WatchTheme.Typography.rowTitle)
                .lineLimit(2)
            JourneyLine(journey: journey)
            HStack(spacing: WatchTheme.Spacing.xs) {
                journey.state
                if !detail.isEmpty, WatchRoute.isDeliveryActive(parcel) {
                    Text(verbatim: detail)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .watchAlwaysOnDimmed()
                }
            }
        }
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: parcel.title))
        .accessibilityValue(Text(journey.statusKey) + Text(verbatim: ". ") + journey.progressText)
    }
}

/// The compact trip: three stops joined by a line, filled as far as the
/// parcel has come. Strokes only in Always On; moves with the snappy
/// spring (a cross-fade under Reduce Motion).
private struct JourneyLine: View {
    let journey: DeliveryJourney

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(journey.stops) { stop in
                if stop.index > 0 {
                    Capsule()
                        .fill(journey.isReached(stop.index) ? journey.tint : Color.secondary.opacity(0.35))
                        .frame(height: WatchTheme.Spacing.xxs)
                        .frame(maxWidth: .infinity)
                }
                node(reached: journey.isReached(stop.index))
            }
        }
        .animation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion),
                   value: journey)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func node(reached: Bool) -> some View {
        let side = WatchTheme.Spacing.m
        if reached, !isLuminanceReduced {
            Circle().fill(journey.tint).frame(width: side, height: side)
        } else {
            Circle()
                .strokeBorder(reached ? journey.tint.opacity(WatchTheme.AlwaysOn.strokeOpacity)
                                      : Color.secondary.opacity(0.5),
                              lineWidth: WatchTheme.Stroke.hairlineIncreased)
                .frame(width: side, height: side)
        }
    }
}

// MARK: - Detail

private struct DeliveryDetailView: View {
    let id: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Read live from the store so "Received" redraws the trip in place.
    private var parcel: DeliveryCatalogEntry? {
        store.payload?.deliveries.first { $0.id == id }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if let parcel {
                content(parcel)
            } else {
                AllClearView(systemImage: WatchModule.deliveries.systemImage)
            }
        }
        .navigationTitle(Text(WatchModule.deliveries.titleKey))
        .skyGround()
        // The parcel can vanish under the open detail when the phone pushes.
        .onChange(of: parcel == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func content(_ parcel: DeliveryCatalogEntry) -> some View {
        let journey = DeliveryJourney(status: parcel.status)
        return ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xl) {
                Text(verbatim: parcel.title)
                    .font(WatchTheme.Typography.hero)
                    .fixedSize(horizontal: false, vertical: true)

                JourneyTimeline(journey: journey, eta: trimmed(parcel.eta))

                if let carrier = trimmed(parcel.carrier) {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                        Text("Courier")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: carrier)
                            .font(WatchTheme.Typography.body)
                    }
                    .accessibilityElement(children: .combine)
                    .watchAlwaysOnDimmed()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WatchTheme.Spacing.xs)
        }
        .toolbar {
            if WatchRoute.isDeliveryActive(parcel) {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        // The intent plays `.success`; the trip completes in place.
                        withAnimation(animation) { store.markDeliveryReceived(parcel.id) }
                    } label: {
                        Label("watch_delivery_received", systemImage: "checkmark.circle.fill")
                    }
                    .tint(WatchTheme.Tint.success)
                }
            }
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

/// The full trip, top to bottom: each stop a glyph on the line with its
/// name; the ETA rides under "Out for delivery" while the parcel is
/// underway. The final stop bounces once when the trip completes (static
/// under Reduce Motion and in Always On). VoiceOver reads one sentence.
private struct JourneyTimeline: View {
    let journey: DeliveryJourney
    let eta: String?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animates: Bool { !reduceMotion && !isLuminanceReduced }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(journey.stops) { stop in
                HStack(alignment: .top, spacing: WatchTheme.Spacing.m) {
                    VStack(spacing: 0) {
                        glyph(stop)
                        if stop.index < DeliveryJourney.stopCount - 1 {
                            Capsule()
                                .fill(journey.isReached(stop.index + 1)
                                      ? journey.tint : Color.secondary.opacity(0.35))
                                .frame(width: WatchTheme.Spacing.xxs, height: WatchTheme.Spacing.xl)
                        }
                    }
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                        Text(stop.titleKey)
                            .font(stop.index == journey.reached
                                  ? WatchTheme.Typography.cardTitle
                                  : WatchTheme.Typography.body)
                            .foregroundStyle(journey.isReached(stop.index) ? Color.primary : Color.secondary)
                        if stop.index == 1, journey.ending == .underway, let eta {
                            // The phone pre-formats the ETA; the catalog key frames it.
                            Text("ETA: \(eta)")
                                .font(WatchTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .watchAlwaysOnDimmed()
                        }
                    }
                    .padding(.top, WatchTheme.Spacing.xxs)
                }
            }
        }
        .animation(WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion),
                   value: journey)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(journey.statusKey))
        .accessibilityValue(journey.progressText)
    }

    private func glyph(_ stop: DeliveryJourney.Stop) -> some View {
        let reached = journey.isReached(stop.index)
        let isFinal = stop.index == DeliveryJourney.stopCount - 1
        return Image(systemName: stop.systemImage)
            .font(WatchTheme.Typography.glyph)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(reached ? journey.tint : Color.secondary)
            .contentTransition(reduceMotion ? ContentTransition.opacity : ContentTransition.symbolEffect(.replace))
            // bounce = done: the trip just reached its last stop.
            .symbolEffect(.bounce, value: isFinal && reached && animates)
            .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
            .background {
                if reached && !isLuminanceReduced {
                    Circle().fill(journey.tint.opacity(WatchTheme.Opacity.glyphFill))
                } else {
                    Circle().strokeBorder(
                        (reached ? journey.tint : Color.secondary)
                            .opacity(reached ? WatchTheme.AlwaysOn.strokeOpacity : 0.4),
                        lineWidth: WatchTheme.Stroke.hairline)
                }
            }
    }
}
