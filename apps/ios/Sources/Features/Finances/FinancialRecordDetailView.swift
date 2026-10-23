import SwiftUI

// MARK: - One transaction, in full (field report 2026-08-02)
//
// Rows hid everything behind a long-press: the details lived nowhere and
// recategorizing an auto-imported card payment was undiscoverable — the
// household taught the merchant memory only if someone happened to know
// about press-and-hold → Edit. Tapping a row now PUSHES this page: the
// full record, and the category as an inline menu — a change persists
// immediately and, for auto-imported payments, teaches the merchant
// memory exactly like the edit form does.

struct FinancialRecordDetailView: View {
    @Environment(FinancialService.self) private var financialService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(MerchantRuleService.self) private var merchantRules
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    let record: FinancialRecord

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var isSavingCategory = false
    @State private var error: String?

    /// Re-resolve from the service so an edit/realtime refresh repaints.
    private var live: FinancialRecord {
        financialService.records.first { $0.id == record.id } ?? record
    }

    /// True for rows the Shortcuts "Transaction" automation imported —
    /// the ones whose category correction teaches the merchant memory.
    private var isAutoImported: Bool { live.tags.contains("apple_pay") }

    /// Same income/expense split the add/edit form offers.
    private var categories: [String] {
        live.isIncome
            ? ["salary", "rent", "investment", "other"]
            : ["groceries", "transport", "dining", "shopping", "healthcare",
               "rent", "utilities", "maintenance", "insurance", "taxes",
               "mortgage", "supplies", "other"]
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.lg) {
                hero
                detailsCard
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("fin_detail_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // One circle, everything in it (menu law): edit, then the
            // destructive delete at the end, with its REAL role.
            ToolbarItem(placement: .pageMenu) {
                Menu {
                    Button {
                        showEdit = true
                    } label: { Label("Edit", systemImage: "pencil") }
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: { Label("Delete", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddFinancialView(editing: live) { await financialService.load() }
        }
        .confirmationDialog("Delete", isPresented: $showDeleteConfirm, titleVisibility: .hidden) {
            Button(role: .destructive) {
                HapticFeedback.warning()
                Task {
                    await financialService.delete(live)
                    dismiss()
                }
            } label: { Text("Delete") }
        }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    // MARK: Hero — who, how much, when

    private var hero: some View {
        let style = catStyle(live.category)
        return VStack(spacing: AppSpacing.md) {
            Image(systemName: style.icon)
                .font(AppFont.scaled(30))
                .foregroundStyle(style.color)
                .frame(width: 72, height: 72)
                .glassRoundedRect(AppRadius.xl)
            Text(live.title)
                .font(AppFont.scaled(22, weight: .bold))
                .multilineTextAlignment(.center)
            Text(verbatim: "\(live.isIncome ? "+" : "-")\(currencyService.formatted(live.amount, from: live.currency, preferred: appSettings.preferredCurrency))")
                .font(AppFont.scaled(34, weight: .bold))
                .foregroundStyle(live.isIncome ? Color.brandSuccess : .primary)
            Text(live.dateFormatted)
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.secondaryTextColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
    }

    // MARK: Details — the category is the interactive row

    private var detailsCard: some View {
        VStack(spacing: 0) {
            // Category: a native inline menu; the change lands immediately.
            Menu {
                Picker("", selection: Binding(
                    get: { live.category },
                    set: { setCategory($0) })) {
                    ForEach(categories, id: \.self) { cat in
                        Label { Text(LocalizedStringKey(cat.capitalized)) }
                            icon: { Image(systemName: catStyle(cat).icon) }
                            .tag(cat)
                    }
                }
            } label: {
                detailRow(icon: catStyle(live.category).icon,
                          tint: catStyle(live.category).color,
                          title: "fin_detail_category") {
                    HStack(spacing: AppSpacing.xs) {
                        if isSavingCategory {
                            ProgressView().controlSize(.small)
                        }
                        Text(LocalizedStringKey(live.category.capitalized))
                            .font(AppFont.scaled(15, weight: .medium))
                            .foregroundStyle(.primary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AppFont.scaled(11, weight: .semibold))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(isSavingCategory)

            // The learning hint — only where a correction actually teaches.
            if isAutoImported {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "sparkles")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.brandPurple)
                    Text("fin_detail_learn_hint")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(Color.secondaryTextColor)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.bottom, AppSpacing.sm)
            }

            divider
            if let notes = live.description, !notes.isEmpty {
                detailRow(icon: "text.alignleft", tint: .secondary,
                          title: "fin_detail_notes") {
                    Text(notes)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.trailing)
                }
                divider
            }
            if live.isRecurring == true {
                detailRow(icon: "arrow.triangle.2.circlepath", tint: .accentColor,
                          title: "fin_detail_recurring") {
                    Text(LocalizedStringKey(live.recurrenceInterval?.capitalized ?? ""))
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                }
                divider
            }
            let userTags = live.tags.filter { $0 != "apple_pay" && $0 != "auto" }
            if !userTags.isEmpty {
                detailRow(icon: "tag", tint: .secondary, title: "fin_detail_tags") {
                    Text(userTags.joined(separator: " · "))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.secondaryTextColor)
                        .multilineTextAlignment(.trailing)
                }
                divider
            }
            detailRow(icon: "creditcard", tint: .secondary, title: "fin_detail_source") {
                Text(isAutoImported ? "fin_detail_source_auto" : "fin_detail_source_manual")
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
            }
        }
        .liquidGlass(cornerRadius: 18)
    }

    private var divider: some View {
        Divider().padding(.leading, 56).opacity(0.5)
    }

    private func detailRow(icon: String, tint: Color, title: LocalizedStringKey,
                           @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(15))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(AppFont.scaled(15))
                .foregroundStyle(Color.secondaryTextColor)
            Spacer(minLength: AppSpacing.md)
            value()
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    // MARK: The category write — same semantics as the edit form

    private func setCategory(_ cat: String) {
        guard cat != live.category, !isSavingCategory else { return }
        isSavingCategory = true
        HapticFeedback.impact(.light)
        struct Patch: Encodable { let category: String }
        Task {
            defer { isSavingCategory = false }
            do {
                try await supabase
                    .from("financial_records")
                    .update(Patch(category: cat))
                    .eq("id", value: live.id.uuidString)
                    .execute()
                // A correction on an auto-imported payment teaches the
                // household's merchant memory — the same shop lands in the
                // chosen category on every phone from now on.
                if isAutoImported {
                    await merchantRules.learn(merchant: live.title, category: cat)
                }
                HapticFeedback.success()
                await financialService.load()
            } catch {
                self.error = error.recordableDescription
            }
        }
    }
}
