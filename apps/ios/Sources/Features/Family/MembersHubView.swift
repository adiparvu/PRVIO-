import SwiftUI

// MARK: - Members hub
//
// One home for everyone with access to the house: the family (with child
// supervision), non-family members (tenants, workers, friends) and the
// invitation audit trail (who was invited, when, and for how long the link is
// still valid). Replaces the separate "Family Members" + "Supervision" rows.
//
// The Family/Others lists merge TWO real sources by auth user id:
//  - property_members + profiles (AccountMemberService): everyone with an
//    ACTIVE account — including the owner, who never gets a family_members
//    row of their own (creating the property grants membership directly).
//    This is why a partner's device used to show no owner here at all.
//  - family_members (FamilyService): the hand-added roster, with or without
//    a linked account.
// An account linked to a roster row renders ONCE (live profile name, roster
// contact details). The owner sorts first; your own row wears a "You · role"
// badge; a green dot marks members online right now (PresenceService).

struct MembersHubView: View {
    @Environment(FamilyService.self) var familyService
    @Environment(PropertyService.self) var propertyService
    @Environment(PresenceService.self) var presenceService

    @State var invitationService = InvitationService()
    @State var accountService = AccountMemberService()
    @State private var segment: Segment = .family
    @State var searchText = ""
    @State private var showAdd = false
    @State var editingMember: FamilyMember?
    @State var reviewingAccount: AccountMember?
    @State var showRevokedHistory = false

    enum Segment: String, CaseIterable, Identifiable {
        case family, others, accounts, invitations
        var id: String { rawValue }
        var title: LocalizedStringKey {
            switch self {
            case .family:      return "Family"
            case .others:      return "Others"
            case .accounts:    return "Accounts"
            case .invitations: return "Invitations"
            }
        }
        var icon: String {
            switch self {
            case .family:      return "figure.2.and.child.holdinghands"
            case .others:      return "person.2.wave.2.fill"
            case .accounts:    return "person.crop.circle.badge.checkmark"
            case .invitations: return "envelope.badge.clock.fill"
            }
        }

        /// Same catalog entries as `title`, resolved for the segment
        /// popover's `GlassPickerOption` (String titles).
        var titleText: String {
            switch self {
            case .family:      return String(localized: "Family")
            case .others:      return String(localized: "Others")
            case .accounts:    return String(localized: "Accounts")
            case .invitations: return String(localized: "Invitations")
            }
        }
    }

    // Tenants are NOT family — they belong to the Tenants page and to the
    // "others" section here (tenants, workers, friends), never to the
    // family list.
    private static let familyRoles: Set<String> = ["owner", "partner", "member", "teen", "child"]

    var children: [FamilyMember] {
        familyService.members.filter { $0.role == "child" }
    }

    // MARK: Unified people (accounts ∪ roster, deduped by user id)

    var familyPeople: [HubPerson] { people(family: true) }
    var otherPeople: [HubPerson] { people(family: false) }

    private func people(family: Bool) -> [HubPerson] {
        let myId = accountService.currentUserId
        var rosterByUserId: [UUID: FamilyMember] = [:]
        for m in familyService.members {
            if let uid = m.userId { rosterByUserId[uid] = m }
        }

        var linkedUserIds: Set<UUID> = []
        var result: [HubPerson] = []

        // 1. Active accounts, split family/outsider by the typed property
        //    role — the same gate RLS uses (PropertyRole.isFamilyMember).
        for account in accountService.members where account.status == "active" {
            guard let role = PropertyRole.resolve(account.role),
                  role.isFamilyMember == family else { continue }
            linkedUserIds.insert(account.userId)
            result.append(HubPerson(account: account,
                                    profile: accountService.profiles[account.userId],
                                    member: rosterByUserId[account.userId],
                                    isSelf: account.userId == myId))
        }

        // 2. Roster rows without an active account behind them.
        for m in familyService.members {
            guard Self.familyRoles.contains(m.role) == family else { continue }
            if let uid = m.userId, linkedUserIds.contains(uid) { continue }
            result.append(HubPerson(account: nil, profile: nil, member: m,
                                    isSelf: m.userId != nil && m.userId == myId))
        }

        return result
            .filter { $0.matchesSearch(searchText) }
            .sorted { a, b in
                if a.sortRank != b.sortRank { return a.sortRank < b.sortRank }
                return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            }
    }

