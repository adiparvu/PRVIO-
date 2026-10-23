import SwiftUI
import VisionKit

// MARK: - Main View

struct InventoryView: View {
    var autoScan: Bool = false
    var autoAdd: Bool = false
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router
    @Environment(InventoryService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(DocumentService.self) private var documentService
    @State private var status: StatusFilter?
    @State private var selectedCategory: String?
    @State private var selectedLocation: String?
    @AppStorage("inventory.sort") private var sortRaw = InvSort.recent.rawValue
    @State private var searchText = ""
    @State private var showAdd = false
    @State private var showScanner = false
    @State private var selectedItem: InventoryItem?
    @State private var editItem: InventoryItem?
    @State private var loanItem: InventoryItem?
    @State private var deleteCandidate: InventoryItem?
    @State private var scannedUnknown = false
    @State private var didAutoScan = false
    @State private var didAutoAdd = false
    /// QR-label picker (IMG_8588): printing opens a selection step —
    /// individual items + Select All — instead of printing the current
    /// slice blind.
    @State private var showQRPicker = false
    /// The picker's confirmed choice, printed from the sheet's onDismiss.
    @State private var qrPendingSelection: [InventoryItem]?
    private let favorites = InventoryFavorites.shared

    /// Cross-cutting slices (favorites / loaned / warranty). One at a time —
    /// they answer different questions — but each combines freely with a
    /// category, a location and the search text.
    enum StatusFilter { case favorites, loaned, warranty }

    enum InvSort: String, CaseIterable {
        case recent, name, value, location

        /// Same catalog keys the sort menu resolved, as plain strings for
        /// `GlassPickerOption.title`.
        var title: String {
            switch self {
            case .recent:   return String(localized: "inv_sort_recent")
            case .name:     return String(localized: "inv_sort_name")
            case .value:    return String(localized: "inv_sort_value")
            case .location: return String(localized: "inv_sort_location")
            }
        }
        var icon: String {
            switch self {
            case .recent:   return "clock"
            case .name:     return "textformat"
            case .value:    return "eurosign.circle"
            case .location: return "mappin.circle"
            }
        }
    }

    private var sort: InvSort { InvSort(rawValue: sortRaw) ?? .recent }
    private var hasActiveFilter: Bool { status != nil || selectedCategory != nil || selectedLocation != nil }

    // MARK: Filtering + sorting

    private var filtered: [InventoryItem] {
        var base = service.items
        switch status {
        case .favorites: base = base.filter { favorites.isFavorite($0.id) }
        case .loaned:    base = base.filter(\.isLoaned)
        case .warranty:  base = base.filter { $0.warrantyExpiresAt != nil }
        case nil:        break
        }
        if let cat = selectedCategory { base = base.filter { $0.category == cat } }
        if let loc = selectedLocation { base = base.filter { $0.location == loc } }
        if !searchText.isEmpty {
            base = base.filter { item in
                var haystack: [String] = [
                    item.name, item.brand, item.serialNumber,
                    item.category, item.location,
                    InventoryLabels.category(item.category),
                    InventoryLabels.location(item.location),
                    item.currentLoan?.borrowerName ?? ""
                ]
                if item.purchasePrice > 0 {
                    haystack.append(CurrencyService.money(item.purchasePrice, code: "EUR", whole: true))
                }
                if item.warrantyStatus == .expiringSoon, let exp = item.warrantyExpiresAt {
                    haystack.append(exp.formatted(.dateTime.day().month(.abbreviated)))
                }
                return haystack.contains { $0.matchesSearch(searchText) }
            }
        }
        return sorted(base)
    }

    private func sorted(_ items: [InventoryItem]) -> [InventoryItem] {
        switch sort {
        case .recent:
            // The service delivers newest-first (created_at desc). The one
            // exception: the warranty slice defaults to soonest-expiring
            // first — the order the user checks under time pressure.
            if status == .warranty {
                return items.sorted {
                    ($0.warrantyExpiresAt ?? .distantFuture) < ($1.warrantyExpiresAt ?? .distantFuture)
                }
            }
            return items
        case .name:
            return items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .value:
            return items.sorted {
                $0.purchasePrice != $1.purchasePrice
                    ? $0.purchasePrice > $1.purchasePrice
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        case .location:
            return items.sorted {
                let l0 = InventoryLabels.location($0.location)
                let l1 = InventoryLabels.location($1.location)
                return l0 != l1
                    ? l0.localizedStandardCompare(l1) == .orderedAscending
                    : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                // The old stat-tile row (value/items/loaned/warranties) is
                // gone (IMG_8548) — its filter shortcuts live in the filter
                // circle's popover now, and the page opens straight on the
                // list.
                if service.items.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    VStack {
                        Spacer()
                        Text("inv_no_results")
                            .font(AppFont.scaled(16))
                            .foregroundStyle(Color.primary.opacity(0.4))
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    // The page ZStack aligns .bottomTrailing (for the FAB), so
                    // a hugging column gets pinned to the right edge — it must
                    // claim the full width to actually center (IMG_8627).
                    .frame(maxWidth: .infinity)
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            ForEach(filtered) { item in
                                InventoryRow(item: item, isFavorite: favorites.isFavorite(item.id))
                                    .onTapGesture { selectedItem = item }
                                    .contextMenu {
                                        Button { selectedItem = item } label: {
                                            Label("View", systemImage: "eye")
                                        }
                                        Button { editItem = item } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        Button {
                                            HapticFeedback.impact(.light)
                                            favorites.toggle(item.id)
                                        } label: {
                                            if favorites.isFavorite(item.id) {
                                                Label("Remove from Favorites", systemImage: "star.slash")
                                            } else {
                                                Label("Add to Favorites", systemImage: "star")
                                            }
                                        }
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); Task { await service.markReturned(item) } } label: {
                                                Label("Returned", systemImage: "checkmark.circle")
                                            }
                                        } else {
                                            Button { HapticFeedback.impact(.medium); loanItem = item } label: {
                                                Label("inv_lend_action", systemImage: "arrow.uturn.right.circle")
                                            }
                                        }
                                        Divider()
                                        Button(role: .destructive) { deleteCandidate = item } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    } preview: {
                                        InventoryItemPreview(item: item)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) { HapticFeedback.warning(); Task { await service.delete(item) } } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        if item.isLoaned {
                                            Button { HapticFeedback.success(); Task { await service.markReturned(item) } } label: { Label("Returned", systemImage: "checkmark.circle") }
                                                .tint(Color.brandSuccess)
                                        } else {
                                            Button { HapticFeedback.impact(.medium); loanItem = item } label: { Label("inv_lend_action", systemImage: "arrow.uturn.right.circle") }
                                                .tint(.accentColor)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl).padding(.bottom, 110)
                    }
                    .refreshable {
                        if let pid = PropertyService.activePropertyId {
                            await service.load(propertyId: pid)
                        }
                    }
                }
            }
            FloatingSpeedDial(
                actions: appSettings.fabVisible(.inventory) ? appSettings.fabActions(.inventory) : [],
                onSelect: { action in
                    switch action {
                    case .scan:    showScanner = true
                    case .addItem: showAdd = true
                    default:       router.perform(action)
                    }
                },
                bottomPadding: 16
            )
        }
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            if !service.items.isEmpty {
                ToolbarItem(placement: .pageMenu) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("Add item")
            }
        }
        .sheet(isPresented: $showAdd) { AddInventorySheet { item in Task { await service.add(item) } } }
        // QR labels go through an explicit SELECTION step (IMG_8588):
        // individual items or Select All. The print panel presents from
        // onDismiss — after the sheet's dismissal transition, so UIKit
        // never drops the presentation.
        .sheet(isPresented: $showQRPicker, onDismiss: {
            guard let chosen = qrPendingSelection else { return }
            qrPendingSelection = nil
            printQRLabels(chosen)
        }) {
            QRLabelPickerSheet(items: service.items,
                               preselected: Set(filtered.map(\.id)),
                               pending: $qrPendingSelection)
        }
        .fullScreenCover(isPresented: $showScanner) {
            QRScannerSheet { qrValue in
                showScanner = false
                // A plant label scanned with the in-app scanner opens the
                // same scan-landing sheet the camera path uses.
                if let pid = Self.plantId(fromScanned: qrValue) {
                    HapticFeedback.success()
                    router.presentScanLanding(.plant(pid))
                } else if let found = resolveScanned(qrValue) {
                    HapticFeedback.success()
                    selectedItem = found
                } else {
                    HapticFeedback.error()
                    scannedUnknown = true
                }
            }
        }
        .sheet(item: $selectedItem) { item in ItemDetailView(item: item, service: service) }
        // A scanned QR label (universal link / prvio://inventory/<id>) parks
        // its item id on the router — open the detail the moment the item is
        // available (immediately when hydrated, or as soon as load lands).
        .onAppear { openPendingDeepLinkItem() }
        // The page owns its data need (lesson of the b1156 DM fix): if the
        // startup orchestration's inventory load was cancelled or failed,
        // self-heal here instead of presenting a silent, wrong empty state.
        .task {
            guard service.items.isEmpty, !service.isLoading,
                  let pid = PropertyService.activePropertyId else { return }
            await service.load(propertyId: pid)
        }
        .onChange(of: router.pendingInventoryItemId) { _, _ in openPendingDeepLinkItem() }
        .onChange(of: service.items.count) { _, _ in openPendingDeepLinkItem() }
        .sheet(item: $editItem) { item in
            AddInventorySheet(editing: item) { updated in Task { await service.update(updated) } }
        }
        .sheet(item: $loanItem) { item in
            LoanItemSheet(suggestions: service.items.recentBorrowers) { borrower, returnDate in
                Task { await service.loanOut(item, to: borrower, expectedReturn: returnDate) }
            }
        }
        .confirmationDialog("Delete this item?", isPresented: .init(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let item = deleteCandidate {
                    HapticFeedback.warning()
                    Task { await service.delete(item) }
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .alert("Item not found", isPresented: $scannedUnknown) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("This QR code doesn't match any item in your inventory.")
        }
        .onAppear {
            if autoScan && !didAutoScan { didAutoScan = true; showScanner = true }
            if autoAdd && !didAutoAdd   { didAutoAdd = true; showAdd = true }
        }
    }

    // MARK: - Toolbar menus

    /// ONE aggregated control replaces both the chip row and the old sort
    /// menu: every slice (status / category / location) plus the sort order,
    /// in a single popover visit. The accent dot reflects narrowing filters
    /// only — a non-default sort reorders the same items, it never narrows
    /// the list, so it must not claim "filtered".
    private var filterButton: some View {
        let counts = filterCounts
        return GlassFilterButton(isActive: hasActiveFilter, inToolbar: true) {
            // Prototype (menu-in-menu): the four facets each drill in to their
            // options instead of stacking as four scrolling sections. The root
            // shows each facet's current value at a glance; share/print stay in
            // the footer, one tap from the root.
            GlassDrillMenu(entries: [
                .facet(id: "status", icon: "circle.lefthalf.filled", title: "Status",
                       options: statusOptions(counts), selection: $status,
                       isNarrowed: status != nil),
                .facet(id: "category", icon: "square.grid.2x2", title: "Category",
                       options: categoryOptions(counts), selection: $selectedCategory,
                       isNarrowed: selectedCategory != nil),
                .facet(id: "location", icon: "mappin", title: "Location",
                       options: locationOptions(counts), selection: $selectedLocation,
                       isNarrowed: selectedLocation != nil),
                .facet(id: "sort", icon: "arrow.up.arrow.down", title: "inv_sort_by",
                       options: sortOptions, selection: $sortRaw,
                       isNarrowed: false)
            ]) {
                // Share/export live in the SAME popover (IMG_8546) — one button
                // holds everything the page can do to its list.
                GlassFilterSectionDivider()
                GlassFilterSectionLabel(titleKey: "inv_share_print")
                GlassFilterActionRow(icon: "doc.richtext",
                                     title: String(localized: "inv_report_action")) {
                    shareReport()
                }
                GlassFilterActionRow(icon: "shield.lefthalf.filled",
                                     title: String(localized: "inv_dossier_action")) {
                    shareDossier()
                }
                GlassFilterActionRow(icon: "qrcode",
                                     title: String(localized: "inv_qr_labels_action")) {
                    showQRPicker = true
                }
            }
        }
    }

    /// Full inventory, grouped by category with subtotals — the document you
    /// hand an insurer, so it always covers every item, not the current slice.
    private func shareReport() {
        guard let url = InventoryExport.makeReportPDF(
            items: service.items,
            propertyName: propertyService.primary?.name
        ) else { return }
        SystemActions.share([url])
    }

    /// The complete insurance dossier: property identity + full inventory
    /// with purchase/warranty evidence + supporting documents. Documents may
    /// not be hydrated yet if that page was never opened this session — load
    /// them first so the dossier never silently omits the paperwork.
    private func shareDossier() {
        Task {
            if documentService.documents.isEmpty { await documentService.load() }
            guard let url = await InsuranceDossier.makePDF(
                items: service.items,
                property: propertyService.primary,
                documents: documentService.documents
            ) else { return }
            SystemActions.share([url])
        }
    }

    /// Prints one A4 sheet of QR labels for an EXPLICIT selection — the
    /// picker seeds it with the current slice, then the user narrows or
    /// selects all (IMG_8588).
    private func printQRLabels(_ items: [InventoryItem]) {
        guard let data = InventoryExport.makeQRLabelsPDF(items: items) else { return }
        SystemActions.print(data: data, jobName: String(localized: "inv_qr_labels_job"))
    }

    // MARK: - Scan resolution

    /// The service resolves legacy formats (`?id=` and `prvio://inventory/`);
    /// current labels encode `https://…/i/<uuid>`, whose id rides in the last
    /// path component — without this, the app couldn't find its own codes.
    /// Opens the item a deep-linked QR label asked for, once it exists in
    /// the loaded set; an id from another property clears without effect.
    private func openPendingDeepLinkItem() {
        guard let iid = router.pendingInventoryItemId else { return }
        guard !service.items.isEmpty else { return }
        router.pendingInventoryItemId = nil
        if let found = service.items.first(where: { $0.id == iid }) {
            HapticFeedback.success()
            selectedItem = found
        }
    }

    private func resolveScanned(_ value: String) -> InventoryItem? {
        if let hit = service.itemByQR(value) { return hit }
        if let last = value.split(separator: "/").last,
           let id = UUID(uuidString: String(last)) {
            return service.items.first { $0.id == id }
        }
        return nil
    }

    /// A plant label: https://xparvu.com/p/<uuid> or prvio://plant/<uuid>.
    static func plantId(fromScanned value: String) -> UUID? {
        guard let url = URL(string: value) else { return nil }
        if url.scheme == "https", url.host == "xparvu.com" {
            let parts = url.pathComponents.filter { $0 != "/" }
            guard parts.first == "p" else { return nil }
            return parts.dropFirst().first.flatMap(UUID.init(uuidString:))
        }
        if url.scheme == "prvio", url.host == "plant" {
            return url.pathComponents.filter { $0 != "/" }.first.flatMap(UUID.init(uuidString:))
        }
        return nil
    }

    // MARK: - Filter options

    /// Everything the chip row could slice by, unchanged: the three status
    /// slices, then the categories and locations that actually hold items
    /// (real counts, never a dead row). Each section's "All" row carries the
    /// nil selection that clearing a chip used to produce, so status +
    /// category + location + search still combine freely.
    private func statusOptions(_ counts: FilterCounts) -> [GlassPickerOption<StatusFilter?>] {
        [.init(value: nil, title: String(localized: "inv_filter_all")),
         .init(value: .favorites, icon: "star.fill",
               title: String(localized: "inv_filter_favorites"), count: counts.favorites),
         .init(value: .loaned, icon: "arrow.uturn.right.circle",
               title: String(localized: "inv_filter_loaned"), count: counts.loaned),
         .init(value: .warranty, icon: "checkmark.shield",
               title: String(localized: "inv_filter_warranty"), count: counts.warranty)]
    }

    private func categoryOptions(_ counts: FilterCounts) -> [GlassPickerOption<String?>] {
        var options: [GlassPickerOption<String?>] = [
            .init(value: nil, title: String(localized: "inv_filter_all"))
        ]
        for cat in InventoryCatalog.categories where counts.categories[cat] != nil {
            options.append(.init(value: cat, icon: InventoryCatalog.icon(for: cat),
                                 title: InventoryLabels.category(cat),
                                 count: counts.categories[cat]))
        }
        return options
    }

    private func locationOptions(_ counts: FilterCounts) -> [GlassPickerOption<String?>] {
        var options: [GlassPickerOption<String?>] = [
            .init(value: nil, title: String(localized: "inv_filter_all"))
        ]
        for loc in orderedLocations(counts.locations) {
            options.append(.init(value: loc, icon: "mappin",
                                 title: InventoryLabels.location(loc),
                                 count: counts.locations[loc]))
        }
        return options
    }

    private var sortOptions: [GlassPickerOption<String>] {
        InvSort.allCases.map { .init(value: $0.rawValue, icon: $0.icon, title: $0.title) }
    }

    /// Known locations keep their canonical order; free-form ones (from older
    /// data) follow, alphabetically.
    private func orderedLocations(_ present: [String: Int]) -> [String] {
        let known = InventoryCatalog.locations.filter { present[$0] != nil }
        let extra = present.keys.filter { !InventoryCatalog.locations.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return known + extra
    }

    private struct FilterCounts {
        var favorites = 0
        var loaned = 0
        var warranty = 0
        var categories: [String: Int] = [:]
        var locations: [String: Int] = [:]
    }

    /// One pass over the items builds every option badge.
    private var filterCounts: FilterCounts {
        var c = FilterCounts()
        for item in service.items {
            if favorites.isFavorite(item.id) { c.favorites += 1 }
            if item.isLoaned { c.loaned += 1 }
            if item.warrantyExpiresAt != nil { c.warranty += 1 }
            c.categories[item.category, default: 0] += 1
            c.locations[item.location, default: 0] += 1
        }
        return c
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "cube.box.fill").font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.18))
            Text("No inventory yet").font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
            Button("Add first item") { showAdd = true }.font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - QR label selection (IMG_8588)

