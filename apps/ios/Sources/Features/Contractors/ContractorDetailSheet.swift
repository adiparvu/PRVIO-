import SwiftUI
import PhotosUI

struct ContractorDetailSheet: View {
    let contractor: ContractorModel
    var service: ContractorService
    @Environment(AppRouter.self) private var router
    @Environment(FamilyService.self) private var familyService
    @Environment(PropertyService.self) private var propertyService
    @Environment(ProfileService.self) private var profileService
    @Environment(DirectMessageService.self) private var directMessageService
    @Environment(\.dismiss) private var dismiss

    @State private var showEdit = false
    @State private var showDeleteConfirm = false
    @State private var localRating: Int
    @State private var dmMember: FamilyMember?
    @State private var callMember: FamilyMember?

    init(contractor: ContractorModel, service: ContractorService) {
        self.contractor = contractor
        self.service = service
        _localRating = State(initialValue: contractor.rating ?? 0)
    }

    var currentContractor: ContractorModel {
        service.contractors.first(where: { $0.id == contractor.id }) ?? contractor
    }

    /// The household member whose PRVIO account matches this contractor's
    /// phone/email — powers the badge and the in-app message/call bridge,
    /// exactly like the list rows (ContractorAccountMatch is pure and cheap).
    private var matchedMember: FamilyMember? {
        ContractorAccountMatch.member(for: currentContractor, in: familyService.members)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        heroHeader
                        // The linked PRVIO account, first-class (IMG_8644):
                        // who they are in the app, with every real channel.
                        if let member = matchedMember {
                            accountSection(member)
                        }
                        contactSection
                        if currentContractor.notes?.isEmpty == false {
                            notesSection
                        }
                        actionsSection
                        Spacer(minLength: 60)
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                ToolbarItem(placement: .pageMenu) {
                    Menu {
                        Button { showEdit = true } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(.primary)
                    }
                    .accessibilityLabel("Menu")
                }
            }
            .confirmationDialog("Delete \(contractor.name)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Contractor", role: .destructive) {
                    Task { await service.delete(contractor); dismiss() }
                }
            }
            .sheet(isPresented: $showEdit) {
                EditContractorSheet(contractor: currentContractor, service: service)
            }
            // Full-height in-app DM with the matched member — the same
            // construction + bootstrap the contractors list uses, so the
            // thread has history and realtime even when the chat tab was
            // never visited this session.
            .sheet(item: $dmMember) { member in
                NavigationStack {
                    DirectMessageView(member: member)
                }
                .task {
                    guard let pid = propertyService.primary?.id else { return }
                    let myName = profileService.profile?.preferredName
                        ?? profileService.profile?.fullName ?? "Me"
                    directMessageService.myName = myName
                    await directMessageService.load(propertyId: pid, myName: myName)
                    await directMessageService.subscribeRealtime(propertyId: pid, myName: myName)
                }
            }
            .sheet(item: $callMember) { member in
                CallPickerSheet(members: [member], isVideo: false)
            }
        }
        .sheetGround()
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        VStack(spacing: 12) {
            // Avatar chain: the matched PRVIO account's avatar, then the
            // contractor's OWN photo (migration 166), then the trade disc.
            if let member = matchedMember {
                MemberAvatar(member: member, size: 72)
            } else if let urlStr = currentContractor.photoUrl, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7))
            } else {
                ZStack {
                    Circle()
                        .fill(Color.teal.opacity(0.18))
                        .frame(width: 72, height: 72)
                    Image(systemName: contractor.specialtyIcon)
                        .font(AppFont.scaled(28, weight: .semibold))
                        .foregroundStyle(Color.teal)
                }
            }

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(currentContractor.name)
                        .font(AppFont.scaled(20, weight: .bold))
                        .foregroundStyle(.primary)
                    // Same badge the list rows wear when the contractor's
                    // phone/email matches a household PRVIO account.
                    if matchedMember != nil {
                        PRVIOAccountBadge()
                    }
                }

                Text(LocalizedStringKey(currentContractor.specialty.capitalized))
                    .font(AppFont.scaled(13))
                    .foregroundStyle(.secondary)
            }

            ratingStars
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    private var ratingStars: some View {
        HStack(spacing: 6) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= localRating ? "star.fill" : "star")
                    .font(AppFont.scaled(22))
                    .foregroundStyle(star <= localRating ? Color.yellow : Color.primary.opacity(0.25))
                    .onTapGesture {
                        HapticFeedback.selection()
                        localRating = star
                        var updated = contractor
                        updated.rating = star
                        Task { await service.update(updated) }
                    }
            }
        }
    }

    // MARK: - PRVIO account (IMG_8644)

    /// The linked account card: identity (avatar, name, role, badge) plus
    /// every channel the ACCOUNT actually carries — email opens Mail, phone
    /// dials, the header row opens the in-app DM. Only real fields render.
    private func accountSection(_ member: FamilyMember) -> some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                Button {
                    HapticFeedback.impact(.light)
                    dmMember = member
                } label: {
                    HStack(spacing: 14) {
                        MemberAvatar(member: member, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(verbatim: member.name)
                                    .font(AppFont.scaled(15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                PRVIOAccountBadge()
                            }
                            Text(verbatim: member.roleLabel)
                                .font(AppFont.scaled(12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "bubble.left.fill")
                            .font(AppFont.scaled(15))
                            .foregroundStyle(Color.brandSkyBlue)
                    }
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.vertical, AppSpacing.base)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("mem_send_message"))

                // Only channels the contact card below doesn't already show
                // — the account card must add information, not repeat it.
                if let email = member.email, !email.isEmpty,
                   ContractorAccountMatch.emailKey(email)
                       != ContractorAccountMatch.emailKey(currentContractor.email) {
                    rowDivider
                    contactRow(icon: "envelope.fill", label: "Email",
                               value: email, color: .blue) {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
                if let phone = member.phone, !phone.isEmpty,
                   ContractorAccountMatch.phoneKey(phone)
                       != ContractorAccountMatch.phoneKey(currentContractor.phone) {
                    rowDivider
                    contactRow(icon: "phone.fill", label: "Phone",
                               value: phone, color: .green) {
                        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        GlassCard(padding: 0) {
            VStack(spacing: 0) {
                if let phone = currentContractor.phone, !phone.isEmpty {
                    contactRow(
                        icon: "phone.fill",
                        label: "Phone",
                        value: phone,
                        color: .green
                    ) {
                        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                            UIApplication.shared.open(url)
                        }
                    }
                    rowDivider
                }

                if let email = currentContractor.email, !email.isEmpty {
                    contactRow(
                        icon: "envelope.fill",
                        label: "Email",
                        value: email,
                        color: .blue
                    ) {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
        }
    }

    private func contactRow(icon: String, label: LocalizedStringKey, value: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { HapticFeedback.impact(.light); action() }) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .glassCircle()
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(AppFont.scaled(11)).foregroundStyle(.secondary)
                    Text(value).font(AppFont.scaled(15)).foregroundStyle(.primary).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(Color.primary.opacity(0.25))
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
        }
        .buttonStyle(.plain)
    }

    private var rowDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 70)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Notes", systemImage: "note.text")
                    .font(AppFont.captionStrong)
                    .foregroundStyle(.secondary)
                Text(currentContractor.notes ?? "")
                    .font(AppFont.scaled(14))
                    .foregroundStyle(Color.primary.opacity(0.75))
            }
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(spacing: 10) {
            // A contractor with a PRVIO account gets first-class in-app
            // reach: message and call ride the household chat, exactly like
            // the members hub — the phone dialer stays for everyone else.
            if let member = matchedMember {
                actionButton(
                    icon: "bubble.left.fill",
                    label: "mem_send_message",
                    color: .brandSkyBlue
                ) {
                    dmMember = member
                }
            }

            if let phone = currentContractor.phone, !phone.isEmpty {
                actionButton(
                    icon: "phone.fill",
                    label: "Call",
                    color: .green
                ) {
                    if let member = matchedMember {
                        callMember = member
                    } else if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
                        UIApplication.shared.open(url)
                    }
                }
            }

            actionButton(
                icon: "checklist",
                label: "Add Maintenance Task",
                color: .orange
            ) {
                router.navigate(to: .newTask)
                dismiss()
            }

            if let email = currentContractor.email, !email.isEmpty {
                actionButton(
                    icon: "envelope.fill",
                    label: "Send Email",
                    color: .blue
                ) {
                    if let url = URL(string: "mailto:\(email)") {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private func actionButton(icon: String, label: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: { HapticFeedback.impact(.medium); action() }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(AppFont.scaled(16))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .glassCircle()
                Text(label)
                    .font(AppFont.body)
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.base)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Edit Contractor Sheet

struct EditContractorSheet: View {
    let contractor: ContractorModel
    var service: ContractorService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String
    @State private var isSaving = false
    /// Own avatar (train 1147) — same well as the add form; the existing
    /// photo shows until a new pick replaces it.
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var avatarImage: UIImage? = nil

    init(contractor: ContractorModel, service: ContractorService) {
        self.contractor = contractor
        self.service = service
        _name     = State(initialValue: contractor.name)
        _category = State(initialValue: contractor.category)
        _phone    = State(initialValue: contractor.phone ?? "")
        _email    = State(initialValue: contractor.email ?? "")
        _notes    = State(initialValue: contractor.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    avatarPicker
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.md)

                    VStack(spacing: 0) {
                        Group {
                            fieldRow("person.fill", "Name", $name)
                            divider
                            fieldRow("wrench.fill", "Specialty", $category)
                            divider
                            fieldRow("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            divider
                            fieldRow("envelope.fill", "Email", $email, keyboard: .emailAddress)
                            divider
                            fieldRow("note.text", "Notes", $notes)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)
                }
            }
            .onChange(of: avatarItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        withAnimation(.snappy(duration: 0.25)) { avatarImage = image }
                    }
                }
            }
            .navigationTitle("Edit Contractor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                        .disabled(name.isEmpty || category.isEmpty || isSaving)
                }
            }
        }
        .sheetGround()
    }

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(placeholder, text: binding).font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52)
    }

    /// The circular avatar well: a fresh pick, else the contractor's current
    /// photo, else a camera glyph on a clear Liquid Glass disc.
    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            Group {
                if let image = avatarImage {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7))
                } else if let urlStr = contractor.photoUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7))
                } else {
                    Image(systemName: "camera.fill")
                        .font(AppFont.scaled(22, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        .frame(width: 84, height: 84)
                        .glassCircle()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(AppFont.scaled(20))
                    .foregroundStyle(Color.accentColor)
                    .background(Circle().fill(.background).padding(2))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(contractor.photoUrl == nil ? Text("Add photo") : Text("est_change_photo"))
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var updated = contractor
        updated.name = name
        updated.category = category
        updated.phone = phone.isEmpty ? nil : phone
        updated.email = email.isEmpty ? nil : email
        updated.notes = notes.isEmpty ? nil : notes
        // A new pick uploads first (fresh name defeats the public-bucket
        // cache); no pick keeps the existing photo untouched.
        if let image = avatarImage, let data = image.uploadJPEG(quality: 0.82) {
            let path = "contractors/\(contractor.id.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            if let uploaded = try? await SignedStorage.uploadPublicImage(data, path: path) {
                updated.photoUrl = uploaded
            }
        }
        await service.update(updated)
        HapticFeedback.success()
        dismiss()
    }
}
