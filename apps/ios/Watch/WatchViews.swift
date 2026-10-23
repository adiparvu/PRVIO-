import SwiftUI
import MapKit

// MARK: - Pages
//
// Watch V12 complete: the wrist now spans glance + list catalogs (today,
// tasks, plants, shopping, pantry, deliveries, map), smart control (relays +
// covers), a live sensor glance, and an Emergency SOS page — all gated on the
// data actually existing so no page ever promises something the home can't do.
// Every control maps to a real device write or a real tel: call; nothing on
// the watch is a decorative stub.

enum WatchPage: Hashable {
    case today, messages, tasks, plants, shopping, pantry, deliveries, map
    case controls, sensors, emergency
}

// MARK: - Double tap
//
// The double-tap gesture fires a screen's PRIMARY action without touching
// it. HIG: never set a primary action in a view with a list, a scroll view
// or vertical tabs — there double tap belongs to the system's own
// navigation (scrolling, paging). The root pager is .verticalPage and every
// list/detail page scrolls, so the only legal host is a screen that cannot
// scroll at all. The name says so and the extension is fileprivate, so no
// list row, toolbar or ScrollView elsewhere can quietly reclaim it.
// watchOS 11+ only; earlier systems simply ignore it.
fileprivate extension View {
    @ViewBuilder
    func primaryDoubleTapOnFixedScreen() -> some View {
        if #available(watchOS 11.0, *) {
            self.handGestureShortcut(.primaryAction)
        } else {
            self
        }
    }
}

// MARK: - Wrist design language
//
// The dialect the whole watch app speaks — Athlytic's dense dashboard,
// Gentler Streak's soft gradient cards, Things' rounded typographic
// hierarchy, Waterllama's act-then-celebrate feedback. One place, so every
// page stays coherent.

enum WatchDesign {
    /// Soft card fill: the domain colour breathing through dark glass.
    static func cardFill(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.32), color.opacity(0.10)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func score(_ value: Int) -> Color {
        switch value {
        case 80...:   return .green
        case 60..<80: return .yellow
        default:      return .orange
        }
    }
}

/// The soft rounded card every module sits in. Cards are CONTENT, not
/// chrome: HIG keeps Liquid Glass out of the content layer (it belongs to
/// the system toolbar and controls floating above), so on every watchOS the
/// card wears the same standard fill the list rows use — the domain tint
/// breathing through, never a glass pane competing with the real chrome.
private struct WatchCard<Content: View>: View {
    var tint: Color = .gray
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchDesign.cardFill(tint),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Staggered entrance — cards breathe in one after another. Sits out
/// entirely under Reduce Motion.
private struct Entrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.spring(duration: 0.5).delay(Double(index) * 0.06)) {
                    shown = true
                }
            }
    }
}

private extension View {
    func entrance(_ index: Int) -> some View { modifier(Entrance(index: index)) }
}

