import SwiftUI
import Observation

@MainActor
@Observable
final class AppRouter {
    /// The tabs the tab bar currently shows. The TabView builds from THIS set
    /// (not from the role directly), so the bar and the selection always
    /// change in the same mutation.
    var visibleTabs: Set<AppTab> = Set(AppTab.allCases) {
        didSet { if !visibleTabs.contains(selectedTab) { selectedTab = fallbackTab } }
    }

    /// Clamped to `visibleTabs`: on the iOS 27 SDK a TabView whose selection
    /// names a hidden tab may crash, and deep links (widgets, quick actions,
    /// notifications) can ask a guest for a tab their role doesn't have.
    var selectedTab: AppTab = .home {
        didSet { if !visibleTabs.contains(selectedTab) { selectedTab = fallbackTab } }
    }

    private var fallbackTab: AppTab {
        visibleTabs.contains(.chat) ? .chat : (AppTab.allCases.first(where: visibleTabs.contains) ?? .chat)
    }

    // MARK: - Routed presentations
    //
    // One sheet slot + one full-screen-cover slot for the whole window,
    // presented by MainTabView. A single `.sheet(item:)` can never race
    // itself the way ~17 chained `.sheet(isPresented:)` modifiers did —
    // assigning a new destination swaps the content instead of silently
    // dropping the presentation and stranding a boolean.

    /// Every globally routed presentation. Sheet-presented except `.aria`,
    /// which keeps its full-screen cover (same split as the old flag stack).
    enum RoutedDestination: String, Identifiable {
        case aria           // fullScreenCover
        case newTask
        case addExpense
        case receiptScan
        case inventoryScan
        case inventoryAdd
        case inventory
        case addSupply
        case plants
        case supplies
        case pantry
        case cameras
        case documents
        case family
        case contractors
        case finances
        case deliveries
        case paintColors
        case photoJournal
        case profile
        case notifications
        /// The notification panel pre-filtered to the chat module — the
        /// conversations screen's bell shows only chat activity.
        case notificationsChat
        case emergency
        case iotHub
        /// The in-app house calendar (tasks + events + deadlines).
        case calendar
        case appliances
        case seasonal
        /// The primary property's own page (value history lives there).
        case propertyDetails
        /// The "Today at home" chronological feed.
        case houseFeed

        var id: String { rawValue }
    }

    /// The single routed sheet slot (MainTabView presents it). Reserved for
    /// self-contained tasks — creation forms, scanning, the notification
    /// panel — per the HIG's modality rule.
    var activeDestination: RoutedDestination?
    /// The single routed full-screen-cover slot (ARIA today).
    var activeCover: RoutedDestination?

    // MARK: - Content pages push, tasks present
    //
    // Content modules (Finances, Documents, Inventory…) are destinations,
    // not tasks: they push onto the current tab's navigation stack — large
    // title, edge-swipe back, context preserved — instead of floating up as
    // sheets. Each tab's NavigationStack binds its own path here.

    /// Per-tab pushed content pages (value-based navigation destinations).
    var tabPaths: [AppTab: [RoutedDestination]] = [:]

    /// Pushes a content page onto the current tab's stack (no-op when that
    /// page is already on top, so a double-tap can't stack duplicates).
    func push(_ destination: RoutedDestination) {
        guard tabPaths[selectedTab]?.last != destination else { return }
        tabPaths[selectedTab, default: []].append(destination)
    }

    // Deep link destinations
    var deepLinkTaskId: UUID?
    var deepLinkPlantId: UUID?
    var deepLinkDocumentId: UUID?

    // MARK: - Single navigation authority
    //
    // Widgets, quick actions, notifications and deep links all funnel
    // through `navigate(to:)`. Before the app is ready the route is
    // buffered; while something is on screen the route is parked in
    // `pendingRoute` and drained by the closing sheet's `onDismiss` —
    // event-driven instead of a fixed sleep that raced the dismissal.

