import Foundation
import RelevanceKit
import WidgetKit

// MARK: - Entry

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let domain: WatchDomainOption
    /// nil until the phone has pushed a payload (or after sign-out); faces
    /// then show their honest empty state.
    let payload: WatchPayload?
}

// MARK: - Shared timeline building

private enum ComplicationTimeline {
    static func placeholder(_ domain: WatchDomainOption) -> ComplicationEntry {
        ComplicationEntry(date: .now, domain: domain, payload: WatchPayload.complicationSample)
    }

    /// The face gallery gets sample shapes when nothing is cached yet; a real
    /// face never shows sample data.
    static func snapshot(_ domain: WatchDomainOption, isPreview: Bool) -> ComplicationEntry {
        let cached = ComplicationStore.payload()
        return ComplicationEntry(date: .now, domain: domain,
                                 payload: cached ?? (isPreview ? WatchPayload.complicationSample : nil))
    }

    /// One entry: everything a face shows is a count or a title that only
    /// changes when the phone pushes, and the watch app reloads timelines on
    /// every push.
    static func timeline(_ domain: WatchDomainOption) -> Timeline<ComplicationEntry> {
        let now = Date.now
        let entry = ComplicationEntry(date: now, domain: domain, payload: ComplicationStore.payload())
        return Timeline(entries: [entry],
                        policy: .after(now.addingTimeInterval(ComplicationTheme.refreshInterval)))
    }
}

// MARK: - Per-domain provider (static complications)

struct DomainTimelineProvider: TimelineProvider {
    let domain: WatchDomainOption

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationTimeline.placeholder(domain)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(ComplicationTimeline.snapshot(domain, isPreview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        completion(ComplicationTimeline.timeline(domain))
    }

    func relevance() async -> WidgetRelevance<Void> {
        let contexts = ComplicationRelevance.contexts(for: domain, payload: ComplicationStore.payload())
        return WidgetRelevance(contexts.map { WidgetRelevanceAttribute(context: $0) })
    }
}

// MARK: - Configurable provider (PRVIOWatchChoice)

struct ChoiceTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationTimeline.placeholder(.status)
    }

    func snapshot(for configuration: PRVIODomainConfigIntent, in context: Context) async -> ComplicationEntry {
        ComplicationTimeline.snapshot(configuration.domain, isPreview: context.isPreview)
    }

    func timeline(for configuration: PRVIODomainConfigIntent, in context: Context) async -> Timeline<ComplicationEntry> {
        ComplicationTimeline.timeline(configuration.domain)
    }

    /// Empty on purpose: since watchOS 26 an empty list makes the system
    /// offer its own configuration UI (edit the face → pick the domain),
    /// instead of a fixed menu of preconfigured copies.
    func recommendations() -> [AppIntentRecommendation<PRVIODomainConfigIntent>] {
        []
    }

    /// One clue set per domain, keyed by configuration, so the Smart Stack
    /// promotes whichever configured copy matters now.
    func relevance() async -> WidgetRelevance<PRVIODomainConfigIntent> {
        let payload = ComplicationStore.payload()
        var attributes: [WidgetRelevanceAttribute<PRVIODomainConfigIntent>] = []
        for domain in WatchDomainOption.allCases {
            let contexts = ComplicationRelevance.contexts(for: domain, payload: payload)
            guard !contexts.isEmpty else { continue }
            let configuration = PRVIODomainConfigIntent.showing(domain)
            attributes += contexts.map { WidgetRelevanceAttribute(configuration: configuration, context: $0) }
        }
        return WidgetRelevance(attributes)
    }
}
