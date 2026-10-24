import SwiftUI

// MARK: - Root: the waiting screen, or sections + the section on screen
//
// A NavigationSplitView, which the watch collapses into one stack:
//
//   Sections list  ─▶  section root (Today, Tasks, Shopping, …)  ─▶  details
//
// The app opens on Today (the detail column), never on the list. Going
// back is always the same control in the same place — the system button in
// the top leading corner (or a swipe from the left edge): inside a section
// it pops one level; on a section root it returns to the list of sections.
// Every section owns its own stack (`paths`), so leaving Tasks mid-detail
// and coming back finds it where it was — until the app has been away long
// enough that a fresh start is kinder (`freshStartAfter`): then it opens
// on Today again, at the top.
//
// The selection is clamped to the visible sections on every read and
// corrected whenever they shrink, so a tile, a deep link or a vanished
// section can never strand the user on a missing screen.

struct RootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The section in the detail column (kept while the list is showing,
    /// so the system's back button can return to it).
    @State private var selection: WatchSection = .today
    /// Which column the collapsed split view shows; the system sets it to
    /// `.sidebar` when back is pressed on a section root.
    @State private var column: NavigationSplitViewColumn = .detail
    @State private var paths: [WatchSection: NavigationPath] = [:]
    /// The module last pushed in each section's stack, for Handoff;
    /// cleared when that stack returns to its root.
    @State private var pushedModules: [WatchSection: WatchModule] = [:]
    @State private var backgroundedAt: Date? = nil

    /// Away this long, the app reopens on Today at the top — a stale detail
    /// from an hour ago is a "where am I?", not a continuation.
    private static let freshStartAfter: TimeInterval = 10 * 60

    /// Advertising an NSUserActivity whose type the built Info.plist does not
    /// declare throws at first render on a real watch ("opens and instantly
    /// exits"). The plist declares it; this check keeps the crash impossible
    /// even if a build configuration ever drops the key.
    private static let handoffDeclared: Bool =
        (Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String])?
            .contains(WatchRoute.handoffActivityType) == true

    var body: some View {
        Group {
            if store.payload != nil {
                split
                    .transition(.opacity)
            } else {
                // Its own stack, so the waiting screen wears the sky too
                // (the ground paints the navigation container).
                NavigationStack {
                    WaitingView()
                }
                .transition(.opacity)
            }
        }
        // First sync (or sign-out) cross-fades instead of snapping.
        .animation(transitionAnimation, value: store.payload == nil)
        // A committed first frame means this launch survived — a sentinel
        // still set at the next launch is a death the handler couldn't see.
        .onAppear { WatchCrashRecorder.firstFrameRendered() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = .now
            case .active:
                store.reloadFromCache()
                if let backgroundedAt, Date.now.timeIntervalSince(backgroundedAt) > Self.freshStartAfter {
                    startFresh()
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    // MARK: Split view

    private var split: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            SectionsView { section in
                selection = section
                column = .detail
            }
        } detail: {
            let section = visibleSelection
            NavigationStack(path: path(for: section)) {
                WatchSectionScreen(section: section)
                    .watchDestinations { pushedModules[section] = $0 }
            }
            // One stack per section: switching sections never carries
            // another section's pushes along.
            .id(section)
        }
        .onChange(of: store.visibleSections) { clampSelection() }
        .onChange(of: currentDepth) {
            if currentDepth == 0 { pushedModules[selection] = nil }
        }
        .onOpenURL { open(WatchDeepLink(url: $0)) }
        .userActivity(WatchRoute.handoffActivityType, isActive: Self.handoffDeclared) { activity in
            let section = visibleSelection
            activity.isEligibleForHandoff = true
            activity.userInfo = ["tab": WatchRoute.handoffTab(section: section, pushed: pushedModules[section])]
        }
    }

    private func path(for section: WatchSection) -> Binding<NavigationPath> {
        Binding(
            get: { paths[section] ?? NavigationPath() },
            set: { paths[section] = $0 }
        )
    }

    private var currentDepth: Int {
        paths[selection]?.count ?? 0
    }

    // MARK: Selection

    /// Changes the app makes (deep links, fresh start) glide; under Reduce
    /// Motion they cross-fade.
    private var transitionAnimation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    /// The selection, or Today when it is no longer on the list.
    private var visibleSelection: WatchSection {
        store.isVisible(selection) ? selection : .today
    }

    private func clampSelection() {
        if !store.isVisible(selection) { selection = .today }
        // Stacks of sections that vanished are dropped, not resurrected later.
        paths = paths.filter { store.isVisible($0.key) }
    }

    /// Today, at the top, with every stack at its root.
    private func startFresh() {
        paths = [:]
        pushedModules = [:]
        selection = .today
        column = .detail
    }

    // MARK: Deep links

    private func open(_ link: WatchDeepLink) {
        let target: WatchSection
        switch link {
        case .page(let page):     target = .page(page)
        case .module(let module): target = .module(module)
        }
        let section = store.isVisible(target) ? target : .today
        withAnimation(transitionAnimation) {
            paths[section] = nil
            selection = section
            column = .detail
        }
    }
}

