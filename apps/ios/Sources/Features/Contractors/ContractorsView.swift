import SwiftUI
import Observation
import PhotosUI

struct ContractorModel: Identifiable, Codable {
    let id: UUID
    var name: String
    var category: String    // DB column: category
    var phone: String?
    var email: String?
    var notes: String?
    var rating: Int?
    var isPreferred: Bool
    var website: String?
    var address: String?
    /// The contractor's own photo (migration 166) — used only when no PRVIO
    /// account matches; matched accounts keep the account's avatar.
    var photoUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, category, phone, email, notes, rating, website, address
        case isPreferred = "is_preferred"
        case photoUrl    = "photo_url"
    }

    var specialty: String { category }  // backward-compat alias for UI

    var specialtyIcon: String {
        switch category.lowercased() {
        case let s where s.contains("electr"): return "bolt.fill"
        case let s where s.contains("plumb"): return "drop.fill"
        case let s where s.contains("paint"): return "paintbrush.fill"
        case let s where s.contains("roof"): return "house.fill"
        case let s where s.contains("hvac"), let s where s.contains("heat"): return "thermometer.medium"
        case let s where s.contains("clean"): return "sparkles"
        case let s where s.contains("garden"), let s where s.contains("landscape"): return "leaf.fill"
        default: return "wrench.and.screwdriver.fill"
        }
    }
}

@MainActor
@Observable
final class ContractorService {
    var contractors: [ContractorModel] = []
    var isLoading = false
    var error: String?

    func load() async {
        let pid = PropertyService.activePropertyId
        // Paint the last known state instantly; the network refresh follows.
        if contractors.isEmpty, let cached = ServiceCache.load([ContractorModel].self, entity: "contractors", propertyId: pid) {
            contractors = cached
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // RLS scopes this to the caller's household; the property filter
            // narrows it to the selected home and the cap just prevents an
            // unbounded select as the table grows over the years.
            contractors = try await PropertyRepo.fetch(table: "contractors", propertyId: pid,
                                                       order: "name", ascending: true, limit: 500)
            ServiceCache.save(contractors, entity: "contractors", propertyId: pid)
        } catch {
            self.error = error.recordableDescription
        }
    }

    func add(_ c: NewContractor) async throws {
        let result: ContractorModel = try await supabase
            .from("contractors").insert(c).select().single().execute().value
        contractors.append(result)
        contractors.sort { $0.name < $1.name }
    }

    func update(_ c: ContractorModel) async {
        do {
            let result: ContractorModel = try await supabase
                .from("contractors")
                .update([
                    "name": c.name,
                    "category": c.category,
                    "phone": c.phone ?? "",
                    "email": c.email ?? "",
                    "notes": c.notes ?? "",
                    "rating": String(c.rating ?? 0),
                    "is_preferred": c.isPreferred ? "true" : "false",
                    "photo_url": c.photoUrl ?? "",
                ])
                .eq("id", value: c.id.uuidString)
                .select()
                .single()
                .execute()
                .value
            if let i = contractors.firstIndex(where: { $0.id == c.id }) {
                contractors[i] = result
            }
        } catch {
            self.error = error.recordableDescription
        }
    }

    func delete(_ c: ContractorModel) async {
        do {
            try await supabase.from("contractors").delete().eq("id", value: c.id.uuidString).execute()
            contractors.removeAll { $0.id == c.id }
        } catch {
            self.error = error.recordableDescription
        }
    }
}

struct NewContractor: Encodable {
    let propertyId: UUID
    let createdBy: UUID?
    let name: String
    let category: String
    let phone: String?
    let email: String?
    let notes: String?
    let isPreferred: Bool
    var photoUrl: String? = nil
    enum CodingKeys: String, CodingKey {
        case name, category, phone, email, notes
        case propertyId  = "property_id"
        case createdBy   = "created_by"
        case isPreferred = "is_preferred"
        case photoUrl    = "photo_url"
    }
}

// Per-device contractor favorites (like starred documents).
enum ContractorFavoritesStore {
    private static let key = "prvio.contractor.favorites"
    static func ids() -> Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }
    static func isFavorite(_ id: UUID) -> Bool { ids().contains(id.uuidString) }
    @discardableResult
    static func toggle(_ id: UUID) -> Bool {
        var s = ids()
        let now: Bool
        if s.contains(id.uuidString) { s.remove(id.uuidString); now = false }
        else { s.insert(id.uuidString); now = true }
        UserDefaults.standard.set(Array(s), forKey: key)
        return now
    }
}

