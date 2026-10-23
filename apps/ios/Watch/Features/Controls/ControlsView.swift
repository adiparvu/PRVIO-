import SwiftUI

// MARK: - Controls: the property's actuators
//
// Each card offers exactly the commands its actuator declared
// (`ActuatorCatalogEntry.commands`), so a wrist tap always maps to a real
// device write; commands this build does not know are skipped rather than
// guessed. The phone executes and reports the true state back; a relay's
// on/off echoes optimistically in the store.
//
// A scroll of cards rather than a List: a List row with several buttons
// does not reliably route each tap to its own button.

struct ControlsView: View {
    @Environment(WatchStore.self) private var store

    init() {}

    var body: some View {
        Group {
            if let actuators = store.payload?.actuators, !actuators.isEmpty {
                ScrollView {
                    LazyVStack(spacing: WatchTheme.Spacing.m) {
                        ForEach(Array(actuators.enumerated()), id: \.element.id) { index, actuator in
                            ActuatorCard(actuator: actuator) { command in
                                withAnimation(WatchTheme.Motion.snappy) {
                                    store.sendCommand(actuatorId: actuator.id, command: command.rawValue)
                                }
                            }
                            .watchEntrance(index)
                        }
                    }
                }
            } else {
                AllClearView(systemImage: WatchModule.controls.systemImage)
            }
        }
        .navigationTitle(Text(WatchModule.controls.titleKey))
        .watchPageGround(WatchTheme.Tint.controls)
    }
}

// MARK: - Command vocabulary

/// The raw `ActuatorCommand` vocabulary the phone executes, with the wrist's
/// label and glyph for each. Unknown raw values fail to initialize and are
/// left off the card.
private enum WatchActuatorCommand: String, CaseIterable, Identifiable {
    case on, off, open, close, stop

    var id: String { rawValue }

    var titleKey: LocalizedStringKey {
        switch self {
        case .on:    return "watch_cmd_on"
        case .off:   return "watch_cmd_off"
        case .open:  return "watch_cmd_open"
        case .close: return "watch_cmd_close"
        case .stop:  return "watch_cmd_stop"
        }
    }

    var systemImage: String {
        switch self {
        case .on:    return "power"
        case .off:   return "poweroff"
        case .open:  return "arrow.up"
        case .close: return "arrow.down"
        case .stop:  return "stop.fill"
        }
    }

    var tint: Color {
        switch self {
        case .on:    return WatchTheme.Tint.success
        case .off:   return WatchTheme.Tint.warning
        case .open:  return WatchTheme.Tint.controls
        case .close: return WatchTheme.Tint.controls
        case .stop:  return WatchTheme.Tint.warning
        }
    }

    /// The declared commands this build understands, in the phone's order,
    /// each once — a repeated raw value would duplicate a ForEach identity.
    static func supported(by actuator: ActuatorCatalogEntry) -> [WatchActuatorCommand] {
        var seen = Set<WatchActuatorCommand>()
        return actuator.commands
            .compactMap(WatchActuatorCommand.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }
}

// MARK: - Card

private struct ActuatorCard: View {
    let actuator: ActuatorCatalogEntry
    let send: (WatchActuatorCommand) -> Void

    private var commands: [WatchActuatorCommand] { WatchActuatorCommand.supported(by: actuator) }

    private var isRelay: Bool { actuator.kind == "relay" }

    private var kindSymbol: String {
        switch actuator.kind {
        case "relay": return "power"
        case "cover": return "door.garage.closed"
        default:      return WatchModule.controls.systemImage
        }
    }

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.controls) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                header
                if !commands.isEmpty {
                    buttons
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: WatchTheme.Spacing.s) {
            Image(systemName: kindSymbol)
                .font(WatchTheme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WatchTheme.Tint.controls)
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .background(WatchTheme.Tint.controls.opacity(WatchTheme.Opacity.glyphFill), in: Circle())
                .accessibilityHidden(true)
            Text(verbatim: actuator.name)
                .font(WatchTheme.Typography.cardTitle)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isRelay, let isOn = actuator.isOn {
                RelayStateDot(isOn: isOn)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Up to three per row; past two the labels collapse to glyphs so the
    /// buttons keep a tappable width (the title stays the accessibility
    /// label).
    private var buttons: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: WatchTheme.Spacing.s),
                            count: min(commands.count, 3))
        let iconOnly = commands.count > 2
        return LazyVGrid(columns: columns, spacing: WatchTheme.Spacing.s) {
            ForEach(commands) { command in
                CommandButton(command: command,
                              isCurrent: isCurrentState(command),
                              iconOnly: iconOnly) {
                    send(command)
                }
            }
        }
        .watchAlwaysOnDimmed()
    }

    /// For a relay, the command matching its reported state is the lit one;
    /// covers report no position, so every command stays lit.
    private func isCurrentState(_ command: WatchActuatorCommand) -> Bool? {
        guard isRelay, let isOn = actuator.isOn else { return nil }
        switch command {
        case .on:  return isOn
        case .off: return !isOn
        default:   return nil
        }
    }
}

/// On is a filled green dot, off a hollow grey ring — the shape carries the
/// state, not only the colour, and VoiceOver reads it as a value.
private struct RelayStateDot: View {
    let isOn: Bool

    private static let diameter: CGFloat = WatchTheme.Spacing.m

    var body: some View {
        Group {
            if isOn {
                Circle().fill(WatchTheme.Tint.success)
            } else {
                Circle().strokeBorder(Color.secondary, lineWidth: 1.5)
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityElement()
        .accessibilityLabel(Text(isOn ? LocalizedStringKey("watch_cmd_on") : LocalizedStringKey("watch_cmd_off")))
    }
}

private struct CommandButton: View {
    let command: WatchActuatorCommand
    /// nil = no reported state to compare against.
    let isCurrent: Bool?
    let iconOnly: Bool
    let action: () -> Void

    private var tint: Color {
        isCurrent == false ? WatchTheme.Tint.neutral : command.tint
    }

    var body: some View {
        Button(action: action) {
            label
                .font(WatchTheme.Typography.captionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .accessibilityAddTraits(isCurrent == true ? .isSelected : [])
    }

    @ViewBuilder
    private var label: some View {
        if iconOnly {
            Label(command.titleKey, systemImage: command.systemImage)
                .labelStyle(.iconOnly)
        } else {
            Label(command.titleKey, systemImage: command.systemImage)
                .labelStyle(.titleAndIcon)
        }
    }
}
