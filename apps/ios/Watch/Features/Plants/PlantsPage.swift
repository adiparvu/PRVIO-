import SwiftUI

// MARK: - Plants: who is thirsty
//
// The thirsty plants lead, each waterable on the spot from its leading
// glyph; the healthy ones fold into a single secondary row with their count,
// one push away. No primary double tap: this is a scrolling list inside the
// pager.

/// A push inside the Plants feature. Feature-specific so it never collides
/// with another feature's route on a shared stack.
enum PlantRoute: Hashable {
    case plant(UUID)
    case healthy
}

struct PlantsPage: View {
    @Environment(WatchStore.self) private var store

    init() {}

    var body: some View {
        let thirsty = store.thirstyPlants
        let healthyCount = store.payload?.plants.filter { !$0.needsWatering }.count ?? 0
        List {
            if thirsty.isEmpty {
                AllClearView(systemImage: "drop", messageKey: "watch_siri_no_plants")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(thirsty, id: \.id) { plant in
                        NavigationLink(value: PlantRoute.plant(plant.id)) {
                            ThirstyPlantRow(plant: plant) {
                                store.waterPlant(plant.id)
                            }
                        }
                        .watchRowBackground(WatchTheme.Tint.water)
                    }
                }
            }

            if healthyCount > 0 {
                Section {
                    NavigationLink(value: PlantRoute.healthy) {
                        ModuleRow(titleKey: "Healthy", systemImage: "leaf.fill",
                                  tint: WatchTheme.Tint.plants,
                                  badge: WatchBadge(count: healthyCount, isUrgent: false))
                    }
                    .watchRowBackground(WatchTheme.Tint.neutral)
                    .watchAlwaysOnDimmed()
                }
            }
        }
        .navigationTitle(Text(WatchPage.plants.titleKey))
        .watchPageGround(WatchTheme.Tint.plants)
        .navigationDestination(for: PlantRoute.self) { route in
            switch route {
            case .plant(let id): PlantDetailView(plantId: id)
            case .healthy:       HealthyPlantsView()
            }
        }
        .toolbar {
            if thirsty.count > 1 {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        withAnimation(WatchTheme.Motion.snappy) { store.waterAllPlants() }
                    } label: {
                        Label("watch_water_all", systemImage: "drop.fill")
                    }
                    .tint(WatchTheme.Tint.water)
                }
            }
        }
    }
}

// MARK: - Rows

private struct ThirstyPlantRow: View {
    let plant: PlantCatalogEntry
    let water: () -> Void

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            ActionGlyphButton(systemImage: "drop",
                              actedSystemImage: "drop.fill",
                              tint: WatchTheme.Tint.water,
                              labelKey: "watch_water_now",
                              action: water)
            PlantLabel(plant: plant)
        }
    }
}

/// Emoji + name, the plant's identity everywhere on the wrist.
private struct PlantLabel: View {
    let plant: PlantCatalogEntry

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            Text(verbatim: plant.emoji)
                .accessibilityHidden(true)
            Text(verbatim: plant.name)
                .font(WatchTheme.Typography.body)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Healthy plants

/// The plants that need nothing right now — reachable, never in the way.
private struct HealthyPlantsView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        let healthy = store.payload?.plants.filter { !$0.needsWatering } ?? []
        Group {
            if healthy.isEmpty {
                AllClearView(systemImage: "leaf")
            } else {
                List {
                    ForEach(healthy, id: \.id) { plant in
                        NavigationLink(value: PlantRoute.plant(plant.id)) {
                            PlantLabel(plant: plant)
                        }
                        .watchRowBackground(WatchTheme.Tint.plants)
                    }
                }
            }
        }
        .navigationTitle(Text("Healthy"))
        .watchPageGround(WatchTheme.Tint.plants)
    }
}
