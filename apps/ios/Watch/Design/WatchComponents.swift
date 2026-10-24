import SwiftUI

// MARK: - Reusable wrist components (DESIGN.md)
//
// The building blocks every page composes. They take plain values — the
// caller owns navigation, data and actions — so they stay cheap to
// re-render and trivially previewable. The two exceptions read the store
// on purpose: `skyGround` (the page's sky depends on the household) and
// `watchAllClearCelebration` (it listens for the store's all-clear event).
//
// Shared rules every component honours:
// - Reduce Motion: no symbol effects, no scale; changes cross-fade.
// - Always On (`isLuminanceReduced`): effects stop, fills become strokes,
//   secondary content dims, private text redacts.
// - Increase Contrast: stronger fills and an outline on cards and rows.
// - State is never colour alone: a symbol and a word travel together.

// MARK: - SkyGround

extension View {
    /// The page ground: the house's sky (payload sky → mood → night-blue),
    /// warmed by the household's state (calm / attention / alarm), dimmed
    /// in Always On. Also publishes the sky accent cards harmonize with.
    /// Apply to the root of every page and pushed screen (the view inside
    /// a NavigationStack — it paints the `.navigation` container).
    func skyGround() -> some View {
        modifier(SkyGround(signalTint: nil))
    }

    /// A ground that never adopts the sky — for screens whose colour is a
    /// signal (Emergency), not an atmosphere.
    func signalGround(_ tint: Color = WatchTheme.Tint.emergency) -> some View {
        modifier(SkyGround(signalTint: tint))
    }

    /// Kept for feature views written before the sky ground: the page tint
    /// is no longer painted (the sky is), so this equals `skyGround()`.
    func watchPageGround(_ tint: Color) -> some View {
        skyGround()
    }

    /// Kept for feature views written before the sky ground: `signalGround`.
    func watchSignalGround(_ tint: Color) -> some View {
        signalGround(tint)
    }

    /// Dims secondary content in Always On (the face is rarely redrawn and
    /// mostly black there — legible and cheap on the OLED).
    func watchAlwaysOnDimmed() -> some View {
        modifier(WatchAlwaysOnDimming())
    }

    /// Personal content (chat, emergency, budget, insights): privacy
    /// sensitive everywhere, and redacted whenever the wrist is down.
    func watchPrivate() -> some View {
        modifier(WatchPrivate())
    }
}

struct SkyGround: ViewModifier {
    /// nil = the house's sky; a colour = a signal ground in that colour.
    let signalTint: Color?

    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        let palette = resolvedPalette
        let dim = isLuminanceReduced ? WatchTheme.AlwaysOn.groundOpacity : 1
        content
            .containerBackground(palette.gradient(dim: dim), for: .navigation)
            .environment(\.watchSkyAccent, signalTint == nil ? palette.accent : nil)
    }

    private var resolvedPalette: WatchSkyPalette {
        if let signalTint { return .signal(signalTint) }
        return WatchSkyPalette.resolve(sky: store.sky, mood: store.mood)
            .warmed(for: store.householdState)
    }
}

private struct WatchAlwaysOnDimming: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content.opacity(isLuminanceReduced ? WatchTheme.AlwaysOn.contentOpacity : 1)
    }
}

private struct WatchPrivate: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content
            .privacySensitive()
            .redacted(reason: isLuminanceReduced ? .privacy : [])
    }
}

// MARK: - Card surface (shared by cards and rows)

/// A tinted surface: gradient fill (outlined under Increase Contrast), or
/// a tinted stroke only in Always On. The tint leans toward the page sky.
struct WatchSurface: View {
    let tint: Color
    var radius: CGFloat = WatchTheme.Radius.card

    @Environment(\.watchSkyAccent) private var skyAccent
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let color = WatchTheme.harmonized(tint, with: skyAccent)
        if isLuminanceReduced {
            shape.strokeBorder(color.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                               lineWidth: WatchTheme.Stroke.outline(contrast))
        } else {
            shape
                .fill(WatchTheme.cardFill(color, increasedContrast: contrast == .increased))
                .overlay {
                    if contrast == .increased {
                        shape.strokeBorder(color.opacity(WatchTheme.Opacity.outline),
                                           lineWidth: WatchTheme.Stroke.hairlineIncreased)
                    }
                }
        }
    }
}

