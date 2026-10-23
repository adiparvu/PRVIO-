import SwiftUI

// MARK: - Task detail
//
// One task: its title, whether it is overdue, Complete, and the work
// session. The session screen is pushed with `navigationDestination
// (isPresented:)` rather than a `WatchDestination.workSession` value link:
// starting must happen before the push (WorkSessionView dismisses itself
// when there is no session), and a value link cannot sequence that.

struct TaskDetailView: View {
    let taskId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var showSession = false
    @State private var confirmReplace = false

    init(taskId: UUID) {
        self.taskId = taskId
    }

    private var task: TaskCatalogEntry? {
        store.payload?.tasks.first { $0.id == taskId }
    }

    var body: some View {
        Group {
            if let task, !task.isCompleted {
                content(task)
            } else {
                // Completed elsewhere (phone, Siri, complication) while open.
                AllClearView(systemImage: "checkmark.circle")
            }
        }
        .navigationTitle(Text(WatchPage.tasks.titleKey))
        .watchPageGround(WatchTheme.Tint.tasks)
        .navigationDestination(isPresented: $showSession) {
            WorkSessionView()
        }
    }

    private func content(_ task: TaskCatalogEntry) -> some View {
        let isOverdue = task.isOverdue == true
        // Typed explicitly: a bare ternary of literals would pick Label's
        // verbatim String initializer and skip localization.
        let sessionKey: LocalizedStringKey = store.session?.taskId == task.id
            ? "watch_session_open" : "watch_session_start"
        return ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xl) {
                if isOverdue {
                    Label("watch_overdue", systemImage: "exclamationmark.circle.fill")
                        .font(WatchTheme.Typography.cardTitle)
                        .foregroundStyle(WatchTheme.Tint.critical)
                }

                Text(verbatim: task.title)
                    .font(WatchTheme.Typography.hero)
                    .fixedSize(horizontal: false, vertical: true)
                    .privacySensitive()

                Button {
                    complete(task)
                } label: {
                    Label("watch_complete", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(isOverdue ? WatchTheme.Tint.critical : WatchTheme.Tint.tasks)

                Button {
                    openSession(for: task)
                } label: {
                    Label(sessionKey, systemImage: "timer")
                        .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
                }
                .buttonStyle(.bordered)
                .tint(WatchTheme.Tint.session)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .confirmationDialog("watch_session_replace", isPresented: $confirmReplace, titleVisibility: .visible) {
            Button("watch_session_start") {
                store.startSession(task: task)
                showSession = true
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: Actions

    /// Completing the task that is being timed ends its session too, so the
    /// clock never keeps running for finished work.
    private func complete(_ task: TaskCatalogEntry) {
        if store.session?.taskId == task.id {
            store.endSession(completingTask: true)
        } else {
            store.completeTask(task.id)
        }
        dismiss()
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
            store.startSession(task: task)
            showSession = true
        }
    }
}
