import SwiftUI

// MARK: - Sensors: live readings, at a glance
//
// One line says how the sensors are doing (calm when all is normal), then a
// grid of readings, hazards first — a critical alarm belongs at the top of a
// small screen. Every value is pre-formatted on the phone (which owns units
// and thresholds); the wrist only orders and renders. Each tile states its
// severity as a symbol and a word as well as colour, so it reads the same
// to everyone, in every display mode. Read-only: nothing here is a button.

struct SensorsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init() {}

    /// Critical, then alerting, then normal — a stable partition, so the
    /// phone's own order survives within each tier.
    private var ordered: [SensorCatalogEntry] {
        let sensors = store.payload?.sensors ?? []
        return SensorSeverity.allCases.flatMap { tier in
            sensors.filter { SensorSeverity($0) == tier }
        }
    }

    var body: some View {
        let sensors = ordered
        Group {
            if sensors.isEmpty {
                AllClearView(systemImage: WatchModule.sensors.systemImage)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                        SensorsSummary(sensors: sensors)
                            .watchEntrance(0)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: WatchTheme.Spacing.s) {
                            ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                                SensorTile(sensor: sensor)
                                    .watchEntrance(index + 1)
                            }
                        }
                        if let updated = store.lastUpdated {
                            UpdatedLine(date: updated)
                        }
                    }
                    .padding(.horizontal, WatchTheme.Spacing.xxs)
                }
            }
        }
        .navigationTitle(Text(WatchModule.sensors.titleKey))
        .skyGround()
    }

    /// Two tiles side by side; one per row at accessibility text sizes so
    /// nothing truncates.
    private var columns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        return Array(repeating: GridItem(.flexible(), spacing: WatchTheme.Spacing.s, alignment: .top),
                     count: count)
    }
}

// MARK: - Severity

/// What a sensor is saying right now. Critical = a hazard (smoke / gas /
/// water) that is alerting — the same rule the wrist's critical-sensor
/// notifications use. Declaration order is display order.
private enum SensorSeverity: CaseIterable, Equatable {
    case critical, alerting, normal

    init(_ sensor: SensorCatalogEntry) {
        if !sensor.isAlerting {
            self = .normal
        } else {
            self = sensor.isCritical ? .critical : .alerting
        }
    }

    /// Red only for a real alarm; an ordinary alert is stated plainly in
    /// the attention amber, never shouted.
    var tint: Color {
        switch self {
        case .critical: return WatchTheme.Tint.critical
        case .alerting: return WatchTheme.Tint.attention
        case .normal:   return WatchTheme.Tint.calm
        }
    }

    var label: StateLabel {
        switch self {
        case .critical:
            return StateLabel("watch_sensor_critical", systemImage: "exclamationmark.octagon.fill", tint: tint)
        case .alerting:
            return StateLabel("watch_sensor_alerting", systemImage: "exclamationmark.triangle.fill", tint: tint)
        case .normal:
            return StateLabel("watch_sensor_normal", systemImage: "checkmark.circle", tint: tint)
        }
    }
}

// MARK: - Summary

/// The page's one sentence: calm when every reading is normal, otherwise
/// how many need a look — with the worst severity's symbol.
private struct SensorsSummary: View {
    let sensors: [SensorCatalogEntry]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let severities = sensors.map(SensorSeverity.init)
        let attention = severities.filter { $0 != .normal }.count
        Group {
            if attention == 0 {
                HStack(spacing: WatchTheme.Spacing.xs) {
                    // breathe = calm (DESIGN.md motion vocabulary).
                    Image(systemName: WatchHouseholdState.calm.systemImage)
                        .symbolEffect(.breathe, isActive: !reduceMotion && !isLuminanceReduced)
                        .accessibilityHidden(true)
                    Text("watch_sensors_all_normal")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(WatchTheme.Typography.captionStrong)
                .foregroundStyle(WatchTheme.Tint.calm)
                .accessibilityElement(children: .combine)
            } else {
                let worst: SensorSeverity = severities.contains(.critical) ? .critical : .alerting
                StateLabel("watch_sensors_attention \(attention)",
                           systemImage: worst == .critical ? "exclamationmark.octagon.fill"
                                                           : "exclamationmark.triangle.fill",
                           tint: worst.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WatchTheme.Spacing.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Tile

private struct SensorTile: View {
    let sensor: SensorCatalogEntry

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var severity: SensorSeverity { SensorSeverity(sensor) }

    /// Normal tiles wear the module's tint; alerting ones their severity.
    private var surfaceTint: Color {
        severity == .normal ? WatchTheme.Tint.sensors : severity.tint
    }

    var body: some View {
        WatchCard(tint: surfaceTint, radius: WatchTheme.Radius.row) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Image(systemName: sensor.icon)
                    .font(WatchTheme.Typography.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .symbolVariant(isLuminanceReduced ? .none : .fill)
                    .foregroundStyle(surfaceTint)
                    .accessibilityHidden(true)
                Text(verbatim: sensor.displayValue)
                    .font(WatchTheme.Typography.numeral)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                Text(verbatim: sensor.name)
                    .font(WatchTheme.Typography.caption.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let zone = sensor.zone, !zone.isEmpty {
                    Text(verbatim: zone)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .watchAlwaysOnDimmed()
                }
                severity.label
            }
        }
        // Reads as "Kitchen, 21.4 °C, Hall, Normal".
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Freshness

/// Readings are only as live as the last sync — say how old they are.
private struct UpdatedLine: View {
    let date: Date

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityHidden(true)
            Text("watch_updated")
            Text(date, format: .relative(presentation: .named))
        }
        .font(WatchTheme.Typography.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }
}
