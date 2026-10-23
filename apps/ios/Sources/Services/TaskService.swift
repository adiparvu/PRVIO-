import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class TaskService {
    var tasks: [MaintenanceTask] = []
    var isLoading = false
    var error: String?

    private var realtimeChannel: RealtimeChannelV2?
    private var subscribedPropertyId: UUID?
    private var postgresSubs: [RealtimeSubscription] = []
    private var realtimeReload: Task<Void, Never>?

    var openCount: Int {
        tasks.filter { $0.status == "pending" || $0.status == "in_progress" }.count
    }
    var overdueCount: Int {
        tasks.filter { $0.isOverdue || $0.status == "overdue" }.count
    }
    var completedThisWeek: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return tasks.filter { t in
            guard t.isCompleted else { return false }
            // Tolerant of every server shape (Z / +00:00 / microseconds) —
            // trigger-touched rows previously failed to parse and vanished
            // from this count.
            if let d = AppDate.timestamp(from: t.updatedAt) { return d >= weekAgo }
            return false
        }.count
    }

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if tasks.isEmpty, let cached = ServiceCache.load([MaintenanceTask].self, entity: "tasks", propertyId: pid) {
            tasks = cached
        }
        isLoading = true
        do {
            tasks = try await PropertyRepo.fetch(table: "maintenance_tasks", propertyId: pid, limit: 500)
            ServiceCache.save(tasks, entity: "tasks", propertyId: pid)
        } catch {
            isLoading = false
            if error is CancellationError { return }
            // A transient refresh failure must not throw a blocking alert
            // over already-displayed cached data — only report when there
            // is nothing on screen to stand behind.
            if tasks.isEmpty { self.error = error.recordableDescription }
        }
        // The spinner ends with the FETCH — the realtime subscribe below can
        // stall on a flaky websocket handshake, and while it hung inside the
        // old `defer` window a member with an empty list stared at an
        // infinite spinner (the "page never loads" report).
        isLoading = false
        if let pid { await subscribeRealtime(propertyId: pid) }
    }

    // MARK: - Live family sync
    //
    // Any insert/update/delete on this home's tasks re-pulls the list, so a
    // task completed on one phone appears on every other family member's
    // phone in seconds — no pull-to-refresh. Events are coalesced so a burst
    // of changes costs one reload.

    private func subscribeRealtime(propertyId: UUID) async {
        // Liveness idempotency (audit 2026-07-21): only a channel that
        // genuinely reached .subscribed (or is mid-join) satisfies the
        // guard — a failed subscribe recorded as "done" was a permanently
        // silent session until app relaunch.
        if let ch = realtimeChannel, subscribedPropertyId == propertyId,
           ch.status == .subscribed || ch.status == .subscribing { return }
        if let ch = realtimeChannel {
            // Real leave from EVERY state (b1173) — removeChannel alone
            // skips the phx_leave and breeds the server-side orphan.
            await ch.unsubscribe()
            await realtimeAnon.removeChannel(ch)
            realtimeChannel = nil
            postgresSubs.removeAll()
        }
        let channel = realtimeAnon.channel("maintenance_tasks:\(propertyId.uuidString)")
        postgresSubs.append(channel.onPostgresChange(
            AnyAction.self,
            schema: "public",
            table: "maintenance_tasks",
            filter: "property_id=eq.\(propertyId.uuidString)"
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.scheduleRealtimeReload() }
        })
        do {
            try await withRealtimeTimeout(seconds: 15) {
                try await channel.subscribeWithError()
            }
            realtimeChannel = channel
            subscribedPropertyId = propertyId
        } catch {
            // No trace on failure: the next subscribe attempt must not be
            // fooled by a dead channel, and the leave keeps the topic clean.
            debugLog("Tasks realtime subscribe failed:", error)
            postgresSubs.removeAll()
            await channel.unsubscribe()
            await realtimeAnon.removeChannel(channel)
        }
    }

    private func scheduleRealtimeReload() {
        realtimeReload?.cancel()
        realtimeReload = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            // Quiet in the background (0x8BADF00D scene-update watchdog, b1036).
            // The skipped change is NOT lost: MainTabView reloads tasks on
            // every return to the foreground.
            guard !Task.isCancelled, !AppLifecycle.isBackgrounded else { return }
            await self?.load()
        }
    }

    @discardableResult
    func addTask(_ payload: NewTaskPayload) async throws -> MaintenanceTask {
        let new: MaintenanceTask = try await supabase
            .from("maintenance_tasks")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
        tasks.insert(new, at: 0)
        return new
    }

    func tasks(forElement elementId: UUID) -> [MaintenanceTask] {
        tasks.filter { $0.elementId == elementId }
    }

    /// Link (or unlink, with nil) a task to an object.
    func setElement(_ elementId: UUID?, for task: MaintenanceTask) async {
        struct ElementLink: Encodable {
            let element_id: String?
            let updated_at: String
        }
        do {
            try await supabase
                .from("maintenance_tasks")
                .update(ElementLink(element_id: elementId?.uuidString,
                                    updated_at: ISODate.string(from: Date())))
                .eq("id", value: task.id.uuidString)
                .execute()
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].elementId = elementId
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func toggleComplete(_ task: MaintenanceTask) async {
        let newStatus = task.isCompleted ? "pending" : "completed"
        let update = TaskStatusUpdate(
            status: newStatus,
            updatedAt: ISODate.string(from: Date())
        )
        do {
            try await supabase
                .from("maintenance_tasks")
                .update(update)
                .eq("id", value: task.id.uuidString)
                .execute()
            if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
                tasks[idx].status = newStatus
                tasks[idx].updatedAt = update.updatedAt
            }
            // Completing a tracked task finishes its Live Activity, and the
            // real completion is donated so Siri Suggestions learn it.
            if newStatus == "completed" {
                LiveActivityService.shared.completeMaintenance(taskTitle: task.title)
                SiriDonations.taskCompleted(id: task.id, title: task.title,
                                            priority: task.priority)
            }
            // Keep the linked Apple Reminder in step (both directions:
            // completing here checks it off, reopening here unchecks it).
            TaskCalendarSync.setReminderCompleted(taskId: task.id, newStatus == "completed")
            // Real recurrence (predictive phase 2): completing a repeating
            // task spawns its next occurrence. The next due date counts from
            // the LATER of the old due date and today, so finishing overdue
            // work never births an already-overdue successor.
            if newStatus == "completed", let every = task.recurrenceDays, every > 0 {
                let cal = Calendar.current
                let today = cal.startOfDay(for: Date())
                let base = task.dueDate.flatMap(MaintenanceTask.parseDate) ?? today
                let next = cal.date(byAdding: .day, value: every, to: max(base, today)) ?? today
                let payload = NewTaskPayload(
                    propertyId: task.propertyId,
                    title: task.title,
                    description: task.description,
                    dueDate: AppDate.day.string(from: next),
                    priority: task.priority,
                    category: task.category,
                    assigneeIds: task.assigneeIds,
                    assigneeNames: task.assigneeNames,
                    recurrenceDays: every)
                _ = try? await addTask(payload)
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    /// Reconciles tasks with Apple Reminders: anything the user checked off
    /// in the Reminders app completes here too. Runs on foreground; silent
    /// no-op without full Reminders access or when nothing is linked.
    func syncFromReminders() async {
        for id in TaskCalendarSync.completedLinkedTaskIds() {
            guard let task = tasks.first(where: { $0.id == id }), !task.isCompleted else { continue }
            await toggleComplete(task)
        }
    }

    func updateTask(
        _ task: MaintenanceTask,
        title: String, description: String?,
        dueDate: String?, priority: String, category: String,
        assigneeIds: [String], assigneeNames: [String],
        photoUrls: [String]? = nil,
        locationName: String?? = .none,
        locationLat: Double?? = .none,
        locationLon: Double?? = .none,
        recurrenceDays: Int?? = .none
    ) async throws {
        struct TaskFieldUpdate: Encodable {
            let title: String
            let description: String?
            let dueDate: String?
            let priority: String
            let category: String
            let assigneeIds: [String]
            let assigneeNames: [String]
            let updatedAt: String
            let photoUrls: [String]?
            let locationName: String?
            let locationLat: Double?
            let locationLon: Double?
            let recurrenceDays: Int?
            enum CodingKeys: String, CodingKey {
                case title, description, priority, category
                case dueDate       = "due_date"
                case assigneeIds   = "assignee_ids"
                case assigneeNames = "assignee_names"
                case updatedAt     = "updated_at"
                case photoUrls     = "photo_urls"
                case locationName  = "location_name"
                case locationLat   = "location_lat"
                case locationLon   = "location_lon"
                case recurrenceDays = "recurrence_days"
            }
            // Explicit encode: location keys write SQL NULL when nil so
            // clearing a location persists (synthesized Codable would omit
            // them and the old value would survive the save). Recurrence
            // clears the same way ("Fără repetare" must stick).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(title, forKey: .title)
                try c.encode(description, forKey: .description)
                try c.encode(dueDate, forKey: .dueDate)
                try c.encode(priority, forKey: .priority)
                try c.encode(category, forKey: .category)
                try c.encode(assigneeIds, forKey: .assigneeIds)
                try c.encode(assigneeNames, forKey: .assigneeNames)
                try c.encode(updatedAt, forKey: .updatedAt)
                try c.encode(photoUrls ?? [], forKey: .photoUrls)
                try c.encode(locationName, forKey: .locationName)
                try c.encode(locationLat, forKey: .locationLat)
                try c.encode(locationLon, forKey: .locationLon)
                try c.encode(recurrenceDays, forKey: .recurrenceDays)
            }
        }
        let update = TaskFieldUpdate(
            title: title, description: description,
            dueDate: dueDate, priority: priority, category: category,
            assigneeIds: assigneeIds, assigneeNames: assigneeNames,
            updatedAt: ISODate.string(from: Date()),
            photoUrls: photoUrls ?? task.photoUrls,
            locationName: locationName ?? task.locationName,
            locationLat: locationLat ?? task.locationLat,
            locationLon: locationLon ?? task.locationLon,
            recurrenceDays: recurrenceDays ?? task.recurrenceDays
        )
        try await supabase
            .from("maintenance_tasks")
            .update(update)
            .eq("id", value: task.id.uuidString)
            .execute()
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx].title = title
            tasks[idx].description = description
            tasks[idx].dueDate = dueDate
            tasks[idx].priority = priority
            tasks[idx].category = category
            tasks[idx].assigneeIds = assigneeIds
            tasks[idx].assigneeNames = assigneeNames
            tasks[idx].updatedAt = update.updatedAt
            tasks[idx].photoUrls = update.photoUrls ?? []
            tasks[idx].locationName = update.locationName
            tasks[idx].locationLat = update.locationLat
            tasks[idx].locationLon = update.locationLon
            tasks[idx].recurrenceDays = update.recurrenceDays
        }
    }

    /// Best-effort server mirror of a task's total worked seconds (from the
    /// work-session timer). Silent no-op until the `worked_seconds` column
    /// exists — the App Group total in WorkSessionStore is the authority, so
    /// this never surfaces an error and self-heals once the migration ships.
    nonisolated static func persistWorkedSeconds(taskId: UUID, total: TimeInterval) {
        struct WorkedUpdate: Encodable { let worked_seconds: Int }
        Task {
            _ = try? await supabase.from("maintenance_tasks")
                .update(WorkedUpdate(worked_seconds: Int(total.rounded())))
                .eq("id", value: taskId.uuidString)
                .execute()
        }
    }

    func delete(_ task: MaintenanceTask) async {
        do {
            try await supabase
                .from("maintenance_tasks")
                .delete()
                .eq("id", value: task.id.uuidString)
                .execute()
            tasks.removeAll { $0.id == task.id }
            // A running session can't outlive its task — drop it without
            // banking time or marking a now-deleted task done.
            if WorkSessionStore.shared.isTiming(task.id) { WorkSessionStore.shared.cancel() }
            // A deleted task must stop steering its Apple Reminder.
            TaskReminderLinks.unlink(taskId: task.id)
        } catch {
            self.error = error.recordableDescription
        }
    }
}
