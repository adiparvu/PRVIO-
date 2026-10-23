import SwiftUI
import Observation
import MapKit
import CoreLocation

// MARK: - Navigation app hand-off (Hărți / Hărți Google / Waze)

/// Launches turn-by-turn directions to a coordinate in the user's choice of
/// navigation app. Apple Maps is always available; Google Maps and Waze are
/// tried through their app scheme first and fall back to their universal
/// link when the app isn't installed — open-and-handle-failure, never a
/// `canOpenURL` probe (deprecated in iOS 27), so no scheme needs declaring.
enum NavigationAppLauncher {
    struct Option: Identifiable { let id: String; let label: String }

    static func availableOptions() -> [Option] {
        // Always offer all three — when the app isn't installed we fall back
        // to its universal link (which routes to web or the App Store).
        [Option(id: "apple",  label: String(localized: "Hărți")),
         Option(id: "google", label: String(localized: "Hărți Google")),
         Option(id: "waze",   label: "Waze")]
    }

    /// Opens directions to (lat, lon) in the chosen app. `label` names the
    /// destination (e.g. the sender's name) in Apple Maps' pin/callout.
    static func open(_ optionId: String, lat: Double, lon: Double, label: String) {
        let encodedLabel = label.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Location"
        switch optionId {
        case "google":
            open(URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"),
                 fallback: URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)"))
        case "waze":
            open(URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes"),
                 fallback: URL(string: "https://waze.com/ul?ll=\(lat),\(lon)&navigate=yes"))
        default:
            // daddr= (directions to) triggers Apple Maps' driving-ETA callout,
            // matching the native "car icon + N minutes" preview.
            open(URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)&q=\(encodedLabel)"), fallback: nil)
        }
    }

    /// Tries the app URL; when no installed app takes it (completion reports
    /// `false`), opens the universal link instead.
    private static func open(_ url: URL?, fallback: URL?) {
        guard let url else {
            if let fallback { UIApplication.shared.open(fallback) }
            return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened, let fallback else { return }
            UIApplication.shared.open(fallback)
        }
    }
}

// MARK: - Location Bubble

struct LocationBubble: View {
    let lat: Double
    let lon: Double
    let isOwn: Bool
    var label: String = ""
    var hasTail: Bool = true
    var senderId: UUID? = nil
    /// The carrying message's created_at — a bubble may only render live if
    /// IT belongs to the current share window.
    var sentAt: String? = nil

    @State private var showDetail = false

    /// The sender's ACTIVE live share, if any — turns this bubble into the
    /// WhatsApp-style live variant that follows their position. Bound to the
    /// message: an older static location from the same sender must not light
    /// up just because a new share is running.
    private var liveRow: LiveLocation? {
        guard let row = LiveLocationService.shared.active.first(where: {
            ($0.userId == senderId || $0.userName == label)
                && ($0.expiresDate ?? .distantPast) > Date()
        }) else { return nil }
        guard let sentAt,
              let sent = AppDate.timestamp(from: sentAt),
              let started = AppDate.timestamp(from: row.startedAt) else { return nil }
        // Small tolerance: the message row can commit moments before the
        // live-location row does.
        return sent >= started.addingTimeInterval(-120) ? row : nil
    }

    private var coordinate: CLLocationCoordinate2D {
        liveRow?.coordinate ?? CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        let live = liveRow
        VStack(spacing: 0) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Annotation("", coordinate: coordinate) {
                    ChatMapAvatar(name: label, senderId: senderId, size: live != nil ? 38 : 30)
                }
            }
            .frame(width: 220, height: live != nil ? 120 : 140)
            .id(live?.updatedAt)
            .allowsHitTesting(false)

