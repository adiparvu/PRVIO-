import SwiftUI
import UIKit
import PhotosUI

// MARK: - Chat theme (conversation background + bubble color)

// MARK: - Custom chat wallpaper storage
//
// A user-uploaded chat background. Only the file name is persisted (not the
// absolute path, which can change between app launches); the full URL is
// reconstructed under the app's Documents directory on read.
enum ChatBackgroundStore {
    private static var dir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    static func url(for fileName: String) -> URL? {
        fileName.isEmpty ? nil : dir.appendingPathComponent(fileName)
    }

    /// Decoded wallpapers, keyed by file name. The chat re-evaluates its body
    /// constantly (typing, presence, scroll) and the background used to hit
    /// `UIImage(contentsOfFile:)` — a synchronous main-thread JPEG decode —
    /// on every single pass, which read as a heavy entry stutter.
    private static let decoded = NSCache<NSString, UIImage>()

    /// The wallpaper image for a stored file name, decoded once and cached.
    static func image(named fileName: String) -> UIImage? {
        if let hit = decoded.object(forKey: fileName as NSString) { return hit }
        guard let url = url(for: fileName),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        decoded.setObject(img, forKey: fileName as NSString)
        return img
    }

    /// Cache-only lookup — never touches disk, safe on the hot render path.
    static func cachedImage(named fileName: String) -> UIImage? {
        decoded.object(forKey: fileName as NSString)
    }

    /// Cheap existence check (a stat, no decode) so the background chooser
    /// can keep its fallback chain without paying for a synchronous decode.
    static func imageExists(named fileName: String) -> Bool {
        guard let url = url(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// The wallpaper decoded off the main actor; the cache is filled so every
    /// later body pass is a synchronous hit.
    static func loadImage(named fileName: String) async -> UIImage? {
        if let hit = cachedImage(named: fileName) { return hit }
        guard let url = url(for: fileName) else { return nil }
        let path = url.path
        let img = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: path)
        }.value
        if let img { decoded.setObject(img, forKey: fileName as NSString) }
        return img
    }

    /// Persist an image for the given scope and return the stored file name.
    static func save(_ image: UIImage, scope: String?) -> String? {
        let safe = (scope ?? "global").replacingOccurrences(of: "/", with: "_")
        let name = "chatbg-\(safe).jpg"
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        do {
            try data.write(to: dir.appendingPathComponent(name))
            // The name is scope-stable, so a re-upload must drop the old decode.
            decoded.removeObject(forKey: name as NSString)
            return name
        } catch { return nil }
    }
}

// MARK: - iMessage bubble tokens
//
// The default PRVIO chat dresses its bubbles exactly like Apple Messages on
// iOS 26: outgoing in the signature blue (a subtle top-to-bottom gradient) and
// incoming in translucent Liquid Glass (rendered via `incomingBubbleGlass`,
// with these gray stops as the Reduce-Transparency / pre-iOS-26 fallback so
// text stays legible over any wallpaper). Custom chat themes keep their own
// picked bubble colour and never see the gradient.
extension Color {
    /// Solid iMessage outgoing blue (#0A7CFF) — the base tint used for
    /// readable-foreground computations and non-gradient surfaces.
    static let imessageBlue = Color(red: 10 / 255, green: 124 / 255, blue: 255 / 255)

    /// The received-bubble gray Messages falls back to when Liquid Glass is
    /// unavailable or Reduce Transparency is on. Light #E9E9EB / dark #262628 —
    /// the exact iMessage grays, adaptive to the interface style.
    static var imessageIncoming: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 38 / 255, green: 38 / 255, blue: 40 / 255, alpha: 1)
                : UIColor(red: 233 / 255, green: 233 / 255, blue: 235 / 255, alpha: 1)
        })
    }

    /// The outgoing-bubble gradient: iMessage blue #0A7CFF (top) → #1E8FFF
    /// (bottom). Applied only on the default theme; custom themes stay solid.
    static var imessageBlueGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 10 / 255, green: 124 / 255, blue: 255 / 255),
                     Color(red: 30 / 255, green: 143 / 255, blue: 255 / 255)],
            startPoint: .top, endPoint: .bottom)
    }
}

struct ChatTheme: Identifiable {
    let id: String
    let name: String
    let outgoingBubble: Color
    let backgroundColors: [Color]?   // nil = app default background
    let isDark: Bool
    var backgroundImage: String? = nil   // custom wallpaper file name (wins over colors)
    var backgroundAnimation: String? = nil   // dynamic preset id (photo wins over it)

