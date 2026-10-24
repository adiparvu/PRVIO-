import SwiftUI
import WidgetKit

// MARK: - Complication tokens
//
// The extension compiles without the watch app's Design/ folder, so the face
// vocabulary lives here. Tints mirror WatchTheme.Tint so a module wears the
// same color on the face, in the Smart Stack and inside the app.
//
// Text floor: every size below stays at or above 11 pt (HIG minimum for
// widget text), including after `compactMinimumScale` is applied.

enum ComplicationTheme {
    enum Typography {
        /// Domain glyph beside a header or above a circular value.
        static let glyph = Font.system(size: 12, weight: .semibold)
        /// Rectangular header (domain name, property name, session title).
        static let header = Font.system(size: 13, weight: .semibold)
        /// Rectangular secondary lines (item titles, attribution, advisories).
        static let detail = Font.system(size: 12)
        /// The day's brief and the household summary: the warm voice, rounded.
        static let brief = Font.system(size: 12, design: .rounded)
        /// The one item on the "Now at home" card.
        static let nowTitle = Font.system(size: 15, weight: .semibold, design: .rounded)
        /// Rectangular header count, trailing the domain name.
        static let headerValue = Font.system(size: 16, weight: .bold, design: .rounded)
        /// Rectangular hero number (temperature, amount, clock).
        static let metric = Font.system(size: 20, weight: .bold, design: .rounded)
        /// Stat pairs on the status face.
        static let statValue = Font.system(size: 13, weight: .bold, design: .rounded)
        /// Circular center value.
        static let circularValue = Font.system(.body, design: .rounded).weight(.bold)
        /// Circular value that may need to shrink (clock, currency):
        /// 13 pt × `compactMinimumScale` = 11.05 pt, never below the floor.
        static let circularCompact = Font.system(size: 13, weight: .bold, design: .rounded)
        /// Corner value, curved along the bezel.
        static let cornerValue = Font.system(.title3, design: .rounded).weight(.bold)
        /// The interactive glyph on a face or card (complete, water, received).
        static let action = Font.system(size: 20, weight: .medium)
    }

    /// The only shrink factor faces may use (see `circularCompact`).
    static let compactMinimumScale: CGFloat = 0.85

    enum Spacing {
        static let hairline: CGFloat = 1
        static let xs: CGFloat = 2
        static let s: CGFloat = 4
        static let m: CGFloat = 6
        static let l: CGFloat = 8
    }

    enum Tint {
        static let status = Color.indigo
        static let tasks = Color.blue
        static let water = Color.cyan
        static let shopping = Color.orange
        static let deliveries = Color.indigo
        static let health = Color.green
        static let weather = Color.cyan
        static let budget = Color.green
        static let session = Color.teal
        static let paused = Color.orange
        /// Household state, as WatchTheme.Tint wears it.
        static let calm = Color.mint
        static let attention = Color.orange
        static let alarm = Color.red
        /// Urgent values, full-color rendering only.
        static let critical = Color.red
    }

    enum Opacity {
        /// The sky on the Smart Stack card. Stronger than the app's page ground
        /// (0.38 / 0.30) because the card is a small island on black and must
        /// read as a sky, yet low enough that white text keeps ≥ 4.5:1 even on
        /// the lightest phone skies (day, winter).
        static let skyTop: Double = 0.55
        static let skyBottom: Double = 0.34
        /// How far a card's sky leans toward its domain tint, so Tasks and
        /// Plants stay recognisable while wearing the same sky.
        static let domainLean: Double = 0.16
        /// Always On: the ground recedes further than the content.
        static let alwaysOnDim: Double = 0.45
    }

    /// Mirrors WatchTheme.Warmth: the colors the sky leans toward and how far.
    enum Warmth {
        static let amber = Color(red: 0.96, green: 0.62, blue: 0.24)
        static let alarm = Color(red: 0.92, green: 0.20, blue: 0.18)
        static let attentionTop: Double = 0.30
        static let attentionBottom: Double = 0.45
        static let alarmTop: Double = 0.55
        static let alarmBottom: Double = 0.70
    }

    /// Fallback re-read of the App Group. The watch app reloads timelines on
    /// every payload and session change, so this only covers a missed reload.
    static let refreshInterval: TimeInterval = 3600

