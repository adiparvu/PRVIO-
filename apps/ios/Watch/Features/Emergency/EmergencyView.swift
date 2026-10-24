import SwiftUI

// MARK: - Emergency: the property's own plan on the wrist
//
// Alert the family, raise the phone's Emergency Live Activity, walk the
// shutoff steps, call a contact. Everything comes from what the owner set up
// on the phone; nothing is invented. It all lives in the cached payload, so
// the plan reads with no phone and no network; calls dial from the watch
// itself, and the alert queues until the phone is back in reach (said
// honestly when that is the case).
//
// The ground is a signal, never an atmosphere: it never adopts the sky.
// Surfaces on it are neutral and strokes stronger, for contrast on red.
//
// "Alert the family" is the page's primary action (bottom toolbar) and
// always asks first: a pocket-tap false alarm costs the family real
// adrenaline. The page is family scope only (enforced by routing; the store
// intents guard again).
//
// Privacy: the property, the steps and the contacts are emergency details —
// `.watchPrivate()` redacts them in Always On until the wrist is raised.

struct EmergencyView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isConfirmingAlert = false
    /// When the alert was handed to the store; drives the 5 s "sent" state.
    @State private var alertSentAt: Date? = nil
    /// When emergency mode was asked of the phone; drives its 5 s state.
    @State private var emergencyStartedAt: Date? = nil

    init() {}

    private var propertyName: String { store.payload?.snapshot.propertyName ?? "" }
    private var steps: [EmergencyStepEntry] { store.payload?.emergencySteps ?? [] }
    private var contacts: [EmergencyContactEntry] { store.payload?.emergencyContacts ?? [] }

    private var isOutOfReach: Bool {
        store.connectivity == .unreachable || store.connectivity == .inactive
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.l) {
                PlanCard(propertyName: propertyName,
                         isFamilyScope: store.isFamilyScope,
                         isStarted: emergencyStartedAt != nil,
                         isOutOfReach: isOutOfReach) {
                    guard emergencyStartedAt == nil else { return }
                    store.startEmergency()   // plays .notification
                    withAnimation(animation) { emergencyStartedAt = Date() }
                }

                if alertSentAt != nil {
                    AlertSentCard(isQueued: isOutOfReach)
                        .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                }

                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
                        SectionHeader("watch_emergency_steps")
                        WatchCard(tint: WatchTheme.Tint.neutral) {
                            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                    EmergencyStepRow(number: index + 1, step: step)
                                }
                            }
                        }
                        .watchPrivate()
                    }
                }

                if !contacts.isEmpty {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
                        SectionHeader("watch_emergency_contacts")
                        ForEach(contacts, id: \.id) { contact in
                            EmergencyContactRow(contact: contact)
                        }
                    }
                }
            }
            .padding(.horizontal, WatchTheme.Spacing.xxs)
        }
        .navigationTitle(Text(WatchModule.emergency.titleKey))
        .signalGround(WatchTheme.Tint.emergency)
        .toolbar {
            // The condition lives inside the item: ToolbarContentBuilder's
            // `buildIf` only takes customizable (id'd) content.
            ToolbarItem(placement: .bottomBar) {
                if store.canAlertFamily {
                    alertFamilyButton
                }
            }
        }
        .confirmationDialog(Text("emg_alert_confirm_title"),
                            isPresented: $isConfirmingAlert,
                            titleVisibility: .visible) {
            Button(role: .destructive) {
                store.alertFamily()   // plays .notification
                withAnimation(animation) { alertSentAt = Date() }
            } label: {
                Text("emg_alert_confirm_send")
            }
        } message: {
            Text("emg_alert_confirm_msg \(propertyName)")
        }
        .task(id: alertSentAt) {
            guard alertSentAt != nil else { return }
            do { try await Task.sleep(for: EmergencyTiming.confirmation) } catch { return }
            withAnimation(animation) { alertSentAt = nil }
        }
        .task(id: emergencyStartedAt) {
            guard emergencyStartedAt != nil else { return }
            do { try await Task.sleep(for: EmergencyTiming.confirmation) } catch { return }
            withAnimation(animation) { emergencyStartedAt = nil }
        }
    }

    // MARK: Primary action

    private var alertFamilyButton: some View {
        let isSent = alertSentAt != nil
        return Button {
            // While the "sent" state shows, a second alert is one tap too
            // easy; the state clears on its own after a few seconds.
            guard !isSent else { return }
            isConfirmingAlert = true
        } label: {
            Label(isSent ? LocalizedStringKey("emg_alert_sent") : LocalizedStringKey("emg_alert_family"),
                  systemImage: isSent ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                .contentTransition(reduceMotion ? ContentTransition.opacity
                                                : ContentTransition.symbolEffect(.replace))
        }
        .tint(isSent ? WatchTheme.Tint.success : WatchTheme.Tint.emergency)
    }
}

private enum EmergencyTiming {
    /// How long a sent / started confirmation stays (the brief: 5 s).
    static let confirmation: Duration = .seconds(5)
}

// MARK: - Plan card

