import SwiftUI

// MARK: - Deliveries: confirm a parcel from the doormat
//
// Parcels still on their way lead, then the settled ones. Each row names
// its status in words beside the glyph (never colour alone) and opens a
// detail whose bottom-bar button marks it received — locally at once, for
// real on the phone's next beat.

struct DeliveriesView: View {
    @Environment(WatchStore.self) private var store

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 10

    init() {}

    /// Active first, catalog order within each group.
    private var parcels: [DeliveryCatalogEntry] {
        let all = store.payload?.deliveries ?? []
        let ordered = all.filter(WatchRoute.isDeliveryActive)
            + all.filter { !WatchRoute.isDeliveryActive($0) }
        return Array(ordered.prefix(Self.rowLimit))
    }

    var body: some View {
        Group {
            if parcels.isEmpty {
                AllClearView(systemImage: "shippingbox")
            } else {
                List(parcels, id: \.id) { parcel in
                    NavigationLink(value: DeliveryRoute(id: parcel.id)) {
                        DeliveryRow(parcel: parcel)
                    }
                    .watchRowBackground(WatchTheme.Tint.deliveries)
                }
            }
        }
        // A feature-specific route type: the Home stack is shared, so a bare
        // UUID destination would collide with other features' pushes.
        .navigationDestination(for: DeliveryRoute.self) { route in
            DeliveryDetailView(id: route.id)
        }
        .navigationTitle(Text(WatchModule.deliveries.titleKey))
        .watchPageGround(WatchTheme.Tint.deliveries)
    }
}

/// Pushes one parcel's detail on whichever stack hosts Deliveries.
struct DeliveryRoute: Hashable {
    let id: UUID
}

// MARK: - Status vocabulary (shared by row and detail)

private enum DeliveryStatus {
    static func systemImage(for status: String) -> String {
        switch status {
        case "out_for_delivery": return "bicycle"
        case "delivered":        return "checkmark.seal.fill"
        case "missed":           return "exclamationmark.triangle.fill"
        default:                 return "shippingbox.fill"
        }
    }

    /// The same catalog keys the phone's delivery status label resolves.
    /// An unknown future status shows raw rather than disappearing.
    static func label(for status: String) -> Text {
        switch status {
        case "expected":         return Text("Expected")
        case "out_for_delivery": return Text("Out for delivery")
        case "delivered":        return Text("Delivered")
        case "missed":           return Text("Missed")
        case "returned":         return Text("Returned")
        default:                 return Text(verbatim: status)
        }
    }

    static func tint(for status: String) -> Color {
        switch status {
        case "out_for_delivery": return WatchTheme.Tint.warning
        case "delivered":        return WatchTheme.Tint.success
        case "missed":           return WatchTheme.Tint.critical
        case "expected":         return WatchTheme.Tint.deliveries
        default:                 return WatchTheme.Tint.neutral
        }
    }
}

// MARK: - Row

private struct DeliveryRow: View {
    let parcel: DeliveryCatalogEntry

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            Image(systemName: DeliveryStatus.systemImage(for: parcel.status))
                .font(WatchTheme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(DeliveryStatus.tint(for: parcel.status))
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: parcel.title)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(2)
                DeliveryStatus.label(for: parcel.status)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .watchAlwaysOnDimmed()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail

private struct DeliveryDetailView: View {
    let id: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Read live from the store so a fresh payload re-renders the detail.
    private var parcel: DeliveryCatalogEntry? {
        store.payload?.deliveries.first { $0.id == id }
    }

    var body: some View {
        Group {
            if let parcel {
                content(parcel)
            } else {
                AllClearView(systemImage: "shippingbox")
            }
        }
        .navigationTitle(Text(WatchModule.deliveries.titleKey))
        .watchPageGround(WatchTheme.Tint.deliveries)
        // The parcel can vanish under the open detail when the phone pushes.
        .onChange(of: parcel == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func content(_ parcel: DeliveryCatalogEntry) -> some View {
        let tint = DeliveryStatus.tint(for: parcel.status)
        return ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.l) {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: DeliveryStatus.systemImage(for: parcel.status))
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    DeliveryStatus.label(for: parcel.status)
                        .font(WatchTheme.Typography.cardTitle)
                        .foregroundStyle(tint)
                }
                .accessibilityElement(children: .combine)

                Text(verbatim: parcel.title)
                    .font(WatchTheme.Typography.hero)
                    .fixedSize(horizontal: false, vertical: true)

                if let carrier = parcel.carrier?.trimmingCharacters(in: .whitespaces), !carrier.isEmpty {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                        Text("Courier")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                        Text(verbatim: carrier)
                            .font(WatchTheme.Typography.body)
                    }
                    .accessibilityElement(children: .combine)
                }

                if let eta = parcel.eta?.trimmingCharacters(in: .whitespaces), !eta.isEmpty {
                    // The phone pre-formats the ETA; the catalog key frames it.
                    Text("ETA: \(eta)")
                        .font(WatchTheme.Typography.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            if WatchRoute.isDeliveryActive(parcel) {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        withAnimation(WatchTheme.Motion.snappy) { store.markDeliveryReceived(parcel.id) }
                        dismiss()
                    } label: {
                        Label("watch_delivery_received", systemImage: "checkmark.seal.fill")
                    }
                    .tint(WatchTheme.Tint.success)
                }
            }
        }
    }
}
