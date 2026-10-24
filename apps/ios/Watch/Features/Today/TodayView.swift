import SwiftUI

// MARK: - Today: Home Pulse
//
// "What needs me now?" in one look, "done" in one tap (DESIGN.md, signature
// moments 1–4). Top to bottom:
//   1. The dial — the house glyph in the health ring, four corner readouts
//      (tasks, plants, parcels, session / streak) and the headline sentence.
//      A corner acts only when its page or module is visible.
//   2. Next Up — the single most useful thing, with its one-tap action; the
//      all-clear celebration takes its place the moment the last open item
//      is cleared on this wrist (once per clear, never on reload).
//   3. The brief — the phone's one warm sentence, or a local one.
//   4. Contextual cards — session, Apple Weather, unread, insight.
//   5. How fresh the data is.

struct TodayView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The household all-clear being celebrated (its event serial).
    @State private var celebration: Int? = nil

    var body: some View {
        if let payload = store.payload {
            content(payload)
        } else {
            EmptyStateView(systemImage: "iphone.and.arrow.forward",
                           titleKey: "watch_waiting_title", messageKey: "watch_waiting_msg")
                .skyGround()
        }
    }

    private var animation: Animation {
        WatchTheme.Motion.resolved(WatchTheme.Motion.smooth, reduceMotion: reduceMotion)
    }

    private func content(_ payload: WatchPayload) -> some View {
        ScrollView {
            VStack(spacing: WatchTheme.Spacing.l) {
                pulse(payload)
                    .watchEntrance(0)

                focus
                    .watchEntrance(1)

                BriefText(text: brief(payload))
                    .watchEntrance(2)

                cards(payload)

                UpdatedFooter(date: payload.snapshot.updatedAt)
            }
            .padding(.horizontal, WatchTheme.Spacing.xxs)
        }
        .navigationTitle(Text(verbatim: payload.snapshot.propertyName ?? "PRVIO"))
        .skyGround()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RefreshButton()
            }
            ToolbarItem(placement: .bottomBar) {
                // Dictate a message for the house chat; the phone sends the
                // real one through the queue notification replies use.
                TextFieldLink(prompt: Text("watch_chat_prompt")) {
                    Image(systemName: "message.fill")
                        .accessibilityLabel(Text("watch_chat_send"))
                } onSubmit: { text in
                    store.sendChatMessage(text)
                }
            }
        }
        .onChange(of: store.allClearEvent) { _, event in
            guard let event, event.scopes.contains(.household) else { return }
            withAnimation(animation) { celebration = event.serial }
        }
        .task(id: celebration) {
            guard celebration != nil else { return }
            try? await Task.sleep(for: WatchTheme.Motion.celebrationHold)
            guard !Task.isCancelled else { return }
            withAnimation(animation) { celebration = nil }
        }
    }

    // MARK: 1. The dial

    private func pulse(_ payload: WatchPayload) -> some View {
        let state = store.householdState
        let tasks = store.openTasks.count
        let plants = store.thirstyPlants.count
        let parcels = payload.deliveries.filter(WatchRoute.isDeliveryActive).count
        let open = store.openItemCount
        let summary = headline(state: state, open: open)
            + Text(verbatim: ". ")
            + Text("watch_dial_ax \(tasks) \(plants) \(parcels)")
            + healthSentence(payload.snapshot.propertyHealthScore)

        return VStack(spacing: WatchTheme.Spacing.s) {
            DialCluster(isStacked: dynamicTypeSize.isAccessibilitySize) {
                PulseDial(score: payload.snapshot.propertyHealthScore, state: state,
                          attentionCount: store.attentionCount, summary: summary)
            } topLeading: {
                pageCorner(.tasks, CornerReadout(count: tasks, systemImage: "checklist",
                                                 labelKey: "watch_tasks", tint: WatchTheme.Tint.tasks,
                                                 isUrgent: payload.snapshot.overdueTaskCount > 0))
            } topTrailing: {
                pageCorner(.plants, CornerReadout(count: plants, systemImage: "drop",
                                                  labelKey: "watch_water", tint: WatchTheme.Tint.water,
                                                  alignment: .trailing))
            } bottomLeading: {
                moduleCorner(.deliveries, CornerReadout(count: parcels, systemImage: "shippingbox",
                                                        labelKey: "watch_deliveries",
                                                        tint: WatchTheme.Tint.deliveries))
            } bottomTrailing: {
                sessionCorner(streak: payload.streakDays)
            }

            headline(state: state, open: open)
                .font(WatchTheme.Typography.headline)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(animation, value: state)
                .accessibilityHidden(true) // the dial already reads it

            if let streak = payload.streakDays, streak >= 2 {
                // Consecutive verified all-clear days, computed on the phone —
                // celebrated, never a target to defend.
                HStack(spacing: WatchTheme.Spacing.xs) {
                    Image(systemName: "flame.fill")
                        .accessibilityHidden(true)
                    Text("watch_streak_calm \(streak)")
                        .contentTransition(.numericText(value: Double(streak)))
                }
                .font(WatchTheme.Typography.captionStrong)
                .foregroundStyle(WatchTheme.Tint.streak)
                .watchAlwaysOnDimmed()
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// The dial's sentence: plain words, never shouting.
    private func headline(state: WatchHouseholdState, open: Int) -> Text {
        switch state {
        case .alarm:     return Text("watch_headline_alarm")
        case .attention: return Text("watch_headline_attention")
        case .calm:      return open == 0 ? Text("watch_headline_clear") : Text("watch_headline_open \(open)")
        }
    }

    private func healthSentence(_ score: Int?) -> Text {
        guard let score else { return Text(verbatim: "") }
        return Text(verbatim: " ") + Text("watch_dial_health_ax \(score)")
    }

    /// A corner that opens Tasks or Plants on Today's stack — only when the
    /// section is visible — so the back button returns to Today.
    @ViewBuilder
    private func pageCorner(_ page: WatchPage, _ readout: CornerReadout<Text>) -> some View {
        if store.isVisible(page) {
            NavigationLink(value: WatchDestination.page(page)) {
                readout
            }
            .buttonStyle(.plain)
        } else {
            readout
        }
    }

    /// A corner that pushes a module on Today's stack — only when visible.
    @ViewBuilder
    private func moduleCorner(_ module: WatchModule, _ readout: CornerReadout<Text>) -> some View {
        if store.isVisible(module) {
            NavigationLink(value: WatchDestination.module(module)) {
                readout
            }
            .buttonStyle(.plain)
        } else {
            readout
        }
    }

    /// The running session (opens it), else the house streak, else nothing.
    @ViewBuilder
    private func sessionCorner(streak: Int?) -> some View {
        if let session = store.session {
            NavigationLink(value: WatchDestination.workSession) {
                CornerReadout(systemImage: session.isPaused ? "pause.circle" : "timer",
                              labelKey: "watch_session", tint: WatchTheme.Tint.session,
                              alignment: .trailing, isLive: !session.isPaused,
                              accessibilityValue: session.isPaused
                                ? Text("watch_session_paused")
                                : Text(verbatim: session.title)) {
                    SessionClockText(session: session, font: WatchTheme.Typography.numeralSmall)
                }
            }
            .buttonStyle(.plain)
        } else if let streak, streak >= 1 {
            CornerReadout(count: streak, systemImage: "flame", labelKey: "watch_data_streak",
                          tint: WatchTheme.Tint.streak, alignment: .trailing)
        } else {
            Color.clear
                .frame(width: WatchTheme.Size.rowIcon, height: WatchTheme.Size.rowIcon)
                .accessibilityHidden(true)
        }
    }

    // MARK: 2. Next Up / celebration

    @ViewBuilder
    private var focus: some View {
        let transition = WatchTheme.Motion.transition(reduceMotion: reduceMotion)
        if let serial = celebration {
            CelebrationView(serial: serial)
                .padding(.vertical, WatchTheme.Spacing.s)
                .id(serial)
                .transition(transition)
        } else if let next = store.nextUp {
            NextUpCard(next) { perform(next) }
                .id(next.id)
                .transition(transition)
        }
    }

    /// Next Up's one tap — the store intent plays the haptic (success).
    private func perform(_ next: WatchNextUp) {
        switch next {
        case .task(let task, _):    store.completeTask(task.id)
        case .plant(let plant):     store.waterPlant(plant.id)
        case .delivery(let parcel): store.markDeliveryReceived(parcel.id)
        }
    }

    // MARK: 3. The brief

    /// The phone's sentence when it shipped one; otherwise a local, warm
    /// one. The watch never waits for the phone's.
    private func brief(_ payload: WatchPayload) -> Text {
        if let shipped = payload.briefHeadline?.trimmingCharacters(in: .whitespacesAndNewlines),
           !shipped.isEmpty {
            return Text(verbatim: shipped)
        }
        switch store.householdState {
        case .alarm:
            return Text("watch_brief_alarm")
        case .attention, .calm:
            let open = store.openItemCount
            return open == 0 ? Text("watch_brief_clear") : Text("watch_brief_open \(open)")
        }
    }

    // MARK: 4. Contextual cards

    @ViewBuilder
    private func cards(_ payload: WatchPayload) -> some View {
        if let session = store.session {
            NavigationLink(value: WatchDestination.workSession) {
                SessionCard(session: session)
            }
            .buttonStyle(.plain)
            .watchScrollDepth()
            .watchEntrance(3)
        }

        if let temp = payload.weatherTemp, let symbol = payload.weatherSymbol {
            WeatherCard(temp: temp, symbol: symbol, low: payload.weatherLo,
                        high: payload.weatherHi, advisory: payload.weatherAdvisory)
                .watchScrollDepth()
                .watchEntrance(4)
        }

        if payload.snapshot.unreadMessages > 0 {
            unreadCard(payload.snapshot.unreadMessages)
                .watchScrollDepth()
                .watchEntrance(5)
        }

        if let title = payload.insightTitle, !title.isEmpty {
            InsightCard(title: title, message: payload.insightBody)
                .watchScrollDepth()
                .watchEntrance(6)
        }
    }

    @ViewBuilder
    private func unreadCard(_ count: Int) -> some View {
        let card = UnreadCard(count: count)
        if store.isVisible(.messages) {
            NavigationLink(value: WatchDestination.module(.messages)) { card }
                .buttonStyle(.plain)
        } else {
            card
        }
    }
}

// MARK: - Dial cluster layout

/// The dial with a readout in each corner. At accessibility text sizes the
/// corners would collide with the ring, so they move into a 2×2 grid under
/// it — nothing truncates.
private struct DialCluster<Dial: View, TL: View, TR: View, BL: View, BR: View>: View {
    let isStacked: Bool
    let dial: Dial
    let topLeading: TL
    let topTrailing: TR
    let bottomLeading: BL
    let bottomTrailing: BR

    init(isStacked: Bool,
         @ViewBuilder dial: () -> Dial,
         @ViewBuilder topLeading: () -> TL,
         @ViewBuilder topTrailing: () -> TR,
         @ViewBuilder bottomLeading: () -> BL,
         @ViewBuilder bottomTrailing: () -> BR) {
        self.isStacked = isStacked
        self.dial = dial()
        self.topLeading = topLeading()
        self.topTrailing = topTrailing()
        self.bottomLeading = bottomLeading()
        self.bottomTrailing = bottomTrailing()
    }

    var body: some View {
        if isStacked {
            VStack(spacing: WatchTheme.Spacing.m) {
                dial
                Grid(horizontalSpacing: WatchTheme.Spacing.l, verticalSpacing: WatchTheme.Spacing.m) {
                    GridRow {
                        topLeading.gridColumnAlignment(.leading)
                        topTrailing.gridColumnAlignment(.trailing)
                    }
                    GridRow {
                        bottomLeading
                        bottomTrailing
                    }
                }
            }
        } else {
            dial
                .frame(maxWidth: .infinity)
                .overlay(alignment: .topLeading) { topLeading }
                .overlay(alignment: .topTrailing) { topTrailing }
                .overlay(alignment: .bottomLeading) { bottomLeading }
                .overlay(alignment: .bottomTrailing) { bottomTrailing }
        }
    }
}

// MARK: - The brief

private struct BriefText: View {
    let text: Text

    var body: some View {
        text
            .font(WatchTheme.Typography.brief)
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, WatchTheme.Spacing.xs)
            .watchAlwaysOnDimmed()
    }
}

// MARK: - Cards

private struct SessionCard: View {
    let session: WatchWorkSession

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.session) {
            HStack(spacing: WatchTheme.Spacing.s) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "timer")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(WatchTheme.Tint.session)
                    // pulse = a live session.
                    .symbolEffect(.pulse, isActive: !session.isPaused && !reduceMotion && !isLuminanceReduced)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: session.title)
                        .font(WatchTheme.Typography.caption.weight(.medium))
                        .lineLimit(1)
                    SessionClockText(session: session, font: WatchTheme.Typography.clockInline)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(WatchTheme.Typography.captionStrong)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("watch_session_open"))
    }
}