    /// Every full-screen destination an external entry point can request.
    enum AppRoute: Equatable {
        case home, tasks(id: UUID?), newTask, plants(id: UUID?), supplies,
             pantry, cameras, deliveries, chat, familyChat, scan, receipts,
             notifications, notificationsChat, aria, twin, settings,
             documents(id: UUID?), finances,
             inventory, family, profile, contractors, paintColors,
             photoJournal, addSupply, communities(groupId: UUID?), emergency,
             iotHub, calendar, appliances, seasonal, propertyDetails, houseFeed
    }

    /// Bumped when an external entry point asks for a chat group; groups are
    /// rows in the conversations list, which observes this and pushes the
    /// thread for `deepLinkCommunityGroupId` when one was requested.
    private(set) var communitiesRequest = 0
    var deepLinkCommunityGroupId: UUID?

    /// Bumped on every close-all — screens that own local sheets (Dashboard's
    /// search / notifications / health) observe it and dismiss theirs too.
    private(set) var dismissGeneration = 0

    /// Set by screens while one of their local sheets is up, so `navigate`
    /// knows a handoff is needed even though no routed slot is active.
    var hasLocalPresentation = false

    /// False until MainTabView finishes its cold-start role resolution.
    /// Routes arriving earlier (widget cold launches, quick actions) are
    /// buffered in `pendingRoute` — the onChange relays they used to rely on
    /// can't fire for values set before the view exists.
    private(set) var isReady = false

    /// A route waiting for the stage to clear (app not ready yet, or a
    /// presentation is still animating out). Drained by `drainPending()`.
    var pendingRoute: AppRoute?

    /// The last deep link handled, for deduping double delivery of a single
    /// Control Center tap (OpenURLIntent + App Group hand-off).
    @ObservationIgnored private var lastDeepLink: (url: URL, at: Date)?

    // MARK: - Scan landing (IMG_8718 request: "o pagină specială la scanare")
    //
    // A scanned QR — the printed item labels (https://xparvu.com/i/<uuid>),
    // the new plant labels (/p/<uuid>) or their prvio:// equivalents — opens
    // a dedicated landing sheet instead of dropping the user somewhere in
    // the module. The sheet exists ONLY through this entry point.

    /// What a scanned code resolved to.
    enum ScanTarget: Identifiable, Equatable {
        case item(UUID)
        case plant(UUID)
        var id: String {
            switch self {
            case .item(let u):  "item-\(u.uuidString)"
            case .plant(let u): "plant-\(u.uuidString)"
            }
        }
    }

    /// The scan-landing sheet slot (MainTabView presents it).
    var scanLanding: ScanTarget?
    /// A scan waiting for the stage to clear (cold launch / open sheet).
    private var pendingScan: ScanTarget?

    /// Routes a scanned code to the landing sheet, respecting the same
    /// stage rules as `navigate(to:)` — never fights a live presentation.
    func presentScanLanding(_ target: ScanTarget) {
        guard isReady else { pendingScan = target; return }
        if scanLanding != nil {
            // Already showing a landing: swap content in place.
            scanLanding = target
            return
        }
        guard anyPresentationActive else {
            scanLanding = target
            return
        }
        pendingScan = target
        closeAllPresentations()
    }

    private var anyPresentationActive: Bool {
        activeDestination != nil || activeCover != nil || hasLocalPresentation
            || scanLanding != nil
    }

    /// Dismisses every routed presentation, so the next one has the stage.
    func closeAllPresentations() {
        activeDestination = nil
        activeCover = nil
        scanLanding = nil
        dismissGeneration &+= 1
    }

    /// Called once MainTabView's cold-start role resolution completed —
    /// presentations applied before that point would be dropped by the
    /// initial mount.
    func markReady() {
        guard !isReady else { return }
        isReady = true
        drainPending()
    }

