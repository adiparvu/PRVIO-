import Foundation
import Observation

// The work-session authority — shared by the phone, the Apple Watch and the
// Dynamic Island so one clock is timed everywhere.

// MARK: - WorkSessionStore
//
// The single authority for a task work session — Start ▸ / Pause ⏸ / Finish ⏹.
// The phone context menu, the pinned banner, the task row and the Apple Watch
// all drive THIS one object, so the timer reads identically everywhere and a
// pause taken on the wrist freezes the same clock the phone shows.
//
// Only one session runs at a time (matching the watch's model). Elapsed time
// is derived from dates, never a ticking counter we could drift — so it stays
// truthful across app kills, and pauses are excluded by accumulating finished
// segments and timing only the current running one.
@MainActor
@Observable
final class WorkSessionStore {
    static let shared = WorkSessionStore()
    private init() { active = Self.loadActive() }

    struct Active: Codable, Equatable {
        var taskId: UUID
        var title: String
        /// Seconds banked from segments that already ran (before each pause).
        var accumulated: TimeInterval
        /// Start of the currently-running segment; nil while paused.
        var segmentStart: Date?

        var isPaused: Bool { segmentStart == nil }

        func elapsed(at now: Date) -> TimeInterval {
            accumulated + (segmentStart.map { max(0, now.timeIntervalSince($0)) } ?? 0)
        }
    }

    /// The live session, or nil when nothing is being timed. `@Observable`, so
    /// every timer view repaints the instant it changes.
    private(set) var active: Active?

    func isTiming(_ taskId: UUID) -> Bool { active?.taskId == taskId }

    // MARK: Controls

    /// Begins timing a task, replacing any session already running.
    func start(taskId: UUID, title: String, startedAt: Date = Date()) {
        active = Active(taskId: taskId, title: title, accumulated: 0, segmentStart: startedAt)
        persist()
        HapticFeedback.impact(.medium)
        LiveActivityService.shared.startWorkSession(taskId: taskId, title: title, startedAt: startedAt)
    }

    /// Adopts a session started elsewhere (the wrist) without restarting its
    /// clock — the original start date and banked time ride along.
    func adopt(taskId: UUID, title: String, accumulated: TimeInterval, segmentStart: Date?) {
        active = Active(taskId: taskId, title: title, accumulated: accumulated, segmentStart: segmentStart)
        persist()
    }

    func pause() {
        guard var s = active, let seg = s.segmentStart else { return }
        s.accumulated += max(0, Date().timeIntervalSince(seg))
        s.segmentStart = nil
        active = s
        persist()
        HapticFeedback.impact(.light)
    }

    func resume() {
        guard var s = active, s.segmentStart == nil else { return }
        s.segmentStart = Date()
        active = s
        persist()
        HapticFeedback.impact(.light)
    }

    func togglePause() { active?.isPaused == true ? resume() : pause() }

    /// Stops the session, banks its time onto the task's running total and
    /// clears the live state. Returns the finished (taskId, seconds) so the
    /// caller can mark the task done — the confirmed "Finish = stop + complete"
    /// behaviour — or nil if nothing was running.
    /// `completingTask: false` banks the time but tells the Live Activity the
    /// work stopped rather than finished (the wrist's "End").
    @discardableResult
    func finish(completingTask: Bool = true) -> (taskId: UUID, seconds: TimeInterval)? {
        guard let s = active else { return nil }
        let total = s.elapsed(at: Date())
        addWorked(taskId: s.taskId, seconds: total)
        active = nil
        persist()
        if completingTask { HapticFeedback.success() }
        LiveActivityService.shared.endWorkSession(completed: completingTask)
        return (s.taskId, total)
    }

    /// Ends the session WITHOUT banking time or completing the task — used when
    /// the timed task is deleted out from under the session.
    func cancel() {
        guard active != nil else { return }
        active = nil
        persist()
        LiveActivityService.shared.endWorkSession(completed: false)
    }

    // MARK: Per-task worked totals (local authority)
    //
    // Stored in the App Group so the widgets and the task detail read the same
    // number. Server persistence rides on top best-effort (see TaskService)
    // once the `worked_seconds` column exists; the local value is always right.

    private static let totalsKey = "prvio.session.totals"

    func workedSeconds(for taskId: UUID) -> TimeInterval {
        totals()[taskId.uuidString] ?? 0
    }

    private func addWorked(taskId: UUID, seconds: TimeInterval) {
        guard seconds > 0 else { return }
        var t = totals()
        t[taskId.uuidString, default: 0] += seconds
        Self.defaults?.set(t, forKey: Self.totalsKey)
        // Best-effort server mirror; harmless no-op until the column ships.
        TaskService.persistWorkedSeconds(taskId: taskId, total: t[taskId.uuidString] ?? seconds)
    }

    private func totals() -> [String: TimeInterval] {
        (Self.defaults?.dictionary(forKey: Self.totalsKey) as? [String: TimeInterval]) ?? [:]
    }

    // MARK: Persistence of the active session (survives app kill)

    private static let activeKey = "prvio.session.active"
    private static var defaults: UserDefaults? { UserDefaults(suiteName: SharedDataStore.suiteName) }

    private func persist() {
        if let s = active, let data = try? JSONEncoder().encode(s) {
            Self.defaults?.set(data, forKey: Self.activeKey)
        } else {
            Self.defaults?.removeObject(forKey: Self.activeKey)
        }
    }

    private static func loadActive() -> Active? {
        guard let data = defaults?.data(forKey: activeKey) else { return nil }
        return try? JSONDecoder().decode(Active.self, from: data)
    }
}

// MARK: - Duration formatting

extension TimeInterval {
    /// "1:20:05" past an hour, else "20:05" — the wall-clock a stopwatch shows.
    var workSessionClock: String {
        let total = Int(max(0, self))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// "1h 20m" / "45m" / "30s" — a compact human total for the task detail.
    var workedTotalDisplay: String {
        let total = Int(max(0, self))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }
}