    static let all: [ChatTheme] = [
        ChatTheme(id: "appDefault", name: "Default",
                  outgoingBubble: .accentColor, backgroundColors: nil, isDark: false),
        ChatTheme(id: "dark", name: "Dark",
                  outgoingBubble: Color(red: 0.13, green: 0.69, blue: 0.30),
                  backgroundColors: [.black, Color(white: 0.07)], isDark: true),
        ChatTheme(id: "paper", name: "Paper",
                  outgoingBubble: Color(red: 0.13, green: 0.69, blue: 0.30),
                  backgroundColors: [Color(red: 0.96, green: 0.94, blue: 0.88),
                                     Color(red: 0.92, green: 0.89, blue: 0.81)], isDark: false),
        ChatTheme(id: "ocean", name: "Ocean",
                  outgoingBubble: Color(red: 0.0, green: 0.48, blue: 0.66),
                  backgroundColors: [Color(red: 0.78, green: 0.90, blue: 0.95),
                                     Color(red: 0.60, green: 0.79, blue: 0.88)], isDark: false),
        ChatTheme(id: "sunset", name: "Sunset",
                  outgoingBubble: Color(red: 0.90, green: 0.42, blue: 0.28),
                  backgroundColors: [Color(red: 0.99, green: 0.86, blue: 0.70),
                                     Color(red: 0.98, green: 0.70, blue: 0.52)], isDark: false),
        ChatTheme(id: "lavender", name: "Lavender",
                  outgoingBubble: Color(red: 0.45, green: 0.35, blue: 0.85),
                  backgroundColors: [Color(red: 0.86, green: 0.83, blue: 0.97),
                                     Color(red: 0.77, green: 0.73, blue: 0.95)], isDark: false),
        ChatTheme(id: "rose", name: "Rose",
                  outgoingBubble: Color(red: 0.82, green: 0.35, blue: 0.55),
                  backgroundColors: [Color(red: 0.98, green: 0.86, blue: 0.91),
                                     Color(red: 0.96, green: 0.77, blue: 0.85)], isDark: false),
        ChatTheme(id: "holographic", name: "Holographic",
                  outgoingBubble: Color(red: 0.36, green: 0.30, blue: 0.80),
                  backgroundColors: [Color(red: 0.82, green: 0.80, blue: 0.97),
                                     Color(red: 0.92, green: 0.83, blue: 0.95)], isDark: false),
        ChatTheme(id: "coral", name: "Coral",
                  outgoingBubble: Color(red: 0.62, green: 0.27, blue: 0.62),
                  backgroundColors: [Color(red: 0.98, green: 0.80, blue: 0.78),
                                     Color(red: 0.96, green: 0.66, blue: 0.72)], isDark: false),
        ChatTheme(id: "amber", name: "Amber",
                  outgoingBubble: Color(red: 0.80, green: 0.40, blue: 0.30),
                  backgroundColors: [Color(red: 0.99, green: 0.82, blue: 0.55),
                                     Color(red: 0.97, green: 0.62, blue: 0.40)], isDark: false),
        ChatTheme(id: "saltflat", name: "Salt Flat",
                  outgoingBubble: Color(red: 0.13, green: 0.45, blue: 0.36),
                  backgroundColors: [Color(red: 0.62, green: 0.80, blue: 0.86),
                                     Color(red: 0.95, green: 0.75, blue: 0.78)], isDark: false),
        ChatTheme(id: "midnight", name: "Midnight",
                  outgoingBubble: Color(red: 0.20, green: 0.40, blue: 0.90),
                  backgroundColors: [Color(red: 0.05, green: 0.08, blue: 0.18),
                                     Color(red: 0.10, green: 0.13, blue: 0.28)], isDark: true),
    ]

    static func theme(for id: String) -> ChatTheme { all.first { $0.id == id } ?? all[0] }

