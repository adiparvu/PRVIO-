import SwiftUI

// MARK: - Task detail: one task as an infographic
//
// Top to bottom: the task's state (symbol + word — "Overdue" in the
// attention tint, never red), the title, a facts card (priority as signal
// bars, the running session's clock when this task is being timed), then
// Complete and the work session.
//
// The payload carries no due date (frozen contract), so "due" is stated the
// only honest way the wrist knows it: overdue or open.
//
// The session screen is pushed with `navigationDestination(isPresented:)`
// rather than a `WatchDestination.workSession` value link: starting must
// happen before the push (WorkSessionView dismisses itself when there is no
// session), and a value link cannot sequence that.

struct TaskDetailView: View {
    let taskId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showSession = false
    @State private var confirmReplace = false
    /// Set on tap: the glyph confirms, then the task completes and the
    /// screen leaves. Also keeps the content up during that beat.
    @State private var isCompleting = false

    init(taskId: UUID) {
        self.taskId = taskId
    }

    private var task: TaskCatalogEntry? {
        store.payload?.tasks.first { $0.id == taskId }
    }

    var body: some View {
        Group {
            if let task, !task.isCompleted || isCompleting {
                content(task)
            } else {
                // Completed elsewhere (phone, Siri, complication) while open.
                AllClearView(systemImage: "checkmark.circle")
            }
        }
        .navigationTitle(Text(WatchPage.tasks.titleKey))
        .skyGround()
        .navigationDestination(isPresented: $showSession) {
            WorkSessionView()
        }
    }

    private func content(_ task: TaskCatalogEntry) -> some View {
        let isOverdue = task.isOverdue == true
        let timed = store.session.flatMap { $0.taskId == task.id ? $0 : nil }
        return ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.l) {
                Group {
                    if isOverdue {
                        StateLabel("watch_overdue", systemImage: "exclamationmark.circle.fill",
                                   tint: WatchTheme.Tint.attention)
                    } else {
                        StateLabel("watch_open", systemImage: "circle.dotted",
                                   tint: WatchTheme.Tint.tasks)
                    }
                }
                .watchEntrance(0)

                Text(verbatim: task.title)
                    .font(WatchTheme.Typography.hero)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitive()
                    .accessibilityAddTraits(.isHeader)
                    .watchEntrance(1)

                TaskFactsCard(priority: TaskPriorityLevel(task.priority), session: timed)
                    .watchEntrance(2)

                actions(task, isTimed: timed != nil)
                    .watchEntrance(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog(Text("watch_session_replace"), isPresented: $confirmReplace,
                            titleVisibility: .visible) {
            Button("watch_session_start") {
                store.startSession(task: task)   // the intent plays .start
                showSession = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Actions

    private func actions(_ task: TaskCatalogEntry, isTimed: Bool) -> some View {
        // Typed explicitly: a bare ternary of literals would pick Label's
        // verbatim String initializer and skip localization.
        let sessionKey: LocalizedStringKey = isTimed ? "watch_session_open" : "watch_session_start"
        return VStack(spacing: WatchTheme.Spacing.s) {
            Button {
                complete(task)
            } label: {
                Label {
                    Text("watch_complete")
                } icon: {
                    Image(systemName: isCompleting ? "checkmark.circle.fill" : "checkmark.circle")
                        .contentTransition(reduceMotion ? ContentTransition.opacity
                                                        : ContentTransition.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: isCompleting && !reduceMotion)
                }
                .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.Tint.tasks)
            .disabled(isCompleting)

            Button {
                openSession(for: task)
            } label: {
                Label(sessionKey, systemImage: "timer")
                    .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            }
            .buttonStyle(.bordered)
            .tint(WatchTheme.Tint.session)
            .disabled(isCompleting)
        }
        .watchAlwaysOnDimmed()
    }

    /// The glyph confirms first (skipped under Reduce Motion), then the task
    /// completes and the screen leaves. Completing the task being timed ends
    /// its session too, so the clock never runs on for finished work. The
    /// store plays `.done`; clearing the last task celebrates on the list.
    private func complete(_ task: TaskCatalogEntry) {
        guard !isCompleting else { return }
        withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)) {
            isCompleting = true
        }
        let id = task.id
        let pause = !reduceMotion
        Task { @MainActor in
            if pause { try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay) }
            if store.session?.taskId == id {
                store.endSession(completingTask: true)
            } else {
                store.completeTask(id)
            }
            dismiss()
        }
    }

    /// Opens this task's running session, or starts one. Another task's
    /// running session is only replaced after the user confirms, because the
    /// replacement discards its clock.
    private func openSession(for task: TaskCatalogEntry) {
        switch store.session {
        case .some(let running) where running.taskId == task.id:
            showSession = true
        case .some:
            confirmReplace = true
        case .none:
            store.startSession(task: task)   // the intent plays .start
            showSession = true
        }
    }
}

// MARK: - Facts card

/// The task's priority, read from the payload's raw value. Unknown values
/// read as medium, the phone's default.
private enum TaskPriorityLevel {
    case low, medium, high, critical

    init(_ raw: String) {
        switch raw.lowercased() {
        case "low":      self = .low
        case "high":     self = .high
        case "critical": self = .critical
        default:         self = .medium
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .low:      return "Low"
        case .medium:   return "Medium"
        case .high:     return "High"
        case .critical: return "Critical"
        }
    }

    /// Filled bars of the signal glyph — the level reads without colour.
    var level: Double {
        switch self {
        case .low:      return 0.25
        case .medium:   return 0.5
        case .high:     return 0.75
        case .critical: return 1
        }
    }

    var tint: Color {
        switch self {
        case .low:             return WatchTheme.Tint.success
        case .medium:          return WatchTheme.Tint.tasks
        case .high, .critical: return WatchTheme.Tint.attention
        }
    }
}

private struct TaskFactsCard: View {
    let priority: TaskPriorityLevel
    /// The running session when it is timing this task.
    let session: WatchWorkSession?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.tasks) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                fact(titleKey: "Priority") {
                    Image(systemName: "chart.bar.fill", variableValue: priority.level)
                        .foregroundStyle(priority.tint)
                } value: {
                    Text(priority.titleKey)
                }

                if let session {
                    fact(titleKey: "watch_session") {
                        Image(systemName: session.isPaused ? "pause.circle.fill" : "timer")
                            .foregroundStyle(WatchTheme.Tint.session)
                            // pulse = a live session.
                            .symbolEffect(.pulse, isActive: !session.isPaused && !reduceMotion
                                                            && !isLuminanceReduced)
                    } value: {
                        SessionClockText(session: session, font: WatchTheme.Typography.numeralSmall)
                    }
                }
            }
        }
    }

    private func fact<Glyph: View, Value: View>(titleKey: LocalizedStringKey,
                                                @ViewBuilder glyph: () -> Glyph,
                                                @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            glyph()
                .font(WatchTheme.Typography.glyph)
                .frame(width: WatchTheme.Size.rowIcon)
                .accessibilityHidden(true)
            Text(titleKey)
                .font(WatchTheme.Typography.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: WatchTheme.Spacing.xs)
            value()
                .font(WatchTheme.Typography.numeralSmall)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
