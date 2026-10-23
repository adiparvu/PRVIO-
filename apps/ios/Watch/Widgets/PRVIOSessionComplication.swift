import WidgetKit
import SwiftUI

// MARK: - Work-session complication
//
// The wrist's maintenance timer, on the face: task title + live elapsed time
// while a session runs, the frozen clock in orange while it's paused, and an
// honest idle state otherwise. It reads the exact session the watch app
// persists in the App Group (SharedDataStore.readWatchWorkSession), and the
// app reloads timelines on every start/pause/resume/end — so the face never
// shows a timer that isn't really running.
//
// NOTE: deliberately no RelevanceKit here. The extension links that framework
// weakly for watchOS 10 (Series 4/5), and an `import RelevanceKit` in any file
// would re-embed a strong autolink hint — see OTHER_SWIFT_FLAGS in project.yml.

struct WatchSessionEntry: TimelineEntry {
    let date: Date
    let session: WatchWorkSession?
}

struct WatchSessionProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchSessionEntry {
        WatchSessionEntry(date: .now, session: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchSessionEntry) -> Void) {
        completion(WatchSessionEntry(date: .now, session: SharedDataStore.readWatchWorkSession()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchSessionEntry>) -> Void) {
        // The watch app reloads timelines on every session transition; the
        // hourly cadence is only the fallback heartbeat (running elapsed is
        // system-driven timer text, so it ticks without new entries).
        let entry = WatchSessionEntry(date: .now, session: SharedDataStore.readWatchWorkSession())
        completion(Timeline(entries: [entry],
                            policy: .after(.now.addingTimeInterval(3600))))
    }
}

struct PRVIOSessionComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PRVIOWatchSession",
                            provider: WatchSessionProvider()) { entry in
            SessionComplicationView(session: entry.session)
                .modifier(ComplicationBackground())
        }
        .configurationDisplayName("PRVIO · Session")
        .description(NSLocalizedString("watch_comp_session_desc", comment: ""))
        .supportedFamilies([.accessoryCircular, .accessoryCorner,
                            .accessoryRectangular, .accessoryInline])
    }
}

private struct SessionComplicationView: View {
    let session: WatchWorkSession?

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    /// The moment the timer text counts from: now minus the true elapsed
    /// (pauses excluded), so system timer text and the app's clock agree.
    private var timerStart: Date? {
        session.map { Date(timeIntervalSinceNow: -$0.elapsed(at: .now)) }
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                circular
            case .accessoryCorner:
                corner
            case .accessoryRectangular:
                rectangular
            default:
                inline
            }
        }
        // Tapping opens the app; Today carries the live session card.
        .widgetURL(URL(string: "prvio://"))
    }

    /// Live elapsed for running sessions (system-driven, ticks on its own),
    /// frozen orange clock while paused. Orange only in full color: accented
    /// faces tint the accent group, and the pause glyph carries the state.
    @ViewBuilder
    private func elapsedText(size: CGFloat) -> some View {
        if let session, let start = timerStart {
            if session.isPaused {
                Text(verbatim: session.clockText(at: .now))
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(renderingMode == .fullColor
                                     ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .widgetAccentable()
            } else {
                Text(timerInterval: start...start.addingTimeInterval(24 * 3600),
                     countsDown: false)
                    .font(.system(size: size, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .widgetAccentable()
            }
        }
    }

    private var circular: some View {
        VStack(spacing: 0) {
            Image(systemName: session == nil ? "timer"
                  : (session?.isPaused == true ? "pause.fill" : "timer"))
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .widgetAccentable()
            if session != nil {
                // 13 pt × 0.85 keeps even an hour-long readout at the
                // 11 pt widget-text floor (0.6 dropped it to ~8 pt).
                elapsedText(size: 13)
                    .minimumScaleFactor(0.85)
                    .lineLimit(1)
            } else {
                Text(verbatim: "–")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var corner: some View {
        if let session {
            elapsedText(size: 18)
                .widgetCurvesContent()
                .widgetLabel { Text(session.title) }
        } else {
            Image(systemName: "timer")
                .font(.system(.title3, weight: .semibold))
                .foregroundStyle(.secondary)
                .widgetLabel { Text("watch_session_none") }
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let session {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: session.isPaused ? "pause.fill" : "timer")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(session.isPaused ? .orange : .teal)
                        .widgetAccentable()
                    Text(session.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
                elapsedText(size: 20)
                Text(session.startedAt, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11, weight: .semibold))
                    Text(verbatim: "PRVIO")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text("watch_session_none")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var inline: some View {
        if let session {
            HStack(spacing: 3) {
                Image(systemName: "timer")
                elapsedText(size: 15)
                Text(session.title)
            }
        } else {
            Text("watch_session_none")
        }
    }
}
