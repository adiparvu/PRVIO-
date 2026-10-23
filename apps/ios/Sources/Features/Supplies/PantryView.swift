import SwiftUI

// MARK: - Pantry (real household stock)
//
// Receipt scans grow these numbers automatically; this page is where the
// household consumes: − and + step in the product's natural unit, low stock
// floats to the top, and the add/edit sheet sets the alert threshold.

struct PantryView: View {
    @Environment(PantryService.self) private var pantryService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ReceiptService.self) private var receiptService

    @State private var searchText = ""
    @State private var editingItem: PantryItem?
    @State private var showAddSheet = false
    @State private var priceHistoryTarget: PriceHistoryTarget? = nil

    private var filtered: [PantryItem] {
        pantryService.items.filter { item in
            item.name.matchesSearch(searchText)
                || item.quantityDisplay.matchesSearch(searchText)
                || (PantryCategory.all.first(where: { $0.id == item.category })?.label ?? "")
                    .matchesSearch(searchText)
        }
    }

    private var low: [PantryItem] { filtered.filter(\.isLow) }

    private typealias CategoryGroup = (category: (id: String, label: String, icon: String), items: [PantryItem])

    // Explicit loop: the Swift 6.4 type checker crashes ("failed to produce
    // diagnostic") inferring a labeled nested tuple out of compactMap.
    private var byCategory: [CategoryGroup] {
        var groups: [CategoryGroup] = []
        for cat in PantryCategory.all {
            let hits = filtered.filter { $0.category == cat.id && !$0.isLow }
            if !hits.isEmpty { groups.append((category: cat, items: hits)) }
        }
        return groups
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            content
        }
        .navigationTitle(Text("pantry_title"))
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: Text("pantry_search"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    HapticFeedback.impact(.light)
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("pantry_add"))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            PantryItemSheet(item: nil)
                .environment(pantryService)
                .environment(propertyService)
        }
        .sheet(item: $editingItem) { item in
            PantryItemSheet(item: item)
                .environment(pantryService)
                .environment(propertyService)
        }
        .sheet(item: $priceHistoryTarget) { target in
            ProductPriceHistorySheet(productName: target.name)
                .environment(receiptService)
        }
        .task {
            if let id = propertyService.primary?.id {
                await pantryService.load(propertyId: id)
            }
            reindexConsumption()
        }
        // The receipt history loads elsewhere (and can land after this
        // page appears); a count change is the cheap signal to re-derive.
        .onChange(of: receiptService.receiptItems.count) {
            reindexConsumption()
        }
    }

    /// Re-derives the consumption index from the receipts already in
    /// memory — a pure client-side pass, no fetch.
    private func reindexConsumption() {
        pantryService.indexConsumption(receipts: receiptService.receipts,
                                       receiptItems: receiptService.receiptItems)
    }

    @ViewBuilder
    private var content: some View {
        if pantryService.items.isEmpty && !pantryService.isLoading {
            emptyState
        } else if filtered.isEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "No results")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: AppSpacing.lg) {
                    if !low.isEmpty {
                        section(title: Text("pantry_low_section"), items: low, tint: .red)
                    }
                    ForEach(byCategory, id: \.category.id) { group in
                        section(title: Text(verbatim: group.category.label),
                                items: group.items, tint: nil)
                    }
                    Spacer(minLength: 90)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .refreshable {
                if let id = propertyService.primary?.id {
                    await pantryService.load(propertyId: id)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.base) {
            EmptyStateView(icon: "basket", title: "pantry_empty_title")
            Text("pantry_empty_body")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .multilineTextAlignment(.center)
                .padding(.horizontal, AppSpacing.xxl)
        }
    }

    private func section(title: Text, items: [PantryItem], tint: Color?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            title
                .font(AppFont.label)
                .foregroundStyle(tint ?? .secondary)
                .padding(.leading, AppSpacing.xxs)

            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        row(item)
                        if idx < items.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.05))
                                .frame(height: 0.5).padding(.leading, 60)
                        }
                    }
                }
            }
        }
    }

    private func row(_ item: PantryItem) -> some View {
        // Display-layer inference only: the badge shows the model's best
        // estimate of what's really on the shelf, while the stored number —
        // the one −/+ and the sheet edit — stays authoritative on the server.
        let estimate = pantryService.consumption(for: item)
        let shownQuantity = quantityText(for: item, estimate: estimate)
        let runsOut = runsOutText(estimate)
        return HStack(spacing: 12) {
            Group {
                if let emoji = item.emoji, !emoji.isEmpty {
                    Text(emoji).font(AppFont.scaled(18))
                } else {
                    Image(systemName: item.categoryIcon)
                        .font(AppFont.footnoteEmphasis)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(item.isLow ? Color.red : Color.primary.opacity(AppOpacity.emphasis))
                }
            }
            .frame(width: 34, height: 34)
            .mediaGlass(in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(AppFont.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                // The module's one quantity treatment; the accent only
                // marks the pantry's real low-stock state.
                QuantityBadge(text: shownQuantity, isLow: item.isLow)
                if let runsOut {
                    Text(verbatim: runsOut)
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            stepButton(icon: "minus", enabled: item.quantity > 0) {
                Task { await pantryService.adjust(item, by: -item.step) }
            }
            stepButton(icon: "plus", enabled: true) {
                Task { await pantryService.adjust(item, by: item.step) }
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
        .onTapGesture { editingItem = item }
        .contextMenu {
            if !receiptService.receiptItems.isEmpty {
                Button {
                    priceHistoryTarget = PriceHistoryTarget(name: item.name)
                } label: {
                    Label(String(localized: "price_history_title"),
                          systemImage: "chart.line.uptrend.xyaxis")
                }
            }
            Button(role: .destructive) {
                Task { await pantryService.deleteItem(item) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: ["\(item.name), \(shownQuantity)", runsOut]
            .compactMap { $0 }.joined(separator: ", ")))
    }

    /// The badge's number: the inferred effective stock when the model has
    /// a pace, the stored quantity otherwise — formatted identically either
    /// way through the item's own display logic.
    private func quantityText(for item: PantryItem,
                              estimate: PantryConsumptionModel.Estimate) -> String {
        guard estimate.dailyPace != nil else { return item.quantityDisplay }
        var proxy = item
        proxy.quantity = estimate.effectiveQuantity
        return proxy.quantityDisplay
    }

    /// "se termină în ~N zile" — only when the model knows a pace and the
    /// end is near enough (≤ 14 days but not already at zero) to be worth
    /// a line.
    private func runsOutText(_ estimate: PantryConsumptionModel.Estimate) -> String? {
        guard let days = estimate.daysUntilEmpty, days > 0, days <= 14 else { return nil }
        return String(format: String(localized: "pantry_runs_out_fmt"), days)
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: icon)
                .font(AppFont.captionEmphasis)
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.25))
                .frame(width: 30, height: 30)
                .mediaGlass(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(Text(icon == "plus" ? "pantry_add_one" : "pantry_consume_one"))
    }
}

// MARK: - Add / edit sheet

private struct PantryItemSheet: View {
    @Environment(PantryService.self) private var pantryService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    let item: PantryItem?

    @State private var name: String = ""
    @State private var quantity: Double = 1
    @State private var unit: String = "buc"
    @State private var category: String = "food"
    @State private var alertEnabled = false
    @State private var minQuantity: Double = 1
    @State private var isSaving = false

    private var step: Double { unit == "buc" ? 1 : 0.5 }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    field(label: "pantry_field_name") {
                        TextField(String(localized: "pantry_name_placeholder"), text: $name)
                            .font(AppFont.scaled(16))
                            .padding(AppSpacing.base)
                            .background(Color.primary.opacity(AppOpacity.subtleFill),
                                        in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    field(label: "pantry_field_unit") {
                        HStack(spacing: 8) {
                            unitChip("buc", label: "pantry_unit_pieces")
                            unitChip("kg", label: "pantry_unit_kg")
                            unitChip("l", label: "pantry_unit_l")
                        }
                    }

                    field(label: "pantry_field_quantity") {
                        HStack {
                            Text(verbatim: quantityText)
                                .font(AppFont.scaled(24, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Spacer()
                            Stepper("", value: $quantity, in: 0...9999, step: step)
                                .labelsHidden()
                        }
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, AppSpacing.sm)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    field(label: "pantry_field_category") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(PantryCategory.all, id: \.id) { cat in
                                    let selected = category == cat.id
                                    GlassFilterChip(label: cat.label,
                                                    systemImage: selected ? "checkmark" : cat.icon,
                                                    isSelected: selected) {
                                        HapticFeedback.selection()
                                        withAnimation(.snappy(duration: 0.2)) { category = cat.id }
                                    }
                                }
                            }
                        }
                    }

                    field(label: "pantry_field_alert") {
                        VStack(spacing: AppSpacing.sm) {
                            Toggle(isOn: $alertEnabled.animation(.snappy)) {
                                Text("pantry_alert_toggle")
                                    .font(AppFont.footnote)
                            }
                            if alertEnabled {
                                HStack {
                                    Text("pantry_alert_below")
                                        .font(AppFont.footnote)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(verbatim: minText)
                                        .font(AppFont.scaled(16, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Stepper("", value: $minQuantity, in: 0...999, step: step)
                                        .labelsHidden()
                                }
                            }
                        }
                        .padding(AppSpacing.base)
                        .background(Color.primary.opacity(AppOpacity.subtleFill),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }

                    GlassWideButton(icon: "checkmark",
                                    label: item == nil ? "pantry_save_add" : "pantry_save_edit",
                                    isBusy: isSaving) {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)

                    if let item {
                        Button(role: .destructive) {
                            Task {
                                await pantryService.deleteItem(item)
                                dismiss()
                            }
                        } label: {
                            Text("pantry_delete")
                                .font(AppFont.scaled(15))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, AppSpacing.md)
                        }
                        .buttonStyle(.plain)
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
            .navigationTitle(item == nil ? Text("pantry_add") : Text("pantry_edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .sheetGround()
        .onAppear {
            guard let item else { return }
            name = item.name
            quantity = item.quantity
            unit = item.unit
            category = item.category
            if let min = item.minQuantity {
                alertEnabled = true
                minQuantity = min
            }
        }
    }

    private var quantityText: String {
        let display = unit == "buc" ? String(format: "%.0f", quantity)
            : (quantity == quantity.rounded() ? String(format: "%.0f", quantity) : String(format: "%.1f", quantity))
        return unit == "buc" ? display : "\(display) \(unit)"
    }

    private var minText: String {
        minQuantity == minQuantity.rounded()
            ? String(format: "%.0f", minQuantity)
            : String(format: "%.1f", minQuantity)
    }

    private func field(label: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
            content()
        }
    }

    // Selection chips: stroke + checkmark, never a colored fill.
    private func unitChip(_ value: String, label: LocalizedStringKey) -> some View {
        let selected = unit == value
        return Button {
            HapticFeedback.selection()
            withAnimation(.snappy(duration: 0.2)) { unit = value }
        } label: {
            HStack(spacing: 5) {
                if selected {
                    Image(systemName: "checkmark").font(AppFont.scaled(11, weight: .bold))
                }
                Text(label).font(AppFont.scaled(13, weight: selected ? .semibold : .regular))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, AppSpacing.md).padding(.vertical, 7)
            .background(
                Capsule().strokeBorder(
                    selected ? Color.primary.opacity(0.35) : Color.primary.opacity(AppOpacity.subtleFill),
                    lineWidth: selected ? 1.2 : 0.7)
            )
        }
        .buttonStyle(.plain)
    }

    private func save() async {
        guard let propId = propertyService.primary?.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }

        if var existing = item {
            existing.name = trimmed
            existing.normalizedName = ReceiptProductLexicon.normalize(trimmed)
            existing.quantity = quantity
            existing.unit = unit
            existing.category = category
            existing.minQuantity = alertEnabled ? minQuantity : nil
            await pantryService.updateItem(existing)
        } else {
            let payload = NewPantryItemPayload(
                propertyId: propId, name: trimmed,
                normalizedName: ReceiptProductLexicon.normalize(trimmed),
                quantity: quantity, unit: unit, category: category,
                minQuantity: alertEnabled ? minQuantity : nil, emoji: nil)
            _ = try? await pantryService.addItem(payload)
        }
        HapticFeedback.success()
        dismiss()
    }
}
