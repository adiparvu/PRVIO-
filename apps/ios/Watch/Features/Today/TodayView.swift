import SwiftUI

// MARK: - Today: the glance
//
// "What needs me now?" in one look: the property's health and streak, four
// counts, then only the cards that have something to say. Tiles act only
// when their destination is visible — a tile never points at a page the
// pager does not have.

struct TodayView: View {
    @Binding var selection: WatchPage
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let payload = store.payload {
            content(payload)
        } else {
            AllClearView(systemImage: "iphone.and.arrow.forward", messageKey: "watch_waiting_msg")
        }
    }

    private func content(_ payload: WatchPayload) -> some View {
        let snapshot = payload.snapshot
        return ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.Spacing.m) {
                TodayHero(payload: payload)
                    .watchEntrance(0)

                metrics(snapshot)

                if let session = store.session {
                    NavigationLink(value: WatchDestination.workSession) {
                        SessionCard(session: session)
                    }
                    .buttonStyle(.plain)
                    .watchEntrance(1)
                }

                if let temp = payload.weatherTemp, let symbol = payload.weatherSymbol {
                    WeatherCard(temp: temp, symbol: symbol, low: payload.weatherLo,
                                high: payload.weatherHi, advisory: payload.weatherAdvisory)
                        .watchEntrance(5)
                }

                if snapshot.unreadMessages > 0 {
                    unreadCard(snapshot.unreadMessages)
                        .watchEntrance(6)
                }

                if let title = payload.insightTitle, !title.isEmpty {
                    InsightCard(title: title, message: payload.insightBody)
                        .watchEntrance(7)
                }

                focusCard(snapshot)
                    .watchEntrance(8)

                UpdatedFooter(date: snapshot.updatedAt)
            }
        }
        .navigationTitle(Text(verbatim: "PRVIO"))
        .watchPageGround(WatchTheme.Tint.today)
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
    }

    // MARK: Metrics (2×2)

    private func metrics(_ snapshot: PRVIOWidgetSnapshot) -> some View {
        Grid(horizontalSpacing: WatchTheme.Spacing.m, verticalSpacing: WatchTheme.Spacing.m) {
            GridRow {
                pageTile(.tasks,
                         tile: MetricTile(count: snapshot.openTaskCount, titleKey: "watch_open",
                                          systemImage: "checklist", tint: WatchTheme.Tint.tasks,
                                          isUrgent: snapshot.overdueTaskCount > 0))
                    .watchEntrance(1)
                pageTile(.plants,
                         tile: MetricTile(count: snapshot.plantsNeedingWater, titleKey: "watch_water",
                                          systemImage: "drop.fill", tint: WatchTheme.Tint.water))
                    .watchEntrance(2)
            }
            GridRow {
                moduleTile(.deliveries,
                           tile: MetricTile(count: snapshot.activeDeliveryCount, titleKey: "watch_deliveries",
                                            systemImage: "shippingbox.fill", tint: WatchTheme.Tint.deliveries))
                    .watchEntrance(3)
                moduleTile(.shopping,
                           tile: MetricTile(count: snapshot.pendingSupplyCount, titleKey: "watch_shopping",
                                            systemImage: "cart.fill", tint: WatchTheme.Tint.shopping))
                    .watchEntrance(4)
            }
        }
    }

    /// Selects a pager page — only when the pager has it.
    @ViewBuilder
    private func pageTile(_ page: WatchPage, tile: MetricTile) -> some View {
        if store.isVisible(page) {
            Button {
                selection = page
            } label: {
                tile
            }
            .buttonStyle(.plain)
        } else {
            tile
        }
    }

    /// Pushes a hub module on Today's stack — only when it is visible.
    @ViewBuilder
    private func moduleTile(_ module: WatchModule, tile: MetricTile) -> some View {
        if store.isVisible(module) {
            NavigationLink(value: WatchDestination.module(module)) {
                tile
            }
            .buttonStyle(.plain)
        } else {
            tile
        }
    }

    // MARK: Cards

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

    @ViewBuilder
    private func focusCard(_ snapshot: PRVIOWidgetSnapshot) -> some View {
        if let critical = snapshot.criticalTaskTitle, !critical.isEmpty {
            FocusCard(systemImage: "exclamationmark.circle.fill", tint: WatchTheme.Tint.critical,
                      title: critical, detail: nil)
        } else if let next = snapshot.nextMaintenanceTitle, !next.isEmpty {
            FocusCard(systemImage: "wrench.and.screwdriver.fill", tint: WatchTheme.Tint.neutral,
                      title: next, detail: snapshot.nextMaintenanceDue)
        }
    }
}