// MARK: - Root: vertical pages, or the sync prompt

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store
    @State private var selection: WatchPage = .today

    /// Default order when the phone hasn't sent a preference yet.
    private static let defaultOrder = ["tasks", "plants", "shopping", "pantry", "deliveries", "map"]

    /// The payload's page order, deduped defensively — a payload cached by
    /// an older phone build can carry duplicate keys, and two ForEach rows
    /// with the same identity is undefined behavior (crashes on device).
    private static func orderedPages(_ payload: WatchPayload) -> [String] {
        var seen = Set<String>()
        return (payload.pageOrder ?? defaultOrder).filter { seen.insert($0).inserted }
    }

    /// Advertising an NSUserActivity whose type isn't declared in the
    /// built Info.plist throws NSInternalInconsistencyException at first
    /// render on a real watch ("opens and instantly exits"). The plist now
    /// declares it, and this runtime check makes the crash impossible even
    /// if a build configuration ever drops the key again.
    private static let handoffDeclared: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])?
            .contains("com.prvio.page") == true

    var body: some View {
        Group {
            if let payload = store.payload {
                pages(payload)
                    .tabViewStyle(.verticalPage)
                    // One atmosphere for every page ground (moodPageGround reads
                    // it); nil until the phone delivers a mood with the payload.
                    .environment(\.watchMood, store.mood)
                    // The real sky (F4) rides the same payload and, when
                    // present, wins over the mood wash on every page ground.
                    .environment(\.watchSky, WatchSky(payload: payload))
                    .onOpenURL { url in
                        // Complication taps: prvio://tasks, prvio://plants, …
                        switch url.host {
                        case "tasks":                  selection = .tasks
                        case "plants":                 selection = .plants
                        case "shopping", "supplies":   selection = .shopping
                        case "pantry":                 selection = .pantry
                        case "deliveries", "packages": selection = .deliveries
                        default:                       selection = .today
                        }
                    }
            } else {
                waiting
            }
        }
        // The launch breadcrumb's other half: a committed first frame means
        // this launch SURVIVED — a sentinel still set at the next launch is
        // therefore a death the exception handler couldn't see.
        .onAppear { WatchCrashRecorder.firstFrameRendered() }
    }

    @ViewBuilder
    private func pages(_ payload: WatchPayload) -> some View {
        let tabs = TabView(selection: $selection) {
            TodayGlance(payload: payload, selection: $selection)
                .tag(WatchPage.today)
            // The wrist inbox rides right after Today (communication first),
            // gated on real conversations existing — it is not part of the
            // owner-ordered page set, so old iPhone preferences can't hide it.
            if !payload.dmConversations.isEmpty {
                MessagesPage(conversations: payload.dmConversations)
                    .tag(WatchPage.messages)
            }
            // The owner's pages, in the owner's order (chosen on the
            // iPhone). Data-gating stays: an enabled page with nothing
            // to show still steps aside.
            ForEach(Self.orderedPages(payload), id: \.self) { key in
                page(for: key, payload: payload)
            }
            // Smart-home surfaces ride after the owner's pages, gated on real
            // devices existing — the wrist never shows an empty control panel.
            if !payload.actuators.isEmpty {
                ControlsPage(actuators: payload.actuators)
                    .tag(WatchPage.controls)
            }
            if !payload.sensors.isEmpty {
                SensorsPage(sensors: payload.sensors)
                    .tag(WatchPage.sensors)
            }
            // The emergency page also exists whenever the property is known —
            // "Alert the family" must work even before any shutoff plan is
            // written; steps/contacts still only render when they exist.
            if Self.showsEmergency(payload) {
                EmergencyPage(contacts: payload.emergencyContacts,
                              steps: payload.emergencySteps,
                              canAlertFamily: Self.canAlertFamily(payload))
                    .tag(WatchPage.emergency)
            }
        }
        if Self.handoffDeclared {
            // Handoff: raise the iPhone and land on the page you were
            // reading here — the phone router already speaks this activity.
            tabs.userActivity("com.prvio.page") { activity in
                activity.isEligibleForHandoff = true
                activity.userInfo = ["tab": Self.handoffKey(for: selection)]
            }
        } else {
            tabs
        }
    }

    @ViewBuilder
    private func page(for key: String, payload: WatchPayload) -> some View {
        switch key {
        case "tasks":
            TasksPage(tasks: payload.tasks)
                .tag(WatchPage.tasks)
        case "plants":
            PlantsPage(plants: payload.plants)
                .tag(WatchPage.plants)
        case "shopping":
            if payload.supplies.contains(where: { !$0.isCompleted }) {
                ShoppingPage(supplies: payload.supplies)
                    .tag(WatchPage.shopping)
            }
        case "pantry":
            if !payload.pantry.isEmpty {
                PantryPage(items: payload.pantry)
                    .tag(WatchPage.pantry)
            }
        case "deliveries":
            if !payload.deliveries.isEmpty {
                DeliveriesPage(deliveries: payload.deliveries)
                    .tag(WatchPage.deliveries)
            }
        case "map":
            if let lat = payload.latitude, let lon = payload.longitude {
                PropertyMapPage(latitude: lat, longitude: lon,
                                name: payload.snapshot.propertyName)
                    .tag(WatchPage.map)
            }
        default:
            EmptyView()
        }
    }

    /// "Alert the family" needs a known property (the message names it) —
    /// the same guard the iPhone's Emergency page applies.
    static func canAlertFamily(_ payload: WatchPayload) -> Bool {
        !(payload.snapshot.propertyName ?? "").isEmpty
    }

    static func showsEmergency(_ payload: WatchPayload) -> Bool {
        canAlertFamily(payload)
            || !payload.emergencyContacts.isEmpty
            || !payload.emergencySteps.isEmpty
    }

    private static func handoffKey(for page: WatchPage) -> String {
        switch page {
        case .today:      return "home"
        case .messages:   return "chat"
        case .tasks:      return "tasks"
        case .plants:     return "plants"
        case .shopping:   return "supplies"
        case .pantry:     return "pantry"
        case .deliveries: return "deliveries"
        case .map:        return "map"
        // No dedicated phone tab for these yet — Handoff lands on Home, which
        // always exists, rather than an activity type the router can't honour.
        case .controls, .sensors, .emergency: return "home"
        }
    }

    private var waiting: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_waiting_title")
                .font(.system(.headline, design: .rounded))
            Text("watch_waiting_msg")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // The previous launch's captured crash, named right here — the
            // wrist's own black box (see WatchCrashRecorder).
            if let note = store.lastCrashNote {
                Text("watch_crash_title")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
                Text(verbatim: note)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }
        .padding()
    }
}

// MARK: - Module grid (jump menu)
//
// A honeycomb-style launcher: every surface with something to show, as a
// round tile. Tapping sets the pager's selection and closes — because only
// live surfaces are listed, a tap can never strand the user on an empty page.

private struct WatchModuleGrid: View {
    let payload: WatchPayload
    @Binding var selection: WatchPage
    @Environment(\.dismiss) private var dismiss

    private struct Module: Identifiable {
        let page: WatchPage
        let label: LocalizedStringKey
        let icon: String
        let tint: Color
        var id: WatchPage { page }
    }

