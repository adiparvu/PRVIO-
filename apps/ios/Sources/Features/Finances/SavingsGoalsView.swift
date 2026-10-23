import SwiftUI

// MARK: - Savings goals — section, full list, detail, and the two sheets
//
// "Obiective comune": shared family savings targets with per-member manual
// deposits. The section rides on the Finances page (top goals + See all); the
// full page owns the one-circle add trigger; the detail shows the ledger and
// the per-member breakdown.

// MARK: Section (embedded on FinancesView)

struct SavingsGoalsSection: View {
    @Environment(SavingsGoalService.self) private var service
    @State private var showAdd = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            // Naked header (headers-no-borders law) with a See-all affordance.
            NavigationLink { SavingsGoalsView() } label: {
                HStack(spacing: AppSpacing.xs) {
                    Text("goal_section_title")
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    if !service.goals.isEmpty {
                        Text(verbatim: "\(service.goals.count)")
                            .font(AppFont.scaled(13, weight: .semibold))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            .buttonStyle(.plain)

            if service.goals.isEmpty {
                NavigationLink { SavingsGoalsView() } label: {
                    EmptyStateView(icon: "target",
                                   title: "goal_empty_title",
                                   message: "goal_empty_message")
                }
                .buttonStyle(.plain)
            } else {
                // Top 2 goals inline; the rest live on the full page.
                ForEach(service.goals.prefix(2)) { goal in
                    NavigationLink { SavingsGoalDetailView(goal: goal) } label: {
                        SavingsGoalCard(progress: service.progress(for: goal))
                    }
                    .buttonStyle(.plain)
                }
                // Adding the SECOND goal used to require: header → full page
                // → the small toolbar plus, and nobody found it (field
                // report 2026-08-02: "să poți adăuga mai multe"). The
                // affordance now lives where the goals do.
                Button { showAdd = true; HapticFeedback.impact(.light) } label: {
                    HStack(spacing: AppSpacing.sm) {
                        Image(systemName: "plus.circle.fill")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.secondaryTextColor)
                        Text("goal_add")
                            .font(AppFont.scaled(14, weight: .medium))
                            .foregroundStyle(Color.secondaryTextColor)
                        Spacer()
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .liquidGlass(cornerRadius: AppRadius.lg)
            }
        }
        .sheet(isPresented: $showAdd) { AddSavingsGoalSheet() }
    }
}

// MARK: Full list page (one-circle add)

struct SavingsGoalsView: View {
    @Environment(SavingsGoalService.self) private var service
    @State private var showAdd = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                if service.goals.isEmpty {
                    EmptyStateView(icon: "target",
                                   title: "goal_empty_title",
                                   message: "goal_empty_message",
                                   actionLabel: "goal_add") { showAdd = true }
                        .padding(.top, AppSpacing.xxl)
                } else {
                    ForEach(service.goals) { goal in
                        NavigationLink { SavingsGoalDetailView(goal: goal) } label: {
                            SavingsGoalCard(progress: service.progress(for: goal))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("goal_section_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel(Text("goal_add"))
            }
        }
        .sheet(isPresented: $showAdd) { AddSavingsGoalSheet() }
        .task { await service.load() }
    }
}

// MARK: Detail — ledger + per-member breakdown

struct SavingsGoalDetailView: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal

    @State private var showContribute = false
    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    /// Re-resolve from the service so realtime updates repaint the detail.
    private var live: SavingsGoal { service.goals.first { $0.id == goal.id } ?? goal }
    private var progress: SavingsGoalProgress { service.progress(for: live) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                SavingsGoalCard(progress: progress)

                Button { showContribute = true; HapticFeedback.impact(.medium) } label: {
                    Label("goal_add_deposit", systemImage: "plus.circle.fill")
                        .font(AppFont.scaled(16, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.base)
                        .background(live.tint.opacity(AppOpacity.tintedFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.lg))
                        .foregroundStyle(live.tint)
                }
                .buttonStyle(.plain)

                if live.hasAutoRule { autoRuleRow }
                if !progress.byMember.isEmpty { memberBreakdown }
                contributionHistory
                Spacer(minLength: 60)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(verbatim: live.title))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                Menu {
                    Button { showEdit = true } label: {
                        Label("goal_edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) { showDeleteConfirm = true } label: {
                        Label("goal_delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(.primary)
                }
            }
        }
        .sheet(isPresented: $showContribute) { AddContributionSheet(goal: live) }
        .sheet(isPresented: $showEdit) { AddSavingsGoalSheet(editing: live) }
        .confirmationDialog("goal_delete_confirm", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("goal_delete", role: .destructive) {
                Task { await service.deleteGoal(live); dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// Shown when a monthly auto-rule is active — states plainly what lands,
    /// for whom, and on which day, so the automation is never a mystery.
    private var autoRuleRow: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(AppFont.scaled(17, weight: .semibold))
                .foregroundStyle(live.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text("goal_auto_active").font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary)
                Text(verbatim: autoRuleSummary).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
            }
            Spacer()
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private var autoRuleSummary: String {
        let amount = CurrencyService.money(live.autoAmount ?? 0, code: live.currency, whole: true)
        let day = live.autoDay ?? 1
        if let name = live.autoMemberName, !name.isEmpty {
            return String(format: String(localized: "goal_auto_summary_member_fmt"), amount, day, name)
        }
        return String(format: String(localized: "goal_auto_summary_fmt"), amount, day)
    }

    private var memberBreakdown: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("goal_by_member").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
            ForEach(progress.byMember, id: \.name) { row in
                HStack {
                    Text(verbatim: row.name).font(AppFont.scaled(14)).foregroundStyle(.primary)
                    Spacer()
                    Text(verbatim: CurrencyService.money(row.amount, code: live.currency, whole: true))
                        .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private var contributionHistory: some View {
        let items = service.contributions(for: live.id)
        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("goal_history").font(AppFont.scaled(15, weight: .semibold)).foregroundStyle(.primary)
            if items.isEmpty {
                Text("goal_history_empty").font(AppFont.scaled(13)).foregroundStyle(Color.secondaryTextColor)
            } else {
                ForEach(items) { c in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: c.memberName ?? "—").font(AppFont.scaled(14)).foregroundStyle(.primary)
                            if let d = c.date {
                                Text(verbatim: AppDate.monthDay.string(from: d))
                                    .font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                            }
                            if let note = c.note, !note.isEmpty {
                                Text(verbatim: note).font(AppFont.scaled(12)).foregroundStyle(Color.secondaryTextColor)
                            }
                        }
                        Spacer()
                        Text(verbatim: CurrencyService.money(c.amount, code: live.currency, whole: true))
                            .font(AppFont.scaled(14, weight: .semibold)).foregroundStyle(.primary).monospacedDigit()
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await service.deleteContribution(c) }
                        } label: { Label("goal_delete_deposit", systemImage: "trash") }
                    }
                }
            }
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }
}

// MARK: Add goal sheet

struct AddSavingsGoalSheet: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    /// When set, the sheet edits this goal in place instead of creating one.
    var editing: SavingsGoal? = nil

    @State private var title = ""
    @State private var target = ""
    @State private var monthly = ""
    @State private var icon = "target"
    @State private var colorToken = "brandPurple"
    @State private var hasDeadline = false
    @State private var deadline = Date()
    // Optional monthly auto-rule (phase 2): a fixed amount credited to a chosen
    // member automatically on a chosen day, applied server-side by pg_cron.
    @State private var hasAutoRule = false
    @State private var autoAmount = ""
    @State private var autoDay = 1
    @State private var autoMemberId: String = ""
    @State private var isSaving = false
    @State private var error: String?
    @State private var didHydrate = false

    /// A goal can be almost anything a family saves for — home, travel, wheels,
    /// study, celebration, tech, health, safety net. Six per row, six rows.
    private static let icons = [
        "target", "house.fill", "building.2.fill", "key.fill", "sofa.fill", "wrench.and.screwdriver.fill",
        "car.fill", "bicycle", "airplane", "sailboat.fill", "tent.fill", "beach.umbrella.fill",
        "gift.fill", "heart.fill", "star.fill", "crown.fill", "diamond.fill", "sparkles",
        "graduationcap.fill", "book.fill", "laptopcomputer", "iphone", "gamecontroller.fill", "tv.fill",
        "banknote.fill", "creditcard.fill", "chart.line.uptrend.xyaxis", "shield.fill", "bag.fill", "cart.fill",
        "pawprint.fill", "stroller.fill", "cross.case.fill", "camera.fill", "music.note", "leaf.fill"
    ]

    /// Brand tokens first, then two explicit-hex extras — everything resolves
    /// through `SavingsGoal.tint(forToken:)`, which understands both.
    private static let palette = ["brandPurple", "brandPrimaryBlue", "brandSkyBlue", "brandSuccess",
                                  "brandWarning", "brandDanger", "#FF2D55", "#FFD60A"]

    /// (stable id string, display name) for each family member — the auto-rule
    /// credits one of them. The id mirrors the manual-deposit stamp (user id
    /// when linked, else the member row id) so the per-member rollup stays one.
    private var memberOptions: [(id: String, name: String)] {
        familyService.members.map { (id: ($0.userId ?? $0.id).uuidString, name: $0.name) }
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (Double(target) ?? 0) > 0
    }

    var body: some View {
        FormScaffold(title: editing == nil ? "goal_new" : "goal_edit",
                     canSave: canSave, isSaving: isSaving,
                     error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: "textformat", tint: tint(colorToken)) {
                    TextField("goal_title_placeholder", text: $title)
                        .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "target", tint: tint(colorToken)) {
                    Text("goal_target").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $target).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: currency).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                FormRow(icon: "person.2.fill", tint: tint(colorToken)) {
                    Text("goal_monthly_per_member").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $monthly).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.body)
                    Text(verbatim: currency).foregroundStyle(Color.secondaryTextColor)
                }
            }

            iconSection
            colorSection

            // Monthly auto-rule — a set amount lands automatically, so a family
            // that commits a standing contribution doesn't have to remember it.
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                FormGroup {
                    FormRow(icon: "arrow.triangle.2.circlepath", tint: tint(colorToken)) {
                        Toggle("goal_auto_rule", isOn: $hasAutoRule.animation(.snappy)).font(AppFont.body)
                    }
                    if hasAutoRule {
                        FormDivider()
                        FormRow(icon: "banknote.fill", tint: tint(colorToken)) {
                            Text("goal_auto_amount").font(AppFont.body).foregroundStyle(.primary)
                            Spacer()
                            TextField("0", text: $autoAmount).keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing).font(AppFont.body)
                            Text(verbatim: currency).foregroundStyle(Color.secondaryTextColor)
                        }
                        FormDivider()
                        FormRow(icon: "calendar.badge.clock", tint: tint(colorToken)) {
                            Picker("goal_auto_day", selection: $autoDay) {
                                ForEach(1...28, id: \.self) { d in
                                    Text(String(format: String(localized: "goal_auto_day_fmt"), d)).tag(d)
                                }
                            }
                            .font(AppFont.body)
                        }
                        if !memberOptions.isEmpty {
                            FormDivider()
                            FormRow(icon: "person.crop.circle.fill", tint: tint(colorToken)) {
                                Picker("goal_auto_member", selection: $autoMemberId) {
                                    ForEach(memberOptions, id: \.id) { m in
                                        Text(verbatim: m.name).tag(m.id)
                                    }
                                }
                                .font(AppFont.body)
                            }
                        }
                    }
                }
                if hasAutoRule {
                    Text("goal_auto_footer")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                        .padding(.leading, AppSpacing.xxs)
                }
            }

            FormGroup {
                FormRow(icon: "calendar", tint: tint(colorToken)) {
                    Toggle("goal_deadline", isOn: $hasDeadline.animation(.snappy)).font(AppFont.body)
                }
                if hasDeadline {
                    FormDivider()
                    FormRow(icon: "flag.checkered", tint: tint(colorToken)) {
                        DatePicker("goal_deadline_date", selection: $deadline, displayedComponents: .date)
                            .font(AppFont.body)
                    }
                }
            }
        }
        .onAppear(perform: hydrate)
    }

    // MARK: Icon + color sections (avatar-ring language)

    /// Naked section label — the same anatomy FormGroup titles use.
    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
    }

    private var iconSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("goal_icon")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 6),
                      spacing: AppSpacing.sm) {
                ForEach(Self.icons, id: \.self) { name in
                    iconCell(name)
                }
            }
        }
    }

    private func iconCell(_ name: String) -> some View {
        let selected = icon == name
        let accent = tint(colorToken)
        return Button {
            withAnimation(.snappy(duration: 0.2)) { icon = name }
            HapticFeedback.selection()
        } label: {
            Image(systemName: name)
                .font(AppFont.scaled(17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(selected ? accent.opacity(AppOpacity.tintedFill)
                                     : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                .overlay {
                    if selected {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .strokeBorder(accent, lineWidth: 1.5)
                    }
                }
                .foregroundStyle(selected ? accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("goal_color")
            // Naked grid, deliberately NOT on glass — inside a glass container
            // the vibrancy compositing ate flat semantic fills on device
            // (IMG_8608, avatar ring); this mirrors that proven surface.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4),
                      spacing: AppSpacing.lg) {
                ForEach(Self.palette, id: \.self) { colorSwatch($0) }
            }
            .padding(.vertical, AppSpacing.xs)

            FormGroup {
                FormRow(icon: "paintpalette.fill", tint: tint(colorToken)) {
                    Text("Custom color")
                        .font(AppFont.scaled(14))
                        .foregroundStyle(.primary)
                    if colorToken.hasPrefix("#"), !Self.palette.contains(colorToken) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFont.footnote)
                            .foregroundStyle(Color.brandSuccess)
                    }
                    Spacer()
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: colorToken) ?? tint(colorToken) },
                        set: { newColor in
                            withAnimation(.snappy(duration: 0.25)) {
                                colorToken = newColor.hexString()
                            }
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .accessibilityLabel(Text("Custom color"))
                }
            }
        }
    }

    private func colorSwatch(_ token: String) -> some View {
        let color = tint(token)
        let selected = colorToken == token
        return Button {
            withAnimation(.snappy(duration: 0.25)) { colorToken = token }
            HapticFeedback.selection()
        } label: {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 40, height: 40)
                if selected {
                    Image(systemName: "checkmark")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(.white)
                }
            }
            .overlay {
                if selected {
                    Circle()
                        .strokeBorder(color, lineWidth: 1.5)
                        .frame(width: 48, height: 48)
                }
            }
            .frame(width: 48, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var currency: String { editing?.currency ?? appSettings.preferredCurrency }

    private func tint(_ token: String) -> Color { SavingsGoal.tint(forToken: token) }

    /// Fill the fields from the goal under edit, once, then default the auto
    /// member to the first family member if nothing was chosen.
    private func hydrate() {
        guard !didHydrate else { return }
        didHydrate = true
        if let g = editing {
            title = g.title
            target = trimZeros(g.targetAmount)
            monthly = (g.monthlyPerMember ?? 0) > 0 ? trimZeros(g.monthlyPerMember!) : ""
            icon = g.iconName
            colorToken = g.color ?? "brandPurple"
            if let d = g.deadlineDate { hasDeadline = true; deadline = d }
            if g.hasAutoRule {
                hasAutoRule = true
                autoAmount = trimZeros(g.autoAmount ?? 0)
                autoDay = g.autoDay ?? 1
                if let mid = g.autoMemberId { autoMemberId = mid }
            }
        }
        if autoMemberId.isEmpty { autoMemberId = memberOptions.first?.id ?? "" }
    }

    private func trimZeros(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }

    private func save() {
        isSaving = true
        let deadlineStr = hasDeadline ? AppDate.day.string(from: deadline) : nil
        let monthlyVal = Double(monthly).flatMap { $0 > 0 ? $0 : nil }
        let autoVal = hasAutoRule ? Double(autoAmount).flatMap { $0 > 0 ? $0 : nil } : nil
        let autoName = autoVal != nil
            ? memberOptions.first { $0.id == autoMemberId }?.name : nil
        let autoId = autoVal != nil ? (autoMemberId.isEmpty ? nil : autoMemberId) : nil
        let cleanTitle = title.trimmingCharacters(in: .whitespaces)

        Task {
            do {
                if let g = editing {
                    try await service.updateGoal(g.id, patch: SavingsGoalService.GoalPatch(
                        title: cleanTitle, icon: icon, color: colorToken,
                        targetAmount: Double(target) ?? 0,
                        monthlyPerMember: monthlyVal, deadline: deadlineStr,
                        autoAmount: autoVal, autoDay: autoVal != nil ? autoDay : nil,
                        autoMemberId: autoId, autoMemberName: autoName,
                        updatedAt: ISODate.string(from: Date())))
                } else {
                    guard let pid = propertyService.primary?.id else {
                        error = String(localized: "No property found. Please set up your property first.")
                        isSaving = false; return
                    }
                    try await service.addGoal(SavingsGoalService.NewGoal(
                        propertyId: pid.uuidString,
                        title: cleanTitle, icon: icon, color: colorToken,
                        targetAmount: Double(target) ?? 0,
                        currency: appSettings.preferredCurrency,
                        monthlyPerMember: monthlyVal, deadline: deadlineStr,
                        autoAmount: autoVal, autoDay: autoVal != nil ? autoDay : nil,
                        autoMemberId: autoId, autoMemberName: autoName))
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}

// MARK: Add contribution sheet

struct AddContributionSheet: View {
    @Environment(SavingsGoalService.self) private var service
    @Environment(FinancialService.self) private var financialService
    @Environment(\.dismiss) private var dismiss
    let goal: SavingsGoal

    @State private var amount = ""
    @State private var note = ""
    // Optional: mirror the deposit into the household's real financial flow as
    // a savings transfer, so cash-flow reflects money actually set aside — not
    // a number floating outside the ledger (phase 2).
    @State private var linkToFlow = false
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool { (Double(amount) ?? 0) > 0 }

    var body: some View {
        FormScaffold(title: "goal_add_deposit", saveLabel: "goal_deposit_save",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: "banknote.fill", tint: goal.tint) {
                    Text("goal_amount").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $amount).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing).font(AppFont.scaled(20, weight: .semibold))
                    Text(verbatim: goal.currency).foregroundStyle(Color.secondaryTextColor)
                }
                FormDivider()
                FormRow(icon: "text.alignleft", tint: goal.tint) {
                    TextField("goal_note_placeholder", text: $note).font(AppFont.body)
                }
            }

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                FormGroup {
                    FormRow(icon: "arrow.left.arrow.right", tint: goal.tint) {
                        Toggle("goal_link_flow", isOn: $linkToFlow.animation(.snappy)).font(AppFont.body)
                    }
                }
                Text("goal_link_flow_footer")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.secondaryTextColor)
                    .padding(.leading, AppSpacing.xxs)
            }
        }
    }

    private func save() {
        isSaving = true
        let value = Double(amount) ?? 0
        Task {
            do {
                try await service.addContribution(to: goal, amount: value, note: note)
                // The link is a best-effort mirror: a failure to write the
                // financial row must not lose the deposit that already landed.
                if linkToFlow {
                    try? await financialService.add(FinancialService.NewFinancialRecord(
                        propertyId: goal.propertyId.uuidString,
                        title: goal.title,
                        amount: value,
                        currency: goal.currency,
                        type: "expense",
                        category: String(localized: "goal_flow_category"),
                        date: AppDate.day.string(from: Date()),
                        description: note.isEmpty ? nil : note,
                        tags: ["savings", "savings_goal:\(goal.id.uuidString)"]))
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}
