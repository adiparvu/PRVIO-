import Foundation
import UserNotifications
import WatchKit

// MARK: - Critical sensor alerts (local, on the wrist)
//
// Fires exactly on the TRANSITION into critical (smoke / gas / water
// alerting), deduplicated across launches by persisting the set of
// currently-critical sensor ids — a refresh while the leak is still active
// must not re-alarm. Honest scope: detection runs when a payload reaches
// the watch app (push or refresh); the watch has no background channel of
// its own. Banners show in the foreground through the app delegate.

@MainActor
enum WatchSensorAlerts {
    /// Frozen notification identifier prefix.
    static let identifierPrefix = "prvio.sensor."
    /// Frozen defaults key.
    static let criticalIdsKey = "prvio.watch.criticalSensorIds"

    /// Compares the payload's critical sensors with the stored set; taps the
    /// wrist and posts one notification per sensor that just went critical.
    static func evaluate(_ payload: WatchPayload, defaults: UserDefaults) {
        let critical = payload.sensors.filter { $0.isCritical && $0.isAlerting }
        let previous = storedIds(defaults)
        let current = Set(critical.map(\.id))
        guard current != previous else { return }
        defaults.set(current.map(\.uuidString), forKey: criticalIdsKey)
        // Sensors that recovered: their banners are stale now.
        let recovered = previous.subtracting(current)
        if !recovered.isEmpty {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: recovered.map(identifier(for:)))
        }
        let fresh = critical.filter { !previous.contains($0.id) }
        guard !fresh.isEmpty else { return }
        WKInterfaceDevice.current().play(.failure)
        let alerts = fresh.map { sensor in
            (id: identifier(for: sensor.id),
             body: [sensor.name, sensor.zone, sensor.displayValue]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = String(localized: "watch_sensor_alert_title")
                content.body = alert.body
                content.sound = .default
                try? await center.add(UNNotificationRequest(identifier: alert.id,
                                                            content: content, trigger: nil))
            }
        }
    }

    /// Forgets every alert — the account changed or signed out. Removes the
    /// banners too, so the next owner never sees the previous home's alarms.
    static func reset(defaults: UserDefaults) {
        let ids = storedIds(defaults).map(identifier(for:))
        defaults.removeObject(forKey: criticalIdsKey)
        guard !ids.isEmpty else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ids)
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private static func storedIds(_ defaults: UserDefaults) -> Set<UUID> {
        Set((defaults.stringArray(forKey: criticalIdsKey) ?? []).compactMap(UUID.init(uuidString:)))
    }

    private static func identifier(for id: UUID) -> String {
        identifierPrefix + id.uuidString
    }
}
