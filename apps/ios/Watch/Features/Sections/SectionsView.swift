import SwiftUI

// MARK: - Sections: the map of the app
//
// The sidebar of RootView's NavigationSplitView. On the watch the split
// view collapses into one stack, so this list is the level above every
// section: the app opens on Today, and the system's back button in the top
// leading corner of any section root returns here. Inside a section the
// same corner is the ordinary back chevron — one control, one meaning:
// "up one level".
//
// Groups (see `WatchRoute.sectionGroups`): Today; the everyday lists; the
// house's systems. Each row wears its section's tint, says in one live line
// what is going on there and carries a badge only when something needs
// the person. A row hands its section to RootView (`open`), which shows it
// in the detail column.

struct SectionsView: View {
    let open: (WatchSection) -> Void
    @Environment(WatchStore.self) private var store

    var body: some View {
        Group {
            if let payload = store.payload {
                List {
                    ForEach(Array(store.sectionGroups.enumerated()), id: \.offset) { _, group in
                        Section {
                            ForEach(group) { section in
                                Button {
                                    open(section)
                                } label: {
                                    SectionRow(section: section,
                                               status: SectionStatus(section: section, payload: payload, store: store),
                                               badge: badge(for: section, payload: payload))
                                }
                                .watchRowBackground(section.tint)
                            }
                        }
                    }
                }
            } else {
                EmptyStateView(systemImage: "iphone.and.arrow.forward",
                               titleKey: "watch_waiting_title", messageKey: "watch_waiting_msg")
            }
        }
        .navigationTitle(Text(verbatim: store.payload?.snapshot.propertyName ?? "PRVIO"))
        .skyGround()
        // The one moment location is asked for (once, ever): on the map of
        // the house, so the purpose — the right card on arriving home —
        // reads in context. Keyed on the payload so a home that syncs in
        // while this list is open still gets the ask.
        .task(id: store.payload != nil) {
            guard store.payload != nil else { return }
            WatchLocationPermission.shared.requestIfNeeded()
        }
    }

    private func badge(for section: WatchSection, payload: WatchPayload) -> WatchBadge? {
        switch section {
        case .module(let module):
            return module.badge(in: payload)
        case .page(.tasks):
            let overdue = store.openTasks.filter { $0.isOverdue == true }.count
            return overdue > 0 ? WatchBadge(count: overdue, isUrgent: false) : nil
        case .page(.plants):
            let thirsty = store.thirstyPlants.count
            return thirsty > 0 ? WatchBadge(count: thirsty, isUrgent: false) : nil
        case .page(.today):
            return nil
        }
    }
}

// MARK: - Live status line

/// One line of live state for a section row — words first, with a symbol when
/// the line is a call to act (never colour alone).
private struct SectionStatus {
    let text: Text
    /// A leading symbol for states that ask for the person (or confirm calm).
    var systemImage: String? = nil
    /// nil = secondary text; a tint only accompanies a symbol.
    var tint: Color? = nil
    /// Chat state stays off a resting wrist.
    var isPrivate = false
    /// Drives the cross-fade when the line changes.
    let identity: String

    init(text: Text, identity: String, systemImage: String? = nil,
         tint: Color? = nil, isPrivate: Bool = false) {
        self.text = text
        self.identity = identity
        self.systemImage = systemImage
        self.tint = tint
        self.isPrivate = isPrivate
    }

    init(section: WatchSection, payload: WatchPayload, store: WatchStore) {
        switch section {
        case .page(.today):  self = Self.today(store)
        case .page(.tasks):  self = Self.tasks(store)
        case .page(.plants): self = Self.plants(store)
        case .module(let module): self = SectionStatus(module: module, payload: payload)
        }
    }

    /// How the home is doing, in the dial's words.
    private static func today(_ store: WatchStore) -> SectionStatus {
        switch store.householdState {
        case .alarm:
            return SectionStatus(text: Text("watch_headline_alarm"), identity: "today-alarm",
                                 systemImage: "exclamationmark.triangle.fill", tint: WatchTheme.Tint.alarm)
        case .attention:
            return SectionStatus(text: Text("watch_headline_attention"), identity: "today-attention",
                                 systemImage: "exclamationmark.circle.fill", tint: WatchTheme.Tint.attention)
        case .calm:
            let open = store.openItemCount
            return open == 0
                ? SectionStatus(text: Text("watch_headline_clear"), identity: "today-clear")
                : SectionStatus(text: Text("watch_headline_open \(open)"), identity: "today-open-\(open)")
        }
    }