/// The explicit selection step before printing QR labels: every item with a
/// native checkmark row, Select All / Deselect All in one toggle, and a
/// prominent Print carrying the honest count. Seeded with the page's current
/// slice so the old "filter, then print" flow is still one tap.
private struct QRLabelPickerSheet: View {
    let items: [InventoryItem]
    let preselected: Set<UUID>
    /// The parent prints this from onDismiss (a print panel presented while
    /// the sheet is still dismissing is silently dropped by UIKit).
    @Binding var pending: [InventoryItem]?

    @State private var selection: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss

    private var allSelected: Bool { selection.count == items.count && !items.isEmpty }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(items) { item in
                        Button {
                            HapticFeedback.selection()
                            if selection.contains(item.id) { selection.remove(item.id) }
                            else { selection.insert(item.id) }
                        } label: {
                            HStack(spacing: AppSpacing.sm) {
                                Image(systemName: item.categoryIcon)
                                    .font(AppFont.scaled(15, weight: .medium))
                                    .foregroundStyle(item.categoryColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: item.name)
                                        .font(AppFont.scaled(15))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text(verbatim: item.location)
                                        .font(AppFont.scaled(12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: selection.contains(item.id)
                                      ? "checkmark.circle.fill" : "circle")
                                    .font(AppFont.scaled(20))
                                    .foregroundStyle(selection.contains(item.id)
                                                     ? Color.accentColor
                                                     : Color.primary.opacity(AppOpacity.disabled))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Button(allSelected
                           ? String(localized: "Deselect All")
                           : String(localized: "Select All")) {
                        HapticFeedback.selection()
                        selection = allSelected ? [] : Set(items.map(\.id))
                    }
                    .font(AppFont.footnoteEmphasis)
                    .textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("inv_qr_select_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        pending = items.filter { selection.contains($0.id) }
                        dismiss()
                    } label: {
                        Text(verbatim: "\(String(localized: "Print")) (\(selection.count))")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selection = preselected.isEmpty ? Set(items.map(\.id)) : preselected }
    }
}