// MARK: - Hero

private struct TodayHero: View {
    let payload: WatchPayload

    var body: some View {
        HStack(spacing: WatchTheme.Spacing.l) {
            if let score = payload.snapshot.propertyHealthScore {
                HealthRing(score: score)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: payload.snapshot.propertyName ?? "PRVIO")
                    .font(WatchTheme.Typography.hero)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if let streak = payload.streakDays, streak >= 2 {
                    // Consecutive verified all-clear days, computed on the phone.
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill")
                            .font(WatchTheme.Typography.captionStrong)
                            .symbolEffect(.bounce, value: streak)
                        Text(verbatim: String(format: String(localized: "watch_streak"), streak))
                            .font(Font.system(.caption2, design: .rounded).weight(.semibold))
                            .contentTransition(.numericText())
                    }
                    .foregroundStyle(WatchTheme.Tint.streak)
                    .accessibilityElement(children: .combine)
                } else if payload.snapshot.propertyHealthScore != nil {
                    Text("watch_health")
                        .font(WatchTheme.Typography.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, WatchTheme.Spacing.xxs)
    }
}

// MARK: - Cards

private struct SessionCard: View {
    let session: WatchWorkSession

    var body: some View {
        WatchCard(tint: WatchTheme.Tint.session) {
            HStack(spacing: WatchTheme.Spacing.s) {
                Image(systemName: session.isPaused ? "pause.circle.fill" : "timer")
                    .font(WatchTheme.Typography.glyph)
                    .foregroundStyle(WatchTheme.Tint.session)
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
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: WatchTheme.Spacing.s) {
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .symbolRenderingMode(.multicolor)
                        .accessibilityHidden(true)
                    Text(verbatim: "\(Int(temp.rounded()))°")
                        .font(WatchTheme.Typography.temperature)
                        .contentTransition(.numericText())
                    Spacer(minLength: 0)
                    if let low, let high {
                        Text(verbatim: "\(Int(low.rounded()))°–\(Int(high.rounded()))°")
                            .font(Font.system(.caption, design: .rounded).weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                if let advisory, advisory == "frost" || advisory == "rain" {
                    HStack(spacing: WatchTheme.Spacing.xs) {
                        Image(systemName: advisory == "frost" ? "snowflake" : "cloud.rain.fill")
                            .font(WatchTheme.Typography.captionStrong)
                        Text(advisory == "frost" ? "watch_adv_frost" : "watch_adv_rain")
                            .font(WatchTheme.Typography.caption.weight(.medium))
                            .lineLimit(2)
                    }
                    .foregroundStyle(WatchTheme.Tint.warning)
                }
                // Required by the WeatherKit terms — must stay visible.
                Text(verbatim: " Apple Weather")
                    .font(WatchTheme.Typography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
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
                Text(verbatim: "\(count)")
                    .font(WatchTheme.Typography.clockInline)
                    .contentTransition(.numericText())
                Text("watch_unread")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        // Messages aren't for whoever glances at a resting wrist.
        .privacySensitive()
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
        .privacySensitive()
    }
}

private struct FocusCard: View {
    let systemImage: String
    let tint: Color
    let title: String
    let detail: String?

    var body: some View {
        WatchCard(tint: tint) {
            HStack(spacing: WatchTheme.Spacing.s) {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint == WatchTheme.Tint.neutral ? Color.secondary : tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: title)
                        .font(WatchTheme.Typography.body)
                        .lineLimit(2)
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(WatchTheme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .privacySensitive()
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
