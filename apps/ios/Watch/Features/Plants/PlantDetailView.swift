import SwiftUI

// MARK: - Plant detail: one plant as an infographic
//
// The plant inside its health ring (the score fills the ring; the number
// sits under the emoji), its name, its state (symbol + word: "Needs water"
// with the drop, or "Healthy" with the leaf), and the Water button.
// Watering a plant that is not marked thirsty is still a real event (the
// phone logs it), so the button stays — just less prominent. The store
// plays `.done`; watering the last thirsty plant celebrates on the list.

struct PlantDetailView: View {
    let plantId: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Set on tap: the drop confirms, then the plant is watered and the
    /// screen leaves.
    @State private var isWatering = false

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
        .skyGround()
    }

    private func content(_ plant: PlantCatalogEntry) -> some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.l) {
                PlantHealthDial(emoji: plant.emoji, score: plant.healthScore,
                                isThirsty: plant.needsWatering)
                    .watchEntrance(0)

                VStack(spacing: WatchTheme.Spacing.xs) {
                    Text(verbatim: plant.name)
                        .font(WatchTheme.Typography.hero)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if plant.needsWatering {
                        StateLabel("Needs water", systemImage: "drop.fill", tint: WatchTheme.Tint.water)
                    } else {
                        StateLabel("Healthy", systemImage: "leaf.fill", tint: WatchTheme.Tint.calm)
                    }
                }
                .watchEntrance(1)

                waterButton(plant)
                    .watchEntrance(2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func waterButton(_ plant: PlantCatalogEntry) -> some View {
        let button = Button {
            water(plant.id)
        } label: {
            Label {
                Text("watch_water_now")
            } icon: {
                Image(systemName: isWatering ? "drop.fill" : "drop")
                    .contentTransition(reduceMotion ? ContentTransition.opacity
                                                    : ContentTransition.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: isWatering && !reduceMotion)
            }
            .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
        }
        .tint(WatchTheme.Tint.water)
        .disabled(isWatering)

        if plant.needsWatering {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    /// The drop confirms first (skipped under Reduce Motion), then the
    /// intent waters (`.done`) and the screen leaves.
    private func water(_ id: UUID) {
        guard !isWatering else { return }
        withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)) {
            isWatering = true
        }
        let pause = !reduceMotion
        Task { @MainActor in
            if pause { try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay) }
            store.waterPlant(id)
            dismiss()
        }
    }
}

// MARK: - Health dial

/// The plant at the centre of its health ring. The ring settles on the
/// score on arrival (instantly under Reduce Motion and in Always On, where
/// it is a thin stroke). Without a score the ring is an empty track and no
/// number is invented. VoiceOver reads one element: health score, value.
private struct PlantHealthDial: View {
    let emoji: String
    let score: Int?
    let isThirsty: Bool

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorSchemeContrast) private var contrast

    private var target: Double { score.map { Double(min(max($0, 0), 100)) / 100 } ?? 0 }
    private var ringTint: Color {
        score.map(WatchTheme.scoreColor) ?? (isThirsty ? WatchTheme.Tint.water : WatchTheme.Tint.plants)
    }
    private var ringWidth: CGFloat {
        isLuminanceReduced ? WatchTheme.Stroke.ring / 2 : WatchTheme.Stroke.ring
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringTint.opacity(contrast == .increased ? 0.35 : WatchTheme.Opacity.ringTrack),
                        lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: isLuminanceReduced ? target : shown)
                .stroke(ringTint.opacity(isLuminanceReduced ? WatchTheme.AlwaysOn.strokeOpacity : 1),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                if emoji.isEmpty {
                    Image(systemName: "leaf")
                        .symbolVariant(isLuminanceReduced ? .none : .fill)
                        .font(WatchTheme.Typography.dialGlyph)
                        .foregroundStyle(WatchTheme.Tint.plants)
                } else {
                    Text(verbatim: emoji)
                        .font(.title2)
                }
                if let score {
                    Text(verbatim: "\(score)")
                        .font(WatchTheme.Typography.numeralSmall)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(score)))
                }
            }
        }
        .padding(ringWidth / 2)
        .frame(width: WatchTheme.Size.dial, height: WatchTheme.Size.dial)
        .onAppear(perform: fill)
        .onChange(of: score) { fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Health score"))
        .accessibilityValue(score.map { Text(verbatim: "\($0)%") } ?? Text(verbatim: "—"))
        .accessibilityHidden(score == nil)
    }

    private func fill() {
        if reduceMotion || isLuminanceReduced {
            shown = target
        } else {
            withAnimation(WatchTheme.Motion.ringFill) { shown = target }
        }
    }
}
