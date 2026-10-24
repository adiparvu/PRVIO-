import SwiftUI

// MARK: - Work session: a dial that simply runs
//
// The task's name, then the dial — a large SF Rounded clock inside a pulse
// ring that fills once per quarter hour of worked time — then Pause / End /
// Complete. The clock scrubs nothing (DESIGN.md, "Crown as the instrument"):
// it runs, large and calm.
//
// Haptics come from the store's intents (pause/end → `.stop`, resume →
// `.start`, complete → `.done`); this screen adds only the quarter-hour cue,
// a quiet `.tick` — never the alarm haptic, which means a real emergency.
//
// The one screen in the app allowed to own the primary double tap — HIG
// reserves it for fixed, non-scrolling screens. It pauses / resumes (the
// reversible action, as in the system Timer), never Complete, so a stray
// gesture can't finish a task. The fixed layout wins whenever it fits; when
// it cannot (small case, accessibility text sizes) the same layout scrolls
// and the gesture goes back to the system.
//
// Always On: the clock drops to h:mm, the ring becomes a thin stroke, and
// nothing animates. Always pushed (WatchDestination.workSession or a task's
// detail), never presented, and it leaves by itself the moment the session
// ends — from here, the phone, or another screen.

struct WorkSessionView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The dial grows with Dynamic Type; at accessibility sizes the fixed
    /// layout stops fitting and the scrolling fallback takes over.
    @ScaledMetric(relativeTo: .largeTitle) private var dialDiameter: CGFloat = SessionDial.baseDiameter

    /// Keeps the controls up for the confirmation beat after Complete.
    @State private var isCompleting = false

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
                // Restarts on pause/resume and on a replaced session, so the
                // sleep always targets the next boundary of worked time.
                .task(id: QuarterCueKey(taskId: session.taskId, isPaused: session.isPaused)) {
                    await cueQuarterHours()
                }
            } else {
                AllClearView(systemImage: "timer")
            }
        }
        .navigationTitle(Text("Work session"))
        .skyGround()
        .onAppear {
            if store.session == nil { dismiss() }
        }
        .onChange(of: store.session == nil) { _, ended in
            if ended { dismiss() }
        }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    // MARK: Layout

    private func layout(_ session: WatchWorkSession, ownsDoubleTap: Bool) -> some View {
        VStack(spacing: WatchTheme.Spacing.m) {
            Text(verbatim: session.title)
                .font(WatchTheme.Typography.cardTitle)
                .lineLimit(1)
                .privacySensitive()
                .watchAlwaysOnDimmed()

            SessionDial(session: session, diameter: dialDiameter)

            controls(session, ownsDoubleTap: ownsDoubleTap)
        }
        .frame(maxWidth: .infinity)
    }

    /// Three round controls: Pause/Resume, End (banks the time, task stays
    /// open), and Complete — the filled one, the clear way to finish.
    private func controls(_ session: WatchWorkSession, ownsDoubleTap: Bool) -> some View {
        // Typed explicitly: a bare ternary of literals would pick Label's
        // verbatim String initializer and skip localization.
        let pauseKey: LocalizedStringKey = session.isPaused ? "watch_session_resume" : "watch_session_pause"
        return HStack(spacing: WatchTheme.Spacing.s) {
            Button {
                withAnimation(animation) { store.toggleSessionPause() }   // .stop / .start
            } label: {
                Label(pauseKey, systemImage: session.isPaused ? "play.fill" : "pause.fill")
                    .labelStyle(.iconOnly)
                    .contentTransition(reduceMotion ? ContentTransition.opacity
                                                    : ContentTransition.symbolEffect(.replace))
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(session.isPaused ? WatchTheme.Tint.session : WatchTheme.Tint.warning)
            // Only the fixed layout owns double tap; the scrolling fallback
            // leaves it to the system.
            .handGestureShortcut(.primaryAction, isEnabled: ownsDoubleTap)

            Button {
                store.endSession(completingTask: false)   // .stop
            } label: {
                Label("watch_session_end", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(WatchTheme.Tint.neutral)

            Button {
                complete()
            } label: {
                Label {
                    Text("watch_complete")
                } icon: {
                    Image(systemName: isCompleting ? "checkmark.circle.fill" : "checkmark")
                        .contentTransition(reduceMotion ? ContentTransition.opacity
                                                        : ContentTransition.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isCompleting && !reduceMotion)
                }
                .labelStyle(.iconOnly)
                .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(WatchTheme.Tint.success)
        }
        .disabled(isCompleting)
        .watchAlwaysOnDimmed()
    }

    /// The glyph confirms (skipped under Reduce Motion), then the store ends
    /// the session completing the task (`.done`); the screen leaves by
    /// itself when the session is gone.
    private func complete() {
        guard !isCompleting else { return }
        withAnimation(animation) { isCompleting = true }
        let pause = !reduceMotion
        Task { @MainActor in
            if pause { try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay) }
            store.endSession(completingTask: true)
        }
    }

    // MARK: Quarter-hour cue

    private static let quarter: TimeInterval = SessionDial.quarter
    /// A boundary older than this when the cue task wakes (the app was
    /// suspended across it) is skipped rather than tapped late.
    private static let cueTolerance: TimeInterval = 30

    /// Sleeps to the next quarter hour of worked time and taps the wrist —
    /// only while this screen is up (the task ends with the view).
    private func cueQuarterHours() async {
        while !Task.isCancelled {
            guard let current = store.session, !current.isPaused else { return }
            let worked = current.elapsed(at: .now)
            let wait = Self.quarter - worked.truncatingRemainder(dividingBy: Self.quarter)
            do {
                try await Task.sleep(for: .seconds(wait))
            } catch {
                return
            }
            guard let after = store.session, after.taskId == current.taskId, !after.isPaused else { return }
            let pastBoundary = after.elapsed(at: .now).truncatingRemainder(dividingBy: Self.quarter)
            if pastBoundary < Self.cueTolerance {
                WatchHaptic.tick.play()
            }
        }
    }
}

/// What the quarter-hour cue restarts on.
private struct QuarterCueKey: Hashable {
    let taskId: UUID
    let isPaused: Bool
}

// MARK: - The dial

/// The large clock inside the pulse ring. The ring fills once per quarter
/// hour of worked time and starts again — progress the eye can read without
/// doing arithmetic. Elapsed is computed (pauses excluded, so a pause truly
/// freezes it), never a wall-clock timer text.
private struct SessionDial: View {
    /// One lap of the ring: a quarter hour.
    static let quarter: TimeInterval = 15 * 60
    /// Leaves room for the title and the controls on a 41 mm screen.
    static let baseDiameter: CGFloat = WatchTheme.Size.dial + WatchTheme.Size.prominentGlyph

    let session: WatchWorkSession
    let diameter: CGFloat

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    private var tint: Color { session.isPaused ? WatchTheme.Tint.warning : WatchTheme.Tint.session }

    private var ringWidth: CGFloat {
        isLuminanceReduced ? WatchTheme.Stroke.ring / 2 : WatchTheme.Stroke.ring
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            // A seconds digit would be stale at minute cadence or with the
            // wrist down.
            let minutesOnly = isLuminanceReduced || context.cadence >= .minutes
            dial(elapsed: elapsed, minutesOnly: minutesOnly)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Work session"))
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func dial(elapsed: TimeInterval, minutesOnly: Bool) -> some View {
        // At minute cadence the ring moves in whole minutes, matching the clock.
        let shown = minutesOnly ? (elapsed / 60).rounded(.down) * 60 : elapsed
        let progress = shown.truncatingRemainder(dividingBy: Self.quarter) / Self.quarter
        return ZStack {
            Circle()
                .stroke(tint.opacity(contrast == .increased ? 0.35 : WatchTheme.Opacity.ringTrack),
                        lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint.opacity(isLuminanceReduced ? WatchTheme.AlwaysOn.strokeOpacity : 1),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: minutesOnly ? elapsed.watchClockMinutesText : elapsed.watchClockText)
                    .font(WatchTheme.Typography.clockLarge)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(session.isPaused ? WatchTheme.Tint.warning : Color.primary)
                SessionStateLine(isPaused: session.isPaused)
            }
            .padding(.horizontal, ringWidth + WatchTheme.Spacing.s)
        }
        .padding(ringWidth / 2)
    }

    /// "12 minutes", spelled out — "12:05" read aloud is ambiguous.
    private var accessibilityValue: Text {
        let worked = Duration.seconds(session.elapsed(at: .now))
            .formatted(Duration.UnitsFormatStyle(allowedUnits: [.hours, .minutes], width: .wide))
        guard session.isPaused else { return Text(verbatim: worked) }
        return Text(verbatim: "\(worked), ") + Text("watch_session_paused")
    }
}

/// Running / Paused as symbol + word; the symbol pulses while the session
/// is live (pulse = live session), still under Reduce Motion and Always On.
private struct SessionStateLine: View {
    let isPaused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        // Typed explicitly so the ternary stays a localized key.
        let titleKey: LocalizedStringKey = isPaused ? "watch_session_paused" : "watch_session_running"
        HStack(spacing: WatchTheme.Spacing.xxs) {
            Image(systemName: isPaused ? "pause.circle.fill" : "timer")
                .symbolEffect(.pulse, isActive: !isPaused && !reduceMotion && !isLuminanceReduced)
            Text(titleKey)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(WatchTheme.Typography.captionStrong)
        .foregroundStyle(isPaused ? WatchTheme.Tint.warning : WatchTheme.Tint.session)
        .watchAlwaysOnDimmed()
    }
}
