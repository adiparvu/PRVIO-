import Foundation

// MARK: - Pending-action drain (widget / watch / notification → real writes)
//
// Every surface that cannot write to Supabase itself — widgets, the watch,
// notification actions, App Intents running in cold extension processes —
// parks its action in a SharedDataStore queue. This type turns those entries
// into the real service calls on the app's foreground beat.
//
// THE LAW (paid for with the lost card payments): a queue entry may leave
// its queue only when the app can actually act on it.
//
//  - Nothing property-scoped drains before the world is loaded. A cold
//    launch reaches `.active` before a single service has data, and the old
//    in-view drains popped — destroyed — every entry right then: watering a
//    plant from the watch while the app was closed simply never happened.
//    The guard skips the beat; `reloadWorld` calls the drain again the
//    moment the property and the loaded services exist.
//  - With the world loaded, an entry whose subject no longer exists is
//    removed as honestly gone — absence now means deletion, not "not yet".
//  - Throwing calls requeue on failure (chat replies, watch-dictated tasks,
//    pantry re-buys), so a network blip delays an action instead of losing
//    it. Card expenses keep the strictest tier: peek → insert keyed by the
//    queue entry's own id (idempotent upsert) → confirm removal, so even a
//    crash between insert and removal cannot double-charge the ledger.
//  - Void service calls (water, complete, check, return, delivered,
//    consume) stay best-effort after dispatch, exactly as before — each is
//    idempotent at the service layer, so a repeat is a no-op, not a dupe.
//
// This lives OUTSIDE MainTabView deliberately: queue orchestration is
// policy, not view code, and the view was carrying ~300 lines of it.

@MainActor
enum PendingActionDrain {

    /// Everything the drain needs, handed over by MainTabView (which owns
    /// the service instances). A plain value: build it fresh per call.
    struct Context {
        let worldLoaded: Bool
        let propertyService: PropertyService
        let profileService: ProfileService
        let auth: AuthService
        let appSettings: AppSettings
        let taskService: TaskService
        let plantService: PlantService
        let supplyService: SupplyService
        let pantryService: PantryService
        let inventoryService: InventoryService
        let deliveryService: DeliveryService
        let directMessageService: DirectMessageService
        let messageService: MessageService
        let financialService: FinancialService
        let merchantRuleService: MerchantRuleService
        /// Repaints widgets + watch after the drain changed shared state.
        let writeSnapshot: () -> Void
    }

    /// Guards the expense drain's two triggers (foreground beat and end of
    /// world load) from double-posting a payment while one pass is in flight.
    private static var expenseDrainInFlight = false

