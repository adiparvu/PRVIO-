import SwiftUI

// MARK: - Sensors: live readings, read-only
//
// The property's own sensors, hazards first: a critical alarm belongs at
// the top of a small screen. Every value is pre-formatted on the phone
// (which owns units and thresholds); the wrist only orders and renders.
// An alarm is said with a symbol and a word as well as colour, so it reads
// the same to everyone, in every display mode.

struct SensorsView: View {
    @Environment(WatchStore.self) private var store

    init() {}

    /// Critical alarms, then other alarms, then the rest — a stable
    /// partition, so the phone's own order survives within each tier.
    private var ordered: [SensorCatalogEntry] {
        let sensors = store.payload?.sensors ?? []
        let critical = sensors.filter { SensorAlarm($0) == .critical }
        let alerting = sensors.filter { SensorAlarm($0) == .alerting }
        let calm = sensors.filter { SensorAlarm($0) == nil }
        return critical + alerting + calm
    }

    var body: some View {
        let sensors = ordered
        Group {
            if sensors.isEmpty {
                AllClearView(systemImage: WatchModule.sensors.systemImage)
            } else {
                List(sensors, id: \.id) { sensor in
                    SensorRow(sensor: sensor)
                        .watchRowBackground(SensorAlarm(sensor)?.tint ?? WatchTheme.Tint.sensors)
                }
            }
        }
        .navigationTitle(Text(WatchModule.sensors.titleKey))
        .watchPageGround(WatchTheme.Tint.sensors)
    }
}

// MARK: - Alarm level

/// What a sensor is saying right now; nil = nothing wrong. Critical means a
/// hazard (smoke / gas / water) that is alerting — the same rule the wrist's
/// critical-sensor notifications use.
private enum SensorAlarm: Equatable {
    case critical, alerting

    init?(_ sensor: SensorCatalogEntry) {
        guard sensor.isAlerting else { return nil }
        self = sensor.isCritical ? .critical : .alerting
    }

    var tint: Color {
        switch self {
        case .critical: return WatchTheme.Tint.critical
        case .alerting: return WatchTheme.Tint.warning
        }
    }

    var systemImage: String {
        switch self {
        case .critical: return "exclamationmark.octagon.fill"
        case .alerting: return "exclamationmark.triangle.fill"
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .critical: return "watch_sensor_critical"
        case .alerting: return "watch_sensor_alerting"
        }
    }
}

// MARK: - Row

private struct SensorRow: View {
    let sensor: SensorCatalogEntry

    private var alarm: SensorAlarm? { SensorAlarm(sensor) }
    private var accent: Color { alarm?.tint ?? WatchTheme.Tint.sensors }

    var body: some View {
        HStack(alignment: .center, spacing: WatchTheme.Spacing.m) {
            Image(systemName: sensor.icon)
                .font(WatchTheme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent)
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .background(accent.opacity(WatchTheme.Opacity.glyphFill), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: sensor.name)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(1)
                if let zone = sensor.zone, !zone.isEmpty {
                    Text(verbatim: zone)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let alarm {
                    Label(alarm.titleKey, systemImage: alarm.systemImage)
                        .font(WatchTheme.Typography.captionStrong)
                        .foregroundStyle(alarm.tint)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            Text(verbatim: sensor.displayValue)
                .font(WatchTheme.Typography.rowTitle.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(alarm?.tint ?? Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .combine)
    }
}