            if let live {
                VStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "location.fill")
                            .font(AppFont.scaled(11, weight: .bold))
                            .foregroundStyle(Color.brandSuccess)
                        if let end = live.expiresDate {
                            Text("Se distribuie până la \(end, style: .time)")
                                .font(AppFont.caption)
                                .foregroundStyle(.primary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)

                    if isOwn {
                        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5)
                        Button {
                            HapticFeedback.impact(.medium)
                            LiveLocationService.shared.stop()
                        } label: {
                            Text("Oprește distribuirea")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color.brandDanger)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 220)
                .background(.thinMaterial)
            }
        }
        .clipShape(ChatBubbleShape(isOwn: isOwn, hasTail: hasTail))
        .overlay(alignment: .topLeading) {
            if live == nil {
                Image(systemName: "car.fill")
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.white)
                    .padding(AppSpacing.sm)
                    .background(Color.accentColor, in: Circle())
                    .padding(AppSpacing.sm)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showDetail = true }
        // Collapse the map + badge into one VoiceOver stop — otherwise it exposes
        // MapKit's own complex accessibility tree, which reads poorly here.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.isEmpty ? Text("Shared location") : Text(label))
        .accessibilityHint("Choose a navigation app to get directions")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showDetail) {
            LocationDetailSheet(lat: lat, lon: lon, label: label, isOwn: isOwn, senderId: senderId)
        }
    }
}

// MARK: - Map avatar marker

/// Sender avatar rendered as a map marker (photo when the member directory
/// has one, initials otherwise) — the WhatsApp live-location look.
struct ChatMapAvatar: View {
    let name: String
    let senderId: UUID?
    var size: CGFloat = 34

