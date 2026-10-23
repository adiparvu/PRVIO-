import SwiftUI

// MARK: - Category / priority helpers (used by AddSupplyItemSheet, SupplyListDetailView)

// `label` holds a LOCALIZATION KEY, not display text — render sites resolve it
// (Text(LocalizedStringKey:) / String(localized:)) so the shopping form reads
// in the user's language, not English.
let supplyCategories: [(id: String, label: String)] = [
    ("food",        "sup_cat_food"),
    ("cleaning",    "sup_cat_cleaning"),
    ("bathroom",    "sup_cat_bathroom"),
    ("garden",      "sup_cat_garden"),
    ("diy",         "sup_cat_diy"),
    ("electronics", "sup_cat_electronics"),
    ("pet",         "sup_cat_pet"),
    ("other",       "sup_cat_other"),
]

let supplyPriorities: [(id: String, label: String)] = [
    ("low",      "sup_prio_low"),
    ("medium",   "sup_prio_medium"),
    ("high",     "sup_prio_high"),
    ("critical", "sup_prio_critical"),
]

// MARK: - Supplies / Expense Hub

enum ExpenseTab: Hashable { case overview, lists, toBuy, completed }

struct SuppliesView: View {
    @Environment(SupplyService.self) private var supplyService
    @Environment(ReceiptService.self) private var receiptService
    @Environment(PropertyService.self) private var propertyService
    @Environment(PantryService.self) private var pantryService
    @Environment(AppSettings.self) private var appSettings

    // The page OPENS on the daily surface — shopping lists + pantry
    // (IMG_8654, user-decreed); the money dashboard stays one tap away.
    @State private var activeTab: ExpenseTab = .lists
    @State private var showAddList = false
    @State private var showScanner = false
    @State private var showAddReceipt = false
    @State private var showBudgets = false
    @State private var showReports = false
    @State private var searchText = ""
    @State private var priceHistoryTarget: PriceHistoryTarget? = nil
    @State private var editingItem: SupplyItem? = nil

    private var filteredLists: [SupplyList] {
        supplyService.lists.filter { $0.name.matchesSearch(searchText) }
    }

