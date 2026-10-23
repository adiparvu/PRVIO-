import SwiftUI
import Charts

// MARK: - Balance insight

/// One sentence under the balance, only ever built from real data.
enum FinanceInsight: Equatable {
    /// Spending changed vs. the previous month (both months have expenses).
    case comparison(percent: Int, less: Bool, previousMonth: String)
    /// The displayed month's biggest expense category.
    case topCategory(category: String, amount: Double)
}

// MARK: - Main View

struct FinancesView: View {
    @Environment(FinancialService.self) var financialService
    @Environment(BudgetService.self) var budgetService
    @Environment(CurrencyService.self) var currencyService
    @Environment(DocumentService.self) var documentService
    @Environment(FamilyService.self) var familyService
    @Environment(AppSettings.self) var appSettings
    @Environment(AppRouter.self) private var router

    @State private var showAddSheet    = false
    /// Row being edited via the long-press menu (nil = none). Not private:
    /// the row menu lives in the FinancesViewComponents extension.
    @State var editingRecord: FinancialRecord?
    @State var selectedType: String? = nil
    @State var displayedMonth: Date   = Calendar.current.startOfMonth(Date())
    @State private var searchText = ""

    var preferred: String { appSettings.preferredCurrency }

    // Records for the displayed month
    var monthRecords: [FinancialRecord] {
        let cal = Calendar.current
        let start = displayedMonth
        guard let end = cal.date(byAdding: .month, value: 1, to: start) else { return [] }
        return financialService.records.filter { r in
            guard let d = AppDate.day(from: r.date) else { return false }
            return d >= start && d < end
        }
    }

    private func total(_ type: String, in records: [FinancialRecord]) -> Double {
        records.filter { $0.type == type }
            .reduce(0) { $0 + currencyService.convert($1.amount, from: $1.currency, to: preferred) }
    }

    // Group records by date string
    func grouped(_ records: [FinancialRecord]) -> [(date: String, records: [FinancialRecord])] {
        var grouped: [String: [FinancialRecord]] = [:]
        for r in records { grouped[r.date, default: []].append(r) }
        return grouped.keys.sorted(by: >).map { (date: $0, records: grouped[$0] ?? []) }
    }

    var isCurrentMonth: Bool {
        Calendar.current.isDate(displayedMonth, equalTo: Date(), toGranularity: .month)
    }

    /// Recurring household costs derived (read-time, never persisted) from the
    /// property's documents that carry a value + monthly/quarterly/yearly
    /// recurrence. Each is normalised to a monthly equivalent and converted to
    /// the preferred currency; sorted biggest first.
    func recurringDocCosts() -> [RecurringDocCostItem] {
        documentService.documents.compactMap { doc -> RecurringDocCostItem? in
            guard let rec = doc.recurrence,
                  ["monthly", "quarterly", "yearly"].contains(rec),
                  let value = doc.value, value > 0 else { return nil }
            let monthly: Double
            switch rec {
            case "quarterly": monthly = value / 3
            case "yearly":    monthly = value / 12
            default:          monthly = value
            }
            let converted = currencyService.convert(monthly, from: doc.currency ?? preferred, to: preferred)
            return RecurringDocCostItem(doc: doc, monthlyAmount: converted, recurrence: rec)
        }
        .sorted { $0.monthlyAmount > $1.monthlyAmount }
    }

    /// Top expense categories of the displayed month, with their share of
    /// the month's spending — one pass, converted to the preferred currency.
    func categoryItems(month: [FinancialRecord]) -> [CategoryBreakdownSection.Item] {
        var totals: [String: Double] = [:]
        for r in month where r.type == "expense" {
            totals[r.category.lowercased(), default: 0]
                += currencyService.convert(r.amount, from: r.currency, to: preferred)
        }
        let grand = totals.values.reduce(0, +)
        guard grand > 0 else { return [] }
        return totals.sorted { $0.value > $1.value }.prefix(5).map {
            CategoryBreakdownSection.Item(category: $0.key, amount: $0.value, share: $0.value / grand)
        }
    }

    /// Income vs. expenses for the six months ending at the displayed month,
    /// zeros included so the chart never lies by omission. Months with no
    /// records at all are flagged (`hasData == false`) so the chart can show
    /// "no history" differently from a real zero.
    func trendPoints() -> [SixMonthTrendSection.Point] {
        let cal = Calendar.current
        guard let end = cal.date(byAdding: .month, value: 1, to: displayedMonth),
              let start = cal.date(byAdding: .month, value: -5, to: displayedMonth) else { return [] }
        var buckets: [Date: (income: Double, expense: Double)] = [:]
        for r in financialService.records {
            guard let d = AppDate.day(from: r.date), d >= start, d < end else { continue }
            let m = cal.startOfMonth(d)
            var b = buckets[m] ?? (0, 0)
            let v = currencyService.convert(r.amount, from: r.currency, to: preferred)
            if r.isIncome { b.income += v } else { b.expense += v }
            buckets[m] = b
        }
        return (0..<6).compactMap { cal.date(byAdding: .month, value: $0, to: start) }
            .flatMap { m -> [SixMonthTrendSection.Point] in
                let bucket = buckets[m]
                let b = bucket ?? (0, 0)
                let label = AppDate.monthLabel.string(from: m).capitalized
                return [SixMonthTrendSection.Point(monthStart: m, label: label, isIncome: true,
                                                   amount: b.income, hasData: bucket != nil),
                        SixMonthTrendSection.Point(monthStart: m, label: label, isIncome: false,
                                                   amount: b.expense, hasData: bucket != nil)]
            }
    }