    var body: some View {
        ZStack {
            if let id = senderId, let url = MemberDirectory.shared.avatarURL(for: id) {
                StorageImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                    } else {
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.85))
            Text(String(name.prefix(2)).uppercased())
                .font(.system(size: size * 0.36, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Full-screen location detail (live map + navigation hand-off)

struct LocationDetailSheet: View {
    let lat: Double
    let lon: Double
    let label: String
    let isOwn: Bool
    var senderId: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    private var liveRow: LiveLocation? {
        LiveLocationService.shared.active.first {
            ($0.userId == senderId || $0.userName == label)
                && ($0.expiresDate ?? .distantPast) > Date()
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        liveRow?.coordinate ?? CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                ))) {
                    Annotation(isOwn ? String(localized: "Tu") : label, coordinate: coordinate) {
                        ChatMapAvatar(name: label, senderId: senderId, size: 46)
                    }
                }
                .id(liveRow?.updatedAt)
                .ignoresSafeArea(edges: .bottom)

                bottomCard
            }
            .navigationTitle(liveRow != nil ? String(localized: "Locație în timp real")
                                            : String(localized: "Locație"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(AppFont.subheadline)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            // Follow the sharer while the sheet is open.
            while !Task.isCancelled {
                await LiveLocationService.shared.refresh()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private var bottomCard: some View {
        VStack(spacing: 12) {
            if let live = liveRow {
                HStack(spacing: 12) {
                    ChatMapAvatar(name: label, senderId: senderId, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isOwn ? String(localized: "Tu") : label)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        Text(String(format: String(localized: "Timp rămas: %d min"), live.minutesLeft))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.secondaryTextColor)
                    }
                    Spacer()
                    if isOwn {
                        Button {
                            HapticFeedback.impact(.medium)
                            LiveLocationService.shared.stop()
                            dismiss()
                        } label: {
                            Text("Oprește distribuirea")
                                .font(AppFont.footnoteEmphasis)
                                .foregroundStyle(Color.brandDanger)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: AppSpacing.sm) {
                ForEach(NavigationAppLauncher.availableOptions()) { opt in
                    Button {
                        NavigationAppLauncher.open(opt.id, lat: coordinate.latitude,
                                                   lon: coordinate.longitude,
                                                   label: label.isEmpty ? "Location" : label)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(AppFont.scaled(13))
                            Text(opt.label)
                                .font(AppFont.captionEmphasis)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Color.accentColor.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(AppSpacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(AppSpacing.lg)
    }
}

// MARK: - Address search (live suggestions as you type)

@Observable
final class AddressSearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(query: String) {
        guard !query.isEmpty else { results = []; return }
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async -> MKMapItem? {
        await withCheckedContinuation { cont in
            let request = MKLocalSearch.Request(completion: completion)
            MKLocalSearch(request: request).start { response, _ in
                cont.resume(returning: response?.mapItems.first)
            }
        }
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) { results = completer.results }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

// MARK: - Nearby places (no query needed — points of interest around a coordinate)

@MainActor
@Observable
final class NearbyPlacesFinder {
    var places: [MKMapItem] = []

    func search(around coordinate: CLLocationCoordinate2D) {
        let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: 800)
        MKLocalSearch(request: request).start { [weak self] response, _ in
            guard let response else { return }
            Task { @MainActor in self?.places = Array(response.mapItems.prefix(6)) }
        }
    }
}

// MARK: - Location Share Sheet
//
// Styled after the native iOS "Trimitere locație" (Send Location) picker: a
// search bar for addresses, the current-location map, a prominent live-share
// row, and a "Locuri din apropiere" (nearby places) list.

struct LocationShareSheet: View {
    var propertyId: UUID? = nil
    var myName: String = ""
    let onShare: (Double, Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var locMgr = LocationManager()
    private let live = LiveLocationService.shared
    @State private var completer = AddressSearchCompleter()
    @State private var nearby = NearbyPlacesFinder()

    @State private var searchText = ""
    @State private var pendingLiveDuration: TimeInterval? = nil
    /// A place picked from search or the nearby list; nil = share current location.
    @State private var pickedPlace: MKMapItem?
    /// A coordinate chosen by long-pressing the map — independent from
    /// `pickedPlace`, rendered as its own red pin with a confirm row.
    @State private var droppedPin: CLLocationCoordinate2D?
    /// Best-effort reverse-geocoded name for the dropped pin. Display only —
    /// sending never waits on it (nil falls back to a generic label).
    @State private var droppedPinName: String?
    /// Invalidates in-flight reverse-geocodes when the pin moves or clears.
    @State private var pinGeneration = 0
    @State private var isResolvingPropertyAddress = false
    @State private var propertyAddressFailed = false
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mapCenter: CLLocationCoordinate2D? {
        pickedPlace?.placemark.coordinate ?? locMgr.location?.coordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                VStack(spacing: 0) {
                    searchField
                    if let center = mapCenter {
                        MapReader { proxy in
                            Map(initialPosition: .region(MKCoordinateRegion(
                                center: center,
                                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                            ))) {
                                Marker(pickedPlace?.name ?? String(localized: "Me"), coordinate: center).tint(.blue)
                                ForEach(live.othersSharing) { s in
                                    Marker(s.userName, systemImage: "dot.radiowaves.left.and.right", coordinate: s.coordinate)
                                        .tint(.orange)
                                }
                                if let pin = droppedPin {
                                    Marker(droppedPinName ?? String(localized: "loc_dropped_pin"),
                                           systemImage: "mappin", coordinate: pin)
                                        .tint(Color.brandDanger)
                                }
                            }
                            // Long-press drops a pin: once the stationary press is
                            // recognized, the zero-distance drag captures the finger's
                            // screen point and MapProxy.convert maps it to a coordinate.
                            // Plain `.gesture` leaves pan/zoom untouched — any movement
                            // fails the long press and the map's own gestures win.
                            .gesture(
                                LongPressGesture(minimumDuration: 0.35)
                                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                    .onEnded { value in
                                        guard case .second(true, let drag?) = value,
                                              let coordinate = proxy.convert(drag.location, from: .local)
                                        else { return }
                                        dropPin(at: coordinate)
                                    }
                            )
                        }
                        .frame(maxWidth: .infinity).frame(height: 260)
                        // Top-aligned so it never covers Apple's attribution (bottom-left).
                        .overlay(alignment: .top) {
                            if droppedPin == nil {
                                Text("loc_long_press_hint")
                                    .font(AppFont.caption2)
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                    .padding(.horizontal, AppSpacing.md).padding(.vertical, AppSpacing.xs)
                                    .background(.thinMaterial, in: Capsule())
                                    .padding(.top, AppSpacing.sm)
                                    .allowsHitTesting(false)
                                    .transition(.opacity)
                            }
                        }

                        ScrollView(showsIndicators: false) {
                            VStack(spacing: 16) {
                                if let pin = droppedPin {
                                    droppedPinRow(pin)
                                        .transition(reduceMotion
                                                    ? AnyTransition.opacity
                                                    : .move(edge: .top).combined(with: .opacity))
                                }
                                if !completer.results.isEmpty {
                                    searchResultsList
                                } else {
                                    if !live.othersSharing.isEmpty {
                                        Text(live.othersSharing.count == 1
                                             ? String(format: String(localized: "%@ is sharing live location"), live.othersSharing[0].userName)
                                             : String(format: String(localized: "%d people are sharing live location"), live.othersSharing.count))
                                            .font(AppFont.scaled(12)).foregroundStyle(.orange)
                                    }
                                    liveShareRow
                                    nearbyPlacesSection
                                }
                            }
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.base)
                            .padding(.bottom, 30)
                        }
                    } else {
                        Spacer()
                        ProgressView().tint(.white)
                        Text(LocalizedStringKey(locMgr.denied ? "Location access denied. Enable in Settings." : "Getting your location…"))
                            .font(AppFont.scaled(14)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        Spacer()
                    }
                }
            }
            .navigationTitle("Trimitere locație").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Text cancel button, matching the app's other sheets.
                    Button("Anulează") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { locMgr.requestLocation() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh location")
                }
            }
        }
        .sheetGround()
        .task {
            locMgr.onLocation = { [weak nearby] loc in nearby?.search(around: loc.coordinate) }
            locMgr.requestLocation()
        }
        .task(id: propertyId) {
            guard let pid = propertyId else { return }
            while !Task.isCancelled {
                await live.load(propertyId: pid)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        .onChange(of: searchText) { _, text in completer.update(query: text) }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Color.primary.opacity(0.4))
            TextField("Caută sau introdu o adresă", text: $searchText)
                .font(AppFont.scaled(15))
            if !searchText.isEmpty {
                Button { searchText = ""; pickedPlace = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.primary.opacity(0.4))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, AppSpacing.base).padding(.vertical, 10)
        .background(Color.primary.opacity(AppOpacity.hairline), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 10)
    }

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(completer.results.enumerated()), id: \.offset) { _, r in
                Button {
                    Task {
                        if let item = await completer.resolve(r) {
                            pickedPlace = item
                            searchText = r.title
                            completer.results = []
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.title).font(AppFont.body).foregroundStyle(.primary)
                        if !r.subtitle.isEmpty {
                            Text(r.subtitle).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
    }

    private var liveShareRow: some View {
        Group {
            if live.isSharing {
                VStack(spacing: 6) {
                    Button(role: .destructive) { live.stop() } label: {
                        Label("Stop sharing live location", systemImage: "location.slash.fill")
                            .font(AppFont.body).foregroundStyle(.red)
                            .frame(maxWidth: .infinity).padding(.vertical, 13)
                            .liquidGlass(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                    if let exp = live.sharingExpiresAt {
                        Text("Sharing live until \(exp, style: .time)")
                            .font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    }
                }
            } else {
                Menu {
                    Button("15 minutes") { pendingLiveDuration = 900 }
                    Button("1 hour")     { pendingLiveDuration = 3600 }
                    Button("8 hours")    { pendingLiveDuration = 28800 }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "location.circle.fill").font(AppFont.scaled(18))
                        Text("Distribuie locația în timp real").font(AppFont.body)
                        Spacer()
                    }
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity).padding(.vertical, 13).padding(.horizontal, AppSpacing.base)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(propertyId == nil)
            }
        }
        // WhatsApp-style consent alert before the live share actually starts.
        .alert("Distribuie locația în timp real", isPresented: Binding(
            get: { pendingLiveDuration != nil },
            set: { if !$0 { pendingLiveDuration = nil } }
        )) {
            Button("Anulează", role: .cancel) { pendingLiveDuration = nil }
            Button("OK") {
                if let d = pendingLiveDuration { startLive(d) }
                pendingLiveDuration = nil
            }
        } message: {
            // Honesty: only promise background sharing when the OS has actually
            // granted Always authorization; otherwise state it shares while the
            // app is open. (A ternary of string literals resolves to `String`,
            // which picks Text's non-localized initializer — bind the key to
            // `LocalizedStringKey` first so it stays localizable.)
            let consentKey: LocalizedStringKey = live.canShareInBackground
                ? "live_share_consent_always"
                : "live_share_consent_foreground"
            Text(consentKey)
        }
    }

    private var nearbyPlacesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Locuri din apropiere")
                .font(AppFont.captionEmphasis)
                .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))

            Button {
                pickedPlace = nil
                if let loc = locMgr.location {
                    onShare(loc.coordinate.latitude, loc.coordinate.longitude)
                    dismiss()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.circle.fill")
                        .font(AppFont.scaled(22)).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Trimite locația curentă").font(AppFont.body).foregroundStyle(.primary)
                        if let acc = locMgr.location?.horizontalAccuracy, acc > 0 {
                            Text("Cu o aproximație de \(Int(acc))m")
                                .font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            Divider().opacity(0.3)

            if let address = propertyAddress {
                propertyAddressRow(address)
                Divider().opacity(0.3)
            }

            ForEach(Array(nearby.places.enumerated()), id: \.offset) { _, item in
                Button {
                    pickedPlace = item
                    onShare(item.placemark.coordinate.latitude, item.placemark.coordinate.longitude)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(AppFont.scaled(22)).foregroundStyle(Color.primary.opacity(0.4))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name ?? "").font(AppFont.body).foregroundStyle(.primary)
                            if let addr = item.placemark.title {
                                Text(addr).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText)).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, AppSpacing.sm)
                }
                .buttonStyle(.plain)
                Divider().opacity(0.3)
            }
        }
    }

    // MARK: Dropped pin (manual map selection)

    private func dropPin(at coordinate: CLLocationCoordinate2D) {
        HapticFeedback.impact(.medium)
        pinGeneration += 1
        let generation = pinGeneration
        droppedPinName = nil
        if reduceMotion {
            droppedPin = coordinate
        } else {
            withAnimation(.snappy) { droppedPin = coordinate }
        }
        // Best-effort display name; the confirm row shows a generic label
        // until (unless) it resolves. Sending never waits on this.
        Task {
            let name = await Self.reverseGeocodedName(for: coordinate)
            guard generation == pinGeneration, droppedPin != nil else { return }
            droppedPinName = name
        }
    }

    private func clearPin() {
        pinGeneration += 1
        droppedPinName = nil
        if reduceMotion {
            droppedPin = nil
        } else {
            withAnimation(.snappy) { droppedPin = nil }
        }
    }

    private static func reverseGeocodedName(for coordinate: CLLocationCoordinate2D) async -> String? {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first else { return nil }
        let street = mark.thoroughfare.map { t in
            mark.subThoroughfare.map { "\(t) \($0)" } ?? t
        }
        let parts = [street ?? mark.name, mark.locality].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func droppedPinRow(_ pin: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 12) {
            Button {
                // Same send path as "current location" — coordinates only,
                // so a missing geocoded name can never block the send.
                onShare(pin.latitude, pin.longitude)
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.circle.fill")
                        .font(AppFont.scaled(22)).foregroundStyle(Color.brandDanger)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("loc_send_chosen_location").font(AppFont.body).foregroundStyle(.primary)
                        Text(droppedPinName ?? String(localized: "loc_dropped_pin_generic"))
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button { clearPin() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(AppFont.scaled(18))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("loc_clear_pin")
        }
        .padding(.vertical, 10).padding(.horizontal, AppSpacing.base)
        .background(Color.brandDanger.opacity(AppOpacity.subtleFill),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: Property address

    /// The primary property's postal address — nil unless a street address is
    /// actually set, which hides the row entirely (no dead controls).
    private var propertyAddress: String? {
        guard let p = propertyService.primary, !p.addressLine1.isEmpty else { return nil }
        let joined = [p.addressLine1, p.city, p.country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    private func propertyAddressRow(_ address: String) -> some View {
        Button {
            Task { await sendPropertyAddress(address) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "house.circle.fill")
                    .font(AppFont.scaled(22)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("loc_send_property_address").font(AppFont.body).foregroundStyle(.primary)
                    if isResolvingPropertyAddress {
                        Text("loc_locating_address")
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    } else if propertyAddressFailed {
                        Text("loc_property_address_error")
                            .font(AppFont.scaled(12)).foregroundStyle(Color.brandDanger)
                    } else {
                        Text(address)
                            .font(AppFont.scaled(12))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isResolvingPropertyAddress { ProgressView().controlSize(.small) }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isResolvingPropertyAddress)
    }

    /// Sends the property's location through the same path as every other row:
    /// stored coordinates when present, otherwise a one-shot geocode of the
    /// address string (the dashboard map widget's approach). On failure the
    /// sheet stays open with an inline, retryable error.
    private func sendPropertyAddress(_ address: String) async {
        if let lat = propertyService.primary?.latitude,
           let lon = propertyService.primary?.longitude {
            onShare(lat, lon)
            dismiss()
            return
        }
        isResolvingPropertyAddress = true
        propertyAddressFailed = false
        defer { isResolvingPropertyAddress = false }
        let placemarks = (try? await CLGeocoder().geocodeAddressString(address)) ?? []
        if let loc = placemarks.first?.location {
            onShare(loc.coordinate.latitude, loc.coordinate.longitude)
            dismiss()
        } else {
            propertyAddressFailed = true
            HapticFeedback.error()
        }
    }

    private func startLive(_ duration: TimeInterval) {
        guard let pid = propertyId else { return }
        live.start(propertyId: pid, userName: myName, duration: duration)
        // The share must be visible in the conversation: drop the current
        // coordinate into the chat immediately, then close the sheet — the
        // live marker keeps updating via LiveLocationService.
        if let loc = locMgr.location {
            onShare(loc.coordinate.latitude, loc.coordinate.longitude)
        }
        dismiss()
    }
}

// MARK: - Mention Picker Sheet

struct MentionPickerSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Binding var selectedIds: [String]
    @Binding var selectedNames: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView {
                    VStack(spacing: 0) {
                        MemberPickerView(selectedIds: $selectedIds, selectedNames: $selectedNames)
                            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                    }
                }
            }
            .navigationTitle("Mention").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                }
            }
        }
        .sheetGround()
    }
}

// MARK: - Location Manager

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    var location: CLLocation?
    var denied = false
    /// Fires once a location arrives. CLLocation isn't Equatable, so callers
    /// that need to react to updates (e.g. nearby-places search) hook this
    /// instead of using SwiftUI's onChange(of:).
    var onLocation: ((CLLocation) -> Void)?
    private let mgr = CLLocationManager()

    override init() {
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestLocation() {
        let status = mgr.authorizationStatus
        if status == .notDetermined { mgr.requestWhenInUseAuthorization() }
        else if status == .denied { denied = true }
        else { mgr.requestLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .denied { denied = true }
        else if manager.authorizationStatus != .notDetermined { mgr.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
        guard let loc = location else { return }
        let callback = onLocation
        Task { @MainActor in callback?(loc) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
