import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - IslandKit
//
// The shared design system for every PRVIO Live Activity: one icon disc, one
// metric style, one progress bar, one lock-screen card. Each activity in
// LiveActivityViews.swift composes these instead of hand-building its own
// layout — the five originals had drifted into five slightly different
// designs with hardcoded colors and frozen font sizes.

// MARK: Preference gates
//
// LiveActivityPrefs reads the app-group suite, so the user's choices in
// Settings › Live Activities drive the REAL activity rendering. Views are
// re-evaluated on every content update, so a settings change applies from
// the next update. Gates are keyed by the canonical kind — no raw strings.
enum LA {
    static func lockDetails(_ k: LiveActivityKind) -> Bool { LiveActivityPrefs.showOnLockScreen(for: k.rawValue) }
    static func island(_ k: LiveActivityKind) -> Bool { LiveActivityPrefs.showDynamicIsland(for: k.rawValue) }
    static func progress(_ k: LiveActivityKind) -> Bool { LiveActivityPrefs.showProgress(for: k.rawValue) }
    static func eta(_ k: LiveActivityKind) -> Bool { LiveActivityPrefs.showETA(for: k.rawValue) }
    static func property(_ k: LiveActivityKind) -> Bool { LiveActivityPrefs.showProperty(for: k.rawValue) }
    static func expandedDetail(_ k: LiveActivityKind) -> Bool { island(k) && LiveActivityPrefs.islandStyle(for: k.rawValue) == .detailed }
    static func expandedData(_ k: LiveActivityKind) -> Bool { island(k) && LiveActivityPrefs.islandStyle(for: k.rawValue) != .minimal }
}

enum IslandMetrics {
    /// Lock-screen leading icon disc.
    static let iconDisc: CGFloat = 44
    /// HIG: compact and minimal presentations must fit a 28pt-diameter circle
    /// wherever the Dynamic Island is limited in width (landscape iPhone).
    static let limitedWidthCircle: CGFloat = 28
    /// Progress ring stroke inside that circle — thin enough to leave the
    /// glyph its full caption size within the remaining ~23pt.
    static let limitedWidthRing: CGFloat = 2.5
}

// MARK: - State icon
//
// The kind's symbol that flips to a green checkmark on completion — with a
// crossfading symbol replace, and a one-shot bounce that Reduce Motion turns
// off. Every activity uses this in every region, so success reads the same
// everywhere.
struct IslandStateIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let kind: LiveActivityKind
    var isComplete = false
    var isProblem = false
    /// Ongoing-attention pulse without the warning symbol swap (emergency).
    var pulses = false
    /// Organic breathing while care is still owed (plant watering).
    var breathes = false
    /// Gentle periodic wiggle for "on its way" attention (delivery en route).
    var wiggles = false

    private var symbol: String {
        if isComplete { return "checkmark.circle.fill" }
        if isProblem { return "exclamationmark.triangle.fill" }
        return kind.icon
    }
    private var tint: Color {
        if isComplete { return .brandSuccess }
        if isProblem { return .brandWarning }
        return kind.color
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint)
            .contentTransition(reduceMotion ? .opacity : .symbolEffect(.replace))
            // Discrete effect keyed on the flip to complete; Reduce Motion
            // keeps the token false so the bounce never triggers.
            .symbolEffect(.bounce, options: .nonRepeating,
                          value: isComplete && !reduceMotion)
            // Ongoing attention while a problem/attention state persists.
            .symbolEffect(.pulse, options: .repeating,
                          isActive: (isProblem || pulses) && !isComplete && !reduceMotion)
            .symbolEffect(.breathe, options: .repeating,
                          isActive: breathes && !isComplete && !reduceMotion)
            // Periodic (not continuous) so it reads as a nudge, not an alarm.
            .symbolEffect(.wiggle, options: .repeat(.periodic),
                          isActive: wiggles && !isComplete && !isProblem && !reduceMotion)
    }
}

/// Lock-screen leading disc: the state icon on the kind's soft fill.
struct IslandIconDisc: View {
    let kind: LiveActivityKind
    var isComplete = false
    var breathes = false
    var wiggles = false

    var body: some View {
        ZStack {
            Circle()
                .fill((isComplete ? Color.brandSuccess : kind.color).opacity(AppOpacity.tintedFill))
                .frame(width: IslandMetrics.iconDisc, height: IslandMetrics.iconDisc)
            IslandStateIcon(kind: kind, isComplete: isComplete, breathes: breathes, wiggles: wiggles)
                .font(AppFont.title3)
        }
        .accessibilityHidden(true) // decorative — the card's text carries the state
    }
}

