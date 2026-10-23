import SwiftUI

// MARK: - PaintColorsView

struct PaintColorsView: View {
    @Environment(PaintColorService.self) private var paintColorService
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false
    @State private var selectedRoom: String? = nil
    @State private var colorToDelete: PaintColor? = nil
    @State private var detailColor: PaintColor? = nil
    @State private var editColor: PaintColor? = nil
    @State private var searchText = ""

    /// Share/Print goes through an explicit selection step (IMG_8628): all
    /// colors preselected, or exactly the ones the user keeps checked.
    private enum SpecJobMode: String, Identifiable {
        case share, print
        var id: String { rawValue }
    }
    @State private var specPicker: SpecJobMode? = nil
    /// Rendered and presented from onDismiss — a print panel or share sheet
    /// presented while the picker is still dismissing is silently dropped.
    @State private var pendingSpec: (print: Bool, colors: [PaintColor])? = nil

    private var filteredByRoom: [String: [PaintColor]] {
        let base: [String: [PaintColor]]
        if let room = selectedRoom {
            base = [room: paintColorService.byRoom[room] ?? []]
        } else {
            base = paintColorService.byRoom
        }
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.compactMapValues { colors in
            let matched = colors.filter(matchesSearch)
            return matched.isEmpty ? nil : matched
        }
    }

    private func matchesSearch(_ color: PaintColor) -> Bool {
        color.colorName.matchesSearch(searchText)
            || (color.brand ?? "").matchesSearch(searchText)
            || (color.code ?? "").matchesSearch(searchText)
            || color.roomName.matchesSearch(searchText)
            || color.finishDisplay.matchesSearch(searchText)
    }

