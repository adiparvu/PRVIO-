import SwiftUI
import PhotosUI
import Supabase

// MARK: - PhotoJournalView
//
// The house's visual diary: photos grouped by month, the newest photo as a
// featured tile, honest filters (tags by frequency + contributors when
// more than one person has added photos) aggregated in the page's single
// toolbar filter circle, an "Acum un an" anniversary strip
// (only when such photos exist), long-press PreviewCard previews, and a
// full-screen viewer that swipes between the photos of the tapped group.
//
// NOTE (motion honesty): a Photos-style zoom hero transition was added in
// build 728 and deliberately REMOVED in build 853 — the iOS 18 zoom portal
// left a lingering artifact and broke the source page's large-title state.
// Do not reintroduce it; the standard sheet presentation is the fix.

struct PhotoJournalView: View {
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(FamilyService.self) private var familyService

    @State private var showAdd = false
    @State private var viewerContext: JournalViewerContext? = nil
    @State private var activeTag: String? = nil
    @State private var activeOwner: UUID? = nil
    @State private var searchText = ""
    @State private var pendingDelete: PhotoJournalEntry? = nil

    private let columns = [GridItem(.adaptive(minimum: 110, maximum: 220), spacing: 2)]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if photoJournalService.isLoading && photoJournalService.entries.isEmpty {
                loadingState
            } else if photoJournalService.entries.isEmpty {
                emptyState
            } else {
                journalContent
            }
        }
        .navigationTitle("Photo Journal")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            if !topTags.isEmpty || !contributors.isEmpty {
                ToolbarItem(placement: .pageMenu) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAdd = true
                    HapticFeedback.impact(.light)
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("Add photo")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPhotoJournalSheet()
                .environment(photoJournalService)
                .environment(propertyService)
                .environment(zoneService)
        }
        .sheet(item: $viewerContext) { context in
            PhotoEntryDetailSheet(context: context)
                .environment(photoJournalService)
                .environment(zoneService)
                .environment(familyService)
        }
        .confirmationDialog("Delete this photo?",
                            isPresented: .init(get: { pendingDelete != nil },
                                               set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible,
                            presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) {
                Task { await photoJournalService.delete(entry) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This action cannot be undone.")
        }
        .task {
            if let id = propertyService.primary?.id {
                if zoneService.zones.isEmpty {
                    await zoneService.load(propertyId: id)
                }
                await photoJournalService.load(propertyId: id)
            }
            if familyService.members.isEmpty {
                await familyService.load()
            }
        }
    }

    // MARK: - Filtering & grouping

    private var currentUserId: UUID? { supabase.auth.currentSession?.user.id }

    /// Tags ordered by how often they are used (display casing = first seen).
    private var topTags: [(tag: String, count: Int)] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for entry in photoJournalService.entries {
            for tag in entry.tags ?? [] {
                let key = tag.lowercased()
                counts[key, default: 0] += 1
                if display[key] == nil { display[key] = tag }
            }
        }
        return counts
            .sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) }
            .prefix(8)
            .compactMap { key, count in display[key].map { (tag: $0, count: count) } }
    }

    /// Distinct contributors, most photos first — shown only when at least
    /// two people with resolvable names have added photos (no dead chips).
    private var contributors: [(ownerId: UUID, name: String, count: Int)] {
        var counts: [UUID: Int] = [:]
        for entry in photoJournalService.entries {
            counts[entry.ownerId, default: 0] += 1
        }
        let resolved: [(ownerId: UUID, name: String, count: Int)] = counts.compactMap { ownerId, count in
            guard let name = JournalDirectory.contributorName(
                for: ownerId, members: familyService.members, currentUserId: currentUserId
            ) else { return nil }
            return (ownerId: ownerId, name: name, count: count)
        }
        guard resolved.count >= 2 else { return [] }
        return resolved.sorted { $0.count > $1.count }
    }

    private var hasActiveFilters: Bool { activeTag != nil || activeOwner != nil }

    private func matchesFilters(_ entry: PhotoJournalEntry) -> Bool {
        if let tag = activeTag,
           !(entry.tags ?? []).contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            return false
        }
        if let owner = activeOwner, entry.ownerId != owner {
            return false
        }
        // Diacritic-insensitive search across title, caption and tags
        // (String.matchesSearch — Components/PageSearch.swift).
        return entry.title.matchesSearch(searchText)
            || (entry.caption ?? "").matchesSearch(searchText)
            || (entry.tags ?? []).contains { $0.matchesSearch(searchText) }
    }

    private var filteredEntries: [PhotoJournalEntry] {
        photoJournalService.entries.filter(matchesFilters)
    }

    /// Photos taken in this calendar month of an earlier year — the honest
    /// "Acum un an" memory strip. Empty array = the row never renders.
    private var anniversaryEntries: [PhotoJournalEntry] {
        let calendar = Calendar.current
        let now = calendar.dateComponents([.year, .month], from: Date())
        guard let thisYear = now.year, let thisMonth = now.month else { return [] }
        return photoJournalService.entries.filter { entry in
            guard let date = entry.takenDate else { return false }
            let c = calendar.dateComponents([.year, .month], from: date)
            return c.month == thisMonth && (c.year ?? thisYear) < thisYear
        }
    }

    private struct MonthGroup: Identifiable {
        let id: String
        let title: String
        let entries: [PhotoJournalEntry]
    }

    private var monthGroups: [MonthGroup] {
        let calendar = Calendar.current
        var groups: [(key: Date, entries: [PhotoJournalEntry])] = []
        for entry in filteredEntries {
            let date = entry.takenDate ?? .distantPast
            let month = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
            if let idx = groups.firstIndex(where: { $0.key == month }) {
                groups[idx].entries.append(entry)
            } else {
                groups.append((month, [entry]))
            }
        }
        return groups
            .sorted { $0.key > $1.key }
            .map { group in
                MonthGroup(
                    id: String(group.key.timeIntervalSinceReferenceDate),
                    title: Self.monthFormatter.string(from: group.key).capitalized,
                    entries: group.entries
                )
            }
    }

    /// The featured tile shows only in the browse state (no search/filters),
    /// as the first entry of the newest month — never duplicated in the grid.
    private var showsFeaturedTile: Bool {
        searchText.isEmpty && !hasActiveFilters
    }

    // MARK: - Content

    private var journalContent: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg, pinnedViews: []) {
                if showsFeaturedTile && !anniversaryEntries.isEmpty {
                    anniversarySection
                }
                if filteredEntries.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                }
                ForEach(Array(monthGroups.enumerated()), id: \.element.id) { index, group in
                    monthSection(group, isNewest: index == 0)
                }
                Spacer(minLength: 110)
            }
            .padding(.top, AppSpacing.xs)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await photoJournalService.load(propertyId: id)
            }
        }
    }

    private func monthSection(_ group: MonthGroup, isNewest: Bool) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(verbatim: group.title)
                    .font(AppFont.headline)
                    .foregroundStyle(.primary)
                Text(verbatim: "\(group.entries.count)")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .padding(.horizontal, AppSpacing.lg)
            .accessibilityElement(children: .combine)

            let featured = (isNewest && showsFeaturedTile) ? group.entries.first : nil
            if let featured {
                featuredTile(featured, monthEntries: group.entries)
            }

            let gridEntries = featured == nil ? group.entries : Array(group.entries.dropFirst())
            if !gridEntries.isEmpty {
                LazyVGrid(columns: columns, spacing: 2) {
                    ForEach(gridEntries) { entry in
                        gridCell(entry, monthEntries: group.entries)
                    }
                }
            }
        }
    }

    private func gridCell(_ entry: PhotoJournalEntry, monthEntries: [PhotoJournalEntry]) -> some View {
        PhotoGridCell(entry: entry)
            .onTapGesture {
                openViewer(entry, in: monthEntries)
            }
            .contextMenu {
                entryMenu(entry, monthEntries: monthEntries)
            } preview: {
                JournalPreviewCard(
                    entry: entry,
                    zoneName: zoneName(for: entry),
                    contributorName: JournalDirectory.contributorName(
                        for: entry.ownerId,
                        members: familyService.members,
                        currentUserId: currentUserId
                    )
                )
            }
            .accessibilityLabel(cellAccessibilityLabel(entry))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func entryMenu(_ entry: PhotoJournalEntry, monthEntries: [PhotoJournalEntry]) -> some View {
        Button {
            openViewer(entry, in: monthEntries)
        } label: {
            Label("View", systemImage: "eye")
        }
        if let url = URL(string: entry.photoUrl) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        Divider()
        Button(role: .destructive) {
            pendingDelete = entry
            HapticFeedback.warning()
        } label: {
            Label("Delete Photo", systemImage: "trash")
        }
    }

    private func openViewer(_ entry: PhotoJournalEntry, in entries: [PhotoJournalEntry]) {
        viewerContext = JournalViewerContext(entries: entries, initial: entry)
        HapticFeedback.impact(.light)
    }

    private func zoneName(for entry: PhotoJournalEntry) -> String? {
        guard let zoneId = entry.zoneId else { return nil }
        return zoneService.zones.first { $0.id == zoneId }?.name
    }

    private func cellAccessibilityLabel(_ entry: PhotoJournalEntry) -> Text {
        if let date = entry.takenDate {
            return Text(verbatim: "\(entry.title), \(Self.dayFormatter.string(from: date))")
        }
        return Text(verbatim: entry.title)
    }

    // MARK: - Featured tile (most recent photo, browse state only)

    private func featuredTile(_ entry: PhotoJournalEntry, monthEntries: [PhotoJournalEntry]) -> some View {
        Button {
            openViewer(entry, in: monthEntries)
        } label: {
            Color.clear
                .aspectRatio(16 / 10, contentMode: .fit)
                .overlay(
                    StorageImage(source: entry.photoUrl, targetSize: 640) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(Image(systemName: "photo")
                                    .foregroundStyle(Color.primary.opacity(0.3)))
                        default:
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .overlay(ProgressView().controlSize(.small).tint(.primary.opacity(0.4)))
                        }
                    }
                )
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("journal_latest_kicker")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(verbatim: entry.title)
                            .font(AppFont.scaled(19, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        if let date = entry.takenDate {
                            Text(verbatim: Self.dayFormatter.string(from: date))
                                .font(AppFont.scaled(13))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                    }
                    .padding(AppSpacing.lg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        LinearGradient(colors: [.clear, .black.opacity(0.55)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                }
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            entryMenu(entry, monthEntries: monthEntries)
        } preview: {
            JournalPreviewCard(
                entry: entry,
                zoneName: zoneName(for: entry),
                contributorName: JournalDirectory.contributorName(
                    for: entry.ownerId,
                    members: familyService.members,
                    currentUserId: currentUserId
                )
            )
        }
        .accessibilityLabel(cellAccessibilityLabel(entry))
    }

    // MARK: - Filter circle (tags by frequency + contributors)

    /// One circle, every filter (the one-circle law): the tag and
    /// contributor chips that used to sit as a permanent row above the grid,
    /// aggregated into the page's single filter popover. Each section keeps
    /// its nil "All" row, so tag + contributor + search combine freely, and
    /// the accent dot lights only when the grid is genuinely narrowed.
    private var filterButton: some View {
        GlassFilterButton(isActive: hasActiveFilters, inToolbar: true) {
            if !topTags.isEmpty {
                GlassFilterSection(
                    title: "journal_tags_label",
                    options: [GlassPickerOption<String?>(value: nil,
                                                         title: String(localized: "All"))]
                        + topTags.map {
                            GlassPickerOption<String?>(value: $0.tag,
                                                       title: "#\($0.tag)",
                                                       count: $0.count)
                        },
                    selection: $activeTag)
            }
            if !contributors.isEmpty {
                if !topTags.isEmpty {
                    GlassFilterSectionDivider()
                }
                GlassFilterSection(
                    title: "People",
                    options: [GlassPickerOption<UUID?>(value: nil,
                                                       title: String(localized: "All"))]
                        + contributors.map {
                            GlassPickerOption<UUID?>(value: $0.ownerId,
                                                     icon: "person.fill",
                                                     title: $0.name,
                                                     count: $0.count)
                        },
                    selection: $activeOwner)
            }
        }
    }

    // MARK: - "Acum un an" (same month, earlier years)

    private var anniversarySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("journal_one_year_ago")
                .font(AppFont.headline)
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(anniversaryEntries) { entry in
                        anniversaryTile(entry)
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
    }

    private func anniversaryTile(_ entry: PhotoJournalEntry) -> some View {
        Button {
            openViewer(entry, in: anniversaryEntries)
        } label: {
            ZStack(alignment: .topLeading) {
                Color.clear
                    .frame(width: 130, height: 170)
                    .overlay(
                        StorageImage(source: entry.photoUrl, targetSize: 170) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                Rectangle().fill(Color.primary.opacity(0.08))
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))

                if let year = entry.takenDate.map({ Calendar.current.component(.year, from: $0) }) {
                    Text(verbatim: String(year))
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.45), in: Capsule())
                        .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cellAccessibilityLabel(entry))
    }

    // MARK: - States

    private var emptyState: some View {
        VStack {
            Spacer()
            EmptyStateView(
                icon: "photo.on.rectangle.angled",
                title: "Start your renovation diary",
                message: "Capture before and after photos, track progress, and document every improvement to your home.",
                actionLabel: "Add first photo",
                action: { showAdd = true }
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView().tint(.primary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Contributor resolution
//
// Names come only from real data: the signed-in user ("journal_me") or a
// roster member whose linked account id matches the entry's owner. Anything
// unresolvable returns nil and simply doesn't render — never a placeholder.

enum JournalDirectory {
    static func contributorName(for ownerId: UUID,
                                members: [FamilyMember],
                                currentUserId: UUID?) -> String? {
        if ownerId == currentUserId {
            return String(localized: "journal_me")
        }
        let name = members.first { $0.userId == ownerId }?.name
            .trimmingCharacters(in: .whitespaces)
        return (name?.isEmpty == false) ? name : nil
    }
}

// MARK: - PhotoGridCell

private struct PhotoGridCell: View {
    let entry: PhotoJournalEntry

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay(
                StorageImage(source: entry.photoUrl, targetSize: 160) { phase in
                    switch phase {
                    case .empty:
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(ProgressView().controlSize(.small).tint(.primary.opacity(0.4)))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .overlay(
                                Image(systemName: "photo")
                                    .foregroundStyle(Color.primary.opacity(0.3))
                            )
                    @unknown default:
                        Rectangle().fill(Color.primary.opacity(0.05))
                    }
                }
            )
            .clipped()
            .contentShape(Rectangle())
    }
}

// MARK: - Long-press preview (PreviewCard — real fields only)

private struct JournalPreviewCard: View {
    let entry: PhotoJournalEntry
    let zoneName: String?
    let contributorName: String?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        PreviewCard(
            title: Text(verbatim: entry.title),
            subtitle: entry.caption.flatMap { $0.isEmpty ? nil : Text(verbatim: $0) },
            details: details
        ) {
            thumbnail
        }
    }

    private var details: [PreviewCardDetail] {
        var rows: [PreviewCardDetail] = []
        if let date = entry.takenDate {
            rows.append(PreviewCardDetail(
                icon: "calendar",
                label: Text("Taken on"),
                value: Text(verbatim: Self.dateFormatter.string(from: date))
            ))
        }
        if let zoneName {
            rows.append(PreviewCardDetail(
                icon: "mappin.and.ellipse",
                label: Text("journal_space_section"),
                value: Text(verbatim: zoneName)
            ))
        }
        if let tags = entry.tags, !tags.isEmpty {
            rows.append(PreviewCardDetail(
                icon: "number",
                label: Text("journal_tags_label"),
                value: Text(verbatim: tags.map { "#\($0)" }.joined(separator: " "))
            ))
        }
        if let contributorName {
            rows.append(PreviewCardDetail(
                icon: "person.fill",
                value: Text("journal_added_by \(contributorName)")
            ))
        }
        return rows
    }

    private var thumbnail: some View {
        StorageImage(source: entry.photoUrl, targetSize: 56) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(Color.primary.opacity(0.08))
                    .overlay(Image(systemName: "photo")
                        .foregroundStyle(Color.primary.opacity(0.3)))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
    }
}

// MARK: - Viewer context + PhotoEntryDetailSheet (swipeable pager)

struct JournalViewerContext: Identifiable {
    let id = UUID()
    let entries: [PhotoJournalEntry]
    let initial: PhotoJournalEntry
}

private struct PhotoEntryDetailSheet: View {
    let context: JournalViewerContext
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(FamilyService.self) private var familyService
    @Environment(\.dismiss) private var dismiss

    @State private var selection: UUID
    @State private var showDeleteConfirm = false

    init(context: JournalViewerContext) {
        self.context = context
        _selection = State(initialValue: context.initial.id)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    private var currentEntry: PhotoJournalEntry {
        context.entries.first { $0.id == selection } ?? context.initial
    }

    private var positionText: String? {
        guard context.entries.count > 1,
              let index = context.entries.firstIndex(where: { $0.id == selection })
        else { return nil }
        return String(format: String(localized: "journal_position %lld %lld"),
                      index + 1, context.entries.count)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                TabView(selection: $selection) {
                    ForEach(context.entries) { entry in
                        entryPage(entry)
                            .tag(entry.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.white)
                }
                if let positionText {
                    ToolbarItem(placement: .principal) {
                        Text(verbatim: positionText)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.white.opacity(0.7))
                            .monospacedDigit()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let url = URL(string: currentEntry.photoUrl) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Share")
                    }
                }
            }
            .confirmationDialog("Delete this photo?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        await photoJournalService.delete(currentEntry)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }

    private func entryPage(_ entry: PhotoJournalEntry) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                StorageImage(source: entry.photoUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                    case .empty:
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 300)
                            .overlay(ProgressView().tint(.white))
                    default:
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 300)
                    }
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: entry.title)
                        .font(AppFont.scaled(22, weight: .bold))
                        .foregroundStyle(.white)

                    if let date = entry.takenDate {
                        Label {
                            Text(verbatim: Self.dateFormatter.string(from: date))
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.white.opacity(0.6))
                    }

                    if let zoneName = entry.zoneId.flatMap({ id in
                        zoneService.zones.first { $0.id == id }?.name
                    }) {
                        Label {
                            Text(verbatim: zoneName)
                        } icon: {
                            Image(systemName: "mappin.and.ellipse")
                        }
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.white.opacity(0.6))
                    }

                    if let contributor = JournalDirectory.contributorName(
                        for: entry.ownerId,
                        members: familyService.members,
                        currentUserId: supabase.auth.currentSession?.user.id
                    ) {
                        Label {
                            Text("journal_added_by \(contributor)")
                        } icon: {
                            Image(systemName: "person.fill")
                        }
                        .font(AppFont.scaled(13))
                        .foregroundStyle(.white.opacity(0.6))
                    }

                    if let caption = entry.caption, !caption.isEmpty {
                        Text(verbatim: caption)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.white.opacity(0.8))
                    }

                    if let entryTags = entry.tags, !entryTags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(entryTags, id: \.self) { tag in
                                    Text(verbatim: "#\(tag)")
                                        .font(AppFont.caption)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(.white.opacity(0.12), in: Capsule())
                                }
                            }
                        }
                    }

                    Button {
                        showDeleteConfirm = true
                        HapticFeedback.warning()
                    } label: {
                        Label("Delete Photo", systemImage: "trash")
                            .font(AppFont.body)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.base)
                            .background(Color.red.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, AppSpacing.sm)
                }
                .padding(AppSpacing.xl)

                Spacer(minLength: 40)
            }
        }
    }
}
