import SwiftUI
import UIKit

// MARK: - The one-circle menu, on the SYSTEM menu (WWDC26)
//
// Apple's current guidance (developer.apple.com, HIG Menus revised June 2026 +
// the Liquid Glass adoption guide) is explicit: the morph-from-the-trigger
// entrance, the floating glass card, the stacked submenu — all of it is the
// native `Menu` presentation on iOS 26+, delivered "out of the box", and
// custom rebuilds are called out as the anti-pattern (a custom background
// "can overlay or interfere with Liquid Glass"). So the aggregate filter
// trigger now presents a REAL system menu: single-select groups are inline
// `Picker`s (native checkmarks, trailing icons), boolean rows are `Toggle`s,
// one-shot actions are `Button(role:)` — which the system runs after the
// dismissal transition, retiring our action mailbox for the native path.
//
// The HIG rules the components enforce:
//  • icons uniformly per group — all rows in a group have one, or none;
//  • icons trail the label (system row anatomy — leading icons were ours);
//  • destructive actions carry the real `ButtonRole.destructive`;
//  • counts/badges are not menu anatomy — they stay on page content.
//
// The legacy rich-popover presentation was DELETED (audit 2026-07-21) —
// Activity's People section, its last justification, moved onto native menu
// options by user decree (IMG_8593). Only the action mailbox survives, for
// the shared rows' dormant non-native branch; do not resurrect the popover.

// MARK: - Rendering mode (native menu vs. rich popover)

private struct GlassMenuNativeKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// True inside a native `Menu` (the default) — the section building
    /// blocks render menu primitives. False inside the rich popover, where
    /// they keep the hand-built glass rows.
    var glassMenuNative: Bool {
        get { self[GlassMenuNativeKey.self] }
        set { self[GlassMenuNativeKey.self] = newValue }
    }
}

// MARK: - Menu chrome (rich-content path only)
//
// The system menu draws its own material, lighting and entrance. This chrome
// survives solely for the rich popover: glass card, morph-open entrance,
// Reduce Motion → fade, Reduce Transparency → opaque surface. Per the
// Liquid Glass guide, it no longer paints specular strokes or sweeps over
// the iOS 26 glass — the material's own lighting model owns that.

struct GlassMenuChrome: ViewModifier {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppRadius.xxl, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .clipShape(shape)
            .modifier(GlassMenuSurface(shape: shape))
            .scaleEffect(appeared || reduceMotion ? 1 : 0.95, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion
                              ? .easeOut(duration: 0.18)
                              : .spring(duration: 0.35, bounce: 0.18)) {
                    appeared = true
                }
            }
            .onDisappear { appeared = false }
            .presentationBackground(.clear)
            .presentationCompactAdaptation(.popover)
    }
}

/// The card surface behind the rich popover's rows. On iOS 26 the bare
/// glass material carries its own lighting — no painted specular edge.
private struct GlassMenuSurface: ViewModifier {
    let shape: RoundedRectangle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(Color(.secondarySystemBackground)
                    .shadow(.drop(color: .black.opacity(0.18), radius: 14, y: 6)),
                            in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
        } else if #available(iOS 26, *) {
            content.glassEffect(in: shape)
        } else {
            content
                .background(.regularMaterial
                    .shadow(.drop(color: .black.opacity(0.16), radius: 16, y: 7)),
                            in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.7))
        }
    }
}

extension View {
    /// The rich popover's presentation: glass card + morph-open entrance.
    func glassMenuChrome() -> some View { modifier(GlassMenuChrome()) }
}

// MARK: - Action mailbox (rich-content path only)
//
// Native menus run their Buttons AFTER the dismissal transition, so the
// mailbox is only needed where we still present a popover ourselves.

final class GlassPopoverActionMailbox {
    var pending: (() -> Void)?
}

private struct GlassPopoverMailboxKey: EnvironmentKey {
    static let defaultValue: GlassPopoverActionMailbox? = nil
}

extension EnvironmentValues {
    var glassPopoverMailbox: GlassPopoverActionMailbox? {
        get { self[GlassPopoverMailboxKey.self] }
        set { self[GlassPopoverMailboxKey.self] = newValue }
    }
}

// MARK: - Toolbar placement — the one circle stays at the trailing edge
//
// Every page's ONE menu trigger uses `.pageMenu`. On iOS 27+ that is the
// system's `topBarPinnedTrailing`: the item is anchored to the trailing
// edge however the toolbar reflows, and (per the SwiftUI docs) pinned
// items only move into the overflow menu when search is active and there
// isn't enough room. Secondary trailing items (an "+" beside the menu)
// keep plain `.topBarTrailing`, so they are the ones that yield first.
// Below iOS 27 the floor is the classic trailing placement.

extension ToolbarItemPlacement {
    static var pageMenu: ToolbarItemPlacement {
        if #available(iOS 27.0, *) {
            return .topBarPinnedTrailing
        } else {
            return .topBarTrailing
        }
    }
}

