import SwiftUI

// MARK: - Routes: sections, deep links, Handoff
//
// The app is one list of sections (the sidebar of a collapsed
// NavigationSplitView) and the section on screen. Visibility is decided
// here and nowhere else, so the list, the Today tiles and deep links can
// never disagree about what exists.

/// A first-class section: Today and the two daily lists.
enum WatchPage: String, CaseIterable, Hashable, Identifiable, Codable {
    case today, tasks, plants

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:  return "watch_menu_today"
        case .tasks:  return "watch_menu_tasks"
        case .plants: return "watch_menu_plants"
        }
    }

    var systemImage: String {
        switch self {
        case .today:  return "sun.max.fill"
        case .tasks:  return "checklist"
        case .plants: return "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today:  return WatchTheme.Tint.today
        case .tasks:  return WatchTheme.Tint.tasks
        case .plants: return WatchTheme.Tint.plants
        }
    }

    /// The phone's `pageOrder` key, for the pages the owner can hide.
    fileprivate var orderKey: String? {
        switch self {
        case .tasks:  return "tasks"
        case .plants: return "plants"
        case .today:  return nil
        }
    }
}

/// Every other surface of the house.
enum WatchModule: String, CaseIterable, Hashable, Identifiable, Codable {
    case shopping, pantry, deliveries, messages, map, controls, sensors, emergency

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .shopping:   return "watch_menu_shopping"
        case .pantry:     return "watch_menu_pantry"
        case .deliveries: return "watch_menu_deliveries"
        case .messages:   return "watch_menu_messages"
        case .map:        return "watch_menu_map"
        case .controls:   return "watch_menu_controls"
        case .sensors:    return "watch_menu_sensors"
        case .emergency:  return "watch_menu_emergency"
        }
    }

    var systemImage: String {
        switch self {
        case .shopping:   return "cart.fill"
        case .pantry:     return "cabinet.fill"
        case .deliveries: return "shippingbox.fill"
        case .messages:   return "message.fill"
        case .map:        return "map.fill"
        case .controls:   return "switch.2"
        case .sensors:    return "sensor.fill"
        case .emergency:  return "cross.case.fill"
        }
    }

    var tint: Color {
        switch self {
        case .shopping:   return WatchTheme.Tint.shopping
        case .pantry:     return WatchTheme.Tint.pantry
        case .deliveries: return WatchTheme.Tint.deliveries
        case .messages:   return WatchTheme.Tint.messages
        case .map:        return WatchTheme.Tint.map
        case .controls:   return WatchTheme.Tint.controls
        case .sensors:    return WatchTheme.Tint.sensors
        case .emergency:  return WatchTheme.Tint.emergency
        }
    }

    /// Smart-home control, live sensors and the family's emergency plan
    /// never surface for an outsider (tenant / guest / worker) payload.
    var requiresFamilyScope: Bool {
        switch self {
        case .controls, .sensors, .emergency: return true
        default: return false
        }
    }

    /// The phone's `pageOrder` key, for the modules the owner can hide and
    /// reorder. Modules without one are governed by data and scope only.
    fileprivate var orderKey: String? {
        switch self {
        case .shopping:   return "shopping"
        case .pantry:     return "pantry"
        case .deliveries: return "deliveries"
        case .map:        return "map"
        case .messages, .controls, .sensors, .emergency: return nil
        }
    }

    /// True when the module has something real to show for this payload.
    func hasContent(in payload: WatchPayload) -> Bool {
        switch self {
        case .shopping:   return payload.supplies.contains { !$0.isCompleted }
        case .pantry:     return !payload.pantry.isEmpty
        case .deliveries: return !payload.deliveries.isEmpty
        case .messages:   return !payload.dmConversations.isEmpty
        case .map:        return payload.latitude != nil && payload.longitude != nil
        case .controls:   return !payload.actuators.isEmpty
        case .sensors:    return !payload.sensors.isEmpty
        case .emergency:
            return WatchRoute.canAlertFamily(payload)
                || !payload.emergencyContacts.isEmpty
                || !payload.emergencySteps.isEmpty
        }
    }

    /// What needs the user in this module, as a section-row badge — nil when
    /// nothing does (a badge is a call to act, not an inventory count).
    func badge(in payload: WatchPayload) -> WatchBadge? {
        let count: Int
        var urgent = false
        switch self {
        case .shopping:
            count = payload.supplies.filter { !$0.isCompleted }.count
        case .pantry:
            count = payload.pantry.filter { $0.quantity <= 0 }.count
        case .deliveries:
            count = payload.deliveries.filter(WatchRoute.isDeliveryActive).count
        case .messages:
            count = payload.dmConversations.reduce(0) { $0 + max(0, $1.unread) }
        case .sensors:
            let alerting = payload.sensors.filter(\.isAlerting)
            count = alerting.count
            urgent = alerting.contains(where: \.isCritical)
        case .map, .controls, .emergency:
            return nil
        }
        return count > 0 ? WatchBadge(count: count, isUrgent: urgent) : nil
    }
}

