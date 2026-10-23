import SwiftUI

// MARK: - Watch design tokens
//
// The watch's counterpart of the phone's DesignSystem.swift (which is not
// compiled into the watch targets). Every watch view takes its tints,
// spacing, radii, type and motion from here instead of literals, so the
// wrist stays one coherent dialect and grows deliberately.
//
// Content, not chrome: cards and rows wear a tinted fill, never Liquid
// Glass — glass belongs to the system toolbar floating above the content.

enum WatchTheme {

    // MARK: Tints (one per surface)

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

    // MARK: Corner radii (always continuous)

    enum Radius {
        static let small: CGFloat = 10
        static let row: CGFloat   = 12
        static let card: CGFloat  = 14
    }

    // MARK: Sizes

    enum Size {
        static let healthRing: CGFloat   = 54
        static let rowIcon: CGFloat      = 24
        static let urgentDot: CGFloat    = 5
        static let actionMinHeight: CGFloat = 36
    }

    // MARK: Opacity tiers

    enum Opacity {
        /// Card fill gradient, top-leading → bottom-trailing.
        static let cardTop: Double     = 0.32
        static let cardBottom: Double  = 0.10
        /// Plain page ground when no sky or mood arrived.
        static let ground: Double      = 0.30
        /// The Emergency page's red ground — a signal, never an atmosphere.
        static let signalGround: Double = 0.28
        /// Always On: atmosphere recedes further than the content on it.
        static let alwaysOnGround: Double  = 0.4
        /// Always On: secondary controls and labels dim to this.
        static let alwaysOnContent: Double = 0.6
        /// Badge/circle fills behind a tinted glyph.
        static let glyphFill: Double   = 0.18
    }

    // MARK: Typography (system text styles only — Dynamic Type intact)

    enum Typography {
        static let hero         = Font.system(.headline, design: .rounded).weight(.semibold)
        static let metric       = Font.system(.title2, design: .rounded).weight(.bold)
        static let temperature  = Font.system(.title3, design: .rounded).weight(.bold)
        static let cardTitle    = Font.system(.footnote, design: .rounded).weight(.semibold)
        static let body         = Font.system(.footnote, design: .rounded)
        static let rowTitle     = Font.system(.footnote, design: .rounded).weight(.medium)
        static let caption      = Font.caption2
        static let captionStrong = Font.caption2.weight(.semibold)
        static let badge        = Font.system(.caption2, design: .rounded).weight(.bold)
        static let glyph        = Font.caption.weight(.semibold)
        static let clockLarge   = Font.system(.largeTitle, design: .rounded).weight(.bold)
        static let clockInline  = Font.system(.headline, design: .rounded).weight(.bold)
        static let sectionHeader = Font.system(.caption2, design: .rounded).weight(.semibold)
    }

    // MARK: Motion

    enum Motion {
        static let snappy: Animation = .snappy
        static let smooth: Animation = .smooth
        /// The beat between a tap's glyph confirmation and the real action —
        /// the pause is the celebration (skipped under Reduce Motion).
        static let actionConfirmDelay: Duration = .milliseconds(380)
        static let entrance: Animation = .spring(duration: 0.5)
        static let entranceStagger: Double = 0.06
        static let ringFill: Animation = .spring(duration: 1.1)
    }

    // MARK: Derived styles