struct ContractorsView: View {
    @Environment(ContractorService.self) private var service
    @Environment(AuthService.self) private var auth
    @Environment(PropertyService.self) private var propertyService
    @Environment(FamilyService.self) private var familyService
    @Environment(FinancialService.self) private var financialService
    @Environment(TaskService.self) private var taskService
    @Environment(ProfileService.self) private var profileService
    @Environment(DirectMessageService.self) private var directMessageService
    @State private var showAdd = false
    @State private var selectedContractor: ContractorModel? = nil
    @State private var editContractor: ContractorModel? = nil
    @State private var deleteCandidate: ContractorModel? = nil
    /// Matched member whose in-app DM thread is being opened from a row.
    @State private var dmMember: FamilyMember? = nil
    /// Matched member for the chat surface's own call affordance (the same
    /// CallPickerSheet DirectMessageView presents from its header).
    @State private var callMember: FamilyMember? = nil
    @State private var search = ""
    @State private var favoritesOnly = false
    @State private var favRefresh = 0

    var filtered: [ContractorModel] {
        _ = favRefresh
        var list = service.contractors
        if favoritesOnly {
            let favs = ContractorFavoritesStore.ids()
            list = list.filter { favs.contains($0.id.uuidString) }
        }
        guard !search.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(search) ||
            $0.specialty.localizedCaseInsensitiveContains(search)
        }
    }

    /// Contractor id → property member with a PRVIO account, rebuilt from the
    /// already-loaded in-memory lists (O(n + m), no network).
    private var accountMatches: [UUID: FamilyMember] {
        ContractorAccountMatch.matches(contractors: service.contractors,
                                       members: familyService.members)
    }

    /// Compact "history on this property" figure for the peek card: how many
    /// already-loaded financial records and tasks mention the contractor by
    /// name. Pure in-memory sweep, evaluated only when a preview is presented.
    private func historyCount(for contractor: ContractorModel) -> Int {
        let name = contractor.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3 else { return 0 }
        let financial = financialService.records.filter {
            $0.title.localizedCaseInsensitiveContains(name) ||
            ($0.description?.localizedCaseInsensitiveContains(name) ?? false)
        }.count
        let tasks = taskService.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(name) ||
            ($0.notes?.localizedCaseInsensitiveContains(name) ?? false)
        }.count
        return financial + tasks
    }

    var body: some View {
        ZStack {
            appBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                if service.isLoading {
                    Spacer(); ProgressView().tint(.white); Spacer()
                } else if filtered.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "person.badge.key.fill").font(AppFont.scaled(44)).foregroundStyle(Color.primary.opacity(0.18))
                        Text(LocalizedStringKey(service.contractors.isEmpty ? "No contractors yet" : "No results")).font(AppFont.scaled(17)).foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                        if service.contractors.isEmpty {
                            Button("Add your first contractor") { showAdd = true }.font(AppFont.scaled(14)).foregroundStyle(Color.accentColor)
                        }
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 10) {
                            // Hoisted: one O(n + m) index build per render,
                            // not one per row.
                            let matches = accountMatches
                            ForEach(filtered) { c in
                                let matched = matches[c.id]
                                ContractorRow(contractor: c,
                                              isFavorite: ContractorFavoritesStore.isFavorite(c.id),
                                              matchedMember: matched,
                                              onOpenDM: { dmMember = $0 },
                                              onOpenCallPicker: { callMember = $0 })
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        HapticFeedback.selection()
                                        selectedContractor = c
                                    }
                                    .contextMenu {
                                        if let phone = c.phone, !phone.isEmpty {
                                            Button { call(phone) } label: { Label("Call", systemImage: "phone.fill") }
                                        }
                                        if matched != nil || c.phone?.isEmpty == false {
                                            Button {
                                                if let matched {
                                                    HapticFeedback.selection()
                                                    dmMember = matched
                                                } else if let phone = c.phone {
                                                    openContactURL("sms://\(contactURLDigits(phone))")
                                                }
                                            } label: { Label("Message", systemImage: "message.fill") }
                                        }
                                        if let phone = c.phone, !phone.isEmpty {
                                            Button {
                                                openContactURL("facetime://\(contactURLDigits(phone))")
                                            } label: { Label("FaceTime", systemImage: "video.fill") }
                                        }
                                        if let email = c.email, !email.isEmpty {
                                            Button {
                                                openContactURL("mailto:\(email)")
                                            } label: { Label("Email", systemImage: "envelope.fill") }
                                        }
                                        Button {
                                            HapticFeedback.selection()
                                            ContractorFavoritesStore.toggle(c.id); favRefresh += 1
                                        } label: {
                                            Label(ContractorFavoritesStore.isFavorite(c.id) ? "Remove from favorites" : "Add to favorites",
                                                  systemImage: ContractorFavoritesStore.isFavorite(c.id) ? "star.slash" : "star")
                                        }
                                        Button { editContractor = c } label: { Label("Edit", systemImage: "pencil") }
                                        Divider()
                                        Button(role: .destructive) {
                                            deleteCandidate = c
                                        } label: { Label("Delete", systemImage: "trash") }
                                    } preview: {
                                        ContractorPeekCard(contractor: c,
                                                           member: matched,
                                                           historyCount: historyCount(for: c))
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            deleteCandidate = c
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                    .swipeActions(edge: .leading) {
                                        Button {
                                            HapticFeedback.selection()
                                            ContractorFavoritesStore.toggle(c.id); favRefresh += 1
                                        } label: {
                                            Label("Favorite", systemImage: "star")
                                        }.tint(.yellow)
                                    }
                            }
                        }
                        .padding(.horizontal, AppSpacing.xl).padding(.bottom, 110)
                    }
                    .refreshable { await service.load() }
                }
            }
        }
        .task {
            // Members power the PRVIO-account matching; they are loaded at
            // startup, so this only refetches after a cold cache. Contractors
            // follow the same rule: fetch once, then rely on the service's
            // in-memory state (pull-to-refresh re-fetches explicitly).
            if service.contractors.isEmpty {
                async let contractorsLoad: Void = service.load()
                if familyService.members.isEmpty { await familyService.load() }
                await contractorsLoad
            } else if familyService.members.isEmpty {
                await familyService.load()
            }
        }
        .sheet(isPresented: $showAdd) {
            AddContractorSheet(service: service, propertyId: propertyService.primary?.id,
                               userId: auth.session?.user.id,
                               members: familyService.members)
        }
        .sheet(item: $selectedContractor) { c in
            ContractorDetailSheet(contractor: c, service: service)
        }
        .sheet(item: $editContractor) { c in
            EditContractorSheet(contractor: c, service: service)
        }
        // Full-height in-app DM with the matched member — the same
        // construction ConversationsView uses (DirectMessageView reads
        // everything else, including myName, from the environment). The task
        // mirrors ConversationsView's bootstrap so the thread has history and
        // realtime even when the chat tab was never visited this session.
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
        // Mirrors DirectMessageView's own header call affordance.
        .sheet(item: $callMember) { member in
            CallPickerSheet(members: [member], isVideo: false)
        }
        .confirmationDialog(
            Text("Delete \(deleteCandidate?.name ?? "")?"),
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Contractor", role: .destructive) {
                guard let c = deleteCandidate else { return }
                deleteCandidate = nil
                HapticFeedback.warning()
                Task { await service.delete(c) }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { service.error != nil },
            set: { if !$0 { service.error = nil } }
        )) {
            Button("OK") { service.error = nil }
        } message: {
            Text(service.error ?? "")
        }
        .navigationTitle("Contractors")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search,
                    prompt: Text("Search…"))
        .floatingSpeedDial(.contractors)
        .toolbar {
            if !service.contractors.isEmpty {
                ToolbarItem(placement: .pageMenu) {
                    filterButton
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                    Image(systemName: "plus")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel("Add contractor")
            }
        }
    }

    // MARK: - Toolbar

    /// One circle, everything (the one-circle law): the favorites star that
    /// used to sit as its own toolbar toggle folds into the page's single
    /// aggregated filter popover. The accent dot is honest — it lights only
    /// when the list is genuinely narrowed to favorites.
    private var filterButton: some View {
        GlassFilterButton(isActive: favoritesOnly, inToolbar: true) {
            GlassFilterToggleRow(icon: "star.fill",
                                 title: String(localized: "Favorites"),
                                 isOn: $favoritesOnly)
        }
    }

    private func call(_ phone: String) {
        HapticFeedback.impact(.light)
        if let url = URL(string: "tel://\(phone.filter { $0.isNumber })") {
            UIApplication.shared.open(url)
        }
    }
}