    private var sortedRooms: [String] {
        filteredByRoom.keys.sorted()
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            if paintColorService.colors.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle("Paint Colors")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            // One circle for everything (IMG_8544/8546): the room
            // filter that used to sit as a permanent capsule plus
            // share/print, in a single aggregated popover.
            if !paintColorService.colors.isEmpty {
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
                .accessibilityLabel("Add paint color")
            }
        }
        .sheet(isPresented: $showAdd) {
            AddPaintColorSheet()
                .environment(paintColorService)
                .environment(propertyService)
        }
        .sheet(item: $detailColor) { color in
            PaintColorDetailSheet(colorId: color.id)
                .environment(paintColorService)
                .environment(propertyService)
        }
        .sheet(item: $editColor) { color in
            AddPaintColorSheet(editing: color)
                .environment(paintColorService)
                .environment(propertyService)
        }
        .sheet(item: $specPicker, onDismiss: runPendingSpec) { mode in
            PaintSpecPickerSheet(rooms: paintColorService.byRoom.keys.sorted()
                                    .map { ($0, paintColorService.byRoom[$0] ?? []) }
                                    .filter { !$0.1.isEmpty },
                                 isPrint: mode == .print,
                                 pending: $pendingSpec)
        }
        .confirmationDialog(
            "Delete \"\(colorToDelete?.colorName ?? "")\"?",
            isPresented: Binding(get: { colorToDelete != nil }, set: { if !$0 { colorToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let c = colorToDelete {
                    Task { await paintColorService.delete(c) }
                    colorToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { colorToDelete = nil }
        } message: {
            Text("This action cannot be undone.")
        }
        .task {
            if let id = propertyService.primary?.id {
                await paintColorService.load(propertyId: id)
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && sortedRooms.isEmpty {
                    EmptyStateView(icon: "magnifyingglass", title: "No results")
                } else {
                    roomsContent
                }
                Spacer(minLength: 110)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .refreshable {
            if let id = propertyService.primary?.id {
                await paintColorService.load(propertyId: id)
            }
        }
    }

    // MARK: - Filter + actions (one toolbar circle)

    private var filterButton: some View {
        GlassFilterButton(isActive: selectedRoom != nil, inToolbar: true) {
            GlassFilterSection(
                title: "Room",
                options: [GlassPickerOption<String?>(value: nil,
                                                     title: String(localized: "All"))]
                    + paintColorService.roomNames.map {
                        GlassPickerOption<String?>(value: $0,
                                                   title: String(localized: String.LocalizationValue($0)))
                    },
                selection: $selectedRoom)
            GlassFilterSectionDivider()
            GlassFilterActionRow(icon: "square.and.arrow.up",
                                 title: String(localized: "paint_share")) {
                specPicker = .share
            }
            GlassFilterActionRow(icon: "printer",
                                 title: String(localized: "paint_print")) {
                specPicker = .print
            }
        }
    }

    // MARK: - Rooms Content

    private var roomsContent: some View {
        LazyVStack(spacing: 24, pinnedViews: []) {
            ForEach(sortedRooms, id: \.self) { room in
                roomSection(room: room, colors: filteredByRoom[room] ?? [])
            }
        }
    }

    private func roomSection(room: String, colors: [PaintColor]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(room)
                    .font(AppFont.title3)
                    .foregroundStyle(.primary)
                Spacer()
                Text(colors.count == 1 ? "\(colors.count) color" : "\(colors.count) colors")
                    .font(AppFont.scaled(12))
                    .foregroundStyle(Color.primary.opacity(0.4))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(colors) { color in
                        PaintSwatch(paintColor: color)
                            .onTapGesture {
                                // Every color has its own page (IMG_8628).
                                detailColor = color
                                HapticFeedback.impact(.light)
                            }
                            .contextMenu {
                                swatchMenu(color)
                            } preview: {
                                swatchPreview(color)
                            }
                            .accessibilityHint(Text("View"))
                    }
                }
                .padding(.horizontal, 2)
                .padding(.bottom, AppSpacing.xxs)
            }
        }
    }

    // MARK: - Long-press: quick actions over the mini preview (IMG_8628)

    @ViewBuilder
    private func swatchMenu(_ color: PaintColor) -> some View {
        Button {
            detailColor = color
        } label: {
            Label("View", systemImage: "eye")
        }
        Button {
            editColor = color
        } label: {
            Label("Edit", systemImage: "pencil")
        }
        Button {
            if let image = PaintColorCard.render(color) {
                SystemActions.share([image])
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            if let image = PaintColorCard.render(color) {
                SystemActions.print(image: image, jobName: color.colorName)
            }
        } label: {
            Label("Print", systemImage: "printer")
        }
        Divider()
        Button(role: .destructive) {
            colorToDelete = color
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// The system-rendered snapshot behind the menu: identity + the real
    /// fields at a glance. Missing fields are omitted, never invented.
    private func swatchPreview(_ color: PaintColor) -> some View {
        var details: [PreviewCardDetail] = [
            PreviewCardDetail(icon: "door.left.hand.closed",
                              label: Text("Room"),
                              value: Text(verbatim: color.roomName)),
        ]
        if let raw = color.lastUsedAt, let day = AppDate.day(from: raw) {
            details.append(PreviewCardDetail(
                icon: "paintbrush.pointed.fill",
                label: Text("paint_last_used"),
                value: Text(day.formatted(date: .abbreviated, time: .omitted))))
        }
        if let leftover = color.leftoverNote, !leftover.isEmpty {
            details.append(PreviewCardDetail(icon: "shippingbox.fill",
                                             label: Text("paint_leftover"),
                                             value: Text(verbatim: leftover)))
        }
        var chips: [PreviewCardChip] = [
            PreviewCardChip(text: Text(verbatim: color.finishDisplay),
                            tint: color.swatchColor),
        ]
        if let hex = color.hexColor, !hex.isEmpty {
            let display = hex.hasPrefix("#") ? hex.uppercased() : "#\(hex.uppercased())"
            chips.append(PreviewCardChip(icon: "number", text: Text(verbatim: display)))
        }
        let subtitle = [color.brand, color.code]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return PreviewCard(
            title: Text(verbatim: color.colorName),
            subtitle: subtitle.isEmpty ? nil : Text(verbatim: subtitle),
            tint: color.swatchColor,
            details: details,
            chips: chips
        ) {
            RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                .fill(color.swatchColor)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        EmptyStateView(
            icon: "paintpalette.fill",
            title: "No colors saved yet",
            message: "Save paint colors for each room so you can easily reorder or touch up later.",
            actionLabel: "Add first color",
            action: { showAdd = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Share / Print

    /// Runs the job the picker left behind: renders exactly the selected
    /// colors into the spec sheet, then presents share or AirPrint.
    private func runPendingSpec() {
        guard let job = pendingSpec else { return }
        pendingSpec = nil
        guard let image = renderSpecSheet(colors: job.colors) else { return }
        if job.print {
            SystemActions.print(image: image,
                                jobName: String(localized: "paint_colors_title"))
        } else {
            SystemActions.share([image])
        }
    }

    /// Renders the given colors (grouped back into their rooms) into a clean,
    /// light-mode document image suitable for AirPrint or sharing — the spec
    /// sheet you take to the paint store.
    private func renderSpecSheet(colors: [PaintColor]) -> UIImage? {
        let grouped = Dictionary(grouping: colors, by: { $0.roomName })
        let rooms = grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
        guard !rooms.isEmpty else { return nil }
        let sheet = PaintColorsSpecSheet(propertyName: propertyService.primary?.name ?? "",
                                         rooms: rooms)
        let renderer = ImageRenderer(content: sheet)
        renderer.scale = 3.0
        return renderer.uiImage
    }
}

// MARK: - Selection step before share / print (IMG_8628)
//
// Same pattern as the inventory QR label picker: every color as a native
// checkmark row grouped by room, Select All / Deselect All in one toggle,
// and a confirm carrying the honest count. All colors start selected, so
// the old "share everything" flow is still two taps.

private struct PaintSpecPickerSheet: View {
    let rooms: [(String, [PaintColor])]
    let isPrint: Bool
    @Binding var pending: (print: Bool, colors: [PaintColor])?

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    private var allColors: [PaintColor] { rooms.flatMap(\.1) }
    private var allSelected: Bool {
        !allColors.isEmpty && selection.count == allColors.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(allSelected
                           ? String(localized: "Deselect All")
                           : String(localized: "Select All")) {
                        HapticFeedback.selection()
                        selection = allSelected ? [] : Set(allColors.map(\.id))
                    }
                    .font(AppFont.footnoteEmphasis)
                }
                ForEach(rooms, id: \.0) { room, colors in
                    Section {
                        ForEach(colors) { color in
                            row(color)
                        }
                    } header: {
                        Text(verbatim: room)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("paint_pick_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        pending = (print: isPrint,
                                   colors: allColors.filter { selection.contains($0.id) })
                        dismiss()
                    } label: {
                        Text(verbatim: "\(String(localized: isPrint ? "Print" : "Share")) (\(selection.count))")
                    }
                    .disabled(selection.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selection = Set(allColors.map(\.id)) }
    }

    private func row(_ color: PaintColor) -> some View {
        Button {
            HapticFeedback.selection()
            if selection.contains(color.id) { selection.remove(color.id) }
            else { selection.insert(color.id) }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.swatchColor)
                    .frame(width: 26, height: 26)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7)
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: color.colorName)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let code = color.code, !code.isEmpty {
                        Text(verbatim: code)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: selection.contains(color.id)
                      ? "checkmark.circle.fill" : "circle")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(selection.contains(color.id)
                                     ? Color.accentColor
                                     : Color.primary.opacity(AppOpacity.disabled))
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Printable spec sheet (redesigned, IMG_8630)
//
// A fixed-width, always-light document (independent of the app theme) so the
// print/share output is legible on paper. Rendered off-screen via
// ImageRenderer. Artistic but honest: the header carries the title, the
// property and a live count line; a paint strip made of the ACTUAL selected
// colors runs under it; every color prints its basics (swatch, name, hex)
// plus every real field it has — brand, code, finish, surface, last used,
// leftover can, notes. Absent fields simply don't print.

private struct PaintColorsSpecSheet: View {
    let propertyName: String
    let rooms: [(String, [PaintColor])]

    private let width: CGFloat = 560
    private let ink = Color(white: 0.08)
    private let soft = Color(white: 0.3)
    private let faint = Color(white: 0.45)
    private let rule = Color(white: 0.9)

    private var all: [PaintColor] { rooms.flatMap(\.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            header
            paintStrip
            ForEach(rooms, id: \.0) { room, colors in
                roomBlock(room, colors)
            }
            footer
        }
        .padding(32)
        .frame(width: width, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    // MARK: Header — title, property, count line

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 11) {
                Image(systemName: "paintpalette.fill")
                    .font(AppFont.scaled(24))
                    .foregroundStyle(Color(red: 0.30, green: 0.20, blue: 0.62))
                Text("paint_colors_title")
                    .font(AppFont.scaled(30, weight: .heavy))
                    .foregroundStyle(ink)
            }
            if !propertyName.isEmpty {
                Text(verbatim: propertyName)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(soft)
            }
            Text(verbatim: metaLine)
                .font(AppFont.scaled(12))
                .foregroundStyle(faint)
        }
    }

    private var metaLine: String {
        let counts = String(format: String(localized: "paint_sheet_meta"),
                            all.count, rooms.count)
        let day = Date().formatted(date: .abbreviated, time: .omitted)
        return "\(counts) · \(day)"
    }

    /// The signature band: one flexible stripe per selected color, in room
    /// order — the palette itself as ornament, never invented data.
    private var paintStrip: some View {
        HStack(spacing: 0) {
            ForEach(all) { color in
                Rectangle().fill(color.swatchColor)
            }
        }
        .frame(height: 16)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Color(white: 0.88), lineWidth: 1))
    }

    // MARK: Rooms

    private func roomBlock(_ room: String, _ colors: [PaintColor]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Text(verbatim: room)
                    .font(AppFont.scaled(17, weight: .bold))
                    .foregroundStyle(ink)
                    .fixedSize()
                Rectangle().fill(rule).frame(height: 1)
            }
            ForEach(colors) { color in row(color) }
        }
    }

    private func row(_ color: PaintColor) -> some View {
        HStack(alignment: .top, spacing: 16) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.swatchColor)
                .frame(width: 56, height: 56)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color(white: 0.85), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: color.colorName)
                        .font(AppFont.scaled(15, weight: .bold))
                        .foregroundStyle(ink)
                    if let hex = color.hexColor, !hex.isEmpty {
                        Text(verbatim: hex.hasPrefix("#") ? hex.uppercased() : "#\(hex.uppercased())")
                            .font(AppFont.scaled(11, weight: .medium))
                            .monospaced()
                            .foregroundStyle(faint)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if let brand = color.brand, !brand.isEmpty { tag(brand) }
                    if let code = color.code, !code.isEmpty { tag(code) }
                    tag(color.finishDisplay)
                    tag(color.surfaceDisplay)
                }
                factsLine(color)
                if !color.notes.isNilOrEmpty {
                    Text(verbatim: color.notes ?? "")
                        .font(AppFont.scaled(11).italic())
                        .foregroundStyle(faint)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// The usage facts (migration 165), printed only when they exist.
    @ViewBuilder
    private func factsLine(_ color: PaintColor) -> some View {
        let lastUsed = color.lastUsedAt.flatMap(AppDate.day(from:))
        if lastUsed != nil || !color.leftoverNote.isNilOrEmpty {
            HStack(spacing: 14) {
                if let day = lastUsed {
                    fact("paint_last_used",
                         day.formatted(date: .abbreviated, time: .omitted))
                }
                if let leftover = color.leftoverNote, !leftover.isEmpty {
                    fact("paint_leftover", leftover)
                }
            }
        }
    }

    private func fact(_ key: String.LocalizationValue, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: String(localized: key) + ":")
                .font(AppFont.scaled(11.5))
                .foregroundStyle(faint)
            Text(verbatim: value)
                .font(AppFont.scaled(11.5, weight: .medium))
                .foregroundStyle(soft)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(verbatim: text)
            .font(AppFont.scaled(11))
            .foregroundStyle(soft)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(white: 0.955), in: Capsule())
    }

    private var footer: some View {
        HStack {
            Spacer()
            Text(verbatim: "PRVIO")
                .font(AppFont.scaled(11, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color(white: 0.75))
            Spacer()
        }
        .padding(.top, 4)
    }
}

private extension Optional where Wrapped == String {
    var isNilOrEmpty: Bool { self?.isEmpty ?? true }
}

// MARK: - PaintSwatch

private struct PaintSwatch: View {
    let paintColor: PaintColor

    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(paintColor.swatchColor)
                .frame(width: 70, height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.8)
                )
                .overlay(alignment: .topTrailing) {
                    // Entries saved with a photo carry a badge — tap to view.
                    if paintColor.photoUrl?.isEmpty == false {
                        Image(systemName: "photo.fill")
                            .font(AppFont.scaled(8, weight: .semibold))
                            .foregroundStyle(paintColor.swatchColor.readableText.opacity(0.85))
                            .padding(5)
                    }
                }
                .shadow(color: paintColor.swatchColor.opacity(0.4), radius: 8, y: 3)

            Text(paintColor.colorName)
                .font(AppFont.caption2)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(width: 70)

            if let code = paintColor.code, !code.isEmpty {
                Text(code)
                    .font(AppFont.scaled(10))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .lineLimit(1)
                    .frame(width: 70)
            }

            Text(LocalizedStringKey(paintColor.finishDisplay))
                .font(AppFont.scaled(10))
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .frame(width: 70)
        }
    }
}
