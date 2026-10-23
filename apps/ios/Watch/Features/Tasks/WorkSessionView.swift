import SwiftUI
import WatchKit

// MARK: - Work session (maintenance timer)
//
// The one screen in the app allowed to own the primary double tap — HIG
// reserves it for fixed, non-scrolling screens. The fixed layout wins
// whenever it fits; when it cannot (small case, large Dynamic Type) the same
// layout scrolls and the gesture goes back to the system.
//
// Always pushed (WatchDestination.workSession or a task's detail), never
// presented, and it leaves by itself the moment the session ends — from
// here, the phone, or another screen.

struct WorkSessionView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// A quiet pulse at each quarter hour of worked time.
    private static let pulseInterval: TimeInterval = 15 * 60
    /// A boundary older than this when the pulse task wakes (the app was
    /// suspended across it) is skipped rather than buzzed late.
    private static let pulseTolerance: TimeInterval = 30

    init() {}

    var body: some View {
        Group {
            if let session = store.session {
                ViewThatFits(in: .vertical) {
                    layout(session, ownsDoubleTap: true)
                    ScrollView {
                        layout(session, ownsDoubleTap: false)
                    }
                }
                // Restarts on pause/resume so the sleep always targets the
                // next boundary of worked (not wall-clock) time.
                .task(id: session.isPaused) { await pulseQuarterHours() }
            } else {
                AllClearView(systemImage: "timer")
            }
        }
        .navigationTitle(Text("Work session"))
        .watchPageGround(WatchTheme.Tint.session)
        .onAppear {
            if store.session == nil { dismiss() }
        }
        .onChange(of: store.session == nil) { _, ended in
            if ended { dismiss() }
        }
    }

    // MARK: Layout

    /// Compact by design so it fits without scrolling: pause and end share
    /// one row as icon buttons (their titles stay as accessibility labels),
    /// leaving the full-width Complete as the obvious primary action.
    private func layout(_ session: WatchWorkSession, ownsDoubleTap: Bool) -> some View {
        VStack(spacing: WatchTheme.Spacing.m) {
            HStack(spacing: WatchTheme.Spacing.xs) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "timer")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(WatchTheme.Tint.session)
                    // No animation on a dimmed, rarely redrawn face.
                    .symbolEffect(.pulse, isActive: !session.isPaused && !isLuminanceReduced)
                    .accessibilityHidden(true)
                Text(verbatim: session.title)
                    .lineLimit(1)
                    .privacySensitive()
            }
            .font(WatchTheme.Typography.cardTitle)
            .watchAlwaysOnDimmed()

            WorkSessionClock(session: session)

            HStack(spacing: WatchTheme.Spacing.s) {
                Button {
                    store.toggleSessionPause()
                } label: {
                    Label(session.isPaused ? "watch_session_resume" as LocalizedStringKey
                                           : "watch_session_pause",
                          systemImage: session.isPaused ? "play.fill" : "pause.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(session.isPaused ? WatchTheme.Tint.success : WatchTheme.Tint.warning)

                Button {
                    // Banks the time and leaves the task open.
                    store.endSession(completingTask: false)
                } label: {
                    Label("watch_session_end", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .watchAlwaysOnDimmed()

            Button {
                store.endSession(completingTask: true)
            } label: {
                Label("watch_complete", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.Tint.session)
            // Only the fixed layout owns double tap; the scrolling fallback
            // leaves it to the system.
            .handGestureShortcut(.primaryAction, isEnabled: ownsDoubleTap)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Quarter-hour pulse

    /// Sleeps to the next quarter hour of worked time and taps the wrist —
    /// only while this screen is up (the task ends with the view).
    private func pulseQuarterHours() async {
        while !Task.isCancelled {
            guard let current = store.session, !current.isPaused else { return }
            let worked = current.elapsed(at: .now)
            let wait = Self.pulseInterval - worked.truncatingRemainder(dividingBy: Self.pulseInterval)
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                return
            }
            guard let after = store.session, after.taskId == current.taskId, !after.isPaused else { return }
            let pastBoundary = after.elapsed(at: .now).truncatingRemainder(dividingBy: Self.pulseInterval)
            if pastBoundary < Self.pulseTolerance {
                WKInterfaceDevice.current().play(.notification)
            }
        }
    }
}

// MARK: - Clock

/// The big readout. Computed elapsed (pauses excluded, so a pause truly
/// freezes it). When the system drops the timeline to minute cadence, or the
/// wrist is down in Always On, a seconds digit would be stale — the readout
/// switches to h:mm until the wrist is raised.
private struct WorkSessionClock: View {
    let session: WatchWorkSession
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            let minutesOnly = context.cadence >= .minutes || isLuminanceReduced
            Text(verbatim: minutesOnly ? elapsed.watchClockMinutesText : elapsed.watchClockText)
                .font(WatchTheme.Typography.clockLarge)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
                .foregroundStyle(session.isPaused ? WatchTheme.Tint.warning : Color.primary)
        }
    }
}
