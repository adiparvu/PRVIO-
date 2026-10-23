import SwiftUI
import RoomPlan
import PhotosUI

// MARK: - Space detail page (Estate OS E2 — Liquid Glass)
//
// The ONE template every space kind shares — presentation-agnostic: a
// sheet from the dashboard's "Domeniul" strip (the original contract,
// unchanged) or a NavigationStack push from the Spaces tab (`presentation:
// .push`, which hides the system bar and drops the tab-switching menu
// entry — from tab 2 it would route to itself). The page sits on the
// app-wide mood backdrop (the zone's own photo stays where it is content —
// the grid/strip cards), with ~140pt of breathing ground, then the space
// NAME floating free over it — no card, no chenar — in the app's light
// typography, with a small "Domeniul · <kind>" kicker above and an honest
// status pill below.
//
// Honest states throughout (honesty law):
// - Status pill: "Fără senzori încă" with zero linked sensors; "Fără
//   semnal" when sensors exist but none has delivered a reading; "Necesită
//   atenție" when any linked sensor is genuinely alerting; "În parametri"
//   only when live readings exist and none alerts.
// - Metrics: up to 3 glass tiles from the zone's REAL linked IoT sensors
//   (linked by zone name in the IoT hub — the one sensor→zone link the app
//   has). No sensors → one empty-state glass card that says so and explains
//   where linking happens. Never a fabricated pH/EC/level tile.
// - Devices: `SmartHomeService.devices(in: zone.name)` rows (IoT sensors
//   excluded — they already ARE the metrics row); the pill toggle is
//   drawn only for devices with the real `.power` capability. No devices →
//   an honest empty row.
// - Scenes (Smart Control R2): quick chips for the HomeKit scenes whose
//   actions genuinely touch an accessory in THIS room (write action →
//   characteristic → accessory → room, matched to the zone by the shared
//   name link). No matching scene → the section simply doesn't exist.
// - Kind extras: garden/greenhouse spaces list plants needing water whose
//   free-text location names THIS zone (the same name-based link sensors
//   use) — the section simply doesn't exist without such plants.
// - Toolbar menu: the SpaceKind picker persists through
//   `PropertyZoneService.setSpaceKind`, and "Deschide în Control" routes to
//   the real Digital Twin tab — both live controls, nothing dead.
//
// Live-state contract mirrors SmartDeviceSheet: the presented zone is a
// value snapshot, so the page re-resolves the live zone from
// PropertyZoneService by id on every render — a saved kind re-dresses the
// open page the moment the reload lands.

struct SpaceDetailView: View {
    /// How the page is on screen — `dismiss` handles both (sheet dismissal
    /// / stack pop); the difference is chrome and the toolbar menu's
    /// tab-switching entry.
    enum Presentation { case sheet, push }

    /// Snapshot from the presenting surface — identity + fallback only.
    let zone: PropertyZone
    var presentation: Presentation = .sheet

    @Environment(\.dismiss) private var dismiss
    @Environment(PropertyZoneService.self) private var zoneService
    @Environment(PlantService.self) private var plantService
    @Environment(PropertyElementService.self) private var elementService
    @Environment(FloorPlanService.self) private var floorPlanService
    @Environment(AppRouter.self) private var router

    /// The sensor stream whose history sheet is up (R4) — nil when none.
    @State private var historyTarget: SensorHistoryTarget? = nil
    /// RoomPlan capture in flight (LiDAR devices only — the menu entry
    /// exists only when RoomCaptureSession.isSupported).
    @State private var showScanner = false
    /// The downloaded .usdz being previewed via QuickLook.
    @State private var scanPreviewURL: URL? = nil
    @State private var isFetchingScan = false
    /// Space photo (IMG_8638/8639): picker presentation + upload state.
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoTarget: SpacePhotoTarget = .backdrop
    @State private var isSavingPhoto = false
    /// The truthful failure of the last photo save — surfaced as an alert
    /// (IMG_9281: the silent error-haptic read as "it does nothing").
    @State private var photoError: String? = nil

    private let smartHome = SmartHomeService.shared
    /// Cached HomeKit indoor readings (Smart Control R3) — feeds the
    /// space's temperature tile when a sensor lives in this room.
    private let indoorClimate = IndoorClimateStore.shared

    /// The live projection of the presented zone; falls back to the
    /// snapshot if the zone vanished mid-presentation.
    private var live: PropertyZone {
        zoneService.zones.first { $0.id == zone.id } ?? zone
    }