/// A count badge on a section row.
struct WatchBadge: Equatable {
    let count: Int
    let isUrgent: Bool
}

/// How the home is doing, read from the payload — drives the sky's warmth,
/// the dial and the headline. Never shown by colour alone.
enum WatchHouseholdState: Equatable, Sendable {
    /// Nothing due now.
    case calm
    /// Something waits (overdue task, thirsty plant, alerting sensor).
    case attention
    /// A critical sensor is alarming (family scope only).
    case alarm
}

/// The one thing Next Up offers, with the entry its one-tap action needs.
enum WatchNextUp: Identifiable {
    case task(TaskCatalogEntry, isOverdue: Bool)
    case plant(PlantCatalogEntry)
    case delivery(DeliveryCatalogEntry)

    /// Stable per item, so the card cross-fades only when the item changes.
    var id: String {
        switch self {
        case .task(let task, _):    return "task-\(task.id.uuidString)"
        case .plant(let plant):     return "plant-\(plant.id.uuidString)"
        case .delivery(let parcel): return "delivery-\(parcel.id.uuidString)"
        }
    }
}

/// Which list a local edit just emptied (see `WatchStore.allClearEvent`).
enum WatchClearScope: Hashable, Sendable {
    case tasks, plants, shopping
    /// Tasks, thirsty plants and shopping together reached zero.
    case household
}

/// One all-clear moment caused by the person on this wrist. `serial`
/// grows per launch and is never persisted, so a reload or relaunch can
/// never replay a celebration.
struct WatchAllClearEvent: Equatable, Sendable {
    let serial: Int
    let scopes: Set<WatchClearScope>
}

/// One row of the sections list and the screen it opens. Wraps the two
/// vocabularies so the list, the selection and Handoff share one type.
enum WatchSection: Hashable, Identifiable, Codable {
    case page(WatchPage)
    case module(WatchModule)

    static let today = WatchSection.page(.today)

    var id: String {
        switch self {
        case .page(let page):     return "page-\(page.rawValue)"
        case .module(let module): return "module-\(module.rawValue)"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .page(let page):     return page.titleKey
        case .module(let module): return module.titleKey
        }
    }

    var systemImage: String {
        switch self {
        case .page(let page):     return page.systemImage
        case .module(let module): return module.systemImage
        }
    }

    var tint: Color {
        switch self {
        case .page(let page):     return page.tint
        case .module(let module): return module.tint
        }
    }
}

/// A value pushed onto a section's NavigationStack. Destinations are
/// registered once per stack by RootView (`watchDestinations`), so feature
/// views push these and never register them again. Today's tiles push
/// `.page` / `.module` so the back chevron returns to Today.
enum WatchDestination: Hashable, Codable {
    case page(WatchPage)
    case module(WatchModule)
    case workSession
}

/// A `prvio://<host>` link resolved against the frozen host vocabulary.
enum WatchDeepLink: Equatable {
    case page(WatchPage)
    case module(WatchModule)

