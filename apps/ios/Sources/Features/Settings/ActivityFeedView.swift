import SwiftUI

// MARK: - Period filter

/// Feed lookback window. Chips carry explicit localized words ("Week",
/// "3 months"), never ticker codes like "1W" that read as a cryptic "1S"
/// once localized.
enum ActivityPeriod: CaseIterable {
    case week, month, threeMonths, sixMonths, year

    var days: Int {
        switch self {
        case .week:        return 7
        case .month:       return 30
        case .threeMonths: return 90
        case .sixMonths:   return 180
        case .year:        return 365
        }
    }

    /// Reuses catalog keys that already exist ("Month", "3 months"); the
    /// remaining labels are feed-specific `activity_` keys.
    var label: String {
        switch self {
        case .week:        return String(localized: "activity_period_week")
        case .month:       return String(localized: "Month")
        case .threeMonths: return String(localized: "3 months")
        case .sixMonths:   return String(localized: "activity_period_6m")
        case .year:        return String(localized: "activity_period_year")
        }
    }
}

// MARK: - Category filter

enum ActivityCategory: String, CaseIterable {
    case all        = "All"
    case tasks      = "Tasks"
    case finances   = "Finances"
    case documents  = "Documents"
    case elements   = "Elements"
    case appliances = "Appliances"
    case plants     = "Plants"

    /// Outline symbols — the filter chips render monochrome, so the lighter
    /// variants read cleaner than `.fill`.
    var icon: String {
        switch self {
        case .all:        return "square.grid.2x2"
        case .tasks:      return "checkmark.circle"
        case .finances:   return "banknote"
        case .documents:  return "doc.text"
        case .elements:   return "cube"
        case .appliances: return "washer"
        case .plants:     return "leaf"
        }
    }

    var label: String { String(localized: String.LocalizationValue(rawValue)) }
}

// MARK: - Event kind

/// The typed identity of a feed entry. Everything derived from the event
/// type lives here: title, module accent color, aggregate wording, and the
/// real navigation target for a tap.
enum ActivityKind: String {
    case incomeAdded, expenseRecorded, documentAdded
    case taskCompleted, taskOverdue, taskAdded
    case plantWatered, plantAdded
    case elementAdded, applianceAdded

    var category: ActivityCategory {
        switch self {
        case .incomeAdded, .expenseRecorded:           return .finances
        case .documentAdded:                           return .documents
        case .taskCompleted, .taskOverdue, .taskAdded: return .tasks
        case .plantWatered, .plantAdded:               return .plants
        case .elementAdded:                            return .elements
        case .applianceAdded:                          return .appliances
        }
    }

    /// Existing catalog keys — the same titles the feed has always shown.
    var title: LocalizedStringKey {
        switch self {
        case .incomeAdded:     return "Income added"
        case .expenseRecorded: return "Expense recorded"
        case .documentAdded:   return "Document added"
        case .taskCompleted:   return "Task completed"
        case .taskOverdue:     return "Task overdue"
        case .taskAdded:       return "Task added"
        case .plantWatered:    return "Plant watered"
        case .plantAdded:      return "Plant added"
        case .elementAdded:    return "Element added"
        case .applianceAdded:  return "Appliance added"
        }
    }

    /// Module accent, consistent with the rest of the app: finances green
    /// banknote, documents orange, watered plants blue drop, completed tasks
    /// green check, overdue red, twin content purple/indigo — the same hues
    /// the Settings rows and module pages already use.
    var color: Color {
        switch self {
        case .incomeAdded, .expenseRecorded: return .brandSuccess
        case .documentAdded:                 return .brandWarning
        case .taskCompleted:                 return .brandSuccess
        case .taskOverdue:                   return .brandDanger
        case .taskAdded:                     return .brandPrimaryBlue
        case .plantWatered:                  return .brandSkyBlue
        case .plantAdded:                    return .brandSuccess
        case .elementAdded:                  return .brandPurple
        case .applianceAdded:                return .brandIndigo
        }
    }