    var filteredAccounts: [AccountMember] {
        accountService.members.filter { account in
            let profile = accountService.profiles[account.userId]
            let haystack: [String] = [
                profile?.bestName ?? "",
                profile?.email ?? "",
                account.nickname ?? "",          // the row title's fallback
                account.role,                    // raw role slug
                accountRoleLabelText(account.role) // the badge the row shows
            ]
            return haystack.contains { $0.matchesSearch(searchText) }
        }
    }

    var filteredInvitations: [MemberInvitation] {
        invitationService.invitations.filter { inv in
            let haystack: [String] = [
                inv.email,
                inv.name ?? "",
                inv.role,                        // raw role slug
                String(localized: String.LocalizationValue(
                    kRoleLabels[inv.role] ?? inv.role.capitalized)), // visible label
                inv.sentDisplay                  // the visible "Sent …" date
            ]
            return haystack.contains { $0.matchesSearch(searchText) }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                switch segment {
                case .family:      familySection
                case .others:      othersSection
                case .accounts:    accountsSection
                case .invitations: invitationsSection
                }

                Spacer(minLength: 90)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .refreshable {
            await familyService.load()
            if let pid = propertyService.primary?.id {
                async let a: Void = invitationService.load(propertyId: pid)
                async let b: Void = accountService.load(propertyId: pid)
                async let c: Void = presenceService.load(propertyId: pid)
                _ = await (a, b, c)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("Members")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText,
                    prompt: Text("Search…"))
        .toolbar {
            ToolbarItem(placement: .pageMenu) {
                segmentButton
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    HapticFeedback.impact(.light)
                    showAdd = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(AppFont.headline)
                        .foregroundStyle(Color.accentColor)
                }
                .accessibilityLabel("Add member")
            }
        }
        .sheet(isPresented: $showAdd, onDismiss: { reload() }) {
            AddFamilyMemberSheet(propertyId: propertyService.primary?.id,
                                 propertyName: propertyService.primary?.name,
                                 preselectedRole: segment == .others ? "guest" : "member")
                .environment(familyService)
        }
        .sheet(item: $editingMember, onDismiss: { reload() }) { member in
            EditMemberSheet(member: member, invitationService: invitationService)
                .environment(familyService)
                .environment(propertyService)
        }
        .sheet(item: $reviewingAccount) { account in
            AccountReviewSheet(member: account,
                               profile: accountService.profiles[account.userId],
                               service: accountService)
        }
        .task { reload() }
    }

    private func reload() {
        Task {
            await familyService.load()
            if let pid = propertyService.primary?.id {
                async let a: Void = invitationService.load(propertyId: pid)
                async let b: Void = accountService.load(propertyId: pid)
                async let c: Void = presenceService.load(propertyId: pid)
                _ = await (a, b, c)
                // Idempotent — live join/leave flips the green dots instantly.
                await presenceService.subscribe(propertyId: pid)
            }
        }
    }

    // MARK: Segment circle

    /// One circle (the one-circle law): the four-capsule segment row that
    /// used to sit at the top of the page, as a single-select view section
    /// in the page's one glass trigger. A segment switches the view, it
    /// never narrows a list — so the trigger never claims the filtered
    /// accent dot; the invitations row keeps its honest pending count.
    private var segmentButton: some View {
        GlassFilterButton(inToolbar: true) {
            GlassFilterSection(
                title: "cal_mode_picker",
                options: Segment.allCases.map { seg in
                    GlassPickerOption(value: seg,
                                      icon: seg.icon,
                                      title: seg.titleText,
                                      count: seg == .invitations && pendingInviteCount > 0
                                          ? pendingInviteCount : nil)
                },
                selection: $segment)
        }
    }

    private var pendingInviteCount: Int {
        invitationService.invitations.filter { !$0.accepted && !$0.isRevoked && !$0.isExpired }.count
    }
}

// MARK: - Edit member sheet

struct EditMemberSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    let member: FamilyMember
    let invitationService: InvitationService

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var role: String = "member"
    @State private var color: String = "#5B8AF5"
    @State private var isSaving = false
    @State private var confirmDelete = false
    @State private var errorMessage: String?

