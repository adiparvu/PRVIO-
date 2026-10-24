import SwiftUI

// MARK: - Pantry: stock on the wrist, tuned with the Crown
//
// The list reads like a shelf: name, how much is left (rounded numerals),
// and an out-of-stock state as symbol + word. What ran out leads, so the
// shelf doubles as a "what to buy" glance. Swipes keep the list fast:
// trailing puts the item on the shopping list, leading uses one unit. A
// tap opens the item, where the Digital Crown is the instrument
// (DESIGN.md, signature moment 5).
//
// Wire constraint: the phone only knows "one unit consumed"
// (`consumePantry`) — increases do not exist on the wire, so the Crown's
// range ends at the current stock and a settled turn is replayed as one
// consume per unit.

/// A push inside the Pantry feature. Feature-specific so it never collides
/// with another feature's route on the shared Home stack.
struct PantryRoute: Hashable {
    let id: UUID
}

struct PantryView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Rows shown on the wrist; anything beyond belongs on the phone.
    private static let rowLimit = 15

    /// Items just sent to the shopping list from this wrist. There is no
    /// optimistic supply row (the phone mints the real one), so the row
    /// confirms it for a moment instead.
    @State private var justListed: Set<UUID> = []

    init() {}

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    /// Out of stock first, catalog order within each group.
    private var items: [PantryCatalogEntry] {
        let all = store.payload?.pantry ?? []
        let ordered = all.filter { $0.quantity <= 0 } + all.filter { $0.quantity > 0 }
        return Array(ordered.prefix(Self.rowLimit))
    }

    private var hiddenCount: Int {
        max(0, (store.payload?.pantry.count ?? 0) - items.count)
    }

    var body: some View {
        Group {
            if items.isEmpty {
                AllClearView(systemImage: WatchModule.pantry.systemImage)
            } else {
                List {
                    Section {
                        ForEach(items, id: \.id) { item in
                            row(item)
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
        .navigationTitle(Text(WatchModule.pantry.titleKey))
        .skyGround()
        .navigationDestination(for: PantryRoute.self) { route in
            PantryDetailView(id: route.id)
        }
    }

    private func row(_ item: PantryCatalogEntry) -> some View {
        NavigationLink(value: PantryRoute(id: item.id)) {
            PantryRow(item: item, isListed: justListed.contains(item.id))
        }
        // The phone skips duplicates when it inserts the supply, so a
        // repeated swipe never doubles a shopping row.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                addToList(item.id)
            } label: {
                Label("watch_pantry_to_list", systemImage: "cart.badge.plus")
            }
            .tint(WatchTheme.Tint.shopping)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if item.quantity > 0 {
                Button {
                    withAnimation(animation) { store.consumePantry(item.id) }
                } label: {
                    Label("watch_consume_one", systemImage: "minus.circle")
                }
                .tint(WatchTheme.Tint.pantry)
            }
        }
        .watchRowBackground(WatchTheme.Tint.pantry)
    }

    private func addToList(_ id: UUID) {
        store.addPantryItemToShoppingList(id)
        withAnimation(animation) { _ = justListed.insert(id) }
        Task { @MainActor in
            try? await Task.sleep(for: WatchTheme.Motion.celebrationHold)
            _ = withAnimation(animation) { justListed.remove(id) }
        }
    }
}

// MARK: - Quantity vocabulary

private enum PantryQuantity {
    /// "2", "0.5" — at most one decimal, the precision the store keeps.
    static func number(_ quantity: Double) -> Text {
        Text(max(0, quantity), format: .number.precision(.fractionLength(0...1)))
    }

    static func unit(_ item: PantryCatalogEntry) -> String? {
        let unit = item.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.isEmpty ? nil : unit
    }

    /// The whole quantity for VoiceOver: "2 kg".
    static func spoken(_ item: PantryCatalogEntry) -> Text {
        guard let unit = unit(item) else { return number(item.quantity) }
        return number(item.quantity) + Text(verbatim: " \(unit)")
    }

    static var outOfStock: StateLabel {
        StateLabel("watch_pantry_out_of_stock", systemImage: "exclamationmark.circle.fill",
                   tint: WatchTheme.Tint.attention)
    }

    static var listed: StateLabel {
        StateLabel("watch_pantry_added", systemImage: "cart.fill", tint: WatchTheme.Tint.shopping)
    }
}

// MARK: - Row

private struct PantryRow: View {
    let item: PantryCatalogEntry
    let isListed: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isOut: Bool { item.quantity <= 0 }

    var body: some View {
        HStack(alignment: .center, spacing: WatchTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                Text(verbatim: item.name)
                    .font(WatchTheme.Typography.rowTitle)
                    .lineLimit(2)
                if isListed {
                    PantryQuantity.listed
                        .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                } else if isOut {
                    PantryQuantity.outOfStock
                        .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
                }
            }
            Spacer(minLength: WatchTheme.Spacing.xs)
            quantity
        }
        .padding(.vertical, WatchTheme.Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: item.name))
        .accessibilityValue(accessibilityValue)
    }

    private var quantity: some View {
        VStack(alignment: .trailing, spacing: 0) {
            PantryQuantity.number(item.quantity)
                .font(WatchTheme.Typography.numeral)
                .monospacedDigit()
                .foregroundStyle(isOut ? Color.secondary : Color.primary)
                .contentTransition(.numericText(value: item.quantity))
            if let unit = PantryQuantity.unit(item) {
                Text(verbatim: unit)
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .watchAlwaysOnDimmed()
            }
        }
    }

    private var accessibilityValue: Text {
        let amount = PantryQuantity.spoken(item)
        if isListed { return amount + Text(verbatim: ", ") + Text("watch_pantry_added") }
        if isOut { return Text("watch_pantry_out_of_stock") }
        return amount
    }
}