    /// Resolves the effective theme from the saved theme id plus optional
    /// per-user customizations (custom bubble colour, custom background,
    /// dynamic wallpaper). A photo wins over a dynamic preset, which wins
    /// over a static gradient.
    static func resolved(themeID: String, bubbleHex: String, bgID: String,
                         bgImage: String = "", bgAnim: String = "") -> ChatTheme {
        let base = theme(for: themeID)
        let bubble: Color = (!bubbleHex.isEmpty ? Color(hex: bubbleHex) : nil) ?? base.outgoingBubble
        let bgTheme = bgID.isEmpty ? base : theme(for: bgID)
        let animPreset = bgImage.isEmpty ? AnimatedBackgroundPreset.preset(for: bgAnim) : nil
        let isPlainDefault = themeID == "appDefault" && bubbleHex.isEmpty
            && bgID.isEmpty && bgImage.isEmpty && bgAnim.isEmpty
        return ChatTheme(
            id: isPlainDefault ? "appDefault" : "custom",
            name: base.name,
            outgoingBubble: bubble,
            backgroundColors: bgTheme.backgroundColors,
            isDark: animPreset?.isDark ?? bgTheme.isDark,
            backgroundImage: bgImage.isEmpty ? nil : bgImage,
            backgroundAnimation: animPreset?.id
        )
    }

    /// The one authority for what a conversation actually shows.
    ///
    /// `scope == nil` resolves the global default. For a conversation scope,
    /// THEME and BUBBLE fall back per-field to the global values, but the
    /// three BACKGROUND keys are one setting: the picker clears the other two
    /// ("" = explicitly none) when one is chosen, so a per-field fallback
    /// would resurrect a stale global photo over a freshly picked preset —
    /// the "background never changes" bug. If ANY scoped background key is
    /// set, the scoped background layer wins wholesale.
    static func effective(scope: String?, defaults d: UserDefaults = .standard) -> ChatTheme {
        func nonEmpty(_ key: String) -> String? {
            d.string(forKey: key).flatMap { $0.isEmpty ? nil : $0 }
        }
        let gTheme = nonEmpty("prvio.chatTheme") ?? "appDefault"
        let gBubble = nonEmpty("prvio.chatBubbleHex") ?? ""
        var bg = nonEmpty("prvio.chatBgID") ?? ""
        var img = nonEmpty("prvio.chatBgImage") ?? ""
        var anim = nonEmpty("prvio.chatBgAnim") ?? ""
        var theme = gTheme
        var bubble = gBubble
        if let scope {
            theme = nonEmpty("prvio.chatTheme.\(scope)") ?? gTheme
            bubble = nonEmpty("prvio.chatBubbleHex.\(scope)") ?? gBubble
            let sBg = d.string(forKey: "prvio.chatBgID.\(scope)") ?? ""
            let sImg = d.string(forKey: "prvio.chatBgImage.\(scope)") ?? ""
            let sAnim = d.string(forKey: "prvio.chatBgAnim.\(scope)") ?? ""
            if !(sBg.isEmpty && sImg.isEmpty && sAnim.isEmpty) {
                bg = sBg; img = sImg; anim = sAnim
            }
        }
        return .resolved(themeID: theme, bubbleHex: bubble, bgID: bg,
                         bgImage: img, bgAnim: anim)
    }

    /// True when this conversation has pinned ANY of its own theme keys —
    /// i.e. it no longer follows the global theme live. Mirrors exactly
    /// what `effective(scope:)` treats as an override ("" = unset).
    static func hasOverride(scope: String, defaults d: UserDefaults = .standard) -> Bool {
        ["prvio.chatTheme.", "prvio.chatBubbleHex.",
         "prvio.chatBgID.", "prvio.chatBgImage.", "prvio.chatBgAnim."].contains {
            d.string(forKey: $0 + scope).map { !$0.isEmpty } ?? false
        }
    }

    /// Re-links a conversation to the global theme by REMOVING its scoped
    /// keys (not copying values — a copy is exactly the "background never
    /// follows the global again" bug the user hit). After this,
    /// `effective(scope:)` falls through to the global keys live.
    static func clearOverride(scope: String, defaults d: UserDefaults = .standard) {
        for prefix in ["prvio.chatTheme.", "prvio.chatBubbleHex.",
                       "prvio.chatBgID.", "prvio.chatBgImage.", "prvio.chatBgAnim."] {
            d.removeObject(forKey: prefix + scope)
        }
    }

    // The wallpaper must be anchored to the WINDOW, not to the message list's
    // keyboard-shrunk frame. Ignoring the `.all` safe-area regions (container
    // + keyboard) keeps the layer's bounds full-bleed — and the explicit
    // window-sized frame inside `ChatWallpaperAnchor` makes the render
    // provably constant: even if some container re-proposes a smaller area
    // (keyboard avoidance, composer growth, reply/edit strips), a fixed frame
    // cannot rescale, so `scaledToFill` can never zoom or pan the photo.
    @ViewBuilder var background: some View {
        // Cache hit short-circuits the file-system stat — the chat re-evaluates
        // its body constantly, so the steady-state path must stay allocation-
        // and syscall-free.
        if let name = backgroundImage,
           ChatBackgroundStore.cachedImage(named: name) != nil
            || ChatBackgroundStore.imageExists(named: name) {
            ChatWallpaperAnchor {
                ChatWallpaperImage(name: name)
            }
        } else if let animID = backgroundAnimation,
                  let preset = AnimatedBackgroundPreset.preset(for: animID) {
            ChatWallpaperAnchor { AnimatedChatBackground(preset: preset) }
        } else if let cols = backgroundColors {
            ChatWallpaperAnchor {
                LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
            }
        } else {
            ChatWallpaperAnchor { appBackground }
        }
    }