    private var modules: [Module] {
        var m: [Module] = [
            .init(page: .today,  label: "watch_menu_today",  icon: "house.fill",     tint: .blue),
            .init(page: .tasks,  label: "watch_menu_tasks",  icon: "checklist",      tint: .blue),
            .init(page: .plants, label: "watch_menu_plants", icon: "leaf.fill",      tint: .green),
        ]
        if !payload.dmConversations.isEmpty {
            m.insert(.init(page: .messages, label: "watch_menu_messages",
                           icon: "message.fill", tint: .blue), at: 1)
        }
        if payload.supplies.contains(where: { !$0.isCompleted }) {
            m.append(.init(page: .shopping, label: "watch_menu_shopping", icon: "cart.fill", tint: .orange))
        }
        if !payload.pantry.isEmpty {
            m.append(.init(page: .pantry, label: "watch_menu_pantry", icon: "cabinet.fill", tint: .brown))
        }
        if !payload.deliveries.isEmpty {
            m.append(.init(page: .deliveries, label: "watch_menu_deliveries", icon: "shippingbox.fill", tint: .indigo))
        }
        if payload.latitude != nil, payload.longitude != nil {
            m.append(.init(page: .map, label: "watch_menu_map", icon: "map.fill", tint: .teal))
        }
        if !payload.actuators.isEmpty {
            m.append(.init(page: .controls, label: "watch_menu_controls", icon: "switch.2", tint: .purple))
        }
        if !payload.sensors.isEmpty {
            m.append(.init(page: .sensors, label: "watch_menu_sensors", icon: "sensor.fill", tint: .mint))
        }
        if WatchRootView.showsEmergency(payload) {
            m.append(.init(page: .emergency, label: "watch_menu_emergency",
                           icon: "cross.case.fill", tint: .red))
        }
        return m
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                    GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(modules) { module in
                        Button {
                            selection = module.page
                            dismiss()
                        } label: {
                            VStack(spacing: 5) {
                                Image(systemName: module.icon)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(module.tint)
                                    .frame(width: 46, height: 46)
                                    .background(module.tint.opacity(0.18), in: Circle())
                                Text(module.label)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle(Text("watch_menu_title"))
            .moodPageGround(fallback: .blue, opacity: 0.25)
        }
    }
}

// MARK: - Page 1: Today (the dashboard)

private struct TodayGlance: View {
    let payload: WatchPayload
    @Binding var selection: WatchPage
    @State private var showMenu = false

    private var snapshot: PRVIOWidgetSnapshot { payload.snapshot }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    hero.entrance(0)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                        GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        metric(count: snapshot.openTaskCount, label: "watch_open",
                               icon: "checklist", tint: .blue,
                               urgent: snapshot.overdueTaskCount > 0, page: .tasks)
                            .entrance(1)
                        metric(count: snapshot.plantsNeedingWater, label: "watch_water",
                               icon: "drop.fill", tint: .cyan, urgent: false, page: .plants)
                            .entrance(2)
                        metric(count: snapshot.activeDeliveryCount, label: "watch_deliveries",
                               icon: "shippingbox.fill", tint: .indigo, urgent: false,
                               page: .deliveries)
                            .entrance(3)
                        metric(count: snapshot.pendingSupplyCount, label: "watch_shopping",
                               icon: "cart.fill", tint: .orange, urgent: false, page: .shopping)
                            .entrance(4)
                    }

                    if let session = store.activeSession {
                        sessionCard(session).entrance(1)
                    }

                    if let temp = payload.weatherTemp, let symbol = payload.weatherSymbol {
                        weatherCard(temp: temp, symbol: symbol).entrance(5)
                    }

                    if snapshot.unreadMessages > 0 {
                        unreadRow(snapshot.unreadMessages).entrance(5)
                    }

                    if let insight = payload.insightTitle {
                        insightCard(title: insight, body: payload.insightBody)
                            .entrance(7)
                    }

                    if let critical = snapshot.criticalTaskTitle {
                        focusCard(icon: "exclamationmark.circle.fill", tint: .red,
                                  title: critical, sub: nil)
                            .entrance(6)
                    } else if let next = snapshot.nextMaintenanceTitle {
                        focusCard(icon: "wrench.and.screwdriver.fill", tint: .gray,
                                  title: next, sub: snapshot.nextMaintenanceDue)
                            .entrance(6)
                    }

                    freshnessFooter
                }
            }
            .navigationTitle(Text(verbatim: "PRVIO"))
            .moodPageGround(fallback: .blue, opacity: 0.25)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    // Ask the phone for a fresh payload over the live channel.
                    Button {
                        store.requestRefresh()
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(store.isRefreshing)
                    .accessibilityLabel(Text("watch_refresh"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // The module grid — jump straight to any surface instead of
                    // paging the wheel. Only surfaces with something to show are
                    // listed, so a tap always lands somewhere real.
                    Button { showMenu = true } label: {
                        Image(systemName: "square.grid.2x2.fill")
                            .accessibilityLabel(Text("watch_menu_title"))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Dictate a message for the house chat — the phone sends
                    // the real one through the same queue notification
                    // replies use.
                    TextFieldLink(prompt: Text("watch_chat_prompt")) {
                        Image(systemName: "message")
                            .accessibilityLabel(Text("watch_chat_send"))
                    } onSubmit: { value in
                        store.sendChatMessage(value)
                    }
                }
            }
            .sheet(isPresented: $showMenu) {
                WatchModuleGrid(payload: payload, selection: $selection)
            }
        }
    }

    /// The running maintenance session — live elapsed, tap to open.
    private func sessionCard(_ session: WatchStore.WorkSession) -> some View {
        Button { showSession = true } label: {
            WatchCard(tint: .teal) {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.title)
                            .font(.caption2.weight(.medium))
                            .lineLimit(1)
                        // The same clock WorkSessionView shows.
                        SessionClock(session: session,
                                     font: .system(.headline, design: .rounded).weight(.bold))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSession) { WorkSessionView() }
    }

    @State private var showSession = false

    /// Trust is knowing how old the data is — stale info must say so.
    private var freshnessFooter: some View {
        // .caption2, never a fixed 8–9pt: that was below any legible minimum
        // on the wrist and ignored Dynamic Type.
        HStack(spacing: 4) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.caption2)
            Text("watch_updated")
                .font(.caption2)
            Text(snapshot.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    @Environment(WatchStore.self) private var store

    // Athlytic hero: the health ring fills on arrival, the name sits beside it.
    private var hero: some View {
        HStack(spacing: 10) {
            if let score = snapshot.propertyHealthScore {
                HealthRing(score: score)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(snapshot.propertyName ?? "PRVIO")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let streak = payload.streakDays, streak >= 2 {
                    // The house streak — consecutive verified all-clear days.
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                            .symbolEffect(.bounce, value: streak)
                        Text(String(format: String(localized: "watch_streak"), streak))
                            .font(.system(.caption2, design: .rounded).weight(.semibold))
                            .foregroundStyle(.orange)
                            .contentTransition(.numericText())
                    }
                } else if snapshot.propertyHealthScore != nil {
                    Text("watch_health")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 2)
    }

    private func metric(count: Int, label: LocalizedStringKey, icon: String,
                        tint: Color, urgent: Bool, page: WatchPage) -> some View {
        Button {
            selection = page
        } label: {
            WatchCard(tint: urgent ? .red : tint) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: icon)
                            .font(.caption.weight(.semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(urgent ? .red : tint)
                        if urgent {
                            Circle().fill(.red).frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                        }
                        Spacer(minLength: 0)
                    }
                    Text(verbatim: "\(count)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Apple Weather at the property, with the garden advisory when there is
    /// one — and the attribution the WeatherKit terms require.
    private func weatherCard(temp: Double, symbol: String) -> some View {
        WatchCard(tint: .cyan) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                    Text(verbatim: "\(Int(temp.rounded()))°")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    if let lo = payload.weatherLo, let hi = payload.weatherHi {
                        Text(verbatim: "\(Int(lo.rounded()))°–\(Int(hi.rounded()))°")
                            .font(.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let advisory = payload.weatherAdvisory {
                    HStack(spacing: 4) {
                        Image(systemName: advisory == "frost" ? "snowflake" : "cloud.rain.fill")
                            .font(.caption2.weight(.semibold))
                        Text(advisory == "frost" ? "watch_adv_frost" : "watch_adv_rain")
                            .font(.caption2.weight(.medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.orange)
                }
                // Required by the WeatherKit terms — must stay visible, and
                // .caption2 keeps it actually legible (8pt wasn't).
                Text(verbatim: " Apple Weather")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func unreadRow(_ count: Int) -> some View {
        WatchCard(tint: .blue) {
            HStack(spacing: 6) {
                Image(systemName: "message.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(verbatim: "\(count)")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text("watch_unread")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        // Redacted on the Always-On dim state — messages aren't for
        // whoever walks past a resting wrist.
        .privacySensitive()
    }

    /// The ProactiveEngine's freshest insight — generated on the iPhone,
    /// pushed in the payload, readable with the phone out of reach.
    private func insightCard(title: String, body: String?) -> some View {
        WatchCard(tint: .purple) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.footnote, design: .rounded).weight(.semibold))
                        .lineLimit(2)
                    if let body, !body.isEmpty {
                        Text(body)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        // Redacted on the Always-On dim state — the household's private
        // intelligence isn't for whoever glances at a resting wrist.
        .privacySensitive()
    }

    private func focusCard(icon: String, tint: Color, title: String, sub: String?) -> some View {
        WatchCard(tint: tint) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint == .gray ? .secondary : tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.footnote, design: .rounded))
                        .lineLimit(2)
                    if let sub {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .privacySensitive()
    }
}

/// The property's health as a ring that fills when the dashboard arrives.
private struct HealthRing: View {
    let score: Int
    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Gauge(value: shown, in: 0...100) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text(verbatim: "\(Int(shown))")
                .font(.system(.body, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [WatchDesign.score(score).opacity(0.55),
                                WatchDesign.score(score)]))
        .frame(width: 54, height: 54)
        .onAppear {
            if reduceMotion {
                shown = Double(score)
            } else {
                withAnimation(.spring(duration: 1.1)) { shown = Double(score) }
            }
        }
        .accessibilityLabel(Text("watch_health"))
        .accessibilityValue(Text(verbatim: "\(score)%"))
    }
}

// MARK: - Acting rows (Waterllama feedback: fill, bounce, then leave)

/// The leading action symbol: tap → it fills and bounces, a beat later the
/// real action fires and the row animates out. The pause is the celebration.
/// Rows live in Lists inside the vertical pager, so no row ever owns the
/// double-tap primary action (see primaryDoubleTapOnFixedScreen).
private struct ActingSymbol: View {
    let idle: String
    let acted: String
    let tint: Color
    let label: LocalizedStringKey
    let action: () -> Void

    @State private var didAct = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            guard !didAct else { return }
            didAct = true
            if reduceMotion {
                action()
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(380))
                    action()
                }
            }
        } label: {
            Image(systemName: didAct ? acted : idle)
                .font(.body.weight(didAct ? .semibold : .light))
                .foregroundStyle(didAct ? tint : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: didAct)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Page 1b: Messages (the wrist inbox)
//
// One row per DM thread — peer, unread badge, last exchange — and a reply
// dictated/scribbled straight from the wrist. The reply rides the guaranteed
// queue with its thread's identity, so it lands in THAT conversation on the
// phone, never in the family chat. Threads without a durable peer id can't
// be answered by id, so they honestly never reach this page.

private struct MessagesPage: View {
    let conversations: [DMConversationEntry]

    private var rows: [DMConversationEntry] { Array(conversations.prefix(8)) }

    var body: some View {
        NavigationStack {
            List(rows, id: \.id) { convo in
                NavigationLink(value: convo.id) {
                    row(convo)
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WatchDesign.cardFill(convo.unread > 0 ? .blue : .gray))
                )
            }
            .navigationDestination(for: UUID.self) { id in
                if let convo = rows.first(where: { $0.id == id }) {
                    DMThreadDetail(convo: convo)
                }
            }
            .navigationTitle(Text("watch_menu_messages"))
            .moodPageGround(fallback: .blue, opacity: 0.3)
        }
    }

    private func row(_ convo: DMConversationEntry) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: convo.peerName)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                DMPreviewText(convo: convo)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if convo.unread > 0 {
                Text(verbatim: "\(min(convo.unread, 99))")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.blue, in: Capsule())
                    .accessibilityLabel(Text("watch_unread"))
            }
        }
        // Mail is not for whoever glances at a resting wrist.
        .privacySensitive()
    }
}

/// The last message, safely: media becomes a label, never a raw storage path.
private struct DMPreviewText: View {
    let convo: DMConversationEntry

    var body: some View {
        if convo.isMedia {
            Text("watch_dm_media")
        } else if let body = convo.lastBody, !body.isEmpty {
            if convo.lastIsMine {
                Text(verbatim: "\(String(localized: "watch_dm_you")): \(body)")
            } else {
                Text(verbatim: body)
            }
        } else {
            Text(verbatim: "—")
        }
    }
}

private struct DMThreadDetail: View {
    let convo: DMConversationEntry
    @Environment(WatchStore.self) private var store
    @State private var justSent = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                // The last exchange — enough context to answer from the wrist.
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: convo.lastIsMine
                         ? String(localized: "watch_dm_you") : convo.peerName)
                        .font(.system(.caption2, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                    DMPreviewText(convo: convo)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(.primary)
                    if let at = convo.lastAt {
                        Text(at, format: .relative(presentation: .named))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .privacySensitive()

                // Dictation / scribble reply — the watch input surface.
                TextFieldLink(prompt: Text("watch_dm_reply_prompt")) {
                    Label {
                        Text(justSent ? "watch_dm_sent" : "watch_dm_reply")
                    } icon: {
                        Image(systemName: justSent
                              ? "checkmark.circle.fill" : "arrowshape.turn.up.left.fill")
                    }
                    .frame(maxWidth: .infinity, minHeight: 36)
                } onSubmit: { value in
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    withAnimation(.snappy) { justSent = true }
                    store.sendDM(to: convo.id, text: trimmed)
                    Task {
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(.smooth) { justSent = false }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(justSent ? .green : .blue)
            }
        }
        .navigationTitle(Text(verbatim: convo.peerName))
        .moodPageGround(fallback: .blue, opacity: 0.3)
    }
}

// MARK: - Page 2: Tasks

private struct TasksPage: View {
    let tasks: [TaskCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var open: [TaskCatalogEntry] {
        // Overdue first, then the rest, capped for wrist reading.
        let pending = tasks.filter { !$0.isCompleted }
        return Array((pending.filter { $0.isOverdue == true }
                      + pending.filter { $0.isOverdue != true }).prefix(12))
    }

    var body: some View {
        NavigationStack {
            Group {
                if open.isEmpty {
                    AllClearView(icon: "checkmark.circle")
                } else {
                    List(open, id: \.id) { task in
                        // Symbol acts on the spot; the row opens the detail —
                        // the Things split, no accidental completes.
                        NavigationLink(value: task.id) {
                            HStack(spacing: 8) {
                                ActingSymbol(idle: "circle",
                                             acted: "checkmark.circle.fill",
                                             tint: task.isOverdue == true ? .red : .blue,
                                             label: "watch_complete") {
                                    withAnimation(.snappy) { store.completeTask(task.id) }
                                }
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(task.title)
                                        .font(.system(.footnote, design: .rounded))
                                        .lineLimit(2)
                                    if task.isOverdue == true {
                                        Text("watch_overdue")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(task.isOverdue == true ? .red : .blue))
                        )
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let task = open.first(where: { $0.id == id }) {
                            TaskDetail(task: task)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_tasks"))
            .moodPageGround(fallback: .blue, opacity: 0.3)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // Dictate a task straight from the wrist — the phone
                    // creates the real one on its next beat.
                    TextFieldLink(prompt: Text("watch_new_task_prompt")) {
                        Image(systemName: "plus")
                            .accessibilityLabel(Text("New Task"))
                    } onSubmit: { value in
                        withAnimation(.snappy) { store.createTask(value) }
                    }
                }
            }
        }
    }
}

private struct TaskDetail: View {
    let task: TaskCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showSession = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if task.isOverdue == true {
                    Label { Text("watch_overdue") } icon: {
                        Image(systemName: "exclamationmark.circle.fill")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.red)
                }

                Text(task.title)
                    .font(.system(.headline, design: .rounded))

                Button {
                    store.completeTask(task.id)
                    dismiss()
                } label: {
                    Label { Text("watch_complete") } icon: {
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                // Time the work: start a session, get on with the job.
                Button {
                    if store.activeSession?.taskId != task.id {
                        store.startSession(taskId: task.id, title: task.title)
                    }
                    showSession = true
                } label: {
                    Label { Text(store.activeSession?.taskId == task.id
                                 ? "watch_session_open" : "watch_session_start") } icon: {
                        Image(systemName: "timer")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .moodPageGround(fallback: .blue, opacity: 0.3)
        .sheet(isPresented: $showSession) { WorkSessionView() }
    }
}

// MARK: - Work session (maintenance timer)

private struct WorkSessionView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Minute ticker for the quarter-hour haptic — fires only while this
    /// screen is up; the elapsed display runs on its own TimelineView
    /// (SessionClock), which the system throttles in Always On.
    private let minuteTick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        if let session = store.activeSession {
            // The one screen allowed to own double tap: it must not scroll
            // (HIG). The fixed layout wins whenever it fits; when it can't
            // (a small case at a large Dynamic Type size) the same layout
            // scrolls and gives the gesture back to the system.
            ViewThatFits(in: .vertical) {
                layout(session, ownsDoubleTap: true)
                ScrollView {
                    layout(session, ownsDoubleTap: false)
                }
            }
            .onReceive(minuteTick) { _ in
                // A quiet pulse every quarter hour keeps time honest while
                // hands are busy — screen-on only, by design.
                let minutes = Int(Date().timeIntervalSince(session.startedAt) / 60)
                if minutes > 0, minutes % 15 == 0 {
                    WKInterfaceDevice.current().play(.notification)
                }
            }
        } else {
            AllClearView(icon: "timer")
                .onAppear { dismiss() }
        }
    }

    /// Compact by design so it fits without scrolling: pause and stop share
    /// one row as icon buttons (their titles stay as accessibility labels),
    /// leaving the full-width Complete as the obvious primary action.
    private func layout(_ session: WatchStore.WorkSession, ownsDoubleTap: Bool) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.teal)
                    // Always On: no animation on a dimmed, rarely-redrawn face.
                    .symbolEffect(.pulse, isActive: !isLuminanceReduced)
                Text(session.title)
                    .lineLimit(1)
            }
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .opacity(isLuminanceReduced ? 0.6 : 1)

            SessionClock(session: session,
                         font: .system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 6) {
                Button {
                    store.toggleSessionPause()
                } label: {
                    Label {
                        Text(session.isPaused ? "watch_session_resume" : "watch_session_pause")
                    } icon: {
                        Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                    }
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(session.isPaused ? .green : .orange)

                Button {
                    store.endSession(completingTask: false)
                    dismiss()
                } label: {
                    Label { Text("watch_session_end") } icon: {
                        Image(systemName: "stop.fill")
                    }
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .opacity(isLuminanceReduced ? 0.6 : 1)

            completeButton(ownsDoubleTap: ownsDoubleTap)
        }
    }

    @ViewBuilder
    private func completeButton(ownsDoubleTap: Bool) -> some View {
        let button = Button {
            store.endSession(completingTask: true)
            dismiss()
        } label: {
            Label { Text("watch_complete") } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.teal)

        if ownsDoubleTap {
            button.primaryDoubleTapOnFixedScreen()
        } else {
            button
        }
    }
}

/// The live session readout. Computed elapsed (not Text(style: .timer),
/// which counts wall-clock from startedAt) so a pause truly freezes it and
/// paused time is excluded. Always On: when the system demotes the timeline
/// to minute cadence the seconds digit can't stay honest, so the readout
/// drops to h:mm until the wrist is raised again.
private struct SessionClock: View {
    let session: WatchStore.WorkSession
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            Text(verbatim: context.cadence >= .minutes
                 ? elapsed.watchSessionClockMinutes
                 : elapsed.watchSessionClock)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(session.isPaused ? .orange : .primary)
        }
    }
}

// MARK: - Page 3: Plants

private struct PlantsPage: View {
    let plants: [PlantCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var thirsty: [PlantCatalogEntry] { plants.filter(\.needsWatering) }

    var body: some View {
        NavigationStack {
            Group {
                if thirsty.isEmpty {
                    AllClearView(icon: "leaf")
                } else {
                    List(thirsty, id: \.id) { plant in
                        NavigationLink(value: plant.id) {
                            HStack(spacing: 6) {
                                ActingSymbol(idle: "drop",
                                             acted: "drop.fill",
                                             tint: .cyan,
                                             label: "watch_water_now") {
                                    withAnimation(.snappy) { store.waterPlant(plant.id) }
                                }
                                Text(plant.emoji)
                                Text(plant.name)
                                    .font(.system(.footnote, design: .rounded))
                                    .lineLimit(1)
                            }
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.cyan))
                        )
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let plant = thirsty.first(where: { $0.id == id }) {
                            PlantDetail(plant: plant)
                        }
                    }
                }
            }
            .navigationTitle(Text("watch_plants"))
            .moodPageGround(fallback: .green, opacity: 0.3)
            .toolbar {
                if thirsty.count > 1 {
                    ToolbarItem(placement: .topBarTrailing) {
                        // With several thirsty plants, one tap waters all.
                        Button {
                            withAnimation(.snappy) { store.waterAllPlants() }
                        } label: {
                            Image(systemName: "drop.fill")
                        }
                        .accessibilityLabel(Text("watch_water_all"))
                    }
                }
            }
        }
    }
}

private struct PlantDetail: View {
    let plant: PlantCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(plant.emoji)
                    .font(.largeTitle)
                Text(plant.name)
                    .font(.system(.headline, design: .rounded))
                    .multilineTextAlignment(.center)

                Button {
                    store.waterPlant(plant.id)
                    dismiss()
                } label: {
                    Label { Text("watch_water_now") } icon: {
                        Image(systemName: "drop.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .frame(maxWidth: .infinity)
        }
        .moodPageGround(fallback: .green, opacity: 0.3)
    }
}

// MARK: - Page 4: Shopping

private struct ShoppingPage: View {
    let supplies: [SupplyCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var pending: [SupplyCatalogEntry] {
        Array(supplies.filter { !$0.isCompleted }.prefix(15))
    }

    var body: some View {
        NavigationStack {
            Group {
                if pending.isEmpty {
                    AllClearView(icon: "cart")
                } else {
                    List(pending, id: \.id) { item in
                        HStack(spacing: 8) {
                            ActingSymbol(idle: "circle",
                                         acted: "checkmark.circle.fill",
                                         tint: .orange,
                                         label: "watch_tap_check") {
                                withAnimation(.snappy) { store.checkSupply(item.id) }
                            }
                            Text(item.name)
                                .font(.system(.footnote, design: .rounded))
                                .lineLimit(2)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.orange))
                        )
                    }
                }
            }
            .navigationTitle(Text("watch_shopping"))
            .moodPageGround(fallback: .orange, opacity: 0.3)
        }
    }
}

// MARK: - Page 4b: Pantry (consume from the wrist)

private struct PantryPage: View {
    let items: [PantryCatalogEntry]
    @Environment(WatchStore.self) private var store

    private var stocked: [PantryCatalogEntry] { Array(items.prefix(15)) }

    var body: some View {
        NavigationStack {
            Group {
                if stocked.isEmpty {
                    AllClearView(icon: "basket")
                } else {
                    List(stocked, id: \.id) { item in
                        PantryRow(item: item) {
                            store.consumePantry(item.id)
                        }
                        // Swipe → straight onto the shopping list: the phone
                        // performs the real SupplyService insert on its next
                        // beat (duplicates are skipped there, so a repeat
                        // swipe can't double a row).
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.addPantryItemToShoppingList(item.id)
                            } label: {
                                Label("watch_pantry_to_list",
                                      systemImage: "cart.fill.badge.plus")
                            }
                            .tint(.orange)
                        }
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(WatchDesign.cardFill(.green))
                        )
                    }
                }
            }
            .navigationTitle(Text("watch_pantry"))
            .moodPageGround(fallback: .green, opacity: 0.25)
        }
    }
}

/// Repeatable consume row — unlike the one-shot ActingSymbol, stock can be
/// consumed again and again; the icon bounces on every unit. A List row, so
/// never the double-tap primary action.
private struct PantryRow: View {
    let item: PantryCatalogEntry
    let consume: () -> Void

    private var quantityLabel: String {
        let qty = item.quantity
        let number = qty == qty.rounded() ? String(Int(qty)) : String(format: "%.1f", qty)
        return "\(number) \(item.unit)"
    }

    var body: some View {
        HStack(spacing: 8) {
            consumeButton
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(.footnote, design: .rounded))
                    .lineLimit(1)
                Text(verbatim: quantityLabel)
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(item.quantity <= 0 ? .red : .secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
    }

    private var consumeButton: some View {
        Button {
            withAnimation(.snappy) { consume() }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.quantity > 0 ? .green : .secondary)
                .symbolEffect(.bounce, value: item.quantity)
        }
        .buttonStyle(.plain)
        .disabled(item.quantity <= 0)
        .accessibilityLabel(Text("watch_consume_one"))
        .accessibilityValue(Text(verbatim: quantityLabel))
    }
}

// MARK: - Page 5: Deliveries (confirm a parcel from the doormat)
//
// The symbol acts on the spot (the Things split, as on Tasks): tapping the
// circle marks a still-active parcel received — locally instantly, then for
// real through DeliveryService.markDelivered on the phone's next beat. The
// row still opens the detail, which offers the same action as a big button.

private struct DeliveriesPage: View {
    let deliveries: [DeliveryCatalogEntry]
    @Environment(WatchStore.self) private var store

    private static func isActive(_ parcel: DeliveryCatalogEntry) -> Bool {
        parcel.status == "expected" || parcel.status == "out_for_delivery"
    }

    var body: some View {
        NavigationStack {
            List(deliveries.prefix(10), id: \.id) { parcel in
                NavigationLink(value: parcel.id) {
                    HStack(spacing: 8) {
                        if Self.isActive(parcel) {
                            ActingSymbol(idle: "circle",
                                         acted: "checkmark.seal.fill",
                                         tint: .green,
                                         label: "watch_delivery_received") {
                                withAnimation(.snappy) { store.markDeliveryReceived(parcel.id) }
                            }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)
                                Text(parcel.title)
                                    .font(.system(.footnote, design: .rounded))
                                    .lineLimit(2)
                            }
                            DeliveryGlyphs.statusLabel(for: parcel.status)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WatchDesign.cardFill(.indigo))
                )
            }
            .navigationDestination(for: UUID.self) { id in
                if let parcel = deliveries.first(where: { $0.id == id }) {
                    DeliveryDetail(parcel: parcel)
                }
            }
            .navigationTitle(Text("watch_deliveries"))
            .moodPageGround(fallback: .cyan, opacity: 0.3)
        }
    }
}

private struct DeliveryDetail: View {
    let parcel: DeliveryCatalogEntry
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: DeliveryGlyphs.icon(for: parcel.status))
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(parcel.status == "out_for_delivery" ? .orange : .secondary)

                Text(parcel.title)
                    .font(.system(.headline, design: .rounded))

                DeliveryGlyphs.statusLabel(for: parcel.status)
                    .font(.footnote.weight(.semibold))

                if let carrier = parcel.carrier, !carrier.isEmpty {
                    Text(verbatim: carrier)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let eta = parcel.eta, !eta.isEmpty {
                    Text(verbatim: eta)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if parcel.status == "expected" || parcel.status == "out_for_delivery" {
                    Button {
                        store.markDeliveryReceived(parcel.id)
                        dismiss()
                    } label: {
                        Label { Text("watch_delivery_received") } icon: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .moodPageGround(fallback: .cyan, opacity: 0.3)
    }
}

// MARK: - Page 6: Property map (the twin on the wrist)
//
// MapKit's native watch map: crown and pan gestures come free, the property
// pin wears the brand. Coordinates ride the payload, so the map centers
// correctly even offline (tiles need connectivity; the pin does not).

private struct PropertyMapPage: View {
    let latitude: Double
    let longitude: Double
    let name: String?

    @State private var position: MapCameraPosition

    init(latitude: Double, longitude: Double, name: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.name = name
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004))))
    }

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                Annotation(name ?? "PRVIO",
                           coordinate: CLLocationCoordinate2D(latitude: latitude,
                                                              longitude: longitude)) {
                    ZStack {
                        Circle()
                            .fill(Color.blue.opacity(0.25))
                            .frame(width: 30, height: 30)
                        Image(systemName: "house.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.blue))
                    }
                    // The pin is fixed map geometry; its glyph scales only
                    // as far as the 22 pt disc can hold.
                    .dynamicTypeSize(...DynamicTypeSize.large)
                }
            }
            .navigationTitle(Text("watch_map"))
        }
    }
}