// MARK: - WatchCard

/// The soft rounded card every glance module sits in. Content, not chrome:
/// a tinted surface, never Liquid Glass.
struct WatchCard<Content: View>: View {
    var tint: Color = WatchTheme.Tint.neutral
    var radius: CGFloat = WatchTheme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(WatchTheme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { WatchSurface(tint: tint, radius: radius) }
    }
}

// MARK: - PulseDial

/// The Home Pulse: the house glyph inside the pulse ring (health score).
/// The glyph breathes while the home is calm and wiggles once when the
/// attention count rises (something new needs you). Static under Reduce
/// Motion; an outline in Always On. VoiceOver reads `summary` — one
/// sentence — and nothing else.
struct PulseDial: View {
    /// Health score 0…100; nil draws a full ring in the state's colour.
    let score: Int?
    let state: WatchHouseholdState
    /// Things due now; a rise triggers the single wiggle.
    let attentionCount: Int
    /// The one-sentence VoiceOver summary of the dial.
    let summary: Text
    var size: CGFloat = WatchTheme.Size.dial

    @State private var shown: Double = 0
    @State private var wiggles = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.colorSchemeContrast) private var contrast

    private var animates: Bool { !reduceMotion && !isLuminanceReduced }
    private var target: Double { score.map { Double(min(max($0, 0), 100)) / 100 } ?? 1 }
    private var ringTint: Color { score.map(WatchTheme.scoreColor) ?? state.tint }
    private var ringWidth: CGFloat {
        isLuminanceReduced ? WatchTheme.Stroke.ring / 2 : WatchTheme.Stroke.ring
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringTint.opacity(contrast == .increased ? 0.35 : WatchTheme.Opacity.ringTrack),
                        lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(ringTint.opacity(isLuminanceReduced ? WatchTheme.AlwaysOn.strokeOpacity : 1),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Image(systemName: isLuminanceReduced ? "house" : "house.fill")
                    .font(WatchTheme.Typography.dialGlyph)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(state.tint)
                    .symbolEffect(.breathe, isActive: animates && state == .calm)
                    .symbolEffect(.wiggle, value: wiggles)
                if let score {
                    Text(verbatim: "\(score)")
                        .font(WatchTheme.Typography.numeralSmall)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(score)))
                }
            }
        }
        .padding(ringWidth / 2)
        .frame(width: size, height: size)
        .onAppear(perform: fill)
        .onChange(of: score) { fill() }
        .onChange(of: attentionCount) { old, new in
            // One wiggle per rise; a drop (something cleared) stays quiet.
            if new > old, animates { wiggles += 1 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func fill() {
        if reduceMotion || isLuminanceReduced {
            shown = target
        } else {
            withAnimation(WatchTheme.Motion.ringFill) { shown = target }
        }
    }
}

// MARK: - CornerReadout

/// One of the dial's four corner numbers: a glyph over a rounded value.
/// Display only — wrap it in a Button / NavigationLink (`.buttonStyle(.plain)`)
/// when it should act, and only when its destination is visible.
/// `isUrgent` adds an exclamation symbol (never colour alone); `isLive`
/// pulses the glyph (a running session) unless Reduce Motion / Always On.
struct CornerReadout<Value: View>: View {
    let systemImage: String
    let labelKey: LocalizedStringKey
    let tint: Color
    var alignment: HorizontalAlignment = .leading
    var isUrgent: Bool = false
    var isLive: Bool = false
    let accessibilityValue: Text
    let value: Value

    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(systemImage: String, labelKey: LocalizedStringKey, tint: Color,
         alignment: HorizontalAlignment = .leading, isUrgent: Bool = false,
         isLive: Bool = false, accessibilityValue: Text,
         @ViewBuilder value: () -> Value) {
        self.systemImage = systemImage
        self.labelKey = labelKey
        self.tint = tint
        self.alignment = alignment
        self.isUrgent = isUrgent
        self.isLive = isLive
        self.accessibilityValue = accessibilityValue
        self.value = value()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 0) {
            HStack(spacing: WatchTheme.Spacing.xxs) {
                Image(systemName: systemImage)
                    .symbolVariant(isLuminanceReduced ? .none : .fill)
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: isLive && !reduceMotion && !isLuminanceReduced)
                if isUrgent {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(WatchTheme.Tint.attention)
                }
            }
            .font(WatchTheme.Typography.glyph)
            value
                .font(WatchTheme.Typography.numeral)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        // Fits beside the dial on a 41 mm screen while keeping a usable target.
        .frame(minWidth: WatchTheme.Size.actionMinHeight, minHeight: WatchTheme.Size.actionMinHeight,
               alignment: Alignment(horizontal: alignment, vertical: .center))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(labelKey))
        .accessibilityValue(accessibilityValue)
    }
}