    /// The soft card fill: the surface's tint breathing through the dark.
    static func cardFill(_ tint: Color) -> LinearGradient {
        LinearGradient(colors: [tint.opacity(Opacity.cardTop), tint.opacity(Opacity.cardBottom)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Health score colour bands.
    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...:   return .green
        case 60..<80: return .yellow
        default:      return .orange
        }
    }
}

// MARK: - The app's mood, on the wrist
//
// The phone resolves its living mood and sends the raw value in
// `WatchPayload.mood`. Raw values this build does not know decode to nil
// and the pages keep their plain tints.
//
// Palette provenance: `AppMoodPalette` in Sources/Components/DesignSystem.swift
// is the source of truth; it does not compile into the watch target, so the
// hue/opacity pairs are mirrored here — change both together.
//
// Adaptive, not copied: watchOS renders on OLED black and every system
// style assumes a dark ground, so the wrist takes each mood's two ambient
// accents (at the palette's own accent opacities) as the page wash, never
// the phone's light grounds.

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
    var pageWash: LinearGradient {
        let top: Color, topOpacity: Double
        let bottom: Color, bottomOpacity: Double
        switch self {
        case .morning:
            top = Color(red: 0.937, green: 0.745, blue: 0.545); topOpacity = 0.32
            bottom = Color(red: 0.890, green: 0.635, blue: 0.616); bottomOpacity = 0.20
        case .day:
            top = Color(red: 0.745, green: 0.843, blue: 0.929); topOpacity = 0.22
            bottom = Color(red: 0.922, green: 0.863, blue: 0.753); bottomOpacity = 0.20
        case .sunset:
            top = Color(red: 0.910, green: 0.592, blue: 0.353); topOpacity = 0.26
            bottom = Color(red: 0.608, green: 0.482, blue: 0.722); bottomOpacity = 0.16
        case .night:
            top = Color(red: 0.788, green: 0.545, blue: 0.322); topOpacity = 0.10
            bottom = Color(red: 0.431, green: 0.306, blue: 0.388); bottomOpacity = 0.12
        case .rain:
            top = Color(red: 0.478, green: 0.576, blue: 0.675); topOpacity = 0.22
            bottom = Color(red: 0.498, green: 0.690, blue: 0.659); bottomOpacity = 0.16
        case .winter:
            top = Color(red: 0.749, green: 0.878, blue: 0.941); topOpacity = 0.30
            bottom = Color(red: 0.843, green: 0.871, blue: 0.898); bottomOpacity = 0.26
        case .event:
            top = Color(red: 0.890, green: 0.702, blue: 0.329); topOpacity = 0.12
            bottom = Color(red: 0.761, green: 0.278, blue: 0.561); bottomOpacity = 0.10
        }
        return LinearGradient(colors: [top.opacity(topOpacity), bottom.opacity(bottomOpacity)],
                              startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - The real sky on the wrist
//
// The phone stamps its backdrop / weather-stage gradient on every push
// (skyTop/skyBottom, [r,g,b] in 0…1). When present it wins over the mood
// wash. On OLED black it rides at reduced opacity — its hue and light, not
// its full luminance.

struct WatchSky: Equatable {
    let top: Color
    let bottom: Color

    init?(payload: WatchPayload?) {
        guard let t = payload?.skyTop, let b = payload?.skyBottom,
              t.count == 3, b.count == 3 else { return nil }
        top = Color(red: t[0], green: t[1], blue: t[2])
        bottom = Color(red: b[0], green: b[1], blue: b[2])
    }

    var pageWash: LinearGradient {
        LinearGradient(colors: [top.opacity(0.38), bottom.opacity(0.30)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Page ground

extension View {
    /// The navigation container ground: the phone's sky when one arrived,
    /// else the mood wash, else the page's own tint. Apply to the root view
    /// of every page and every pushed screen.
    func watchPageGround(_ tint: Color) -> some View {
        modifier(WatchPageGround(tint: tint, isSignal: false))
    }

    /// A ground that never adopts the mood or sky — for screens whose
    /// colour is a signal (Emergency), not an atmosphere.
    func watchSignalGround(_ tint: Color) -> some View {
        modifier(WatchPageGround(tint: tint, isSignal: true))
    }

    /// Dims secondary content in Always On (the face is rarely redrawn and
    /// mostly black there — legible and cheap on the OLED).
    func watchAlwaysOnDimmed() -> some View {
        modifier(WatchAlwaysOnDimming())
    }
}

private struct WatchPageGround: ViewModifier {
    let tint: Color
    let isSignal: Bool
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var dim: Double { isLuminanceReduced ? WatchTheme.Opacity.alwaysOnGround : 1 }

    func body(content: Content) -> some View {
        content.containerBackground(ground.opacity(dim), for: .navigation)
    }

    private var ground: AnyShapeStyle {
        if isSignal {
            return AnyShapeStyle(tint.gradient.opacity(WatchTheme.Opacity.signalGround))
        }
        if let sky = store.sky { return AnyShapeStyle(sky.pageWash) }
        if let mood = store.mood { return AnyShapeStyle(mood.pageWash) }
        return AnyShapeStyle(tint.gradient.opacity(WatchTheme.Opacity.ground))
    }
}

private struct WatchAlwaysOnDimming: ViewModifier {
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        content.opacity(isLuminanceReduced ? WatchTheme.Opacity.alwaysOnContent : 1)
    }
}
