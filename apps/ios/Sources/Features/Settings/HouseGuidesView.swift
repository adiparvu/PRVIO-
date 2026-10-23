import SwiftUI

// MARK: - House manual — list, detail, editor
//
// "Manualul casei": the written knowledge of the home, one guide per thing
// worth explaining. Guides anchor to zones and appliances so the manual is
// part of the property's dossier. Everyone living in the house reads it;
// the household's adults write it (mirrors RLS).

struct HouseGuidesView: View {
    @Environment(HouseGuideService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(ApplianceService.self) private var applianceService

    @State private var showAdd = false
    @State private var searchText = ""

    private var canWrite: Bool { propertyService.hasWriteAccess }

    private var filtered: [HouseGuide] {
        guard !searchText.isEmpty else { return service.guides }
        return service.guides.filter {
            $0.title.matchesSearch(searchText) || $0.content.matchesSearch(searchText)
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if service.guides.isEmpty {
                    if canWrite {
                        EmptyStateView(icon: "book.closed.fill",
                                       title: "guides_empty_title",
                                       message: "guides_empty_message",
                                       actionLabel: "guide_add") { showAdd = true }
                            .padding(.top, AppSpacing.xxl)
                    } else {
                        EmptyStateView(icon: "book.closed.fill",
                                       title: "guides_empty_title",
                                       message: "guides_empty_message")
                            .padding(.top, AppSpacing.xxl)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(filtered) { guide in
                            guideRow(guide)
                            if guide.id != filtered.last?.id {
                                FormDivider()
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                    .liquidGlass(cornerRadius: AppRadius.xl)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("guides_title")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: Text("Search…"))
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                    }
                    .accessibilityLabel(Text("guide_add"))
                }
            }
        }
        .sheet(isPresented: $showAdd) { GuideFormSheet() }
        .task {
            await service.loadIfNeeded()
            if let id = propertyService.primary?.id {
                if zoneService.zones.isEmpty { await zoneService.load(propertyId: id) }
                if applianceService.appliances.isEmpty { await applianceService.load(propertyId: id) }
            }
        }
        .refreshable { await service.load() }
    }

    private func guideRow(_ guide: HouseGuide) -> some View {
        NavigationLink {
            GuideDetailView(guideId: guide.id)
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle().fill(Color.brandPrimaryBlue.opacity(AppOpacity.tintedFill))
                    Image(systemName: guide.iconName)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(Color.brandPrimaryBlue)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: guide.title)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    if let anchor = anchorLine(guide) {
                        Text(verbatim: anchor)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor).lineLimit(1)
                    } else if !guide.content.isEmpty {
                        Text(verbatim: guide.content)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor).lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func anchorLine(_ guide: HouseGuide) -> String? {
        let zone = guide.zoneId.flatMap { id in zoneService.zones.first { $0.id == id }?.name }
        let appliance = guide.applianceId.flatMap { id in
            applianceService.appliances.first { $0.id == id }?.name
        }
        let parts = [zone, appliance].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: Detail

struct GuideDetailView: View {
    @Environment(HouseGuideService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(\.dismiss) private var dismiss

    let guideId: UUID
    @State private var showEdit = false

    /// Always read the live row — edits repaint the page instantly.
    private var guide: HouseGuide? { service.guides.first { $0.id == guideId } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let guide {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    header(guide)
                    anchorChips(guide)
                    Text(verbatim: guide.content)
                        .font(AppFont.body)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(AppSpacing.lg)
                        .liquidGlass(cornerRadius: AppRadius.xl)
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(verbatim: guide?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if propertyService.hasWriteAccess, let guide {
                ToolbarItem(placement: .pageMenu) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("guide_edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            Task {
                                await service.delete(guide)
                                dismiss()
                            }
                        } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(AppFont.scaled(17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let guide { GuideFormSheet(editing: guide) }
        }
    }

    private func header(_ guide: HouseGuide) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill(Color.brandPrimaryBlue.opacity(AppOpacity.tintedFill))
                Image(systemName: guide.iconName)
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(Color.brandPrimaryBlue)
            }
            .frame(width: 52, height: 52)
            Text(verbatim: guide.title)
                .font(AppFont.scaled(22, weight: .bold))
                .foregroundStyle(.primary)
            Spacer()
        }
    }

    @ViewBuilder
    private func anchorChips(_ guide: HouseGuide) -> some View {
        let zone = guide.zoneId.flatMap { id in zoneService.zones.first { $0.id == id } }
        let appliance = guide.applianceId.flatMap { id in
            applianceService.appliances.first { $0.id == id }
        }
        if zone != nil || appliance != nil {
            HStack(spacing: AppSpacing.sm) {
                if let zone { chip(icon: zone.icon, text: zone.name) }
                if let appliance { chip(icon: "washer.fill", text: appliance.name) }
            }
        }
    }

    private func chip(icon: String, text: String) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon).font(AppFont.scaled(12, weight: .semibold))
            Text(verbatim: text).font(AppFont.scaled(13, weight: .medium))
        }
        .foregroundStyle(Color.brandPrimaryBlue)
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.brandPrimaryBlue.opacity(AppOpacity.tintedFill), in: Capsule())
    }
}