extension CornerReadout where Value == Text {
    /// A counted corner (tasks, plants, parcels).
    init(count: Int, systemImage: String, labelKey: LocalizedStringKey, tint: Color,
         alignment: HorizontalAlignment = .leading, isUrgent: Bool = false) {
        self.init(systemImage: systemImage, labelKey: labelKey, tint: tint,
                  alignment: alignment, isUrgent: isUrgent,
                  accessibilityValue: Text(verbatim: "\(count)")) {
            Text(verbatim: "\(count)")
        }
    }
}

// MARK: - StateLabel

/// A state as symbol + word, in its colour — readable without colour.
struct StateLabel: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let tint: Color

    init(_ titleKey: LocalizedStringKey, systemImage: String, tint: Color) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.tint = tint
    }

    /// The household's state (calm / waiting / critical).
    init(state: WatchHouseholdState) {
        self.init(state.titleKey, systemImage: state.systemImage, tint: state.tint)
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.xs) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(titleKey)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(WatchTheme.Typography.captionStrong)
        .foregroundStyle(tint)
        .watchAlwaysOnDimmed()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ActionGlyphButton

/// The act-on-the-spot glyph: tap → the symbol is replaced by its acted
/// form and bounces → a beat later the action runs, animated (immediately
/// and cross-faded under Reduce Motion). One-shot by default (a second tap
/// is ignored while the item leaves); `isRepeatable` acts on every tap with
/// no delay. `haptic` plays on tap — leave it nil when the action is a
/// WatchStore intent, which already speaks its own haptic. Never a primary
/// double-tap action — rows live in scrolling lists.
struct ActionGlyphButton: View {
    enum Prominence { case row, prominent }

    let systemImage: String
    let actedSystemImage: String
    let tint: Color
    let labelKey: LocalizedStringKey
    var isRepeatable: Bool = false
    var prominence: Prominence = .row
    var haptic: WatchHaptic? = nil
    let action: () -> Void

    @State private var didAct = false
    @State private var taps = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    init(systemImage: String, actedSystemImage: String, tint: Color,
         labelKey: LocalizedStringKey, isRepeatable: Bool = false,
         prominence: Prominence = .row, haptic: WatchHaptic? = nil,
         action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.actedSystemImage = actedSystemImage
        self.tint = tint
        self.labelKey = labelKey
        self.isRepeatable = isRepeatable
        self.prominence = prominence
        self.haptic = haptic
        self.action = action
    }

    private var side: CGFloat {
        prominence == .row ? WatchTheme.Size.rowIcon : WatchTheme.Size.prominentGlyph
    }