/// The page's head: the property, a plain promise that the plan works
/// offline, and — in family scope — the one big Start button.
private struct PlanCard: View {
    let propertyName: String
    let isFamilyScope: Bool
    let isStarted: Bool
    let isOutOfReach: Bool
    let start: () -> Void

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.neutral, radius: WatchTheme.Radius.hero) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: "light.beacon.max.fill")
                        .font(WatchTheme.Typography.glyph)
                        .foregroundStyle(WatchTheme.Tint.emergency)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                        if !propertyName.isEmpty {
                            Text(verbatim: propertyName)
                                .font(WatchTheme.Typography.cardTitle)
                                .lineLimit(2)
                                .watchPrivate()
                        }
                        StateLabel("watch_emergency_ready", systemImage: "checkmark.shield.fill",
                                   tint: WatchTheme.Tint.success)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if isFamilyScope {
                    Button(action: start) {
                        Label(isStarted ? LocalizedStringKey("watch_emergency_started")
                                        : LocalizedStringKey("watch_emergency_start"),
                              systemImage: isStarted ? "checkmark.circle.fill" : "light.beacon.max.fill")
                    }
                    .buttonStyle(SignalButtonStyle(isSettled: isStarted))
                    .accessibilityHint(Text("watch_emergency_start_hint"))

                    if isStarted, isOutOfReach {
                        QueuedNote()
                    }
                }
            }
        }
    }
}

// MARK: - Sent card

/// The alert's answer for five seconds. Out of reach it is honest: the
/// alert waits in the queue and leaves when the phone is back.
private struct AlertSentCard: View {
    let isQueued: Bool

    var body: some View {
        WatchCard(tint: isQueued ? WatchTheme.Tint.attention : WatchTheme.Tint.success) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xs) {
                HStack(alignment: .top, spacing: WatchTheme.Spacing.s) {
                    Image(systemName: isQueued ? "clock.fill" : "checkmark.seal.fill")
                        .foregroundStyle(isQueued ? WatchTheme.Tint.attention : WatchTheme.Tint.success)
                        .accessibilityHidden(true)
                    Text(isQueued ? LocalizedStringKey("emg_alert_sending") : LocalizedStringKey("emg_alert_sent"))
                        .font(WatchTheme.Typography.cardTitle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if isQueued {
                    QueuedNote()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// "Sends when your iPhone is back in reach."
private struct QueuedNote: View {
    var body: some View {
        Text("watch_emergency_queued")
            .font(WatchTheme.Typography.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Step

/// A numbered step. The number sits in an outlined disc in the primary
/// colour — legible on red, and not dependent on colour at all.
private struct EmergencyStepRow: View {
    let number: Int
    let step: EmergencyStepEntry

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WatchTheme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(WatchTheme.Typography.badge)
                .monospacedDigit()
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .overlay {
                    Circle().strokeBorder(Color.primary, lineWidth: WatchTheme.Stroke.outline(contrast))
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: step.title)
                    .font(WatchTheme.Typography.rowTitle)
                if !step.detail.isEmpty {
                    Text(verbatim: step.detail)
                        .font(WatchTheme.Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("watch_emergency_step_ax \(number)"))
        .accessibilityValue(Text(verbatim: step.detail.isEmpty ? step.title : "\(step.title). \(step.detail)"))
    }
}

// MARK: - Contact

/// A real call from the wrist. The number is reduced to the characters a
/// tel URL accepts; a number with none left renders without a link rather
/// than dialling garbage.
private struct EmergencyContactRow: View {
    let contact: EmergencyContactEntry

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var callURL: URL? {
        let dialable = contact.phone.filter { $0.isASCII && ($0.isNumber || $0 == "+") }
        guard dialable.contains(where: \.isNumber) else { return nil }
        return URL(string: "tel://\(dialable)")
    }

    var body: some View {
        if let url = callURL {
            Link(destination: url) {
                row(isCallable: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("watch_emergency_call_hint"))
        } else {
            row(isCallable: false)
        }
    }

    private func row(isCallable: Bool) -> some View {
        let tint = isCallable ? WatchTheme.Tint.success : WatchTheme.Tint.neutral
        return WatchCard(tint: WatchTheme.Tint.neutral, radius: WatchTheme.Radius.row) {
            HStack(spacing: WatchTheme.Spacing.m) {
                Image(systemName: "phone.fill")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(isCallable ? tint : Color.secondary)
                    .frame(width: WatchTheme.Size.prominentGlyph, height: WatchTheme.Size.prominentGlyph)
                    .background {
                        if isLuminanceReduced {
                            Circle().strokeBorder(tint.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                                  lineWidth: WatchTheme.Stroke.hairline)
                        } else {
                            Circle().fill(tint.opacity(WatchTheme.Opacity.glyphFill))
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                    Text(verbatim: contact.name)
                        .font(WatchTheme.Typography.rowTitle)
                        .lineLimit(1)
                    if !contact.role.isEmpty {
                        Text(verbatim: contact.role)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if !contact.phone.isEmpty {
                        Text(verbatim: contact.phone)
                            .font(WatchTheme.Typography.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // Names and numbers of the household's people stay off a resting wrist.
        .watchPrivate()
    }
}

// MARK: - Signal button

/// The Start button: solid red with white words — the highest-contrast
/// object on the page (content, never glass). Always On draws it as a red
/// outline; once started it settles to the success colour.
private struct SignalButtonStyle: ButtonStyle {
    let isSettled: Bool

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        let tint = isSettled ? WatchTheme.Tint.success : WatchTheme.Tint.emergency
        let shape = RoundedRectangle(cornerRadius: WatchTheme.Radius.card, style: .continuous)
        configuration.label
            .font(WatchTheme.Typography.cardTitle)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
            .multilineTextAlignment(.center)
            .foregroundStyle(isLuminanceReduced ? tint : Color.white)
            .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
            .padding(.horizontal, WatchTheme.Spacing.m)
            .padding(.vertical, WatchTheme.Spacing.xs)
            .background {
                if isLuminanceReduced {
                    shape.strokeBorder(tint.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                       lineWidth: WatchTheme.Stroke.outline(contrast))
                } else {
                    shape.fill(tint)
                }
            }
            .contentShape(shape)
            .opacity(pressed && reduceMotion ? 0.7 : 1)
            .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
            .animation(WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion),
                       value: pressed)
    }
}
