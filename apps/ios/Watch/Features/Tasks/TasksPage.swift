import SwiftUI

// MARK: - Tasks: what is left to do
//
// A calm summary line (symbol + word, never a shouted count), then the open
// tasks, overdue first, capped so the list stays a glance. The leading
// glyph completes on the spot: it bounces, the store plays `.done`, and the
// row leaves with the List's own removal animation (the glyph wraps the
// intent in the snappy animation, a cross-fade under Reduce Motion). The
// rest of the row opens the detail — the split keeps a scroll from
// completing anything by accident. Clearing the last task here celebrates
// once (`watchAllClearCelebration(.tasks)`).
//
// No primary double tap: this is a scrolling list inside the pager. The
// one primary action — dictating a new task — lives in the bottom bar.

/// A pushed task detail. Feature-specific so it never collides with another
/// feature's route on a shared stack.
struct TaskRoute: Hashable {
    let id: UUID
}

struct TasksPage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Wrist reading, not a backlog: the phone owns the long tail.
    private static let visibleCap = 12

    init() {}

    var body: some View {
        let open = store.openTasks
        let shown = Array(open.prefix(Self.visibleCap))
        let timedTaskId = store.session?.taskId
        Group {
            if shown.isEmpty {
                AllClearView(systemImage: "checkmark.circle")
            } else {
                List {
                    TasksSummary(openCount: open.count,
                                 overdueCount: open.filter { $0.isOverdue == true }.count)
                        .listRowBackground(Color.clear)

                    ForEach(shown, id: \.id) { task in
                        NavigationLink(value: TaskRoute(id: task.id)) {
                            TaskRow(task: task, isTimed: task.id == timedTaskId) {
                                store.completeTask(task.id)   // the intent plays .done
                            }
                        }
                        .watchRowBackground(WatchTheme.Tint.tasks)
                    }

                    if open.count > shown.count {
                        Text("watch_more_on_iphone \(open.count - shown.count)")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                            .watchAlwaysOnDimmed()
                    }
                }
            }
        }
        .navigationTitle(Text(WatchPage.tasks.titleKey))
        .skyGround()
        .navigationDestination(for: TaskRoute.self) { route in
            TaskDetailView(taskId: route.id)
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                // Dictated on the wrist; the phone creates the real task and
                // the local list shows it at the top immediately.
                TextFieldLink(prompt: Text("watch_new_task_prompt")) {
                    Label("New Task", systemImage: "plus")
                } onSubmit: { title in
                    withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy,
                                                             reduceMotion: reduceMotion)) {
                        store.createTask(title: title)   // the intent plays .done
                    }
                }
                .tint(WatchTheme.Tint.tasks)
            }
        }
        .watchAllClearCelebration(.tasks)
    }
}

// MARK: - Summary

/// The page's one-line state: "3 open, nothing urgent" with a leaf, or
/// "3 open · 1 overdue" with the attention symbol — plain words, no alarm.
private struct TasksSummary: View {
    let openCount: Int
    let overdueCount: Int

    var body: some View {
        Group {
            if overdueCount > 0 {
                StateLabel("watch_tasks_summary_overdue \(openCount) \(overdueCount)",
                           systemImage: "exclamationmark.circle.fill",
                           tint: WatchTheme.Tint.attention)
            } else {
                StateLabel("watch_headline_open \(openCount)",
                           systemImage: "leaf.fill",
                           tint: WatchTheme.Tint.calm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Row

private struct TaskRow: View {
    let task: TaskCatalogEntry
    /// This task is the one the work session is timing.
    let isTimed: Bool
    let complete: () -> Void

    private var isOverdue: Bool { task.isOverdue == true }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            // Bounces and acts after the confirmation beat; the store plays
            // the haptic, so the glyph plays none of its own.
            ActionGlyphButton(systemImage: "circle",
                              actedSystemImage: "checkmark.circle.fill",
                              tint: isOverdue ? WatchTheme.Tint.attention : WatchTheme.Tint.tasks,
                              labelKey: "watch_complete",
                              action: complete)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: task.title)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(2)
                    // The task's own text stays off a resting wrist.
                    .privacySensitive()
                if isOverdue {
                    StateLabel("watch_overdue", systemImage: "exclamationmark.circle.fill",
                               tint: WatchTheme.Tint.attention)
                } else if isTimed {
                    StateLabel("watch_session", systemImage: "timer", tint: WatchTheme.Tint.session)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    NavigationStack { TasksPage() }
        .environment(WatchStore(preview: nil))
}