    var body: some View {
        Button(action: tap) {
            Image(systemName: didAct ? actedSystemImage : systemImage)
                .font(prominence == .row
                      ? Font.body.weight(didAct ? .semibold : .light)
                      : Font.title3.weight(.semibold))
                .foregroundStyle(didAct || isRepeatable || prominence == .prominent ? tint : Color.secondary)
                .contentTransition(reduceMotion ? ContentTransition.opacity : ContentTransition.symbolEffect(.replace))
                .symbolEffect(.bounce, value: taps)
                .frame(minWidth: side, minHeight: side)
                .background {
                    if prominence == .prominent {
                        if isLuminanceReduced {
                            Circle().strokeBorder(tint.opacity(WatchTheme.AlwaysOn.strokeOpacity),
                                                  lineWidth: WatchTheme.Stroke.hairline)
                        } else {
                            Circle().fill(tint.opacity(WatchTheme.Opacity.glyphFill))
                        }
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(labelKey))
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    private func tap() {
        haptic?.play()
        if isRepeatable {
            if !reduceMotion { taps += 1 }
            withAnimation(animation) { action() }
            return
        }
        guard !didAct else { return }
        withAnimation(animation) { didAct = true }
        if reduceMotion {
            withAnimation(animation) { action() }
            didAct = false
            return
        }
        taps += 1
        Task { @MainActor in
            try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay)
            withAnimation(animation) { action() }
            // A row that stays (its item changed state rather than leaving)
            // returns to idle so it never looks stuck.
            try? await Task.sleep(for: .seconds(1))
            withAnimation(animation) { didAct = false }
        }
    }
}

// MARK: - NextUpCard

/// The single most useful thing right now, with its one-tap action.
/// Never a list: one card, one action.
struct NextUpCard: View {
    let title: String
    var detail: String? = nil
    /// Optional state line (e.g. "Overdue", "To water") — symbol + word.
    var state: StateLabel? = nil
    let tint: Color
    let actionSystemImage: String
    let actedSystemImage: String
    let actionLabelKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        WatchCard(tint: tint, radius: WatchTheme.Radius.hero) {
            HStack(alignment: .center, spacing: WatchTheme.Spacing.m) {
                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                    Text("watch_next_up")
                        .font(WatchTheme.Typography.sectionHeader)
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: title)
                        .font(WatchTheme.Typography.cardTitle)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let state { state }
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .watchAlwaysOnDimmed()
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                ActionGlyphButton(systemImage: actionSystemImage, actedSystemImage: actedSystemImage,
                                  tint: tint, labelKey: actionLabelKey, prominence: .prominent,
                                  action: action)
            }
        }
    }
}

extension NextUpCard {
    /// The card for a `WatchNextUp`; `action` performs its store intent
    /// (completeTask / waterPlant / markDeliveryReceived).
    init(_ nextUp: WatchNextUp, action: @escaping () -> Void) {
        switch nextUp {
        case .task(let task, let isOverdue):
            self.init(title: task.title,
                      state: isOverdue
                        ? StateLabel("watch_overdue", systemImage: "exclamationmark.circle.fill",
                                     tint: WatchTheme.Tint.attention)
                        : nil,
                      tint: WatchTheme.Tint.tasks,
                      actionSystemImage: "circle", actedSystemImage: "checkmark.circle.fill",
                      actionLabelKey: "watch_tap_complete", action: action)
        case .plant(let plant):
            self.init(title: plant.emoji.isEmpty ? plant.name : "\(plant.emoji) \(plant.name)",
                      state: StateLabel("watch_water", systemImage: "drop.fill",
                                        tint: WatchTheme.Tint.water),
                      tint: WatchTheme.Tint.water,
                      actionSystemImage: "drop", actedSystemImage: "drop.fill",
                      actionLabelKey: "watch_tap_water", action: action)
        case .delivery(let parcel):
            let detail = [parcel.carrier, parcel.eta]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            self.init(title: parcel.title, detail: detail,
                      state: StateLabel("Out for delivery", systemImage: "shippingbox.fill",
                                        tint: WatchTheme.Tint.deliveries),
                      tint: WatchTheme.Tint.deliveries,
                      actionSystemImage: "shippingbox", actedSystemImage: "checkmark.circle.fill",
                      actionLabelKey: "watch_delivery_received", action: action)
        }
    }
}

// MARK: - CelebrationView

/// The all-clear moment: a checkmark draws itself on, `.success` plays
/// once, and one encouraging line (rotating by `serial`) says so. Give the
/// host view `.id(serial)` so each clear is a fresh moment; the haptic is
/// played once per instance and coalesced with the store's own `.done`.
struct CelebrationView: View {
    /// The `WatchAllClearEvent.serial` being celebrated.
    let serial: Int
    var tint: Color = WatchTheme.Tint.success

    @State private var drawn = false
    @State private var didPlay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rotating encouraging lines — warm, never pressure.
    static let lines: [LocalizedStringKey] = [
        "watch_celebrate_1", "watch_celebrate_2", "watch_celebrate_3", "watch_celebrate_4",
    ]