    /// Open and overdue, in the Tasks page's own summary words.
    private static func tasks(_ store: WatchStore) -> SectionStatus {
        let open = store.openTasks
        let overdue = open.filter { $0.isOverdue == true }.count
        if overdue > 0 {
            return SectionStatus(text: Text("watch_tasks_summary_overdue \(open.count) \(overdue)"),
                                 identity: "tasks-\(open.count)-\(overdue)",
                                 systemImage: "exclamationmark.circle.fill", tint: WatchTheme.Tint.attention)
        }
        if !open.isEmpty {
            return SectionStatus(text: Text("watch_headline_open \(open.count)"), identity: "tasks-\(open.count)")
        }
        return SectionStatus(text: Text("watch_hub_caught_up"), identity: "tasks-none",
                             systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.success)
    }

    /// Who is thirsty, else calm.
    private static func plants(_ store: WatchStore) -> SectionStatus {
        let thirsty = store.thirstyPlants.count
        if thirsty > 0 {
            return SectionStatus(text: Text("watch_plants_thirsty \(thirsty)"), identity: "plants-\(thirsty)",
                                 systemImage: "drop.fill", tint: WatchTheme.Tint.water)
        }
        return SectionStatus(text: Text("watch_hub_all_normal"), identity: "plants-ok",
                             systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.calm)
    }

    init(module: WatchModule, payload: WatchPayload) {
        switch module {
        case .shopping:   self = Self.shopping(payload)
        case .pantry:     self = Self.pantry(payload)
        case .deliveries: self = Self.deliveries(payload)
        case .messages:   self = Self.messages(payload)
        case .map:        self = Self.map(payload)
        case .controls:   self = Self.controls(payload)
        case .sensors:    self = Self.sensors(payload)
        case .emergency:  self = SectionStatus(text: Text("watch_hub_emergency_ready"), identity: "emergency")
        }
    }

    /// The first things on the list, by name — the badge already counts them.
    private static func shopping(_ payload: WatchPayload) -> SectionStatus {
        let names = payload.supplies
            .filter { !$0.isCompleted }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let line = names.prefix(3).joined(separator: ", ")
        return SectionStatus(text: Text(verbatim: line), identity: "shopping-\(line)")
    }

    /// What ran out (by name when it is one thing), else how much is stocked.
    private static func pantry(_ payload: WatchPayload) -> SectionStatus {
        let out = payload.pantry.filter { $0.quantity <= 0 }
        let symbol = "exclamationmark.circle.fill"
        switch out.count {
        case 0:
            let count = payload.pantry.count
            return SectionStatus(text: Text("watch_hub_in_stock \(count)"), identity: "pantry-stock-\(count)")
        case 1:
            let name = out[0].name
            return SectionStatus(text: Text("watch_hub_ran_out \(name)"), identity: "pantry-out-\(name)",
                             systemImage: symbol, tint: WatchTheme.Tint.attention)
        default:
            return SectionStatus(text: Text("watch_hub_ran_out_count \(out.count)"),
                             identity: "pantry-out-\(out.count)",
                             systemImage: symbol, tint: WatchTheme.Tint.attention)
        }
    }

    /// Today's arrivals lead; then what is still on its way; then "all in".
    private static func deliveries(_ payload: WatchPayload) -> SectionStatus {
        let today = payload.deliveries.filter(WatchRoute.isOutForDelivery).count
        let onTheWay = payload.deliveries.filter(WatchRoute.isDeliveryActive).count - today
        if today > 0 {
            return SectionStatus(text: Text("watch_hub_arriving_today \(today)"), identity: "parcels-today-\(today)",
                             systemImage: "shippingbox.fill", tint: WatchTheme.Tint.deliveries)
        }
        if onTheWay > 0 {
            return SectionStatus(text: Text("watch_hub_on_the_way \(onTheWay)"), identity: "parcels-way-\(onTheWay)")
        }
        return SectionStatus(text: Text("watch_hub_all_received"), identity: "parcels-in",
                         systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.success)
    }

