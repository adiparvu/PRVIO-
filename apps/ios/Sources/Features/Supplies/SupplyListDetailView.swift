import SwiftUI

struct SupplyListDetailView: View {
    @Environment(SupplyService.self) private var supplyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ReceiptService.self) private var receiptService
    var list: SupplyList

    @State private var searchText = ""
    @State private var selectedCategory: String? = nil
    @State private var showAddItem = false
    @State private var editingItem: SupplyItem? = nil
    @State private var showCompleted = false
    @State private var priceHistoryTarget: PriceHistoryTarget? = nil

    private var listItems: [SupplyItem] { supplyService.items(for: list.id) }

    private var filtered: [SupplyItem] {
        listItems.filter { item in
            let matchSearch = searchText.isEmpty
                || item.name.matchesSearch(searchText)
                || (item.quantity ?? "").matchesSearch(searchText)
                || SupplyLocation.displayName(for: item.location ?? "").matchesSearch(searchText)
            let matchCat = selectedCategory == nil || item.category == selectedCategory
            return matchSearch && matchCat
        }
    }

    private var pending: [SupplyItem] { filtered.filter { !$0.isCompleted } }
    private var completed: [SupplyItem] { filtered.filter { $0.isCompleted } }

    var body: some View {
        VStack(spacing: 0) {
            if listItems.isEmpty {
                emptyListState
            } else if filtered.isEmpty {
                noResultsState
            } else {
                itemsScroll
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search items…"))
        .toolbar {
            if !listItems.isEmpty {
                ToolbarItem(placement: .pageMenu) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddItem = true; HapticFeedback.impact(.light) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showAddItem) {
            AddSupplyItemSheet(list: list, editingItem: nil)
                .environment(supplyService)
                .environment(propertyService)
                .environment(receiptService)
        }
        .sheet(item: $editingItem) { item in
            AddSupplyItemSheet(list: list, editingItem: item)
                .environment(supplyService)
                .environment(propertyService)
                .environment(receiptService)
        }
        .sheet(item: $priceHistoryTarget) { target in
            ProductPriceHistorySheet(productName: target.name)
                .environment(receiptService)
        }
        .floatingSpeedDial(.supplies)
    }

    // MARK: Toolbar filter

    /// The permanent category chip row folded into the page's one circle
    /// (the one-circle law) — same aggregated popover as Inventory. Options
    /// mirror the retired chips exactly: only categories that actually hold
    /// pending items (or the one currently selected, so it can be cleared)
    /// appear, with their honest counts.
    private var filterButton: some View {
        GlassFilterButton(isActive: selectedCategory != nil, inToolbar: true) {
            GlassFilterSection(title: "Category",
                               options: categoryOptions,
                               selection: $selectedCategory)
        }
    }

    private var categoryOptions: [GlassPickerOption<String?>] {
        var options: [GlassPickerOption<String?>] = [
            .init(value: nil, title: String(localized: "All"))
        ]
        for cat in supplyCategories {
            let count = listItems.filter { $0.category == cat.id && !$0.isCompleted }.count
            if count > 0 || selectedCategory == cat.id {
                options.append(.init(value: cat.id,
                                     title: String(localized: String.LocalizationValue(cat.label)),
                                     count: count))
            }
        }
        return options
    }

    // MARK: Items scroll

    private var itemsScroll: some View {
        ScrollView(showsIndicators: false) {
            // Headers are NOT pinned: they carry no background at all, so
            // they must scroll with their rows instead of floating naked
            // over them (IMG_8562 "nici aici, nici nicăieri").
            LazyVStack(spacing: 0) {
                if !pending.isEmpty {
                    Section {
                        GlassCard(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(pending.enumerated()), id: \.element.id) { idx, item in
                                    SupplyItemRow(
                                        item: item,
                                        isLast: idx == pending.count - 1,
                                        onToggle: { Task { await supplyService.toggleComplete(item); HapticFeedback.success() } },
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
                    } header: {
                        sectionHeader("TO BUY · \(pending.count)")
                    }
                }

                if !completed.isEmpty {
                    Section {
                        if showCompleted {
                            GlassCard(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(completed.enumerated()), id: \.element.id) { idx, item in
                                        SupplyItemRow(
                                            item: item,
                                            isLast: idx == completed.count - 1,
                                            onToggle: { Task { await supplyService.toggleComplete(item); HapticFeedback.selection() } },
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
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    } header: {
                        Button {
                            withAnimation(.spring(response: 0.35)) { showCompleted.toggle() }
                            HapticFeedback.selection()
                        } label: {
                            // Naked text — headers wear no chip, band or
                            // material, ever; the chevron alone carries the
                            // disclosure affordance.
                            HStack(spacing: 6) {
                                Image(systemName: showCompleted ? "chevron.down" : "chevron.right")
                                    .font(AppFont.scaled(10, weight: .semibold))
                                Text("COMPLETED · \(completed.count)")
                                    .font(AppFont.label)
                                    .tracking(0.5)
                            }
                            .foregroundStyle(Color.brandSuccess)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.xl + AppSpacing.xxs)
                            .padding(.vertical, AppSpacing.xs)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isHeader)
                    }
                }

                Spacer(minLength: 120)
            }
            .padding(.top, AppSpacing.md)
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        // Naked text — headers wear no chip, band or material, ever.
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(Color.backdropSecondaryText)
            .tracking(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, AppSpacing.xl + AppSpacing.xxs)
            .padding(.vertical, AppSpacing.xs)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: States

    private var emptyListState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cart")
                .font(AppFont.scaled(48)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No items in this list")
                .font(AppFont.headline).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Text("Tap + to add the first item.")
                .font(AppFont.scaled(13)).foregroundStyle(Color.primary.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(AppFont.scaled(36)).foregroundStyle(Color.primary.opacity(0.12))
            Text("No results")
                .font(AppFont.subheadline).foregroundStyle(Color.primary.opacity(0.4))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