    private var line: LocalizedStringKey {
        let count = Self.lines.count
        return Self.lines[((serial - 1) % count + count) % count]
    }

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.s) {
            ZStack {
                if drawn {
                    if reduceMotion {
                        checkmark.transition(.opacity)
                    } else {
                        checkmark.transition(.symbolEffect(.drawOn))
                    }
                }
            }
            .frame(width: WatchTheme.Size.celebrationGlyph, height: WatchTheme.Size.celebrationGlyph)
            Text("watch_all_good")
                .font(WatchTheme.Typography.headline)
            Text(line)
                .font(WatchTheme.Typography.brief)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear(perform: celebrate)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle")
            .font(.largeTitle.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityHidden(true)
    }

    private func celebrate() {
        if !didPlay {
            didPlay = true
            WatchHaptic.celebration.play()
        }
        withAnimation(WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)) {
            drawn = true
        }
    }
}

extension View {
    /// Overlays the celebration when a local edit empties `scope`
    /// (`WatchStore.allClearEvent`), holds it for `Motion.celebrationHold`,
    /// then settles. Never on reload: the event is never persisted.
    func watchAllClearCelebration(_ scope: WatchClearScope) -> some View {
        modifier(AllClearCelebration(scope: scope))
    }
}

private struct AllClearCelebration: ViewModifier {
    let scope: WatchClearScope

    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showing: Int? = nil

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if let serial = showing {
                    CelebrationView(serial: serial)
                        .padding(WatchTheme.Spacing.xl)
                        .background(Color.black.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: WatchTheme.Radius.hero,
                                                         style: .continuous))
                        .padding(.horizontal, WatchTheme.Spacing.s)
                        .id(serial)
                        .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                }
            }
            .onChange(of: store.allClearEvent) { _, event in
                guard let event, event.scopes.contains(scope) else { return }
                withAnimation(animation) { showing = event.serial }
            }
            .task(id: showing) {
                guard showing != nil else { return }
                try? await Task.sleep(for: WatchTheme.Motion.celebrationHold)
                guard !Task.isCancelled else { return }
                withAnimation(animation) { showing = nil }
            }
    }
}

// MARK: - CrownStepper

/// A quantity tuned with the Digital Crown: one detent per `step` (the
/// system clicks each detent — no extra haptic), committed once the Crown
/// rests (`onIdle`). − / + buttons do the same for a tap, and VoiceOver's
/// adjustable action increments / decrements and commits.
struct CrownStepper: View {
    /// The committed value; the stepper follows it when it changes outside.
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Unit shown after the number (payload text, rendered verbatim).
    var unit: String? = nil
    let tint: Color
    let labelKey: LocalizedStringKey
    /// Called once per settled change with the new value.
    let onCommit: (Double) -> Void

    @State private var draft: Double
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    init(value: Double, in range: ClosedRange<Double>, step: Double = 1, unit: String? = nil,
         tint: Color, labelKey: LocalizedStringKey, onCommit: @escaping (Double) -> Void) {
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.tint = tint
        self.labelKey = labelKey
        self.onCommit = onCommit
        _draft = State(initialValue: min(max(value, range.lowerBound), range.upperBound))
    }

    private var canTurn: Bool { range.lowerBound < range.upperBound }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            nudge(-step, systemImage: "minus")
                .disabled(draft <= range.lowerBound)
            Group {
                if canTurn {
                    readout
                        .focusable()
                        .digitalCrownRotation(detent: $draft, from: range.lowerBound,
                                              through: range.upperBound, by: step,
                                              sensitivity: .low, isContinuous: false,
                                              isHapticFeedbackEnabled: true,
                                              onIdle: commit)
                } else {
                    readout
                }
            }
            .frame(maxWidth: .infinity)
            nudge(step, systemImage: "plus")
                .disabled(draft >= range.upperBound)
        }
        .onChange(of: value) { draft = min(max(value, range.lowerBound), range.upperBound) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(labelKey))
        .accessibilityValue(valueText)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: draft = min(draft + step, range.upperBound)
            case .decrement: draft = max(draft - step, range.lowerBound)
            @unknown default: return
            }
            commit()
        }
    }

    private var valueText: Text {
        let number = Text(draft, format: .number.precision(.fractionLength(0...1)))
        guard let unit, !unit.isEmpty else { return number }
        return number + Text(verbatim: " \(unit)")
    }

    private var readout: some View {
        valueText
            .font(WatchTheme.Typography.numeralHero)
            .monospacedDigit()
            .contentTransition(.numericText(value: draft))
            .animation(WatchTheme.Motion.snappy, value: draft)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(isLuminanceReduced ? Color.secondary : Color.primary)
    }

    private func nudge(_ delta: Double, systemImage: String) -> some View {
        Button {
            draft = min(max(draft + delta, range.lowerBound), range.upperBound)
            commit()
        } label: {
            Image(systemName: systemImage)
                .font(WatchTheme.Typography.glyph)
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .background(tint.opacity(WatchTheme.Opacity.glyphFill), in: Circle())
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }

    private func commit() {
        guard draft != value else { return }
        onCommit(draft)
    }
}

