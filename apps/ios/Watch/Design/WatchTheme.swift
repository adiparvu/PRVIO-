import SwiftUI

// MARK: - Watch design tokens: "the sky of the house"
//
// The watch's counterpart of the phone's DesignSystem.swift (which is not
// compiled into the watch targets). DESIGN.md is the brief; this file is
// its vocabulary. Every watch view takes tints, spacing, radii, type,
// motion and the Always On rules from here instead of literals.
//
// The idea in one line: the page ground IS the house's sky (the phone's
// `skyTop`/`skyBottom`), and its warmth says how the home is doing —
// calm when all is clear, an amber dawn when something waits, red only for
// a real alarm. Emergency never wears the sky: its ground is a signal.
//
// Content, not chrome: cards and rows wear a tinted fill, never Liquid
// Glass — glass belongs to the system toolbar floating above the content.

enum WatchTheme {

    // MARK: Tints (one per surface)
    //
    // System colours on purpose: they already carry the Increase Contrast
    // variants. Harmony with the sky comes from `harmonized(_:with:)`, which
    // leans a tint a little toward the current sky on cards and rows, so a
    // module keeps its identity while belonging to the page it sits on.

    enum Tint {
        static let today      = Color.blue
        static let tasks      = Color.blue
        static let plants     = Color.green
        static let water      = Color.cyan
        static let home       = Color.indigo
        static let shopping   = Color.orange
        static let pantry     = Color.brown
        static let deliveries = Color.indigo
        static let messages   = Color.blue
        static let map        = Color.teal
        static let controls   = Color.purple
        static let sensors    = Color.mint
        static let emergency  = Color.red
        static let session    = Color.teal
        static let weather    = Color.cyan
        static let insight    = Color.purple
        static let streak     = Color.orange
        static let critical   = Color.red
        static let warning    = Color.orange
        static let success    = Color.green
        static let neutral    = Color.gray
        /// The household's state, as the dial and StateLabel wear it.
        static let calm       = Color.mint
        static let attention  = Color.orange
        static let alarm      = Color.red
    }

