import SwiftUI

// MARK: - "Spațiile casei" — tab 2 (Estate OS)
//
// The full-page home of the estate's spaces, replacing the Digital Twin by
// user decision (no 3D, no maps, no twin of any kind). The app's one
// Liquid Glass language: the living mood backdrop, a free-floating light
// title, a quick row of real destinations (all devices, cameras, the
// home's health), and a 2-column grid of space cards — each the zone's own
// photo (or its kind's tinted scene wash + icon) with the ONE honest live
// subline and the honest status dot, all computed by the shared
// `SpaceCardModel` so this page, the home strip and the space page can
// never drift apart.
//
// Navigation is a page hierarchy, not a stack of sheets: tapping a card
// PUSHES SpaceDetailView onto the tab's existing NavigationStack (the one
// MainTabView owns — same `navigationDestination(item:)` pattern as
// TasksView). The trailing "+" card and the zero-spaces full-page state
// both open the shared create-space flow.

struct SpacesTabView: View {
    @Environment(PropertyService.self) private var propertyService
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(CurrencyService.self) private var currencyService
    @Environment(AppSettings.self) private var appSettings
    @Environment(AppRouter.self) private var router
    // The SHARED plan service — Blueprints' rooms drawn on this tab
    // (read-only; editing keeps its one home in Settings → Blueprints).
    @Environment(FloorPlanService.self) private var floorPlanService

    /// Grid of photo cards ↔ the interactive floor plan (E4). Persisted so
    /// the tab reopens the way it was left.
    enum DisplayMode: String { case grid, plan }
    @AppStorage("spaces.displayMode") private var displayModeRaw = DisplayMode.grid.rawValue
    private var displayMode: DisplayMode { DisplayMode(rawValue: displayModeRaw) ?? .grid }

    @State private var createFlow = SpaceCreateFlow()
    /// The pushed space page's target (id, not snapshot — the destination
    /// re-resolves the live zone, the TasksView pattern).
    @State private var pushedZoneId: UUID?

    /// One nested-presentation slot — the hub's single-`sheet(item:)`
    /// discipline, so presentations never race.
    private enum ActiveSheet: String, Identifiable {
        case allDevices, health
        var id: String { rawValue }
    }