    private var kind: SpaceKind { live.resolvedSpaceKind }

    /// The zone's linked IoT sensors — the shared `SpaceCardModel` match
    /// (trimmed zone name, like everywhere else the two worlds meet).
    private var zoneSensors: [IoTSensor] {
        SpaceCardModel.sensors(for: live)
    }

    /// Devices in this space across both providers, minus IoT sensors —
    /// those already render as the metrics row above.
    private var spaceDevices: [SmartDevice] {
        smartHome.devices(in: live.name).filter {
            if case .iotSensor = $0.backing { return false }
            return true
        }
    }

    /// Plants needing water located in this zone — the shared
    /// `SpaceCardModel` name-based link. Empty when plants aren't tied here.
    private var thirstyPlants: [Plant] {
        SpaceCardModel.thirstyPlants(in: live, plantService: plantService)
    }

    /// HomeKit scenes whose actions touch an accessory in THIS room —
    /// resolved per render from the mirrored homes (empty when HomeKit is
    /// unauthorized), through the shared name link between the two worlds.
    private var spaceScenes: [HomeKitScene] {
        HomeKitService.shared.scenes(touchingSpaceNamed: live.name)
    }

    var body: some View {
        // System chrome in BOTH presentations (IMG_9276): pushed, the
        // system bar's own glass back circle; as a sheet, a fresh
        // NavigationStack so the SAME toolbar hosts the close circle and
        // the page's one menu. The hand-drawn in-body circles were the
        // last of the IMG_8555 exceptions — this page and every future
        // one ride the system toolbar, like the rest of the app.
        if presentation == .sheet {
            NavigationStack { core }
        } else {
            core
        }
    }