// MARK: - CountBadge

/// A capsule count (capped at 99) — tinted; urgent adds a symbol, not just red.
struct CountBadge: View {
    let count: Int
    var tint: Color = WatchTheme.Tint.messages
    var isUrgent: Bool = false

    var body: some View {
        HStack(spacing: 1) {
            if isUrgent {
                Image(systemName: "exclamationmark")
                    .accessibilityHidden(true)
            }
            Text(verbatim: "\(min(count, 99))")
                .contentTransition(.numericText(value: Double(min(count, 99))))
        }
        .font(WatchTheme.Typography.badge)
        .foregroundStyle(.white)
        .padding(.horizontal, WatchTheme.Spacing.xs + 1)
        .padding(.vertical, 1)
        .background(isUrgent ? WatchTheme.Tint.critical : tint, in: Capsule())
    }
}

// MARK: - HealthRing

/// A score as a small ring that settles on arrival (instantly under Reduce
/// Motion) — plant detail and other per-item scores.
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

/// A page with nothing left to do — calm, not empty. The glyph breathes
/// (calm) unless Reduce Motion or Always On.
struct AllClearView: View {
    let systemImage: String
    var messageKey: LocalizedStringKey = "watch_all_good"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: WatchTheme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(WatchTheme.Tint.calm)
                .symbolEffect(.breathe, isActive: !reduceMotion && !isLuminanceReduced)
                .accessibilityHidden(true)
            Text(messageKey)
                .font(WatchTheme.Typography.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, WatchTheme.Spacing.m)
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
                .accessibilityHidden(true)
            Text(titleKey)
                .font(WatchTheme.Typography.headline)
                .multilineTextAlignment(.center)
            if let messageKey {
                Text(messageKey)
                    .font(WatchTheme.Typography.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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

// MARK: - Row background, entrance, scroll depth

extension View {
    /// The standard tinted list-row surface (use inside `List`): harmonized
    /// with the sky, a stroke in Always On, outlined under Increase Contrast.
    func watchRowBackground(_ tint: Color) -> some View {
        listRowBackground(WatchSurface(tint: tint, radius: WatchTheme.Radius.row))
    }

    /// Staggered card entrance; sits out entirely under Reduce Motion.
    func watchEntrance(_ index: Int) -> some View {
        modifier(WatchEntrance(index: index))
    }

    /// Cards in a ScrollView recede slightly at the edges, the way system
    /// lists do (opacity only under Reduce Motion).
    func watchScrollDepth() -> some View {
        modifier(WatchScrollDepth())
    }
}

private struct WatchEntrance: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : WatchTheme.Spacing.m)
            .onAppear {
                guard !reduceMotion, !shown else { return }
                withAnimation(WatchTheme.Motion.entrance
                    .delay(Double(index) * WatchTheme.Motion.entranceStagger)) {
                    shown = true
                }
            }
    }
}

private struct WatchScrollDepth: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let scales = !reduceMotion
        return content.scrollTransition { effect, phase in
            effect
                .opacity(phase.isIdentity ? 1 : 0.6)
                .scaleEffect(x: phase.isIdentity || !scales ? 1 : 0.94,
                             y: phase.isIdentity || !scales ? 1 : 0.94)
        }
    }
}
