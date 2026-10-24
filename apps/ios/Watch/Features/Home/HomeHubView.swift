import SwiftUI

// MARK: - Home hub
//
// Every surface beyond Today, Tasks and Plants as one calm list: each row
// wears its module's tint, says in one live line what is going on there
// ("2 arriving today", "Basil ran out") and carries a badge only when
// something needs the person. Visibility and order come from
// `WatchRoute.visibleModules` (the owner's `pageOrder`, data, scope) and
// nowhere else, so the hub, Today and deep links never disagree.
//
// Rows push `WatchDestination` values; RootView registers them on this
// stack. The bar keeps the system's default minimization: on watchOS the
// minimization API offers only `.automatic`, which is what a List already
// does.

struct HomeHubView: View {
    @Environment(WatchStore.self) private var store

    init() {}

    var body: some View {
        Group {
            if let payload = store.payload, !store.visibleModules.isEmpty {
                List {
                    ForEach(store.visibleModules) { module in
                        NavigationLink(value: WatchDestination.module(module)) {
                            HubRow(module: module,
                                   status: HubStatus(module: module, payload: payload),
                                   badge: module.badge(in: payload))
                        }
                        .watchRowBackground(module.tint)
                    }
                }
            } else {
                AllClearView(systemImage: WatchPage.home.systemImage)
            }
        }
        .navigationTitle(Text(WatchPage.home.titleKey))
        .skyGround()
        // The one moment location is asked for (once, ever): here, with a
        // home on screen, so the purpose — the right card on arriving home —
        // reads in context. Keyed on the payload so a home that syncs in
        // while this page is open still gets the ask.
        .task(id: store.payload != nil) {
            guard store.payload != nil else { return }
            WatchLocationPermission.shared.requestIfNeeded()
        }
    }
}

// MARK: - Live status line

/// One line of live state for a hub row — words first, with a symbol when
/// the line is a call to act (never colour alone).
private struct HubStatus {
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

    init(module: WatchModule, payload: WatchPayload) {
        switch module {
        case .shopping:   self = Self.shopping(payload)
        case .pantry:     self = Self.pantry(payload)
        case .deliveries: self = Self.deliveries(payload)
        case .messages:   self = Self.messages(payload)
        case .map:        self = Self.map(payload)
        case .controls:   self = Self.controls(payload)
        case .sensors:    self = Self.sensors(payload)
        case .emergency:  self = HubStatus(text: Text("watch_hub_emergency_ready"), identity: "emergency")
        }
    }

    /// The first things on the list, by name — the badge already counts them.
    private static func shopping(_ payload: WatchPayload) -> HubStatus {
        let names = payload.supplies
            .filter { !$0.isCompleted }
            .map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let line = names.prefix(3).joined(separator: ", ")
        return HubStatus(text: Text(verbatim: line), identity: "shopping-\(line)")
    }

    /// What ran out (by name when it is one thing), else how much is stocked.
    private static func pantry(_ payload: WatchPayload) -> HubStatus {
        let out = payload.pantry.filter { $0.quantity <= 0 }
        let symbol = "exclamationmark.circle.fill"
        switch out.count {
        case 0:
            let count = payload.pantry.count
            return HubStatus(text: Text("watch_hub_in_stock \(count)"), identity: "pantry-stock-\(count)")
        case 1:
            let name = out[0].name
            return HubStatus(text: Text("watch_hub_ran_out \(name)"), identity: "pantry-out-\(name)",
                             systemImage: symbol, tint: WatchTheme.Tint.attention)
        default:
            return HubStatus(text: Text("watch_hub_ran_out_count \(out.count)"),
                             identity: "pantry-out-\(out.count)",
                             systemImage: symbol, tint: WatchTheme.Tint.attention)
        }
    }