    /// Where a tap lands. Tasks, plants and documents open the object itself
    /// (the router carries the deep-link id); finances opens its module page
    /// (the router has no per-record route for it); elements and appliances
    /// live in the property twin — the closest real destination the router
    /// has (the same mapping NFC deep links use).
    func route(objectId: UUID?) -> AppRouter.AppRoute {
        switch self {
        case .taskCompleted, .taskOverdue, .taskAdded: return .tasks(id: objectId)
        case .plantWatered, .plantAdded:               return .plants(id: objectId)
        case .incomeAdded, .expenseRecorded:           return .finances
        case .documentAdded:                           return .documents(id: objectId)
        case .elementAdded, .applianceAdded:           return .twin
        }
    }

    /// "2 tasks completed" — aggregate row titles. Only ever called with
    /// count ≥ 2, so each key is the plural wording by construction; the
    /// singular path renders individual rows, keeping the catalog free of
    /// plural variations.
    func aggregateTitle(_ count: Int) -> String {
        let format: String
        switch self {
        case .incomeAdded:     format = String(localized: "activity_agg_incomes")
        case .expenseRecorded: format = String(localized: "activity_agg_expenses")
        case .documentAdded:   format = String(localized: "activity_agg_documents")
        case .taskCompleted:   format = String(localized: "activity_agg_tasks_completed")
        case .taskOverdue:     format = String(localized: "activity_agg_tasks_overdue")
        case .taskAdded:       format = String(localized: "activity_agg_tasks_added")
        case .plantWatered:    format = String(localized: "activity_agg_plants_watered")
        case .plantAdded:      format = String(localized: "activity_agg_plants_added")
        case .elementAdded:    format = String(localized: "activity_agg_elements")
        case .applianceAdded:  format = String(localized: "activity_agg_appliances")
        }
        return String.localizedStringWithFormat(format, count)
    }
}

// MARK: - Event model

/// One synthesized feed entry. Carries its source identity (kind + object
/// id) so a tap can open the real object, and whether the source stored a
/// real time of day — date-only sources must never display a fictitious
/// "00:00".
struct ActivityEvent: Identifiable {
    let kind: ActivityKind
    let icon: String
    let subtitle: String
    let date: Date
    /// False when the source stores only a calendar day (finance records,
    /// date-only due dates) — the row then shows a short date, not 00:00.
    let hasTime: Bool
    /// Filter identity: the "You" sentinel or a family member's name.
    let member: String
    /// `family_members.id` when the source knows it (task assignees) — the
    /// strongest avatar key; name matching is the fallback.
    let memberId: String?
    /// The id of the object this event describes, when one exists.
    let sourceId: UUID?

    /// Stable across body evaluations (unlike a fresh UUID), so expansion
    /// state and animation diffs keep tracking the same row.
    var id: String {
        "\(kind.rawValue)|\(sourceId?.uuidString ?? subtitle)|\(Int(date.timeIntervalSince1970))"
    }

    var title: LocalizedStringKey { kind.title }
    var color: Color { kind.color }
    var category: ActivityCategory { kind.category }
}

/// Consecutive same-day events of the same kind by the same member,
/// collapsed into one expandable row ("2 tasks completed").
struct ActivityAggregate: Identifiable {
    let kind: ActivityKind
    let member: String
    let memberId: String?
    /// Newest first, ≥ 2 by construction.
    let events: [ActivityEvent]

    var id: String { "agg|\(events.first?.id ?? kind.rawValue)|\(events.count)" }
    var icon: String { events.first?.icon ?? kind.category.icon }
    var title: String { kind.aggregateTitle(events.count) }
    var subtitle: String { events.map(\.subtitle).joined(separator: ", ") }
}

/// One rendered row of a day card: a single event or an aggregate.
enum ActivityRowItem: Identifiable {
    case single(ActivityEvent)
    case aggregate(ActivityAggregate)

    var id: String {
        switch self {
        case .single(let e):    return e.id
        case .aggregate(let a): return a.id
        }
    }
}

/// Rows of one calendar day, newest first.
struct ActivityDayGroup: Identifiable {
    let day: Date
    let items: [ActivityRowItem]
    let eventCount: Int
    var id: Date { day }
}