    private var pageTitle: String {
        switch activeTab {
        case .overview:   return String(localized: "expense_title")
        case .lists:      return String(localized: "expense_lists_title")
        case .toBuy:      return String(localized: "De cumpărat")
        case .completed:  return String(localized: "Finalizate")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch activeTab {
            case .overview:
                ExpenseDashboardView(
                    activeTab: $activeTab,
                    showScanner: $showScanner,
                    showAddReceipt: $showAddReceipt,
                    showBudgets: $showBudgets,
                    showReports: $showReports
                )
                .environment(receiptService)
                .environment(propertyService)
                .environment(supplyService)
            case .lists:
                shoppingListsContent
            case .toBuy:
                toBuyContent
            case .completed:
                completedContent
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(pageTitle)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                filterButton
            }
            if activeTab == .lists {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAddList = true; HapticFeedback.impact(.light) } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                    }
                    .accessibilityLabel("Add list")
                }
            }
        }
        .sheet(isPresented: $showAddList) {
            AddSupplyListSheet().environment(supplyService).environment(propertyService)
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScannerView().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showAddReceipt) {
            AddReceiptSheet().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showBudgets) {
            BudgetManagementView().environment(receiptService).environment(propertyService)
        }
        .sheet(isPresented: $showReports) {
            SpendingReportView().environment(receiptService)
        }
        .sheet(item: $priceHistoryTarget) { target in
            ProductPriceHistorySheet(productName: target.name)
                .environment(receiptService)
        }
        .sheet(item: $editingItem) { item in
            AddSupplyItemSheet(list: supplyService.lists.first { $0.id == item.listId },
                               editingItem: item)
                .environment(supplyService)
                .environment(propertyService)
                .environment(receiptService)
        }
        .task {
            if let id = propertyService.primary?.id {
                // Both loads in parallel, both awaited — un-awaited `async let`s
                // are cancelled when the task scope exits, so the lists could
                // arrive empty.
                async let supplies: Void = supplyService.load(propertyId: id)
                async let receipts: Void = receiptService.load(propertyId: id)
                // The pantry card's live stock line reads PantryService, so
                // the surface hydrates it alongside the other two.
                async let pantry: Void = pantryService.load(propertyId: id)
                _ = await (supplies, receipts, pantry)
            }
        }
        .userActivity("com.prvio.shopping") { activity in
            activity.title = String(localized: "Shopping — PRVIO")
            activity.userInfo = ["tab": "shopping"]
            activity.isEligibleForHandoff = true
            // Siri Suggestions may propose reopening this screen at the
            // habitual moment — prediction learns from these publishes.
            activity.isEligibleForPrediction = true
            activity.isEligibleForSearch = true
        }
    }

    // MARK: - Toolbar

    /// One circle, everything (the one-circle law): the four views that used
    /// to sit as a permanent underline strip on the page body, plus the old
    /// "+" menu's one-shot actions (scan / manual receipt / budgets /
    /// reports) — a single aggregated popover, same pattern as Inventory.
    /// Nothing here narrows a list — switching views navigates and the rows
    /// are one-shot — so the trigger never claims the "filtered" accent dot.
    /// View rows are `GlassFilterActionRow`s (not a picker section): picking
    /// a view is navigation, so the popover must dismiss — the mailbox runs
    /// the switch after the dismissal transition. Counts survive as a
    /// " · N" title suffix; no checkmark, the large title already names the
    /// current view.
    private var filterButton: some View {
        GlassFilterButton(inToolbar: true) {
            GlassFilterSectionLabel(titleKey: "View")
            GlassFilterActionRow(icon: "chart.bar.fill",
                                 title: String(localized: "expense_tab_overview")) {
                activeTab = .overview
            }
            GlassFilterActionRow(icon: "list.bullet",
                                 title: String(localized: "expense_tab_lists")
                                    + " · \(supplyService.lists.count)") {
                activeTab = .lists
            }
            GlassFilterActionRow(icon: "cart.fill",
                                 title: String(localized: "De cumpărat")
                                    + " · \(supplyService.totalPending)") {
                activeTab = .toBuy
            }
            GlassFilterActionRow(icon: "checkmark.circle.fill",
                                 title: String(localized: "Finalizate")
                                    + " · \(supplyService.totalCompleted)") {
                activeTab = .completed
            }
            GlassFilterSectionDivider()
            GlassFilterActionRow(icon: "camera.viewfinder",
                                 title: String(localized: "expense_scan_receipt")) {
                showScanner = true
            }
            GlassFilterActionRow(icon: "plus.circle",
                                 title: String(localized: "expense_add_manual")) {
                showAddReceipt = true
            }
            GlassFilterActionRow(icon: "target",
                                 title: String(localized: "expense_manage_budgets")) {
                showBudgets = true
            }
            GlassFilterActionRow(icon: "chart.bar.doc.horizontal",
                                 title: String(localized: "expense_reports")) {
                showReports = true
            }
        }
    }

    // MARK: - Shopping lists

    private var shoppingListsContent: some View {
        Group {
            if propertyService.primary == nil {
                noPropertyState
            } else if supplyService.isLoading && supplyService.lists.isEmpty {
                loadingState
            } else if supplyService.lists.isEmpty {
                emptyListsState
            } else {
                listsScrollContent
            }
        }
    }

    // The approved stage-2 order (IMG_8654): the pantry leads, the active
    // lists follow with their progress, the urgent picks stay by the lists,
    // and the month's money compresses into one card that opens the full
    // dashboard. The receipt scan floats permanently — it feeds BOTH worlds
    // (the pantry stock and the month's ledger).
    private var listsScrollContent: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    if searchText.isEmpty { pantryCard }
                    if searchText.isEmpty { mealPlannerCard }
                    if !filteredLists.isEmpty {
                        listsGrid
                    } else if !searchText.isEmpty {
                        EmptyStateView(icon: "magnifyingglass", title: "No results")
                    }
                    if supplyService.totalPending > 0 { urgentSection }
                    if searchText.isEmpty { monthMoneyCard }
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.lg)
            }
            .refreshable {
                if let id = propertyService.primary?.id {
                    await supplyService.load(propertyId: id)
                }
            }
            scanFAB
        }
    }

    /// The pantry door: real stock, fed automatically by receipt scans.
    /// The subline turns live once stock exists — count + running-low,
    /// straight from PantryService; before that, the honest generic line.
    private var pantryCard: some View {
        NavigationLink(destination: PantryView()) {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "basket.fill")
                        .font(AppFont.scaled(17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .mediaGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("pantry_title")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Group {
                            if pantryService.items.isEmpty {
                                Text("pantry_card_subtitle")
                            } else {
                                Text(verbatim: pantryLiveLine)
                            }
                        }
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// The week's table, one door down from the pantry — ingredients flow
    /// into the lists, cooked meals consume the stock.
    private var mealPlannerCard: some View {
        NavigationLink(destination: MealPlannerView()) {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "fork.knife")
                        .font(AppFont.scaled(17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .mediaGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("meal_planner_title")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        Text("meal_planner_card_subtitle")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var pantryLiveLine: String {
        let count = pantryService.items.count
        var line = count == 1
            ? String(localized: "pantry_one_product")
            : String(format: String(localized: "pantry_stock_fmt"), count)
        let low = pantryService.lowStock.count
        if low > 0 {
            line += " · " + String(format: String(localized: "pantry_low_fmt"), low)
        }
        return line
    }

    /// The month's money, compact (approved stage 2): the CURRENT month's
    /// real total and receipt count, one tap to the full dashboard.
    private var monthMoneyCard: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) { activeTab = .overview }
            HapticFeedback.selection()
        } label: {
            GlassCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar.fill")
                        .font(AppFont.scaled(17, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .mediaGlass(in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("supply_month_money_title")
                            .font(AppFont.subheadline)
                            .foregroundStyle(.primary)
                        let month = receiptService.currentMonthKey
                        let total = receiptService.totalSpent(in: month)
                        let count = receiptService.receiptsForMonth(month).count
                        Text(verbatim: "\(CurrencyService.money(total, code: appSettings.preferredCurrency)) · \(count) \(String(localized: "expense_receipts"))")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(AppFont.captionStrong)
                        .foregroundStyle(Color.primary.opacity(0.25))
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// The one action feeding both worlds — permanent, at thumb reach.
    private var scanFAB: some View {
        Button {
            HapticFeedback.impact(.light)
            showScanner = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(AppFont.scaled(20, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.plain)
        .glassCircle(interactive: true)
        .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        .padding(.trailing, AppSpacing.xl)
        .padding(.bottom, 96)
        .accessibilityLabel(Text("expense_scan_receipt"))
    }

    private var listsGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "supply_section_lists"))
                .font(AppFont.label).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(filteredLists) { list in
                    NavigationLink(destination:
                        SupplyListDetailView(list: list)
                            .environment(supplyService)
                            .environment(propertyService)
                    ) {
                        SupplyListCard(list: list).environment(supplyService)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            Task { await supplyService.deleteList(list) }
                        } label: { Label("Delete list", systemImage: "trash") }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var urgentSection: some View {
        let urgent = supplyService.items
            .filter { item in
                guard !item.isCompleted, item.priority == "critical" || item.priority == "high" else { return false }
                // The compact row shows the item name plus the parent list's
                // name as its subtitle — both must be findable.
                return item.name.matchesSearch(searchText)
                    || (supplyService.lists.first { $0.id == item.listId }?.name ?? "").matchesSearch(searchText)
            }
            .prefix(5)
        if !urgent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Urgent")
                    .font(AppFont.label).foregroundStyle(.secondary).padding(.leading, AppSpacing.xxs)
                GlassCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(urgent.enumerated()), id: \.element.id) { idx, item in
                            compactRow(item, isLast: idx == urgent.count - 1)
                        }
                    }
                }
            }
        }
    }

    private func compactRow(_ item: SupplyItem, isLast: Bool) -> some View {
        let listName = supplyService.lists.first { $0.id == item.listId }?.name ?? ""
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: item.categoryIcon).font(AppFont.captionEmphasis).foregroundStyle(item.categoryColor)
                    .frame(width: 30, height: 30)
                    .glassRoundedRect(7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(AppFont.footnote).foregroundStyle(.primary)
                    Text(listName).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                }
                Spacer()
                RoundedRectangle(cornerRadius: 2, style: .continuous).fill(item.priorityColor).frame(width: 3, height: 22)
            }
            .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
            if !isLast { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 54) }
        }
    }

    // MARK: - To Buy / Completed tabs

    /// SupplyItemRow displays name, quantity badge and the localized
    /// location label — search must reach all three.
    private func matchesItemRowSearch(_ item: SupplyItem) -> Bool {
        item.name.matchesSearch(searchText)
            || (item.quantity ?? "").matchesSearch(searchText)
            || SupplyLocation.displayName(for: item.location ?? "").matchesSearch(searchText)
    }

    private var toBuyContent: some View {
        let pending = supplyService.items.filter { !$0.isCompleted && matchesItemRowSearch($0) }
        return Group {
            if pending.isEmpty && searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cart.badge.checkmark")
                        .font(AppFont.scaled(52)).foregroundStyle(Color.primary.opacity(0.12))
                    Text(String(localized: "supply_all_done"))
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !pending.isEmpty {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(pending.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(
                                            item: item,
                                            isLast: idx == pending.count - 1,
                                            onToggle: { Task { await supplyService.toggleComplete(item) } },
                                            onEdit: { editingItem = item },
                                            onDelete: { Task { await supplyService.deleteItem(item) } },
                                            onPriceHistory: receiptService.receiptItems.isEmpty
                                                ? nil
                                                : { priceHistoryTarget = PriceHistoryTarget(name: item.name) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.xl)
                        } else if !searchText.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
        }
    }

    private var completedContent: some View {
        let done = supplyService.items.filter { $0.isCompleted && matchesItemRowSearch($0) }
        return Group {
            if done.isEmpty && searchText.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(AppFont.scaled(52)).foregroundStyle(Color.primary.opacity(0.12))
                    Text(String(localized: "supply_empty_title"))
                        .font(AppFont.scaled(17, weight: .semibold)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        if !done.isEmpty {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(done.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(
                                            item: item,
                                            isLast: idx == done.count - 1,
                                            onToggle: { Task { await supplyService.toggleComplete(item) } },
                                            onEdit: { editingItem = item },
                                            onDelete: { Task { await supplyService.deleteItem(item) } },
                                            onPriceHistory: receiptService.receiptItems.isEmpty
                                                ? nil
                                                : { priceHistoryTarget = PriceHistoryTarget(name: item.name) }
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, AppSpacing.xl)
                        } else if !searchText.isEmpty {
                            EmptyStateView(icon: "magnifyingglass", title: "No results")
                        }
                        Spacer(minLength: 110)
                    }
                    .padding(.top, AppSpacing.lg)
                }
            }
        }
    }

    // MARK: - States

    private var emptyListsState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "cart.badge.plus").font(AppFont.scaled(56)).foregroundStyle(Color.primary.opacity(0.12))
            Text(String(localized: "supply_empty_title")).font(AppFont.title3).foregroundStyle(Color.primary.opacity(0.6))
            Text(String(localized: "supply_empty_body")).font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled)).multilineTextAlignment(.center)
            Button { showAddList = true } label: {
                Label(String(localized: "supply_add_first"), systemImage: "plus")
                    .font(AppFont.subheadline).foregroundStyle(.primary)
                    .padding(.horizontal, 22).padding(.vertical, 13)
                    .mediaGlass(in: RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, 40)
    }

    private var loadingState: some View {
        VStack { Spacer(); ProgressView().tint(.primary); Spacer() }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noPropertyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "house.slash").font(AppFont.scaled(48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No property added").font(AppFont.headline).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - List card

struct SupplyListCard: View {
    @Environment(SupplyService.self) private var supplyService
    let list: SupplyList

    var body: some View {
        GlassCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [list.swiftColor.opacity(0.65), list.swiftColor.opacity(0.35)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ).frame(height: 72)
                    Image(systemName: list.icon)
                        .font(AppFont.scaled(28, weight: .semibold)).foregroundStyle(.white.opacity(0.92)).padding(AppSpacing.base)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(list.name).font(AppFont.footnoteEmphasis).foregroundStyle(.primary).lineLimit(1)
                    let pending = supplyService.pendingCount(for: list.id)
                    Text(pending == 0 ? String(localized: "supply_all_done") : "\(pending) \(String(localized: "supply_to_buy_short"))")
                        .font(AppFont.scaled(11))
                        .foregroundStyle(pending == 0 ? Color.brandSuccess : Color.primary.opacity(AppOpacity.secondaryText))
                }
                .padding(.horizontal, AppSpacing.md).padding(.vertical, 10)
            }
        }
    }
}