    static func run(_ ctx: Context) {
        // Self-contained hand-offs that need no property context: smart-home
        // commands the watch queued, and the wrist's "start emergency mode".
        IoTService.shared.drainPendingWatchCommands()
        if SharedDataStore.consumePendingEmergencyStart() {
            LiveActivityService.shared.startEmergency()
        }
        // THE cold-start gate. Everything below acts on loaded services and
        // the active property; popping before they exist is how actions used
        // to vanish. reloadWorld re-runs the drain when this becomes true.
        guard ctx.worldLoaded, let propId = ctx.propertyService.primary?.id else { return }

        // Failed chat mutations (pin/mark/reaction/edit/delete) recorded by
        // the journal — replayed before anything else so the chat state the
        // queues below might touch is already caught up.
        Task { await ChatMutationJournal.replayAll() }

        let waterIds = SharedDataStore.popPendingWaterings()
        for id in waterIds {
            if let plant = ctx.plantService.plants.first(where: { $0.id == id }) {
                Task { await ctx.plantService.markWatered(plant) }
            }
        }
        let completeIds = SharedDataStore.popPendingCompletions()
        for id in completeIds {
            if let task = ctx.taskService.tasks.first(where: { $0.id == id }), !task.isCompleted {
                Task { await ctx.taskService.toggleComplete(task) }
            }
        }
        drainPendingExpenses(ctx, propId: propId)
        let chatReplies = SharedDataStore.popPendingChatReplies()
        for reply in chatReplies {
            let name = ctx.profileService.profile?.preferredName
                ?? ctx.profileService.profile?.fullName ?? ""
            Task {
                do {
                    // The reply goes to the conversation the push came
                    // from: "dm:<peer>" → that direct thread; "grp:<group>"
                    // → that community sub-group; anything else → the
                    // household chat.
                    if reply.target.hasPrefix("dm:"),
                       let peerId = UUID(uuidString: String(reply.target.dropFirst(3))) {
                        _ = try await ctx.directMessageService.send(
                            propertyId: propId, senderName: name,
                            to: DMThread(peer: ChatPeer(userId: peerId)),
                            body: reply.text)
                    } else if reply.target.hasPrefix("grp:"),
                              let groupId = UUID(uuidString: String(reply.target.dropFirst(4))) {
                        try await ChatGroupService.sendMessage(
                            propertyId: propId, groupId: groupId,
                            senderName: name, body: reply.text)
                    } else {
                        try await ctx.messageService.send(propertyId: propId,
                                                          senderName: name, body: reply.text)
                    }
                } catch {
                    // Never lose a notification quick-reply to a silent
                    // drop: requeue so the next foreground beat retries.
                    SharedDataStore.appendPendingChatReply(reply.text, target: reply.target)
                }
            }
        }
        let watchTaskTitles = SharedDataStore.popPendingWatchTasks()
        for title in watchTaskTitles {
            Task {
                do {
                    try await ctx.taskService.addTask(NewTaskPayload(
                        propertyId: propId, title: title, description: nil,
                        dueDate: nil, priority: "medium", category: "maintenance",
                        assigneeIds: [], assigneeNames: []))
                } catch {
                    // A wrist-dictated task must survive a network blip —
                    // same requeue policy as the chat replies above (this
                    // one used to die in a `try?`).
                    SharedDataStore.appendPendingWatchTask(title)
                }
            }
        }
        let supplyIds = SharedDataStore.popPendingSupplyChecks()
        for id in supplyIds {
            if let item = ctx.supplyService.items.first(where: { $0.id == id }), !item.isCompleted {
                Task { await ctx.supplyService.toggleComplete(item) }
            }
        }
        // Loans marked returned from the reminder notification (IMG_8612).
        let loanReturnIds = SharedDataStore.popPendingLoanReturns()
        for id in loanReturnIds {
            if let item = ctx.inventoryService.items.first(where: { $0.id == id }), item.isLoaned {
                Task { await ctx.inventoryService.markReturned(item) }
            }
        }
        // Deliveries marked received from the Live Activity island.
        let deliveredIds = SharedDataStore.popPendingDeliveryReceived()
        for id in deliveredIds {
            if let delivery = ctx.deliveryService.deliveries.first(where: { $0.id == id }),
               delivery.status != "delivered" {
                Task { await ctx.deliveryService.markDelivered(delivery) }
            }
        }
        // Wrist pantry consumption: every queued tap is one unit off the
        // stock. Taps on the same item collapse into ONE adjustment — two
        // separate adjust(-1) calls would both start from the same stale
        // quantity and lose a unit.
        let pantryConsumeIds = SharedDataStore.popPendingPantryConsumes()
        let consumeCounts = Dictionary(pantryConsumeIds.map { ($0, 1) }, uniquingKeysWith: +)
        for (id, count) in consumeCounts {
            if let item = ctx.pantryService.items.first(where: { $0.id == id }) {
                Task { await ctx.pantryService.adjust(item, by: -Double(count)) }
            }
        }
        // Pantry items the wrist asked to re-buy — one real SupplyService
        // insert each, into the first shopping list (created if the household
        // has none yet). Sequential on purpose: parallel inserts with no list
        // would each create their own. An item already pending on a list is
        // skipped, so a repeated wrist tap never duplicates a row.
        let pantryToListIds = SharedDataStore.popPendingPantryToList()
        if !pantryToListIds.isEmpty {
            let ownerId = ctx.auth.session?.user.id
            Task {
                for id in pantryToListIds {
                    guard let name = ctx.pantryService.items.first(where: { $0.id == id })?.name
                    else { continue }
                    guard !ctx.supplyService.items.contains(where: {
                        !$0.isCompleted && $0.name.caseInsensitiveCompare(name) == .orderedSame
                    }) else { continue }
                    let now = ISO8601DateFormatter().string(from: Date())
                    do {
                        let listId: UUID
                        if let list = ctx.supplyService.lists.first {
                            listId = list.id
                        } else if let ownerId {
                            listId = try await ctx.supplyService.addList(NewSupplyListPayload(
                                propertyId: propId, ownerId: ownerId,
                                name: String(localized: "Shopping list"),
                                icon: "cart.fill", color: "#3B82F6", note: nil,
                                createdAt: now, updatedAt: now)).id
                        } else { continue }
                        _ = try await ctx.supplyService.addItem(NewSupplyItemPayload(
                            listId: listId, propertyId: propId, name: name,
                            quantity: nil, category: "food", priority: "medium",
                            notes: nil, isCompleted: false, location: nil,
                            createdAt: now, updatedAt: now))
                    } catch {
                        // Never lose a wrist request to a network blip —
                        // requeue for the next foreground beat.
                        SharedDataStore.appendPendingPantryToList(id)
                    }
                }
                // The wrist's shopping page repaints from the fresh catalog.
                ctx.writeSnapshot()
            }
        }
        // The watch's work session, mirrored into the Dynamic Island. This
        // runs on the foreground beat — exactly when the system allows a
        // Live Activity to start; the original start date keeps the elapsed
        // time truthful however late the mirror appears.
        if let event = SharedDataStore.consumePendingSessionEvent() {
            if let start = event.start {
                // Adopt the wrist-started session into the one authority so the
                // phone's banner/row timer light up with the true elapsed time;
                // start() also raises the Dynamic Island mirror.
                WorkSessionStore.shared.start(
                    taskId: start.taskId, title: start.title, startedAt: start.startedAt)
            } else if event.isEnd {
                // The wrist's "Complete" banks the time and completes the task;
                // its "End" banks the time and leaves the task open.
                if let done = WorkSessionStore.shared.finish(completingTask: event.completesTask),
                   event.completesTask,
                   let task = ctx.taskService.tasks.first(where: { $0.id == done.taskId }),
                   !task.isCompleted {
                    Task { await ctx.taskService.toggleComplete(task) }
                }
            }
        }
        if !waterIds.isEmpty || !completeIds.isEmpty || !supplyIds.isEmpty
            || !watchTaskTitles.isEmpty || !chatReplies.isEmpty || !pantryConsumeIds.isEmpty
            || !deliveredIds.isEmpty {
            ctx.writeSnapshot()
        }
    }

