import SwiftUI

// MARK: - Routes: pager pages, Home hub modules, deep links, Handoff
//
// Visibility is decided here and nowhere else, so the pager, the Today
// tiles, the hub and deep links can never disagree about what exists — the
// old app's tiles and links could select pages missing from the pager.

/// A top-level page of the vertical pager, in pager order.
enum WatchPage: String, CaseIterable, Hashable, Identifiable {
    case today, tasks, plants, home

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .today:  return "watch_menu_today"
        case .tasks:  return "watch_menu_tasks"
        case .plants: return "watch_menu_plants"
        case .home:   return "watch_page_home"
        }
    }

    var systemImage: String {
        switch self {
        case .today:  return "sun.max.fill"
        case .tasks:  return "checklist"
        case .plants: return "leaf.fill"
        case .home:   return "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .today:  return WatchTheme.Tint.today
        case .tasks:  return WatchTheme.Tint.tasks
        case .plants: return WatchTheme.Tint.plants
        case .home:   return WatchTheme.Tint.home
        }
    }

    /// The phone's `pageOrder` key, for the pages the owner can hide.
    fileprivate var orderKey: String? {
        switch self {
        case .tasks:  return "tasks"
        case .plants: return "plants"
        case .today, .home: return nil
        }
    }
}

/// A row of the Home hub, pushed in a NavigationStack.
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

    /// What needs the user in this module, as a row badge — nil when
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

/// A count badge on a hub row.
struct WatchBadge: Equatable {
    let count: Int
    let isUrgent: Bool
}

/// A value pushed onto any page's NavigationStack. Destinations are
/// registered once per stack by RootView (`watchDestinations`), so feature
/// views push these and never register them again.
enum WatchDestination: Hashable, Codable {
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

    /// The pager, in order: Today (always), Tasks and Plants as the owner
    /// ordered and enabled them, then Home when any module is visible.
    /// Tasks stays while enabled even with no open task — the all-clear is
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
        if !visibleModules(for: payload).isEmpty { pages.append(.home) }
        return pages
    }

    /// The hub rows, in order: Messages first (communication leads), the
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

    // MARK: Handoff

    static let handoffActivityType = "com.prvio.page"

    /// `userInfo["tab"]` for the phone router: the pushed module when there
    /// is one the phone has a tab for, else the page.
    static func handoffTab(page: WatchPage, module: WatchModule?) -> String {
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
        case .today, .home:  return "home"
        }
    }
}