// MARK: - Item row

struct SupplyItemRow: View {
    let item: SupplyItem
    let isLast: Bool
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Optional "price history" context action — offered only where the
    /// caller can actually present the history (real receipt data).
    var onPriceHistory: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Custom horizontal-drag reveal (same pattern as HubActivityCard): the
    // row lives inside ScrollView-hosted cards, where `.swipeActions`
    // silently no-ops — it only works in List.
    @State private var offsetX: CGFloat = 0
    @State private var revealed = false

    /// Three 46pt buttons + 2×sm spacing + breathing room.
    private let actionSpan: CGFloat = 170

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                swipeActionButtons
                    .opacity(offsetX < -12 ? 1 : 0)
                    .accessibilityHidden(offsetX >= -12)
                rowContent
                    .offset(x: offsetX)
                    .gesture(swipeGesture)
                    .onTapGesture {
                        if revealed { close() }
                    }
            }
            if !isLast { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 58) }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(22))
                    .foregroundStyle(item.isCompleted
                        ? Color.brandSuccess
                        : Color.primary.opacity(0.28))
                    .symbolEffect(.bounce, value: item.isCompleted)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(AppFont.scaled(15)).foregroundStyle(item.isCompleted ? Color.primary.opacity(AppOpacity.disabled) : .primary)
                        .strikethrough(item.isCompleted, color: .secondary).lineLimit(1)
                    if let qty = item.quantity, !qty.isEmpty {
                        QuantityBadge(text: qty)
                    }
                }
                if let loc = item.location, !loc.isEmpty {
                    Label(SupplyLocation.displayName(for: loc), systemImage: "mappin")
                        .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            Spacer()
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(item.isCompleted ? Color.clear : item.priorityColor).frame(width: 3, height: 24)
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
        .contextMenu {
            Button { onEdit() } label: { Label("Edit", systemImage: "pencil") }
            Button { onToggle() } label: {
                Label(LocalizedStringKey(item.isCompleted ? "Mark as incomplete" : "Mark as complete"),
                      systemImage: item.isCompleted ? "circle" : "checkmark.circle")
            }
            if let onPriceHistory {
                Button { onPriceHistory() } label: {
                    Label(String(localized: "price_history_title"),
                          systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            Divider()
            Button(role: .destructive) { onDelete() } label: { Label("Delete", systemImage: "trash") }
        }
    }

    private var swipeActionButtons: some View {
        HStack(spacing: AppSpacing.sm) {
            Button {
                onToggle()
                close()
            } label: {
                Image(systemName: item.isCompleted ? "arrow.uturn.backward" : "checkmark")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(item.isCompleted ? Color.orange : Color.brandSuccess)
                    .frame(width: 46, height: 46)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(item.isCompleted ? "Undo" : "Complete")))

            Button {
                onEdit()
                close()
            } label: {
                Image(systemName: "pencil")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 46, height: 46)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Edit"))

            Button(role: .destructive) {
                onDelete()
                close()
            } label: {
                Image(systemName: "trash")
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(Color.brandDanger)
                    .frame(width: 46, height: 46)
                    .glassCircle()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
        .padding(.trailing, AppSpacing.xxs)
    }

    /// Horizontal-only swipe that reveals the actions; vertical drags stay
    /// with the ScrollView.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = revealed ? -actionSpan : 0
                offsetX = max(-actionSpan - 20, min(0, base + value.translation.width))
            }
            .onEnded { _ in
                let open = offsetX < -actionSpan / 2
                withAnimation(reduceMotion ? nil : AppMotion.state) {
                    revealed = open
                    offsetX = open ? -actionSpan : 0
                }
            }
    }

    private func close() {
        withAnimation(reduceMotion ? nil : AppMotion.state) {
            revealed = false
            offsetX = 0
        }
    }
}
