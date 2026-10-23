import SwiftUI

// The house calendar: EVERY date the property knows about — task due dates,
// document/paper expirations, appliance warranties, family birthdays, recurring
// bills, plant care and lease deadlines. All of it flows from ONE aggregator
// (HouseAgenda); this screen is just four lenses onto that stream — Month grid,
// Week strip + day, a single Day, and a forward Agenda list — filtered by the
// category chips, mirrored to Apple Calendar and exported as .ics.
struct CalendarView: View {
    @Environment(TaskService.self) private var taskService
    @Environment(DocumentService.self) private var documentService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(PlantService.self) private var plantService
    @Environment(CalendarEventService.self) private var calendarEventService
    @Environment(VehicleService.self) private var vehicleService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The focal date the current mode is centred on (month/week/day). Agenda
    /// always reads forward from today, so it ignores this.
    @State private var anchor = Date()
    /// The day whose detail list is shown under the Month grid / Week strip.
    @State private var selectedDay: Date? = Date()
    @State private var mode: CalendarMode = Self.storedMode()
    @State private var icsURL: URL? = nil
    /// Which categories are shown. All on by default; chips toggle them and the
    /// choice persists across launches.
    @State private var active: Set<AgendaCategory> = Self.storedActiveCategories()
    /// Mirror-to-Apple-Calendar toggle (mirrors the persisted flag).
    @State private var mirrorOn = HouseCalendarMirror.isEnabled
    /// The event whose editor is open (tap an event row), or nil.
    @State private var editingEvent: CalendarEvent? = nil
    /// True while the new-event editor sheet is presented.
    @State private var creatingEvent = false
    /// The day a newly created event defaults to (the selected/anchored day).
    @State private var newEventDay = Date()

    private let cal = Calendar.current
    private static let activeCategoriesKey = "houseCalendar.activeCategories"
    private static let modeKey = "houseCalendar.mode"

    // MARK: - Persistence

