import SwiftUI

// MARK: - Tasks: what is left to do
//
// Open tasks, overdue first, capped so the list stays a glance. The leading
// glyph completes on the spot; the rest of the row opens the detail — the
// split that keeps a scroll from completing anything by accident. No
// primary double tap here: this is a scrolling list inside the pager.

/// A pushed task detail. Feature-specific so it never collides with another
/// feature's route on a shared stack.
struct TaskRoute: Hashable {
    let id: UUID
}

struct TasksPage: View {
    @Environment(WatchStore.self) private var store

    /// Wrist reading, not a backlog: the phone owns the long tail.
    private static let visibleCap = 12

    init() {}

    var body: some View {
        let open = store.openTasks
        let shown = Array(open.prefix(Self.visibleCap))
        Group {
            if shown.isEmpty {
                AllClearView(systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(shown, id: \.id) { task in
                        NavigationLink(value: TaskRoute(id: task.id)) {
                            TaskRow(task: task) {
                                store.completeTask(task.id)
                            }
                        }
                        .watchRowBackground(task.isOverdue == true ? WatchTheme.Tint.critical
                                                                   : WatchTheme.Tint.tasks)
                    }
                    if open.count > shown.count {
                        Text("watch_more_on_iphone \(open.count - shown.count)")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .navigationTitle(Text(WatchPage.tasks.titleKey))
        .watchPageGround(WatchTheme.Tint.tasks)
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
                    withAnimation(WatchTheme.Motion.snappy) {
                        store.createTask(title: title)
                    }
                }
            }
        }
    }
}

// MARK: - Row

private struct TaskRow: View {
    let task: TaskCatalogEntry
    let complete: () -> Void

    private var isOverdue: Bool { task.isOverdue == true }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            ActionGlyphButton(systemImage: "circle",
                              actedSystemImage: "checkmark.circle.fill",
                              tint: isOverdue ? WatchTheme.Tint.critical : WatchTheme.Tint.tasks,
                              labelKey: "watch_complete",
                              action: complete)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: task.title)
                    .font(WatchTheme.Typography.body)
                    .lineLimit(2)
                if isOverdue {
                    // Words and a glyph, not colour alone.
                    Label("watch_overdue", systemImage: "exclamationmark.circle.fill")
                        .font(WatchTheme.Typography.captionStrong)
                        .foregroundStyle(WatchTheme.Tint.critical)
                }
            }
            Spacer(minLength: 0)
        }
        // The task's own text stays off a resting wrist.
        .privacySensitive()
    }
}