    static let families: [WidgetFamily] = [
        .accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline,
    ]
}

// MARK: - Widget kinds
//
// The first ten are frozen: renaming any of them removes the complication
// from every watch face that carries it (ARCHITECTURE.md, "Frozen contract").
// `now` is new with the relevance card; keep it stable once shipped.

enum ComplicationKind {
    static let status = "PRVIOWatchStatus"
    static let tasks = "PRVIOWatchTasks"
    static let water = "PRVIOWatchWater"
    static let shopping = "PRVIOWatchShopping"
    static let deliveries = "PRVIOWatchDeliveries"
    static let health = "PRVIOWatchHealth"
    static let weather = "PRVIOWatchWeather"
    static let budget = "PRVIOWatchBudget"
    static let session = "PRVIOWatchSession"
    static let choice = "PRVIOWatchChoice"
    static let now = "PRVIOWatchNow"
}

// MARK: - Deep links (handled by the watch app's WatchDeepLink)

enum ComplicationLink {
    static let today = URL(string: "prvio://")
    static let tasks = URL(string: "prvio://tasks")
    static let plants = URL(string: "prvio://plants")
    static let shopping = URL(string: "prvio://shopping")
    static let deliveries = URL(string: "prvio://deliveries")
}

// MARK: - Domain presentation

extension WatchDomainOption {
    var tint: Color {
        switch self {
        case .status:     return ComplicationTheme.Tint.status
        case .tasks:      return ComplicationTheme.Tint.tasks
        case .water:      return ComplicationTheme.Tint.water
        case .shopping:   return ComplicationTheme.Tint.shopping
        case .deliveries: return ComplicationTheme.Tint.deliveries
        case .health:     return ComplicationTheme.Tint.health
        case .weather:    return ComplicationTheme.Tint.weather
        case .budget:     return ComplicationTheme.Tint.budget
        }
    }

    var systemImage: String {
        switch self {
        case .status, .health: return "house.fill"
        case .tasks:           return "checklist"
        case .water:           return "drop.fill"
        case .shopping:        return "cart.fill"
        case .deliveries:      return "shippingbox.fill"
        case .weather:         return "cloud.sun.fill"
        case .budget:          return "banknote.fill"
        }
    }

    /// The domain's name, from the existing watch catalog keys.
    var label: Text {
        switch self {
        case .status:     return Text(verbatim: "PRVIO")
        case .tasks:      return Text("watch_tasks")
        case .water:      return Text("watch_water")
        case .shopping:   return Text("watch_shopping")
        case .deliveries: return Text("watch_deliveries")
        case .health:     return Text("watch_health")
        case .weather:    return Text("watch_weather")
        case .budget:     return Text("watch_budget")
        }
    }

    var link: URL? {
        switch self {
        case .tasks:                             return ComplicationLink.tasks
        case .water:                             return ComplicationLink.plants
        case .shopping:                          return ComplicationLink.shopping
        case .deliveries:                        return ComplicationLink.deliveries
        case .status, .health, .weather, .budget: return ComplicationLink.today
        }
    }
}

// MARK: - Urgency without color
//
// Accented faces tint everything in the face color, and not every wearer
// separates red from the rest, so an urgent state always carries a glyph (or
// a trailing "!" where only one text run fits). Red is added only in full
// color, on top of that cue.

enum UrgencyCue {
    static let symbol = "exclamationmark.circle.fill"
}

struct UrgentGlyph: View {
    /// What VoiceOver says for the cue ("Overdue", "over budget", …).
    var label: Text = Text("watch_overdue")

    var body: some View {
        Image(systemName: UrgencyCue.symbol)
            .symbolRenderingMode(.hierarchical)
            .widgetAccentable()
            .accessibilityLabel(label)
    }
}

extension WidgetRenderingMode {
    /// Primary everywhere; a warm tint only in full color, where the system
    /// keeps app colors. Overdue and over-budget are stated plainly in amber
    /// (DESIGN.md: red is reserved for real alarms); the glyph or "!" carries
    /// the cue in every mode.
    func emphasis(_ isUrgent: Bool, color: Color = ComplicationTheme.Tint.attention) -> AnyShapeStyle {
        isUrgent && self == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(.primary)
    }
}