    /// Today's arrivals lead; then what is still on its way; then "all in".
    private static func deliveries(_ payload: WatchPayload) -> HubStatus {
        let today = payload.deliveries.filter(WatchRoute.isOutForDelivery).count
        let onTheWay = payload.deliveries.filter(WatchRoute.isDeliveryActive).count - today
        if today > 0 {
            return HubStatus(text: Text("watch_hub_arriving_today \(today)"), identity: "parcels-today-\(today)",
                             systemImage: "shippingbox.fill", tint: WatchTheme.Tint.deliveries)
        }
        if onTheWay > 0 {
            return HubStatus(text: Text("watch_hub_on_the_way \(onTheWay)"), identity: "parcels-way-\(onTheWay)")
        }
        return HubStatus(text: Text("watch_hub_all_received"), identity: "parcels-in",
                         systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.success)
    }

    /// Unread count only — never a sender or a preview on the hub.
    private static func messages(_ payload: WatchPayload) -> HubStatus {
        let unread = payload.dmConversations.reduce(0) { $0 + max(0, $1.unread) }
        if unread > 0 {
            return HubStatus(text: Text("watch_unread_count \(unread)"), identity: "dm-\(unread)", isPrivate: true)
        }
        return HubStatus(text: Text("watch_hub_caught_up"), identity: "dm-none", isPrivate: true)
    }

    private static func map(_ payload: WatchPayload) -> HubStatus {
        let name = payload.snapshot.propertyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty
            ? HubStatus(text: Text("watch_page_desc_map"), identity: "map")
            : HubStatus(text: Text(verbatim: name), identity: "map-\(name)")
    }

    /// Relays report on/off; covers do not, so a cover-only home names them.
    private static func controls(_ payload: WatchPayload) -> HubStatus {
        let relays = payload.actuators.filter { $0.isOn != nil }
        let on = relays.filter { $0.isOn == true }.count
        if on > 0 {
            return HubStatus(text: Text("watch_hub_devices_on \(on)"), identity: "controls-on-\(on)",
                             systemImage: "power", tint: WatchTheme.Tint.controls)
        }
        if !relays.isEmpty {
            return HubStatus(text: Text("watch_hub_all_off"), identity: "controls-off")
        }
        let names = payload.actuators.prefix(2).map(\.name).joined(separator: ", ")
        return HubStatus(text: Text(verbatim: names), identity: "controls-\(names)")
    }

    /// Critical is the only red on the hub — and it says so in words.
    private static func sensors(_ payload: WatchPayload) -> HubStatus {
        let alerting = payload.sensors.filter(\.isAlerting)
        if alerting.contains(where: \.isCritical) {
            return HubStatus(text: Text("watch_sensor_critical"), identity: "sensors-critical",
                             systemImage: "exclamationmark.triangle.fill", tint: WatchTheme.Tint.alarm)
        }
        if !alerting.isEmpty {
            return HubStatus(text: Text("watch_hub_to_check \(alerting.count)"),
                             identity: "sensors-check-\(alerting.count)",
                             systemImage: "exclamationmark.circle.fill", tint: WatchTheme.Tint.attention)
        }
        return HubStatus(text: Text("watch_hub_all_normal"), identity: "sensors-ok",
                         systemImage: "checkmark.circle.fill", tint: WatchTheme.Tint.calm)
    }
}

// MARK: - Row

/// Tinted glyph, title, live status line, badge. The glyph's disc becomes a
/// stroke in Always On; the status dims there and cross-fades when it
/// changes (a plain fade under Reduce Motion).
private struct HubRow: View {
    let module: WatchModule
    let status: HubStatus
    let badge: WatchBadge?

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.watchSkyAccent) private var skyAccent

    private var tint: Color { WatchTheme.harmonized(module.tint, with: skyAccent) }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            glyph
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(module.titleKey)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                statusLine
            }
            Spacer(minLength: 0)
            if let badge {
                CountBadge(count: badge.count, tint: module.tint, isUrgent: badge.isUrgent)
                    .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
            }
        }
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .animation(animation, value: badge)
        .animation(animation, value: status.identity)
        .accessibilityElement(children: .combine)
    }

    private var glyph: some View {
        Image(systemName: module.systemImage)
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
