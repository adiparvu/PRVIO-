import SwiftUI

// MARK: - Shopping: check items off in the aisle
//
// The whole row is the target (an aisle is no place for a 24 pt glyph).
// A tap checks the item at once — the store plays the click and syncs —
// while the row lingers for a beat, struck through, and then slides out.
// Emptying the list draws the all-clear celebration (once per clear, never
// on reload). A scrolling list: no primary double tap.

struct ShoppingView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 15

    /// Items checked on this wrist that stay on screen, struck through, for
    /// one beat after the store already marked them bought.
    @State private var lingering: Set<UUID> = []

    init() {}

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    /// Open items plus the ones still lingering, in catalog order so a
    /// checked row never jumps.
    private var rows: [SupplyCatalogEntry] {
        let shown = (store.payload?.supplies ?? []).filter { !$0.isCompleted || lingering.contains($0.id) }
        return Array(shown.prefix(Self.rowLimit))
    }

    private var hiddenCount: Int {
        max(0, store.pendingSupplies.count - rows.filter { !$0.isCompleted }.count)
    }

    var body: some View {
        Group {
            if rows.isEmpty {
                AllClearView(systemImage: "cart", messageKey: "watch_all_good")
            } else {
                List {
                    Section {
                        ForEach(rows, id: \.id) { item in
                            ShoppingRow(item: item) { check(item) }
                                .watchRowBackground(WatchTheme.Tint.shopping)
                        }
                    } footer: {
                        if hiddenCount > 0 {
                            Text("watch_more_on_iphone \(hiddenCount)")
                                .font(WatchTheme.Typography.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .watchAlwaysOnDimmed()
                        }
                    }
                }
            }
        }
        .navigationTitle(Text(WatchModule.shopping.titleKey))
        .skyGround()
        .watchAllClearCelebration(.shopping)
    }

    /// Check now (haptic, sync, celebration all happen in the store), keep
    /// the struck row for a beat, then let it slide out.
    private func check(_ item: SupplyCatalogEntry) {
        guard !item.isCompleted else { return }
        withAnimation(animation) {
            lingering.insert(item.id)
            store.checkSupply(item.id)
        }
        Task { @MainActor in
            try? await Task.sleep(for: WatchTheme.Motion.actionConfirmDelay * 2.0)
            _ = withAnimation(animation) { lingering.remove(item.id) }
        }
    }
}

// MARK: - Row

private struct ShoppingRow: View {
    let item: SupplyCatalogEntry
    let check: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    private var isChecked: Bool { item.isCompleted }

    var body: some View {
        Button(action: check) {
            HStack(spacing: WatchTheme.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(Font.body.weight(isChecked ? .semibold : .light))
                    .foregroundStyle(isChecked ? WatchTheme.Tint.shopping : Color.secondary)
                    .contentTransition(reduceMotion
                                       ? ContentTransition.opacity
                                       : ContentTransition.symbolEffect(.replace))
                    // bounce = done; static under Reduce Motion and Always On.
                    .symbolEffect(.bounce, value: isChecked && !reduceMotion && !isLuminanceReduced)
                    .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                    .accessibilityHidden(true)
                Text(verbatim: item.name)
                    .font(WatchTheme.Typography.body)
                    .strikethrough(isChecked, color: WatchTheme.Tint.shopping)
                    .foregroundStyle(isChecked ? Color.secondary : Color.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The struck row eases toward the edge it is about to leave by.
            .offset(x: isChecked && !reduceMotion ? WatchTheme.Spacing.s : 0)
            .frame(minHeight: WatchTheme.Size.actionMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChecked)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(isChecked ? Text("Done") : Text(verbatim: ""))
        .accessibilityHint(isChecked ? Text(verbatim: "") : Text("watch_tap_check"))
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }
}
