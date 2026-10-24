import SwiftUI

// MARK: - Controls: the property's actuators
//
// One card per device: what it is, its live state (symbol + word), and
// exactly the commands it declared (`ActuatorCatalogEntry.commands`) — a
// wrist tap always maps to a real device write; commands this build does
// not know are left off rather than guessed.
//
// The tap echoes at once: a relay's on/off flips in the store (the phone
// reports the truth back); a cover, which reports no position, says
// "Opening…" / "Closing…" / "Stopped" for a few seconds. The store intent
// plays `.click`.
//
// Out of reach of the iPhone a command is NOT queued: the action queue
// survives unreachability and would deliver "open the garage" hours later,
// when nobody is watching the door. The tap plays `.retry` and the card
// says "Not sent — try again" instead. `.activating` is not "out of reach"
// (the connector holds transfers until activation, a moment away).
//
// A scroll of cards rather than a List: a List row with several buttons
// does not reliably route each tap to its own button.

struct ControlsView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init() {}

    private var actuators: [ActuatorCatalogEntry] { store.payload?.actuators ?? [] }

    private var isOutOfReach: Bool {
        store.connectivity == .unreachable || store.connectivity == .inactive
    }

    var body: some View {
        let devices = actuators
        Group {
            if devices.isEmpty {
                AllClearView(systemImage: WatchModule.controls.systemImage)
            } else {
                ScrollView {
                    // A plain VStack: a handful of devices, and each card keeps
                    // its echo state while scrolled out of view.
                    VStack(spacing: WatchTheme.Spacing.m) {
                        if isOutOfReach {
                            ReachNote()
                                .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                        }
                        ForEach(Array(devices.enumerated()), id: \.element.id) { index, actuator in
                            ActuatorCard(actuator: actuator) { command in
                                send(command, to: actuator)
                            }
                            .watchScrollDepth()
                            .watchEntrance(index)
                        }
                    }
                    .padding(.horizontal, WatchTheme.Spacing.xxs)
                    .animation(animation, value: isOutOfReach)
                }
            }
        }
        .navigationTitle(Text(WatchModule.controls.titleKey))
        .skyGround()
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    /// Sends when the phone can act on it now; otherwise refuses with
    /// `.retry`. Returns whether the command left.
    private func send(_ command: ActuatorCommand, to actuator: ActuatorCatalogEntry) -> Bool {
        guard !isOutOfReach else {
            // Not a store intent (nothing was sent), so the view speaks the
            // haptic itself.
            WatchHaptic.retry.play()
            return false
        }
        withAnimation(animation) {
            store.sendCommand(actuatorId: actuator.id, command: command.rawValue)   // plays .click
        }
        return true
    }
}

// MARK: - Command vocabulary

/// The raw `ActuatorCommand` vocabulary the phone executes, with the wrist's
/// word, glyph and optimistic echo for each. Unknown raw values fail to
/// initialize and are left off the card.
private enum ActuatorCommand: String, CaseIterable, Identifiable {
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
        case .on:           return WatchTheme.Tint.success
        case .off, .stop:   return WatchTheme.Tint.warning
        case .open, .close: return WatchTheme.Tint.controls
        }
    }

    /// What a cover says right after the tap (it reports no position).
    var echoKey: LocalizedStringKey {
        switch self {
        case .on:    return "watch_cmd_on"
        case .off:   return "watch_cmd_off"
        case .open:  return "watch_cmd_echo_open"
        case .close: return "watch_cmd_echo_close"
        case .stop:  return "watch_cmd_echo_stop"
        }
    }

    /// The declared commands this build understands, in the phone's order,
    /// each once — a repeated raw value would duplicate a ForEach identity.
    static func supported(by actuator: ActuatorCatalogEntry) -> [ActuatorCommand] {
        var seen = Set<ActuatorCommand>()
        return actuator.commands
            .compactMap(ActuatorCommand.init(rawValue:))
            .filter { seen.insert($0).inserted }
    }
}

/// The card's answer to the last tap; `serial` makes every tap a new echo
/// (it restarts the hold and bounces the glyph again).
private struct CommandEcho: Equatable {
    let command: ActuatorCommand
    let wasSent: Bool
    let serial: Int
}

private enum ControlsTiming {
    /// How long a tap's echo stays before the card returns to the reported
    /// state.
    static let echoHold: Duration = .seconds(4)
}

// MARK: - Card

private struct ActuatorCard: View {
    let actuator: ActuatorCatalogEntry
    /// Sends `command`; false when it could not leave the wrist.
    let send: (ActuatorCommand) -> Bool

    @State private var echo: CommandEcho? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var commands: [ActuatorCommand] { ActuatorCommand.supported(by: actuator) }

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
        .task(id: echo) {
            guard echo != nil else { return }
            do { try await Task.sleep(for: ControlsTiming.echoHold) } catch { return }
            withAnimation(animation) { echo = nil }
        }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    // MARK: Header — glyph, name, live state