// MARK: - GlassFilterButton — one circle, every filter (IMG_8540)
//
// The page-level consolidation stands: ONE circular Liquid Glass trigger
// aggregating every view option, filter, sort and one-shot action. What
// changed is the presentation behind it — the system `Menu`, so the open
// animation, the card, the submenus and the dismissal contract are Apple's
// own. The trigger never lies about state: `isActive` shows the accent dot.

struct GlassFilterButton<Content: View>: View {
    /// Accent dot when any hosted filter is narrowed from its default.
    var isActive: Bool = false
    /// True when placed in a `.toolbar` — the system supplies the glass.
    var inToolbar: Bool = false
    /// Trigger glyph. The filter lines by default; pages hosting quick
    /// NAVIGATION rows pass Apple's More glyph ("ellipsis").
    var icon: String = "line.3.horizontal.decrease"
    var accessibilityLabelKey: LocalizedStringKey = "filter_picker"
    /// Standalone trigger diameter (ignored in toolbars — system metrics).
    var standaloneSize: CGFloat = 38
    @ViewBuilder var content: () -> Content


    private var glyphSize: CGFloat {
        inToolbar ? 15 : (standaloneSize * 15 / 38).rounded()
    }

    var body: some View {
        // The native Menu is the ONLY presentation (user-decreed, IMG_8593);
        // the legacy rich-popover path was deleted with zero call sites.
        Menu {
            content()
        } label: {
            trigger
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabelKey))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var trigger: some View {
        Image(systemName: icon)
            .font(AppFont.scaled(glyphSize, weight: .semibold))
            // Concrete ink, not hierarchical: vibrancy over the photographic
            // moods washed the glyph out (see Color.glassInk).
            .foregroundStyle(Color.glassInk)
            .frame(width: inToolbar ? 28 : standaloneSize,
                   height: inToolbar ? 28 : standaloneSize)
            .overlay(alignment: .topTrailing) {
                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                        .offset(x: inToolbar ? 1 : -5, y: inToolbar ? 1 : 5)
                }
            }
            .contentShape(Circle())
            // Glass rides INSIDE the label: applied outside, the interactive
            // glass layer competes for the touch and the first tap only
            // deforms the glass (IMG_8572 "trebuie să apăs de două ori").
            .modifier(StandaloneGlassCircle(enabled: !inToolbar))
    }

}

private struct StandaloneGlassCircle: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.glassCircle(interactive: true)
        } else {
            content
        }
    }
}

// MARK: - Building blocks
//
// Same API everywhere; the body renders native menu primitives inside a
// `Menu` and the legacy glass rows inside the rich popover.

/// Uniform-icon rule (HIG Menus, June 2026 revision): "provide icons for
/// all menu items in a group, or none of them."
private func groupShowsIcons<Value>(_ options: [GlassPickerOption<Value>]) -> Bool {
    !options.isEmpty && options.allSatisfy { $0.icon != nil }
}

/// One option row for the native menu: Label when the group carries icons
/// (the system places the glyph on the trailing edge), plain Text otherwise.
@ViewBuilder
private func nativeOptionLabel<Value>(_ option: GlassPickerOption<Value>,
                                      showsIcons: Bool) -> some View {
    if showsIcons, let icon = option.icon {
        Label { Text(verbatim: option.title) } icon: { Image(systemName: icon) }
    } else {
        Text(verbatim: option.title)
    }
}

/// Uppercase section label separating groups inside the RICH popover; in a
/// native menu it renders as the system's inert caption row.
struct GlassFilterSectionLabel: View {
    let titleKey: LocalizedStringKey

    @Environment(\.glassMenuNative) private var native

