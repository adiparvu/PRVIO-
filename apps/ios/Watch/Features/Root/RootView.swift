import SwiftUI

// MARK: - Root: the waiting screen, or the vertical pager
//
// The pager shows only `store.visiblePages`; the selection is clamped to
// that set on every read and corrected whenever it shrinks, so a tile, a
// deep link or a vanished page can never strand the user on a missing tab.
// Each page owns its own NavigationStack, and every stack registers the
// shared `WatchDestination` routes once, here.

struct RootView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selection: WatchPage = .today
    @State private var todayPath = NavigationPath()
    @State private var tasksPath = NavigationPath()
    @State private var plantsPath = NavigationPath()
    @State private var homePath = NavigationPath()
    /// The module last opened in each page's stack, for Handoff; cleared
    /// when that stack returns to its root.
    @State private var focusedModules: [WatchPage: WatchModule] = [:]

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
                pager
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
        .onChange(of: scenePhase) {
            if scenePhase == .active { store.reloadFromCache() }
        }
    }

    // MARK: Pager

    private var pager: some View {
        TabView(selection: clampedSelection) {
            ForEach(store.visiblePages) { page in
                stack(for: page)
                    .tag(page)
            }
        }
        .tabViewStyle(.verticalPage)
        .onChange(of: store.visiblePages) { clampSelection() }
        .onChange(of: todayPath.count) { if todayPath.isEmpty { focusedModules[.today] = nil } }
        .onChange(of: homePath.count) { if homePath.isEmpty { focusedModules[.home] = nil } }
        .onOpenURL { open(WatchDeepLink(url: $0)) }
        .userActivity(WatchRoute.handoffActivityType, isActive: Self.handoffDeclared) { activity in
            activity.isEligibleForHandoff = true
            activity.userInfo = ["tab": WatchRoute.handoffTab(page: clampedSelection.wrappedValue,
                                                             module: focusedModules[clampedSelection.wrappedValue])]
        }
    }

    @ViewBuilder
    private func stack(for page: WatchPage) -> some View {
        switch page {
        case .today:
            NavigationStack(path: $todayPath) {
                TodayView(selection: clampedSelection)
                    .watchDestinations { focusedModules[.today] = $0 }
            }
        case .tasks:
            NavigationStack(path: $tasksPath) {
                TasksPage()
                    .watchDestinations { focusedModules[.tasks] = $0 }
            }
        case .plants:
            NavigationStack(path: $plantsPath) {
                PlantsPage()
                    .watchDestinations { focusedModules[.plants] = $0 }
            }
        case .home:
            NavigationStack(path: $homePath) {
                HomeHubView()
                    .watchDestinations { focusedModules[.home] = $0 }
            }
        }
    }

    // MARK: Selection

    /// Page changes the app makes (deep links) glide like a crown scroll;
    /// under Reduce Motion they cross-fade.
    private var transitionAnimation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    private var clampedSelection: Binding<WatchPage> {
        Binding(
            get: { store.visiblePages.contains(selection) ? selection : .today },
            set: { newValue in
                selection = store.visiblePages.contains(newValue) ? newValue : .today
            }
        )
    }

    private func clampSelection() {
        if !store.visiblePages.contains(selection) { selection = .today }
        if !store.visiblePages.contains(.home) { homePath = NavigationPath() }
    }

    // MARK: Deep links

    private func open(_ link: WatchDeepLink) {
        switch link {
        case .page(let page):
            withAnimation(transitionAnimation) {
                selection = store.isVisible(page) ? page : .today
            }
        case .module(let module):
            guard store.isVisible(module), store.isVisible(.home) else {
                withAnimation(transitionAnimation) { selection = .today }
                return
            }
            var path = NavigationPath()
            path.append(WatchDestination.module(module))
            homePath = path
            withAnimation(transitionAnimation) { selection = .home }
        }
    }
}

// MARK: - Shared destinations

extension View {
    /// Registers the `WatchDestination` routes on a page's stack root.
    /// RootView applies it once per stack; feature views push
    /// `WatchDestination` values and never register them again.
    func watchDestinations(onModuleShown: @escaping (WatchModule) -> Void = { _ in }) -> some View {
        navigationDestination(for: WatchDestination.self) { destination in
            switch destination {
            case .workSession:
                WorkSessionView()
            case .module(let module):
                WatchModuleScreen(module: module)
                    .onAppear { onModuleShown(module) }
            }
        }
    }
}

/// The screen behind each Home hub module.
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