    /// Applies whatever route was parked while a presentation was in flight.
    /// Wired to the `onDismiss` of every routed/local sheet so handoffs are
    /// driven by the actual end of the dismissal, not a timer.
    func drainPending() {
        guard isReady else { return }
        // Never navigate while backgrounded: a parked route draining after
        // the user left (sheet dismissal completing mid-background-transition)
        // ran a NavigationStack push in a background process — the b1179
        // 0x8BADF00D shows the exit watchdog catching exactly that push.
        // The route stays parked; scene-activation re-drains it.
        guard !AppLifecycle.isBackgrounded else { return }
        if let scan = pendingScan {
            pendingScan = nil
            presentScanLanding(scan)
            return
        }
        guard let route = pendingRoute else { return }
        pendingRoute = nil
        navigate(to: route)
    }

    func navigate(to route: AppRoute) {
        guard isReady else {
            pendingRoute = route
            return
        }
        guard anyPresentationActive else {
            apply(route)
            return
        }
        // Something is on screen: park the route, start the dismissal, and
        // let the closing sheet's onDismiss drain it once UIKit is done.
        pendingRoute = route
        closeAllPresentations()
    }

    private func apply(_ route: AppRoute) {
        switch route {
        // Tabs
        case .home:
            selectedTab = .home
        case .tasks(let id):
            selectedTab = .tasks
            deepLinkTaskId = id
        case .chat, .familyChat:
            // The family conversation IS the chat tab — switching there beats
            // presenting a second copy of it as a sheet.
            selectedTab = .chat
        case .twin:
            selectedTab = .digitalTwin
        case .settings:
            selectedTab = .settings

        // Content destinations — push on the current tab (HIG: hierarchical
        // navigation for places, modality for tasks).
        case .plants(let id):
            deepLinkPlantId = id
            push(.plants)
        case .supplies:
            push(.supplies)
        case .pantry:
            push(.pantry)
        case .cameras:
            push(.cameras)
        case .deliveries:
            push(.deliveries)
        case .documents(let id):
            deepLinkDocumentId = id
            push(.documents)
        case .finances:
            push(.finances)
        case .inventory:
            push(.inventory)
        case .family:
            push(.family)
        case .profile:
            selectedTab = .settings
            push(.profile)
        case .contractors:
            push(.contractors)
        case .paintColors:
            push(.paintColors)
        case .photoJournal:
            push(.photoJournal)
        case .emergency:
            // The burst-pipe page: reachable from its Live Activity with one
            // tap, wherever it was pinned from.
            selectedTab = .settings
            push(.emergency)
        case .iotHub:
            // Sensor alert / energy / cover Live Activities land here.
            selectedTab = .settings
            push(.iotHub)
        case .calendar:
            push(.calendar)
        case .appliances:
            push(.appliances)
        case .seasonal:
            push(.seasonal)
        case .propertyDetails:
            push(.propertyDetails)
        case .houseFeed:
            push(.houseFeed)

        // Self-contained tasks — sheets / covers.
        case .newTask:
            selectedTab = .tasks
            activeDestination = .newTask
        case .scan:
            // A camera — full-screen cover, never a sheet that leaves the page
            // visible behind it (and never the inventory module wrapped in a
            // sheet, which stacked the scanner as a second sheet on top).
            activeCover = .inventoryScan
        case .receipts:
            // "Scan Receipt" (Control Center / prvio://receipts) opens the
            // camera OCR receipt scanner — NOT the manual add-transaction form
            // (that is .addExpense, reachable from the Finances FAB action).
            // Camera → full-screen cover so nothing shows through behind it.
            activeCover = .receiptScan
        case .notifications:
            selectedTab = .home
            activeDestination = .notifications
        case .notificationsChat:
            // Opened from the conversations bell — stay on the chat tab.
            activeDestination = .notificationsChat
        case .aria:
            activeCover = .aria
        case .addSupply:
            activeDestination = .addSupply
        case .communities(let groupId):
            selectedTab = .chat
            deepLinkCommunityGroupId = groupId
            communitiesRequest &+= 1
        }
    }

