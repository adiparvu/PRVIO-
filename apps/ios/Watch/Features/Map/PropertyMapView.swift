import MapKit
import SwiftUI

// MARK: - Property map
//
// MapKit's native watch map — Digital Crown zoom and pan come free — kept
// calm: no points of interest, just the streets and the house. The house
// marker wears the page's sky accent, so the map belongs to the same sky
// as every other screen. Coordinates ride the payload, so the marker is
// placed correctly even offline (only the tiles need a connection).
//
// Camera: until the person moves the map, the camera follows the payload,
// so a re-geocoded property recentres by itself. Once they pan or zoom,
// their camera is kept until "Recenter" hands control back.

struct PropertyMapView: View {
    @Environment(WatchStore.self) private var store

    init() {}

    private var coordinate: CLLocationCoordinate2D? {
        guard let latitude = store.payload?.latitude,
              let longitude = store.payload?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var title: String {
        let name = store.payload?.snapshot.propertyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "PRVIO" : name
    }

    var body: some View {
        Group {
            if let coordinate {
                PropertyMap(coordinate: coordinate, title: title)
            } else {
                EmptyStateView(systemImage: "map", titleKey: WatchModule.map.titleKey,
                               messageKey: "watch_page_desc_map")
            }
        }
        .navigationTitle(Text(WatchModule.map.titleKey))
        .skyGround()
    }
}

// MARK: - Map

/// A child of `skyGround` so it can read the sky accent the ground
/// publishes (the modifier sets it for its content, not for the view that
/// applies it).
private struct PropertyMap: View {
    let coordinate: CLLocationCoordinate2D
    let title: String

    @Environment(\.watchSkyAccent) private var skyAccent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The person's own camera; nil follows the property. No initializer
    /// assigns it, so the default here is its only source.
    @State private var userPosition: MapCameraPosition? = nil

    /// Close enough to read the street, wide enough to place the house.
    private static let spanDegrees: CLLocationDegrees = 0.004

    private var home: MapCameraPosition {
        .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: Self.spanDegrees, longitudeDelta: Self.spanDegrees)))
    }

    var body: some View {
        let position = Binding<MapCameraPosition>(
            get: { userPosition ?? home },
            set: { newValue in
                // Only a gesture detaches the camera from the property.
                if newValue.positionedByUser { userPosition = newValue }
            }
        )
        Map(position: position) {
            Annotation(title, coordinate: coordinate, anchor: .center) {
                HouseMarker(accent: skyAccent ?? WatchTheme.Tint.map)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .toolbar {
            if userPosition != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.smooth,
                                                                 reduceMotion: reduceMotion)) {
                            userPosition = nil
                        }
                    } label: {
                        Image(systemName: "house.fill")
                    }
                    .accessibilityLabel(Text("watch_map_recenter"))
                }
            }
        }
    }
}

/// The house on the map: a disc in the sky accent (deepened so a pale
/// morning sky still carries a white glyph) with a white rim, the way
/// system pins read on any tile. A stroke only in Always On.
private struct HouseMarker: View {
    let accent: Color

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorSchemeContrast) private var contrast

    private var fill: Color { accent.mix(with: .black, by: 0.35) }

    var body: some View {
        Image(systemName: isLuminanceReduced ? "house" : "house.fill")
            .font(WatchTheme.Typography.glyph)
            .foregroundStyle(isLuminanceReduced ? fill : Color.white)
            .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
            .background {
                if isLuminanceReduced {
                    Circle().strokeBorder(fill.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                          lineWidth: WatchTheme.Stroke.outline(contrast))
                } else {
                    Circle()
                        .fill(fill)
                        .overlay {
                            Circle().strokeBorder(Color.white,
                                                  lineWidth: WatchTheme.Stroke.outline(contrast) * 1.5)
                        }
                }
            }
            .accessibilityHidden(true)
    }
}