    /// Empty is fine (e-mail is optional); non-empty must pass the shared
    /// EmailFormat authority — same rule as the add-member and tenant flows.
    private var emailFieldOK: Bool {
        email.trimmingCharacters(in: .whitespaces).isEmpty || EmailFormat.isValid(email)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        // Identity preview
                        ZStack {
                            Circle().fill((Color(hex: color) ?? .blue).opacity(0.22))
                                .overlay(Circle().strokeBorder((Color(hex: color) ?? .blue).opacity(0.5), lineWidth: 2))
                            Text(String(name.prefix(2)).uppercased())
                                .font(AppFont.scaled(26, weight: .bold))
                                .foregroundStyle(Color(hex: color) ?? .blue)
                        }
                        .frame(width: 76, height: 76)
                        .padding(.top, AppSpacing.sm)

                        // Colour swatches removed (IMG_8664) — the member's
                        // colour is a stable identity set at add time.
                        VStack(spacing: 0) {
                            editRow(icon: "person.fill", tint: .blue, placeholder: "Name", text: $name)
                            div
                            editRow(icon: "envelope.fill", tint: .orange, placeholder: "E-mail", text: $email,
                                    keyboard: .emailAddress)
                            div
                            editRow(icon: "phone.fill", tint: Color.brandSuccess, placeholder: "Phone", text: $phone,
                                    keyboard: .phonePad)
                            div
                            HStack(spacing: 12) {
                                Image(systemName: kRoleIcons[role] ?? "person.fill")
                                    .font(AppFont.scaled(14)).foregroundStyle(.purple).frame(width: 28)
                                Text("Role").font(AppFont.scaled(15)).foregroundStyle(.primary)
                                Spacer()
                                Picker("", selection: $role) {
                                    ForEach(kRoles.filter { $0 != "owner" } + (role == "owner" ? ["owner"] : []), id: \.self) { r in
                                        Text(LocalizedStringKey(kRoleLabels[r] ?? r.capitalized)).tag(r)
                                    }
                                }
                                .tint(Color.primary.opacity(AppOpacity.mediumText))
                            }
                            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.xs)
                        }
                        .liquidGlass(cornerRadius: AppRadius.lg)

                        if !emailFieldOK {
                            Label {
                                Text("This e-mail address doesn't look valid")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.brandDanger)
                            } icon: {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(Color.brandDanger)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, AppSpacing.xxs)
                        }

                        if let err = errorMessage {
                            Text(err).font(AppFont.scaled(13)).foregroundStyle(.red)
                                .multilineTextAlignment(.center)
                        }

                        if member.role != "owner" {
                            Button(role: .destructive) { confirmDelete = true } label: {
                                HStack {
                                    Image(systemName: "trash.fill")
                                    Text("Remove member")
                                }
                                .font(AppFont.subheadline)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: {
                        if isSaving { ProgressView().tint(.accentColor) }
                        else { Text("Save").font(AppFont.subheadline).foregroundStyle(Color.accentColor) }
                    }
                    .disabled(isSaving
                              || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || !emailFieldOK)
                }
            }
            .confirmationDialog("Remove this member?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Remove member", role: .destructive) { Task { await remove() } }
            } message: {
                Text("They lose access to the home and are removed from the member list. This cannot be undone.")
            }
        }
        .onAppear {
            name = member.name
            email = member.email ?? ""
            phone = member.phone ?? ""
            role = member.role
            color = member.color
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = member
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.email = email.isEmpty ? nil : email
        updated.phone = phone.isEmpty ? nil : phone
        updated.role = role
        updated.color = color
        if await familyService.update(updated) {
            HapticFeedback.success()
            dismiss()
        } else {
            errorMessage = familyService.error ?? String(localized: "Couldn't save changes.")
            HapticFeedback.warning()
        }
    }

    private func remove() async {
        do {
            try await invitationService.removeMember(familyMemberId: member.id)
            await familyService.load()
            HapticFeedback.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func editRow(icon: String, tint: Color, placeholder: LocalizedStringKey,
                         text: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(tint).frame(width: 28)
            TextField(placeholder, text: text)
                .font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor)
                .keyboardType(keyboard)
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var div: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }
}