    private var header: some View {
        HStack(alignment: .center, spacing: WatchTheme.Spacing.s) {
            Image(systemName: kindSymbol)
                .font(WatchTheme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WatchTheme.Tint.controls)
                .symbolEffect(.bounce, value: reduceMotion || isLuminanceReduced ? 0 : (echo?.serial ?? 0))
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .background {
                    if isLuminanceReduced {
                        Circle().strokeBorder(WatchTheme.Tint.controls.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                              lineWidth: WatchTheme.Stroke.hairline)
                    } else {
                        Circle().fill(WatchTheme.Tint.controls.opacity(WatchTheme.Opacity.glyphFill))
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: actuator.name)
                    .font(WatchTheme.Typography.cardTitle)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let state = liveState {
                    state
                        .id(stateIdentity)
                        .transition(.opacity)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(animation, value: stateIdentity)
        .accessibilityElement(children: .combine)
    }

    /// The state line: a refused tap first, then a cover's fresh echo, then
    /// the relay's reported (optimistically echoed) state.
    private var liveState: StateLabel? {
        if let echo, !echo.wasSent {
            return StateLabel("watch_cmd_not_sent", systemImage: "iphone.slash",
                              tint: WatchTheme.Tint.attention)
        }
        if let echo, !isRelay {
            return StateLabel(echo.command.echoKey, systemImage: echo.command.systemImage,
                              tint: WatchTheme.Tint.controls)
        }
        if isRelay, let isOn = actuator.isOn {
            // The shape carries the state as well as the colour: filled
            // when on, outlined when off.
            return isOn
                ? StateLabel("watch_cmd_on", systemImage: "power.circle.fill", tint: WatchTheme.Tint.success)
                : StateLabel("watch_cmd_off", systemImage: "power.circle", tint: WatchTheme.Tint.neutral)
        }
        return nil
    }

    /// Changes whenever the state line says something new.
    private var stateIdentity: String {
        if let echo, !echo.wasSent { return "refused-\(echo.serial)" }
        if let echo, !isRelay { return "echo-\(echo.command.rawValue)-\(echo.serial)" }
        if isRelay, let isOn = actuator.isOn { return isOn ? "on" : "off" }
        return "none"
    }

    // MARK: Buttons — from the declared commands

    /// Up to three per row; past two the words collapse to glyphs so every
    /// button keeps a tappable width (the word stays the VoiceOver label).
    /// At accessibility text sizes: one per row, words always shown.
    private var buttons: some View {
        let isLarge = dynamicTypeSize.isAccessibilitySize
        let perRow = isLarge ? 1 : min(commands.count, 3)
        let columns = Array(repeating: GridItem(.flexible(), spacing: WatchTheme.Spacing.s), count: perRow)
        let iconOnly = !isLarge && commands.count > 2
        return LazyVGrid(columns: columns, spacing: WatchTheme.Spacing.s) {
            ForEach(commands) { command in
                Button {
                    tap(command)
                } label: {
                    if iconOnly {
                        Label(command.titleKey, systemImage: command.systemImage)
                            .labelStyle(.iconOnly)
                    } else {
                        Label(command.titleKey, systemImage: command.systemImage)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .buttonStyle(CommandButtonStyle(tint: command.tint, isCurrent: isCurrentState(command)))
                .accessibilityAddTraits(isCurrentState(command) == true ? .isSelected : [])
            }
        }
        .watchAlwaysOnDimmed()
    }

    private func tap(_ command: ActuatorCommand) {
        let sent = send(command)
        withAnimation(animation) {
            echo = CommandEcho(command: command, wasSent: sent, serial: (echo?.serial ?? 0) + 1)
        }
    }

    /// For a relay, the command matching its reported state is the lit one;
    /// covers report no position, so every command stays lit (nil).
    private func isCurrentState(_ command: ActuatorCommand) -> Bool? {
        guard isRelay, let isOn = actuator.isOn else { return nil }
        switch command {
        case .on:  return isOn
        case .off: return !isOn
        default:   return nil
        }
    }
}

// MARK: - Out-of-reach note

/// Said once at the top while the phone cannot act — before the person taps.
private struct ReachNote: View {
    var body: some View {
        WatchCard(tint: WatchTheme.Tint.attention) {
            HStack(alignment: .top, spacing: WatchTheme.Spacing.s) {
                Image(systemName: "iphone.slash")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(WatchTheme.Tint.attention)
                    .accessibilityHidden(true)
                Text("watch_controls_unreachable")
                    .font(WatchTheme.Typography.caption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Button style

/// A command: a tinted surface (content, never glass) — strong when it is
/// the device's current state or stateless, neutral when it is the other
/// side of a relay. A soft press; a fade only under Reduce Motion.
private struct CommandButtonStyle: ButtonStyle {
    let tint: Color
    /// nil = no reported state to compare against.
    let isCurrent: Bool?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let surfaceTint = isCurrent == false ? WatchTheme.Tint.neutral : tint
        configuration.label
            .font(WatchTheme.Typography.captionStrong)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(isCurrent == false ? Color.secondary : Color.primary)
            .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .background { WatchSurface(tint: surfaceTint, radius: WatchTheme.Radius.small) }
            .contentShape(RoundedRectangle(cornerRadius: WatchTheme.Radius.small, style: .continuous))
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.95 : 1)
            .animation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion),
                       value: pressed)
    }
}