    /// Turns the card taps queued by `LogExpenseIntent` (the Shortcuts
    /// "Transaction" automation) into real ledger rows.
    ///
    /// The strictest tier of the drain law: PEEK, then confirm. An expense
    /// leaves the shared queue only after its insert succeeded, the insert is
    /// keyed by the queue entry's own id (idempotent upsert), and a failure
    /// simply keeps the row queued for the next beat. Money gets the
    /// exactly-once treatment the other queues approximate.
    private static func drainPendingExpenses(_ ctx: Context, propId: UUID) {
        let pending = SharedDataStore.peekPendingExpenses()
        guard !pending.isEmpty, !expenseDrainInFlight else { return }
        expenseDrainInFlight = true
        Task {
            defer { expenseDrainInFlight = false }
            // Category chain: the household's learned rule -> the static
            // chain table -> Yuna (one call per unknown merchant, cached
            // as a shared AI rule) -> honest "other".
            let aiVerdicts = await ctx.merchantRuleService.classifyUnknown(pending.map(\.merchant))
            var landed: Set<UUID> = []
            for e in pending {
                let detail = [e.card.map { String(format: String(localized: "expense_via_card_fmt"), $0) },
                              e.note]
                    .compactMap { $0 }.joined(separator: " · ")
                do {
                    try await ctx.financialService.addQueued(FinancialService.NewFinancialRecord(
                        id: e.id.uuidString,
                        propertyId: propId.uuidString,
                        title: e.merchant,
                        amount: e.amount,
                        // The currency the card was CHARGED in (IMG_9288) —
                        // the automation passes it since the Currency
                        // parameter exists; older queue entries fall back to
                        // the household's preferred currency, as before.
                        currency: e.currency ?? ctx.appSettings.preferredCurrency,
                        type: "expense",
                        category: ctx.merchantRuleService.category(for: e.merchant)
                            ?? MerchantCategorizer.staticCategory(for: e.merchant)
                            ?? aiVerdicts[e.merchant]
                            ?? "other",
                        date: e.date,
                        description: detail.isEmpty ? nil : detail,
                        tags: ["apple_pay", "auto"]))
                    landed.insert(e.id)
                } catch {
                    // Stays queued — the next foreground beat retries it.
                }
            }
            SharedDataStore.removePendingExpenses(ids: landed)
        }
    }
}