// MARK: - Metric
//
// Rounded numerals with the numeric-text roll — counts, percentages, ETAs.
// Three sizes: compact (island pill), expanded (island trailing), hero
// (Lock Screen right edge).
struct IslandMetric: View {
    enum Size { case compact, expanded, hero }

    let text: Text
    var tint: Color = .primary
    var size: Size = .compact

    init(_ text: Text, tint: Color = .primary, size: Size = .compact) {
        self.text = text
        self.tint = tint
        self.size = size
    }

    private var font: Font {
        switch size {
        case .compact:  return AppFont.metricSmall
        case .expanded: return AppFont.metric
        case .hero:     return AppFont.metricLarge
        }
    }

    var body: some View {
        text
            .font(font)
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .contentTransition(.numericText())
    }
}

// MARK: - Expanded leading header
//
// Icon-only when the user chose a data-light island; icon + title otherwise.
struct IslandHeader: View {
    let kind: LiveActivityKind
    let title: Text
    var isComplete = false
    /// Ongoing-attention pulse on the leading glyph (emergency), matching the
    /// compact/minimal presentations so the beacon reads "live" everywhere.
    var pulses = false
    var breathes = false
    var wiggles = false

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            IslandStateIcon(kind: kind, isComplete: isComplete, pulses: pulses,
                            breathes: breathes, wiggles: wiggles)
                .font(AppFont.captionStrong)
            if LA.expandedData(kind) {
                title
                    .font(AppFont.captionStrong)
                    .foregroundStyle(isComplete ? Color.brandSuccess : kind.color)
                    .lineLimit(1)
            }
        }
    }
}

// MARK: - Progress
struct IslandProgressBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        ProgressView(value: max(0, min(1, value)))
            .tint(tint)
            // The documented LA mechanism for custom update timing: the fill
            // eases with the brand curve instead of the system default.
            .animation(.smooth, value: value)
            .accessibilityHidden(true) // the row's text already states n of m
    }
}

/// Ordered journey in discrete segments (the Apple Store order-tracking
/// pattern): filled up to and including the current stage; a problem tints
/// the current segment to warning. HStack order mirrors under RTL.
struct IslandMilestoneBar: View {
    let stage: Int
    var total: Int = 4
    var tint: Color
    var isProblem = false

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(segmentColor(i))
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.smooth, value: stage)
        .accessibilityHidden(true) // the status text carries the stage
    }

    private func segmentColor(_ i: Int) -> Color {
        guard i <= stage else { return Color.primary.opacity(AppOpacity.subtleFill) }
        return (isProblem && i == stage) ? .brandWarning : tint
    }
}

// MARK: - Limited-width Dynamic Island
//
// iOS 27 shows compact and minimal presentations in landscape too, where they
// cannot grow in width. Per the HIG, each activity then keeps a leading view
// only — one glyph that fits a 28pt circle, ringed with progress where the
// activity has one — and the trailing view goes empty so the system hides it.
// Outside that context, and below iOS 27, every wrapper renders its content
// untouched. The environment value is iOS 27-only and the widget extension
// floors at iOS 18, so the reader lives in an availability-gated view.

@available(iOS 27.0, *)
private struct LimitedWidthSwitch<Full: View, Limited: View>: View {
    @Environment(\.isDynamicIslandLimitedInWidth) private var isLimited
    @ViewBuilder var full: Full
    @ViewBuilder var limited: Limited

    var body: some View {
        if isLimited { limited } else { full }
    }
}

/// `full` normally; `limited` when the Dynamic Island is limited in width.
private struct IslandLimitedWidth<Full: View, Limited: View>: View {
    @ViewBuilder var full: Full
    @ViewBuilder var limited: Limited

    var body: some View {
        if #available(iOS 27.0, *) {
            LimitedWidthSwitch { full } limited: { limited }
        } else {
            full
        }
    }
}

/// Circular progress around the limited-width glyph — the graphic stand-in
/// for the count/percentage the hidden trailing view would have shown.
struct IslandProgressRing: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(AppOpacity.tintedFill), lineWidth: IslandMetrics.limitedWidthRing)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: IslandMetrics.limitedWidthRing, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Strokes straddle the path; inset by half so the ring stays inside 28pt.
        .padding(IslandMetrics.limitedWidthRing / 2)
        .animation(.smooth, value: value)
        .accessibilityHidden(true) // the glyph's accessibility value states it
    }
}

/// compactLeading. When limited: the same glyph inside the 28pt circle, an
/// optional progress ring, and `value` read by VoiceOver in place of the
/// hidden trailing metric. Ring and value follow the user's island-data gate,
/// exactly like the trailing view they replace.
struct IslandCompactLeading<Content: View>: View {
    let kind: LiveActivityKind
    var progress: Double? = nil
    var tint: Color? = nil
    var value: Text? = nil
    @ViewBuilder var content: Content