    // MARK: Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat  = 4
        static let s: CGFloat   = 6
        static let m: CGFloat   = 8
        static let l: CGFloat   = 10
        static let xl: CGFloat  = 12
        static let xxl: CGFloat = 16
    }

    // MARK: Corner radii (always `style: .continuous`)

    enum Radius {
        static let small: CGFloat = 10
        static let row: CGFloat   = 12
        static let card: CGFloat  = 14
        /// Next Up and the celebration — the page's one prominent card.
        static let hero: CGFloat  = 18
    }

    // MARK: Sizes

    enum Size {
        static let healthRing: CGFloat      = 54
        static let rowIcon: CGFloat         = 24
        static let urgentDot: CGFloat       = 5
        static let actionMinHeight: CGFloat = 36
        /// The Home Pulse dial (ring outer diameter).
        static let dial: CGFloat            = 84
        /// The prominent act-on-the-spot glyph (Next Up).
        static let prominentGlyph: CGFloat  = 36
        /// The celebration's drawn checkmark.
        static let celebrationGlyph: CGFloat = 44
    }

    // MARK: Strokes

    enum Stroke {
        /// The dial's pulse ring.
        static let ring: CGFloat = 7
        /// Card / row outline (Always On, Increase Contrast).
        static let hairline: CGFloat = 1
        /// The same outline when the person asked for more contrast.
        static let hairlineIncreased: CGFloat = 1.5

        static func outline(_ contrast: ColorSchemeContrast) -> CGFloat {
            contrast == .increased ? hairlineIncreased : hairline
        }
    }

    // MARK: Opacity tiers

    enum Opacity {
        /// Card fill gradient, top-leading → bottom-trailing.
        static let cardTop: Double     = 0.32
        static let cardBottom: Double  = 0.10
        /// Card fill under Increase Contrast — stronger, never louder.
        static let cardTopIncreased: Double    = 0.42
        static let cardBottomIncreased: Double = 0.18
        /// Plain page ground for a tint (kept for screens without a sky).
        static let ground: Double      = 0.30
        /// The phone's sky on OLED black: its hue and light, not its luminance.
        static let skyTop: Double      = 0.38
        static let skyBottom: Double   = 0.30
        /// The Emergency page's red ground — a signal, never an atmosphere.
        static let signalGround: Double = 0.30
        /// Always On: the atmosphere recedes further than the content.
        static let alwaysOnGround: Double  = AlwaysOn.groundOpacity
        /// Always On: secondary controls and labels dim to this.
        static let alwaysOnContent: Double = AlwaysOn.contentOpacity
        /// Badge/circle fills behind a tinted glyph.
        static let glyphFill: Double   = 0.18
        /// The dial's ring track.
        static let ringTrack: Double   = 0.22
        /// Card outline under Increase Contrast.
        static let outline: Double     = 0.55
    }

    // MARK: Typography (system text styles only — Dynamic Type intact)
    //
    // SF Rounded for every numeral and for the warm voice; plain SF for
    // running captions so long text stays dense and legible.

    enum Typography {
        static let hero          = Font.system(.headline, design: .rounded).weight(.semibold)
        /// The dial's headline sentence.
        static let headline      = Font.system(.headline, design: .rounded).weight(.semibold)
        /// The day's brief — one warm sentence.
        static let brief         = Font.system(.footnote, design: .rounded)
        static let metric        = Font.system(.title2, design: .rounded).weight(.bold)
        static let temperature   = Font.system(.title3, design: .rounded).weight(.bold)
        static let cardTitle     = Font.system(.footnote, design: .rounded).weight(.semibold)
        static let body          = Font.system(.footnote, design: .rounded)
        static let rowTitle      = Font.system(.footnote, design: .rounded).weight(.medium)
        static let caption       = Font.caption2
        static let captionStrong = Font.caption2.weight(.semibold)
        static let badge         = Font.system(.caption2, design: .rounded).weight(.bold)
        static let glyph         = Font.caption.weight(.semibold)
        static let clockLarge    = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let clockInline   = Font.system(.headline, design: .rounded).weight(.bold)
        static let sectionHeader = Font.system(.caption2, design: .rounded).weight(.semibold)
        /// Numerals: always rounded, always `.monospacedDigit()` at the call
        /// site when the value ticks, so digits never jitter.
        static let numeralHero   = Font.system(.title, design: .rounded).weight(.bold)
        static let numeral       = Font.system(.title3, design: .rounded).weight(.semibold)
        static let numeralSmall  = Font.system(.footnote, design: .rounded).weight(.semibold)
        /// The dial's centre glyph.
        static let dialGlyph     = Font.system(.title2).weight(.semibold)
    }

    // MARK: Motion
    //
    // Purposeful and brief: nothing longer than 0.35 s. Symbol effects
    // carry meaning — breathe = calm, wiggle = needs you, bounce = done,
    // drawOn = celebration, pulse = live session. Under Reduce Motion every
    // animation resolves to a short cross-fade (`resolved(_:reduceMotion:)`,
    // `transition(reduceMotion:)`) and symbol effects are removed.

    enum Motion {
        static let snappy: Animation = .snappy(duration: 0.3)
        static let smooth: Animation = .smooth(duration: 0.35)
        /// Cards arriving on a page.
        static let entrance: Animation = .smooth(duration: 0.35)
        static let entranceStagger: Double = 0.04
        /// The dial's ring settling on its score.
        static let ringFill: Animation = .smooth(duration: 0.35)
        /// What every animation becomes under Reduce Motion.
        static let crossfade: Animation = .easeInOut(duration: 0.2)
        /// The beat between a tap's glyph confirmation and the real action —
        /// the pause is the confirmation (skipped under Reduce Motion).
        static let actionConfirmDelay: Duration = .milliseconds(300)
        /// How long the all-clear celebration stays before settling.
        static let celebrationHold: Duration = .milliseconds(2600)

        /// `animation`, or the cross-fade when Reduce Motion is on.
        static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation {
            reduceMotion ? crossfade : animation
        }

        /// Insert/remove: a small scale + fade, or a pure fade under Reduce Motion.
        static func transition(reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94))
        }
    }

    // MARK: Always On
    //
    // When `isLuminanceReduced` is true the wrist is down: animations stop
    // (symbol effects removed), fills become strokes (cards and rows draw a
    // tinted outline instead of a gradient), the ground dims, seconds
    // disappear (TimelineView drops to minute cadence — SessionClockText),
    // and private text redacts (`.watchPrivate()`: chat, emergency, budget,
    // insights).

    enum AlwaysOn {
        static let groundOpacity: Double  = 0.25
        static let contentOpacity: Double = 0.6
        static let strokeOpacity: Double  = 0.7
    }

    // MARK: Warmth (household state → sky)

    enum Warmth {
        /// The amber dawn "something waits" leans toward.
        static let amber = Color(red: 0.96, green: 0.62, blue: 0.24)
        /// The red a real alarm leans toward.
        static let alarm = Color(red: 0.92, green: 0.20, blue: 0.18)
        /// How far the sky leans (top, bottom) per state.
        static let attentionTop: Double = 0.30
        static let attentionBottom: Double = 0.45
        static let alarmTop: Double = 0.55
        static let alarmBottom: Double = 0.70
    }

    // MARK: Derived styles

    /// The soft card fill: the surface's tint breathing through the dark.
    static func cardFill(_ tint: Color, increasedContrast: Bool = false) -> LinearGradient {
        let top = increasedContrast ? Opacity.cardTopIncreased : Opacity.cardTop
        let bottom = increasedContrast ? Opacity.cardBottomIncreased : Opacity.cardBottom
        return LinearGradient(colors: [tint.opacity(top), tint.opacity(bottom)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// A module tint leaned 18 % toward the page's sky, so every card
    /// belongs to the sky it sits on. nil sky → the tint unchanged.
    static func harmonized(_ tint: Color, with skyAccent: Color?) -> Color {
        guard let skyAccent else { return tint }
        return tint.mix(with: skyAccent, by: 0.18)
    }

    /// Health score colour bands (always paired with the number).
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...:   return .green
        case 60..<80: return .yellow
        default:      return .orange
        }
    }
}