// MARK: - Household state (mirror of WatchRoute.householdState)
//
// The extension cannot import the app's WatchRoute/WatchTheme, so the rule is
// repeated here; change both together. Alarm only for a critical sensor in
// family scope; attention when something is due now (overdue task, thirsty
// plant, alerting sensor); calm otherwise — open-but-not-due is calm.

enum ComplicationHousehold: Equatable, Sendable {
    case calm, attention, alarm

    init(_ payload: WatchPayload?) {
        guard let payload else { self = .calm; return }
        if payload.isFamilyScope, payload.sensors.contains(where: { $0.isAlerting && $0.isCritical }) {
            self = .alarm
        } else {
            self = Self.attentionCount(payload) > 0 ? .attention : .calm
        }
    }

    /// Overdue tasks + thirsty plants + alerting sensors (family scope).
    static func attentionCount(_ payload: WatchPayload?) -> Int {
        guard let payload else { return 0 }
        let overdue = payload.tasks.filter { !$0.isCompleted && $0.isOverdue == true }.count
        let thirsty = payload.plants.filter(\.needsWatering).count
        let alerting = payload.isFamilyScope ? payload.sensors.filter(\.isAlerting).count : 0
        // Catalog-less payloads still carry the snapshot counts.
        let fromCatalog = overdue + thirsty + alerting
        return fromCatalog > 0 ? fromCatalog
            : payload.snapshot.overdueTaskCount + payload.snapshot.plantsNeedingWater
    }

    /// Open tasks + thirsty plants + unbought shopping (WatchRoute.openItemCount).
    static func openItemCount(_ payload: WatchPayload?) -> Int {
        guard let payload else { return 0 }
        return payload.snapshot.openTaskCount
            + payload.snapshot.plantsNeedingWater
            + payload.snapshot.pendingSupplyCount
    }

    var tint: Color {
        switch self {
        case .calm:      return ComplicationTheme.Tint.calm
        case .attention: return ComplicationTheme.Tint.attention
        case .alarm:     return ComplicationTheme.Tint.alarm
        }
    }

    /// Shape carries the state, so it survives accented and tinted faces.
    var systemImage: String {
        switch self {
        case .calm:      return "leaf.fill"
        case .attention: return "sun.horizon.fill"
        case .alarm:     return "exclamationmark.triangle.fill"
        }
    }

    var word: Text {
        switch self {
        case .calm:      return Text("watch_state_calm")
        case .attention: return Text("watch_state_waiting")
        case .alarm:     return Text("watch_sensor_critical")
        }
    }

    /// The encouraging one-liner: "All calm at home", "2 waiting", "3 open",
    /// or the plain alarm sentence. Never "OVERDUE".
    static func summary(_ payload: WatchPayload?) -> Text {
        switch ComplicationHousehold(payload) {
        case .alarm:
            return Text("watch_headline_alarm")
        case .attention:
            return Text("watch_comp_waiting \(attentionCount(payload))")
        case .calm:
            let open = openItemCount(payload)
            return open > 0 ? Text("watch_comp_open \(open)") : Text("watch_headline_clear")
        }
    }
}

// MARK: - The sky of the house (mirror of WatchSkyPalette)
//
// Resolution order matches the app: the phone's live sky → the phone's mood →
// a quiet night blue. The household's state then warms it (amber when
// something waits, red only for an alarm). Mood hues mirror
// Design/WatchTheme.swift (`WatchMood.palette`, itself mirroring the phone's
// AppMoodPalette); change all three together. Opacities are the card's own
// (`Opacity.skyTop/skyBottom`) so every mood stays legible behind white text.

struct ComplicationSky: Equatable, Sendable {
    var top: Color
    var bottom: Color

    static let fallback = ComplicationSky(top: Color(red: 0.25, green: 0.38, blue: 0.62),
                                          bottom: Color(red: 0.12, green: 0.18, blue: 0.34))

    init(top: Color, bottom: Color) {
        self.top = top
        self.bottom = bottom
    }

    /// The house's sky for `payload`, unwarmed.
    init(payload: WatchPayload?) {
        if let t = payload?.skyTop, let b = payload?.skyBottom, t.count == 3, b.count == 3 {
            self = ComplicationSky(top: Color(red: t[0], green: t[1], blue: t[2]),
                                   bottom: Color(red: b[0], green: b[1], blue: b[2]))
        } else if let mood = payload?.mood, let sky = Self.mood(mood) {
            self = sky
        } else {
            self = .fallback
        }
    }