    func perform(_ action: DashboardQuickAction) {
        switch action {
        // Destinations go through navigate() so an open sheet is dismissed
        // first and the push lands on a visible stack.
        case .aria:       navigate(to: .aria)
        case .finances:   navigate(to: .finances)
        case .chat:       navigate(to: .chat)
        case .waterPlant: navigate(to: .plants(id: nil))
        case .documents:  navigate(to: .documents(id: nil))
        case .deliveries: navigate(to: .deliveries)
        case .digitalTwin: selectedTab = .digitalTwin
        // Creation forms stay modal sheets (HIG). Cameras go full-screen.
        case .newTask:    activeDestination = .newTask
        case .addExpense: activeDestination = .addExpense
        case .scan:       activeCover = .inventoryScan
        case .addItem:    activeCover = .inventoryAdd
        case .addSupply:  activeDestination = .addSupply
        }
    }

    /// Set by a scanned QR label (universal link or prvio://inventory/<id>);
    /// InventoryView consumes it once its items are loaded and opens the
    /// item's detail sheet.
    var pendingInventoryItemId: UUID?

    func handle(deepLink url: URL) {
        // Universal links https://xparvu.com/i/<uuid> (item labels) and
        // /p/<uuid> (plant labels): the camera scan lands on the dedicated
        // scan sheet, never somewhere generic in the module.
        if url.scheme == "https", url.host == "xparvu.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            if parts.first == "i", let iid = parts.dropFirst().first.flatMap(UUID.init(uuidString:)) {
                presentScanLanding(.item(iid))
            } else if parts.first == "p", let pid = parts.dropFirst().first.flatMap(UUID.init(uuidString:)) {
                presentScanLanding(.plant(pid))
            }
            return
        }
        guard url.scheme == "prvio" else { return }
        // One Control Center tap can arrive twice — once through the
        // OpenURLIntent and once through the App Group hand-off. Navigating
        // twice would stack the same page, so an identical link within a
        // short window is the same tap.
        if let last = lastDeepLink, last.url == url,
           Date().timeIntervalSince(last.at) < 2 { return }
        lastDeepLink = (url, Date())
        let host = url.host ?? ""
        let pathComponents = url.pathComponents.filter { $0 != "/" }
        let pathId = pathComponents.first.flatMap(UUID.init(uuidString:))
        switch host {
        case "", "home", "dashboard":
            navigate(to: .home)
        case "tasks":
            navigate(to: pathComponents.first == "new" ? .newTask : .tasks(id: pathId))
        case "plants":
            navigate(to: .plants(id: pathId))
        case "shopping", "supplies":
            navigate(to: .supplies)
        case "pantry":
            navigate(to: .pantry)
        case "cameras":
            navigate(to: .cameras)
        case "deliveries", "packages":
            navigate(to: .deliveries)
        case "chat":
            navigate(to: .chat)
        case "communities", "groups":
            navigate(to: .communities(groupId: pathId))
        case "scan":
            navigate(to: .scan)
        case "receipts":
            navigate(to: .receipts)
        case "alerts", "notifications":
            navigate(to: .notifications)
        case "aria", "ai":
            navigate(to: .aria)
        case "twin", "map":
            navigate(to: .twin)
        case "settings":
            navigate(to: .settings)
        case "emergency":
            navigate(to: .emergency)
        case "iot":
            navigate(to: .iotHub)
        case "documents":
            navigate(to: .documents(id: pathId))
        case "finances":
            navigate(to: .finances)
        case "inventory":
            // A specific item id means a SCAN context ("Deschide în PRVIO"
            // from the public page, or the app's own label) — the landing
            // sheet, not the bare module. No id keeps the module route.
            if let pathId {
                presentScanLanding(.item(pathId))
            } else {
                navigate(to: .inventory)
            }
        case "plant":
            // prvio://plant/<uuid> — the plant label's scheme fallback.
            if let pathId { presentScanLanding(.plant(pathId)) }
        case "family", "members":
            navigate(to: .family)
        case "profile":
            navigate(to: .profile)
        case "nfc":
            // A physical tag written by the NFC wallet (prvio://nfc/<tagId>).
            // Resolve the saved tag and open the place it's linked to: zones,
            // elements and appliances all live in the property twin — the
            // closest existing route (there is no appliances AppRoute).
            guard let tag = pathComponents.first.flatMap(NFCTagStore.tag(withId:)) else {
                navigate(to: .home)
                return
            }
            switch tag.linkedType {
            case "zone", "element", "appliance":
                navigate(to: .twin)
            default:
                navigate(to: .home)
            }
        default:
            break
        }
    }

    /// Translates a tapped in-app notification into the route for the thing
    /// it's about. Prefers the typed module + resource id; falls back to
    /// parsing the action_url path the DB triggers write ("/maintenance/<id>").
    /// Exposed so NotificationCenterView can park the route in `pendingRoute`
    /// before dismissing itself.
    func route(forNotificationModule module: String?, actionUrl: String?, resourceId: UUID?) -> AppRoute {
        let id = resourceId ?? Self.firstUUID(in: actionUrl ?? "")
        switch module ?? "" {
        case "chat":                    return .chat
        case "maintenance", "tasks":    return .tasks(id: id)
        case "garden", "plants":        return .plants(id: id)
        case "documents", "document":   return .documents(id: id)
        case "inventory":               return .inventory
        case "finance", "finances":     return .finances
        case "delivery", "deliveries":  return .deliveries
        case "family", "members":       return .family
        case "aria":                    return .aria
        case "security":                return .settings
        default:                        return .home
        }
    }

    /// Routes a tapped in-app notification to the thing it's about.
    func handle(notificationModule module: String?, actionUrl: String?, resourceId: UUID?) {
        navigate(to: route(forNotificationModule: module,
                           actionUrl: actionUrl,
                           resourceId: resourceId))
    }

    private static func firstUUID(in path: String) -> UUID? {
        path.split(separator: "/").lazy.compactMap { UUID(uuidString: String($0)) }.first
    }

    func handle(quickActionType type: String) {
        // "opentask" carries the task id in the type string ("…opentask:<uuid>")
        // because userInfo doesn't survive the cold-launch UserDefaults hand-off.
        if type.hasPrefix("com.prvio.action.opentask") {
            let id = type.split(separator: ":").last.flatMap { UUID(uuidString: String($0)) }
            navigate(to: .tasks(id: id))
            return
        }
        switch type {
        case "com.prvio.action.addtask":    navigate(to: .newTask)
        case "com.prvio.action.plants":     navigate(to: .plants(id: nil))
        case "com.prvio.action.shopping":
            // The list, not the add-item form — the shortcut says "Shopping List".
            navigate(to: .supplies)
        case "com.prvio.action.deliveries": navigate(to: .deliveries)
        case "com.prvio.action.chat":       navigate(to: .chat)
        case "com.prvio.action.scan":       navigate(to: .scan)
        case "com.prvio.action.home":       navigate(to: .home)
        default: break
        }
    }

    func handle(userActivity activity: NSUserActivity) {
        // Universal links arrive as a browsing-web activity carrying the
        // scanned URL — previously DROPPED here (only Spotlight and tab
        // payloads were handled), which is why a camera scan opened the app
        // on whatever screen was last up instead of the item (IMG_8718).
        if activity.activityType == NSUserActivityTypeBrowsingWeb,
           let url = activity.webpageURL {
            handle(deepLink: url)
            return
        }
        if activity.activityType == "CSSearchableItemActionType" {
            guard let id = activity.userInfo?["kCSSearchableItemActivityIdentifier"] as? String else { return }
            if id.hasPrefix("task-"), let uuid = UUID(uuidString: String(id.dropFirst(5))) {
                navigate(to: .tasks(id: uuid))
            } else if id.hasPrefix("plant-"), let uuid = UUID(uuidString: String(id.dropFirst(6))) {
                navigate(to: .plants(id: uuid))
            }
        } else if let tab = activity.userInfo?["tab"] as? String {
            switch tab {
            case "tasks":      navigate(to: .tasks(id: nil))
            case "chat":       navigate(to: .chat)
            case "home":       navigate(to: .home)
            case "plants":     navigate(to: .plants(id: nil))
            case "supplies":   navigate(to: .supplies)
            case "pantry":     navigate(to: .pantry)
            case "deliveries": navigate(to: .deliveries)
            case "map":        navigate(to: .twin)
            default: break
            }
        }
    }
}