    /// The one honest sentence under the balance: spending compared with the
    /// previous month when both months actually have expenses, otherwise the
    /// displayed month's biggest expense category. Nil when the data can't
    /// back either claim — then nothing is shown, nothing is invented.
    func insight(expenses: Double, month: [FinancialRecord]) -> FinanceInsight? {
        let cal = Calendar.current
        if expenses > 0, let prevStart = cal.date(byAdding: .month, value: -1, to: displayedMonth) {
            let previous = financialService.records.filter { r in
                guard let d = AppDate.day(from: r.date) else { return false }
                return d >= prevStart && d < displayedMonth
            }
            let prevExpenses = total("expense", in: previous)
            if prevExpenses > 0 {
                let percent = Int((abs(expenses - prevExpenses) / prevExpenses * 100).rounded())
                if percent >= 1 {
                    return .comparison(percent: percent,
                                       less: expenses < prevExpenses,
                                       previousMonth: AppDate.monthName.string(from: prevStart))
                }
            }
        }
        if let top = categoryItems(month: month).first {
            return .topCategory(category: top.category, amount: top.amount)
        }
        return nil
    }

    /// The next few real recurring due dates, merged from the two sources the
    /// backend actually has: recurring financial-record templates
    /// (`is_recurring` + `next_occurrence`, migration 015) and active tenant
    /// leases (`monthly_rent` + `payment_day`, migration 105). No recurring
    /// data → empty array → the section never appears.
    func upcomingPayments(limit: Int = 3) -> [UpcomingPaymentItem] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var items: [UpcomingPaymentItem] = []

        for r in financialService.records where r.isRecurring == true {
            guard let nextStr = r.nextOccurrence,
                  let due = AppDate.day(from: nextStr), due >= today else { continue }
            items.append(UpcomingPaymentItem(
                id: "record-\(r.id.uuidString)",
                kind: .record(title: r.title),
                category: r.category,
                date: due,
                amount: currencyService.convert(r.amount, from: r.currency, to: preferred),
                isIncome: r.isIncome))
        }

        for lease in familyService.leases.values {
            guard let rent = lease.monthlyRent, rent > 0,
                  let day = lease.paymentDay, (1...31).contains(day),
                  !lease.hasEnded,
                  let due = Self.nextMonthlyDate(day: day, onOrAfter: today, calendar: cal)
            else { continue }
            if let endStr = lease.leaseEnd, let end = AppDate.day(from: endStr), due > end { continue }
            if let startStr = lease.leaseStart, let start = AppDate.day(from: startStr), due < start { continue }
            let tenant = familyService.members.first { $0.id == lease.memberId }?.name
            items.append(UpcomingPaymentItem(
                id: "lease-\(lease.id.uuidString)",
                kind: .rent(tenantName: tenant),
                category: "rent",
                date: due,
                amount: currencyService.convert(rent, from: lease.currency, to: preferred),
                isIncome: true))
        }

