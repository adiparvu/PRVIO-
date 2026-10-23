import SwiftUI

// MARK: - PRVIO Timeline — matches dark mockup (chronological events + aggregated toolbar filter)

struct PRVIOTimelineView: View {
    @Environment(TaskService.self) var taskService
    @Environment(PropertyElementService.self) var elementService

    enum TimeFilter: String, CaseIterable {
        case today  = "Today"
        case fiveMin = "5m"
        case thirtyMin = "30m"
        case day = "24h"

        var interval: TimeInterval? {
            switch self {
            case .today:    return nil
            case .fiveMin:  return 5 * 60
            case .thirtyMin: return 30 * 60
            case .day:      return 24 * 3600
            }
        }

        /// Same catalog keys the chips resolved (`LocalizedStringKey(rawValue)`),
        /// as plain strings for `GlassPickerOption.title`.
        var title: String {
            switch self {
            case .today:     return String(localized: "Today")
            case .fiveMin:   return String(localized: "5m")
            case .thirtyMin: return String(localized: "30m")
            case .day:       return String(localized: "24h")
            }
        }
    }

    @State private var filter: TimeFilter = .today
    @State private var searchText = ""

    private var filteredEvents: [TimelineEvent] {
        let all = buildEvents()
        let timed: [TimelineEvent]
        if let interval = filter.interval {
            let cutoff = Date().addingTimeInterval(-interval)
            timed = all.filter { $0.date >= cutoff }
        } else {
            // "Today" → events from today only
            timed = all.filter { Calendar.current.isDateInToday($0.date) || $0.date > Date() }
        }
        guard !searchText.isEmpty else { return timed }
        return timed.filter {
            $0.title.matchesSearch(searchText)
                || $0.subtitle.matchesSearch(searchText)
                || $0.timeLabel.matchesSearch(searchText)
        }
    }

    private var groupedEvents: [(String, [TimelineEvent])] {
        let grouped = Dictionary(grouping: filteredEvents) { $0.groupKey }
        let sorted = grouped.sorted { a, b in
            guard let d1 = a.value.first?.date, let d2 = b.value.first?.date else { return false }
            return d1 > d2
        }
        return sorted.map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if groupedEvents.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    ForEach(groupedEvents, id: \.0) { group, events in
                        sectionHeader(LocalizedStringKey(group))
                            .padding(.horizontal, AppSpacing.lg)
                            .padding(.top, 18)
                            .padding(.bottom, AppSpacing.sm)

                        ForEach(Array(events.enumerated()), id: \.element.id) { idx, event in
                            HStack(alignment: .top, spacing: 0) {
                                // Timeline spine
                                VStack(spacing: 0) {
                                    Circle()
                                        .fill(event.color)
                                        .frame(width: 10, height: 10)
                                        .padding(.top, 5)
                                    if idx < events.count - 1 {
                                        Rectangle()
                                            .fill(Color.primary.opacity(0.1))
                                            .frame(width: 1.5)
                                            .frame(maxHeight: .infinity)
                                    }
                                }
                                .frame(width: 30)
                                .padding(.leading, AppSpacing.lg)

                                // Event card
                                TimelineEventCard(event: event)
                                    .padding(.horizontal, 10)
                                    .padding(.bottom, AppSpacing.sm)
                            }
                        }
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("\(filteredEvents.count)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.secondary)
            }
            // The one aggregated filter — replaces the chip row that
            // sat above the list. `inToolbar` because iOS 26 wraps
            // toolbar controls in system glass (IMG_8315 class).
            ToolbarItem(placement: .pageMenu) {
                GlassFilterButton(isActive: filter != .today, inToolbar: true) {
                    GlassFilterSection(options: timeFilterOptions, selection: $filter)
                }
            }
        }
    }

    // MARK: - Filter options

    /// The exact time ranges the chip row drove, for the aggregated popover.
    private var timeFilterOptions: [GlassPickerOption<TimeFilter>] {
        TimeFilter.allCases.map { GlassPickerOption(value: $0, title: $0.title) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(AppFont.scaled(42, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.2))
            Text("No events")
                .font(AppFont.headline)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            Text("No activity in this time range")
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(0.3))
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionHeader(_ label: LocalizedStringKey) -> some View {
        Text(label)
            .font(AppFont.label)
            .foregroundStyle(Color.backdropSecondaryText)
    }

    private func buildEvents() -> [TimelineEvent] {
        var events: [TimelineEvent] = []

        // Completed tasks → timeline events
        let completed = taskService.tasks.filter { $0.isCompleted }
        for task in completed.prefix(20) {
            let date = parseDate(task.updatedAt) ?? Date()
            events.append(.init(
                id: task.id,
                icon: "checkmark.circle.fill",
                color: Color.brandSuccess,
                title: task.title,
                subtitle: task.category.capitalized,
                date: date
            ))
        }

        // Active tasks with due dates
        let active = taskService.tasks.filter { !$0.isCompleted && $0.dueDate != nil }
        for task in active.prefix(10) {
            let date = parseDate(task.dueDate ?? task.createdAt) ?? Date()
            let isOverdue = date < Date()
            events.append(.init(
                id: task.id,
                icon: isOverdue ? "exclamationmark.circle.fill" : "clock.fill",
                color: isOverdue ? .red : .orange,
                title: task.title,
                subtitle: isOverdue ? String(localized: "Overdue") : String(format: String(localized: "Due %@"), relativeDate(date)),
                date: date
            ))
        }

        // Elements — recent additions
        for element in elementService.elements.prefix(8) {
            let date = parseDate(element.createdAt) ?? Date()
            events.append(.init(
                id: element.id,
                icon: element.elementType.icon,
                color: element.layer.color,
                title: String(format: String(localized: "%@ added"), element.name),
                subtitle: element.elementType.displayName,
                date: date
            ))
        }

        return events.sorted { $0.date > $1.date }
    }

    private func parseDate(_ str: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: str) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: str)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return String(localized: "today") }
        if cal.isDateInTomorrow(date)  { return String(localized: "tomorrow") }
        if cal.isDateInYesterday(date) { return String(localized: "yesterday") }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }
}

// MARK: - TimelineEvent model

struct TimelineEvent: Identifiable {
    let id: UUID
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let date: Date

    var groupKey: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return String(localized: "Today") }
        if cal.isDateInYesterday(date) { return String(localized: "Yesterday") }
        let df = DateFormatter()
        df.dateStyle = .medium
        return df.string(from: date)
    }

    /// Shared formatter — timeLabel now also runs inside the search filter
    /// (once per event per keystroke), so it must not allocate per call.
    private static let shortTimeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.timeStyle = .short
        return df
    }()

    var timeLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) || cal.isDateInYesterday(date) {
            return Self.shortTimeFormatter.string(from: date)
        }
        return ""
    }
}

// MARK: - Timeline Event Card

struct TimelineEventCard: View {
    let event: TimelineEvent

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(event.color.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: event.icon)
                    .font(AppFont.subheadline)
                    .foregroundStyle(event.color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(LocalizedStringKey(event.subtitle))
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }

            Spacer()

            if !event.timeLabel.isEmpty {
                Text(event.timeLabel)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.primary.opacity(0.3))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .background {
            RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
    }
}