// MARK: - Delivery glyphs (shared row/detail vocabulary)

enum DeliveryGlyphs {
    static func icon(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    // The same keys the iPhone's Delivery.statusLabel resolves.
    static func statusLabel(for status: String) -> Text {
        switch status {
        case "expected":         return Text("Expected")
        case "out_for_delivery": return Text("Out for delivery")
        case "delivered":        return Text("Delivered")
        case "missed":           return Text("Missed")
        case "returned":         return Text("Returned")
        default:                 return Text(verbatim: status)
        }
    }
}

// MARK: - Shared empty state

private struct AllClearView: View {
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text("watch_all_good")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Controls (smart-home actuators)
//
// Relays get an On/Off pair; covers get up/close/stop. Every button maps to a
// command the actuator declared on the phone, so a wrist tap always resolves
// to a real device write — the phone performs it and reports the true state
// back. A relay echoes its new state instantly for a responsive wrist.

private struct ControlsPage: View {
    @Environment(WatchStore.self) private var store
    let actuators: [ActuatorCatalogEntry]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(actuators, id: \.id) { actuator in
                        card(actuator)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .navigationTitle(Text("watch_menu_controls"))
            .moodPageGround(fallback: .purple, opacity: 0.25)
        }
    }

    private func card(_ a: ActuatorCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: a.kind == "cover" ? "door.garage.closed" : "power")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.purple)
                Text(verbatim: a.name)
                    .font(.system(.footnote, design: .rounded).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                if a.kind == "relay" {
                    Circle()
                        .fill(a.isOn == true ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 8, height: 8)
                }
            }
            if a.kind == "relay" {
                HStack(spacing: 6) {
                    relayButton(a, command: "on", title: "watch_cmd_on",
                                tint: .green, active: a.isOn == true)
                    relayButton(a, command: "off", title: "watch_cmd_off",
                                tint: .orange, active: a.isOn == false)
                }
            } else {
                HStack(spacing: 6) {
                    coverButton(a, command: "open",  icon: "arrow.up",   tint: .blue)
                    coverButton(a, command: "close", icon: "arrow.down", tint: .indigo)
                    coverButton(a, command: "stop",  icon: "stop.fill",  tint: .orange)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func relayButton(_ a: ActuatorCatalogEntry, command: String,
                             title: LocalizedStringKey, tint: Color, active: Bool) -> some View {
        Button {
            store.sendCommand(actuatorId: a.id, command: command)
        } label: {
            Text(title)
                .font(.system(.footnote, design: .rounded).weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(active ? tint : Color.gray.opacity(0.4))
    }

    private func coverButton(_ a: ActuatorCatalogEntry, command: String,
                             icon: String, tint: Color) -> some View {
        Button {
            store.sendCommand(actuatorId: a.id, command: command)
        } label: {
            Image(systemName: icon)
                .font(.body.weight(.bold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }
}

// MARK: - Sensors (live readings)
//
// Read-only glance over the property's own sensors. An alerting sensor tints
// warm; a critical hazard (smoke / gas / water) tints red — the same honesty
// the phone and the Live Activities use.

private struct SensorsPage: View {
    let sensors: [SensorCatalogEntry]

    /// Hazards first: a critical alarm belongs at the top of a small screen.
    /// Stable partition, so the phone's own order survives within each tier.
    private var ordered: [SensorCatalogEntry] {
        sensors.filter { $0.isCritical && $0.isAlerting }
            + sensors.filter { !($0.isCritical && $0.isAlerting) && $0.isAlerting }
            + sensors.filter { !$0.isAlerting }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(ordered, id: \.id) { s in
                        row(s)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .navigationTitle(Text("watch_menu_sensors"))
            .moodPageGround(fallback: .mint, opacity: 0.25)
        }
    }

    private func row(_ s: SensorCatalogEntry) -> some View {
        let accent: Color = s.isCritical ? .red : (s.isAlerting ? .orange : .mint)
        return HStack(spacing: 8) {
            Image(systemName: s.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: s.name)
                    .font(.system(.footnote, design: .rounded).weight(.medium))
                    .lineLimit(1)
                if let zone = s.zone {
                    Text(verbatim: zone)
                        .font(.system(.caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(verbatim: s.displayValue)
                .font(.system(.footnote, design: .rounded).weight(.semibold).monospacedDigit())
                .foregroundStyle(s.isCritical ? .red : (s.isAlerting ? .orange : .primary))
        }
        .padding(8)
        .background(s.isAlerting ? accent.opacity(0.15) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Emergency (SOS)
//
// The property's own plan on the wrist: pin the Emergency Live Activity, walk
// the shutoff steps, and tap a contact to call it — a real tel: call straight
// from the watch. Everything here comes from what the user configured on the
// phone; nothing is invented.

private struct EmergencyPage: View {
    @Environment(WatchStore.self) private var store
    let contacts: [EmergencyContactEntry]
    let steps: [EmergencyStepEntry]
    /// Whether the property is known — the family alert names it, exactly
    /// like the iPhone Emergency page's own guard.
    var canAlertFamily = false

    @State private var showAlertConfirm = false
    @State private var alertSent = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    // One tap + one confirmation (a pocket-tap false alarm
                    // costs real adrenaline): the phone sends the SAME
                    // "⚠️ Emergency at <property> — call me!" the iPhone
                    // button sends, into the household chat.
                    if canAlertFamily {
                        Button {
                            guard !alertSent else { return }
                            showAlertConfirm = true
                        } label: {
                            Label {
                                Text(alertSent ? "emg_alert_sent" : "emg_alert_family")
                            } icon: {
                                Image(systemName: alertSent
                                      ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                            }
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(alertSent ? .green : .red)
                        .confirmationDialog("emg_alert_confirm_title",
                                            isPresented: $showAlertConfirm,
                                            titleVisibility: .visible) {
                            Button("emg_alert_confirm_send", role: .destructive) {
                                store.alertFamily()
                                withAnimation(.snappy) { alertSent = true }
                                Task {
                                    try? await Task.sleep(for: .seconds(5))
                                    withAnimation(.smooth) { alertSent = false }
                                }
                            }
                        }
                    }

                    Button {
                        store.startEmergency()
                    } label: {
                        Label("watch_emergency_start", systemImage: "light.beacon.max.fill")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)

                    if !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("watch_emergency_steps")
                            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                                HStack(alignment: .top, spacing: 6) {
                                    Text(verbatim: "\(idx + 1)")
                                        .font(.system(.caption2, design: .rounded).weight(.bold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(verbatim: step.title)
                                            .font(.system(.footnote, design: .rounded).weight(.medium))
                                            .lineLimit(2)
                                        if !step.detail.isEmpty {
                                            Text(verbatim: step.detail)
                                                .font(.system(.caption2))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }

                    if !contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            sectionLabel("watch_emergency_contacts")
                            ForEach(contacts, id: \.id) { contact in
                                contactRow(contact)
                            }
                        }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
            .navigationTitle(Text("watch_menu_emergency"))
            // Deliberately NOT moodPageGround: the red ground is a signal
            // (this is the SOS page), never an atmosphere to soften.
            .containerBackground(Color.red.gradient.opacity(0.28), for: .navigation)
        }
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func contactRow(_ contact: EmergencyContactEntry) -> some View {
        let digits = contact.phone.filter { !$0.isWhitespace }
        if let url = URL(string: "tel://\(digits)") {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "phone.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: contact.name)
                            .font(.system(.footnote, design: .rounded).weight(.medium))
                            .lineLimit(1)
                        if !contact.role.isEmpty {
                            Text(verbatim: contact.role)
                                .font(.system(.caption2))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
    }
}
