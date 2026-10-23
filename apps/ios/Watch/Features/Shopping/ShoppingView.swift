import SwiftUI

// MARK: - Shopping: check items off in the aisle
//
// The open list, capped so the wrist stays a glance (the full list lives on
// the phone). The leading glyph acts on the spot; the row leaves once the
// store marks the item bought. No primary double tap: this is a scrolling
// list inside the vertical pager.

struct ShoppingView: View {
    @Environment(WatchStore.self) private var store

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 15

    init() {}

    private var items: [SupplyCatalogEntry] {
        Array(store.pendingSupplies.prefix(Self.rowLimit))
    }

    var body: some View {
        Group {
            if items.isEmpty {
                AllClearView(systemImage: "cart")
            } else {
                List(items, id: \.id) { item in
                    ShoppingRow(item: item) {
                        store.checkSupply(item.id)
                    }
                    .watchRowBackground(WatchTheme.Tint.shopping)
                }
            }
        }
        .navigationTitle(Text(WatchModule.shopping.titleKey))
        .watchPageGround(WatchTheme.Tint.shopping)
    }
}

// MARK: - Row

private struct ShoppingRow: View {
    let item: SupplyCatalogEntry
    let check: () -> Void

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            // ActionGlyphButton wraps the action in the snappy animation itself.
            ActionGlyphButton(systemImage: "circle",
                              actedSystemImage: "checkmark.circle.fill",
                              tint: WatchTheme.Tint.shopping,
                              labelKey: "watch_tap_check",
                              action: check)
            Text(verbatim: item.name)
                .font(WatchTheme.Typography.body)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
