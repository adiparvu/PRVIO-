import SwiftUI
import PhotosUI

// MARK: - Damage claims — list, detail, form
//
// "Asistent de daune": every incident from draft to resolution. The detail
// page moves the claim along its life (native Menu), shows the evidence
// photos, and exports the insurer-ready PDF report. Adults write; the
// household reads (mirrors RLS).

struct InsuranceClaimsView: View {
    @Environment(InsuranceClaimService.self) private var service
    @Environment(PropertyService.self) private var propertyService

    @State private var showAdd = false

    private var canWrite: Bool { propertyService.hasWriteAccess }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if service.claims.isEmpty {
                    if canWrite {
                        EmptyStateView(icon: "shield.lefthalf.filled",
                                       title: "claims_empty_title",
                                       message: "claims_empty_message",
                                       actionLabel: "claim_add") { showAdd = true }
                            .padding(.top, AppSpacing.xxl)
                    } else {
                        EmptyStateView(icon: "shield.lefthalf.filled",
                                       title: "claims_empty_title",
                                       message: "claims_empty_message")
                            .padding(.top, AppSpacing.xxl)
                    }
                } else {
                    VStack(spacing: 0) {
                        ForEach(service.sorted) { claim in
                            claimRow(claim)
                            if claim.id != service.sorted.last?.id {
                                FormDivider()
                            }
                        }
                    }
                    .padding(.vertical, AppSpacing.xs)
                    .liquidGlass(cornerRadius: AppRadius.xl)
                }
                Spacer(minLength: 80)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.md)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("claims_title")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if canWrite {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true; HapticFeedback.impact(.medium) } label: {
                        Image(systemName: "plus")
                            .font(AppFont.scaled(17, weight: .semibold))
                            .foregroundStyle(Color.glassInk)
                    }
                    .accessibilityLabel(Text("claim_add"))
                }
            }
        }
        .sheet(isPresented: $showAdd) { ClaimFormSheet() }
        .task { await service.loadIfNeeded() }
        .refreshable { await service.load() }
    }

    private func claimRow(_ claim: InsuranceClaim) -> some View {
        NavigationLink {
            ClaimDetailView(claimId: claim.id)
        } label: {
            HStack(spacing: AppSpacing.md) {
                ZStack {
                    Circle().fill(claim.statusKind.tint.opacity(AppOpacity.tintedFill))
                    Image(systemName: claim.statusKind.icon)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(claim.statusKind.tint)
                }
                .frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: claim.title)
                        .font(AppFont.scaled(15, weight: .semibold))
                        .foregroundStyle(.primary).lineLimit(1)
                    HStack(spacing: AppSpacing.xs) {
                        Text(claim.statusKind.label)
                            .foregroundStyle(claim.statusKind.tint)
                        if let d = claim.date {
                            Text(verbatim: "· \(d.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(Color.secondaryTextColor)
                        }
                    }
                    .font(AppFont.scaled(12))
                }
                Spacer()
                if let amount = claim.approvedAmount ?? claim.claimedAmount {
                    Text(verbatim: CurrencyService.money(amount, code: claim.currency, whole: true))
                        .font(AppFont.scaled(13, weight: .semibold))
                        .foregroundStyle(claim.approvedAmount != nil
                            ? Color.brandSuccess : Color.secondaryTextColor)
                }
                Image(systemName: "chevron.right")
                    .font(AppFont.scaled(13, weight: .semibold))
                    .foregroundStyle(Color.secondaryTextColor)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: Detail

struct ClaimDetailView: View {
    @Environment(InsuranceClaimService.self) private var service
    @Environment(PropertyService.self) private var propertyService
    @Environment(\.dismiss) private var dismiss

    let claimId: UUID
    @State private var showEdit = false
    @State private var isExporting = false
    @State private var approvedInput = ""
    @State private var askApproved = false

    private var claim: InsuranceClaim? { service.claims.first { $0.id == claimId } }
    private var canWrite: Bool { propertyService.hasWriteAccess }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if let claim {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    statusHeader(claim)
                    factsCard(claim)
                    if let description = claim.description, !description.isEmpty {
                        Text(verbatim: description)
                            .font(AppFont.body)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.lg)
                            .liquidGlass(cornerRadius: AppRadius.xl)
                    }
                    if !claim.photoUrls.isEmpty {
                        photosGrid(claim)
                    }
                    exportButton(claim)
                    Spacer(minLength: 80)
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.md)
            }
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle(Text(verbatim: claim?.title ?? ""))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canWrite, let claim {
                ToolbarItem(placement: .pageMenu) {
                    Menu {
                        Menu {
                            ForEach(ClaimStatus.allCases) { status in
                                Button {
                                    if status == .resolved {
                                        askApproved = true
                                    } else {
                                        Task { try? await service.setStatus(claim, to: status) }
                                    }
                                } label: {
                                    Label(status.label, systemImage: status.icon)
                                }
                            }
                        } label: {
                            Label("claim_status", systemImage: claim.statusKind.icon)
                        }
                        Button { showEdit = true } label: {
                            Label("claim_edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            HapticFeedback.warning()
                            Task {
                                await service.delete(claim)
                                dismiss()
                            }
                        } label: { Label("Remove", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(AppFont.scaled(17, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let claim { ClaimFormSheet(editing: claim) }
        }
        .alert("claim_approved_prompt", isPresented: $askApproved) {
            TextField("0", text: $approvedInput)
                .keyboardType(.decimalPad)
            Button("claim_resolve_confirm") {
                guard let claim else { return }
                let amount = Double(approvedInput.replacingOccurrences(of: ",", with: "."))
                Task { try? await service.setStatus(claim, to: .resolved, approvedAmount: amount) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statusHeader(_ claim: InsuranceClaim) -> some View {
        HStack(spacing: AppSpacing.md) {
            ZStack {
                Circle().fill(claim.statusKind.tint.opacity(AppOpacity.tintedFill))
                Image(systemName: claim.statusKind.icon)
                    .font(AppFont.scaled(22, weight: .semibold))
                    .foregroundStyle(claim.statusKind.tint)
            }
            .frame(width: 52, height: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(claim.statusKind.label)
                    .font(AppFont.scaled(17, weight: .bold))
                    .foregroundStyle(claim.statusKind.tint)
                if let d = claim.date {
                    Text(verbatim: d.formatted(date: .long, time: .omitted))
                        .font(AppFont.scaled(13))
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            Spacer()
        }
    }

    private func factsCard(_ claim: InsuranceClaim) -> some View {
        VStack(spacing: 0) {
            if let insurer = claim.insurer, !insurer.isEmpty {
                factRow(icon: "building.2.fill", label: "claim_insurer", value: insurer)
                FormDivider()
            }
            if let policy = claim.policyNumber, !policy.isEmpty {
                factRow(icon: "doc.text.fill", label: "claim_policy_number", value: policy)
                FormDivider()
            }
            if let amount = claim.claimedAmount {
                factRow(icon: "banknote.fill", label: "claim_claimed_amount",
                        value: CurrencyService.money(amount, code: claim.currency))
            }
            if let amount = claim.approvedAmount {
                FormDivider()
                factRow(icon: "checkmark.seal.fill", label: "claim_approved_amount",
                        value: CurrencyService.money(amount, code: claim.currency),
                        tint: .brandSuccess)
            }
        }
        .padding(.vertical, AppSpacing.xs)
        .liquidGlass(cornerRadius: AppRadius.xl)
    }

    private func factRow(icon: String, label: LocalizedStringKey, value: String,
                         tint: Color = .brandPrimaryBlue) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: icon)
                .font(AppFont.scaled(14))
                .foregroundStyle(tint)
                .frame(width: 26)
            Text(label).font(AppFont.body).foregroundStyle(.primary)
            Spacer()
            Text(verbatim: value)
                .font(AppFont.scaled(14, weight: .semibold))
                .foregroundStyle(tint == .brandSuccess ? tint : .primary)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.sm)
    }

    private func photosGrid(_ claim: InsuranceClaim) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm),
                                 count: 3),
                  spacing: AppSpacing.sm) {
            ForEach(claim.photoUrls, id: \.self) { urlString in
                StorageImage(source: urlString, targetSize: 160) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    default:
                        Color.subtleFill
                    }
                }
                .frame(height: 100)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.md))
            }
        }
    }

    private func exportButton(_ claim: InsuranceClaim) -> some View {
        Button {
            guard !isExporting else { return }
            isExporting = true
            HapticFeedback.impact(.medium)
            Task {
                defer { isExporting = false }
                guard let url = await ClaimReport.makePDF(
                    claim: claim, property: propertyService.primary) else { return }
                SystemActions.share([url])
            }
        } label: {
            HStack {
                Spacer()
                if isExporting {
                    ProgressView().tint(.white)
                } else {
                    Label("claim_export_pdf", systemImage: "square.and.arrow.up")
                        .font(AppFont.scaled(15, weight: .semibold))
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.md)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

// MARK: Add / edit sheet

struct ClaimFormSheet: View {
    @Environment(InsuranceClaimService.self) private var service
    @Environment(AppSettings.self) private var appSettings
    @Environment(\.dismiss) private var dismiss

    var editing: InsuranceClaim?

    @State private var title = ""
    @State private var incidentDate = Date()
    @State private var insurer = ""
    @State private var policyNumber = ""
    @State private var claimedAmount = ""
    @State private var descriptionText = ""
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var newPhotos: [Data] = []
    @State private var existingUrls: [String] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var hydrated = false

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        FormScaffold(title: editing == nil ? "claim_add" : "claim_edit",
                     canSave: canSave, isSaving: isSaving, error: $error, onSave: save) {
            FormGroup {
                FormRow(icon: "shield.lefthalf.filled", tint: .brandWarning) {
                    TextField("claim_title_ph", text: $title).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "calendar", tint: .brandWarning) {
                    DatePicker("claim_incident_date", selection: $incidentDate,
                               displayedComponents: .date)
                        .font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "building.2.fill", tint: .brandWarning) {
                    TextField("claim_insurer", text: $insurer).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "doc.text.fill", tint: .brandWarning) {
                    TextField("claim_policy_number", text: $policyNumber).font(AppFont.body)
                }
                FormDivider()
                FormRow(icon: "banknote.fill", tint: .brandWarning) {
                    Text("claim_claimed_amount").font(AppFont.body).foregroundStyle(.primary)
                    Spacer()
                    TextField("0", text: $claimedAmount).keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(AppFont.scaled(18, weight: .semibold))
                    Text(verbatim: editing?.currency ?? appSettings.preferredCurrency)
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }

            FormGroup(title: "claim_description_title") {
                TextEditor(text: $descriptionText)
                    .font(AppFont.body)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.xs)
            }

            FormGroup {
                FormRow(icon: "camera.fill", tint: .brandWarning) {
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6,
                                 matching: .images) {
                        HStack {
                            Text(photoLine)
                                .font(AppFont.body)
                                .foregroundStyle(newPhotos.isEmpty && existingUrls.isEmpty
                                    ? Color.accentColor : .primary)
                            Spacer()
                            if !newPhotos.isEmpty || !existingUrls.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.brandSuccess)
                            }
                        }
                    }
                }
            }
        }
        .onAppear(perform: hydrate)
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var loaded: [Data] = []
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        loaded.append(data)
                    }
                }
                newPhotos = loaded
            }
        }
    }

    private var photoLine: String {
        let count = existingUrls.count + newPhotos.count
        return count == 0
            ? String(localized: "claim_add_photos")
            : String(format: String(localized: "claim_photos_fmt"), count)
    }

    private func hydrate() {
        guard let claim = editing, !hydrated else { return }
        hydrated = true
        title = claim.title
        incidentDate = claim.date ?? Date()
        insurer = claim.insurer ?? ""
        policyNumber = claim.policyNumber ?? ""
        if let amount = claim.claimedAmount {
            claimedAmount = amount == amount.rounded() ? String(Int(amount)) : String(amount)
        }
        descriptionText = claim.description ?? ""
        existingUrls = claim.photoUrls
    }

    private func save() {
        isSaving = true
        Task {
            do {
                let uploaded = try await service.uploadPhotos(newPhotos)
                let payload = InsuranceClaimService.ClaimPayload(
                    title: title.trimmingCharacters(in: .whitespaces),
                    description: descriptionText.isEmpty ? nil : descriptionText,
                    incidentDate: AppDate.dayString(from: incidentDate),
                    insurer: insurer.isEmpty ? nil : insurer,
                    policyNumber: policyNumber.isEmpty ? nil : policyNumber,
                    claimedAmount: Double(claimedAmount.replacingOccurrences(of: ",", with: ".")),
                    currency: editing?.currency ?? appSettings.preferredCurrency,
                    photoUrls: existingUrls + uploaded)
                if let claim = editing {
                    try await service.update(claim.id, payload: payload)
                } else {
                    try await service.add(payload)
                }
                HapticFeedback.success()
                dismiss()
            } catch {
                self.error = error.recordableDescription
                isSaving = false
            }
        }
    }
}
