import Foundation
import RelevanceKit
import WidgetKit

// MARK: - Smart Stack relevance
//
// Clues that tell watchOS WHEN a PRVIO card earns a place at the top of the
// Smart Stack — derived only from the cached payload, so they are honest and
// offline. Kinds follow RelevanceKit's meaning: `.scheduled` when the card
// asks for an action now, `.default` for a useful routine moment,
// `.informational` when it only informs.
//
// Health and Budget never volunteer themselves: health is a slow signal, and
// spending is private — it appears only where its owner placed it.

enum ComplicationRelevance {
    static func contexts(for domain: WatchDomainOption,
                         payload: WatchPayload?,
                         now: Date = .now,
                         calendar: Calendar = .current) -> [RelevantContext] {
        guard let payload else { return [] }
        let day = DayWindows(now: now, calendar: calendar)

        switch domain {
        case .tasks:
            if payload.hasOverdueTasks {
                return [.date(interval: day.fromNow(hours: 2), kind: .scheduled)]
            }
            guard payload.snapshot.openTaskCount > 0 else { return [] }
            return day.windows(fromHour: 8, toHour: 10, days: 0...1)
                .map { RelevantContext.date(interval: $0, kind: .default) }

        case .status:
            // The tasks card owns the urgent slot; the overview only offers
            // itself as the morning summary when something is open.
            guard payload.snapshot.openTaskCount > 0 || payload.snapshot.plantsNeedingWater > 0 else { return [] }
            return day.windows(fromHour: 7, toHour: 9, days: 0...1)
                .map { RelevantContext.date(interval: $0, kind: .informational) }

        case .water:
            guard payload.snapshot.plantsNeedingWater > 0 else { return [] }
            // Rain is forecast: watering can wait, so the card informs
            // instead of asking.
            let kind: RelevantContext.DateKind = payload.weatherAdvisory == "rain" ? .informational : .scheduled
            var contexts = day.windows(fromHour: 7, toHour: 10, days: 0...1)
                .map { RelevantContext.date(interval: $0, kind: kind) }
            if let evening = day.window(dayOffset: 0, fromHour: 18, toHour: 20) {
                contexts.append(.date(interval: evening, kind: .default))
            }
            return contexts

        case .shopping:
            guard payload.snapshot.pendingSupplyCount > 0 else { return [] }
            var contexts: [RelevantContext] = []
            if let afterWork = day.window(dayOffset: 0, fromHour: 17, toHour: 19) {
                contexts.append(.date(interval: afterWork, kind: .informational))
            }
            // Saturday (weekday 7 in the Gregorian numbering Calendar uses).
            if let saturday = day.nextWeekday(7, fromHour: 9, toHour: 12) {
                contexts.append(.date(interval: saturday, kind: .default))
            }
            return contexts

        case .deliveries:
            if payload.deliveries.contains(where: { $0.status == "out_for_delivery" }),
               let rest = day.window(dayOffset: 0, fromHour: 0, toHour: 21) {
                return [.date(interval: rest, kind: .scheduled)]
            }
            if payload.deliveries.contains(where: { $0.status == "expected" }),
               let daytime = day.window(dayOffset: 0, fromHour: 8, toHour: 21) {
                return [.date(interval: daytime, kind: .informational)]
            }
            return []

        case .weather:
            var contexts: [RelevantContext] = []
            if payload.weatherAdvisory != nil {
                contexts.append(.date(interval: day.fromNow(hours: 6), kind: .scheduled))
            }
            if payload.weatherTemp != nil {
                contexts += day.windows(fromHour: 7, toHour: 9, days: 0...1)
                    .map { RelevantContext.date(interval: $0, kind: .informational) }
            }
            return contexts

        case .health, .budget:
            return []
        }
    }