    /// The same visual layers as `background`, WITHOUT the screen-anchored
    /// frame — for previews that render the theme INSIDE a card (Profile's
    /// chat card, the hub's theme hero). The anchor's fixed
    /// window-sized frame is the chat surface's keyboard contract; put
    /// inside a card it inflates the card to full screen width, blowing
    /// past the page's 20pt margins (IMG_8592). Here the card's own frame
    /// + clip bound the layers instead.
    @ViewBuilder var previewBackground: some View {
        if let name = backgroundImage,
           ChatBackgroundStore.cachedImage(named: name) != nil
            || ChatBackgroundStore.imageExists(named: name) {
            ChatWallpaperImage(name: name)
        } else if let animID = backgroundAnimation,
                  let preset = AnimatedBackgroundPreset.preset(for: animID) {
            AnimatedChatBackground(preset: preset)
        } else if let cols = backgroundColors {
            LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
        } else {
            appBackground
        }
    }

    /// WhatsApp-style bubble colour palette for the "Chat bubble" picker.
    // (see ChatWallpaperAnchor below for how wallpaper layers stay motionless)
    static let bubblePalette: [Color] = [
        Color(red: 0.30, green: 0.69, blue: 0.45), Color(red: 0.82, green: 0.95, blue: 0.82),
        Color(red: 0.36, green: 0.30, blue: 0.85), Color(red: 0.88, green: 0.85, blue: 0.98),
        Color(red: 0.66, green: 0.36, blue: 0.80), Color(red: 0.92, green: 0.85, blue: 0.95),
        Color(red: 0.83, green: 0.42, blue: 0.33), Color(red: 0.96, green: 0.86, blue: 0.82),
        Color(red: 0.22, green: 0.52, blue: 0.50), Color(red: 0.80, green: 0.93, blue: 0.90),
        Color(red: 0.23, green: 0.45, blue: 0.86), Color(red: 0.82, green: 0.89, blue: 0.97),
        Color(red: 0.13, green: 0.28, blue: 0.45), Color(red: 0.80, green: 0.86, blue: 0.91),
        Color(red: 0.22, green: 0.36, blue: 0.20), Color(red: 0.86, green: 0.90, blue: 0.84),
        Color(red: 0.42, green: 0.13, blue: 0.20), Color(red: 0.96, green: 0.82, blue: 0.86),
        Color(red: 0.16, green: 0.16, blue: 0.18), Color(red: 0.84, green: 0.86, blue: 0.88),
        Color(red: 0.30, green: 0.58, blue: 0.92), Color(red: 0.82, green: 0.89, blue: 0.97),
        Color(red: 0.55, green: 0.40, blue: 0.28), Color(red: 0.92, green: 0.84, blue: 0.78),
        Color(red: 0.69, green: 0.62, blue: 0.45), Color(red: 0.92, green: 0.90, blue: 0.83),
        Color(red: 0.27, green: 0.62, blue: 0.50), Color(red: 0.84, green: 0.96, blue: 0.90),
        Color(red: 0.85, green: 0.72, blue: 0.20), Color(red: 0.96, green: 0.95, blue: 0.70),
        Color(red: 0.45, green: 0.66, blue: 0.30), Color(red: 0.88, green: 0.96, blue: 0.78),
        Color(red: 0.83, green: 0.30, blue: 0.50), Color(red: 0.97, green: 0.85, blue: 0.90),
        Color.brandDanger, Color(red: 0.97, green: 0.84, blue: 0.84),
        Color(red: 0.84, green: 0.30, blue: 0.20), Color(red: 0.95, green: 0.85, blue: 0.80),
        Color(red: 0.82, green: 0.66, blue: 0.18), Color(red: 0.97, green: 0.93, blue: 0.78),
    ]
}

// MARK: - Async wallpaper layer

