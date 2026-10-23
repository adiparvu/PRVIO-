import Foundation

// MARK: - Wrist crash forensics
//
// "Opens for a second and closes" is a crash in the launch / first-render
// path — the class both historical wrist crashes belonged to (duplicate
// ForEach identities, an undeclared Handoff type), and both were
// NSExceptions, exactly what the handler below catches. The report survives
// in the App Group; the NEXT launch (even a one-second one) shows it on the
// waiting screen and forwards it to the iPhone as `watchCrash` over the
// guaranteed transferUserInfo queue, where the Watch settings page shows it.
//
// The defaults keys are part of the frozen contract.

enum WatchCrashRecorder {
    fileprivate static let reportKey = "prvio.watch.lastCrash"
    private static let launchKey = "prvio.watch.launchInFlight"
    private static let deathCountKey = "prvio.watch.launchDeathCount"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard
    }

    /// Set on the main thread by the first `start()`; guards the sentinel
    /// from being counted twice when both the app and the store call it.
    nonisolated(unsafe) private static var started = false

    /// Arms the exception handler and plants the launch sentinel. Idempotent;
    /// call it as early as possible — everything after it is a crash suspect.
    static func start() {
        guard !started else { return }
        started = true
        arm()
        beginLaunch()
    }

    private static func arm() {
        // A C function pointer: no captures, statics only.
        NSSetUncaughtExceptionHandler { exception in
            let text = "\(exception.name.rawValue): \(exception.reason ?? "?")\n"
                + exception.callStackSymbols.prefix(8).joined(separator: "\n")
            (UserDefaults(suiteName: SharedDataStore.suiteName) ?? .standard)
                .set(text, forKey: WatchCrashRecorder.reportKey)
        }
    }

    /// The exception handler is blind to watchdog kills and signal crashes —
    /// the "never opens" class. A sentinel set here and cleared only by the
    /// first rendered frame means: still present at the next launch → the
    /// previous launch died silently. Counted, and synthesized into a report
    /// when no exception was captured. (A death before this line — dyld /
    /// the launch loader — stays invisible to the app; only the system .ips
    /// report has it.)
    private static func beginLaunch() {
        let defaults = Self.defaults
        if defaults.bool(forKey: launchKey) {
            let died = defaults.integer(forKey: deathCountKey) + 1
            defaults.set(died, forKey: deathCountKey)
            if defaults.string(forKey: reportKey) == nil {
                defaults.set(
                    "Launch died before first frame ×\(died) — no exception captured "
                    + "(watchdog kill or hard crash). The system .ips report has the cause.",
                    forKey: reportKey)
            }
        }
        defaults.set(true, forKey: launchKey)
    }

    /// The first frame rendered — this launch survived; clear the sentinel
    /// so a later clean exit is never miscounted as a death.
    static func firstFrameRendered() {
        let defaults = Self.defaults
        defaults.set(false, forKey: launchKey)
        defaults.removeObject(forKey: deathCountKey)
    }

    /// The captured report, left in place (shown on the waiting screen).
    static func peek() -> String? {
        defaults.string(forKey: reportKey)
    }

    /// The captured report, removed — it is about to ride to the phone.
    static func drain() -> String? {
        let defaults = Self.defaults
        guard let text = defaults.string(forKey: reportKey) else { return nil }
        defaults.removeObject(forKey: reportKey)
        return text
    }
}