private struct ContractorRow: View {
    let contractor: ContractorModel
    var isFavorite: Bool = false
    /// Property member with a PRVIO account matching this contractor, if any.
    var matchedMember: FamilyMember? = nil
    /// Opens the in-app 1:1 DM with the matched member (default tap on the
    /// message icon when matched).
    var onOpenDM: (FamilyMember) -> Void = { _ in }
    /// Presents the chat surface's call affordance for the matched member
    /// (default tap on the call icon when matched).
    var onOpenCallPicker: (FamilyMember) -> Void = { _ in }

    /// Channel data: the contractor's own fields, falling back to the matched
    /// member's profile so a linked account stays reachable either way.
    private var channelPhone: String? {
        nonEmpty(contractor.phone) ?? nonEmpty(matchedMember?.phone)
    }
    private var channelEmail: String? {
        nonEmpty(contractor.email) ?? nonEmpty(matchedMember?.email)
    }
    private var hasChannels: Bool { channelPhone != nil || channelEmail != nil }

    var body: some View {
        GlassCard {
            HStack(spacing: 14) {
                // Avatar chain (IMG_8643 + train 1147): the matched PRVIO
                // account's avatar first, the contractor's OWN photo second,
                // and the round glass disc with the trade icon last — never
                // a tinted square.
                if let member = matchedMember {
                    MemberAvatar(member: member, size: 44)
                } else if let urlStr = contractor.photoUrl, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Circle().fill(.ultraThinMaterial)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.7))
                } else {
                    Image(systemName: contractor.specialtyIcon)
                        .font(AppFont.scaled(17, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .glassCircle()
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(contractor.name).font(AppFont.subheadline).foregroundStyle(.primary).lineLimit(1)
                        if matchedMember != nil {
                            PRVIOAccountBadge()
                        }
                        if isFavorite {
                            Image(systemName: "star.fill").font(AppFont.scaled(11)).foregroundStyle(.yellow)
                        }
                    }
                    Text(LocalizedStringKey(contractor.specialty.capitalized)).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer()
                // Two-layer quick actions: default tap = the primary channel
                // (in-app when the contractor has a PRVIO account), long-press
                // = a native menu of every other way to reach them.
                if matchedMember != nil || channelPhone != nil {
                    quickAction("message.fill", accessibility: "Message contractor") {
                        if let member = matchedMember {
                            onOpenDM(member)
                        } else if let phone = channelPhone {
                            openContactURL("sms://\(contactURLDigits(phone))")
                        }
                    }
                    quickAction("phone.fill", accessibility: "Call contractor") {
                        if let member = matchedMember {
                            onOpenCallPicker(member)
                        } else if let phone = channelPhone {
                            openContactURL("tel://\(contactURLDigits(phone))")
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func quickAction(_ icon: String,
                             accessibility: LocalizedStringKey,
                             primary: @escaping () -> Void) -> some View {
        Group {
            if hasChannels {
                Menu {
                    ContractorChannelMenu(phone: channelPhone, email: channelEmail)
                } label: {
                    quickActionIcon(icon)
                } primaryAction: {
                    HapticFeedback.impact(.light)
                    primary()
                }
            } else {
                Button {
                    HapticFeedback.impact(.light)
                    primary()
                } label: {
                    quickActionIcon(icon)
                }
            }
        }
        .glassCircle()
        .accessibilityLabel(accessibility)
    }

    private func quickActionIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(AppFont.scaled(16))
            .foregroundStyle(.primary)
            .frame(width: 38, height: 38)
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}

// MARK: - Contact plumbing (shared by row + context menu)

/// Digits (plus leading "+") suitable for tel:/sms:/facetime: URLs.
private func contactURLDigits(_ phone: String) -> String {
    phone.filter { $0.isNumber || $0 == "+" }
}

private func openContactURL(_ raw: String) {
    HapticFeedback.impact(.light)
    guard let url = URL(string: raw) else { return }
    UIApplication.shared.open(url)
}

/// Long-press menu on the row's quick-action icons: every other channel for
/// reaching the contractor, built only from data that actually exists.
private struct ContractorChannelMenu: View {
    let phone: String?
    let email: String?

    var body: some View {
        Section("Alege cum contactezi") {
            if let phone, !phone.isEmpty {
                let urlDigits = contactURLDigits(phone)
                let bareDigits = phone.filter(\.isNumber)
                Button {
                    openContactURL("facetime://\(urlDigits)")
                } label: { Label("FaceTime", systemImage: "video.fill") }
                Button {
                    openContactURL("facetime-audio://\(urlDigits)")
                } label: { Label("FaceTime Audio", systemImage: "phone.and.waveform.fill") }
                Button {
                    openContactURL("https://wa.me/\(bareDigits)")
                } label: { Label("WhatsApp", systemImage: "message.fill") }
                Button {
                    openContactURL("tg://resolve?phone=\(bareDigits)")
                } label: { Label("Telegram", systemImage: "paperplane.fill") }
                Button {
                    openContactURL("sms://\(urlDigits)")
                } label: { Label("Mesaj SMS", systemImage: "bubble.left.fill") }
                Button {
                    openContactURL("tel://\(urlDigits)")
                } label: { Label("Sună clasic", systemImage: "phone.fill") }
            } else if let email, !email.isEmpty {
                // No phone on file: FaceTime still works against the account
                // email; every phone-bound channel is deliberately absent.
                Button {
                    openContactURL("facetime://\(email)")
                } label: { Label("FaceTime", systemImage: "video.fill") }
                Button {
                    openContactURL("facetime-audio://\(email)")
                } label: { Label("FaceTime Audio", systemImage: "phone.and.waveform.fill") }
            }
        }
    }
}

// MARK: - PRVIO account badge

/// Small monochrome glass capsule marking contractors who also have a PRVIO
/// account on this property.
struct PRVIOAccountBadge: View {
    var body: some View {
        Text(verbatim: "PRVIO")
            .font(AppFont.label)
            .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .glassCapsule()
            .accessibilityLabel(Text("Are cont PRVIO"))
    }
}

// MARK: - Long-press peek card

/// Rich `.contextMenu` preview for a contractor row: avatar (member photo when
/// the contractor has a PRVIO account, monochrome initials on glass
/// otherwise), name + trade, contact rows, and a compact history line
/// computed from data already in memory.
struct ContractorPeekCard: View {
    let contractor: ContractorModel
    let member: FamilyMember?
    let historyCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(contractor.name)
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                            .lineLimit(1)
                        if member != nil {
                            PRVIOAccountBadge()
                        }
                    }
                    Text(LocalizedStringKey(contractor.specialty.capitalized))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
                Spacer(minLength: 0)
            }
            if contractor.phone?.isEmpty == false || contractor.email?.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    if let phone = contractor.phone, !phone.isEmpty {
                        contactLine("phone.fill", phone)
                    }
                    if let email = contractor.email, !email.isEmpty {
                        contactLine("envelope.fill", email)
                    }
                }
            }
            if historyCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                    Text("Activitate pe proprietate: \(historyCount)")
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.primary.opacity(AppOpacity.secondaryText))
                }
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial)
    }

    @ViewBuilder private var avatar: some View {
        if let member {
            MemberAvatar(member: member, size: 56)
        } else if let urlStr = contractor.photoUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Circle().fill(.ultraThinMaterial)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
        } else {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 1)
                Text(initials)
                    .font(AppFont.scaled(18, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
            }
            .frame(width: 56, height: 56)
        }
    }

    private var initials: String {
        let parts = contractor.name.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(contractor.name.prefix(2)).uppercased()
    }

    private func contactLine(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(AppFont.scaled(13))
                .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                .frame(width: 20)
            Text(value)
                .font(AppFont.scaled(14))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }
}

