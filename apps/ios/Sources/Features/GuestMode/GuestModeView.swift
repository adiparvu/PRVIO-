import SwiftUI
import UIKit
import Security

// MARK: - WiFi password stored in Keychain (never UserDefaults)

private enum GuestWiFiKeychain {
    static let service = "com.prvio.app.guest"
    static let account = "wifi_password"

    static func load() -> String {
        let q: [String: Any] = [
            kSecClass as String:        kSecClassGenericPassword,
            kSecAttrService as String:  service,
            kSecAttrAccount as String:  account,
            kSecReturnData as String:   true,
            kSecMatchLimit as String:   kSecMatchLimitOne
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &ref) == errSecSuccess,
              let data = ref as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ password: String) {
        let data = Data(password.utf8)
        // ThisDeviceOnly, like every other secret in the app: the WiFi
        // password must never ride an encrypted backup onto another device.
        let q: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    service,
            kSecAttrAccount as String:    account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String:      data
        ]
        SecItemDelete(q as CFDictionary)
        if !password.isEmpty { SecItemAdd(q as CFDictionary, nil) }
    }
}

// MARK: - GuestModeView
//
// The host's guest sheet editor: Wi-Fi with a live native join QR, predefined
// house-rule chips plus free text, structured essentials (check-in/out, host
// phone) and notes — with a live preview of the exact card the share action
// renders (GuestInfoCard via ImageRenderer).

struct GuestModeView: View {
    @Environment(PropertyService.self) private var propertyService

    @AppStorage("prvio.guest.wifi_name") private var wifiName = ""
    @State private var wifiPass: String = GuestWiFiKeychain.load()
    @AppStorage("prvio.guest.rules") private var houseRules = ""
    @AppStorage("prvio.guest.rules_selected") private var selectedRuleIDs = ""
    @AppStorage("prvio.guest.check_in") private var checkInStored = ""
    @AppStorage("prvio.guest.check_out") private var checkOutStored = ""
    @AppStorage("prvio.guest.host_phone") private var hostPhone = ""
    @AppStorage("prvio.guest.notes") private var guestNotes = ""

    @State private var showPassword = false
    @State private var passwordCopied = false

    private var propertyName: String {
        propertyService.primary?.name ?? String(localized: "My Home")
    }

