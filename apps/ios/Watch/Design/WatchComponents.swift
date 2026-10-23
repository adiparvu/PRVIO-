import SwiftUI

// MARK: - Reusable wrist components
//
// The building blocks every page composes. They take plain values (no
// store access) so they stay cheap to re-render and trivially previewable;
// the caller owns navigation and actions.

// MARK: - WatchCard

/// The soft rounded card every glance module sits in. Content, not chrome:
/// a tinted fill, never Liquid Glass.
struct WatchCard<Content: View>: View {
    var tint: Color = WatchTheme.Tint.neutral
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(WatchTheme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WatchTheme.cardFill(tint),
                        in: RoundedRectangle(cornerRadius: WatchTheme.Radius.card, style: .continuous))
    }
}

// MARK: - MetricTile

/// One number of the Today 2×2 grid. Display only — wrap it in a Button or
/// NavigationLink (`.buttonStyle(.plain)`) when it should act.
struct MetricTile: View {
    let count: Int
    let titleKey: LocalizedStringKey
    let systemImage: String
    let tint: Color
    var isUrgent: Bool = false

    private var accent: Color { isUrgent ? WatchTheme.Tint.critical : tint }

    var body: some View {
        WatchCard(tint: accent) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                HStack(spacing: WatchTheme.Spacing.xs) {
                    Image(systemName: systemImage)
                        .font(WatchTheme.Typography.glyph)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(accent)
                    if isUrgent {
                        Circle()
                            .fill(WatchTheme.Tint.critical)
                            .frame(width: WatchTheme.Size.urgentDot, height: WatchTheme.Size.urgentDot)
                            .accessibilityHidden(true)
                    }
                    Spacer(minLength: 0)
                }
                Text(verbatim: "\(count)")
                    .font(WatchTheme.Typography.metric)
                    .contentTransition(.numericText())
                Text(titleKey)
                    .font(WatchTheme.Typography.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - CountBadge

/// A capsule count (capped at 99) — tinted, red when urgent.
struct CountBadge: View {
    let count: Int
    var tint: Color = WatchTheme.Tint.messages
    var isUrgent: Bool = false

    var body: some View {
        Text(verbatim: "\(min(count, 99))")
            .font(WatchTheme.Typography.badge)
            .foregroundStyle(.white)
            .padding(.horizontal, WatchTheme.Spacing.xs + 1)
            .padding(.vertical, 1)
            .background(isUrgent ? WatchTheme.Tint.critical : tint, in: Capsule())
            .contentTransition(.numericText())
    }
}

// MARK: - ModuleRow

/// A Home hub row: tinted glyph, title, optional badge. The caller wraps it
/// in a NavigationLink.
struct ModuleRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let tint: Color
    var badge: WatchBadge? = nil

    init(titleKey: LocalizedStringKey, systemImage: String, tint: Color, badge: WatchBadge? = nil) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
        self.badge = badge
    }

    /// The row for a hub module, badged from the payload.
    init(module: WatchModule, payload: WatchPayload) {
        self.init(titleKey: module.titleKey, systemImage: module.systemImage,
                  tint: module.tint, badge: module.badge(in: payload))
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(WatchTheme.Typography.glyph)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .background(tint.opacity(WatchTheme.Opacity.glyphFill), in: Circle())
            Text(titleKey)
                .font(WatchTheme.Typography.rowTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            if let badge {
                CountBadge(count: badge.count, tint: tint, isUrgent: badge.isUrgent)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - HealthRing

/// The property's health as a ring that fills on arrival (instantly under
/// Reduce Motion).
struct HealthRing: View {
    let score: Int
    var size: CGFloat = WatchTheme.Size.healthRing

    @State private var shown: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Gauge(value: shown, in: 0...100) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text(verbatim: "\(Int(shown))")
                .font(Font.system(.body, design: .rounded).weight(.bold))
                .contentTransition(.numericText())
        }
        .gaugeStyle(.accessoryCircular)
        .tint(Gradient(colors: [WatchTheme.scoreColor(score).opacity(0.55),
                                WatchTheme.scoreColor(score)]))
        .frame(width: size, height: size)
        .onAppear { fill() }
        .onChange(of: score) { fill() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("watch_health"))
        .accessibilityValue(Text(verbatim: "\(score)%"))
    }

    private func fill() {
        let target = Double(min(max(score, 0), 100))
        if reduceMotion {
            shown = target
        } else {
            withAnimation(WatchTheme.Motion.ringFill) { shown = target }
        }
    }
}

// MARK: - AllClearView / EmptyStateView

/// A page with nothing left to do — calm, not empty.
struct AllClearView: View {
    let systemImage: String
    var messageKey: LocalizedStringKey = "watch_all_good"

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(messageKey)
                .font(WatchTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A titled empty / waiting state with an optional explanation.
struct EmptyStateView: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    var messageKey: LocalizedStringKey? = nil

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.m) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            Text(titleKey)
                .font(WatchTheme.Typography.hero)
                .multilineTextAlignment(.center)
            if let messageKey {
                Text(messageKey)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ActionGlyphButton

/// The leading act-on-the-spot glyph of a list row: tap → the glyph fills
/// and bounces → a beat later the action runs (immediately under Reduce
/// Motion). One-shot by default (a second tap is ignored while the row
/// leaves); `isRepeatable` acts on every tap with no delay (pantry
/// consume). Never a primary double-tap action — rows live in scrolling
/// lists inside the vertical pager, where double tap belongs to the system.
struct ActionGlyphButton: View {
    let systemImage: String
    let actedSystemImage: String
    let tint: Color
    let labelKey: LocalizedStringKey
    var isRepeatable: Bool = false
    let action: () -> Void

    @State private var didAct = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(systemImage: String, actedSystemImage: String, tint: Color,
         labelKey: LocalizedStringKey, isRepeatable: Bool = false,
         action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.actedSystemImage = actedSystemImage
        self.tint = tint
        self.labelKey = labelKey
        self.isRepeatable = isRepeatable
        self.action = action
    }

    var body: some View {
        Button(action: tap) {
            Image(systemName: didAct ? actedSystemImage : systemImage)
                .font(.body.weight(didAct ? .semibold : .light))
                .foregroundStyle(didAct || isRepeatable ? tint : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .frame(minWidth: WatchTheme.Size.rowIcon, minHeight: WatchTheme.Size.rowIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(labelKey))
    }

    private func tap() {
        if isRepeatable {
            taps += 1
            withAnimation(WatchTheme.Motion.snappy) { action() }
            return
        }
        guard !didAct else { return }
        didAct = true
        taps += 1
        if reduceMotion {
            action()
            didAct = false
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay)
            withAnimation(WatchTheme.Motion.snappy) { action() }
            // A row that stays (its item changed state rather than leaving)
            // returns to idle so it never looks stuck.
            try? await Task.sleep(for: .seconds(1))
            didAct = false
        }
    }
}

// MARK: - SectionHeader

/// A section title: naked text — no chip, capsule, band or background.
struct SectionHeader: View {
    let titleKey: LocalizedStringKey

    init(_ titleKey: LocalizedStringKey) {
        self.titleKey = titleKey
    }

    var body: some View {
        Text(titleKey)
            .font(WatchTheme.Typography.sectionHeader)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - SessionClockText

/// The live work-session readout. Computed elapsed (pauses excluded, a
/// pause truly freezes it) rather than a wall-clock timer text. In Always
/// On the timeline drops to minute cadence, so the readout drops to h:mm
/// instead of showing a stale seconds digit.
struct SessionClockText: View {
    let session: WatchWorkSession
    var font: Font = WatchTheme.Typography.clockInline

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = session.elapsed(at: context.date)
            Text(verbatim: context.cadence >= .minutes
                 ? elapsed.watchClockMinutesText
                 : elapsed.watchClockText)
                .font(font)
                .monospacedDigit()
                .foregroundStyle(session.isPaused ? WatchTheme.Tint.warning : Color.primary)
        }
    }
}

extension TimeInterval {
    /// "1:20:05" past an hour, else "20:05".
    var watchClockText: String {
        let total = Int(Swift.max(0, self))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    /// "1:20" / "0:20" — h:mm, for the Always On cadence.
    var watchClockMinutesText: String {
        let total = Int(Swift.max(0, self))
        return String(format: "%d:%02d", total / 3600, (total % 3600) / 60)
    }
}

// MARK: - Row background + entrance

extension View {
    /// The standard tinted list-row background (use inside `List`).
    func watchRowBackground(_ tint: Color) -> some View {
        listRowBackground(
            RoundedRectangle(cornerRadius: WatchTheme.Radius.row, style: .continuous)
                .fill(WatchTheme.cardFill(tint))
        )
    }

    /// Staggered card entrance; sits out entirely under Reduce Motion.
    func watchEntrance(_ index: Int) -> some View {
        modifier(WatchEntrance(index: index))
    }
}

private struct WatchEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : WatchTheme.Spacing.l)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(WatchTheme.Motion.entrance
                    .delay(Double(index) * WatchTheme.Motion.entranceStagger)) {
                    shown = true
                }
            }
    }
}
