import RelevanceKit
import SwiftUI
import WidgetKit

// MARK: - Work-session complication
//
// The wrist's maintenance timer on the face: the task title and a live
// elapsed clock while the session runs, the same clock frozen while it is
// paused, and an honest idle state otherwise. It reads the exact session the
// watch app persists (`prvio.watch.session`), and the app reloads timelines
// on every start, pause, resume and end, so the face never shows a timer that
// is not really running.

struct SessionEntry: TimelineEntry {
    let date: Date
    let session: WatchWorkSession?
}

struct SessionTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> SessionEntry {
        SessionEntry(date: .now, session: WatchWorkSession.complicationSample(at: .now))
    }

    func getSnapshot(in context: Context, completion: @escaping (SessionEntry) -> Void) {
        let now = Date.now
        let session = ComplicationStore.session() ?? (context.isPreview ? WatchWorkSession.complicationSample(at: now) : nil)
        completion(SessionEntry(date: now, session: session))
    }

    /// One entry: the running clock is system-driven timer text, so it ticks
    /// without new entries; the heartbeat only re-reads a missed transition.
    func getTimeline(in context: Context, completion: @escaping (Timeline<SessionEntry>) -> Void) {
        let now = Date.now
        let entry = SessionEntry(date: now, session: ComplicationStore.session())
        completion(Timeline(entries: [entry],
                            policy: .after(now.addingTimeInterval(ComplicationTheme.refreshInterval))))
    }

    func relevance() async -> WidgetRelevance<Void> {
        let contexts = ComplicationRelevance.sessionContexts(ComplicationStore.session())
        return WidgetRelevance(contexts.map { WidgetRelevanceAttribute(context: $0) })
    }
}

struct PRVIOSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: ComplicationKind.session, provider: SessionTimelineProvider()) { entry in
            SessionFace(session: entry.session, date: entry.date)
                .complicationBackground(.calm(entry.session?.isPaused == true
                                              ? ComplicationTheme.Tint.paused
                                              : ComplicationTheme.Tint.session))
        }
        .configurationDisplayName(Text("Work session"))
        .description(Text("watch_comp_session_desc"))
        .supportedFamilies(ComplicationTheme.families)
    }
}

// MARK: - Face

struct SessionFace: View {
    let session: WatchWorkSession?
    /// The entry date: elapsed time is computed against it, never against
    /// render time, so a paused clock stays exactly where it stopped.
    let date: Date

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private typealias Theme = ComplicationTheme

    /// Long enough for any real session; the timer stops counting after it.
    private static let timerSpan: TimeInterval = 24 * 3600

    var body: some View {
        face
            // Today carries the live session card.
            .widgetURL(ComplicationLink.today)
    }

    @ViewBuilder
    private var face: some View {
        switch family {
        case .accessoryCircular:    circular
        case .accessoryCorner:      corner
        case .accessoryRectangular: rectangular
        default:                    inline
        }
    }

    private func glyph(for session: WatchWorkSession) -> String {
        session.isPaused ? "pause.fill" : "timer"
    }

    /// One timer view for both states: running counts live from the true
    /// start (pauses excluded); paused passes `pauseTime`, which freezes the
    /// same readout at the elapsed time. Orange is a full-color extra — the
    /// pause glyph or label always states the pause.
    private func clock(_ session: WatchWorkSession, font: Font) -> some View {
        let start = date.addingTimeInterval(-session.elapsed(at: date))
        return Text(timerInterval: start...start.addingTimeInterval(Self.timerSpan),
                    pauseTime: session.isPaused ? date : nil,
                    countsDown: false)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(renderingMode.emphasis(session.isPaused, color: Theme.Tint.paused))
            .widgetAccentable()
    }

    @ViewBuilder
    private var circular: some View {
        if let session {
            VStack(spacing: 0) {
                Image(systemName: glyph(for: session))
                    .font(Theme.Typography.glyph)
                    .symbolRenderingMode(.hierarchical)
                    .widgetAccentable()
                    .accessibilityLabel(session.isPaused ? Text("watch_session_paused") : Text("Work session"))
                clock(session, font: Theme.Typography.circularCompact)
                    .lineLimit(1)
                    .minimumScaleFactor(Theme.compactMinimumScale)
            }
            .accessibilityElement(children: .combine)
        } else {
            VStack(spacing: 0) {
                Image(systemName: "timer")
                    .font(Theme.Typography.glyph)
                    .accessibilityHidden(true)
                Text(verbatim: "–")
                    .font(Theme.Typography.circularValue)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("watch_session_none"))
            }
        }
    }

    @ViewBuilder
    private var corner: some View {
        if let session {
            clock(session, font: Theme.Typography.cornerValue)
                .widgetCurvesContent()
                .widgetLabel {
                    if session.isPaused {
                        Text("watch_session_paused")
                    } else {
                        Text(verbatim: session.title)
                    }
                }
        } else {
            Image(systemName: "timer")
                .font(Theme.Typography.cornerValue)
                .foregroundStyle(.secondary)
                .widgetLabel { Text("watch_session_none") }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let session {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: glyph(for: session))
                        .font(Theme.Typography.glyph)
                        .widgetAccentable()
                        .accessibilityHidden(true)
                    Text(verbatim: session.title)
                        .font(Theme.Typography.header)
                        .lineLimit(1)
                }
                clock(session, font: Theme.Typography.metric)
                    .lineLimit(1)
                if session.isPaused {
                    Text("watch_session_paused")
                        .font(Theme.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(session.startedAt, style: .time)
                        .font(Theme.Typography.detail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: "timer")
                        .font(Theme.Typography.glyph)
                        .accessibilityHidden(true)
                    Text("Work session")
                        .font(Theme.Typography.header)
                        .lineLimit(1)
                }
                Text("watch_session_none")
                    .font(Theme.Typography.detail)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let session {
            Label {
                clock(session, font: .body)
            } icon: {
                Image(systemName: glyph(for: session))
            }
        } else {
            Text("watch_session_none")
        }
    }
}

// MARK: - Gallery sample

private extension WatchWorkSession {
    /// A running 25-minute session for placeholders and the face gallery.
    static func complicationSample(at now: Date) -> WatchWorkSession {
        let start = now.addingTimeInterval(-25 * 60)
        return WatchWorkSession(taskId: UUID(), title: String(localized: "Work session"),
                                startedAt: start, accumulated: 0, segmentStart: start)
    }
}
