import SwiftUI

// MARK: - "Year of Your Home" — the pride moment
//
// The household's own "wrapped": every number on this page is synthesized
// from this property's real rows (tasks, receipts, photos, documents,
// plants, evaluations, rent) — see YearStoryBuilder. Chapters whose data
// doesn't exist simply never render; the page is different in every home
// and gets richer the more the app is lived in.
//
// Structure: hero → headline stats (with honest vs-last-year deltas) →
// „Vezi povestea" (full-screen wrapped mode) → the 12-month activity
// strip → the story chapters. The year selector and the share action
// (two rendered cards, numbers + highlights) live in the toolbar's one
// filter circle.

struct YearInReviewView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(TaskService.self) private var taskService
    @Environment(FinancialService.self) private var financialService
    @Environment(PhotoJournalService.self) private var photoJournalService
    @Environment(DocumentService.self) private var documentService
    @Environment(PlantService.self) private var plantService
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyValueService.self) private var propertyValueService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var wateringsByYear: [Int: Int] = [:]
    @State private var shareURLs: [URL] = []
    @State private var showWrapped = false

    // Stretchy-hero chrome — the property page's edge-to-edge presentation
    // (user-decreed, IMG_8599): same StretchyHeroHeader, same hidden system
    // bar + materializing compact bar.
    /// 0…1 — how far the compact inline bar has materialized.
    @State private var heroBarProgress: CGFloat = 0
    /// Measured status-bar + navigation-bar height; the compact bar's frame.
    @State private var heroTopInset: CGFloat = 0

    private static let heroScrollSpace = "yearHeroScroll"
    private static let heroHeight: CGFloat = 280
    private static let compactBarStripHeight: CGFloat = 44
    /// The year identity lives INSIDE the hero, so the bar materializes the
    /// moment the hero's bottom edge slides under the bar (gap 0).
    private static let heroBarFadeDistance: CGFloat = 28

    // MARK: Synthesis (all from this home's data)

    private var builder: YearStoryBuilder {
        YearStoryBuilder(
            tasks: taskService.tasks,
            records: financialService.records,
            photos: photoJournalService.entries,
            documents: documentService.documents,
            plants: plantService.plants,
            valueEntries: propertyValueService.entries,
            members: familyService.members,
            wateringsByYear: wateringsByYear,
            currentStreak: SharedDataStore.currentHouseStreak()
        )
    }

    /// Fingerprint of everything the share cards draw — re-renders them only
    /// when a number actually changed (year switch, realtime update).
    private func shareFingerprint(_ story: YearStory) -> String {
        // Double interpolation, not `Int(...)`: the conversion traps on a
        // pathological expense total, and this runs at page entry.
        "\(story.year)-\(story.tasksDoneCount)-\(story.photosCount)-\(story.documentsCount)-"
            + "\(story.expenseTotal.rounded())-\(story.workedSeconds)-\(story.waterings)-"
            + "\(story.rentPaymentsCount)-\(propertyService.primary?.name ?? "")"
    }

    var body: some View {
        let story = builder.build(year: selectedYear)
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                heroHeader
                VStack(spacing: 20) {
                    statGrid(story)
                    if story.hasAnyData {
                        wrappedButton
                    }
                    if story.months.contains(where: { $0.total > 0 }) {
                        YearActivityStrip(
                            months: story.months,
                            monthSymbols: monthSymbols,
                            moneyDisplay: { moneyDisplay($0, code: story.expenseCurrency) }
                        )
                    }
                    storySection(story)
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        .coordinateSpace(name: Self.heroScrollSpace)
        .background(appBackground.ignoresSafeArea())
        // Edge-to-edge hero, exactly the property page's chrome: content
        // starts at the very top of the screen, the system bar draws no
        // background, and a compact bar materializes at the threshold.
        .ignoresSafeArea(edges: .top)
        // LOOP GUARD (same as PropertyDetailView): the inset is measured
        // mid-layout; absorb sub-point jitter and land writes in their own
        // main-queue turn so a geometry↔state oscillation can't livelock.
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.safeAreaInsets.top
        } action: { inset in
            guard abs(inset - heroTopInset) > 0.5 else { return }
            Task { @MainActor in
                if abs(inset - heroTopInset) > 0.5 { heroTopInset = inset }
            }
        }
        .overlay(alignment: .top) { compactBar }
        .onPreferenceChange(StretchyHeroBottomEdgeKey.self) { bottom in
            updateHeroBarProgress(heroBottom: bottom)
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .pageMenu) { optionsButton }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: selectedYear)
        .fullScreenCover(isPresented: $showWrapped) {
            YearWrappedView(
                year: story.year,
                propertyName: propertyService.primary?.name ?? "PRVIO",
                pages: wrappedPages(story)
            )
        }
        .task { await loadEverything() }
        .task(id: shareFingerprint(story)) { renderShareCards(story) }
    }

    // MARK: Data (load whatever hasn't been loaded elsewhere yet)

    private func loadEverything() async {
        guard let pid = propertyService.primary?.id else { return }
        await withTaskGroup(of: Void.self) { group in
            if taskService.tasks.isEmpty { group.addTask { @MainActor in await taskService.load() } }
            if financialService.records.isEmpty { group.addTask { @MainActor in await financialService.load() } }
            if photoJournalService.entries.isEmpty { group.addTask { @MainActor in await photoJournalService.load(propertyId: pid) } }
            if documentService.documents.isEmpty { group.addTask { @MainActor in await documentService.load() } }
            if plantService.plants.isEmpty { group.addTask { @MainActor in await plantService.load(propertyId: pid) } }
            if familyService.members.isEmpty { group.addTask { @MainActor in await familyService.load() } }
            if propertyValueService.entries.isEmpty { group.addTask { @MainActor in await propertyValueService.load(propertyId: pid) } }
            group.addTask { @MainActor in
                wateringsByYear = await YearPlantCare.wateringCounts(propertyId: pid)
            }
        }
    }

    // MARK: Options (one circle: year + share)

    /// ONE circle for the whole page (one-circle law): the year selector
    /// that used to sit as its own glass capsule menu — only years that
    /// actually hold data — plus the share action that used to be a
    /// page-body ShareLink capsule. The year is the page's period, not a
    /// narrowing filter, so the trigger never claims the accent dot.
    private var optionsButton: some View {
        GlassFilterButton(inToolbar: true,
                          accessibilityLabelKey: "year_pick_year") {
            GlassFilterSection(
                title: "year_pick_year",
                options: builder.availableYears.map {
                    GlassPickerOption(value: $0, title: String($0))
                },
                selection: $selectedYear)
            if !shareURLs.isEmpty {
                GlassFilterSectionDivider()
                GlassFilterActionRow(icon: "square.and.arrow.up",
                                     title: String(localized: "Share your year")) {
                    SystemActions.share(shareURLs)
                }
            }
        }
    }

    // MARK: - Hero

    private var heroHeader: some View {
        StretchyHeroHeader(height: Self.heroHeight,
                           scrollSpace: Self.heroScrollSpace) {
            heroMedia
        } overlay: {
            heroOverlay
        }
    }

    /// The stretchable photo layer — sized, clipped, stretched, receded and
    /// dimmed by the hero; keep it free of text.
    private var heroMedia: some View {
        Group {
            if let ui = UIImage(named: "aerial_property") {
                Image(uiImage: ui).resizable().scaledToFill()
            } else {
                LinearGradient(colors: [Color.brandPurple, Color.brandPrimaryBlue],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .overlay(alignment: .top) {
            // Status-bar/toolbar legibility over bright skies — pinned to the
            // photo's visual top, exactly the property page's crown.
            LinearGradient(colors: [.black.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
                .allowsHitTesting(false)
        }
    }

    /// The year identity, pinned to the hero's resting bounds — never
    /// stretched, receded, or dimmed.
    private var heroOverlay: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: String(selectedYear))
                    .font(AppFont.scaled(34, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                Text(propertyService.primary?.name ?? "")
                    .font(AppFont.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.base)
        }
    }

    // MARK: Compact inline bar (the property page's TestFlight transition)

    private var compactBar: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.bar)
            Text("Year of Your Home")
                .font(AppFont.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                // Clearance for the floating back/options buttons on top.
                .padding(.horizontal, 72)
                .frame(height: Self.compactBarStripHeight)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hairline).frame(height: 0.5)
        }
        .frame(height: heroTopInset)
        .frame(maxWidth: .infinity)
        .ignoresSafeArea(edges: .top)
        .opacity(heroBarProgress)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Same transaction-break discipline as PropertyDetailView: preference
    /// handlers never write state back into the pass that produced it.
    private func updateHeroBarProgress(heroBottom: CGFloat) {
        guard heroTopInset > 0 else {
            if heroBarProgress != 0 {
                Task { @MainActor in
                    if heroBarProgress != 0 { heroBarProgress = 0 }
                }
            }
            return
        }
        let raw = (heroTopInset - heroBottom) / Self.heroBarFadeDistance
        let clamped = min(max(raw, 0), 1)
        let next = reduceMotion
            ? (clamped < 0.5 ? 0 : 1)
            : (clamped * 50).rounded() / 50
        guard next != heroBarProgress else { return }
        Task { @MainActor in
            if heroBarProgress != next { heroBarProgress = next }
        }
    }

    // MARK: - Numbers

    private func statGrid(_ story: YearStory) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
            yearStat(value: "\(story.photosCount)", label: "Photos captured",
                     icon: "photo.stack.fill", color: .orange,
                     deltaPct: story.photosDeltaPct)
            yearStat(value: "\(story.tasksDoneCount)", label: "Tasks completed",
                     icon: "checkmark.seal.fill", color: Color.brandSuccess,
                     deltaPct: story.tasksDeltaPct)
            yearStat(value: "\(story.documentsCount)", label: "Documents filed",
                     icon: "doc.text.fill", color: Color.brandSkyBlue,
                     deltaPct: nil)
            yearStat(value: moneyDisplay(story.expenseTotal, code: story.expenseCurrency),
                     label: "Spent on the home",
                     icon: "banknote.fill", color: Color.brandPurple,
                     deltaPct: story.expensesDeltaPct, deltaIsNeutral: true,
                     footnote: otherCurrenciesLine(story.otherExpenseTotals))
        }
    }

    private func moneyDisplay(_ amount: Double, code: String?) -> String {
        CurrencyService.money(amount, code: code ?? financialService.currency, whole: true)
    }

    /// "+ 1.200 RON · 300 USD" when expenses exist in further currencies —
    /// listed, never silently summed into the headline.
    private func otherCurrenciesLine(_ totals: [(code: String, total: Double)]) -> String? {
        guard !totals.isEmpty else { return nil }
        return "+ " + totals
            .map { CurrencyService.money($0.total, code: $0.code, whole: true) }
            .joined(separator: " · ")
    }

    private func deltaText(_ pct: Int) -> String {
        let sign = pct >= 0 ? "+" : "−"
        return String(format: String(localized: "year_vs_prev_fmt"),
                      "\(sign)\(abs(pct))%", selectedYear - 1)
    }

    private func yearStat(value: String, label: LocalizedStringKey, icon: String, color: Color,
                          deltaPct: Int?, deltaIsNeutral: Bool = false,
                          footnote: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(AppFont.headline)
                .foregroundStyle(color)
            Text(value)
                .font(AppFont.scaled(26, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            Text(label)
                .font(AppFont.scaled(12))
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            if let footnote {
                Text(verbatim: footnote)
                    .font(AppFont.scaled(10))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if let deltaPct {
                Text(verbatim: deltaText(deltaPct))
                    .font(AppFont.scaled(10, weight: .semibold))
                    .foregroundStyle(!deltaIsNeutral && deltaPct > 0
                        ? Color.brandSuccess
                        : Color.primary.opacity(AppOpacity.secondaryText))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.base)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
            .strokeBorder(color.opacity(0.15), lineWidth: 0.8))
    }

    // MARK: - „Vezi povestea"

    private var wrappedButton: some View {
        GlassWideButton(icon: "play.fill", label: "year_view_story") {
            showWrapped = true
        }
    }

    // MARK: - Story chapters (each renders only when its data exists)

    @ViewBuilder private func storySection(_ story: YearStory) -> some View {
        let rows = chapterRows(story)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("The Story")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                    .padding(.leading, AppSpacing.xxs)
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        storyRow(row)
                    }
                }
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
            }
        }
    }

    private struct ChapterRow: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: LocalizedStringKey
        let detail: String
        var thumb: URL? = nil
        var member: FamilyMember? = nil
    }

    private func chapterRows(_ story: YearStory) -> [ChapterRow] {
        var rows: [ChapterRow] = []

        if let first = story.firstMemory {
            rows.append(ChapterRow(
                id: "memory", icon: "sparkles", color: .orange,
                title: "First memory of the year",
                detail: first.title.isEmpty ? monthName(monthOf(first.takenAt)) : first.title,
                thumb: URL(string: first.photoUrl)))
        }
        if let busy = story.busiestMonth {
            rows.append(ChapterRow(
                id: "busiest", icon: "flame.fill", color: Color.brandDanger,
                title: "Busiest month",
                detail: String(format: String(localized: "%@ — %d tasks done"),
                               monthName(busy.month), busy.count)))
        }
        if story.workedSeconds > 0 {
            rows.append(ChapterRow(
                id: "hours", icon: "timer", color: Color.brandTeal,
                title: "year_hours_title",
                detail: String(format: String(localized: "year_hours_detail_fmt"),
                               TimeInterval(story.workedSeconds).workedTotalDisplay)))
        }
        if let project = story.projectOfYear {
            rows.append(ChapterRow(
                id: "project", icon: "hammer.fill", color: Color.brandWarning,
                title: "year_project_title",
                detail: "\(project.title) · \(TimeInterval(project.workedSeconds).workedTotalDisplay)"))
        }
        if let top = story.topMember {
            rows.append(ChapterRow(
                id: "member", icon: "trophy.fill", color: Color.brandGold,
                title: "year_member_title",
                detail: "\(top.member.name) · " + String(
                    format: String(localized: "year_tasks_count_fmt"), top.count),
                member: top.member))
        }
        if let big = story.biggestExpense {
            rows.append(ChapterRow(
                id: "investment", icon: "creditcard.fill", color: Color.brandPurple,
                title: "Biggest investment",
                detail: "\(big.title) · \(big.amountDisplay)"))
        }
        if story.plantsAdded > 0 || story.waterings > 0 {
            var pieces: [String] = []
            if story.plantsAdded > 0 {
                pieces.append(String(format: String(localized: "year_plants_added_fmt"), story.plantsAdded))
            }
            if story.waterings > 0 {
                pieces.append(String(format: String(localized: "year_waterings_fmt"), story.waterings))
            }
            rows.append(ChapterRow(
                id: "garden", icon: "leaf.fill", color: Color.brandSuccess,
                title: "year_garden_title",
                detail: pieces.joined(separator: " · ")))
        }
        if let first = story.valueFirst, let last = story.valueLast {
            let grew = last.valueAmount > first.valueAmount
            rows.append(ChapterRow(
                id: "value",
                icon: grew ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                color: grew ? Color.brandSuccess : Color.brandPrimaryBlue,
                title: grew ? "year_value_up_title" : "year_value_title",
                detail: String(format: String(localized: "year_value_detail_fmt"),
                               CurrencyService.money(first.valueAmount, code: first.currency, whole: true),
                               CurrencyService.money(last.valueAmount, code: last.currency, whole: true))))
        }
        if !story.rentTotals.isEmpty {
            let totals = story.rentTotals
                .map { CurrencyService.money($0.total, code: $0.code, whole: true) }
                .joined(separator: " · ")
            rows.append(ChapterRow(
                id: "rent", icon: "key.fill", color: Color.brandIndigo,
                title: "year_rent_title",
                detail: totals + " · " + String(
                    format: String(localized: "year_rent_payments_fmt"), story.rentPaymentsCount)))
        }
        if story.streak >= 2 {
            rows.append(ChapterRow(
                id: "streak", icon: "flame.fill", color: .orange,
                title: "year_streak_title",
                detail: String(format: String(localized: "year_streak_detail_fmt"), story.streak)))
        }
        return rows
    }

    private func storyRow(_ row: ChapterRow) -> some View {
        HStack(spacing: 12) {
            ColoredIconBadge(icon: row.icon, color: row.color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(AppFont.subheadline).foregroundStyle(.primary)
                Text(verbatim: row.detail)
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    .lineLimit(1)
            }
            Spacer()
            if let member = row.member {
                MemberAvatar(member: member, size: 38)
            } else if let thumb = row.thumb {
                StorageImage(url: thumb) { phase in
                    if case .success(let img) = phase { img.resizable().scaledToFill() }
                    else { Color.primary.opacity(0.06) }
                }
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Month names (app locale)

    private func monthOf(_ dateString: String) -> Int {
        Int(dateString.dropFirst(5).prefix(2)) ?? 1
    }

    private var monthSymbols: [String] {
        let f = DateFormatter()
        f.locale = appSettings.appLocale
        return f.shortStandaloneMonthSymbols ?? []
    }

    private func monthName(_ month: Int) -> String {
        let f = DateFormatter()
        f.locale = appSettings.appLocale
        let names = f.standaloneMonthSymbols ?? []
        guard names.indices.contains(month - 1) else { return "\(month)" }
        return names[month - 1].capitalized
    }

    // MARK: - Wrapped pages (only stats that exist become slides)

    private func wrappedPages(_ story: YearStory) -> [YearWrappedPage] {
        var pages: [YearWrappedPage] = []
        if story.tasksDoneCount > 0 {
            pages.append(YearWrappedPage(
                id: "tasks", icon: "checkmark.seal.fill", tint: Color.brandSuccess,
                value: "\(story.tasksDoneCount)", label: "Tasks completed"))
        }
        if story.photosCount > 0 {
            pages.append(YearWrappedPage(
                id: "photos", icon: "photo.stack.fill", tint: .orange,
                value: "\(story.photosCount)", label: "Photos captured",
                detail: story.firstMemory.flatMap { $0.title.isEmpty ? nil : $0.title }))
        }
        if story.documentsCount > 0 {
            pages.append(YearWrappedPage(
                id: "documents", icon: "doc.text.fill", tint: Color.brandSkyBlue,
                value: "\(story.documentsCount)", label: "Documents filed"))
        }
        if story.workedSeconds > 0 {
            pages.append(YearWrappedPage(
                id: "hours", icon: "timer", tint: Color.brandTeal,
                value: TimeInterval(story.workedSeconds).workedTotalDisplay,
                label: "year_hours_title",
                detail: story.projectOfYear?.title))
        }
        if story.expenseTotal > 0 {
            pages.append(YearWrappedPage(
                id: "spent", icon: "banknote.fill", tint: Color.brandPurple,
                value: moneyDisplay(story.expenseTotal, code: story.expenseCurrency),
                label: "Spent on the home",
                detail: otherCurrenciesLine(story.otherExpenseTotals)))
        }
        if let big = story.biggestExpense {
            pages.append(YearWrappedPage(
                id: "investment", icon: "creditcard.fill", tint: Color.brandPurple,
                value: big.amountDisplay, label: "Biggest investment",
                detail: big.title))
        }
        if let top = story.topMember {
            pages.append(YearWrappedPage(
                id: "member", icon: "trophy.fill", tint: Color.brandGold,
                value: top.member.name, label: "year_member_title",
                detail: String(format: String(localized: "year_tasks_count_fmt"), top.count)))
        }
        if story.plantsAdded > 0 || story.waterings > 0 {
            let value = story.waterings > 0 ? "\(story.waterings)" : "\(story.plantsAdded)"
            let label: LocalizedStringKey = "year_garden_title"
            var pieces: [String] = []
            if story.waterings > 0 {
                pieces.append(String(format: String(localized: "year_waterings_fmt"), story.waterings))
            }
            if story.plantsAdded > 0 {
                pieces.append(String(format: String(localized: "year_plants_added_fmt"), story.plantsAdded))
            }
            pages.append(YearWrappedPage(
                id: "garden", icon: "leaf.fill", tint: Color.brandSuccess,
                value: value, label: label, detail: pieces.joined(separator: " · ")))
        }
        if let first = story.valueFirst, let last = story.valueLast, let delta = story.valueDelta {
            let sign = delta > 0 ? "+" : "−"
            pages.append(YearWrappedPage(
                id: "value",
                icon: delta > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                tint: delta > 0 ? Color.brandSuccess : Color.brandPrimaryBlue,
                value: "\(sign)\(CurrencyService.money(abs(delta), code: last.currency, whole: true))",
                label: delta > 0 ? "year_value_up_title" : "year_value_title",
                detail: String(format: String(localized: "year_value_detail_fmt"),
                               CurrencyService.money(first.valueAmount, code: first.currency, whole: true),
                               CurrencyService.money(last.valueAmount, code: last.currency, whole: true))))
        }
        if let topRent = story.rentTotals.first {
            pages.append(YearWrappedPage(
                id: "rent", icon: "key.fill", tint: Color.brandIndigo,
                value: CurrencyService.money(topRent.total, code: topRent.code, whole: true),
                label: "year_rent_title",
                detail: String(format: String(localized: "year_rent_payments_fmt"),
                               story.rentPaymentsCount)))
        }
        if story.streak >= 2 {
            pages.append(YearWrappedPage(
                id: "streak", icon: "flame.fill", tint: .orange,
                value: "\(story.streak)", label: "year_streak_title",
                detail: String(format: String(localized: "year_streak_detail_fmt"), story.streak)))
        }
        return pages
    }

    // MARK: - Share (two rendered cards: numbers + highlights)
    //
    // The share entry point lives in the toolbar circle's popover
    // (`optionsButton`) as a one-shot action row; the cards themselves are
    // still rendered here, ahead of time, from the story's real numbers.

    /// Renders the share cards off-screen from the story's real numbers.
    @MainActor
    private func renderShareCards(_ story: YearStory) {
        guard story.hasAnyData else {
            shareURLs = []
            return
        }
        var urls: [URL] = []

        var stats: [(value: String, label: String)] = [
            ("\(story.photosCount)", String(localized: "Photos captured")),
            ("\(story.tasksDoneCount)", String(localized: "Tasks completed")),
            ("\(story.documentsCount)", String(localized: "Documents filed")),
            (moneyDisplay(story.expenseTotal, code: story.expenseCurrency),
             String(localized: "Spent on the home")),
        ]
        if story.workedSeconds > 0 {
            stats.append((TimeInterval(story.workedSeconds).workedTotalDisplay,
                          String(localized: "year_hours_title")))
        }
        let numbersCard = YearShareCard(
            year: story.year,
            propertyName: propertyService.primary?.name ?? "PRVIO",
            stats: stats)
        if let url = YearShareRenderer.render(numbersCard, year: story.year, slot: "recap") {
            urls.append(url)
        }

        let highlights = shareHighlights(story)
        if highlights.count >= 2 {
            let highlightsCard = YearHighlightsCard(
                year: story.year,
                propertyName: propertyService.primary?.name ?? "PRVIO",
                highlights: highlights)
            if let url = YearShareRenderer.render(highlightsCard, year: story.year, slot: "story") {
                urls.append(url)
            }
        }
        shareURLs = urls
    }

    private func shareHighlights(_ story: YearStory) -> [(icon: String, text: String)] {
        var rows: [(icon: String, text: String)] = []
        if let first = story.firstMemory, !first.title.isEmpty {
            rows.append(("sparkles", "\(String(localized: "First memory of the year")): \(first.title)"))
        }
        if let busy = story.busiestMonth {
            rows.append(("flame.fill", String(format: String(localized: "%@ — %d tasks done"),
                                              monthName(busy.month), busy.count)))
        }
        if story.workedSeconds > 0 {
            rows.append(("timer", String(format: String(localized: "year_hours_detail_fmt"),
                                         TimeInterval(story.workedSeconds).workedTotalDisplay)))
        }
        if let big = story.biggestExpense {
            rows.append(("creditcard.fill", "\(big.title) · \(big.amountDisplay)"))
        }
        if let top = story.topMember {
            rows.append(("trophy.fill", "\(String(localized: "year_member_title")): \(top.member.name)"))
        }
        if story.plantsAdded > 0 {
            rows.append(("leaf.fill", String(format: String(localized: "year_plants_added_fmt"),
                                             story.plantsAdded)))
        }
        return Array(rows.prefix(5))
    }
}