    var body: some View {
        if native {
            Text(titleKey)
        } else {
            Text(titleKey)
                .font(AppFont.label)
                .foregroundStyle(.secondary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.md)
                .padding(.bottom, AppSpacing.xxs)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// Separator between groups: the system divider in a native menu (which may
/// render as the gap-in-glass break), the hairline in the rich popover.
struct GlassFilterSectionDivider: View {
    @Environment(\.glassMenuNative) private var native

    var body: some View {
        if native {
            Divider()
        } else {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
                .padding(.top, AppSpacing.sm)
        }
    }
}

/// Single-select group: an inline `Picker` in the native menu — the system
/// checkmark, row anatomy and dismissal are Apple's. Counts stay out of the
/// menu (badges aren't menu anatomy); the page content carries them.
struct GlassFilterSection<Value: Hashable>: View {
    var title: LocalizedStringKey? = nil
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Value
    /// Persistence/side-effect hook, fired after every change.
    var onChange: () -> Void = {}

    @Environment(\.glassMenuNative) private var native
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Routes writes through the haptic + onChange hook.
    private var hookedSelection: Binding<Value> {
        Binding(get: { selection },
                set: { newValue in
                    HapticFeedback.selection()
                    selection = newValue
                    onChange()
                })
    }

    var body: some View {
        if native {
            let showsIcons = groupShowsIcons(options)
            Section {
                Picker(selection: hookedSelection) {
                    ForEach(options) { option in
                        nativeOptionLabel(option, showsIcons: showsIcons)
                            .tag(option.value)
                    }
                } label: { EmptyView() }
                .pickerStyle(.inline)
            } header: {
                if let title { Text(title) }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let title { GlassFilterSectionLabel(titleKey: title) }
                ForEach(options) { option in
                    Button {
                        HapticFeedback.selection()
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            selection = option.value
                        }
                        onChange()
                    } label: {
                        GlassPopoverRow(icon: option.icon, title: option.title,
                                        count: option.count,
                                        isSelected: option.value == selection)
                    }
                    .buttonStyle(.plain)
                    if option.id != options.last?.id {
                        Divider().padding(.leading, AppSpacing.lg)
                    }
                }
            }
        }
    }
}

/// Multi-select group: native `Toggle`s (system checkmarks) in the menu.
struct GlassFilterMultiSection<Value: Hashable>: View {
    var title: LocalizedStringKey? = nil
    let options: [GlassPickerOption<Value>]
    @Binding var selection: Set<Value>
    var onChange: () -> Void = {}

    @Environment(\.glassMenuNative) private var native
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private func membership(_ value: Value) -> Binding<Bool> {
        Binding(get: { selection.contains(value) },
                set: { isOn in
                    HapticFeedback.selection()
                    if isOn { selection.insert(value) } else { selection.remove(value) }
                    onChange()
                })
    }

    var body: some View {
        if native {
            let showsIcons = groupShowsIcons(options)
            Section {
                ForEach(options) { option in
                    Toggle(isOn: membership(option.value)) {
                        nativeOptionLabel(option, showsIcons: showsIcons)
                    }
                }
            } header: {
                if let title { Text(title) }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if let title { GlassFilterSectionLabel(titleKey: title) }
                ForEach(options) { option in
                    Button {
                        HapticFeedback.selection()
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                            if selection.contains(option.value) {
                                selection.remove(option.value)
                            } else {
                                selection.insert(option.value)
                            }
                        }
                        onChange()
                    } label: {
                        GlassPopoverRow(icon: option.icon, title: option.title,
                                        count: option.count,
                                        isSelected: selection.contains(option.value))
                    }
                    .buttonStyle(.plain)
                    if option.id != options.last?.id {
                        Divider().padding(.leading, AppSpacing.lg)
                    }
                }
            }
        }
    }
}

/// One ACTION row (share, export, print…). In the native menu it is a plain
/// `Button(role:)` — the system dismisses first and runs the action after
/// the transition, and styles destructive rows in the semantic red itself.
struct GlassFilterActionRow: View {
    let icon: String
    let title: String
    /// Destructive actions carry the REAL role — HIG: mark them destructive
    /// and list them at the END of the menu.
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.glassMenuNative) private var native
    @Environment(\.dismiss) private var dismiss
    @Environment(\.glassPopoverMailbox) private var mailbox

    var body: some View {
        if native {
            Button(role: role) {
                HapticFeedback.impact(.light)
                action()
            } label: {
                Label { Text(verbatim: title) } icon: { Image(systemName: icon) }
            }
        } else {
            Button {
                HapticFeedback.impact(.light)
                if let mailbox {
                    // Deterministic: the popover's onDisappear runs this once
                    // the dismissal transition is truly over (IMG_8560).
                    mailbox.pending = action
                    dismiss()
                } else {
                    dismiss()
                    action()
                }
            } label: {
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: icon)
                        .font(AppFont.scaled(14, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(role == .destructive ? Color.brandDanger : Color.accentColor)
                        .frame(width: 24)
                    Text(verbatim: title)
                        .font(AppFont.scaled(15))
                        .foregroundStyle(role == .destructive ? Color.brandDanger : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.lg)
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.vertical, AppSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// One boolean row (e.g. "Favorites only") — a native `Toggle` in the menu.
struct GlassFilterToggleRow: View {
    var icon: String? = nil
    let title: String
    @Binding var isOn: Bool
    var onChange: () -> Void = {}

    @Environment(\.glassMenuNative) private var native
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var hooked: Binding<Bool> {
        Binding(get: { isOn },
                set: { newValue in
                    HapticFeedback.selection()
                    isOn = newValue
                    onChange()
                })
    }

    var body: some View {
        if native {
            Toggle(isOn: hooked) {
                if let icon {
                    Label { Text(verbatim: title) } icon: { Image(systemName: icon) }
                } else {
                    Text(verbatim: title)
                }
            }
        } else {
            Button {
                HapticFeedback.selection()
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                    isOn.toggle()
                }
                onChange()
            } label: {
                GlassPopoverRow(icon: icon, title: title, count: nil, isSelected: isOn)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
        }
    }
}