    @State private var activeSheet: ActiveSheet? = nil

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    EnergyCard()
                    if zoneService.zones.isEmpty {
                        emptyState
                    } else {
                        modeToggle
                        if displayMode == .plan {
                            planContent
                        } else {
                            grid
                        }
                    }
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
        }
        // The standard large navigation title + system-toolbar circle, like
        // every other page — the free-floating in-body header was the last
        // custom page chrome left, and the user retired it (IMG_8590).
        .navigationTitle("spaces_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                quickMenu
            }
        }
        .navigationDestination(item: $pushedZoneId) { id in
            // Re-resolve the live zone; a space deleted mid-navigation
            // simply has no page (the pop gesture returns to the grid).
            if let zone = zoneService.zones.first(where: { $0.id == id }) {
                SpaceDetailView(zone: zone, presentation: .push)
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .allDevices:
                SmartHomeDeviceListSheet(kind: nil, room: nil)
            case .health:
                PropertyHealthDashboardView()
                    .environment(elementService)
                    .environment(currencyService)
                    .environment(appSettings)
                    .environment(propertyService)
            }
        }
        .spaceCreateAlerts(createFlow,
                           zoneService: zoneService,
                           propertyService: propertyService)
        .task(id: propertyService.primary?.id) { await loadData() }
        // Plan rooms hydrate LAZILY — only when the plan mode is actually
        // on screen (first entry or a mode flip), never in reloadWorld.
        .task(id: displayModeRaw) {
            guard displayMode == .plan, let pid = propertyService.primary?.id,
                  floorPlanService.propertyId != pid else { return }
            await floorPlanService.load(propertyId: pid)
        }
    }

    // MARK: Quick menu — the old chip row's four destinations, one More
    // circle (IMG_8553) in the system toolbar. Navigation rows, so the
    // trigger wears Apple's ellipsis, never the filter glyph.

    private var quickMenu: some View {
        GlassFilterButton(inToolbar: true, icon: "ellipsis", accessibilityLabelKey: "More") {
            GlassFilterActionRow(icon: "square.grid.2x2",
                                 title: String(localized: "hub_devices")) {
                activeSheet = .allDevices
            }
            GlassFilterActionRow(icon: "video.fill",
                                 title: String(localized: "hub_cameras")) {
                // Cameras is a pushed content page (AppRoute.cameras) —
                // the router lands it on THIS tab's stack.
                router.navigate(to: .cameras)
            }
            GlassFilterActionRow(icon: "heart.text.square.fill",
                                 title: String(localized: "spaces_health")) {
                activeSheet = .health
            }
            // Emergency mode — the quiet gate to the loud page
            // (EmergencyModeView itself inverts the design rules).
            GlassFilterActionRow(icon: "cross.case.fill",
                                 title: String(localized: "spaces_emergency")) {
                router.navigate(to: .emergency)
            }
        }
    }

    // MARK: Mode toggle — photo grid ↔ the floor plan

    private var modeToggle: some View {
        Picker("spaces_title", selection: Binding(
            get: { displayMode },
            set: { displayModeRaw = $0.rawValue }
        ).animation(.snappy(duration: 0.25))) {
            Label("plan_mode_list", systemImage: "square.grid.2x2").tag(DisplayMode.grid)
            Label("plan_mode_plan", systemImage: "square.split.bottomrightquarter").tag(DisplayMode.plan)
        }
        .pickerStyle(.segmented)
    }

    // MARK: Plan — Blueprints' canvas, read-only, zones as destinations

    /// The zone a plan room stands for: the 159 id-link first, the app-wide
    /// name match for pre-bridge rooms.
    private func zone(for room: RoomRecord) -> PropertyZone? {
        if let byId = zoneService.zones.first(where: { $0.id == room.zoneId }) { return byId }
        return zoneService.zones.first {
            $0.name.compare(room.name, options: [.caseInsensitive, .diacriticInsensitive])
                == .orderedSame
        }
    }

    /// Zones not yet standing on the plan — offered as one-tap placements.
    private var unplacedZones: [PropertyZone] {
        zoneService.zones.filter { floorPlanService.room(for: $0) == nil }
    }

    @ViewBuilder private var planContent: some View {
        if floorPlanService.isLoading && floorPlanService.rooms.isEmpty {
            ProgressView().tint(.accentColor).frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                ForEach(floorPlanService.levels, id: \.self) { level in
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text(floorPlanService.floor(forLevel: level)?.name
                             ?? String(format: String(localized: "floor_level %lld"), level))
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                        // READ-ONLY here by design: one plan editor lives in
                        // Settings → Blueprints, so geometry can never fork.
                        LevelPlanCanvas(
                            rooms: floorPlanService.rooms(onLevel: level),
                            healthFor: { zone(for: $0)?.healthScore },
                            isEditing: false,
                            onTap: { room in
                                if let target = zone(for: room) {
                                    pushedZoneId = target.id
                                }
                            },
                            onGeometryChange: { _, _ in }
                        )
                    }
                }
                if !unplacedZones.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        Text("spaces_unplaced")
                            .font(AppFont.label)
                            .foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: AppSpacing.sm) {
                                ForEach(unplacedZones) { zone in
                                    Button {
                                        HapticFeedback.impact(.light)
                                        Task { await floorPlanService.ensureRoom(for: zone) }
                                    } label: {
                                        HStack(spacing: AppSpacing.xs) {
                                            Image(systemName: "plus")
                                                .font(AppFont.scaled(12, weight: .semibold))
                                                .foregroundStyle(Color.accentColor)
                                            Text(verbatim: zone.name)
                                                .font(AppFont.scaled(13, weight: .medium))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                        }
                                        .padding(.horizontal, AppSpacing.base)
                                        .padding(.vertical, AppSpacing.sm + 1)
                                        .liquidGlass(cornerRadius: AppRadius.md)
                                    }
                                    .buttonStyle(SmartCardPressStyle())
                                }
                            }
                            .padding(.vertical, 1)
                        }
                    }
                }
                if floorPlanService.rooms.isEmpty && unplacedZones.isEmpty {
                    Text("spaces_plan_empty")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Grid — 2 columns of big space cards + the trailing "+" card

    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: AppSpacing.md),
         GridItem(.flexible(), spacing: AppSpacing.md)]
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: AppSpacing.md) {
            ForEach(zoneService.zones) { zone in
                SpaceGridCard(
                    zone: zone,
                    subline: SpaceCardModel.subline(for: zone, plantService: plantService),
                    status: SpaceCardModel.status(for: zone),
                    climate: IndoorClimateStore.shared.reading(forSpaceNamed: zone.name),
                    attentionCount: elementService.elements(inZone: zone.id)
                        .filter { $0.healthScore < 70 }.count
                ) {
                    pushedZoneId = zone.id
                }
            }
            AddSpaceGridCard(isCreating: createFlow.isCreating) {
                createFlow.begin()
            }
            .disabled(createFlow.isCreating)
        }
        // Room for the cards' lift shadow inside the scroll clip.
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: Zero spaces — the honest full-page create-first state

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            ZStack {
                SmartRadialGlow(diameter: 150)
                Image(systemName: "house")
                    .font(AppFont.scaled(44, weight: .light))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(height: 110)
            .accessibilityHidden(true)
            VStack(spacing: AppSpacing.xs) {
                Text("est_create_first")
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("est_create_first_caption")
                    .font(AppFont.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                HapticFeedback.impact(.light)
                createFlow.begin()
            } label: {
                Group {
                    if createFlow.isCreating {
                        ProgressView()
                    } else {
                        Text("est_create_space")
                    }
                }
                .font(AppFont.scaled(15, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, AppSpacing.xl)
                .padding(.vertical, AppSpacing.md)
                .mediaGlass(in: Capsule(style: .continuous), interactive: true)
            }
            .buttonStyle(SmartCardPressStyle())
            .disabled(createFlow.isCreating)
        }
        .frame(maxWidth: .infinity)
        // Half the space page's hero breath: pure scene above the invite.
        .padding(.top, SpaceHero.breath / 2)
    }

    // MARK: Data

    /// Zones dress the grid; elements feed the health dashboard behind the
    /// quick row. Plants load in MainTabView's world reload, IoT sensors
    /// self-load, and the smart-home list is computed — nothing else to ask.
    private func loadData() async {
        guard let pid = propertyService.primary?.id else { return }
        // Reload whenever the cached data belongs to another property, so a
        // property switch swaps this page's contents too.
        if zoneService.zones.first?.propertyId != pid {
            await zoneService.load(propertyId: pid)
        }
        if elementService.elements.first?.propertyId != pid {
            await elementService.load(propertyId: pid)
        }
    }
}