    /// The card ground: the sky, warmed by the household, leaned a little
    /// toward the card's own tint so it keeps its identity.
    static func ground(_ payload: WatchPayload?, accent: Color?) -> ComplicationSky {
        ComplicationSky(payload: payload)
            .warmed(for: ComplicationHousehold(payload))
            .leaned(toward: accent)
    }

    func warmed(for state: ComplicationHousehold) -> ComplicationSky {
        typealias W = ComplicationTheme.Warmth
        switch state {
        case .calm:
            return self
        case .attention:
            return ComplicationSky(top: top.mix(with: W.amber, by: W.attentionTop),
                                   bottom: bottom.mix(with: W.amber, by: W.attentionBottom))
        case .alarm:
            return ComplicationSky(top: top.mix(with: W.alarm, by: W.alarmTop),
                                   bottom: bottom.mix(with: W.alarm, by: W.alarmBottom))
        }
    }

    func leaned(toward tint: Color?) -> ComplicationSky {
        guard let tint else { return self }
        let lean = ComplicationTheme.Opacity.domainLean
        return ComplicationSky(top: top.mix(with: tint, by: lean), bottom: bottom.mix(with: tint, by: lean))
    }

    func gradient(dim: Double = 1) -> LinearGradient {
        LinearGradient(colors: [top.opacity(ComplicationTheme.Opacity.skyTop * dim),
                                bottom.opacity(ComplicationTheme.Opacity.skyBottom * dim)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The mood's two ambient hues (WatchMood.palette); unknown raw values → nil.
    private static func mood(_ raw: String) -> ComplicationSky? {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        switch raw {
        case "morning": return ComplicationSky(top: rgb(0.937, 0.745, 0.545), bottom: rgb(0.890, 0.635, 0.616))
        case "day":     return ComplicationSky(top: rgb(0.745, 0.843, 0.929), bottom: rgb(0.922, 0.863, 0.753))
        case "sunset":  return ComplicationSky(top: rgb(0.910, 0.592, 0.353), bottom: rgb(0.608, 0.482, 0.722))
        case "night":   return ComplicationSky(top: rgb(0.788, 0.545, 0.322), bottom: rgb(0.431, 0.306, 0.388))
        case "rain":    return ComplicationSky(top: rgb(0.478, 0.576, 0.675), bottom: rgb(0.498, 0.690, 0.659))
        case "winter":  return ComplicationSky(top: rgb(0.749, 0.878, 0.941), bottom: rgb(0.843, 0.871, 0.898))
        case "event":   return ComplicationSky(top: rgb(0.890, 0.702, 0.329), bottom: rgb(0.761, 0.278, 0.561))
        default:        return nil
        }
    }
}

// MARK: - Container background
//
// Circular and corner slots take the system's adaptive accessory background.
// The rectangular card (face slot and Smart Stack) wears the house's sky — in
// full color only: accented and vibrant rendering would flatten a gradient
// into a grey slab, so those and inline keep a clear ground and rely on
// glyphs and words.

private struct ComplicationGround: ViewModifier {
    let sky: ComplicationSky

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryCorner:
            AccessoryWidgetBackground()
        case .accessoryRectangular where renderingMode == .fullColor:
            sky.gradient(dim: isLuminanceReduced ? ComplicationTheme.Opacity.alwaysOnDim : 1)
        default:
            Color.clear
        }
    }
}

extension View {
    /// The house's sky behind a face or card (see `ComplicationGround`).
    func complicationGround(_ sky: ComplicationSky) -> some View {
        modifier(ComplicationGround(sky: sky))
    }
}

// MARK: - The day's brief, made to fit
//
// The phone's sentence can be long. Trim it at a word boundary before the
// text system truncates, so a cut never lands mid-word, and keep the face
// honest by never inventing a brief when the phone sent none.

enum ComplicationBrief {
    static func line(_ raw: String?, limit: Int = 90) -> String? {
        guard let raw else { return nil }
        let collapsed = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > limit else { return collapsed }
        let head = collapsed.prefix(limit)
        let cut = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        let trimmed = cut.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces))
        return trimmed + "…"
    }
}