/// Renders a stored chat wallpaper without ever decoding JPEG bytes on the
/// main actor. A cached decode paints on the very first body pass; a cold
/// start shows the app background for the decode's few milliseconds, then
/// settles on the exact same render as before.
private struct ChatWallpaperImage: View {
    let name: String
    @State private var loaded: UIImage?

    var body: some View {
        Group {
            if let img = loaded ?? ChatBackgroundStore.cachedImage(named: name) {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    // Photos arrive raw; the stock themes are designed
                    // gradients. A vertical scrim makes wallpapers read like
                    // part of the set: stronger where the header and compose
                    // bar live, lighter where bubbles carry their own contrast.
                    .overlay(
                        LinearGradient(stops: [
                            .init(color: .black.opacity(0.28), location: 0),
                            .init(color: .black.opacity(0.10), location: 0.25),
                            .init(color: .black.opacity(0.10), location: 0.72),
                            .init(color: .black.opacity(0.30), location: 1),
                        ], startPoint: .top, endPoint: .bottom)
                    )
            } else {
                appBackground
            }
        }
        .task(id: name) {
            guard ChatBackgroundStore.cachedImage(named: name) == nil else { return }
            loaded = nil   // a reused view got a new wallpaper — drop the old one
            loaded = await ChatBackgroundStore.loadImage(named: name)
        }
    }
}

// MARK: - Conversation theme picker (WhatsApp-style)