// MARK: - Household state, worn

extension WatchHouseholdState {
    /// The state's colour — never used alone (StateLabel pairs it with a
    /// symbol and a word).
    var tint: Color {
        switch self {
        case .calm:      return WatchTheme.Tint.calm
        case .attention: return WatchTheme.Tint.attention
        case .alarm:     return WatchTheme.Tint.alarm
        }
    }

    /// The state's symbol (filled; Always On uses the outline variant).
    var systemImage: String {
        switch self {
        case .calm:      return "leaf.fill"
        case .attention: return "sun.horizon.fill"
        case .alarm:     return "exclamationmark.triangle.fill"
        }
    }

    /// The state's word.
    var titleKey: LocalizedStringKey {
        switch self {
        case .calm:      return "watch_state_calm"
        case .attention: return "watch_state_waiting"
        case .alarm:     return "watch_sensor_critical"
        }
    }
}

// MARK: - The sky palette
//
// Resolution order: the phone's live sky → the phone's mood → a quiet
// night-blue default (so even the waiting screen has a sky). Then the
// household's warmth leans it: calm keeps it, attention warms it toward
// amber, alarm toward red. Emergency bypasses all of this (`.signal`).

struct WatchSkyPalette: Equatable {
    var top: Color
    var bottom: Color
    var topOpacity: Double
    var bottomOpacity: Double

    /// A calm night-blue for when no sky or mood has arrived yet.
    static let fallback = WatchSkyPalette(
        top: Color(red: 0.25, green: 0.38, blue: 0.62),
        bottom: Color(red: 0.12, green: 0.18, blue: 0.34),
        topOpacity: WatchTheme.Opacity.skyTop,
        bottomOpacity: WatchTheme.Opacity.skyBottom)

    static func resolve(sky: WatchSky?, mood: WatchMood?) -> WatchSkyPalette {
        if let sky {
            return WatchSkyPalette(top: sky.top, bottom: sky.bottom,
                                   topOpacity: WatchTheme.Opacity.skyTop,
                                   bottomOpacity: WatchTheme.Opacity.skyBottom)
        }
        if let mood { return mood.palette }
        return fallback
    }

    /// The emergency ground: a signal in `tint`, never an atmosphere.
    static func signal(_ tint: Color) -> WatchSkyPalette {
        WatchSkyPalette(top: tint, bottom: tint.mix(with: .black, by: 0.5),
                        topOpacity: WatchTheme.Opacity.signalGround + 0.1,
                        bottomOpacity: WatchTheme.Opacity.signalGround)
    }

    /// The sky leaned by how the home is doing.
    func warmed(for state: WatchHouseholdState) -> WatchSkyPalette {
        var copy = self
        switch state {
        case .calm:
            break
        case .attention:
            copy.top = top.mix(with: WatchTheme.Warmth.amber, by: WatchTheme.Warmth.attentionTop)
            copy.bottom = bottom.mix(with: WatchTheme.Warmth.amber, by: WatchTheme.Warmth.attentionBottom)
        case .alarm:
            copy.top = top.mix(with: WatchTheme.Warmth.alarm, by: WatchTheme.Warmth.alarmTop)
            copy.bottom = bottom.mix(with: WatchTheme.Warmth.alarm, by: WatchTheme.Warmth.alarmBottom)
            copy.topOpacity = max(topOpacity, WatchTheme.Opacity.skyTop)
            copy.bottomOpacity = max(bottomOpacity, WatchTheme.Opacity.skyBottom)
        }
        return copy
    }

    /// The ground gradient, scaled by `dim` (Always On).
    func gradient(dim: Double = 1) -> LinearGradient {
        LinearGradient(colors: [top.opacity(topOpacity * dim), bottom.opacity(bottomOpacity * dim)],
                       startPoint: .top, endPoint: .bottom)
    }