// MARK: - Detail: the Crown as the instrument

/// One item, its stock on the Crown. Each detent clicks (system haptic) and
/// a settled turn commits as one `consumePantry` per unit. Stock is shown
/// as it really is: whole units step to 0; a fractional stock steps by
/// whole units down to its remainder (2.5 → 1.5 → 0.5), and a remainder
/// under one unit is used up with a single tap — every value the Crown
/// offers is one the wire can reach.
private struct PantryDetailView: View {
    let id: UUID

    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isListed = false

    /// Read live from the store so every consume re-renders the detail.
    private var item: PantryCatalogEntry? {
        store.payload?.pantry.first { $0.id == id }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.snappy, reduceMotion: reduceMotion)
    }

    var body: some View {
        Group {
            if let item {
                content(item)
            } else {
                AllClearView(systemImage: WatchModule.pantry.systemImage)
            }
        }
        .navigationTitle(Text(WatchModule.pantry.titleKey))
        .skyGround()
        // The item can vanish under the open detail when the phone pushes.
        .onChange(of: item == nil) { _, isGone in
            if isGone { dismiss() }
        }
    }

    private func content(_ item: PantryCatalogEntry) -> some View {
        // A fixed screen when it fits, so the Crown belongs to the stepper;
        // scrolls only at the largest text sizes.
        ViewThatFits(in: .vertical) {
            stack(item)
            ScrollView { stack(item) }
        }
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Button {
                    store.addPantryItemToShoppingList(item.id)
                    withAnimation(animation) { isListed = true }
                } label: {
                    Label(isListed ? LocalizedStringKey("watch_pantry_added")
                                   : LocalizedStringKey("watch_pantry_to_list"),
                          systemImage: isListed ? "checkmark" : "cart.badge.plus")
                        .contentTransition(reduceMotion
                                           ? ContentTransition.opacity
                                           : ContentTransition.symbolEffect(.replace))
                }
                .tint(WatchTheme.Tint.shopping)
                .disabled(isListed)
            }
        }
    }

    private func stack(_ item: PantryCatalogEntry) -> some View {
        VStack(spacing: WatchTheme.Spacing.l) {
            Text(verbatim: item.name)
                .font(WatchTheme.Typography.hero)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            adjuster(item)

            Group {
                if item.quantity <= 0 {
                    PantryQuantity.outOfStock
                } else if isListed {
                    PantryQuantity.listed
                }
            }
            .transition(WatchTheme.Motion.transition(reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity)
        .animation(animation, value: item.quantity <= 0)
        .animation(animation, value: isListed)
    }

    /// Whole units (and 0) on the Crown; a sub-unit remainder gets one tap.
    @ViewBuilder
    private func adjuster(_ item: PantryCatalogEntry) -> some View {
        let quantity = max(0, item.quantity)
        let remainder = Self.remainder(of: quantity)
        if quantity > 0, quantity < 1 {
            remainderControl(item, quantity: quantity)
        } else {
            CrownStepper(value: quantity, in: remainder...quantity, step: 1,
                         unit: PantryQuantity.unit(item),
                         tint: WatchTheme.Tint.pantry, labelKey: WatchModule.pantry.titleKey) { target in
                consume(item.id, from: quantity, to: target)
            }
        }
    }

    /// The last fraction of a unit: its amount, and one tap that uses it up.
    private func remainderControl(_ item: PantryCatalogEntry, quantity: Double) -> some View {
        VStack(spacing: WatchTheme.Spacing.s) {
            (PantryQuantity.number(quantity)
                + Text(verbatim: PantryQuantity.unit(item).map { " \($0)" } ?? ""))
                .font(WatchTheme.Typography.numeralHero)
                .monospacedDigit()
                .contentTransition(.numericText(value: quantity))
                .accessibilityLabel(Text(WatchModule.pantry.titleKey))
                .accessibilityValue(PantryQuantity.spoken(item))
            ActionGlyphButton(systemImage: "minus.circle", actedSystemImage: "checkmark.circle.fill",
                              tint: WatchTheme.Tint.pantry, labelKey: "watch_consume_one",
                              prominence: .prominent) {
                store.consumePantry(item.id)   // the intent plays the click
            }
        }
    }

    /// The fractional part, at the store's one-decimal precision (2.5 → 0.5;
    /// whole numbers → 0).
    private static func remainder(of quantity: Double) -> Double {
        let tenths = (quantity * 10).rounded()
        return tenths.truncatingRemainder(dividingBy: 10) / 10
    }

    /// One `consumePantry` per unit between the old and the settled value.
    /// Each intent clicks; identical haptics inside the coalescing window
    /// land as one, so a three-unit turn is felt once, not three times.
    private func consume(_ id: UUID, from quantity: Double, to target: Double) {
        let units = Int((quantity - target).rounded())
        guard units > 0 else { return }
        withAnimation(animation) {
            for _ in 0..<units { store.consumePantry(id) }
        }
    }
}