    /// A running session asks to stay in view; a paused one is a reminder
    /// that work is open, at default priority.
    static func sessionContexts(_ session: WatchWorkSession?, now: Date = .now) -> [RelevantContext] {
        guard let session else { return [] }
        let span: TimeInterval = session.isPaused ? 3600 : 4 * 3600
        return [.date(interval: DateInterval(start: now, duration: span),
                      kind: session.isPaused ? .default : .scheduled)]
    }
}

// MARK: - "Now at home" clues
//
// The card earns its place only in four moments, returned in priority order
// (the system may keep just the first few):
//   1. a work session is running (paused: a gentle reminder for an hour),
//   2. a parcel is out for delivery (until 21:00 today),
//   3. the morning watering window (07–10, today and tomorrow) while a plant
//      is thirsty — skipped when rain is forecast, since watering can wait,
//   4. the evening return home (17–20) while something is due now.
// Nothing matches → no clue at all, and the card stays away.
//
// Arrival at home is approximated by the evening window. A real
// `.location(inferred: .home)` clue needs When-in-Use location permission
// granted to the watch app (and extended to this extension); the app does
// not request it, so a location clue would never match. Add it ahead of the
// evening window once the app asks for that permission.

enum NowRelevance {
    static func attributes(payload: WatchPayload?,
                           session: WatchWorkSession?,
                           now: Date = .now,
                           calendar: Calendar = .current) -> [WidgetRelevanceAttribute<PRVIONowIntent>] {
        let day = DayWindows(now: now, calendar: calendar)
        var result: [WidgetRelevanceAttribute<PRVIONowIntent>] = []

        func add(_ moment: NowMoment, _ contexts: [RelevantContext]) {
            let configuration = PRVIONowIntent.showing(moment)
            result += contexts.map { WidgetRelevanceAttribute(configuration: configuration, context: $0) }
        }

        add(.session, ComplicationRelevance.sessionContexts(session, now: now))

        guard let payload else { return result }

        if payload.showsDeliveries, !payload.outForDelivery.isEmpty,
           let rest = day.window(dayOffset: 0, fromHour: 0, toHour: 21) {
            add(.delivery, [.date(interval: rest, kind: .scheduled)])
        }

        if payload.showsPlants, payload.firstThirstyPlant != nil, payload.weatherAdvisory != "rain" {
            add(.watering, day.windows(fromHour: 7, toHour: 10, days: 0...1)
                .map { RelevantContext.date(interval: $0, kind: .scheduled) })
        }

        if ComplicationHousehold.attentionCount(payload) > 0 {
            add(.homecoming, day.windows(fromHour: 17, toHour: 20, days: 0...1)
                .map { RelevantContext.date(interval: $0, kind: .default) })
        }
        return result
    }
}

// MARK: - Local-time windows

private struct DayWindows {
    let now: Date
    let calendar: Calendar

    func fromNow(hours: Double) -> DateInterval {
        DateInterval(start: now, duration: hours * 3600)
    }

    /// `startHour`–`endHour` local time, `dayOffset` days from today, clipped
    /// to start no earlier than now; nil once the window has passed.
    func window(dayOffset: Int, fromHour startHour: Int, toHour endHour: Int) -> DateInterval? {
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: now),
              let start = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: day),
              let end = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: day),
              end > now else { return nil }
        return DateInterval(start: max(start, now), end: end)
    }

    func windows(fromHour startHour: Int, toHour endHour: Int, days: ClosedRange<Int>) -> [DateInterval] {
        days.compactMap { window(dayOffset: $0, fromHour: startHour, toHour: endHour) }
    }

    /// The next not-yet-passed window on `weekday` (1 = Sunday … 7 = Saturday).
    func nextWeekday(_ weekday: Int, fromHour startHour: Int, toHour endHour: Int) -> DateInterval? {
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  calendar.component(.weekday, from: day) == weekday else { continue }
            if let interval = window(dayOffset: offset, fromHour: startHour, toHour: endHour) {
                return interval
            }
        }
        return nil
    }
}
