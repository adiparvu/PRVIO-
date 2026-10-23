import SwiftUI

// MARK: - Delivery detail with live tracking timeline
//
// Renders purely from our own normalized fields (live_status, checkpoints, ETA)
// written by the tracking webhook — it never knows which aggregator produced
// them, so the provider can change without touching this screen.
//
// The page is a parcel dossier: hero identity, journey stepper, every known
// reference (the identification heart — copyable AWBs and order numbers),
// live tracking, the checkpoint timeline, plain details, and the shipping
// emails the importer matched to this parcel.

struct DeliveryDetailView: View {
    @Environment(DeliveryService.self) private var deliveryService
    @Environment(\.dismiss) private var dismiss

    private let deliveryId: UUID
    private let initial: Delivery
    private let onEdit: () -> Void

    init(delivery: Delivery, onEdit: @escaping () -> Void) {
        self.deliveryId = delivery.id
        self.initial = delivery
        self.onEdit = onEdit
    }

    /// Always read the freshest copy from the service so live updates reflect.
    private var delivery: Delivery {
        deliveryService.deliveries.first { $0.id == deliveryId } ?? initial
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: AppSpacing.xl) {
                hero
                journeyCard
                referencesCard
                liveStatusCard
                timelineCard
                detailsCard
                sourceEmailsCard
                actions
                Spacer(minLength: 100)
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.top, AppSpacing.sm)
        }
        .background(appBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // One-circle law: every action for this parcel lives in the single
            // system Menu — edit, copy, complete, and delete at the end.
            ToolbarItem(placement: .pageMenu) {
                Menu {
                    Button { onEdit() } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    if let tn = delivery.trackingNumber, !tn.isEmpty {
                        Button {
                            UIPasteboard.general.string = tn
                            HapticFeedback.selection()
                        } label: {
                            Label("Copy tracking", systemImage: "doc.on.doc")
                        }
                    }
                    if delivery.isActive {
                        Button {
                            HapticFeedback.success()
                            Task { await deliveryService.markDelivered(delivery) }
                        } label: {
                            Label("Mark as delivered", systemImage: "checkmark.seal.fill")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        HapticFeedback.warning()
                        Task { await deliveryService.delete(delivery); dismiss() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(AppFont.scaled(17, weight: .semibold))
                        .foregroundStyle(Color.glassInk)
                }
                .accessibilityLabel(Text("More"))
            }
        }
        .refreshable { await refresh() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: AppSpacing.md) {
            BrandLogoCircle(
                domain: delivery.brandDomain,
                monogram: delivery.brandName,
                fallbackIcon: delivery.statusIcon,
                tint: delivery.statusColor,
                size: 76)
            VStack(spacing: 4) {
                Text(delivery.description)
                    .font(AppFont.title2)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                if let origin = originLine {
                    Text(origin)
                        .font(AppFont.subheadline)
                        .foregroundStyle(Color.secondaryTextColor)
                }
            }
            statusPill
            if delivery.isActive, let eta = etaText {
                Text(String(format: String(localized: "deliv_arrives_fmt"), eta))
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.secondaryTextColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, AppSpacing.sm)
    }

    /// "merchant · carrier" — whichever the importer / user captured.
    private var originLine: String? {
        let parts = [delivery.merchant, delivery.carrier]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var statusPill: some View {
        // Naked colored text — no capsule chrome (user-decreed, the same law
        // as the list row's status label).
        Text(verbatim: liveStatusLabel)
            .font(AppFont.captionEmphasis)
            .foregroundStyle(delivery.statusColor)
    }

    // MARK: - Journey card (progress + milestone labels)

    private var journeyCard: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("deliv_journey_title")
                    .font(AppFont.captionStrong).foregroundStyle(.secondary)
                DeliveryProgressBar(delivery: delivery)
                milestoneLabels
            }
        }
    }

    /// The four journey milestones under the bar — the current stage carries
    /// the status color, past stages read secondary, future ones fade.
    private var milestoneLabels: some View {
        let stage = delivery.progressStage
        let exception = delivery.hasException
        let names: [LocalizedStringKey] = ["Info received", "In transit",
                                           "Out for delivery", "Delivered"]
        return HStack(alignment: .top, spacing: 4) {
            ForEach(0..<Delivery.journeyStages, id: \.self) { i in
                Text(names[i])
                    .font(AppFont.scaled(10, weight: i == stage ? .semibold : .regular))
                    .foregroundStyle(milestoneColor(i, stage: stage, exception: exception))
                    .multilineTextAlignment(i == 0 ? .leading : (i == names.count - 1 ? .trailing : .center))
                    .frame(maxWidth: .infinity,
                           alignment: i == 0 ? .leading : (i == names.count - 1 ? .trailing : .center))
            }
        }
    }

    private func milestoneColor(_ index: Int, stage: Int, exception: Bool) -> Color {
        if exception { return index == 0 ? Color.brandDanger : Color.primary.opacity(AppOpacity.disabled) }
        if index == stage { return delivery.statusColor }
        return index < stage ? Color.secondaryTextColor : Color.primary.opacity(AppOpacity.disabled)
    }

    // MARK: - References card (the identification heart)

    @ViewBuilder
    private var referencesCard: some View {
        let refs = delivery.allReferences
        if !refs.isEmpty {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("deliv_refs_title")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    ForEach(Array(refs.enumerated()), id: \.element) { idx, ref in
                        referenceRow(ref, isPrimary: idx == 0)
                    }
                }
            }
        }
    }

    private func referenceRow(_ ref: String, isPrimary: Bool) -> some View {
        HStack(spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Delivery.referenceKind(ref).label)
                    .font(AppFont.caption2)
                    .foregroundStyle(Color.secondaryTextColor)
                Text(ref)
                    .font(AppFont.scaled(isPrimary ? 15 : 13,
                                         weight: isPrimary ? .semibold : .regular,
                                         design: .monospaced))
                    .foregroundStyle(isPrimary ? .primary : Color.secondaryTextColor)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button {
                UIPasteboard.general.string = ref
                HapticFeedback.selection()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.secondaryTextColor)
                    .frame(width: 32, height: 32)
                    .background(Color.primary.opacity(AppOpacity.subtleFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("deliv_ref_copy"))
        }
    }

    // MARK: - Live status card

    private var liveStatusCard: some View {
        GlassCard(padding: AppSpacing.lg) {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                HStack(spacing: 8) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(AppFont.footnote).foregroundStyle(Color.brandSuccess)
                    Text("Live tracking").font(AppFont.captionStrong).foregroundStyle(.secondary)
                    Spacer()
                    if delivery.isLiveTracked {
                        Text(verbatim: liveStatusLabel)
                            .font(AppFont.captionEmphasis).foregroundStyle(delivery.statusColor)
                    }
                }

                if delivery.isLiveTracked {
                    if let eta = etaText {
                        infoRow(icon: "clock.badge.checkmark", label: "Estimated delivery", value: eta)
                    }
                    if let last = lastUpdateText {
                        infoRow(icon: "arrow.triangle.2.circlepath", label: "Last update", value: last)
                    }
                    if delivery.liveCheckpoints.isEmpty {
                        Text("Waiting for the courier's first scan…")
                            .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor)
                    }
                } else {
                    Text(delivery.trackingNumber?.isEmpty == false
                         ? "Live tracking is starting — check back shortly."
                         : "Add a tracking number to follow this parcel live.")
                        .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor)
                }
            }
        }
    }

    private func infoRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor).frame(width: 20)
            Text(label).font(AppFont.subheadline).foregroundStyle(.primary)
            Spacer()
            Text(value).font(AppFont.subheadline).foregroundStyle(Color.secondaryTextColor)
        }
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timelineCard: some View {
        let events = delivery.liveCheckpoints
        if !events.isEmpty {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Tracking history")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                        .padding(.bottom, AppSpacing.md)

                    ForEach(Array(events.enumerated()), id: \.element.id) { idx, cp in
                        TimelineRow(
                            checkpoint: cp,
                            isFirst: idx == 0,
                            isLast: idx == events.count - 1,
                            tint: idx == 0 ? delivery.statusColor : Color.secondaryTextColor
                        )
                    }
                }
            }
        }
    }

    // MARK: - Details card

    @ViewBuilder
    private var detailsCard: some View {
        let expected = delivery.expectedDisplay
        let created = dayText(delivery.createdAt)
        let received = dayText(delivery.receivedAt)
        let notes = delivery.notes.flatMap { $0.isEmpty ? nil : $0 }
        if expected != nil || created != nil || received != nil || notes != nil {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("Details")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    if let expected {
                        infoRow(icon: "calendar", label: "Expected", value: expected)
                    }
                    if let created {
                        infoRow(icon: "plus.circle", label: "deliv_created_label", value: created)
                    }
                    if let received {
                        infoRow(icon: "shippingbox.and.arrow.backward", label: "deliv_received_label", value: received)
                    }
                    if let notes {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Image(systemName: "note.text")
                                    .font(AppFont.footnote).foregroundStyle(Color.secondaryTextColor).frame(width: 20)
                                Text("Notes").font(AppFont.subheadline).foregroundStyle(.primary)
                            }
                            Text(notes)
                                .font(AppFont.footnote)
                                .foregroundStyle(Color.secondaryTextColor)
                                .padding(.leading, 30)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Source emails card

    @ViewBuilder
    private var sourceEmailsCard: some View {
        let emails = sortedSourceEmails
        if !emails.isEmpty {
            GlassCard(padding: AppSpacing.lg) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Text("deliv_emails_title")
                        .font(AppFont.captionStrong).foregroundStyle(.secondary)
                    ForEach(emails) { email in
                        sourceEmailRow(email)
                    }
                }
            }
        }
    }

    /// Newest first — the latest shipping email is the most relevant.
    private var sortedSourceEmails: [DeliverySourceEmail] {
        (delivery.sourceEmails ?? []).sorted {
            let a = $0.at.flatMap { ISODate.date(from: $0) } ?? .distantPast
            let b = $1.at.flatMap { ISODate.date(from: $0) } ?? .distantPast
            return a > b
        }
    }

    private func sourceEmailRow(_ email: DeliverySourceEmail) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "envelope")
                .font(AppFont.footnote)
                .foregroundStyle(Color.secondaryTextColor)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                if let subject = email.subject, !subject.isEmpty {
                    Text(subject)
                        .font(AppFont.scaled(14, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                let meta = [email.from, timestampText(email.at)]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                if !meta.isEmpty {
                    Text(meta.joined(separator: " · "))
                        .font(AppFont.scaled(12))
                        .foregroundStyle(Color.secondaryTextColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if delivery.isActive {
            GlassWideButton(icon: "checkmark.circle.fill", label: "Mark as delivered") {
                HapticFeedback.success()
                Task { await deliveryService.markDelivered(delivery) }
            }
        }
    }

    // MARK: - Helpers

    private func refresh() async {
        await deliveryService.reload()
    }

    /// One source of truth: the model's localized live-status phrase, falling
    /// back to the manual status label when the parcel isn't live-tracked.
    private var liveStatusLabel: String {
        delivery.liveStatusLabel ?? delivery.statusLabel
    }

    private var etaText: String? {
        guard let eta = delivery.estimatedDelivery, let d = ISODate.date(from: eta) else {
            return delivery.expectedDisplay
        }
        if Calendar.current.isDateInToday(d) { return String(localized: "Today") }
        if Calendar.current.isDateInTomorrow(d) { return String(localized: "Tomorrow") }
        return AppDate.monthDay.string(from: d)
    }

    private var lastUpdateText: String? {
        timestampText(delivery.lastEventAt)
    }

    /// "6 Jul, 14:30" from any server timestamp, nil when absent/unparseable.
    private func timestampText(_ ts: String?) -> String? {
        guard let ts, let d = ISODate.date(from: ts) else { return nil }
        return AppDate.monthDayTime.string(from: d)
    }

    /// "6 Jul 2026" from a server timestamp or plain day — created/received rows.
    private func dayText(_ ts: String?) -> String? {
        guard let ts else { return nil }
        guard let d = ISODate.date(from: ts) ?? AppDate.day(from: ts) else { return nil }
        return AppDate.monthDayYear.string(from: d)
    }
}

// MARK: - Timeline row (dot + connecting rail + event)

private struct TimelineRow: View {
    let checkpoint: TrackingCheckpoint
    let isFirst: Bool
    let isLast: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(tint)
                    .frame(width: isFirst ? 12 : 9, height: isFirst ? 12 : 9)
                    .overlay(
                        Circle().stroke(tint.opacity(0.25), lineWidth: isFirst ? 4 : 0)
                    )
                    .padding(.top, 3)
                if !isLast {
                    Rectangle()
                        .fill(Color.primary.opacity(AppOpacity.hairline))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(checkpoint.message?.isEmpty == false ? checkpoint.message! : (checkpoint.status ?? ""))
                    .font(AppFont.scaled(14, weight: isFirst ? .semibold : .regular))
                    .foregroundStyle(isFirst ? .primary : Color.secondaryTextColor)
                if let loc = checkpoint.location, !loc.isEmpty {
                    Text(loc).font(AppFont.scaled(12)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
                if let t = timeText {
                    Text(t).font(AppFont.scaled(11)).foregroundStyle(Color.primary.opacity(AppOpacity.disabled))
                }
            }
            .padding(.bottom, isLast ? 0 : AppSpacing.base)
            Spacer(minLength: 0)
        }
    }

    private var timeText: String? {
        guard let d = checkpoint.date else { return checkpoint.time }
        return AppDate.monthDayTime.string(from: d)
    }
}