// MARK: - Shared destinations

extension View {
    /// Registers the `WatchDestination` routes on a section's stack root.
    /// RootView applies it once per stack; feature views push
    /// `WatchDestination` values and never register them again.
    func watchDestinations(onModuleShown: @escaping (WatchModule) -> Void = { _ in }) -> some View {
        navigationDestination(for: WatchDestination.self) { destination in
            switch destination {
            case .workSession:
                WorkSessionView()
            case .page(let page):
                WatchSectionScreen(section: .page(page))
            case .module(let module):
                WatchModuleScreen(module: module)
                    .onAppear { onModuleShown(module) }
            }
        }
    }
}

/// The root screen of a section.
struct WatchSectionScreen: View {
    let section: WatchSection

    var body: some View {
        switch section {
        case .page(.today):       TodayView()
        case .page(.tasks):       TasksPage()
        case .page(.plants):      PlantsPage()
        case .module(let module): WatchModuleScreen(module: module)
        }
    }
}

/// The screen behind each module.
struct WatchModuleScreen: View {
    let module: WatchModule

    var body: some View {
        switch module {
        case .shopping:   ShoppingView()
        case .pantry:     PantryView()
        case .deliveries: DeliveriesView()
        case .messages:   MessagesView()
        case .map:        PropertyMapView()
        case .controls:   ControlsView()
        case .sensors:    SensorsView()
        case .emergency:  EmergencyView()
        }
    }
}

// MARK: - Waiting for the iPhone
//
// The same language as Home Pulse: the ring, a breathing glyph (calm — the
// phone is on its way), one warm sentence, one action. When the phone is
// out of reach it says so plainly instead of spinning.

private struct WaitingView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isOutOfReach: Bool {
        store.connectivity == .unreachable || store.connectivity == .inactive
    }

    var body: some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.l) {
                ZStack {
                    Circle()
                        .stroke(WatchTheme.Tint.calm.opacity(WatchTheme.Opacity.ringTrack),
                                lineWidth: WatchTheme.Stroke.ring)
                    Image(systemName: isOutOfReach ? "iphone.slash" : "iphone.and.arrow.forward")
                        .font(WatchTheme.Typography.dialGlyph)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(isOutOfReach ? WatchTheme.Tint.attention : WatchTheme.Tint.calm)
                        .contentTransition(reduceMotion ? ContentTransition.opacity
                                                        : ContentTransition.symbolEffect(.replace))
                        .symbolEffect(.breathe, isActive: !isOutOfReach && !reduceMotion && !isLuminanceReduced)
                }
                .frame(width: WatchTheme.Size.dial, height: WatchTheme.Size.dial)
                .accessibilityHidden(true)

                VStack(spacing: WatchTheme.Spacing.xs) {
                    Text("watch_waiting_title")
                        .font(WatchTheme.Typography.headline)
                    Text(isOutOfReach ? "watch_waiting_unreachable" : "watch_waiting_msg")
                        .font(WatchTheme.Typography.brief)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
                .accessibilityElement(children: .combine)

                if store.connectivity == .reachable {
                    Button {
                        store.requestRefresh()
                    } label: {
                        if store.isRefreshing {
                            ProgressView()
                        } else {
                            Label("watch_sync_now", systemImage: "arrow.clockwise")
                        }
                    }
                    .tint(WatchTheme.Tint.today)
                    .disabled(store.isRefreshing)
                }

                // The previous launch's captured crash, named right here —
                // the wrist's own black box (see WatchCrashRecorder).
                if let note = store.crashNote {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                        StateLabel("watch_crash_title", systemImage: "exclamationmark.triangle.fill",
                                   tint: WatchTheme.Tint.critical)
                        Text(verbatim: note)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.xs)
        }
        .navigationTitle(Text(verbatim: "PRVIO"))
        .skyGround()
    }
}
