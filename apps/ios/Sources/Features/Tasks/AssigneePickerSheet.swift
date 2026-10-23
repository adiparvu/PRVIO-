import SwiftUI

// MARK: - Assignee picker sheet
//
// Everyone assignable, from the same union the Members hub reads:
// family_members roster ∪ active property_members accounts, deduped by auth
// user id — so the owner is assignable from a partner's device even without
// a roster row. Assignee identity in assignee_ids: roster people keep their
// family_members.id string (migration 090), account-only people store
// "user_<auth id>" (resolved by migration 149), free-text helpers store
// "custom_<name>" (display-only, never notified).

struct AssigneePickerSheet: View {
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss
    @Binding var assigneeIds: [String]
    @Binding var assigneeNames: [String]

    @State private var accountService = AccountMemberService()
    @State private var customName = ""
    @State private var recentCustom = RecentAssigneeNames.load()
    @FocusState private var customFocused: Bool

    // Roster rows without an account behind them still split family/others by
    // their raw role — the same set the Members hub uses.
    private static let familyRoles: Set<String> = ["owner", "partner", "member", "teen", "child"]

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    if !assigneeIds.isEmpty { selectedStrip }
                    if let me = people.first(where: { $0.isSelf }) { assignMeRow(me) }
                    peopleSection("FAMILY MEMBERS", familyPeople)
                    peopleSection("task_assign_others", otherPeople)
                    customSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.sm)
            }
            .navigationTitle("Assign Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Done")
                            if !assigneeIds.isEmpty {
                                Text(verbatim: "· \(assigneeIds.count)")
                            }
                        }
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .task {
                guard let pid = propertyService.primary?.id else { return }
                await accountService.load(propertyId: pid)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheetGround()
    }

    // MARK: People (accounts ∪ roster, deduped by auth user id)

    private var people: [PickPerson] {
        let myId = accountService.currentUserId
        var rosterByUserId: [UUID: FamilyMember] = [:]
        for m in familyService.members {
            if let uid = m.userId { rosterByUserId[uid] = m }
        }

        var linkedUserIds: Set<UUID> = []
        var result: [PickPerson] = []

        for account in accountService.members where account.status == "active" {
            guard let role = PropertyRole.resolve(account.role) else { continue }
            linkedUserIds.insert(account.userId)
            result.append(PickPerson(member: rosterByUserId[account.userId],
                                     account: account,
                                     profile: accountService.profiles[account.userId],
                                     isSelf: account.userId == myId,
                                     isFamily: role.isFamilyMember))
        }
        for m in familyService.members {
            if let uid = m.userId, linkedUserIds.contains(uid) { continue }
            result.append(PickPerson(member: m, account: nil, profile: nil,
                                     isSelf: m.userId != nil && m.userId == myId,
                                     isFamily: Self.familyRoles.contains(m.role)))
        }
        return result
            .filter { !$0.displayName.isEmpty }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private var familyPeople: [PickPerson] { people.filter { $0.isFamily && !$0.isSelf } }
    private var otherPeople: [PickPerson] { people.filter { !$0.isFamily && !$0.isSelf } }

    private var customEntries: [(id: String, name: String)] {
        assigneeIds.filter { $0.hasPrefix("custom_") }
            .map { ($0, String($0.dropFirst("custom_".count))) }
    }

    // MARK: Selected strip

    /// Everyone currently chosen, as removable avatars — visible no matter
    /// how far down the list the row lives.
    private var selectedStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.md) {
                ForEach(Array(zip(assigneeIds, assigneeNames)), id: \.0) { id, name in
                    VStack(spacing: 4) {
                        ZStack(alignment: .topTrailing) {
                            avatarFor(id: id, name: name, size: 44)
                            Button {
                                remove(id: id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(AppFont.scaled(15))
                                    .foregroundStyle(.white, Color.primary.opacity(0.55))
                            }
                            .offset(x: 6, y: -4)
                            .accessibilityLabel(Text(verbatim: name))
                        }
                        Text(verbatim: name)
                            .font(AppFont.scaled(10))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .lineLimit(1)
                    }
                    .frame(width: 56)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.vertical, AppSpacing.xxs)
        }
    }

    // MARK: Rows

    /// The most common assignment deserves a single tap: yourself, first.
    private func assignMeRow(_ me: PickPerson) -> some View {
        let selected = assigneeIds.contains(where: me.matches)
        return Button {
            toggle(me)
        } label: {
            HStack(spacing: AppSpacing.md) {
                avatar(me, size: 36, selected: selected)
                Text("task_assign_me")
                    .font(AppFont.scaled(15, weight: .medium))
                    .foregroundStyle(.primary)
                youBadge
                Spacer()
                checkmark(selected)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .background(rowFill(selected), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(rowStroke(selected))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func peopleSection(_ header: LocalizedStringKey, _ list: [PickPerson]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                sectionHeader(header)
                ForEach(list) { person in
                    personRow(person)
                }
            }
        }
    }

    private func personRow(_ p: PickPerson) -> some View {
        let selected = assigneeIds.contains(where: p.matches)
        return Button {
            toggle(p)
        } label: {
            HStack(spacing: AppSpacing.md) {
                avatar(p, size: 36, selected: selected)
                Text(verbatim: p.displayName)
                    .font(AppFont.scaled(15))
                    .foregroundStyle(.primary)
                Spacer()
                checkmark(selected)
            }
            .padding(.horizontal, AppSpacing.base)
            .padding(.vertical, 10)
            .background(rowFill(selected), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
            .overlay(rowStroke(selected))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Someone else (free text + recents)

    private var customSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            sectionHeader("SOMEONE ELSE")

            ForEach(customEntries, id: \.id) { entry in
                Button {
                    remove(id: entry.id)
                } label: {
                    HStack(spacing: AppSpacing.md) {
                        initialsCircle(name: entry.name, size: 36)
                        Text(verbatim: entry.name)
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                        Spacer()
                        checkmark(true)
                    }
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, 10)
                    .background(rowFill(true), in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                    .overlay(rowStroke(true))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(verbatim: entry.name))
                .accessibilityAddTraits(.isSelected)
            }

            HStack(spacing: AppSpacing.md) {
                TextField("Name", text: $customName)
                    .font(AppFont.scaled(15))
                    .tint(.accentColor)
                    .focused($customFocused)
                    .submitLabel(.done)
                    .onSubmit(addCustom)
                    .padding(.horizontal, AppSpacing.base)
                    .padding(.vertical, 11)
                    .background(Color.primary.opacity(AppOpacity.subtleFill),
                                in: RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous))
                Button(action: addCustom) {
                    Image(systemName: "plus.circle.fill")
                        .font(AppFont.scaled(26))
                        .foregroundStyle(canAddCustom ? Color.accentColor : Color.primary.opacity(AppOpacity.disabled))
                }
                .disabled(!canAddCustom)
                .accessibilityLabel("Add someone else…")
            }

            if !availableRecents.isEmpty {
                sectionHeader("task_assign_recent")
                    .padding(.top, AppSpacing.xxs)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(availableRecents, id: \.self) { name in
                            Button {
                                add(name: name)
                            } label: {
                                Text(verbatim: name)
                                    .font(AppFont.scaled(13, weight: .medium))
                            }
                            .buttonStyle(.plain)
                            .glassFilterCapsule(selected: false)
                        }
                    }
                }
            }
        }
    }

    private var canAddCustom: Bool {
        !customName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var availableRecents: [String] {
        let chosen = Set(customEntries.map { $0.name.lowercased() })
        return recentCustom.filter { !chosen.contains($0.lowercased()) }
    }

    // MARK: Mutations

    private func toggle(_ p: PickPerson) {
        HapticFeedback.selection()
        withAnimation(.snappy) {
            if assigneeIds.contains(where: p.matches) {
                // Drop every alias (a legacy roster id and the account id
                // may both be present), keeping names index-aligned.
                for idx in assigneeIds.indices.reversed() where p.matches(assigneeIds[idx]) {
                    assigneeIds.remove(at: idx)
                    if idx < assigneeNames.count { assigneeNames.remove(at: idx) }
                }
            } else {
                assigneeIds.append(p.pickId)
                assigneeNames.append(p.displayName)
            }
        }
    }

    private func remove(id: String) {
        HapticFeedback.selection()
        withAnimation(.snappy) {
            guard let idx = assigneeIds.firstIndex(of: id) else { return }
            assigneeIds.remove(at: idx)
            if idx < assigneeNames.count { assigneeNames.remove(at: idx) }
        }
    }

    private func addCustom() {
        let name = customName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        add(name: name)
        customName = ""
        customFocused = false
    }

    private func add(name: String) {
        let id = "custom_\(name)"
        guard !assigneeIds.contains(id) else { return }
        HapticFeedback.success()
        withAnimation(.snappy) {
            assigneeIds.append(id)
            assigneeNames.append(name)
        }
        recentCustom = RecentAssigneeNames.remember(name)
    }

    // MARK: Small pieces

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
            .padding(.leading, AppSpacing.xxs)
    }

    private func checkmark(_ selected: Bool) -> some View {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .font(AppFont.scaled(22))
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(AppOpacity.disabled))
            .contentTransition(.symbolEffect(.replace))
    }

    private func rowFill(_ selected: Bool) -> Color {
        selected ? Color.accentColor.opacity(0.10) : Color.primary.opacity(AppOpacity.subtleFill)
    }

    private func rowStroke(_ selected: Bool) -> some View {
        RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
            .strokeBorder(selected ? Color.accentColor.opacity(0.35) : Color.hairline, lineWidth: 1)
    }

    private var youBadge: some View {
        Text("You")
            .font(AppFont.scaled(10, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }

    private func avatar(_ p: PickPerson, size: CGFloat, selected: Bool) -> some View {
        avatarContent(p, size: size)
            .overlay(Circle().strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
    }

    @ViewBuilder
    private func avatarContent(_ p: PickPerson, size: CGFloat) -> some View {
        if let member = p.member {
            MemberAvatar(member: member, size: size)
        } else if let urlStr = MemberDirectory.shared.avatarString(
                      userId: p.account?.userId, fallback: p.profile?.avatarUrl),
                  !urlStr.isEmpty, let url = URL(string: urlStr) {
            // Account-only people (the owner has no roster row on a partner's
            // device): the live, cached profiles directory wins over the
            // snapshot loaded with the account list.
            StorageImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    initialsCircle(name: p.displayName, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsCircle(name: p.displayName, size: size)
        }
    }

    /// Strip avatars resolve through the person list, then — for "user_<uuid>"
    /// entries whose person is gone — through the profiles directory; custom
    /// entries and everyone unresolved fall back to initials.
    @ViewBuilder
    private func avatarFor(id: String, name: String, size: CGFloat) -> some View {
        if let p = people.first(where: { $0.matches(id) }) {
            avatarContent(p, size: size)
        } else if let url = AssigneeAvatarView.directoryAvatarURL(assigneeId: id, name: name) {
            StorageImage(url: url) { phase in
                if case .success(let img) = phase {
                    img.resizable().scaledToFill()
                } else {
                    initialsCircle(name: name, size: size)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialsCircle(name: name, size: size)
        }
    }

    private func initialsCircle(name: String, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.15))
                .overlay(Circle().strokeBorder(Color.accentColor.opacity(0.3), lineWidth: 1))
            Text(verbatim: String(name.prefix(1)).uppercased())
                .font(AppFont.scaled(size * 0.4, weight: .bold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - One assignable human (account ∪ roster)

private struct PickPerson: Identifiable {
    let member: FamilyMember?
    let account: AccountMember?
    let profile: AccountProfile?
    let isSelf: Bool
    let isFamily: Bool

    var id: String { pickId }

    /// The value stored in assignee_ids: the roster id (migration 090) when
    /// that row can actually deliver — i.e. it's linked to an auth user or
    /// there's no account to fall back to. An unlinked roster row shadowing
    /// a real account would silence the assignment push, so the account
    /// fallback (migration 149) wins there.
    ///
    /// Whenever an ACCOUNT exists, its `user_<uid>` form wins — it is the only
    /// encoding the read policy (`is_task_assignee`, migration 151) matches
    /// unconditionally. A roster id only grants read access when that row is
    /// linked to the user AND sits on this exact property; a roster row that
    /// was unlinked, NULL-property or from another home made the tag a dead
    /// letter — the person got the push yet never saw the task.
    var pickId: String {
        if let account { return "user_" + account.userId.uuidString }
        return member?.id.uuidString ?? ""
    }

    /// Every encoding this person may already be stored under — tasks tagged
    /// before the rule above still show them as selected, and un-tagging
    /// removes every alias. Case-insensitive (Swift writes uppercase uuids).
    var aliasIds: Set<String> {
        var ids: Set<String> = [pickId.lowercased()]
        if let member { ids.insert(member.id.uuidString.lowercased()) }
        if let account { ids.insert("user_" + account.userId.uuidString.lowercased()) }
        return ids
    }

    func matches(_ id: String) -> Bool { aliasIds.contains(id.lowercased()) }

    var displayName: String {
        if let p = profile, !p.bestName.isEmpty { return p.bestName }
        return member?.name ?? ""
    }
}

// MARK: - Recent free-text assignees

private enum RecentAssigneeNames {
    private static let key = "task.assignee.recentCustomNames"

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func remember(_ name: String) -> [String] {
        var list = load().filter { $0.caseInsensitiveCompare(name) != .orderedSame }
        list.insert(name, at: 0)
        list = Array(list.prefix(6))
        UserDefaults.standard.set(list, forKey: key)
        return list
    }
}