/// The whole feed derived in a single pass per body evaluation — the body
/// never re-filters or re-groups inside its loops.
private struct ActivityFeedSnapshot {
    let groups: [ActivityDayGroup]
    /// Events inside the selected period, before category/member filters —
    /// distinguishes "no activity at all" from "filters matched nothing".
    let periodCount: Int
    let visibleCount: Int
}

// MARK: - View

struct ActivityFeedView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(DocumentService.self) private var documentService
    @Environment(FamilyService.self) private var familyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(TaskService.self) private var taskService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(PlantService.self) private var plantService
    @Environment(AppRouter.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var period:           ActivityPeriod   = .month
    @State private var selectedMember:   String?          = nil
    @State private var selectedCategory: ActivityCategory = .all
    /// Aggregate rows the user opened up into their individual events.
    @State private var expandedAggregates: Set<String> = []

    /// Internal sentinel for "the signed-in user" — kept stable for filter
    /// equality; presented through the localized "You" catalog key.
    private let currentUser = "You"

    private var filterAnimation: Animation? { reduceMotion ? nil : AppMotion.state }
    private var expandAnimation: Animation? { reduceMotion ? nil : .snappy }

    // MARK: Event synthesis

    private var allEvents: [ActivityEvent] {
        var events: [ActivityEvent] = []

        // Finances — record dates are calendar days ("YYYY-MM-DD"), so no
        // real time of day exists; the row shows a short date instead.
        for r in financialService.records {
            guard let date = AppDate.day(from: r.date) else { continue }
            let isIncome = r.type == "income"
            events.append(ActivityEvent(
                kind:     isIncome ? .incomeAdded : .expenseRecorded,
                icon:     isIncome ? "arrow.down.circle.fill" : "arrow.up.circle.fill",
                subtitle: "\(r.title) · \(financialService.moneyDisplay(r.amount))",
                date:     date,
                hasTime:  r.date.count > 10,
                member:   currentUser,
                memberId: nil,
                sourceId: r.id
            ))
        }

        // Documents
        for doc in documentService.documents {
            let date = AppDate.timestamp(from: doc.createdAt) ?? Date()
            events.append(ActivityEvent(
                kind:     .documentAdded,
                icon:     doc.categoryIcon,
                subtitle: doc.name,
                date:     date,
                hasTime:  true,
                member:   currentUser,
                memberId: nil,
                sourceId: doc.id
            ))
        }

        // Tasks
        for task in taskService.tasks {
            let taskMember   = task.assigneeNames.first ?? currentUser
            let taskMemberId = task.assigneeIds.first
            if task.isCompleted {
                let date = AppDate.timestamp(from: task.updatedAt)
                    ?? AppDate.timestamp(from: task.createdAt) ?? Date()
                events.append(ActivityEvent(
                    kind:     .taskCompleted,
                    icon:     "checkmark.circle.fill",
                    subtitle: task.title,
                    date:     date,
                    hasTime:  true,
                    member:   taskMember,
                    memberId: taskMemberId,
                    sourceId: task.id
                ))
            } else if let due = task.dueDate,
                      let dueDate = AppDate.day(from: due),
                      isOverdue(dueDate, hasTime: due.count > 10) {
                // Due dates are usually date-only — a day is overdue once it
                // has fully passed, and its row never invents a 00:00 time.
                events.append(ActivityEvent(
                    kind:     .taskOverdue,
                    icon:     "exclamationmark.circle.fill",
                    subtitle: task.title,
                    date:     dueDate,
                    hasTime:  due.count > 10,
                    member:   taskMember,
                    memberId: taskMemberId,
                    sourceId: task.id
                ))
            } else {
                let created = AppDate.timestamp(from: task.createdAt) ?? Date()
                events.append(ActivityEvent(
                    kind:     .taskAdded,
                    icon:     "clock.fill",
                    subtitle: task.title,
                    date:     created,
                    hasTime:  true,
                    member:   taskMember,
                    memberId: taskMemberId,
                    sourceId: task.id
                ))
            }
        }

        // Plants
        for plant in plantService.plants {
            if let wateredStr = plant.lastWateredAt,
               let wateredDate = AppDate.timestamp(from: wateredStr) {
                events.append(ActivityEvent(
                    kind:     .plantWatered,
                    icon:     "drop.fill",
                    subtitle: plant.name,
                    date:     wateredDate,
                    hasTime:  true,
                    member:   currentUser,
                    memberId: nil,
                    sourceId: plant.id
                ))
            }
            let addedDate = AppDate.timestamp(from: plant.createdAt) ?? Date()
            let plantSubtitle = plant.emoji.isEmpty ? plant.name : "\(plant.emoji) \(plant.name)"
            events.append(ActivityEvent(
                kind:     .plantAdded,
                icon:     "leaf.fill",
                subtitle: plantSubtitle,
                date:     addedDate,
                hasTime:  true,
                member:   currentUser,
                memberId: nil,
                sourceId: plant.id
            ))
        }

        // Property elements
        for el in elementService.elements {
            let date = AppDate.timestamp(from: el.createdAt) ?? Date()
            events.append(ActivityEvent(
                kind:     .elementAdded,
                icon:     el.elementType.icon,
                subtitle: el.name,
                date:     date,
                hasTime:  true,
                member:   currentUser,
                memberId: nil,
                sourceId: el.id
            ))
        }

        // Appliances
        for ap in applianceService.appliances {
            let date = AppDate.timestamp(from: ap.createdAt) ?? Date()
            events.append(ActivityEvent(
                kind:     .applianceAdded,
                icon:     ap.categoryIcon,
                subtitle: [ap.brand, ap.name].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " "),
                date:     date,
                hasTime:  true,
                member:   currentUser,
                memberId: nil,
                sourceId: ap.id
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    /// A timed due date is overdue the moment it passes; a date-only due
    /// date only once its whole day has passed — never at a fictitious 00:00.
    private func isOverdue(_ due: Date, hasTime: Bool) -> Bool {
        hasTime ? due < Date() : due < Calendar.current.startOfDay(for: Date())
    }

    /// Filters, groups and aggregates in one pass; called once per body
    /// evaluation.
    private var feedSnapshot: ActivityFeedSnapshot {
        let cutoff = Calendar.current.date(byAdding: .day, value: -period.days, to: Date()) ?? Date()
        let inPeriod = allEvents.filter { $0.date >= cutoff }
        let visible = inPeriod.filter {
            (selectedMember == nil || $0.member == selectedMember)
                && (selectedCategory == .all || $0.category == selectedCategory)
        }

        let cal = Calendar.current
        var buckets: [Date: [ActivityEvent]] = [:]
        for event in visible {
            buckets[cal.startOfDay(for: event.date), default: []].append(event)
        }
        // `visible` is already newest-first, so each bucket stays sorted.
        let groups = buckets.keys.sorted(by: >).map { day -> ActivityDayGroup in
            let dayEvents = buckets[day] ?? []
            return ActivityDayGroup(day: day,
                                    items: Self.aggregated(dayEvents),
                                    eventCount: dayEvents.count)
        }
        return ActivityFeedSnapshot(groups: groups,
                                    periodCount: inPeriod.count,
                                    visibleCount: visible.count)
    }

    /// Collapses runs of ≥ 2 consecutive events of the same kind by the same
    /// member into one aggregate row; everything else stays a single row.
    private static func aggregated(_ events: [ActivityEvent]) -> [ActivityRowItem] {
        var items: [ActivityRowItem] = []
        var i = 0
        while i < events.count {
            let head = events[i]
            var j = i + 1
            while j < events.count,
                  events[j].kind == head.kind,
                  events[j].member == head.member {
                j += 1
            }
            if j - i >= 2 {
                items.append(.aggregate(ActivityAggregate(kind: head.kind,
                                                          member: head.member,
                                                          memberId: head.memberId,
                                                          events: Array(events[i..<j]))))
            } else {
                items.append(.single(head))
            }
            i = j
        }
        return items
    }

    // MARK: Members for filter

    private var allMembers: [String] {
        [currentUser] + familyService.members.map(\.name)
    }

    // MARK: Body

    var body: some View {
        let snapshot = feedSnapshot
        VStack(spacing: 0) {

            countLine(snapshot.visibleCount)
                .padding(.top, AppSpacing.sm)

            Divider().opacity(0.3).padding(.top, AppSpacing.sm)

            if snapshot.visibleCount == 0 {
                emptyState(filtersMatchedNothing: snapshot.periodCount > 0)
            } else {
                timeline(snapshot.groups)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                filterButton
            }
        }
        .task { await MemberDirectory.shared.loadIfNeeded() }
    }

    // MARK: Aggregated filter (toolbar) + event count line

    /// The one aggregated filter, on the NATIVE system menu like every other
    /// page (IMG_8593) — the last rich-popover holdout retired by user
    /// decree. The People section's search field and avatar rows were the
    /// exception's whole justification; a household roster is short, so
    /// members are plain single-select options ("Everyone" clears), and
    /// avatars/search are not menu anatomy (HIG). `inToolbar` because
    /// iOS 26 wraps toolbar controls in system glass (IMG_8315).
    private var filterButton: some View {
        GlassFilterButton(
            isActive: period != .month || selectedCategory != .all || selectedMember != nil,
            inToolbar: true
        ) {
            GlassFilterSection(
                title: "Period",
                options: ActivityPeriod.allCases.map {
                    GlassPickerOption(value: $0, title: $0.label)
                },
                selection: Binding(
                    get: { period },
                    set: { newValue in withAnimation(filterAnimation) { period = newValue } }))
            GlassFilterSectionDivider()
            GlassFilterSection(
                title: "Category",
                options: ActivityCategory.allCases.map {
                    GlassPickerOption(value: $0, icon: $0.icon, title: $0.label)
                },
                selection: Binding(
                    get: { selectedCategory },
                    set: { newValue in
                        withAnimation(filterAnimation) { selectedCategory = newValue }
                    }))
            GlassFilterSectionDivider()
            GlassFilterSection(
                title: "People",
                options: [GlassPickerOption(value: "", title: String(localized: "Everyone"))]
                    + allMembers.map { GlassPickerOption(value: $0, title: displayName($0)) },
                selection: Binding(
                    get: { selectedMember ?? "" },
                    set: { newValue in
                        withAnimation(filterAnimation) {
                            selectedMember = newValue.isEmpty ? nil : newValue
                        }
                    }))
        }
    }

    /// The honest event count stays on the page (where the filter row used
    /// to be) while the filters that produce it live in the toolbar popover.
    private func countLine(_ count: Int) -> some View {
        Text(eventCountLabel(count))
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(filterAnimation, value: count)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.xl)
    }

    /// "12 events" — explicit wording instead of a bare number pill. The
    /// singular/plural key is chosen in code, keeping the catalog free of
    /// plural variations.
    private func eventCountLabel(_ count: Int) -> String {
        count == 1
            ? String(localized: "activity_event_count_one")
            : String.localizedStringWithFormat(String(localized: "activity_event_count_many"), count)
    }

    // MARK: Timeline

    private func timeline(_ groups: [ActivityDayGroup]) -> some View {
        ScrollView(showsIndicators: false) {
            // Headers are NOT pinned: they are naked text (no chip, no band —
            // IMG_8559 "fără chenar"), so they must scroll with their rows
            // rather than have content slide beneath bare glyphs.
            LazyVStack(spacing: AppSpacing.xl) {
                ForEach(groups) { group in
                    Section {
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.id) { idx, item in
                                    rows(for: item, isLastItem: idx == group.items.count - 1)
                                }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl)
                    } header: {
                        dayHeader(group.day, eventCount: group.eventCount)
                    }
                }
                Spacer(minLength: 100)
            }
            .padding(.top, AppSpacing.md)
            .animation(filterAnimation, value: period)
            .animation(filterAnimation, value: selectedCategory)
            .animation(filterAnimation, value: selectedMember)
        }
    }

    /// A single row, or an aggregate row followed by its expanded children.
    @ViewBuilder
    private func rows(for item: ActivityRowItem, isLastItem: Bool) -> some View {
        switch item {
        case .single(let event):
            eventRow(event, showsDivider: !isLastItem, indented: false)

        case .aggregate(let agg):
            let isExpanded = expandedAggregates.contains(agg.id)
            ActivityAggregateRow(
                aggregate: agg,
                isExpanded: isExpanded,
                member: familyMember(named: agg.member, id: agg.memberId),
                memberDisplayName: displayName(agg.member),
                isCurrentUser: agg.member == currentUser,
                showsDivider: isExpanded || !isLastItem
            ) {
                toggleAggregate(agg.id)
            }
            if isExpanded {
                ForEach(Array(agg.events.enumerated()), id: \.element.id) { idx, event in
                    eventRow(event,
                             showsDivider: idx < agg.events.count - 1 || !isLastItem,
                             indented: true)
                }
            }
        }
    }

    private func eventRow(_ event: ActivityEvent, showsDivider: Bool, indented: Bool) -> some View {
        ActivityEventRow(
            event: event,
            member: familyMember(named: event.member, id: event.memberId),
            memberDisplayName: displayName(event.member),
            isCurrentUser: event.member == currentUser,
            showsDivider: showsDivider,
            indented: indented
        ) {
            open(event)
        }
    }

    private func toggleAggregate(_ id: String) {
        HapticFeedback.selection()
        withAnimation(expandAnimation) {
            if expandedAggregates.contains(id) {
                expandedAggregates.remove(id)
            } else {
                expandedAggregates.insert(id)
            }
        }
    }

    /// Opens the real object behind an event: tasks/plants deep-link to the
    /// item itself, finances/documents open their module page, elements and
    /// appliances open the property twin. Routing through the router lands
    /// correctly regardless of which tab or stack is current.
    private func open(_ event: ActivityEvent) {
        HapticFeedback.selection()
        router.navigate(to: event.kind.route(objectId: event.sourceId))
    }

    private func dayHeader(_ day: Date, eventCount: Int) -> some View {
        // Naked text — no chip, no band, no background of any kind
        // (IMG_8541 → IMG_8559): the label sits directly on the living
        // backdrop and scrolls with its rows, the Journal-app pattern.
        HStack {
            HStack(spacing: AppSpacing.xs) {
                dayTitle(day)
                    .font(AppFont.scaled(12, weight: .semibold))
                    .foregroundStyle(Color.backdropPrimaryText)
                    .tracking(0.5)
                Text(verbatim: "·")
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.backdropSecondaryText)
                Text(eventCountLabel(eventCount))
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.backdropSecondaryText)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.xs)
        .accessibilityElement(children: .combine)
    }

    /// "Today"/"Yesterday" resolve through the catalog; other days use the
    /// shared locale-aware formatters (year appended once it's not this year).
    private func dayTitle(_ day: Date) -> Text {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return Text("Today") }
        if cal.isDateInYesterday(day) { return Text("Yesterday") }
        let formatter = cal.isDate(day, equalTo: Date(), toGranularity: .year)
            ? AppDate.monthDay : AppDate.monthDayYear
        return Text(formatter.string(from: day))
    }

    // MARK: Empty state

    private func emptyState(filtersMatchedNothing: Bool) -> some View {
        VStack {
            Spacer()
            if filtersMatchedNothing {
                EmptyStateView(icon: "line.3.horizontal.decrease",
                               title: "No results")
            } else {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "No activity in this period",
                    message: "Activities appear automatically as you\nadd tasks, documents, and transactions."
                )
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Helpers

    private func displayName(_ member: String) -> String {
        member == currentUser ? String(localized: "You") : member
    }

    /// Resolves the family member behind an event — by `family_members.id`
    /// when the source carried one (task assignees), by name otherwise.
    private func familyMember(named name: String, id: String?) -> FamilyMember? {
        if let id,
           let match = familyService.members.first(where: {
               $0.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
           }) {
            return match
        }
        return familyService.members.first { $0.name == name }
    }
}
