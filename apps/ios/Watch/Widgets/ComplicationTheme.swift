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
        /// The interactive check on the tasks face.
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
        /// Smart Stack wash when something needs the wearer now.
        static let attention = Color.orange
        /// Urgent values, full-color rendering only.
        static let critical = Color.red
    }

    enum Opacity {
        static let washTop: Double = 0.45
        static let washBottom: Double = 0.18
    }

    /// Fallback re-read of the App Group. The watch app reloads timelines on
    /// every payload and session change, so this only covers a missed reload.
    static let refreshInterval: TimeInterval = 3600

    static let families: [WidgetFamily] = [
        .accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline,
    ]
}

// MARK: - Frozen widget kinds
//
// Renaming any of these removes the complication from every watch face that
// carries it (ARCHITECTURE.md, "Frozen contract").

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
    /// Primary everywhere; the critical tint only in full color, where the
    /// system keeps app colors.
    func emphasis(_ isUrgent: Bool, color: Color = ComplicationTheme.Tint.critical) -> AnyShapeStyle {
        isUrgent && self == .fullColor ? AnyShapeStyle(color) : AnyShapeStyle(.primary)
    }
}

// MARK: - Container background
//
// Circular and corner slots take the system's adaptive accessory background.
// The Smart Stack's rectangular card takes a wash whose color carries meaning
// (domain tint when calm, attention when something is due) — in full color
// only: accented and vibrant rendering would flatten it into a grey slab, so
// those and inline keep a clear ground.

enum ComplicationTone: Equatable {
    case calm(Color)
    case attention

    var color: Color {
        switch self {
        case .calm(let tint): return tint
        case .attention:      return ComplicationTheme.Tint.attention
        }
    }
}

private struct ComplicationBackground: ViewModifier {
    let tone: ComplicationTone

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) { background }
    }

    @ViewBuilder
    private var background: some View {
        switch family {
        case .accessoryCircular, .accessoryCorner:
            AccessoryWidgetBackground()
        case .accessoryRectangular where renderingMode == .fullColor:
            LinearGradient(colors: [tone.color.opacity(ComplicationTheme.Opacity.washTop),
                                    tone.color.opacity(ComplicationTheme.Opacity.washBottom)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        default:
            Color.clear
        }
    }
}

extension View {
    func complicationBackground(_ tone: ComplicationTone) -> some View {
        modifier(ComplicationBackground(tone: tone))
    }
}