    /// The colour cards and rows lean toward (`WatchTheme.harmonized`).
    var accent: Color { top }
}

// MARK: - The app's mood, on the wrist
//
// The phone resolves its living mood and sends the raw value in
// `WatchPayload.mood`. Raw values this build does not know decode to nil.
//
// Palette provenance: `AppMoodPalette` in Sources/Components/DesignSystem.swift
// is the source of truth; it does not compile into the watch target, so the
// hue/opacity pairs are mirrored here — change both together. On OLED black
// the wrist takes each mood's two ambient accents at the palette's own
// accent opacities, never the phone's light grounds.

enum WatchMood: String, Equatable {
    case morning, day, sunset, night, rain, winter, event

    /// Values from AppMoodPalette:
    /// - morning: gold #EFBE8B @ 0.32, rose #E3A29D @ 0.20
    /// - day:     sky #BED7ED @ 0.22, sand #EBDCC0 @ 0.20
    /// - sunset:  ember #E8975A @ 0.26, violet #9B7BB8 @ 0.16
    /// - night:   ember #C98B52 @ 0.10, mauve #6E4E63 @ 0.12
    /// - rain:    slate #7A93AC @ 0.22, teal #7FB0A8 @ 0.16
    /// - winter:  ice #BFE0F0 @ 0.30, silver #D7DEE5 @ 0.26
    /// - event:   gold #E3B354 @ 0.12, magenta #C2478F @ 0.10
    var palette: WatchSkyPalette {
        switch self {
        case .morning:
            return WatchSkyPalette(top: Color(red: 0.937, green: 0.745, blue: 0.545),
                                   bottom: Color(red: 0.890, green: 0.635, blue: 0.616),
                                   topOpacity: 0.32, bottomOpacity: 0.20)
        case .day:
            return WatchSkyPalette(top: Color(red: 0.745, green: 0.843, blue: 0.929),
                                   bottom: Color(red: 0.922, green: 0.863, blue: 0.753),
                                   topOpacity: 0.22, bottomOpacity: 0.20)
        case .sunset:
            return WatchSkyPalette(top: Color(red: 0.910, green: 0.592, blue: 0.353),
                                   bottom: Color(red: 0.608, green: 0.482, blue: 0.722),
                                   topOpacity: 0.26, bottomOpacity: 0.16)
        case .night:
            return WatchSkyPalette(top: Color(red: 0.788, green: 0.545, blue: 0.322),
                                   bottom: Color(red: 0.431, green: 0.306, blue: 0.388),
                                   topOpacity: 0.10, bottomOpacity: 0.12)
        case .rain:
            return WatchSkyPalette(top: Color(red: 0.478, green: 0.576, blue: 0.675),
                                   bottom: Color(red: 0.498, green: 0.690, blue: 0.659),
                                   topOpacity: 0.22, bottomOpacity: 0.16)
        case .winter:
            return WatchSkyPalette(top: Color(red: 0.749, green: 0.878, blue: 0.941),
                                   bottom: Color(red: 0.843, green: 0.871, blue: 0.898),
                                   topOpacity: 0.30, bottomOpacity: 0.26)
        case .event:
            return WatchSkyPalette(top: Color(red: 0.890, green: 0.702, blue: 0.329),
                                   bottom: Color(red: 0.761, green: 0.278, blue: 0.561),
                                   topOpacity: 0.12, bottomOpacity: 0.10)
        }
    }

    /// The mood's wash as a plain gradient.
    var pageWash: LinearGradient { palette.gradient() }
}

// MARK: - The real sky on the wrist
//
// The phone stamps its backdrop / weather-stage gradient on every push
// (skyTop/skyBottom, [r,g,b] in 0…1). When present it wins over the mood.

struct WatchSky: Equatable {
    let top: Color
    let bottom: Color

    init?(payload: WatchPayload?) {
        guard let t = payload?.skyTop, let b = payload?.skyBottom,
              t.count == 3, b.count == 3 else { return nil }
        top = Color(red: t[0], green: t[1], blue: t[2])
        bottom = Color(red: b[0], green: b[1], blue: b[2])
    }

    /// The sky as a plain gradient.
    var pageWash: LinearGradient {
        WatchSkyPalette.resolve(sky: self, mood: nil).gradient()
    }
}

// MARK: - Environment

extension EnvironmentValues {
    /// The current page's sky accent, set by `skyGround`; cards and rows
    /// lean their tint toward it (`WatchTheme.harmonized`). nil off-sky.
    @Entry var watchSkyAccent: Color? = nil
}
