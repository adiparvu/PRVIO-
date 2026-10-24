import SwiftUI

// MARK: - Plants: who is thirsty
//
// A one-line state ("2 to water", with the drop), then the thirsty plants,
// each waterable on the spot from its leading drop: it bounces, the store
// plays `.done`, and the row leaves with the List's own removal animation.
// The healthy plants fold into one quiet row — one push away, never in the
// way. "Water all" is the page's primary action, in the bottom bar.
// Watering the last thirsty plant here celebrates once
// (`watchAllClearCelebration(.plants)`).
//
// No primary double tap: this is a scrolling list inside the pager.

/// A push inside the Plants feature. Feature-specific so it never collides
/// with another feature's route on a shared stack.
enum PlantRoute: Hashable {
    case plant(UUID)
    case healthy
}

struct PlantsPage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    var body: some View {
        let thirsty = store.thirstyPlants
        let healthy = store.payload?.plants.filter { !$0.needsWatering } ?? []
        List {
            if thirsty.isEmpty {
                AllClearView(systemImage: "drop", messageKey: "watch_siri_no_plants")
                    .listRowBackground(Color.clear)
            } else {
                StateLabel("watch_plants_thirsty \(thirsty.count)", systemImage: "drop.fill",
                           tint: WatchTheme.Tint.water)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                    .listRowBackground(Color.clear)

                ForEach(thirsty, id: \.id) { plant in
                    NavigationLink(value: PlantRoute.plant(plant.id)) {
                        ThirstyPlantRow(plant: plant) {
                            store.waterPlant(plant.id)   // the intent plays .done
                        }
                    }
                    .watchRowBackground(WatchTheme.Tint.water)
                }
            }

            if !healthy.isEmpty {
                Section {
                    NavigationLink(value: PlantRoute.healthy) {
                        HealthyFoldRow(plants: healthy)
                    }
                    .watchRowBackground(WatchTheme.Tint.plants)
                }
            }
        }
        .navigationTitle(Text(WatchPage.plants.titleKey))
        .skyGround()
        .navigationDestination(for: PlantRoute.self) { route in
            switch route {
            case .plant(let id): PlantDetailView(plantId: id)
            case .healthy:       HealthyPlantsView()
            }
        }
        .toolbar {
            // One thirsty plant is watered from its row; "all" means several.
            if thirsty.count > 1 {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy,
                                                                 reduceMotion: reduceMotion)) {
                            store.waterAllPlants()   // one .done for the gesture
                        }
                    } label: {
                        Label("watch_water_all", systemImage: "drop.fill")
                    }
                    .tint(WatchTheme.Tint.water)
                }
            }
        }
        .watchAllClearCelebration(.plants)
    }
}

// MARK: - Rows

private struct ThirstyPlantRow: View {
    let plant: PlantCatalogEntry
    let water: () -> Void

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            // The store plays the haptic, so the glyph plays none of its own.
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
            if !plant.emoji.isEmpty {
                Text(verbatim: plant.emoji)
                    .accessibilityHidden(true)
            }
            Text(verbatim: plant.name)
                .font(WatchTheme.Typography.rowTitle)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}

/// The healthy plants, folded: a leaf, the word, a few of their emoji and
/// how many — an inventory, so a plain number rather than a call-to-act badge.
private struct HealthyFoldRow: View {
    let plants: [PlantCatalogEntry]

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var emojiPreview: String {
        plants.prefix(3).map(\.emoji).filter { !$0.isEmpty }.joined()
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            Image(systemName: "leaf")
                .symbolVariant(isLuminanceReduced ? .none : .fill)
                .font(WatchTheme.Typography.glyph)
                .foregroundStyle(WatchTheme.Tint.calm)
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Healthy")
                    .font(WatchTheme.Typography.rowTitle)
                if !emojiPreview.isEmpty {
                    Text(verbatim: emojiPreview)
                        .font(WatchTheme.Typography.caption)
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(plants.count)")
                .font(WatchTheme.Typography.numeralSmall)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: Double(plants.count)))
        }
        .watchAlwaysOnDimmed()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Healthy"))
        .accessibilityValue(Text(verbatim: "\(plants.count)"))
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
                            HStack(spacing: WatchTheme.Spacing.s) {
                                PlantLabel(plant: plant)
                                if let score = plant.healthScore {
                                    ScoreReadout(score: score)
                                }
                            }
                        }
                        .watchRowBackground(WatchTheme.Tint.plants)
                    }
                }
            }
        }
        .navigationTitle(Text("Healthy"))
        .skyGround()
    }
}

/// A plant's health score, trailing a row: the number always travels with
/// its colour band.
private struct ScoreReadout: View {
    let score: Int

    var body: some View {
        Text(verbatim: "\(score)")
            .font(WatchTheme.Typography.numeralSmall)
            .monospacedDigit()
            .foregroundStyle(WatchTheme.scoreColor(score))
            .watchAlwaysOnDimmed()
            .accessibilityLabel(Text("Health score"))
            .accessibilityValue(Text(verbatim: "\(score)%"))
    }
}