/// Apple Weather at the property, with the garden advisory when there is
/// one — and the attribution the WeatherKit terms require.
private struct WeatherCard: View {
    let temp: Double
    let symbol: String
    let low: Double?
    let high: Double?
    let advisory: String?

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.weather) {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(Int(temp.rounded()))°")
                        .font(WatchTheme.Typography.temperature)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: temp.rounded()))
                    Spacer(minLength: 0)
                    if let low, let high {
                        Text(verbatim: "\(Int(low.rounded()))°–\(Int(high.rounded()))°")
                            .font(WatchTheme.Typography.numeralSmall)
                            .foregroundStyle(.secondary)
                    }
                }
                if let advisory, advisory == "frost" || advisory == "rain" {
                    StateLabel(advisory == "frost" ? "watch_adv_frost" : "watch_adv_rain",
                               systemImage: advisory == "frost" ? "snowflake" : "cloud.rain.fill",
                               tint: WatchTheme.Tint.warning)
                }
                // Required by the WeatherKit terms — must stay visible.
                Text(verbatim: " Apple Weather")
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct UnreadCard: View {
    let count: Int

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.messages) {
            HStack(spacing: WatchTheme.Spacing.s) {
                Image(systemName: "message.fill")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(WatchTheme.Tint.messages)
                    .accessibilityHidden(true)
                Text("watch_unread_count \(count)")
                    .font(WatchTheme.Typography.cardTitle)
                    .contentTransition(.numericText(value: Double(count)))
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // Messages aren't for whoever glances at a resting wrist.
        .watchPrivate()
    }
}

/// The phone's freshest insight, readable with the phone out of reach.
private struct InsightCard: View {
    let title: String
    let message: String?

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.insight) {
            HStack(alignment: .top, spacing: WatchTheme.Spacing.s) {
                Image(systemName: "sparkles")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(WatchTheme.Tint.insight)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: WatchTheme.Spacing.xxs) {
                    Text(verbatim: title)
                        .font(WatchTheme.Typography.cardTitle)
                        .lineLimit(2)
                    if let message, !message.isEmpty {
                        Text(verbatim: message)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // The household's private intelligence stays off a resting wrist.
        .watchPrivate()
    }
}

/// Trust is knowing how old the data is — stale information says so.
private struct UpdatedFooter: View {
    let date: Date

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.xs) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .accessibilityHidden(true)
            Text("watch_updated")
            Text(date, format: .relative(presentation: .named))
        }
        .font(WatchTheme.Typography.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, WatchTheme.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

/// Asks the phone for a fresh payload over the live channel.
private struct RefreshButton: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        Button {
            store.requestRefresh()
        } label: {
            if store.isRefreshing {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(store.isRefreshing)
        .accessibilityLabel(Text("watch_refresh"))
    }
}