        return Array(items.sorted { $0.date < $1.date }.prefix(limit))
    }

    /// First occurrence of `day`-of-month on/after `date`, clamped to the
    /// month's length (a "31st" rent day falls on Feb 28/29, like Calendar).
    private static func nextMonthlyDate(day: Int, onOrAfter date: Date, calendar cal: Calendar) -> Date? {
        func clamped(in monthStart: Date) -> Date? {
            guard let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count else { return nil }
            var comps = cal.dateComponents([.year, .month], from: monthStart)
            comps.day = min(day, daysInMonth)
            return cal.date(from: comps)
        }
        let thisMonth = cal.startOfMonth(date)
        if let due = clamped(in: thisMonth), due >= date { return due }
        guard let nextMonth = cal.date(byAdding: .month, value: 1, to: thisMonth) else { return nil }
        return clamped(in: nextMonth)
    }

    var body: some View {
        // One pass per render: the month filter and both totals used to be
        // recomputed on every property access (4× per render, each with a
        // currency conversion per record).
        let month = monthRecords
        let income = total("income", in: month)
        let expenses = total("expense", in: month)
        let typed = selectedType.map { t in month.filter { $0.type == t } } ?? month
        let filtered = searchText.isEmpty ? typed : typed.filter {
            $0.title.matchesSearch(searchText)
                || $0.category.matchesSearch(searchText)
                || ($0.description ?? "").matchesSearch(searchText)
                || $0.dateFormatted.matchesSearch(searchText)
                || currencyService.formatted($0.amount, from: $0.currency, preferred: preferred)
                    .matchesSearch(searchText)
        }

        Group {
        if financialService.isLoading && financialService.records.isEmpty {
                ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection(net: income - expenses,
                                    insight: insight(expenses: expenses, month: month))
                        // The KPI strip is pure data now — its old
                        // tap-to-filter lives in the toolbar circle.
                        kpiStrip(income: income, expenses: expenses)
                        quickActionsRow
                            .padding(.top, AppSpacing.xl)
                            .padding(.horizontal, AppSpacing.xl)
                        UpcomingPaymentsSection(items: upcomingPayments(),
                                                format: { fmt($0) })
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        SavingsGoalsSection()
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        NetWorthSection()
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        PropertyTCOSection()
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        CategoryBreakdownSection(items: categoryItems(month: month),
                                                 format: { fmt($0) })
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        SixMonthTrendSection(points: trendPoints())
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        ExpenseForecastSection(records: financialService.records)
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        SubscriptionsSection(items: SubscriptionsSection.detect(in: financialService.records),
                                             format: { financialService.moneyDisplay($0) })
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        RecurringDocumentCostsSection(items: recurringDocCosts(),
                                                      format: { fmt($0) })
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        MetersSection()
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        VehiclesSection()
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        transactionList(filtered)
                            .padding(.top, AppSpacing.lg)
                            .padding(.horizontal, AppSpacing.xl)
                        Spacer(minLength: 110)
                    }
                }
                .refreshable {
            await financialService.load()
            checkBudgetThresholds()
        }
        }
        }
        .background(appBackground.ignoresSafeArea())
        .overlay(alignment: .bottomTrailing) {
            FloatingSpeedDial(
                actions: appSettings.fabVisible(.finances) ? appSettings.fabActions(.finances) : [],
                onSelect: { action in
                    if action == .addExpense {
                        showAddSheet = true
                        HapticFeedback.impact(.medium)
                    } else {
                        router.perform(action)
                    }
                },
                bottomPadding: 16
            )
        }
        .navigationTitle("Finances")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("fin_search_prompt"))
        .toolbar {
            ToolbarItem(placement: .pageMenu) { filterMenu }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("fin_add_transaction")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddFinancialView { await financialService.load() }
        }
        .sheet(item: $editingRecord) { record in
            AddFinancialView(editing: record) { await financialService.load() }
        }
        .alert("Error", isPresented: Binding(
            get: { financialService.error != nil },
            set: { if !$0 { financialService.error = nil } }
        )) {
            Button("OK") { financialService.error = nil }
        } message: { Text(LocalizedStringKey(financialService.error ?? "")) }
        .task {
            await financialService.load()
            // Leases feed the "next payments" strip (rent due dates); load
            // members too so a due rent can carry the tenant's name.
            if let pid = PropertyService.activePropertyId {
                if familyService.members.isEmpty { await familyService.load() }
                await familyService.loadLeases(propertyId: pid)
                // Budgets usually arrive with the app-start batch; make sure
                // they're here before the threshold check below.
                if budgetService.budgets.isEmpty { await budgetService.load(propertyId: pid) }
            }
            checkBudgetThresholds()
        }
    }

    /// Budgets and the fresh month's records are both in memory here — let
    /// the budget service fire its 80%/100% alerts (deduped per category per
    /// calendar month). Same raw-amount totals BudgetView draws.
    private func checkBudgetThresholds() {
        var spent: [String: Double] = [:]
        for r in financialService.currentMonthRecords where r.type == "expense" {
            spent[r.category.lowercased(), default: 0] += r.amount
        }
        budgetService.checkThresholds(spentByCategory: spent)
    }

    /// ONE circle for the page (one-circle law): the type filter that used
    /// to live in a bare toolbar `Menu` — and the tap-to-filter the KPI
    /// tiles used to carry — in a single aggregated popover, with honest
    /// counts from the displayed month. The accent dot only lights for a
    /// narrowed type, never for the default "All".
    private var filterMenu: some View {
        let month = monthRecords
        let incomeCount = month.filter { $0.type == "income" }.count
        let expenseCount = month.filter { $0.type == "expense" }.count
        return GlassFilterButton(isActive: selectedType != nil,
                                 inToolbar: true,
                                 accessibilityLabelKey: "fin_filter_transactions") {
            GlassFilterSection(
                title: "Type",
                options: [
                    GlassPickerOption<String?>(value: nil, icon: "tray.full",
                                               title: String(localized: "All"),
                                               count: month.count),
                    GlassPickerOption<String?>(value: "income", icon: "arrow.down.left",
                                               title: String(localized: "Income"),
                                               count: incomeCount),
                    GlassPickerOption<String?>(value: "expense", icon: "arrow.up.right",
                                               title: String(localized: "Expenses"),
                                               count: expenseCount)
                ],
                selection: $selectedType)
        }
    }
}
