import Foundation
import Supabase

// MARK: - MetricKit → Supabase telemetry
//
// The upload half of the app's telemetry: MetricsMonitor (AppDelegate) is
// the app's one MetricKit subscriber — it persists every report on-device
// and hands it here, and this service ships it to the `app_metrics` table
// so launch-time, hang, memory and crash regressions are visible across
// the fleet without a device in hand. Reports that arrive before sign-in
// wait in a small buffer until `start()`. Strictly fire-and-forget: every
// failure path drops the payload silently — telemetry must never block,
// error or crash the app.

final class MetricKitService: @unchecked Sendable {
    static let shared = MetricKitService()
    private init() {}

    private let lock = NSLock()
    private var started = false
    /// Reports delivered before the first sign-in (MetricKit hands them over
    /// right after launch). Bounded — a launch that never signs in must not
    /// hoard payloads.
    private var pending: [(data: Data, kind: String)] = []
    private static let maxPending = 20

    /// Idempotent: MainTabView's startup beat calls this once per sign-in.
    /// Flushes whatever MetricsMonitor buffered before the session existed.
    func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        let backlog = pending
        pending = []
        lock.unlock()
        for item in backlog { upload(item.data, kind: item.kind) }
    }

    /// Called by MetricsMonitor for every report, on MetricKit's background
    /// delivery — uploads are rare, small, and never touch the main actor
    /// beyond one read of the active property.
    func submit(_ data: Data, kind: String) {
        lock.lock()
        guard started else {
            if pending.count < Self.maxPending { pending.append((data, kind)) }
            lock.unlock()
            return
        }
        lock.unlock()
        upload(data, kind: kind)
    }

    // MARK: Upload

    /// Anything larger is not worth a mobile upload — telemetry must never
    /// cost the user real bandwidth (some diagnostic payloads carry deep
    /// call trees).
    private static let maxPayloadBytes = 200_000

    private struct Row: Encodable {
        let property_id: String?
        let user_id: String
        let kind: String
        let app_version: String
        let os_version: String
        let device_model: String
        let payload: JSONObject
    }

    private func upload(_ data: Data, kind: String) {
        // No session, no owner for the row (RLS would refuse it anyway): drop.
        guard let userId = supabase.auth.currentSession?.user.id else { return }
        guard data.count <= Self.maxPayloadBytes,
              let object = try? JSONDecoder().decode(JSONObject.self, from: data)
        else { return }

        let os = ProcessInfo.processInfo.operatingSystemVersion
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let osVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let model = Self.deviceModel

        Task.detached(priority: .utility) {
            // The active property lives on the main actor — one cheap hop to
            // read it, then the insert stays off the main thread.
            let propertyId = await MainActor.run { PropertyService.activePropertyId?.uuidString }
            let row = Row(
                property_id: propertyId,
                user_id: userId.uuidString,
                kind: kind,
                app_version: appVersion,
                os_version: osVersion,
                device_model: model,
                payload: object)
            // Fire-and-forget: a failed insert is a lost data point, never
            // a user-visible problem.
            _ = try? await supabase.from("app_metrics").insert(row).execute()
        }
    }

    /// The hardware identifier ("iPhone16,2"), not UIDevice's generic
    /// "iPhone" — the only form that lets a regression be pinned to a chip.
    private static let deviceModel: String = {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }()
}
