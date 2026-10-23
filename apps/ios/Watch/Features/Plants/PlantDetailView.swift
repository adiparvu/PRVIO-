import SwiftUI

// MARK: - Plant detail
//
// One plant: who it is, whether it is thirsty, its health score when the
// phone has computed one, and a big Water button. Watering a plant that is
// not marked thirsty is still a real event (the phone logs it), so the
// button stays — just less prominent.

struct PlantDetailView: View {
    let plantId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    init(plantId: UUID) {
        self.plantId = plantId
    }

    private var plant: PlantCatalogEntry? {
        store.payload?.plants.first { $0.id == plantId }
    }

    var body: some View {
        Group {
            if let plant {
                content(plant)
            } else {
                // Removed on the phone while open.
                AllClearView(systemImage: "leaf")
            }
        }
        .navigationTitle(Text(WatchPage.plants.titleKey))
        .watchPageGround(WatchTheme.Tint.plants)
    }

    private func content(_ plant: PlantCatalogEntry) -> some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.l) {
                Text(verbatim: plant.emoji)
                    .font(.largeTitle)
                    .accessibilityHidden(true)

                Text(verbatim: plant.name)
                    .font(WatchTheme.Typography.hero)
                    .multilineTextAlignment(.center)

                if plant.needsWatering {
                    Label("Needs water", systemImage: "drop")
                        .font(WatchTheme.Typography.cardTitle)
                        .foregroundStyle(WatchTheme.Tint.water)
                }

                if let score = plant.healthScore {
                    VStack(spacing: WatchTheme.Spacing.xs) {
                        HealthRing(score: score)
                        Text("Health score")
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    .watchAlwaysOnDimmed()
                }

                waterButton(plant)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func waterButton(_ plant: PlantCatalogEntry) -> some View {
        let button = Button {
            store.waterPlant(plant.id)
            dismiss()
        } label: {
            Label("watch_water_now", systemImage: "drop.fill")
                .font(WatchTheme.Typography.hero)
                .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
        }
        .tint(WatchTheme.Tint.water)

        if plant.needsWatering {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