    private var core: some View {
        ZStack {
            backdrop
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // The hero's breathing room: nothing but the mood ground.
                    Spacer().frame(height: SpaceHero.breath)
                    hero
                    metricsSection
                    devicesSection
                    let scenes = spaceScenes
                    if !scenes.isEmpty {
                        scenesSection(scenes)
                    }
                    // The zone's mapped elements — id-linked (zone_id), so
                    // this is the strongest link the page renders. Absent
                    // when nothing is mapped here (never an empty section).
                    let elements = elementService.elements(inZone: live.id)
                    if !elements.isEmpty {
                        elementsSection(elements)
                    }
                    if kind == .garden || kind == .greenhouse, !thirstyPlants.isEmpty {
                        plantsSection
                    }
                    // The dossier: journal photos, paint colors and tagged
                    // expenses recorded about THIS space (E3).
                    SpaceDossierSections(zone: live)
                    Spacer(minLength: AppSpacing.xxl)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.lg)
            }
        }
        // Sheet chrome (ignored when pushed).
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // Indoor climate (R3): fresh-enough readings on arrival, a real
        // readValue fan-out on pull-to-refresh — the page's manual refresh.
        .refreshable { await indoorClimate.refresh() }
        .task { await indoorClimate.refreshIfStale() }
        // History (R4): tapping a metric tile opens the sensor's iot_events
        // line — HomeKit tiles under their mirrored id, IoT tiles under
        // their sensor id.
        .sheet(item: $historyTarget) { target in
            SensorHistorySheet(target: target)
        }
        // Space photo (IMG_8638/8639): the system picker, opened from the
        // page's one menu; the upload runs off-main and the row update
        // re-dresses every surface.
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            photoItem = nil
            Task { await savePhoto(newItem) }
        }
        // Honest failure (IMG_9281): an upload that dies must SAY so —
        // the error haptic alone read as "the button does nothing".
        .alert(Text("est_photo_failed"),
               isPresented: Binding(get: { photoError != nil },
                                    set: { if !$0 { photoError = nil } })) {
            Button(role: .cancel) {} label: { Text("OK") }
        } message: {
            Text(verbatim: photoError ?? "")
        }
        // System toolbar chrome: no title (the hero carries the name);
        // pushed pages keep the system back button, sheets get a close
        // circle in the same slot.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if presentation == .sheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        HapticFeedback.impact(.light)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                    }
                    .accessibilityLabel(Text("sh_close"))
                }
            }
            ToolbarItem(placement: .pageMenu) {
                spaceMenu
            }
        }
        // Plan rooms hydrate lazily on first arrival — the scan menu
        // entries need the zone's bridged room to state the truth.
        .task(id: live.propertyId) {
            if floorPlanService.propertyId != live.propertyId {
                await floorPlanService.load(propertyId: live.propertyId)
            }
        }
        .fullScreenCover(isPresented: $showScanner) {
            RoomScanView { url in
                showScanner = false
                guard let url else { return }
                HapticFeedback.success()
                Task {
                    // The scan lands on the zone's plan room, created on
                    // demand — ONE storage slot per room, upsert on re-scan.
                    if let room = await floorPlanService.ensureRoom(for: live) {
                        await floorPlanService.attachScan(fileURL: url, to: room)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { scanPreviewURL != nil },
            set: { if !$0 { scanPreviewURL = nil } }
        )) {
            if let url = scanPreviewURL {
                QuickLookSheet(url: url, title: live.name)
            }
        }
        .overlay {
            if isFetchingScan || isSavingPhoto {
                ProgressView()
                    .padding(AppSpacing.xl)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            }
        }
    }

    /// The zone's plan-room projection (migration 159's id-link, name as
    /// the pre-bridge fallback).
    private var bridgedRoom: RoomRecord? {
        floorPlanService.room(for: live)
    }

    private func openScan() {
        // No haptic here — the invoking GlassFilterActionRow already fired
        // the tap haptic.
        guard !isFetchingScan, let room = bridgedRoom else { return }
        isFetchingScan = true
        Task {
            let url = await floorPlanService.localScanURL(for: room)
            isFetchingScan = false
            if let url { scanPreviewURL = url }
        }
    }

    /// Presents AFTER the menu's dismissal transition has truly ended
    /// (IMG_9281): the system runs menu actions post-dismissal, but iOS 27's
    /// picker/cover presentation still lands inside the closing window and
    /// is silently dropped — the photo rows and the scanner "did nothing"
    /// on device. One deliberate beat later, presentation succeeds every
    /// time; the hop is imperceptible and harmless where it wasn't needed.
    private func presentAfterMenuDismissal(_ present: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            present()
        }
    }

    // MARK: Backdrop — the app-wide living mood ground

    /// The mood ground, and — when the space has its photo — the photo as
    /// the page's upper band, fading into the mood with a top scrim so the
    /// glass circles and the white hero type keep their contrast.
    private var backdrop: some View {
        ZStack(alignment: .top) {
            appBackground
            if let photo = live.photoUrl, !photo.isEmpty {
                Color.clear
                    .frame(height: 360)
                    .overlay {
                        StorageImage(source: photo, targetSize: 480) { phase in
                            if case .success(let image) = phase {
                                image.resizable().scaledToFill()
                            }
                        }
                    }
                    .clipped()
                    .mask(LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        LinearGradient(colors: [.black.opacity(0.38), .clear],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }

    // MARK: The page's one menu (one-circle law, in the system toolbar)

    /// The kind picker as a single-select section, the navigation/scan
    /// entries as one-shot action rows. Apple's More glyph — the menu
    /// hosts actions, not list filters, and setting a kind narrows
    /// nothing, so no accent dot ever.
    private var spaceMenu: some View {
        GlassFilterButton(inToolbar: true,
                          icon: "ellipsis",
                          accessibilityLabelKey: "est_kind_menu") {
                GlassFilterSection(
                    title: "est_kind_menu",
                    options: SpaceKind.allCases.map {
                        GlassPickerOption(value: $0, icon: $0.icon, title: $0.title)
                    },
                    selection: kindBinding)
                // Hairline only when at least one action row follows —
                // never a divider hanging under the last section.
                if presentation == .sheet || RoomCaptureSession.isSupported
                    || bridgedRoom?.hasScan == true {
                    GlassFilterSectionDivider()
                }
                if presentation == .sheet {
                    // From the home strip's sheet this jumps to tab 2 (the
                    // Spaces page). Pushed FROM that tab it would route to
                    // itself, so it doesn't exist there — no dead controls.
                    GlassFilterActionRow(icon: "square.split.2x2",
                                         title: String(localized: "est_open_twin")) {
                        dismiss()
                        router.navigate(to: .twin)
                    }
                }
                // RoomPlan (LiDAR) — the entry exists only on capable
                // hardware; "view" only when a scan genuinely exists on the
                // zone's bridged plan room.
                if RoomCaptureSession.isSupported {
                    GlassFilterActionRow(icon: "cube.transparent",
                                         title: bridgedRoom?.hasScan == true
                                             ? String(localized: "room_rescan")
                                             : String(localized: "est_scan_space")) {
                        presentAfterMenuDismissal { showScanner = true }
                    }
                }
                if bridgedRoom?.hasScan == true {
                    GlassFilterActionRow(icon: "eye",
                                         title: String(localized: "room_view_scan")) {
                        openScan()
                    }
                }
                // Two separate identities (migration 168): the BACKDROP
                // dresses the card and the page ground; the AVATAR is the
                // small identity disc in the hero.
                GlassFilterSectionDivider()
                GlassFilterActionRow(icon: "photo",
                                     title: String(localized: hasPhoto
                                         ? "est_change_backdrop" : "est_set_backdrop")) {
                    photoTarget = .backdrop
                    presentAfterMenuDismissal { showPhotoPicker = true }
                }
                if hasPhoto {
                    GlassFilterActionRow(icon: "photo.badge.arrow.down",
                                         title: String(localized: "est_remove_backdrop")) {
                        var updated = live
                        updated.photoUrl = nil
                        Task { await zoneService.update(updated) }
                    }
                }
                GlassFilterActionRow(icon: "person.crop.circle",
                                     title: String(localized: hasAvatar
                                         ? "est_change_avatar" : "est_set_avatar")) {
                    photoTarget = .avatar
                    presentAfterMenuDismissal { showPhotoPicker = true }
                }
                if hasAvatar {
                    GlassFilterActionRow(icon: "person.crop.circle.badge.xmark",
                                         title: String(localized: "est_remove_avatar")) {
                        var updated = live
                        updated.avatarUrl = nil
                        Task { await zoneService.update(updated) }
                    }
                }
        }
    }

    private var hasPhoto: Bool { live.photoUrl?.isEmpty == false }
    private var hasAvatar: Bool { live.avatarUrl?.isEmpty == false }

    /// Which slot the picker fills — the page backdrop or the identity disc.
    private enum SpacePhotoTarget { case backdrop, avatar }

    /// Uploads the picked image into the chosen slot. A fresh object name
    /// per upload (the public bucket caches aggressively — a fixed name
    /// would show the OLD photo after a change), then the zone row updates
    /// and every surface re-dresses from the service.
    private func savePhoto(_ pickerItem: PhotosPickerItem) async {
        guard !isSavingPhoto else { return }
        isSavingPhoto = true
        defer { isSavingPhoto = false }
        guard let data = try? await pickerItem.loadTransferable(type: Data.self) else {
            photoError = String(localized: "est_photo_load_failed")
            return
        }
        let target = photoTarget
        let compressed = await Task.detached(priority: .userInitiated) {
            // The avatar renders at 56pt — cap it small so the disc loads
            // instantly; the backdrop keeps full display quality.
            UIImage(data: data).flatMap {
                target == .avatar ? $0.uploadJPEG(quality: 0.82, maxDimension: 512)
                                  : $0.uploadJPEG(quality: 0.82)
            } ?? data
        }.value
        do {
            let prefix = target == .avatar ? "avatar" : "cover"
            let path = "zones/\(live.id.uuidString.lowercased())/\(prefix)-\(UUID().uuidString.lowercased()).jpg"
            let url = try await SignedStorage.uploadPublicImage(compressed, path: path, upsert: true)
            var updated = live
            if target == .avatar { updated.avatarUrl = url } else { updated.photoUrl = url }
            await zoneService.update(updated)
            HapticFeedback.success()
        } catch {
            HapticFeedback.error()
            photoError = error.recordableDescription
        }
    }

    /// Selecting a kind persists it through the service extension (targeted
    /// PATCH + sanctioned reload); the open page re-dresses from `live`.
    private var kindBinding: Binding<SpaceKind> {
        Binding(
            get: { kind },
            set: { newKind in
                guard newKind != kind else { return }
                // No haptic here — the hosting GlassFilterSection already
                // fires the selection haptic on the row tap.
                let current = live
                Task { @MainActor in
                    await zoneService.setSpaceKind(newKind, for: current,
                                                   propertyId: current.propertyId)
                }
            })
    }

    // MARK: Hero — kicker, the free-floating name, the honest status pill

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // The round identity disc — its OWN avatar photo when set
            // (migration 168), else the backdrop as before.
            if let photo = live.avatarUrl?.isEmpty == false ? live.avatarUrl : live.photoUrl,
               !photo.isEmpty {
                StorageImage(source: photo, targetSize: 64) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        kind.sceneGradient
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                .accessibilityHidden(true)
            }
            Text(verbatim: "\(String(localized: "est_domain")) · \(kind.title)")
                .font(AppFont.scaled(11, weight: .semibold))
                .foregroundStyle(hasPhoto ? AnyShapeStyle(Color.white.opacity(0.78))
                                          : AnyShapeStyle(.secondary))
            Text(verbatim: live.name)
                .font(AppFont.scaled(SpaceHero.nameSize, weight: .light))
                .kerning(SpaceHero.nameTracking)
                // White on the photo's scrim (the grid card's legibility
                // contract); the adaptive primary on the bare mood ground.
                .foregroundStyle(hasPhoto ? AnyShapeStyle(Color.white)
                                          : AnyShapeStyle(.primary))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            statusPill
        }
        .accessibilityElement(children: .combine)
    }

    /// The pill's honest states — the shared `SpaceCardModel` priority
    /// order (also the Spaces tab's card dot).
    private var status: SpaceStatus {
        SpaceCardModel.status(for: live)
    }

    private var statusPill: some View {
        let status = status
        return HStack(spacing: AppSpacing.xs) {
            if let dot = status.dotColor {
                Circle()
                    .fill(dot)
                    .frame(width: 6, height: 6)
            }
            Text(status.titleKey)
                .font(AppFont.scaled(12, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .glassCapsule()
    }

    // MARK: Metrics — up to 3 real sensor tiles, or the honest empty card

    /// This space's live HomeKit temperature (R3) — the accessory whose
    /// HomeKit room matches the zone by name, when one reported.
    private var homeKitReading: IndoorClimateReading? {
        indoorClimate.reading(forSpaceNamed: live.name)
    }

    @ViewBuilder private var metricsSection: some View {
        let reading = homeKitReading
        // The HomeKit temperature tile joins the row; IoT tiles fill the
        // remaining slots — the row stays capped at 3, like before.
        let sensors = Array(zoneSensors.prefix(reading == nil ? 3 : 2))
        if sensors.isEmpty && reading == nil {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                    Text("est_no_sensors_title")
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("est_no_sensors_caption")
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(spacing: AppSpacing.md) {
                if let reading {
                    metricTile(value: Self.degreesText(reading.celsius),
                               label: reading.accessoryName,
                               staleSince: nil,
                               history: SensorHistoryTarget(
                                   id: IoTService.homeKitSensorId(accessory: reading.id,
                                                                  metric: "temperature"),
                                   name: reading.accessoryName,
                                   unit: "°C",
                                   tint: IoTSensor.SensorType.temperature.color))
                }
                ForEach(sensors) { sensor in
                    metricTile(sensor)
                }
            }
        }
    }

    private func metricTile(_ sensor: IoTSensor) -> some View {
        // `displayValue` is the hub's own formatting: value + unit as
        // stored, "—" while no reading has arrived (never invented).
        // Freshness honesty (R4): a reading older than 24 h carries a
        // quiet relative stamp so stale never masquerades as live.
        metricTile(value: sensor.displayValue, label: sensor.name,
                   staleSince: SensorFreshness.isStale(sensor.lastUpdated)
                       ? sensor.lastUpdated : nil,
                   history: SensorHistoryTarget(id: sensor.id.uuidString,
                                                name: sensor.name,
                                                unit: sensor.unit,
                                                tint: sensor.type.color))
    }

    /// The one metric tile both worlds share — an IoT sensor's stored
    /// display value or a HomeKit accessory's live temperature. Tapping
    /// opens the stream's history sheet (R4).
    private func metricTile(value: String, label: String,
                            staleSince: Date?,
                            history: SensorHistoryTarget) -> some View {
        Button {
            HapticFeedback.impact(.light)
            historyTarget = history
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                Text(verbatim: value)
                    .font(AppFont.scaled(SpaceHero.metricValueSize, weight: .light))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: label)
                    .font(AppFont.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let staleSince {
                    Text(staleSince, format: .relative(presentation: .named))
                        .font(AppFont.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.base)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: AppRadius.xl)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("sh_history_title"))
    }

    /// "21,5 °C" — locale-aware, at most one decimal, the IoT tiles' format.
    private static func degreesText(_ celsius: Double) -> String {
        "\(celsius.formatted(.number.precision(.fractionLength(0...1)))) °C"
    }

    // MARK: Devices — real rows or the honest empty row

    private var devicesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("est_devices")
            if spaceDevices.isEmpty {
                HStack(spacing: AppSpacing.md) {
                    Image(systemName: "cube")
                        .font(AppFont.headline)
                        .foregroundStyle(.secondary)
                    Text("est_no_devices")
                        .font(AppFont.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, AppSpacing.base)
                .padding(.vertical, AppSpacing.md)
                .spaceGlassRow()
            } else {
                VStack(spacing: AppSpacing.sm) {
                    ForEach(spaceDevices) { device in
                        SpaceDeviceRow(device: device)
                    }
                }
            }
        }
    }

    // MARK: Scenes — quick chips for scenes touching THIS room (R2)

    /// Rendered only when ≥1 scene genuinely touches an accessory in this
    /// room — never an empty section. Execution is the shared chip-row
    /// contract: spinner, haptics, verbatim-error alert, still-running note.
    private func scenesSection(_ scenes: [HomeKitScene]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("sh_scene_section")
            SmartSceneChipRow(scenes: scenes)
        }
    }

    // MARK: Elements — the zone's mapped inventory, health-honest rows

    private func elementsSection(_ elements: [PropertyElement]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("est_elements")
            VStack(spacing: AppSpacing.sm) {
                // Worst health first — the row a caretaker needs is on top.
                ForEach(elements.sorted { $0.healthScore < $1.healthScore }) { element in
                    HStack(spacing: AppSpacing.md) {
                        Image(systemName: element.elementType.icon)
                            .font(AppFont.headline)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(element.healthColor)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: element.name)
                                .font(AppFont.scaled(14, weight: .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(verbatim: element.technicalCondition.displayName)
                                .font(AppFont.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: AppSpacing.xs)
                        Text(verbatim: "\(element.healthScore)")
                            .font(AppFont.scaled(14, weight: .semibold))
                            .foregroundStyle(element.healthColor)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, AppSpacing.md)
                    .spaceGlassRow()
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    // MARK: Kind extras — Plant OS chips (garden/greenhouse, real data only)

    private var plantsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionLabel("est_plants_water")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(thirstyPlants) { plant in
                        plantChip(plant)
                    }
                }
                .padding(.horizontal, AppSpacing.xxs)
            }
        }
    }

    /// Informational chip — deliberately NOT a button (no dead controls):
    /// it states which real plant is thirsty, nothing more.
    private func plantChip(_ plant: Plant) -> some View {
        HStack(spacing: AppSpacing.xxs) {
            Text(verbatim: plant.emoji)
                .font(AppFont.scaled(13))
            Text(verbatim: plant.name)
                .font(AppFont.scaled(13, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.sm)
        .liquidGlass(cornerRadius: AppRadius.md)
        .accessibilityElement(children: .combine)
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Device row (icon, name, honest state, pill toggle)

/// One slim glass row per device: kind icon, name, an honest one-line
/// state, and the pill toggle only when the device genuinely has `.power`
/// — the S2 hero card's contract at row density.
private struct SpaceDeviceRow: View {
    let device: SmartDevice

    private let smartHome = SmartHomeService.shared

    /// Optimistic hold while the provider round-trip is in flight — the
    /// same discipline as the dashboard's hero cards.
    @State private var pendingOn: Bool? = nil

    private var powerBinding: Binding<Bool> {
        Binding(
            get: { pendingOn ?? (device.isOn == true) },
            set: { on in
                pendingOn = on
                Task { @MainActor in
                    await smartHome.setPower(device, on: on)
                    pendingOn = nil
                }
            })
    }

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: device.kind.icon)
                .font(AppFont.headline)
                .foregroundStyle(device.kind.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: device.name)
                    .font(AppFont.scaled(15, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                stateLine
            }
            Spacer(minLength: AppSpacing.sm)
            if device.hasPower {
                SmartPillToggle(isOn: powerBinding,
                                accessibilityLabel: Text(verbatim: device.name))
                    .disabled(!device.isReachable)
            }
        }
        .padding(.horizontal, AppSpacing.base)
        .padding(.vertical, AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .spaceGlassRow()
    }

    /// Unreachable → reported power state → the kind name. Never a guess.
    @ViewBuilder private var stateLine: some View {
        if !device.isReachable {
            Text("sh_unreachable")
                .font(AppFont.caption2)
                .foregroundStyle(Color.brandWarning)
        } else if let isOn = device.isOn {
            Text(LocalizedStringKey((pendingOn ?? isOn) ? "sh_state_on" : "sh_state_off"))
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        } else {
            Text(LocalizedStringKey(device.kind.titleKey))
                .font(AppFont.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Slim glass row backing (shared by the rows above)

// Internal, not fileprivate: the dossier sections (SpaceDossierSections.swift,
// the same page's E3 file) render the same row surface.
extension View {
    func spaceGlassRow() -> some View {
        liquidGlass(cornerRadius: AppRadius.lg)
    }
}