    private var fullAddress: String {
        guard let property = propertyService.primary else { return "" }
        return [property.addressLine1, property.city]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private var wifiQRPayload: String? {
        WiFiQR.payload(ssid: wifiName, password: wifiPass)
    }

    private var selectedRules: [GuestRule] {
        GuestRule.decode(selectedRuleIDs)
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    headerCard
                    wifiSection
                    rulesSection
                    essentialsSection
                    notesSection
                    previewSection
                    shareButtonCard
                    Spacer(minLength: 110)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
        }
        .navigationTitle("Guest Mode")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: wifiPass) { _, newVal in GuestWiFiKeychain.save(newVal) }
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                moreButton
            }
        }
    }

    // MARK: - Toolbar

    /// One circle (the one-circle law): the page's one-shot share action
    /// lives in the single glass trigger. Action rows, not filters — so the
    /// trigger wears Apple's More glyph, and the share sheet runs through
    /// the popover's action mailbox (after the dismissal transition).
    private var moreButton: some View {
        GlassFilterButton(inToolbar: true, icon: "ellipsis",
                          accessibilityLabelKey: "More") {
            GlassFilterActionRow(icon: "square.and.arrow.up",
                                 title: String(localized: "Share Guest Info")) {
                shareGuestInfo()
            }
        }
    }

    // MARK: - Header Card

    private var headerCard: some View {
        GlassCard {
            HStack(spacing: 14) {
                Image("BrandMark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 26, height: 26)
                    .frame(width: 48, height: 48)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(propertyName)
                        .font(AppFont.scaled(17, weight: .bold))
                        .foregroundStyle(.primary)
                    if !fullAddress.isEmpty {
                        Button {
                            openInMaps()
                        } label: {
                            HStack(spacing: 4) {
                                Text(fullAddress)
                                    .font(AppFont.scaled(13))
                                    .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(2)
                                Image(systemName: "arrow.up.right")
                                    .font(AppFont.scaled(10, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text("guest_open_maps"))
                    }
                    Text("Guest information sheet")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.accentColor)
                }

                Spacer()
            }
        }
    }

    // MARK: - WiFi Section

    private var wifiSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "wifi", title: "WiFi")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    wifiQRArea
                    rowDivider
                    editableRow(icon: "wifi", placeholder: "Network name", text: $wifiName)
                    rowDivider
                    passwordRow
                }
            }
            .animation(.smooth(duration: 0.3), value: wifiQRPayload == nil)
        }
    }

    /// The star of the page: a native Wi-Fi join QR the moment both fields
    /// are filled — and an honest hint (never an empty code) until then.
    @ViewBuilder private var wifiQRArea: some View {
        if let wifiQRPayload {
            VStack(spacing: AppSpacing.md) {
                QRCodeImage(content: wifiQRPayload, size: 168)
                Text("guest_wifi_qr_hint")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("guest_wifi_qr_hint"))
        } else {
            VStack(spacing: AppSpacing.sm) {
                Image(systemName: "qrcode.viewfinder")
                    .font(AppFont.scaled(28))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                Text("guest_wifi_qr_placeholder")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.xl)
            .padding(.horizontal, AppSpacing.xxl)
            .transition(.opacity)
        }
    }

    private var passwordRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.fill")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Group {
                if showPassword {
                    TextField("Password", text: $wifiPass)
                } else {
                    SecureField("Password", text: $wifiPass)
                }
            }
            .font(AppFont.scaled(15))
            .foregroundStyle(.primary)
            .tint(.accentColor)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)

            if !wifiPass.isEmpty {
                Button {
                    copyPassword()
                } label: {
                    Image(systemName: passwordCopied ? "checkmark" : "doc.on.doc")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(passwordCopied ? Color.brandSuccess : Color.accentColor)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(passwordCopied ? Text("Copied") : Text("guest_wifi_copy_password"))

                Button {
                    HapticFeedback.selection()
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showPassword ? Text("guest_wifi_hide_password") : Text("guest_wifi_show_password"))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
        .animation(.snappy(duration: 0.25), value: wifiPass.isEmpty)
    }

    private func copyPassword() {
        UIPasteboard.general.string = wifiPass
        HapticFeedback.success()
        withAnimation(.snappy) { passwordCopied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation(AppMotion.state) { passwordCopied = false }
        }
    }

    // MARK: - Rules Section

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "list.bullet.clipboard.fill", title: "House Rules")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.sm) {
                    ForEach(GuestRule.allCases) { rule in
                        GlassFilterChip(label: rule.title,
                                        systemImage: rule.icon,
                                        isSelected: selectedRules.contains(rule)) {
                            toggleRule(rule)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.clipboard.fill")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text("Rules")
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    TextField(
                        "guest_rules_placeholder",
                        text: $houseRules,
                        axis: .vertical
                    )
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(4...12)
                }
            }
        }
    }

    private func toggleRule(_ rule: GuestRule) {
        var current = selectedRules
        if let index = current.firstIndex(of: rule) {
            current.remove(at: index)
        } else {
            current.append(rule)
        }
        withAnimation(.snappy(duration: 0.25)) {
            selectedRuleIDs = GuestRule.encode(current)
        }
    }

    // MARK: - Essentials Section

    private var essentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "key.fill", title: "guest_essentials_title")
            GlassCard(padding: 0) {
                VStack(spacing: 0) {
                    timeRow(icon: "arrow.right.to.line", title: "guest_checkin",
                            stored: $checkInStored, defaultTime: "15:00")
                    rowDivider
                    timeRow(icon: "arrow.left.to.line", title: "guest_checkout",
                            stored: $checkOutStored, defaultTime: "11:00")
                    rowDivider
                    phoneRow
                }
            }
        }
    }

    private func timeRow(icon: String, title: LocalizedStringKey,
                         stored: Binding<String>, defaultTime: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            Text(title)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
            Spacer()
            if let date = GuestTime.date(from: stored.wrappedValue) {
                DatePicker("",
                           selection: Binding(
                               get: { date },
                               set: { stored.wrappedValue = GuestTime.stored(from: $0) }),
                           displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .accessibilityLabel(Text(title))
                Button {
                    HapticFeedback.impact(.light)
                    withAnimation(.snappy(duration: 0.25)) { stored.wrappedValue = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(AppFont.scaled(16))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("guest_clear_time"))
            } else {
                Button {
                    HapticFeedback.impact(.light)
                    withAnimation(.snappy(duration: 0.25)) { stored.wrappedValue = defaultTime }
                } label: {
                    Text("guest_set_time")
                        .font(AppFont.footnoteEmphasis)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, AppSpacing.base)
                        .padding(.vertical, 6)
                        .glassCapsule()
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 9)
    }

    private var phoneRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField("guest_phone_placeholder", text: $hostPhone)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
                .accessibilityLabel(Text("guest_host_phone"))
            if !hostPhone.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    callHost()
                } label: {
                    Image(systemName: "phone.arrow.up.right")
                        .font(AppFont.scaled(14, weight: .semibold))
                        .foregroundStyle(Color.brandSuccess)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("guest_call_host"))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
        .animation(.snappy(duration: 0.25), value: hostPhone.isEmpty)
    }

    private func callHost() {
        let digits = hostPhone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty, let url = URL(string: "tel://\(digits)") else { return }
        HapticFeedback.impact(.light)
        UIApplication.shared.open(url)
    }

    private func openInMaps() {
        guard let query = fullAddress.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "http://maps.apple.com/?q=\(query)") else { return }
        HapticFeedback.impact(.light)
        UIApplication.shared.open(url)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "note.text", title: "Important Notes")
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "note.text")
                            .font(AppFont.scaled(14))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 24)
                        Text("Notes")
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                    }
                    TextField(
                        "guest_notes_placeholder",
                        text: $guestNotes,
                        axis: .vertical
                    )
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                    .tint(.accentColor)
                    .lineLimit(4...10)
                }
            }
        }
    }

    // MARK: - Preview Section

    /// The exact GuestInfoCard the share action renders, embedded live so the
    /// host always sees what the guest will receive.
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(icon: "eye", title: "Preview")
            guestCard
                .shadow(color: .black.opacity(0.10), radius: 14, y: 6)
            Text("guest_preview_note")
                .font(AppFont.caption2)
                .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                .padding(.leading, AppSpacing.xs)
        }
    }

    private var guestCard: GuestInfoCard {
        GuestInfoCard(
            propertyName: propertyName,
            address: fullAddress,
            wifiName: wifiName.trimmingCharacters(in: .whitespacesAndNewlines),
            wifiQRPayload: wifiQRPayload,
            rules: selectedRules,
            rulesText: houseRules.trimmingCharacters(in: .whitespacesAndNewlines),
            checkIn: GuestTime.display(checkInStored),
            checkOut: GuestTime.display(checkOutStored),
            hostPhone: hostPhone.trimmingCharacters(in: .whitespaces),
            notes: guestNotes.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Share

    private var shareButtonCard: some View {
        GlassWideButton(icon: "square.and.arrow.up", label: "Share Guest Info") {
            shareGuestInfo()
        }
    }

    /// Renders the guest card to a crisp image and hands it to the system
    /// share sheet — the same view shown in the Preview section.
    private func shareGuestInfo() {
        let renderer = ImageRenderer(content: guestCard.frame(width: 430))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return }
        SystemActions.share([image])
        HapticFeedback.impact(.medium)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(AppFont.label)
                .foregroundStyle(Color.backdropSecondaryText)
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(Color.backdropSecondaryText)
                .tracking(0.5)
        }
        .padding(.leading, AppSpacing.xs)
    }

    private func editableRow(icon: String, placeholder: LocalizedStringKey, text: Binding<String>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15))
                .foregroundStyle(.primary)
                .tint(.accentColor)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, 13)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.05))
            .frame(height: 0.5)
            .padding(.leading, 52)
    }
}