// MARK: Add / edit sheet

struct GuideFormSheet: View {
    @Environment(HouseGuideService.self) private var service
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(ApplianceService.self) private var applianceService
    @Environment(\.dismiss) private var dismiss

    var editing: HouseGuide?

    @State private var title = ""
    @State private var icon = "book.closed.fill"
    @State private var content = ""
    @State private var zoneId: UUID?
    @State private var applianceId: UUID?
    @State private var isSaving = false
    @State private var error: String?
    @State private var hydrated = false

    private static let icons = [
        "book.closed.fill", "flame.fill", "drop.fill", "bolt.fill",
        "thermometer.medium", "key.fill", "wifi", "washer.fill",
        "wrench.and.screwdriver.fill", "trash.fill", "leaf.fill",
        "lock.shield.fill", "house.fill", "exclamationmark.triangle.fill",
        "fan.fill", "lightbulb.fill"
    ]

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        FormScaffold(title: editing == nil ? "guide_add" : "guide_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: icon, tint: .brandPrimaryBlue) {
                    TextField("guide_title_ph", text: $title).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "square.split.bottomrightquarter", tint: .brandPrimaryBlue) {
                    Picker("guide_zone", selection: $zoneId) {
                        Text("guide_none").tag(UUID?.none)
                        ForEach(zoneService.zones) { zone in
                            Text(verbatim: zone.name).tag(UUID?.some(zone.id))
                        }
                    }
                    .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "washer.fill", tint: .brandPrimaryBlue) {
                    Picker("guide_appliance", selection: $applianceId) {
                        Text("guide_none").tag(UUID?.none)
                        ForEach(applianceService.appliances) { appliance in
                            Text(verbatim: appliance.name).tag(UUID?.some(appliance.id))
                        }
                    }
                    .font(AppFont.body)
                }
            }

            FormGroup(title: "guide_content_title") {
                TextEditor(text: $content)
                    .font(AppFont.body)
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
                    .overlay(alignment: .topLeading) {
                        if content.isEmpty {
                            Text("guide_content_ph")
                                .font(AppFont.body)
                                .foregroundStyle(Color.secondaryTextColor.opacity(AppOpacity.emphasis))
                                .padding(.horizontal, AppSpacing.md + 5)
                                .padding(.top, AppSpacing.md)
                                .allowsHitTesting(false)
                        }
                    }
            }

            FormGroup(title: "guide_icon_title") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8),
                          spacing: AppSpacing.sm) {
                    ForEach(Self.icons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                            HapticFeedback.selection()
                        } label: {
                            Image(systemName: symbol)
                                .font(AppFont.scaled(15, weight: .semibold))
                                .foregroundStyle(icon == symbol ? Color.white : Color.brandPrimaryBlue)
                                .frame(width: 34, height: 34)
                                .background(
                                    Circle().fill(icon == symbol
                                        ? Color.brandPrimaryBlue
                                        : Color.brandPrimaryBlue.opacity(AppOpacity.tintedFill)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(AppSpacing.md)
            }
        }
        .onAppear(perform: hydrate)
    }

    private func hydrate() {
        guard let guide = editing, !hydrated else { return }
        hydrated = true
        title = guide.title
        icon = guide.iconName
        content = guide.content
        zoneId = guide.zoneId
        applianceId = guide.applianceId
    }

    private func save() {
        let payload = HouseGuideService.GuidePayload(
            title: title.trimmingCharacters(in: .whitespaces),
            icon: icon,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            zoneId: zoneId?.uuidString,
            applianceId: applianceId?.uuidString)
        isSaving = true
        Task {
            do {
                if let guide = editing {
                    try await service.update(guide.id, payload: payload)
                } else {
                    try await service.add(payload)
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