private struct AddContractorSheet: View {
    var service: ContractorService
    let propertyId: UUID?
    let userId: UUID?
    /// The household roster (IMG_8645): typing a name, email or phone that
    /// matches someone already in PRVIO surfaces live suggestions whose tap
    /// autofills the form — the saved contractor then auto-links to that
    /// account (badge, avatar, in-app message) through the existing match.
    var members: [FamilyMember] = []
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""; @State private var category = ""; @State private var phone = ""
    @State private var email = ""; @State private var notes = ""; @State private var isSaving = false
    /// Own avatar (train 1147) — for contractors without a PRVIO account;
    /// matched accounts keep showing the account's avatar everywhere.
    @State private var avatarItem: PhotosPickerItem? = nil
    @State private var avatarImage: UIImage? = nil

    /// Live matches from what's typed so far — name/email substrings (2+
    /// chars) or phone digits (4+), capped at three honest rows.
    private var suggestions: [FamilyMember] {
        let qName = name.trimmingCharacters(in: .whitespaces).lowercased()
        let qEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
        let qPhone = phone.filter(\.isNumber)
        guard qName.count >= 2 || qEmail.count >= 2 || qPhone.count >= 4 else { return [] }
        return Array(members.filter { member in
            if qName.count >= 2, member.name.lowercased().contains(qName) { return true }
            if qEmail.count >= 2, member.email?.lowercased().contains(qEmail) == true { return true }
            if qPhone.count >= 4, member.phone?.filter(\.isNumber).contains(qPhone) == true { return true }
            return false
        }.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                appBackground.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    avatarPicker
                        .frame(maxWidth: .infinity)
                        .padding(.top, AppSpacing.md)

                    VStack(spacing: 0) {
                        Group {
                            fieldRow("person.fill", "Name", $name)
                            divider
                            fieldRow("wrench.fill", "Specialty (e.g. Plumber)", $category)
                            divider
                            fieldRow("phone.fill", "Phone", $phone, keyboard: .phonePad)
                            divider
                            fieldRow("envelope.fill", "Email (optional)", $email, keyboard: .emailAddress)
                            divider
                            fieldRow("note.text", "Notes (optional)", $notes)
                        }
                    }
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.lg).strokeBorder(Color.primary.opacity(AppOpacity.subtleFill), lineWidth: 0.5))
                    .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)

                    if !suggestions.isEmpty {
                        suggestionsBlock
                            .padding(.horizontal, AppSpacing.xl)
                            .padding(.top, AppSpacing.md)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(.smooth(duration: 0.25), value: suggestions.map(\.id))
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
            .navigationTitle("Add Contractor").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(AppFont.subheadline).foregroundStyle(Color.accentColor)
                        .disabled(name.isEmpty || category.isEmpty || isSaving)
                }
            }
        }
    }

    /// The circular avatar well: picked photo, or a camera glyph on a clear
    /// Liquid Glass disc — the system photo picker opens on tap.
    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            Group {
                if let image = avatarImage {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
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
        .accessibilityLabel(Text("Add photo"))
    }

    // MARK: Suggestions — people already in PRVIO (IMG_8645)

    private var suggestionsBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("cont_suggestions_title")
                .font(AppFont.label)
                .foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                .padding(.leading, AppSpacing.xxs)
            ForEach(suggestions) { member in
                suggestionRow(member)
            }
        }
    }

    /// One tap fills the form from the member's real profile — name always,
    /// email/phone only when the account actually has them.
    private func suggestionRow(_ member: FamilyMember) -> some View {
        Button {
            HapticFeedback.success()
            name = member.name
            if let e = member.email, !e.isEmpty { email = e }
            if let p = member.phone, !p.isEmpty { phone = p }
        } label: {
            HStack(spacing: AppSpacing.md) {
                MemberAvatar(member: member, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(verbatim: member.name)
                            .font(AppFont.scaled(14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        PRVIOAccountBadge()
                    }
                    if let detail = [member.email, member.phone]
                        .compactMap({ $0 }).first(where: { !$0.isEmpty }) {
                        Text(verbatim: detail)
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: AppSpacing.sm)
                Image(systemName: "arrow.down.left.circle.fill")
                    .font(AppFont.scaled(18))
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm + 2)
            .contentShape(Rectangle())
            .liquidGlass(cornerRadius: AppRadius.lg)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("cont_suggestion_hint"))
    }

    private func fieldRow(_ icon: String, _ placeholder: LocalizedStringKey, _ binding: Binding<String>, keyboard: UIKeyboardType = .default) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(AppFont.scaled(14)).foregroundStyle(Color.accentColor).frame(width: 28)
            TextField(placeholder, text: binding).font(AppFont.scaled(15)).foregroundStyle(.primary).tint(.accentColor).keyboardType(keyboard)
        }.padding(.horizontal, AppSpacing.lg).padding(.vertical, 13)
    }
    private var divider: some View { Rectangle().fill(Color.primary.opacity(0.05)).frame(height: 0.5).padding(.leading, 52) }

    private func save() async {
        guard let pid = propertyId else { dismiss(); return }
        isSaving = true
        defer { isSaving = false }
        // Optional avatar first — the same public documents-bucket pattern
        // as every other property image (fresh name per upload).
        var photoUrl: String? = nil
        if let image = avatarImage, let data = image.uploadJPEG(quality: 0.82) {
            let path = "contractors/\(pid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            photoUrl = try? await SignedStorage.uploadPublicImage(data, path: path)
        }
        let c = NewContractor(
            propertyId: pid,
            createdBy: userId,
            name: name,
            category: category,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            notes: notes.isEmpty ? nil : notes,
            isPreferred: false,
            photoUrl: photoUrl
        )
        try? await service.add(c)
        HapticFeedback.success()
        dismiss()
    }
}
