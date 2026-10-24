import CoreLocation
import Foundation

// MARK: - When-in-Use location, asked once
//
// The watch never reads or tracks a location itself. The grant exists only so
// the system can match the "Now at home" card's `.location(inferred: .home)`
// relevance clue: on watchOS the app must run and ask once, and its
// complications and widgets then ride on that authorization (watchOS has no
// NSWidgetWantsLocation / per-widget extension prompt).
//
// Asked at most once, ever, and never at launch: the first time the person
// opens the Home page with a home to show. "Asked" lives in the App Group
// defaults, so a denial is final — the person can still change it in
// Settings, and the evening time window keeps working without it.
//
// Core Location calls the delegate on the run loop of the thread that created
// the manager; it is created here on the main actor, but the delegate method
// stays nonisolated (the protocol is not main-actor annotated) and hops back
// explicitly.

@MainActor
final class WatchLocationPermission: NSObject {
    static let shared = WatchLocationPermission()

    /// App Group defaults key; true once the prompt was offered (or was not
    /// needed because a decision already existed).
    static let askedKey = "prvio.watch.locationAsked"

    /// Held only while a prompt is pending — releasing it early would drop
    /// the delegate callback; nothing keeps running afterwards.
    private var manager: CLLocationManager?

    private override init() {
        super.init()
    }

    /// Offers the When-in-Use prompt if it has never been offered. No-op
    /// after the first call, in previews, and whenever a decision exists.
    func requestIfNeeded(defaults: UserDefaults = UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard) {
        guard !defaults.bool(forKey: Self.askedKey), manager == nil else { return }
        // Previews must never mark the real flag or show a system alert.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }

        let manager = CLLocationManager()
        // Recorded before prompting: a crash or force-quit mid-prompt must
        // not turn into a second prompt later.
        defaults.set(true, forKey: Self.askedKey)
        guard manager.authorizationStatus == .notDetermined else { return }

        manager.delegate = self
        self.manager = manager
        manager.requestWhenInUseAuthorization()
    }

    private func settle(_ status: CLAuthorizationStatus) {
        // The first callback reports the still-undetermined status as the
        // manager finishes initializing; wait for the person's answer.
        guard status != .notDetermined else { return }
        manager?.delegate = nil
        manager = nil
    }
}

extension WatchLocationPermission: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.settle(status)
        }
    }
}