    private static func storedActiveCategories() -> Set<AgendaCategory> {
        guard let raw = UserDefaults.standard.stringArray(forKey: activeCategoriesKey) else {
            return Set(AgendaCategory.allCases)
        }
        return Set(raw.compactMap(AgendaCategory.init(rawValue:)))
    }
    private func persistActiveCategories() {
        UserDefaults.standard.set(active.map(\.rawValue).sorted(), forKey: Self.activeCategoriesKey)
    }
    private static func storedMode() -> CalendarMode {
        UserDefaults.standard.string(forKey: modeKey).flatMap(CalendarMode.init(rawValue:)) ?? .month
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                periodHeader
                content
            }
        }
        .navigationTitle(Text("house_calendar_title"))
        // Large, like every other page (IMG_8565) — the calendar is not an
        // exception to the app's title language.
        .navigationBarTitleDisplayMode(.large)
        .toolbar { optionsMenu }
        .sheet(isPresented: $creatingEvent, onDismiss: mirrorIfEnabled) {
            CalendarEventEditor(propertyId: propertyService.primary?.id, defaultDay: newEventDay)
        }
        .sheet(item: $editingEvent, onDismiss: mirrorIfEnabled) { event in
            CalendarEventEditor(propertyId: propertyService.primary?.id,
                                existing: event,
                                defaultDay: event.startDate ?? Date())
        }
        .onAppear {
            buildICS()
            if HouseCalendarMirror.isEnabled {
                Task { await HouseCalendarMirror.sync(fullAgenda()) }
            }
        }
        .onChange(of: mode) { _, m in UserDefaults.standard.set(m.rawValue, forKey: Self.modeKey) }
        .onChange(of: mirrorOn) { _, on in
            Task {
                if on {
                    let ok = await HouseCalendarMirror.enable(with: fullAgenda())
                    if !ok { mirrorOn = false }
                } else {
                    HouseCalendarMirror.disableAndRemove()
                }
            }
        }
    }

    // MARK: - Content per mode

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .month:
            VStack(spacing: 0) {
                weekdayRow
                daysGrid
                Divider().background(Color.primary.opacity(AppOpacity.hairline)).padding(.top, AppSpacing.sm)
                selectedDayDetail
            }
        case .week:
            let weekByDay = itemsByDay(in: weekRange(of: anchor))
            VStack(spacing: 0) {
                CalendarWeekStrip(
                    weekDays: weekDays(of: anchor),
                    selectedDay: selectedDay,
                    dotsFor: { dots(for: $0, byDay: weekByDay) },
                    onSelect: { select($0) }
                )
                .contentShape(Rectangle())
                .gesture(periodSwipe)
                Divider().background(Color.primary.opacity(AppOpacity.hairline))
                selectedDayDetail
            }
        case .day:
            VStack(spacing: 0) {
                CalendarDayHeader(date: anchor)
                    .contentShape(Rectangle())
                    .gesture(periodSwipe)
                Divider().background(Color.primary.opacity(AppOpacity.hairline))
                dayList(for: anchor)
            }
        case .agenda:
            agendaList
        }
    }

    // MARK: - Period header (title + today + prev/next)

    private var periodHeader: some View {
        HStack(spacing: AppSpacing.sm) {
            if mode != .agenda {
                stepButton(system: "chevron.left", label: "Previous", delta: -1)
            }
            Spacer(minLength: 0)
            Text(periodTitle)
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(Color.glassInk)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
            if !cal.isDateInToday(anchor) || mode == .agenda {
                Button { jumpToToday() } label: {
                    Text("cal_today")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("cal_today"))
            }
            if mode != .agenda {
                stepButton(system: "chevron.right", label: "Next", delta: 1)
            }
        }
        .frame(minHeight: 36)
        .padding(.horizontal, AppSpacing.xl)
        .padding(.vertical, AppSpacing.sm)
    }

    private func stepButton(system: String, label: LocalizedStringKey, delta: Int) -> some View {
        Button { step(delta) } label: {
            Image(systemName: system)
                .font(AppFont.headline)
                .foregroundStyle(.primary)
                .frame(width: 34, height: 34)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Weekday labels (Month grid)

    private var weekdayRow: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let mondayFirst = (0..<7).map { symbols[($0 + 1) % 7] }
        return HStack(spacing: 0) {
            ForEach(Array(mondayFirst.enumerated()), id: \.offset) { _, d in
                Text(d)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, AppSpacing.md)
    }

    // MARK: - Month grid

    private var daysGrid: some View {
        let days = daysInMonth()
        // Compute the whole month's items ONCE, then read per-day dots off it —
        // recomputing the agenda for each of the 42 cells would be O(n) per cell.
        let byDay = itemsByDay(in: monthRange(of: anchor))
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                if let day = day {
                    DayCell(
                        date: day,
                        isToday: cal.isDateInToday(day),
                        isSelected: selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false,
                        dots: dots(for: day, byDay: byDay)
                    ) {
                        withAnimation(.spring(response: 0.22)) {
                            selectedDay = cal.isDate(selectedDay ?? .distantPast, inSameDayAs: day) ? nil : day
                        }
                    }
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.xxs)
        .contentShape(Rectangle())
        .gesture(periodSwipe)
    }

    // MARK: - Selected-day detail (Month + Week share it)

    @ViewBuilder
    private var selectedDayDetail: some View {
        if let day = selectedDay {
            dayList(for: day)
        } else {
            VStack(spacing: 8) {
                Spacer()
                Text("cal_tap_day")
                    .font(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.25))
                Spacer()
            }
        }
    }

    /// One day's items as a scrollable list (Day mode + the selected-day detail).
    @ViewBuilder
    private func dayList(for day: Date) -> some View {
        let items = itemsByDay(in: dayRange(day))[AppDate.dayString(from: day)] ?? []
        if items.isEmpty {
            CalendarEmptyDay()
        } else {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    ForEach(items) { item in
                        agendaRow(for: item)
                    }
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .padding(.bottom, 100)
            }
        }
    }

    // MARK: - Agenda (forward, grouped by day)

    private var agendaList: some View {
        let sections = agendaSections()
        return Group {
            if sections.isEmpty {
                CalendarEmptyDay()
            } else {
                ScrollView(showsIndicators: false) {
                    // Headers are naked text (IMG_8559) — unpinned, so rows
                    // never slide beneath bare glyphs.
                    LazyVStack(alignment: .leading, spacing: AppSpacing.md) {
                        ForEach(sections) { section in
                            Section {
                                VStack(spacing: 8) {
                                    ForEach(section.items) { item in
                                        agendaRow(for: item)
                                    }
                                }
                            } header: {
                                agendaSectionHeader(section.day)
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, 100)
                }
            }
        }
    }

    private func agendaSectionHeader(_ day: Date) -> some View {
        // Naked text — no chip, no band, no background of any kind
        // (IMG_8542 → IMG_8559): the label sits directly on the living
        // backdrop and scrolls with its rows.
        HStack {
            Text(agendaHeaderLabel(day))
                .font(AppFont.scaled(13, weight: .bold))
                .foregroundStyle(cal.isDateInToday(day) ? Color.accentColor : Color.backdropPrimaryText)
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppSpacing.xxs)
    }

    private func agendaHeaderLabel(_ day: Date) -> String {
        if cal.isDateInToday(day) { return String(localized: "cal_today") }
        if cal.isDateInTomorrow(day) { return String(localized: "cal_tomorrow") }
        let f = DateFormatter(); f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE d MMM"); return f.string(from: day)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var optionsMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                HapticFeedback.selection()
                newEventDay = selectedDay ?? anchor
                creatingEvent = true
            } label: {
                Image(systemName: "plus")
                    .font(AppFont.scaled(17, weight: .semibold))
                    .foregroundStyle(Color.glassInk)
            }
            .accessibilityLabel(Text("cal_new_event"))
            .disabled(propertyService.primary == nil)
        }
        ToolbarItem(placement: .pageMenu) {
            // ONE menu for the whole page (IMG_8564): the mode capsule, the
            // category filter circle and the old "…" options all live here.
            GlassFilterButton(isActive: active.count < AgendaCategory.allCases.count,
                              inToolbar: true,
                              accessibilityLabelKey: "cal_filter_all") {
                // Menu-in-menu (the 4-facet rule): the view mode drills into
                // its own native submenu with the current value on the row.
                GlassDrillMenu(entries: [
                    .facet(id: "mode", icon: "calendar.day.timeline.left",
                           title: "cal_mode_picker",
                           options: CalendarMode.allCases.map {
                               GlassPickerOption(value: $0, icon: $0.icon, title: modeLabel($0))
                           },
                           selection: Binding(
                               get: { mode },
                               set: { newMode in
                                   withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                                       mode = newMode
                                   }
                               }),
                           isNarrowed: false)
                ]) {
                    // Categories are MULTI-select — a facet the drill model
                    // can't erase into one value, so it nests as its own
                    // native submenu card of toggles (the Photos multi facet),
                    // with the honest narrowed count on the row.
                    Menu {
                        GlassFilterMultiSection(
                            options: AgendaCategory.allCases.map {
                                GlassPickerOption(value: $0, icon: $0.icon, title: catLabel($0))
                            },
                            selection: $active,
                            onChange: { persistActiveCategories() })
                    } label: {
                        Text("Categories")
                        Text(verbatim: "\(active.count)/\(AgendaCategory.allCases.count)")
                        Image(systemName: "square.grid.2x2")
                    }
                    Divider()
                GlassFilterToggleRow(icon: "calendar",
                                     title: String(localized: "cal_sync_apple"),
                                     isOn: $mirrorOn)
                if mirrorOn {
                    GlassFilterActionRow(icon: "arrow.triangle.2.circlepath",
                                         title: String(localized: "cal_sync_now")) {
                        Task { await HouseCalendarMirror.sync(fullAgenda()) }
                    }
                }
                if let icsURL {
                    GlassFilterActionRow(icon: "square.and.arrow.up",
                                         title: String(localized: "cal_export_ics")) {
                        SystemActions.share([icsURL])
                    }
                }
                }
            }
        }
    }

    // MARK: - Navigation

    private func step(_ delta: Int) {
        guard let d = cal.date(byAdding: mode.stepComponent, value: delta, to: anchor) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            anchor = d
            if mode == .day { selectedDay = cal.startOfDay(for: d) }
            // Keep a valid selection inside the new week.
            if mode == .week, let sel = selectedDay,
               !weekDays(of: d).contains(where: { cal.isDate($0, inSameDayAs: sel) }) {
                selectedDay = nil
            }
        }
    }

    private func jumpToToday() {
        // Agenda already reads forward from today; month/week/day recentre.
        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
            anchor = Date(); selectedDay = Date()
        }
    }

    private func select(_ day: Date) {
        HapticFeedback.selection()
        withAnimation(.spring(response: 0.22)) { selectedDay = day }
    }

    /// A horizontal swipe steps the period; the vertical lists keep their scroll.
    private var periodSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.4,
                      abs(v.translation.width) > 50 else { return }
                step(v.translation.width < 0 ? 1 : -1)
            }
    }

    // MARK: - Ranges + agenda data

    private func monthRange(of date: Date) -> ClosedRange<Date> {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: date)),
              let range = cal.range(of: .day, in: .month, for: start),
              let end = cal.date(byAdding: .day, value: range.count - 1, to: start) else {
            let d = cal.startOfDay(for: date); return d...d
        }
        return start...end
    }
    private func weekRange(of date: Date) -> ClosedRange<Date> {
        let days = weekDays(of: date)
        return (days.first ?? date)...(days.last ?? date)
    }
    private func dayRange(_ date: Date) -> ClosedRange<Date> {
        let d = cal.startOfDay(for: date); return d...d
    }
    private func weekDays(of date: Date) -> [Date] {
        // Monday-first week containing `date`.
        var weekday = cal.component(.weekday, from: date) - 2
        if weekday < 0 { weekday += 7 }
        guard let monday = cal.date(byAdding: .day, value: -weekday, to: cal.startOfDay(for: date)) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// The current mode's on-screen range → HouseAgenda items, filtered, grouped
    /// by day string. Month/week-scoped so it stays small; recomputed per pass.
    private func itemsByDay(in range: ClosedRange<Date>) -> [String: [AgendaItem]] {
        Dictionary(grouping: agendaItems(in: range)) { AppDate.dayString(from: $0.date) }
    }

    private func agendaItems(in range: ClosedRange<Date>) -> [AgendaItem] {
        HouseAgenda.items(
            in: range,
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants,
            leases: Array(familyService.leases.values),
            events: calendarEventService.events,
            vehicles: vehicleService.vehicles
        ).filter { active.contains($0.category) }
    }

    /// Forward-planning agenda: today … +3 months, grouped into non-empty days.
    private func agendaSections() -> [CalendarAgendaSection] {
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .month, value: 3, to: start) ?? start
        let grouped = Dictionary(grouping: agendaItems(in: start...end)) { cal.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { CalendarAgendaSection(day: $0, items: grouped[$0] ?? []) }
    }

    /// The full mirror window (−1…+12 months), ALL categories — what the Apple
    /// Calendar mirror reconciles against, independent of the on-screen filter.
    private func fullAgenda() -> [AgendaItem] {
        HouseAgenda.upcomingYear(
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members,
            financial: financialService.records, plants: plantService.plants,
            leases: Array(familyService.leases.values),
            events: calendarEventService.events)
    }

    /// After creating/editing/deleting an event, keep the Apple Calendar mirror
    /// in step (a no-op when the mirror is off).
    private func mirrorIfEnabled() {
        guard HouseCalendarMirror.isEnabled else { return }
        Task { await HouseCalendarMirror.sync(fullAgenda()) }
    }

    private func buildICS() {
        icsURL = HouseCalendarICS.writeFile(
            tasks: taskService.tasks, documents: documentService.documents,
            appliances: applianceService.appliances, members: familyService.members)
    }

    // MARK: - Small helpers

    private func catLabel(_ cat: AgendaCategory) -> String {
        switch cat {
        case .event:     return String(localized: "agenda_cat_events")
        case .task:      return String(localized: "agenda_cat_tasks")
        case .document:  return String(localized: "agenda_cat_documents")
        case .warranty:  return String(localized: "agenda_cat_warranties")
        case .birthday:  return String(localized: "agenda_cat_birthdays")
        case .financial: return String(localized: "agenda_cat_financial")
        case .plant:     return String(localized: "agenda_cat_plants")
        case .lease:     return String(localized: "agenda_cat_leases")
        case .vehicle:   return String(localized: "agenda_cat_vehicles")
        }
    }

    private func modeLabel(_ m: CalendarMode) -> String {
        switch m {
        case .month:  return String(localized: "cal_mode_month")
        case .week:   return String(localized: "cal_mode_week")
        case .day:    return String(localized: "cal_mode_day")
        case .agenda: return String(localized: "cal_mode_agenda")
        }
    }

    private var periodTitle: String {
        switch mode {
        case .month:
            return AppDateDisplay.fullMonthYear.string(from: anchor).capitalized
        case .week:
            let days = weekDays(of: anchor)
            let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("d MMM")
            let a = days.first.map { f.string(from: $0) } ?? ""
            let b = days.last.map { f.string(from: $0) } ?? ""
            return "\(a) – \(b)"
        case .day:
            let f = DateFormatter(); f.locale = .current; f.setLocalizedDateFormatFromTemplate("MMMM yyyy")
            return f.string(from: anchor).capitalized
        case .agenda:
            return String(localized: "cal_mode_agenda")
        }
    }

    /// The live task behind a `.task` agenda item (matched by id), so its row can
    /// be checked off. nil for every other category.
    private func taskForItem(_ item: AgendaItem) -> MaintenanceTask? {
        guard item.category == .task else { return nil }
        return taskService.tasks.first { $0.id.uuidString == item.sourceId }
    }

    /// The live event behind an `.event` agenda item (matched by id), so tapping
    /// the row can open its editor. nil for every other category.
    private func eventForItem(_ item: AgendaItem) -> CalendarEvent? {
        guard item.category == .event else { return nil }
        return calendarEventService.events.first { $0.id.uuidString == item.sourceId }
    }

    /// One agenda row wired to the calendar's behaviours: tasks check off, events
    /// open their editor, everything else follows its own deep link. Shared by the
    /// day detail and the forward Agenda so both behave identically.
    @ViewBuilder
    private func agendaRow(for item: AgendaItem) -> some View {
        let task = taskForItem(item)
        HouseAgendaRow(
            item: item,
            task: task,
            onToggle: task.map { t in { Task { await taskService.toggleComplete(t) } } },
            onTap: eventForItem(item).map { event in { editingEvent = event } })
    }

    private func daysInMonth() -> [Date?] {
        guard let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: anchor)),
              let range = cal.range(of: .day, in: .month, for: monthStart) else { return [] }
        var weekday = cal.component(.weekday, from: monthStart) - 2
        if weekday < 0 { weekday += 7 }
        var days: [Date?] = Array(repeating: nil, count: weekday)
        for d in range { days.append(cal.date(byAdding: .day, value: d - 1, to: monthStart)) }
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    /// Up to three category dots for a day (distinct categories present in view),
    /// read off a pre-computed month/week grouping so cells don't each re-derive.
    private func dots(for date: Date, byDay: [String: [AgendaItem]]) -> [Color] {
        let items = byDay[AppDate.dayString(from: date)] ?? []
        var seen = Set<AgendaCategory>(); var colors: [Color] = []
        for it in items where !seen.contains(it.category) { seen.insert(it.category); colors.append(it.category.color) }
        return colors
    }
}

// MARK: - Day Cell (Month grid)

private struct DayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let dots: [Color]
    let action: () -> Void

    private var day: Int { Calendar.current.component(.day, from: date) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white : isToday ? Color.primary.opacity(0.15) : Color.clear)
                        .frame(width: 32, height: 32)
                    Text("\(day)")
                        .font(AppFont.scaled(14, weight: isToday || isSelected ? .bold : .regular))
                        .foregroundStyle(isSelected ? Color.black : Color.primary.opacity(isToday ? 1 : 0.7))
                }
                HStack(spacing: 3) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, c in
                        Circle().fill(c).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 6)
            }
            .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}
