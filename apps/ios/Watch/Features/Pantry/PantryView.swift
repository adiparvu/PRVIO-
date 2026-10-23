import SwiftUI

// MARK: - Pantry: consume from the wrist
//
// Stock at a glance, one unit off with a tap, and a trailing swipe that puts
// the item on the shopping list. Consuming is repeatable (every tap is a
// unit), so the minus button acts immediately rather than through the
// one-shot ActionGlyphButton delay. A scrolling list: no primary double tap.

struct PantryView: View {
    @Environment(WatchStore.self) private var store

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 15

    init() {}

    private var items: [PantryCatalogEntry] {
        Array((store.payload?.pantry ?? []).prefix(Self.rowLimit))
    }

    var body: some View {
        Group {
            if items.isEmpty {
                AllClearView(systemImage: "basket")
            } else {
                List(items, id: \.id) { item in
                    PantryRow(item: item) {
                        withAnimation(WatchTheme.Motion.snappy) { store.consumePantry(item.id) }
                    }
                    // The phone skips duplicates when it inserts the supply,
                    // so a repeated swipe never doubles a shopping row.
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            store.addPantryItemToShoppingList(item.id)
                        } label: {
                            Label("watch_pantry_to_list", systemImage: "cart.fill.badge.plus")
                        }
                        .tint(WatchTheme.Tint.shopping)
                    }
                    .watchRowBackground(WatchTheme.Tint.pantry)
                }
            }
        }
        .navigationTitle(Text(WatchModule.pantry.titleKey))
        .watchPageGround(WatchTheme.Tint.pantry)
    }
}

// MARK: - Row

private struct PantryRow: View {
    let item: PantryCatalogEntry
    let consume: () -> Void

    private var isEmpty: Bool { item.quantity <= 0 }

    /// "2 kg" / "0.5 l" — at most one decimal, the precision the store keeps.
    private var quantityText: String {
        let number = max(0, item.quantity).formatted(.number.precision(.fractionLength(0...1)))
        let unit = item.unit.trimmingCharacters(in: .whitespaces)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.m) {
            consumeButton
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: item.name)
                    .font(WatchTheme.Typography.body)
                    .lineLimit(2)
                quantityLine
            }
            Spacer(minLength: 0)
        }
    }

    /// The empty state carries a glyph and a word, not only a colour.
    private var quantityLine: some View {
        HStack(spacing: WatchTheme.Spacing.xs) {
            if isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .accessibilityHidden(true)
            }
            Text(verbatim: quantityText)
                .contentTransition(.numericText())
            if isEmpty {
                Text("watch_pantry_out_of_stock")
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .font(WatchTheme.Typography.captionStrong)
        .foregroundStyle(isEmpty ? WatchTheme.Tint.critical : Color.secondary)
        .accessibilityElement(children: .combine)
    }

    private var consumeButton: some View {
        Button(action: consume) {
            Image(systemName: "minus.circle.fill")
                .font(.body)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isEmpty ? Color.secondary : WatchTheme.Tint.pantry)
                .symbolEffect(.bounce, value: item.quantity)
                .frame(minWidth: WatchTheme.Size.rowIcon, minHeight: WatchTheme.Size.rowIcon)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty)
        .accessibilityLabel(Text("watch_consume_one"))
        .accessibilityValue(Text(verbatim: quantityText))
    }
}
