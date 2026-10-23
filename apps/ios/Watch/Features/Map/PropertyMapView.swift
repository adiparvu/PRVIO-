import MapKit
import SwiftUI

// MARK: - Property map
//
// MapKit's native watch map: Digital Crown zoom and pan come free. The
// coordinates ride the payload, so the house marker is placed correctly even
// offline (only the tiles need a connection).
//
// Camera: until the user moves the map, the camera is derived from the
// payload, so a re-geocoded property recentres by itself. Once they pan or
// zoom, their position is kept until "Recenter" hands control back.

struct PropertyMapView: View {
    @Environment(WatchStore.self) private var store

    /// The user's own camera; nil follows the property. No initializer
    /// assigns it, so the default here is its only source.
    @State private var userPosition: MapCameraPosition? = nil

    /// Close enough to read the street, wide enough to place the house.
    private static let spanDegrees: CLLocationDegrees = 0.004

    init() {}

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = store.payload?.latitude,
              let longitude = store.payload?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var title: String {
        let name = store.payload?.snapshot.propertyName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "PRVIO" : name
    }

    var body: some View {
        Group {
            if let coordinate {
                map(at: coordinate)
            } else {
                EmptyStateView(systemImage: "map", titleKey: WatchModule.map.titleKey)
            }
        }
        .navigationTitle(Text(WatchModule.map.titleKey))
        .watchPageGround(WatchTheme.Tint.map)
    }

    private func map(at coordinate: CLLocationCoordinate2D) -> some View {
        let home = MapCameraPosition.region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: Self.spanDegrees, longitudeDelta: Self.spanDegrees)))
        let position = Binding<MapCameraPosition>(
            get: { userPosition ?? home },
            set: { newValue in
                // Only a user gesture detaches the camera from the property.
                if newValue.positionedByUser { userPosition = newValue }
            }
        )
        return Map(position: position) {
            Marker(title, systemImage: "house.fill", coordinate: coordinate)
                .tint(WatchTheme.Tint.map)
        }
        .toolbar {
            if userPosition != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(WatchTheme.Motion.smooth) { userPosition = nil }
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityLabel(Text("watch_map_recenter"))
                }
            }
        }
    }
}