    var body: some View {
        IslandLimitedWidth {
            content
        } limited: {
            ZStack {
                if LA.island(kind), let progress {
                    IslandProgressRing(value: progress, tint: tint ?? kind.color)
                }
                if LA.island(kind), let value {
                    content.accessibilityValue(value)
                } else {
                    content
                }
            }
            .frame(width: IslandMetrics.limitedWidthCircle, height: IslandMetrics.limitedWidthCircle)
        }
    }
}

/// compactTrailing. Owns the user's island-data gate and goes empty when
/// limited in width, so the system hides the trailing side entirely.
struct IslandCompactTrailing<Content: View>: View {
    let kind: LiveActivityKind
    @ViewBuilder var content: Content

    var body: some View {
        if LA.island(kind) {
            IslandLimitedWidth { content } limited: { EmptyView() }
        }
    }
}

/// minimal. Already a single glyph; when limited it is pinned to the 28pt
/// circle so a wide symbol can never spill past it.
struct IslandMinimal<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        IslandLimitedWidth {
            content
        } limited: {
            content
                .frame(maxWidth: IslandMetrics.limitedWidthCircle,
                       maxHeight: IslandMetrics.limitedWidthCircle)
        }
    }
}

// MARK: - Lock-screen card
//
// The one card layout every activity's Lock Screen presentation composes:
// disc · title + detail rows · trailing metric, on the system material.
struct IslandLockCard<Detail: View, Trailing: View>: View {
    let kind: LiveActivityKind
    let title: Text
    var isComplete = false
    var breathes = false
    var wiggles = false
    @ViewBuilder var detail: Detail
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppSpacing.base) {
            IslandIconDisc(kind: kind, isComplete: isComplete, breathes: breathes, wiggles: wiggles)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                title
                    .font(AppFont.footnoteEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                detail
            }
            Spacer()
            trailing
        }
        .padding(AppSpacing.lg)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

/// Secondary line under a lock-card title — context + optional property name.
struct IslandContextLine: View {
    let kind: LiveActivityKind
    let text: Text
    var propertyName: String?

    var body: some View {
        HStack(spacing: AppSpacing.xxs) {
            text
            if LA.property(kind), let property = propertyName, !property.isEmpty {
                Text(verbatim: "· \(property)")
            }
        }
        .font(AppFont.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        // Counts inside context lines ("2 of 5 items") roll like the hero
        // metrics; prose keeps the system's blurred text transition.
        .contentTransition(.numericText())
    }
}

// MARK: - Apple Watch Smart Stack (activityFamily .small)
//
// Every Live Activity declares `supplementalActivityFamilies([.small])`, so
// watchOS 11+ renders these compact cards in the Smart Stack instead of
// falling back to the Dynamic Island compact strip. One shared card layout
// keeps all nine activities reading as one family on the wrist.

/// Routes an activity's content between the phone Lock Screen presentation
/// and the Apple Watch Smart Stack small presentation.
struct ActivityFamilyGate<Small: View, Full: View>: View {
    @Environment(\.activityFamily) private var family
    @ViewBuilder var small: () -> Small
    @ViewBuilder var full: () -> Full

    var body: some View {
        switch family {
        case .small: small()
        default: full()
        }
    }
}

/// The one Smart Stack card: leading state glyph · title + context line or
/// progress · trailing metric. Sized for the watch card — single rows,
/// caption type, no buttons (Smart Stack Live Activities are not
/// interactive; tapping opens the activity on the phone).
struct SmallStackCard<Icon: View, Trailing: View>: View {
    let title: Text
    var detail: Text? = nil
    var progress: Double? = nil
    var progressTint: Color = .accentColor
    @ViewBuilder var icon: Icon
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: AppSpacing.sm + 2) {
            icon
                .font(AppFont.subheadline)
            VStack(alignment: .leading, spacing: AppSpacing.xxs) {
                title
                    .font(AppFont.captionEmphasis)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail {
                    detail
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let progress {
                    IslandProgressBar(value: progress, tint: progressTint)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(AppSpacing.md)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}

// MARK: - Minimal lock-screen row (details toggled off)
struct MinimalLockRow: View {
    let kind: LiveActivityKind
    let title: Text
    var isComplete = false

    var body: some View {
        HStack(spacing: AppSpacing.sm + 2) {
            IslandStateIcon(kind: kind, isComplete: isComplete)
                .font(AppFont.subheadline)
            title
                .font(AppFont.captionEmphasis)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .activityBackgroundTint(Color.clear)
        .activitySystemActionForegroundColor(.primary)
    }
}