    /// Unread count only — never a sender or a preview on the list.
    private static func messages(_ payload: WatchPayload) -> SectionStatus {
        let unread = payload.dmConversations.reduce(0) { $0 + max(0, $1.unread) }
        if unread > 0 {
            return SectionStatus(text: Text("watch_unread_count \(unread)"), identity: "dm-\(unread)", isPrivate: true)
        }
        return SectionStatus(text: Text("watch_hub_caught_up"), identity: "dm-none", isPrivate: true)
    }

    private static func map(_ payload: WatchPayload) -> SectionStatus {
        let name = payload.snapshot.propertyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? SectionStatus(text: Text("watch_page_desc_map"), identity: "map")
            : SectionStatus(text: Text(verbatim: name), identity: "map-\(name)")
    }

    /// Relays report on/off; covers do not, so a cover-only home names them.
    private static func controls(_ payload: WatchPayload) -> SectionStatus {
        let relays = payload.actuators.filter { $0.isOn != nil }
        let on = relays.filter { $0.isOn == true }.count
        if on > 0 {
            return SectionStatus(text: Text("watch_hub_devices_on \(on)"), identity: "controls-on-\(on)",
                             systemImage: "power", tint: WatchTheme.Tint.controls)
        }
        if !relays.isEmpty {
            return SectionStatus(text: Text("watch_hub_all_off"), identity: "controls-off")
        }
        let names = payload.actuators.prefix(2).map(\.name).joined(separator: ", ")
        return SectionStatus(text: Text(verbatim: names), identity: "controls-\(names)")
    }

    /// Critical is the only red on the list — and it says so in words.
    private static func sensors(_ payload: WatchPayload) -> SectionStatus {
        let alerting = payload.sensors.filter(\.isAlerting)
        if alerting.contains(where: \.isCritical) {
            return SectionStatus(text: Text("watch_sensor_critical"), identity: "sensors-critical",
                             systemImage: "exclamationmark.triangle.fill", tint: WatchTheme.Tint.alarm)
        }
        if !alerting.isEmpty {
            return SectionStatus(text: Text("watch_hub_to_check \(alerting.count)"),
                             identity: "sensors-check-\(alerting.count)",
                             systemImage: "exclamationmark.circle.fill", tint: WatchTheme.Tint.attention)
        }
        return SectionStatus(text: Text("watch_hub_all_normal"), identity: "sensors-ok",
                         systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.calm)
    }
}

// MARK: - Row

/// Tinted glyph, title, live status line, badge. The glyph's disc becomes a
/// stroke in Always On; the status dims there and cross-fades when it
/// changes (a plain fade under Reduce Motion).
private struct SectionRow: View {
    let section: WatchSection
    let status: SectionStatus
    let badge: WatchBadge?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchSkyAccent) private var skyAccent

    private var tint: Color { WatchTheme.harmonized(section.tint, with: skyAccent) }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            glyph
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(section.titleKey)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                statusLine
            }
            Spacer(minLength: 0)
            if let badge {
                CountBadge(count: badge.count, tint: section.tint, isUrgent: badge.isUrgent)
                    .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
            }
        }
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .animation(animation, value: badge)
        .animation(animation, value: status.identity)
        .accessibilityElement(children: .combine)
    }

    private var glyph: some View {
        Image(systemName: section.systemImage)
            .font(WatchTheme.Typography.glyph)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
            .background {
                if isLuminanceReduced {
                    Circle().strokeBorder(tint.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                          lineWidth: WatchTheme.Stroke.hairline)
                } else {
                    Circle().fill(tint.opacity(WatchTheme.Opacity.glyphFill))
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var statusLine: some View {
        let line = HStack(spacing: WatchTheme.Spacing.xxs) {
            if let symbol = status.systemImage {
                Image(systemName: symbol)
                    .foregroundStyle(status.tint ?? Color.secondary)
                    .accessibilityHidden(true)
            }
            status.text
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(WatchTheme.Typography.caption)
        .contentTransition(.opacity)
        .id(status.identity)
        .transition(.opacity)
        .watchAlwaysOnDimmed()

        if status.isPrivate {
            line.watchPrivate()
        } else {
            line
        }
    }
}