struct ChatThemePicker: View {
    // scope == nil  -> global default (Chat Settings), writes prvio.chatTheme…
    // scope == id   -> per-conversation override, writes prvio.chatTheme.<id>…
    // Per-conversation keys default to the current global value so the picker
    // opens showing the conversation's effective theme.
    private let scope: String?
    @AppStorage private var selected: String
    @AppStorage private var bubbleHex: String
    @AppStorage private var bgID: String
    @AppStorage private var bgAnim: String
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        self.scope = scope
        let suffix = scope.map { ".\($0)" } ?? ""
        let d = UserDefaults.standard
        let gTheme = scope == nil ? "appDefault" : (d.string(forKey: "prvio.chatTheme") ?? "appDefault")
        let gBubble = scope == nil ? "" : (d.string(forKey: "prvio.chatBubbleHex") ?? "")
        let gBg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgID") ?? "")
        let gAnim = scope == nil ? "" : (d.string(forKey: "prvio.chatBgAnim") ?? "")
        _selected  = AppStorage(wrappedValue: gTheme,  "prvio.chatTheme\(suffix)")
        _bubbleHex = AppStorage(wrappedValue: gBubble, "prvio.chatBubbleHex\(suffix)")
        _bgID      = AppStorage(wrappedValue: gBg,     "prvio.chatBgID\(suffix)")
        _bgAnim    = AppStorage(wrappedValue: gAnim,   "prvio.chatBgAnim\(suffix)")
    }

    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    private var bubbleColor: Color {
        (!bubbleHex.isEmpty ? Color(hex: bubbleHex) : nil) ?? ChatTheme.theme(for: selected).outgoingBubble
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.clear
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        // Per-conversation pickers lead with the way BACK:
                        // once any scoped key was ever written, only this
                        // row re-links the conversation to the global theme
                        // (the keys are removed, not copied).
                        if let scope {
                            Button {
                                ChatTheme.clearOverride(scope: scope)
                                HapticFeedback.success()
                                dismiss()
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "globe")
                                        .font(AppFont.scaled(16))
                                        .foregroundStyle(Color.primary.opacity(AppOpacity.emphasis))
                                        .frame(width: 26)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("chat_theme_use_global")
                                            .font(AppFont.scaled(16)).foregroundStyle(.primary)
                                        Text("chat_theme_use_global_footer")
                                            .font(AppFont.scaled(12)).foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer()
                                    if !ChatTheme.hasOverride(scope: scope) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(AppFont.scaled(18))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                }
                                .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .liquidGlass(cornerRadius: AppRadius.lg)
                            .padding(.horizontal, AppSpacing.lg)
                        }

                        Text("Themes")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl)

                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ChatTheme.all) { theme in
                                Button {
                                    selected = theme.id
                                    bubbleHex = ""; bgID = ""; bgAnim = ""   // theme overrides customizations
                                    HapticFeedback.impact(.light)
                                } label: {
                                    thumb(theme, isSelected: selected == theme.id && bubbleHex.isEmpty
                                                             && bgID.isEmpty && bgAnim.isEmpty)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(AppSpacing.md)
                        .liquidGlass(cornerRadius: 18)
                        .padding(.horizontal, AppSpacing.lg)

                        Text("Both the chat bubble and the conversation background will change.")
                            .font(AppFont.scaled(13))
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl).padding(.top, 2)

                        Text("Customize")
                            .font(AppFont.captionEmphasis)
                            .foregroundStyle(Color.primary.opacity(AppOpacity.mediumText))
                            .padding(.horizontal, AppSpacing.xl).padding(.top, AppSpacing.sm)

                        VStack(spacing: 0) {
                            NavigationLink {
                                BubbleColorPicker(scope: scope)
                            } label: {
                                customRow(icon: "bubble.left.fill", label: "Chat bubble") {
                                    Circle().fill(bubbleColor).frame(width: 22, height: 22)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading, 52)
                            NavigationLink {
                                BackgroundPicker(scope: scope)
                            } label: {
                                customRow(icon: "photo.fill", label: "Background") {
                                    backgroundSwatch
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .liquidGlass(cornerRadius: AppRadius.lg)
                        .padding(.horizontal, AppSpacing.lg)

                        Spacer(minLength: 20)
                    }
                    .padding(.top, AppSpacing.sm)
                }
            }
            .navigationTitle("Conversation theme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // Sheet-presented: a glass backdrop instead of the opaque app
        // background (the sub-pickers inherit the same NavigationStack).
        .sheetGround()
    }

    @ViewBuilder private var backgroundSwatch: some View {
        if let preset = AnimatedBackgroundPreset.preset(for: bgAnim) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(preset.gradient)
                .frame(width: 30, height: 30)
        } else {
            let cols = ChatTheme.theme(for: bgID.isEmpty ? selected : bgID).backgroundColors
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(cols.map { LinearGradient(colors: $0, startPoint: .top, endPoint: .bottom) }
                      ?? LinearGradient(colors: [Color.primary.opacity(0.1)], startPoint: .top, endPoint: .bottom))
                .frame(width: 30, height: 30)
        }
    }

    private func customRow<Trailing: View>(icon: String, label: String,
                                            @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(AppFont.scaled(16)).foregroundStyle(Color.primary.opacity(AppOpacity.emphasis)).frame(width: 26)
            Text(LocalizedStringKey(label)).font(AppFont.scaled(16)).foregroundStyle(.primary)
            Spacer()
            trailing()
            Image(systemName: "chevron.right")
                .font(AppFont.captionEmphasis).foregroundStyle(Color.primary.opacity(0.25))
        }
        .padding(.horizontal, AppSpacing.lg).padding(.vertical, AppSpacing.md)
        .contentShape(Rectangle())
    }

    // Phone-shaped preview: wallpaper + incoming/outgoing sample bubbles.
    private func thumb(_ theme: ChatTheme, isSelected: Bool) -> some View {
        ZStack {
            Group {
                if let cols = theme.backgroundColors {
                    LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                } else {
                    appBackground
                }
            }
            VStack(spacing: 6) {
                Capsule().fill(Color.white.opacity(theme.isDark ? 0.85 : 0.95))
                    .frame(width: 38, height: 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule().fill(theme.outgoingBubble)
                    .frame(width: 42, height: 13)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(AppSpacing.sm)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(16, weight: .bold))
                    .foregroundStyle(.white, theme.outgoingBubble)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppSpacing.xs)
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.primary : Color.primary.opacity(0.12),
                              lineWidth: isSelected ? 2.5 : 1)
        )
    }
}

// MARK: - Chat bubble colour picker

