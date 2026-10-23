import SwiftUI
import RoomPlan

// MARK: - Floors & Rooms (Plans & 3D rebuild, phase A+B)
//
// The house as a structure: levels, the rooms on them, and a RoomPlan
// .usdz scan attached to each room — synced through Supabase so the whole
// household sees the same house, unlike the old device-local scan library.

struct FloorPlansView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(InventoryService.self) private var inventoryService
    @Environment(ApplianceService.self) private var applianceService
    // The SHARED plan service (injected in MainTabView) — Tab 2's plan mode
    // reads the same rooms, so an edit here re-draws that page instantly.
    @Environment(FloorPlanService.self) private var service

    enum DisplayMode: String, CaseIterable {
        case list, plan
    }

    @State private var displayMode: DisplayMode = .list
    @State private var isEditingPlan = false
    @State private var showAddRoom = false
    @State private var showAddFloor = false
    @State private var scanTarget: RoomRecord?
    @State private var previewURL: URL?
    @State private var previewTitle = ""
    @State private var isFetchingScan = false
    @State private var roomToDelete: RoomRecord?
    @State private var inspectedRoom: RoomRecord?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                if service.isLoading {
                    ProgressView().tint(.accentColor).padding(.top, 80)
                } else if service.rooms.isEmpty && service.floors.isEmpty {
                    EmptyStateView(
                        icon: "square.split.bottomrightquarter.fill",
                        title: "floors_empty_title",
                        message: "floors_empty_msg"
                    )
                    .padding(.top, 40)
                } else {
                    ForEach(service.levels, id: \.self) { level in
                        levelSection(level)
                    }
                }
                Spacer(minLength: 110)
            }
            // Full width even when the only content is the loading spinner —
            // otherwise the push transition sizes the incoming page to its
            // narrow ideal width (the vertical band in IMG_8060, with the
            // title clipped to match).
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("floors_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if displayMode == .plan {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        HapticFeedback.selection()
                        withAnimation(.snappy(duration: 0.25)) { isEditingPlan.toggle() }
                    } label: {
                        Text(isEditingPlan ? "plan_edit_done" : "plan_edit")
                            .font(AppFont.footnoteEmphasis)
                    }
                }
            }
            if !(service.rooms.isEmpty && service.floors.isEmpty) {
                ToolbarItem(placement: .pageMenu) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showAddRoom = true
                    } label: {
                        Label("room_add", systemImage: "square.split.bottomrightquarter")
                    }
                    Button {
                        showAddFloor = true
                    } label: {
                        Label("floor_add", systemImage: "square.3.layers.3d")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("room_add")
            }
        }
        .task(id: propertyService.primary?.id) {
            if let pid = propertyService.primary?.id {
                await service.load(propertyId: pid)
                // The inspector matches inventory/appliances by location —
                // hydrate them if this page is reached before their own.
                if inventoryService.items.isEmpty {
                    await inventoryService.load(propertyId: pid)
                }
                if applianceService.appliances.isEmpty {
                    await applianceService.load(propertyId: pid)
                }
            }
        }
        .sheet(item: $inspectedRoom) { room in
            RoomInspectorSheet(
                room: room,
                health: zoneHealth(for: room),
                onViewScan: { openScan(room) },
                onScan: { scanTarget = room }
            )
        }
        .refreshable {
            if let pid = propertyService.primary?.id {
                await service.load(propertyId: pid)
            }
        }
        .sheet(isPresented: $showAddRoom) {
            AddRoomSheet(levels: service.levels) { name, type, level, area in
                Task { await service.addRoom(name: name, type: type, level: level, areaSqm: area) }
            }
        }
        .sheet(isPresented: $showAddFloor) {
            AddFloorSheet { name, level in
                Task { await service.addFloor(name: name, level: level) }
            }
        }
        .fullScreenCover(item: $scanTarget) { room in
            RoomScanView { url in
                scanTarget = nil
                if let url {
                    HapticFeedback.success()
                    Task { await service.attachScan(fileURL: url, to: room) }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let url = previewURL {
                QuickLookSheet(url: url, title: previewTitle)
            }
        }
        .confirmationDialog("Delete \"\(roomToDelete?.name ?? "")\"?",
                            isPresented: Binding(
                                get: { roomToDelete != nil },
                                set: { if !$0 { roomToDelete = nil } }
                            ), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let room = roomToDelete {
                    HapticFeedback.warning()
                    Task { await service.deleteRoom(room) }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay {
            if isFetchingScan {
                ProgressView()
                    .padding(AppSpacing.xl)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
        }
        .alert("Error", isPresented: Binding(
            get: { service.error != nil },
            set: { if !$0 { service.error = nil } }
        )) {
            Button("OK") { service.error = nil }
        } message: { Text(service.error ?? "") }
    }

    // MARK: Mode circle (list ↔ plan)

    /// One circle (the one-circle law): the segmented list ↔ plan control
    /// that used to sit on the page body, as a single-select view-mode
    /// section. A view mode never narrows the list, so the trigger never
    /// claims the filtered accent dot.
    private var filterButton: some View {
        GlassFilterButton(inToolbar: true) {
            GlassFilterSection(
                title: "cal_mode_picker",
                options: [
                    GlassPickerOption(value: DisplayMode.list,
                                      icon: "list.bullet",
                                      title: String(localized: "plan_mode_list")),
                    GlassPickerOption(value: DisplayMode.plan,
                                      icon: "square.split.bottomrightquarter",
                                      title: String(localized: "plan_mode_plan"))
                ],
                selection: $displayMode,
                onChange: {
                    if displayMode == .list { isEditingPlan = false }
                })
        }
    }

    /// Digital Twin health for a room: the zone that shares its name.
    private func zoneHealth(for room: RoomRecord) -> Int? {
        zoneService.zones.first {
            $0.name.compare(room.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }?.healthScore
    }

    // MARK: Level section

    private func levelSection(_ level: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(service.floor(forLevel: level)?.name
                     ?? String(format: String(localized: "floor_level %lld"), level))
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Spacer()
                let count = service.rooms(onLevel: level).count
                Text("\(count)")
                    .font(AppFont.label)
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .monospacedDigit()
            }
            .padding(.leading, AppSpacing.xxs)

            if displayMode == .plan {
                LevelPlanCanvas(
                    rooms: service.rooms(onLevel: level),
                    healthFor: { zoneHealth(for: $0) },
                    isEditing: isEditingPlan,
                    onTap: { room in
                        inspectedRoom = room
                    },
                    onGeometryChange: { room, rect in
                        Task {
                            await service.updateGeometry(room,
                                                         xPct: rect.minX, yPct: rect.minY,
                                                         widthPct: rect.width, heightPct: rect.height)
                        }
                    }
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(service.rooms(onLevel: level)) { room in
                        roomRow(room)
                    }
                }
            }
        }
    }

    private func roomRow(_ room: RoomRecord) -> some View {
        Button {
            inspectedRoom = room
        } label: {
            GlassCard {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                            .fill(RoomKind.color(room.roomType).opacity(0.15))
                            .frame(width: 44, height: 44)
                        Image(systemName: room.kindIcon)
                            .font(AppFont.subheadline)
                            .foregroundStyle(RoomKind.color(room.roomType))
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(room.name)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        HStack(spacing: 6) {
                            Text(room.kindLabel)
                                .font(AppFont.caption2)
                                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                            if let area = room.areaSqm, area > 0 {
                                Text(String(format: String(localized: "room_area_fmt %@"),
                                            String(format: "%.0f", area)))
                                    .font(AppFont.caption2)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                            }
                        }
                    }
                    Spacer()
                    if room.hasScan {
                        Image(systemName: "cube.transparent.fill")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.purple)
                            .accessibilityLabel("room_view_scan")
                    } else if RoomCaptureSession.isSupported {
                        Image(systemName: "plus.viewfinder")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(Color.primary.opacity(0.3))
                            .accessibilityLabel("room_scan")
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            if RoomCaptureSession.isSupported {
                Button {
                    scanTarget = room
                } label: {
                    Label(room.hasScan ? "room_rescan" : "room_scan",
                          systemImage: "cube.transparent")
                }
            }
            if room.hasScan {
                Button {
                    openScan(room)
                } label: {
                    Label("room_view_scan", systemImage: "eye")
                }
            }
            Divider()
            Button(role: .destructive) {
                roomToDelete = room
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func openScan(_ room: RoomRecord) {
        guard !isFetchingScan else { return }
        isFetchingScan = true
        Task {
            let url = await service.localScanURL(for: room)
            isFetchingScan = false
            if let url {
                previewTitle = room.name
                previewURL = url
            }
        }
    }
}

// MARK: - Add room

private struct AddRoomSheet: View {
    let levels: [Int]
    let onSave: (String, String, Int, Double?) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type = "living_room"
    @State private var level = 0
    @State private var areaText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("room_name", text: $name)
                Picker("room_type", selection: $type) {
                    ForEach(RoomKind.all, id: \.self) { t in
                        Label(RoomKind.label(t), systemImage: RoomKind.icon(t)).tag(t)
                    }
                }
                Stepper(value: $level, in: -3...10) {
                    HStack {
                        Text("floor_level_field")
                        Spacer()
                        Text("\(level)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                TextField("room_area", text: $areaText)
                    .keyboardType(.decimalPad)
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("room_add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, type, level,
                               Double(areaText.replacingOccurrences(of: ",", with: ".")))
                        HapticFeedback.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { level = levels.first ?? 0 }
    }
}

// MARK: - Add floor

private struct AddFloorSheet: View {
    let onSave: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var level = 0

    var body: some View {
        NavigationStack {
            Form {
                TextField("floor_name", text: $name)
                Stepper(value: $level, in: -3...10) {
                    HStack {
                        Text("floor_level_field")
                        Spacer()
                        Text("\(level)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(appBackground.ignoresSafeArea())
            .navigationTitle("floor_add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed, level)
                        HapticFeedback.success()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