    /// Complication and widget taps. Unknown or missing hosts land on Today.
    init(url: URL) {
        switch url.host?.lowercased() {
        case "tasks":                  self = .page(.tasks)
        case "plants":                 self = .page(.plants)
        case "shopping", "supplies":   self = .module(.shopping)
        case "pantry":                 self = .module(.pantry)
        case "deliveries", "packages": self = .module(.deliveries)
        case "messages":               self = .module(.messages)
        case "emergency":              self = .module(.emergency)
        default:                       self = .page(.today)
        }
    }
}

enum WatchRoute {
    /// The phone's page vocabulary when it has not sent a preference.
    static let defaultOrder = ["tasks", "plants", "shopping", "pantry", "deliveries", "map"]

    /// The owner's order, deduplicated — a cached payload from an older
    /// phone build can repeat keys, and duplicate ForEach identities crash.
    static func pageOrder(for payload: WatchPayload) -> [String] {
        var seen = Set<String>()
        return (payload.pageOrder ?? defaultOrder).filter { seen.insert($0).inserted }
    }

    /// The first-class sections, in order: Today (always), then Tasks and
    /// Plants as the owner ordered and enabled them. Tasks stays while enabled even with no open task — the all-clear is
    /// real information and the page hosts dictating a new one. Plants
    /// needs at least one plant.
    static func visiblePages(for payload: WatchPayload?) -> [WatchPage] {
        guard let payload else { return [.today] }
        let order = pageOrder(for: payload)
        var pages: [WatchPage] = [.today]
        let ordered = [WatchPage.tasks, .plants]
            .compactMap { page -> (WatchPage, Int)? in
                guard let key = page.orderKey, let index = order.firstIndex(of: key) else { return nil }
                return (page, index)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        for page in ordered {
            switch page {
            case .plants: if !payload.plants.isEmpty { pages.append(page) }
            default:      pages.append(page)
            }
        }
        return pages
    }

    /// The sections list, as groups shown with a gap between them:
    /// 1. Today — where the app opens;
    /// 2. the everyday lists — Tasks, Plants and the owner-ordered modules,
    ///    with Messages first (communication leads);
    /// 3. the house's systems — Controls, Sensors, Emergency (family only).
    /// Empty groups are dropped.
    static func sectionGroups(for payload: WatchPayload?) -> [[WatchSection]] {
        let pages = visiblePages(for: payload)
        let modules = visibleModules(for: payload)
        let systems: Set<WatchModule> = [.controls, .sensors, .emergency]
        let everyday = pages.filter { $0 != .today }.map(WatchSection.page)
        var daily = modules.filter { !systems.contains($0) }.map(WatchSection.module)
        if daily.first == .module(.messages) {
            daily.removeFirst()
            daily = [.module(.messages)] + everyday + daily
        } else {
            daily = everyday + daily
        }
        let house = modules.filter(systems.contains).map(WatchSection.module)
        return [[.today], daily, house].filter { !$0.isEmpty }
    }

    /// Every section on the list, in order.
    static func visibleSections(for payload: WatchPayload?) -> [WatchSection] {
        sectionGroups(for: payload).flatMap { $0 }
    }

    /// The visible modules, in order: Messages first (communication leads), the
    /// owner-ordered modules, then Controls, Sensors, Emergency. A module is
    /// listed only when it has content, the owner has not hidden it, and —
    /// for family surfaces — the payload is family-scoped.
    static func visibleModules(for payload: WatchPayload?) -> [WatchModule] {
        guard let payload else { return [] }
        let order = pageOrder(for: payload)
        let ordered = WatchModule.allCases
            .compactMap { module -> (WatchModule, Int)? in
                guard let key = module.orderKey, let index = order.firstIndex(of: key) else { return nil }
                return (module, index)
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
        let candidates: [WatchModule] = [.messages] + ordered + [.controls, .sensors, .emergency]
        return candidates.filter { module in
            (!module.requiresFamilyScope || payload.isFamilyScope) && module.hasContent(in: payload)
        }
    }

    /// "Alert the family" names the property, exactly like the iPhone's
    /// Emergency page guard.
    static func canAlertFamily(_ payload: WatchPayload) -> Bool {
        payload.isFamilyScope && !(payload.snapshot.propertyName ?? "").isEmpty
    }

    /// A parcel still on its way.
    static func isDeliveryActive(_ parcel: DeliveryCatalogEntry) -> Bool {
        parcel.status == "expected" || parcel.status == "out_for_delivery"
    }

    /// A parcel at the door today — the only delivery state worth Next Up.
    static func isOutForDelivery(_ parcel: DeliveryCatalogEntry) -> Bool {
        parcel.status == "out_for_delivery"
    }

    // MARK: Household reading (read-only, derived from the payload)

    /// How the home is doing — the sky's warmth. Alarm only for a critical
    /// sensor (family scope); attention when something is due now (an
    /// overdue task, a thirsty plant, an alerting sensor); calm otherwise —
    /// open-but-not-due tasks are calm, never pressure.
    static func householdState(for payload: WatchPayload?) -> WatchHouseholdState {
        guard let payload else { return .calm }
        if payload.isFamilyScope,
           payload.sensors.contains(where: { $0.isAlerting && $0.isCritical }) {
            return .alarm
        }
        return attentionCount(for: payload) > 0 ? .attention : .calm
    }

    /// The things due now: overdue tasks + thirsty plants + alerting
    /// sensors (family scope). Rising means "something new needs you".
    static func attentionCount(for payload: WatchPayload?) -> Int {
        guard let payload else { return 0 }
        let overdue = payload.tasks.filter { !$0.isCompleted && $0.isOverdue == true }.count
        let thirsty = payload.plants.filter(\.needsWatering).count
        let alerting = payload.isFamilyScope ? payload.sensors.filter(\.isAlerting).count : 0
        return overdue + thirsty + alerting
    }

    /// Open household items the person can clear from the wrist: open
    /// tasks, thirsty plants and unbought shopping items. Zero = all clear.
    static func openItemCount(for payload: WatchPayload?) -> Int {
        guard let payload else { return 0 }
        return payload.tasks.filter { !$0.isCompleted }.count
            + payload.plants.filter(\.needsWatering).count
            + payload.supplies.filter { !$0.isCompleted }.count
    }

    /// The single most useful thing right now, in the brief's order:
    /// overdue task → thirsty plant → parcel out for delivery → next open
    /// task. Each candidate is offered only when its page or module is
    /// visible, so Next Up never acts on a surface the owner hid.
    static func nextUp(for payload: WatchPayload?) -> WatchNextUp? {
        guard let payload else { return nil }
        let pages = visiblePages(for: payload)
        let modules = visibleModules(for: payload)
        let open = pages.contains(.tasks) ? payload.tasks.filter { !$0.isCompleted } : []
        if let overdue = open.first(where: { $0.isOverdue == true }) {
            return .task(overdue, isOverdue: true)
        }
        if pages.contains(.plants), let plant = payload.plants.first(where: \.needsWatering) {
            return .plant(plant)
        }
        if modules.contains(.deliveries),
           let parcel = payload.deliveries.first(where: WatchRoute.isOutForDelivery) {
            return .delivery(parcel)
        }
        if let next = open.first {
            return .task(next, isOverdue: false)
        }
        return nil
    }

    // MARK: Handoff

    static let handoffActivityType = "com.prvio.page"

    /// `userInfo["tab"]` for the phone router: the module on screen (the
    /// section itself, or one pushed on top of it) when the phone has a tab
    /// for it, else the page.
    static func handoffTab(section: WatchSection, pushed: WatchModule?) -> String {
        let module: WatchModule?
        let page: WatchPage
        switch section {
        case .page(let p):   page = p; module = pushed
        case .module(let m): page = .today; module = m
        }
        switch module {
        case .some(.shopping): return "supplies"
        case .some(.messages): return "chat"
        case .some(.map):      return "map"
        case .some:            return "home"
        case .none:            break
        }
        switch page {
        case .tasks:         return "tasks"
        case .plants:        return "plants"
        case .today:         return "home"
        }
    }
}