struct BubbleColorPicker: View {
    @AppStorage private var bubbleHex: String
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        let suffix = scope.map { ".\($0)" } ?? ""
        let g = scope == nil ? "" : (UserDefaults.standard.string(forKey: "prvio.chatBubbleHex") ?? "")
        _bubbleHex = AppStorage(wrappedValue: g, "prvio.chatBubbleHex\(suffix)")
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 4)

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(Array(ChatTheme.bubblePalette.enumerated()), id: \.offset) { _, color in
                    let hex = color.hexString()
                    Button {
                        bubbleHex = hex
                        HapticFeedback.impact(.light)
                    } label: {
                        Circle()
                            .fill(color)
                            .frame(width: 62, height: 62)
                            .overlay {
                                if bubbleHex == hex {
                                    Circle().strokeBorder(Color.primary, lineWidth: 3)
                                    Image(systemName: "checkmark")
                                        .font(AppFont.scaled(20, weight: .bold))
                                        .foregroundStyle(color.isLight ? .black : .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppSpacing.xl)
        }
        .navigationTitle("Chat bubble")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Background (wallpaper) picker
//
// Restructured like the Messages background sheet: a live preview of the
// current choice up top, then Your Photo (the personal option leads —
// IMG_8611 "nu are ce căuta jos"), then Dynamic and Colors as HORIZONTAL
// swatch rows — compact phone-shaped chips that scroll sideways instead of
// the old page-length slab grid. Selection is exclusive across sections;
// the storage keys record which kind won.

struct BackgroundPicker: View {
    private let scope: String?
    @AppStorage private var bgID: String
    @AppStorage private var bgImage: String   // custom wallpaper file name ("" = none)
    @AppStorage private var bgAnim: String    // dynamic preset id ("" = none)
    @State private var photoItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    init(scope: String? = nil) {
        self.scope = scope
        let suffix = scope.map { ".\($0)" } ?? ""
        let d = UserDefaults.standard
        let gBg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgID") ?? "")
        let gImg = scope == nil ? "" : (d.string(forKey: "prvio.chatBgImage") ?? "")
        let gAnim = scope == nil ? "" : (d.string(forKey: "prvio.chatBgAnim") ?? "")
        _bgID = AppStorage(wrappedValue: gBg, "prvio.chatBgID\(suffix)")
        _bgImage = AppStorage(wrappedValue: gImg, "prvio.chatBgImage\(suffix)")
        _bgAnim = AppStorage(wrappedValue: gAnim, "prvio.chatBgAnim\(suffix)")
    }

    /// Width of one preset chip in the horizontal rows — phone-shaped at the
    /// tile's 0.62 aspect, six of them visible with a peek of the seventh.
    private static let tileWidth: CGFloat = 84

    private var usingPhoto: Bool { !bgImage.isEmpty }
    private var usingDynamic: Bool { !usingPhoto && !bgAnim.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                livePreview
                photoSection
                dynamicSection
                colorsSection
                Spacer(minLength: 24)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.sm)
        }
        .navigationTitle("Background")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data),
                   let name = ChatBackgroundStore.save(img, scope: scope) {
                    await MainActor.run {
                        bgImage = name; bgID = ""; bgAnim = ""
                        HapticFeedback.success()
                    }
                }
            }
        }
    }

    // MARK: Live preview — the actual background with sample bubbles on it.

    private var livePreview: some View {
        section(title: "Preview") {
            ZStack {
                ChatTheme.resolved(themeID: "appDefault", bubbleHex: "", bgID: bgID,
                                   bgImage: bgImage, bgAnim: bgAnim).background
                VStack(spacing: 8) {
                    HStack {
                        sampleBubble(fill: Color(.systemBackground).opacity(0.92), isOwn: false)
                        Spacer(minLength: 90)
                    }
                    HStack {
                        Spacer(minLength: 90)
                        sampleBubble(fill: Color.accentColor, isOwn: true)
                    }
                }
                .padding(AppSpacing.lg)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.7)
            )
        }
    }

    private func sampleBubble(fill: Color, isOwn: Bool) -> some View {
        Capsule()
            .fill(fill)
            .frame(width: isOwn ? 96 : 128, height: 30)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
    }

    // MARK: Your photo (leads — the personal option is the page's point)

    private var photoSection: some View {
        section(title: "Your photo") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: AppSpacing.sm) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        tile(selected: false) {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus")
                                    .font(AppFont.scaled(20, weight: .semibold))
                                Text("Upload").font(AppFont.caption2)
                            }
                            .foregroundStyle(Color.accentColor)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.accentColor.opacity(0.1))
                        }
                        .frame(width: Self.tileWidth)
                    }
                    .buttonStyle(.plain)

                    if usingPhoto, let img = ChatBackgroundStore.image(named: bgImage) {
                        Button {
                            HapticFeedback.impact(.light)  // already selected — tap re-affirms
                        } label: {
                            tile(selected: true) {
                                // scaledToFill inside a clear overlay: the photo
                                // fills the tile without inflating its layout —
                                // a bare fill let portrait shots burst out of
                                // the grid and cover the Upload tile.
                                Color.clear
                                    .overlay(Image(uiImage: img).resizable().scaledToFill())
                                    .clipped()
                            }
                            .frame(width: Self.tileWidth)
                        }
                        .buttonStyle(.plain)
                    }

                    if usingPhoto {
                        Button(role: .destructive) {
                            bgImage = ""; HapticFeedback.impact(.light)
                        } label: {
                            Label("Remove custom photo", systemImage: "trash")
                                .font(AppFont.caption)
                        }
                        .padding(.leading, AppSpacing.sm)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Dynamic (animated) presets — one horizontal swatch row

    private var dynamicSection: some View {
        section(title: "Dynamic") {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: AppSpacing.sm) {
                    ForEach(AnimatedBackgroundPreset.all) { preset in
                        let isSel = usingDynamic && bgAnim == preset.id
                        Button {
                            bgAnim = preset.id; bgID = ""; bgImage = ""
                            HapticFeedback.impact(.light)
                        } label: {
                            VStack(spacing: AppSpacing.xs) {
                                tile(selected: isSel) {
                                    AnimatedChatBackground(preset: preset)
                                }
                                .frame(width: Self.tileWidth)
                                Text(preset.name)
                                    .font(AppFont.caption2)
                                    .foregroundStyle(isSel ? AnyShapeStyle(.primary)
                                                          : AnyShapeStyle(.secondary))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Static gradient presets — one horizontal swatch row

    private var colorsSection: some View {
        section(title: "Colors") {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: AppSpacing.sm) {
                    ForEach(ChatTheme.all) { theme in
                        let isSel = !usingPhoto && !usingDynamic && bgID == theme.id
                        Button {
                            bgID = theme.id; bgImage = ""; bgAnim = ""
                            HapticFeedback.impact(.light)
                        } label: {
                            tile(selected: isSel) {
                                Group {
                                    if let cols = theme.backgroundColors {
                                        LinearGradient(colors: cols, startPoint: .top, endPoint: .bottom)
                                    } else {
                                        appBackground
                                    }
                                }
                            }
                            .frame(width: Self.tileWidth)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Building blocks

    private func section<Content: View>(title: LocalizedStringKey,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.captionStrong)
                .foregroundStyle(.secondary)
                .padding(.leading, AppSpacing.xxs)
            content()
        }
    }

    @ViewBuilder
    private func tile<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        ZStack {
            content()
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFont.scaled(18, weight: .bold))
                    .foregroundStyle(.white, Color.accentColor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(AppSpacing.xs)
            }
        }
        .aspectRatio(0.62, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: selected ? 2.5 : 1)
        )
    }
}

// MARK: - Window-anchored wallpaper layer

/// Pins a chat wallpaper layer to the hosting window. Two guarantees stack:
/// `.ignoresSafeArea(.all)` keeps the layer's bounds out of every safe-area
/// negotiation (container AND keyboard), and the explicit window-sized frame
/// makes the render constant even if some ancestor still re-proposes a
/// smaller area — a fixed frame cannot rescale, so `scaledToFill` content can
/// never zoom or pan when the keyboard rises, the composer grows a line, or
/// a reply/edit strip appears. Every chat surface (DM, group, communities,
/// Yuna) draws its background through this one anchor.
///
/// The size comes from the view's own window, never the main screen: apps
/// are resizable (iPad windowing, iPhone Mirroring), so the window is the
/// only truthful canvas. Full screen, window bounds equal screen bounds —
/// the render is unchanged; a resized window re-anchors on the next layout
/// pass. Until the window is known (the first layout) the frame stays
/// flexible, so nothing renders blank.
struct ChatWallpaperAnchor<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @State private var windowSize: CGSize?

    var body: some View {
        // The probe rides on a flexible base that follows the container, so a
        // window resize reaches it even though the wallpaper's own frame is
        // fixed; the wallpaper is centred on that base exactly as the fixed
        // frame was centred before.
        Color.clear
            .background {
                WindowSizeReader { size in
                    if windowSize != size { windowSize = size }
                }
            }
            .overlay {
                content()
                    .frame(width: windowSize?.width, height: windowSize?.height)
                    .clipped()
            }
            .ignoresSafeArea(.all)
    }
}

/// Reports the hosting window's bounds — keyboard-independent by
/// construction (the keyboard never resizes a window), and re-reported
/// whenever the window itself is resized.
private struct WindowSizeReader: UIViewRepresentable {
    let onChange: (CGSize) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onChange = onChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onChange = onChange
    }

    final class ProbeView: UIView {
        var onChange: ((CGSize) -> Void)?
        private var reported: CGSize?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let size = window?.bounds.size, size != .zero, size != reported else { return }
            reported = size
            // Hop out of the layout pass — SwiftUI state must not change
            // mid-update.
            DispatchQueue.main.async { [weak self] in self?.onChange?(size) }
        }
    }
}
