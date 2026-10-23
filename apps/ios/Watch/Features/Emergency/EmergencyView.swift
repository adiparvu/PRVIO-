import SwiftUI

// MARK: - Emergency: the property's own plan on the wrist
//
// Alert the family, raise the phone's Emergency Live Activity, walk the
// shutoff steps, call a contact. Everything comes from what the owner set up
// on the phone; nothing is invented. The ground is a signal, never an
// atmosphere, so it never adopts the mood or sky.
//
// "Alert the family" is the page's primary action (bottom toolbar) and
// always asks first: a pocket-tap false alarm costs the family real
// adrenaline.

struct EmergencyView: View {
    @Environment(WatchStore.self) private var store

    @State private var isConfirmingAlert = false
    /// When the alert was sent; drives the 5 s "sent" state.
    @State private var alertSentAt: Date?

    private static let sentConfirmation: Duration = .seconds(5)

    init() {}

    private var propertyName: String { store.payload?.snapshot.propertyName ?? "" }
    private var steps: [EmergencyStepEntry] { store.payload?.emergencySteps ?? [] }
    private var contacts: [EmergencyContactEntry] { store.payload?.emergencyContacts ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.l) {
                if alertSentAt != nil {
                    AlertSentBanner()
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if store.isFamilyScope {
                    startEmergencyButton
                }

                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: WatchTheme.Spacing.s) {
                        SectionHeader("watch_emergency_steps")
                        WatchCard(tint: WatchTheme.Tint.warning) {
                            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                                    EmergencyStepRow(number: index + 1, step: step)
                                }
                            }
                        }
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
        }
        .navigationTitle(Text(WatchModule.emergency.titleKey))
        .watchSignalGround(WatchTheme.Tint.emergency)
        .toolbar {
            // The condition lives inside the item: ToolbarContentBuilder's
            // documented `buildIf` only takes customizable (id'd) content.
            ToolbarItem(placement: .bottomBar) {
                if store.canAlertFamily {
                    alertFamilyButton
                }
            }
        }
        .confirmationDialog("emg_alert_confirm_title",
                            isPresented: $isConfirmingAlert,
                            titleVisibility: .visible) {
            Button("emg_alert_confirm_send", role: .destructive) {
                store.alertFamily()
                withAnimation(WatchTheme.Motion.snappy) { alertSentAt = Date() }
            }
        } message: {
            Text("emg_alert_confirm_msg \(propertyName)")
        }
        .task(id: alertSentAt) {
            guard alertSentAt != nil else { return }
            do { try await Task.sleep(for: Self.sentConfirmation) } catch { return }
            withAnimation(WatchTheme.Motion.smooth) { alertSentAt = nil }
        }
    }

    // MARK: Actions

    private var alertFamilyButton: some View {
        Button {
            // While the "sent" state shows, a second alert is one tap too
            // easy; the state clears on its own after a few seconds.
            guard alertSentAt == nil else { return }
            isConfirmingAlert = true
        } label: {
            Label(alertSentAt == nil ? LocalizedStringKey("emg_alert_family")
                                     : LocalizedStringKey("emg_alert_sent"),
                  systemImage: alertSentAt == nil ? "exclamationmark.bubble.fill" : "checkmark.seal.fill")
                .contentTransition(.symbolEffect(.replace))
        }
        .tint(alertSentAt == nil ? WatchTheme.Tint.emergency : WatchTheme.Tint.success)
    }

    private var startEmergencyButton: some View {
        Button {
            store.startEmergency()
        } label: {
            Label("watch_emergency_start", systemImage: "light.beacon.max.fill")
                .font(WatchTheme.Typography.cardTitle)
                .frame(maxWidth: .infinity, minHeight: WatchTheme.Size.actionMinHeight)
        }
        .buttonStyle(.borderedProminent)
        .tint(WatchTheme.Tint.emergency)
    }
}

// MARK: - Sent banner

private struct AlertSentBanner: View {
    var body: some View {
        WatchCard(tint: WatchTheme.Tint.success) {
            Label {
                Text("emg_alert_sent")
                    .font(WatchTheme.Typography.cardTitle)
            } icon: {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(WatchTheme.Tint.success)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Step

private struct EmergencyStepRow: View {
    let number: Int
    let step: EmergencyStepEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WatchTheme.Spacing.s) {
            Text(verbatim: "\(number)")
                .font(WatchTheme.Typography.badge)
                .foregroundStyle(WatchTheme.Tint.warning)
                .monospacedDigit()
            VStack(alignment: .leading, spacing: 1) {
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
    }
}

// MARK: - Contact

/// A real call from the wrist. The number is reduced to the characters a
/// tel URL accepts; a number with none left renders without a link rather
/// than dialling garbage.
private struct EmergencyContactRow: View {
    let contact: EmergencyContactEntry

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
        WatchCard(tint: isCallable ? WatchTheme.Tint.success : WatchTheme.Tint.neutral) {
            HStack(spacing: WatchTheme.Spacing.m) {
                Image(systemName: "phone.fill")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(isCallable ? WatchTheme.Tint.success : Color.secondary)
                    .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                    .background((isCallable ? WatchTheme.Tint.success : WatchTheme.Tint.neutral)
                                    .opacity(WatchTheme.Opacity.glyphFill), in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: contact.name)
                        .font(WatchTheme.Typography.rowTitle)
                        .lineLimit(1)
                    if !contact.role.isEmpty {
                        Text(verbatim: contact.role)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // Names and numbers of the household's people stay off a resting wrist.
        .privacySensitive()
    }
}