// MARK: - One grid card

/// A big 4:5 space card: the zone's photo filling the card (or its kind's
/// tinted scene wash + icon), the name floating over a bottom scrim, the
/// honest live subline, and the status dot (only when there is live sensor
/// truth to signal). The whole card is one button that pushes the space page.
private struct SpaceGridCard: View {
    let zone: PropertyZone
    let subline: Text?
    let status: SpaceStatus
    /// The room's live HomeKit reading (name-matched) — a small °C badge in
    /// the card's top-right corner, only when a real sensor reported.
    var climate: IndoorClimateReading? = nil
    /// Elements in this zone whose health genuinely needs attention (<70).
    var attentionCount: Int = 0
    let onOpen: () -> Void

    /// Width/height of the card (taller than wide — the strip's cards are
    /// small chips; the tab's are the page's main event).
    private static let aspect: CGFloat = 4.0 / 5.0
    /// Photo decode target for the ~half-screen-wide card (points).
    private static let photoTargetSize: CGFloat = 360

    private var kind: SpaceKind { zone.resolvedSpaceKind }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onOpen()
        } label: {
            ZStack(alignment: .bottomLeading) {
                backdrop
                caption
            }
            .overlay(alignment: .topTrailing) {
                if let climate {
                    climateBadge(climate)
                }
            }
            .aspectRatio(Self.aspect, contentMode: .fit)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .contentShape(shape)
        }
        .buttonStyle(SmartCardPressStyle())
        // Long-press: real controls only — power devices in this room,
        // scenes that genuinely touch it. No targets → no menu entries
        // beyond opening the page (the honesty law).
        .contextMenu { contextActions }
        .accessibilityElement(children: .combine)
        .accessibilityValue(status.dotColor != nil ? Text(status.titleKey) : Text(verbatim: ""))
        .accessibilityHint(Text("spaces_open_hint"))
    }

    // MARK: Quick actions (long-press)

    private var poweredDevices: [SmartDevice] {
        SmartHomeService.shared.devices(in: zone.name).filter(\.hasPower)
    }

    @ViewBuilder private var contextActions: some View {
        let powered = poweredDevices
        if !powered.isEmpty {
            Button {
                setAll(powered, on: false)
            } label: {
                Label("spaces_all_off", systemImage: "lightbulb.slash.fill")
            }
            Button {
                setAll(powered, on: true)
            } label: {
                Label("spaces_all_on", systemImage: "lightbulb.fill")
            }
        }
        let scenes = HomeKitService.shared.scenes(touchingSpaceNamed: zone.name)
        if !scenes.isEmpty {
            Divider()
            ForEach(scenes.prefix(4)) { scene in
                Button {
                    HapticFeedback.impact(.light)
                    Task { try? await HomeKitService.shared.executeScene(scene) }
                } label: {
                    Label(scene.name, systemImage: "sparkles")
                }
            }
        }
        Divider()
        Button {
            onOpen()
        } label: {
            Label("Open", systemImage: "arrow.up.right")
        }
    }

    private func setAll(_ devices: [SmartDevice], on: Bool) {
        HapticFeedback.impact(.light)
        Task {
            for device in devices {
                await SmartHomeService.shared.setPower(device, on: on)
            }
        }
    }

    /// "21°" over its own scrim capsule — white type on the photo, the
    /// caption's exact legibility contract.
    private func climateBadge(_ reading: IndoorClimateReading) -> some View {
        Text(verbatim: "\(reading.celsius.formatted(.number.precision(.fractionLength(0))))°")
            .font(AppFont.scaled(12, weight: .semibold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 3)
            .background(.black.opacity(0.35), in: Capsule())
            .padding(AppSpacing.sm)
            .accessibilityLabel(Text(verbatim: "\(reading.celsius.formatted(.number.precision(.fractionLength(0)))) °C"))
    }

    /// The kind's scene wash is also the photo's loading state.
    private var backdrop: some View {
        ZStack {
            kind.sceneGradient
            if let photo = zone.photoUrl, !photo.isEmpty {
                Color.clear
                    .overlay {
                        StorageImage(source: photo, targetSize: Self.photoTargetSize) { phase in
                            if case .success(let image) = phase {
                                image
                                    .resizable()
                                    .scaledToFill()
                            }
                        }
                    }
                    .clipped()
            } else {
                Image(systemName: kind.icon)
                    .font(AppFont.scaled(34, weight: .semibold))
                    .foregroundStyle(kind.accent)
            }
        }
        .accessibilityHidden(true)
    }

    /// Name + honest subline over a legibility scrim (a gradient, not a
    /// card). White type is deliberate here — it sits on the dark photo
    /// scrim, not on glass, in both schemes (the CamerasView contract).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: AppSpacing.xs) {
                Text(verbatim: zone.name)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if let dot = status.dotColor {
                    Circle()
                        .fill(dot)
                        .frame(width: 6, height: 6)
                }
            }
            if let subline {
                subline
                    .font(AppFont.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .monospacedDigit()
                    .lineLimit(1)
            }
            if attentionCount > 0 {
                HStack(spacing: AppSpacing.xxs) {
                    Circle()
                        .fill(Color.brandWarning)
                        .frame(width: 5, height: 5)
                    (attentionCount == 1
                        ? Text("1 element needs attention")
                        : Text("\(attentionCount) elements need attention"))
                        .font(AppFont.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
            }
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.55)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - The trailing "+" card (dashed ghost)

/// The grid's create-space entry: same footprint as a space card, drawn as
/// a dashed ghost — clearly an invitation, never mistakable for a space
/// that exists.
private struct AddSpaceGridCard: View {
    let isCreating: Bool
    let onCreate: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
    }

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            onCreate()
        } label: {
            VStack(spacing: AppSpacing.sm) {
                if isCreating {
                    ProgressView()
                } else {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(24, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("est_create_space")
                    .font(AppFont.scaled(13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .background(shape.fill(Color.subtleFill))
            .overlay {
                shape.strokeBorder(Color.accentColor.opacity(0.45),
                                   style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
            }
            .clipShape(shape)
            .contentShape(shape)
        }
        .buttonStyle(SmartCardPressStyle())
        .accessibilityLabel(Text("est_create_space"))
    }
}
