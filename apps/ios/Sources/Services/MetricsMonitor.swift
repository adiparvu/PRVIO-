import Foundation
import MetricKit

// MARK: - MetricKit telemetry
//
// The measured foundation any future self-healing must stand on: Apple's
// own daily metrics (launch time, hangs, memory, battery) and crash/hang
// diagnostics land here and persist as compact JSON on-device — no
// third-party SDK, nothing leaves the phone from this half. Reading them:
// the files sit in Application Support/Metrics, newest last, capped at 30.
//
// This is the app's ONE MetricKit subscriber: every report is persisted
// here and handed to MetricKitService, which ships it to `app_metrics`
// once a user is signed in. On iOS 27+ reports arrive through the
// Swift-first `MetricManager` (`MetricReport` / `DiagnosticReport`,
// encoded with `JSONEncoder`); earlier systems use the original
// `MXMetricManager` subscriber and its payloads' `jsonRepresentation()`.
// The two JSON shapes differ — `os_version` on each uploaded row tells
// them apart.

final class MetricsMonitor: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = MetricsMonitor()
    private override init() { super.init() }

    private let capacity = 30

    private let lock = NSLock()
    private var started = false
    /// The iOS 27 `MetricManager`, held for the process lifetime as Apple
    /// requires. Typed `AnyObject` because a stored property cannot carry an
    /// availability gate.
    private var manager: AnyObject?

    /// Idempotent: AppDelegate calls this once at launch.
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !started else { return }
        started = true
        if #available(iOS 27.0, *) {
            let manager = MetricManager()
            self.manager = manager
            startReports(from: manager)
        } else {
            MXMetricManager.shared.add(self)
        }
    }

    // MARK: MetricManager (iOS 27+)
    //
    // Both sequences never throw and never finish while the manager lives —
    // two long-lived utility tasks, idle until MetricKit delivers.

    @available(iOS 27.0, *)
    private func startReports(from manager: MetricManager) {
        Task.detached(priority: .utility) {
            for await report in manager.metricReports {
                guard let data = Self.encode(report) else { continue }
                self.deliver(data, isMetric: true)
            }
        }
        Task.detached(priority: .utility) {
            for await report in manager.diagnosticReports {
                // Crashes and hangs — the signal that matters most.
                guard let data = Self.encode(report) else { continue }
                self.deliver(data, isMetric: false)
            }
        }
    }

    @available(iOS 27.0, *)
    private static func encode<Report: Encodable>(_ report: Report) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(report)
    }

    // MARK: MXMetricManagerSubscriber (before iOS 27)
    //
    // MetricKit delivers at most daily — writes are rare and tiny.

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { deliver(payload.jsonRepresentation(), isMetric: true) }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        // Crashes and hangs — the signal that matters most.
        for payload in payloads { deliver(payload.jsonRepresentation(), isMetric: false) }
    }

    // MARK: Fan-out

    /// One report, two destinations: the on-device copy, and the fleet
    /// upload (which buffers until sign-in).
    private func deliver(_ data: Data, isMetric: Bool) {
        persist(data, kind: isMetric ? "metrics" : "diagnostics")
        MetricKitService.shared.submit(data, kind: isMetric ? "metric" : "diagnostic")
    }

    // MARK: On-device persistence

    private var directory: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("Metrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func persist(_ data: Data, kind: String) {
        guard let dir = directory else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        // A short random suffix: iOS 27 delivers each diagnostic as its own
        // report, so several can land within the same second.
        let suffix = UUID().uuidString.prefix(8)
        let url = dir.appendingPathComponent("\(kind)-\(stamp)-\(suffix).json")
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            debugLog("[Metrics] persist failed: \(error)")
        }
        trim(in: dir)
    }

    /// Oldest files fall away past capacity — telemetry must never become
    /// the thing that fills the disk.
    private func trim(in dir: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return }
        let sorted = files.sorted { $0.lastPathComponent < $1.lastPathComponent }
        for stale in sorted.dropLast(capacity) {
            try? FileManager.default.removeItem(at: stale)
        }
    }
}
