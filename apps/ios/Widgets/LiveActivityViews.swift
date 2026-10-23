import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - PRVIO Live Activities
//
// Every activity composes IslandKit (IslandKit.swift): one icon language, one
// metric style, one lock card — themed by the canonical LiveActivityKind.
// Appearance preferences are applied through the LA gates at render time; the
// system re-renders on each content update.

// MARK: - Interactive action buttons
//
// Every button runs a LiveActivityIntent in the app's process; the action is a
// REAL mutation queued through the App Group (see LiveActivityActionIntents),
// and the island updates the moment the intent ends/updates the activity. Sized
// for a full-width tap target and legible in the island and on the Lock Screen;
// they inherit the system's Reduce Motion handling.

private struct ShoppingCheckButton: View {
    let itemId: UUID
    let name: String?

    var body: some View {
        Button(intent: CheckNextShoppingItemIntent(itemId: itemId)) {
            Label {
                if let name { Text(verbatim: name).lineLimit(1) }
                else { Text("la_shopping_check") }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(AppFont.captionStrong)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(LiveActivityKind.shopping.color)
        .accessibilityLabel(Text("la_shopping_check"))
    }
}

private struct PlantWaterButton: View {
    var body: some View {
        Button(intent: WaterNextPlantIntent()) {
            Label("la_plant_water", systemImage: "drop.fill")
                .font(AppFont.captionStrong)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(LiveActivityKind.plantCare.color)
    }
}

private struct DeliveryReceivedButton: View {
    let deliveryId: UUID

    var body: some View {
        Button(intent: MarkDeliveryReceivedIntent(deliveryId: deliveryId)) {
            Label("la_delivery_received", systemImage: "checkmark.circle.fill")
                .font(AppFont.captionStrong)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(LiveActivityKind.delivery.color)
    }
}

private struct MaintenanceDoneButton: View {
    let taskId: UUID

    var body: some View {
        Button(intent: CompleteMaintenanceTaskIntent(taskId: taskId)) {
            Label("la_maintenance_done", systemImage: "checkmark.circle.fill")
                .font(AppFont.captionStrong)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(LiveActivityKind.maintenance.color)
    }
}

// MARK: - Shopping

struct ShoppingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        // The widget extension targets iOS 18 precisely so every activity can
        // declare the Apple Watch Smart Stack presentation unconditionally
        // (Widget.body has no result builder, so this can't be
        // #available-gated at a lower target).
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: ShoppingActivityAttributes.self) { context in
            ActivityFamilyGate {
                ShoppingActivitySmallView(context: context)
            } full: {
                ShoppingLockView(context: context)
            }
            .widgetURL(LiveActivityKind.shopping.deepLink)
        } dynamicIsland: { context in
            let bought = context.state.itemsBought
            let total = context.state.totalItems
            let done = total > 0 && bought >= total
            let progress = total > 0 ? Double(bought) / Double(total) : 0
            let countText = Text(verbatim: "\(bought)/\(total)")
            let countLabel = Text(String(format: String(localized: "%d of %d items"), bought, total))

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .shopping, title: Text(context.attributes.listName), isComplete: done)
                        .widgetURL(LiveActivityKind.shopping.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.shopping) {
                        IslandMetric(countText, size: .expanded)
                            .accessibilityLabel(countLabel)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.shopping) {
                        VStack(spacing: AppSpacing.xs) {
                            if LA.progress(.shopping) {
                                IslandProgressBar(value: progress, tint: LiveActivityKind.shopping.color)
                            }
                            HStack {
                                countLabel
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                if done {
                                    Text("Complete! 🎉")
                                        .font(AppFont.captionStrong)
                                        .foregroundStyle(Color.brandSuccess)
                                }
                            }
                            if !done, let nextId = context.state.nextItemId {
                                ShoppingCheckButton(itemId: nextId, name: context.state.nextItemName)
                                    .transition(.blurReplace)
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandCompactLeading(kind: .shopping, progress: progress,
                                     tint: done ? .brandSuccess : LiveActivityKind.shopping.color,
                                     value: countLabel) {
                    IslandStateIcon(kind: .shopping, isComplete: done)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.shopping.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .shopping) {
                    IslandMetric(countText)
                        .accessibilityLabel(countLabel)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .shopping, isComplete: done)
                        .accessibilityLabel(Text(LiveActivityKind.shopping.title))
                }
            }
        }
    }
}

private struct ShoppingActivitySmallView: View {
    let context: ActivityViewContext<ShoppingActivityAttributes>

    var body: some View {
        let bought = context.state.itemsBought
        let total = context.state.totalItems
        let done = total > 0 && bought >= total
        SmallStackCard(title: Text(context.attributes.listName),
                       progress: total > 0 ? Double(bought) / Double(total) : 0,
                       progressTint: done ? .brandSuccess : LiveActivityKind.shopping.color) {
            IslandStateIcon(kind: .shopping, isComplete: done)
        } trailing: {
            IslandMetric(Text(verbatim: "\(bought)/\(total)"),
                         tint: done ? .brandSuccess : LiveActivityKind.shopping.color,
                         size: .expanded)
                .accessibilityLabel(Text(String(format: String(localized: "%d of %d items"), bought, total)))
        }
    }
}

private struct ShoppingLockView: View {
    let context: ActivityViewContext<ShoppingActivityAttributes>

    private var progress: Double {
        context.state.totalItems > 0
            ? Double(context.state.itemsBought) / Double(context.state.totalItems)
            : 0
    }
    private var isComplete: Bool {
        context.state.totalItems > 0 && context.state.itemsBought >= context.state.totalItems
    }

    var body: some View {
        if LA.lockDetails(.shopping) {
            VStack(spacing: 0) {
                IslandLockCard(kind: .shopping,
                               title: Text(context.attributes.listName),
                               isComplete: isComplete) {
                    if LA.progress(.shopping) {
                        IslandProgressBar(value: progress, tint: LiveActivityKind.shopping.color)
                    }
                    IslandContextLine(kind: .shopping,
                                      text: Text(String(format: String(localized: "%d of %d items"),
                                                        context.state.itemsBought, context.state.totalItems)),
                                      propertyName: context.attributes.propertyName)
                } trailing: {
                    IslandMetric(Text(verbatim: "\(Int(progress * 100))%"),
                                 tint: isComplete ? .brandSuccess : LiveActivityKind.shopping.color,
                                 size: .hero)
                }
                if !isComplete, let nextId = context.state.nextItemId {
                    ShoppingCheckButton(itemId: nextId, name: context.state.nextItemName)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.lg)
                        .transition(.blurReplace)
                }
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .shopping, title: Text(context.attributes.listName), isComplete: isComplete)
        }
    }
}

// MARK: - Maintenance

struct MaintenanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: MaintenanceActivityAttributes.self) { context in
            ActivityFamilyGate {
                MaintenanceActivitySmallView(context: context)
            } full: {
                MaintenanceLockView(context: context)
            }
            .widgetURL(LiveActivityKind.maintenance.deepLink)
        } dynamicIsland: { context in
            let done = context.state.isComplete
            let percentText = Text(verbatim: "\(Int(context.state.progress * 100))%")

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .maintenance, title: Text(context.attributes.taskTitle), isComplete: done)
                        .widgetURL(LiveActivityKind.maintenance.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.maintenance) {
                        IslandMetric(percentText,
                                     tint: done ? .brandSuccess : LiveActivityKind.maintenance.color,
                                     size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.maintenance) {
                        VStack(spacing: AppSpacing.xxs) {
                            if LA.progress(.maintenance) {
                                IslandProgressBar(value: context.state.progress,
                                                  tint: LiveActivityKind.maintenance.color)
                            }
                            HStack(spacing: AppSpacing.xs) {
                                Text(context.state.stepDescription)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if !context.attributes.category.isEmpty {
                                    Spacer(minLength: AppSpacing.xs)
                                    Text(context.attributes.category)
                                        .font(AppFont.caption2)
                                        .foregroundStyle(LiveActivityKind.maintenance.color)
                                        .lineLimit(1)
                                }
                            }
                            if !done, let taskId = context.attributes.taskId {
                                MaintenanceDoneButton(taskId: taskId)
                                    .transition(.blurReplace)
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandCompactLeading(kind: .maintenance, progress: context.state.progress,
                                     tint: done ? .brandSuccess : LiveActivityKind.maintenance.color,
                                     value: percentText) {
                    IslandStateIcon(kind: .maintenance, isComplete: done)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.maintenance.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .maintenance) {
                    IslandMetric(percentText)
                        .accessibilityLabel(Text(context.state.stepDescription))
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .maintenance, isComplete: done)
                        .accessibilityLabel(Text(LiveActivityKind.maintenance.title))
                }
            }
        }
    }
}

private struct MaintenanceActivitySmallView: View {
    let context: ActivityViewContext<MaintenanceActivityAttributes>

    var body: some View {
        let done = context.state.isComplete
        SmallStackCard(title: Text(context.attributes.taskTitle),
                       detail: Text(context.state.stepDescription),
                       progress: context.state.progress,
                       progressTint: done ? .brandSuccess : LiveActivityKind.maintenance.color) {
            IslandStateIcon(kind: .maintenance, isComplete: done)
        } trailing: {
            IslandMetric(Text(verbatim: "\(Int(context.state.progress * 100))%"),
                         tint: done ? .brandSuccess : LiveActivityKind.maintenance.color,
                         size: .expanded)
        }
    }
}

private struct MaintenanceLockView: View {
    let context: ActivityViewContext<MaintenanceActivityAttributes>

    var body: some View {
        if LA.lockDetails(.maintenance) {
            VStack(spacing: 0) {
                IslandLockCard(kind: .maintenance,
                               title: Text(context.attributes.taskTitle),
                               isComplete: context.state.isComplete) {
                    if LA.progress(.maintenance) {
                        IslandProgressBar(value: context.state.progress,
                                          tint: LiveActivityKind.maintenance.color)
                    }
                    IslandContextLine(kind: .maintenance,
                                      text: Text(context.state.stepDescription),
                                      propertyName: context.attributes.propertyName)
                } trailing: {
                    IslandMetric(Text(verbatim: "\(Int(context.state.progress * 100))%"),
                                 tint: context.state.isComplete ? .brandSuccess : LiveActivityKind.maintenance.color,
                                 size: .hero)
                }
                if !context.state.isComplete, let taskId = context.attributes.taskId {
                    MaintenanceDoneButton(taskId: taskId)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.lg)
                        .transition(.blurReplace)
                }
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .maintenance,
                           title: Text(context.attributes.taskTitle),
                           isComplete: context.state.isComplete)
        }
    }
}

// MARK: - Work session
//
// The system counts the elapsed time from the fixed start date (no content
// updates while it runs), and the buttons run as LiveActivityIntents in the
// app's process — completing really completes.

struct WorkSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: WorkSessionActivityAttributes.self) { context in
            ActivityFamilyGate {
                WorkSessionActivitySmallView(context: context)
            } full: {
                WorkSessionLockView(context: context)
            }
            .widgetURL(LiveActivityKind.workSession.deepLink)
        } dynamicIsland: { context in
            let done = context.state.isComplete
            let timer = Text(context.attributes.startedAt, style: .timer)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .workSession, title: Text(context.attributes.taskTitle), isComplete: done)
                        .widgetURL(LiveActivityKind.workSession.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.workSession) {
                        IslandMetric(timer,
                                     tint: done ? .brandSuccess : LiveActivityKind.workSession.color,
                                     size: .expanded)
                            .frame(maxWidth: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.workSession), !done {
                        HStack(spacing: AppSpacing.sm + 2) {
                            Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                                Label("la_session_complete", systemImage: "checkmark.circle.fill")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(LiveActivityKind.workSession.color)
                            Button(intent: EndWorkSessionIntent()) {
                                Text("la_session_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                        }
                        .transition(.blurReplace)
                    }
                }
            } compactLeading: {
                // A running timer can't fit 28pt; limited width keeps the glyph
                // and moves the elapsed time to VoiceOver.
                IslandCompactLeading(kind: .workSession, value: timer) {
                    IslandStateIcon(kind: .workSession, isComplete: done)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.workSession.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .workSession) {
                    IslandMetric(timer, tint: done ? .brandSuccess : LiveActivityKind.workSession.color)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .workSession, isComplete: done)
                        .accessibilityLabel(Text(LiveActivityKind.workSession.title))
                }
            }
        }
    }
}

private struct WorkSessionActivitySmallView: View {
    let context: ActivityViewContext<WorkSessionActivityAttributes>

    var body: some View {
        let done = context.state.isComplete
        SmallStackCard(title: Text(context.attributes.taskTitle)) {
            IslandStateIcon(kind: .workSession, isComplete: done)
        } trailing: {
            IslandMetric(Text(context.attributes.startedAt, style: .timer),
                         tint: done ? .brandSuccess : LiveActivityKind.workSession.color,
                         size: .expanded)
                .frame(maxWidth: 60)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct WorkSessionLockView: View {
    let context: ActivityViewContext<WorkSessionActivityAttributes>

    var body: some View {
        if LA.lockDetails(.workSession) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    IslandIconDisc(kind: .workSession, isComplete: context.state.isComplete)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.taskTitle)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if LA.property(.workSession),
                           let property = context.attributes.propertyName, !property.isEmpty {
                            Text(property)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    IslandMetric(Text(context.attributes.startedAt, style: .timer),
                                 tint: context.state.isComplete ? .brandSuccess : LiveActivityKind.workSession.color,
                                 size: .hero)
                        .frame(maxWidth: 90)
                        .multilineTextAlignment(.trailing)
                }
                if !context.state.isComplete {
                    HStack(spacing: AppSpacing.sm + 2) {
                        Button(intent: CompleteWorkSessionIntent(taskId: context.attributes.taskId)) {
                            Label("la_session_complete", systemImage: "checkmark.circle.fill")
                                .font(AppFont.captionEmphasis)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(LiveActivityKind.workSession.color)
                        Button(intent: EndWorkSessionIntent()) {
                            Text("la_session_end")
                                .font(AppFont.captionEmphasis)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .transition(.blurReplace)
                }
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .workSession,
                           title: Text(context.attributes.taskTitle),
                           isComplete: context.state.isComplete)
        }
    }
}

// MARK: - Delivery
//
// A milestone journey (ordered → in transit → out for delivery → delivered).
// The content state can arrive from the app OR from a server push whose
// sender doesn't know the device language, so the status label is resolved
// on-device from the status key, falling back to the pushed label.

private enum DeliveryFace {
    /// On-device label for both the legacy and the live-tracking status
    /// vocabularies; `fallback` covers unknown/future statuses.
    static func label(_ status: String, fallback: String) -> String {
        switch status {
        case "expected", "pending", "info_received": return String(localized: "Expected")
        case "in_transit":                           return String(localized: "In transit")
        case "out_for_delivery":                     return String(localized: "Out for delivery")
        case "available_for_pickup":                 return String(localized: "Ready for pickup")
        case "delivered":                            return String(localized: "Delivered")
        case "missed":                               return String(localized: "Missed")
        case "returned":                             return String(localized: "Returned")
        case "exception", "expired":                 return String(localized: "Delivery issue")
        case "failed_attempt":                       return String(localized: "Failed attempt")
        default:                                     return fallback
        }
    }

    static func milestone(_ state: DeliveryActivityAttributes.ContentState) -> Int {
        if let index = state.milestoneIndex { return max(0, min(3, index)) }
        switch state.status { // payloads from before the milestone field
        case "out_for_delivery", "available_for_pickup": return 2
        case "delivered":                                 return 3
        case "in_transit":                                return 1
        default:                                          return 0
        }
    }

    static func tint(_ state: DeliveryActivityAttributes.ContentState) -> Color {
        if state.isProblem == true { return .brandWarning }
        switch state.status {
        case "out_for_delivery", "available_for_pickup": return .brandWarning
        case "delivered":                                 return .brandSuccess
        default:                                          return LiveActivityKind.delivery.color
        }
    }
}

/// The delivery ETA line. When the tracking aggregator gave a real arrival
/// instant (`etaDate`) it renders a self-animating countdown — a ticking
/// `Text(timerInterval:)` inside the final same-day stretch, a self-updating
/// relative estimate ("in 2 days") further out — so the island counts down on
/// its own with no content pushes. It falls back to the day-level `eta` string
/// when no precise instant exists, and shows nothing at all otherwise. The
/// countdown is never fabricated: a day-only expected date arrives here as
/// `eta` (string) and stays a static estimate.
private struct DeliveryETALine: View {
    let state: DeliveryActivityAttributes.ContentState
    var tint: Color = .secondary

    /// Beyond this the second-by-second timer is noise, so a relative estimate
    /// ("in 2 days") — which also self-updates — reads better.
    private static let countdownWindow: TimeInterval = 12 * 3600

    var body: some View {
        if let date = state.etaDate, date > .now {
            HStack(spacing: AppSpacing.xxs) {
                Text("la_delivery_eta")
                if date.timeIntervalSinceNow <= Self.countdownWindow {
                    Text(timerInterval: Date.now...date, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 58, alignment: .leading)
                } else {
                    Text(date, style: .relative)
                }
            }
            .font(AppFont.caption2)
            .foregroundStyle(tint)
            .lineLimit(1)
        } else if let eta = state.eta {
            Text(String(format: String(localized: "ETA: %@"), eta))
                .font(AppFont.caption2)
                .foregroundStyle(tint)
                .lineLimit(1)
        }
    }
}

struct DeliveryLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: DeliveryActivityAttributes.self) { context in
            ActivityFamilyGate {
                DeliveryActivitySmallView(context: context)
            } full: {
                DeliveryLockView(context: context)
            }
            .widgetURL(LiveActivityKind.delivery.deepLink)
        } dynamicIsland: { context in
            let state = context.state
            let delivered = state.status == "delivered"
            let problem = state.isProblem == true
            let tint = DeliveryFace.tint(state)
            let label = DeliveryFace.label(state.status, fallback: state.statusLabel)
            // Out for delivery: the box wiggles periodically — attention, not alarm.
            let enRoute = !delivered && !problem && DeliveryFace.milestone(state) == 2

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .delivery, title: Text(context.attributes.carrier), isComplete: delivered,
                                 wiggles: enRoute)
                        .widgetURL(LiveActivityKind.delivery.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.delivery) {
                        Text(label)
                            .font(AppFont.captionStrong)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.delivery) {
                        VStack(spacing: AppSpacing.xs) {
                            if LA.progress(.delivery) {
                                IslandMilestoneBar(stage: DeliveryFace.milestone(state),
                                                   tint: delivered ? .brandSuccess : LiveActivityKind.delivery.color,
                                                   isProblem: problem)
                            }
                            HStack {
                                Text(state.checkpoint ?? context.attributes.description)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                if LA.eta(.delivery) {
                                    DeliveryETALine(state: state)
                                }
                            }
                            // One island, honestly disclosed: the other
                            // parcels also in motion, without a second island.
                            if let more = state.othersActive, more > 0 {
                                Text(String(format: String(localized: "la_delivery_others"), more))
                                    .font(AppFont.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if !delivered, let deliveryId = context.attributes.deliveryId {
                                DeliveryReceivedButton(deliveryId: deliveryId)
                                    .transition(.blurReplace)
                            }
                        }
                    }
                }
            } compactLeading: {
                // Limited width: the status word becomes the journey ring —
                // the same four milestones the expanded bar segments.
                IslandCompactLeading(kind: .delivery,
                                     progress: Double(DeliveryFace.milestone(state) + 1) / 4,
                                     tint: tint, value: Text(verbatim: label)) {
                    IslandStateIcon(kind: .delivery, isComplete: delivered, isProblem: problem, wiggles: enRoute)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.delivery.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .delivery) {
                    Text(label)
                        .font(AppFont.label)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .delivery, isComplete: delivered, isProblem: problem, wiggles: enRoute)
                        .accessibilityLabel(Text(verbatim: label))
                }
            }
        }
    }
}

private struct DeliveryActivitySmallView: View {
    let context: ActivityViewContext<DeliveryActivityAttributes>

    var body: some View {
        let state = context.state
        let delivered = state.status == "delivered"
        SmallStackCard(title: Text(context.attributes.description),
                       detail: Text(verbatim: DeliveryFace.label(state.status, fallback: state.statusLabel)),
                       progress: Double(DeliveryFace.milestone(state)) / 3.0,
                       progressTint: DeliveryFace.tint(state)) {
            IslandStateIcon(kind: .delivery, isComplete: delivered, isProblem: state.isProblem == true)
        } trailing: {
            EmptyView()
        }
    }
}

private struct DeliveryLockView: View {
    let context: ActivityViewContext<DeliveryActivityAttributes>

    var body: some View {
        let state = context.state
        let delivered = state.status == "delivered"
        let label = DeliveryFace.label(state.status, fallback: state.statusLabel)
        let enRoute = !delivered && state.isProblem != true && DeliveryFace.milestone(state) == 2

        if LA.lockDetails(.delivery) {
            VStack(spacing: 0) {
                IslandLockCard(kind: .delivery,
                               title: Text(context.attributes.description),
                               isComplete: delivered,
                               wiggles: enRoute) {
                    if LA.progress(.delivery) {
                        IslandMilestoneBar(stage: DeliveryFace.milestone(state),
                                           tint: delivered ? .brandSuccess : LiveActivityKind.delivery.color,
                                           isProblem: state.isProblem == true)
                    }
                    IslandContextLine(kind: .delivery,
                                      text: Text(verbatim: "\(context.attributes.carrier) · \(label)"),
                                      propertyName: context.attributes.propertyName)
                    if let checkpoint = state.checkpoint {
                        Text(checkpoint)
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if LA.eta(.delivery) {
                        DeliveryETALine(state: state, tint: DeliveryFace.tint(state))
                    }
                    if let more = state.othersActive, more > 0 {
                        Text(String(format: String(localized: "la_delivery_others"), more))
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } trailing: {
                    EmptyView()
                }
                if !delivered, let deliveryId = context.attributes.deliveryId {
                    DeliveryReceivedButton(deliveryId: deliveryId)
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.lg)
                        .transition(.blurReplace)
                }
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .delivery,
                           title: Text(context.attributes.description),
                           isComplete: delivered)
        }
    }
}

// MARK: - Plant care

struct PlantCareLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: PlantCareActivityAttributes.self) { context in
            ActivityFamilyGate {
                PlantCareActivitySmallView(context: context)
            } full: {
                PlantCareLockView(context: context)
            }
            .widgetURL(LiveActivityKind.plantCare.deepLink)
        } dynamicIsland: { context in
            let watered = context.state.wateredCount
            let total = context.state.totalCount
            let done = total > 0 && watered >= total
            let progress = total > 0 ? Double(watered) / Double(total) : 0
            let countText = Text(verbatim: "\(watered)/\(total)")
            let countLabel = Text(String(format: String(localized: "%d of %d plants watered"), watered, total))

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .plantCare, title: Text("Plant watering"), isComplete: done,
                                 breathes: !done)
                        .widgetURL(LiveActivityKind.plantCare.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.plantCare) {
                        IslandMetric(countText,
                                     tint: done ? .brandSuccess : LiveActivityKind.plantCare.color,
                                     size: .expanded)
                            .accessibilityLabel(countLabel)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.plantCare) {
                        VStack(spacing: AppSpacing.xxs) {
                            if LA.progress(.plantCare) {
                                IslandProgressBar(value: progress, tint: LiveActivityKind.plantCare.color)
                            }
                            if let name = context.state.lastWateredName {
                                Text(String(format: String(localized: "Last watered: %@"), name))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if !done {
                                PlantWaterButton()
                                    .padding(.top, AppSpacing.xxs)
                                    .transition(.blurReplace)
                            }
                        }
                    }
                }
            } compactLeading: {
                IslandCompactLeading(kind: .plantCare, progress: progress,
                                     tint: done ? .brandSuccess : LiveActivityKind.plantCare.color,
                                     value: countLabel) {
                    IslandStateIcon(kind: .plantCare, isComplete: done, breathes: !done)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.plantCare.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .plantCare) {
                    IslandMetric(countText)
                        .accessibilityLabel(countLabel)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .plantCare, isComplete: done, breathes: !done)
                        .accessibilityLabel(Text(LiveActivityKind.plantCare.title))
                }
            }
        }
    }
}

private struct PlantCareActivitySmallView: View {
    let context: ActivityViewContext<PlantCareActivityAttributes>

    var body: some View {
        let watered = context.state.wateredCount
        let total = context.state.totalCount
        let done = total > 0 && watered >= total
        SmallStackCard(title: Text("Plant watering"),
                       progress: total > 0 ? Double(watered) / Double(total) : 0,
                       progressTint: done ? .brandSuccess : LiveActivityKind.plantCare.color) {
            IslandStateIcon(kind: .plantCare, isComplete: done, breathes: !done)
        } trailing: {
            IslandMetric(Text(verbatim: "\(watered)/\(total)"),
                         tint: done ? .brandSuccess : LiveActivityKind.plantCare.color,
                         size: .expanded)
                .accessibilityLabel(Text(String(format: String(localized: "%d of %d plants watered"), watered, total)))
        }
    }
}

private struct PlantCareLockView: View {
    let context: ActivityViewContext<PlantCareActivityAttributes>

    private var progress: Double {
        context.state.totalCount > 0
            ? Double(context.state.wateredCount) / Double(context.state.totalCount)
            : 0
    }
    private var isComplete: Bool {
        context.state.totalCount > 0 && context.state.wateredCount >= context.state.totalCount
    }

    var body: some View {
        if LA.lockDetails(.plantCare) {
            VStack(spacing: 0) {
                IslandLockCard(kind: .plantCare,
                               title: Text("Plant watering"),
                               isComplete: isComplete,
                               breathes: !isComplete) {
                    if LA.progress(.plantCare) {
                        IslandProgressBar(value: progress, tint: LiveActivityKind.plantCare.color)
                    }
                    IslandContextLine(kind: .plantCare,
                                      text: Text(String(format: String(localized: "%d of %d plants watered"),
                                                        context.state.wateredCount, context.state.totalCount)),
                                      propertyName: context.attributes.propertyName)
                } trailing: {
                    IslandMetric(Text(verbatim: "\(Int(progress * 100))%"),
                                 tint: isComplete ? .brandSuccess : LiveActivityKind.plantCare.color,
                                 size: .hero)
                }
                if !isComplete {
                    PlantWaterButton()
                        .padding(.horizontal, AppSpacing.lg)
                        .padding(.bottom, AppSpacing.lg)
                        .transition(.blurReplace)
                }
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .plantCare, title: Text("Plant watering"), isComplete: isComplete)
        }
    }
}

// MARK: - Emergency incident
//
// User-pinned from the Emergency page during a real incident: the beacon
// pulses in the island, the elapsed time is system-counted from the fixed
// start date, and the only actions are the honest ones — open the page,
// or declare the incident over. The only activity allowed to wear red.

struct EmergencyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: EmergencyActivityAttributes.self) { context in
            ActivityFamilyGate {
                EmergencyActivitySmallView(context: context)
            } full: {
                EmergencyLockView(context: context)
            }
            .widgetURL(LiveActivityKind.emergency.deepLink)
        } dynamicIsland: { context in
            let timer = Text(context.attributes.startedAt, style: .timer)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .emergency, title: Text("la_emergency_active"), pulses: true)
                        .widgetURL(LiveActivityKind.emergency.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.emergency) {
                        IslandMetric(timer, tint: LiveActivityKind.emergency.color, size: .expanded)
                            .frame(maxWidth: 60)
                            .multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.emergency) {
                        HStack(spacing: AppSpacing.sm + 2) {
                            if LA.property(.emergency),
                               let property = context.attributes.propertyName, !property.isEmpty {
                                Text(property)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button(intent: EndEmergencyIntent()) {
                                Text("la_emergency_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                            .tint(LiveActivityKind.emergency.color)
                        }
                    }
                }
            } compactLeading: {
                IslandCompactLeading(kind: .emergency, value: timer) {
                    IslandStateIcon(kind: .emergency, pulses: true)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.emergency.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .emergency) {
                    IslandMetric(timer, tint: LiveActivityKind.emergency.color)
                        .frame(maxWidth: 44)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .emergency, pulses: true)
                        .accessibilityLabel(Text(LiveActivityKind.emergency.title))
                }
            }
        }
    }
}

private struct EmergencyActivitySmallView: View {
    let context: ActivityViewContext<EmergencyActivityAttributes>

    var body: some View {
        SmallStackCard(title: Text("la_emergency_active")) {
            IslandStateIcon(kind: .emergency, pulses: true)
        } trailing: {
            IslandMetric(Text(context.attributes.startedAt, style: .timer),
                         tint: LiveActivityKind.emergency.color,
                         size: .expanded)
                .frame(maxWidth: 60)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct EmergencyLockView: View {
    let context: ActivityViewContext<EmergencyActivityAttributes>

    var body: some View {
        if LA.lockDetails(.emergency) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    IslandIconDisc(kind: .emergency)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("la_emergency_active")
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                        if LA.property(.emergency),
                           let property = context.attributes.propertyName, !property.isEmpty {
                            Text(property)
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    IslandMetric(Text(context.attributes.startedAt, style: .timer),
                                 tint: LiveActivityKind.emergency.color, size: .hero)
                        .frame(maxWidth: 90)
                        .multilineTextAlignment(.trailing)
                }
                Button(intent: EndEmergencyIntent()) {
                    Text("la_emergency_end")
                        .font(AppFont.captionEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(LiveActivityKind.emergency.color)
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .emergency, title: Text("la_emergency_active"))
        }
    }
}

// MARK: - IoT sensor alert
//
// Raised by the user's own sensors (threshold crossings, smoke). Critical
// hazards (smoke / gas / water) wear danger red; everything else warning
// orange. "Got it" silences this instance until the sensor clears.

private struct AlertSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    let tint: Color
    var pulses = true

    var body: some View {
        Image(systemName: name)
            .foregroundStyle(tint)
            .symbolEffect(.pulse, options: .repeating, isActive: pulses && !reduceMotion)
    }
}

struct IoTAlertLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: IoTAlertActivityAttributes.self) { context in
            ActivityFamilyGate {
                IoTAlertActivitySmallView(context: context)
            } full: {
                IoTAlertLockView(context: context)
            }
            .widgetURL(LiveActivityKind.iotAlert.deepLink)
        } dynamicIsland: { context in
            let active = context.state.isActive
            let tint: Color = active
                ? (context.attributes.isCritical ? .brandDanger : .brandWarning)
                : .brandSuccess

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: AppSpacing.xs) {
                        AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                            .font(AppFont.captionStrong)
                        if LA.expandedData(.iotAlert) {
                            Text(context.attributes.sensorName)
                                .font(AppFont.captionStrong)
                                .foregroundStyle(tint)
                                .lineLimit(1)
                        }
                    }
                    .widgetURL(LiveActivityKind.iotAlert.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.iotAlert) {
                        IslandMetric(Text(verbatim: context.state.valueDisplay),
                                     tint: tint, size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.iotAlert) {
                        HStack(spacing: AppSpacing.sm + 2) {
                            if let zone = context.attributes.zone {
                                Text(zone)
                                    .font(AppFont.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Label {
                                Text(context.attributes.startedAt, style: .relative)
                            } icon: {
                                Image(systemName: "clock")
                            }
                            .font(AppFont.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            Spacer()
                            if active {
                                Button(intent: AcknowledgeIoTAlertIntent(sensorId: context.attributes.sensorId)) {
                                    Text("la_alert_ack")
                                        .font(AppFont.captionStrong)
                                }
                                .buttonStyle(.bordered)
                                .tint(tint)
                            }
                        }
                    }
                }
            } compactLeading: {
                // Free-form readings can't be promised to fit 28pt, so limited
                // width keeps the tinted sensor glyph — its color already
                // carries active / critical / resolved — and speaks the value.
                IslandCompactLeading(kind: .iotAlert, value: Text(verbatim: context.state.valueDisplay)) {
                    AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(context.attributes.sensorName))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .iotAlert) {
                    IslandMetric(Text(verbatim: context.state.valueDisplay), tint: tint)
                        .accessibilityLabel(Text(verbatim: "\(context.attributes.sensorName) \(context.state.valueDisplay)"))
                }
            } minimal: {
                IslandMinimal {
                    AlertSymbol(name: context.attributes.icon, tint: tint, pulses: active)
                        .accessibilityLabel(Text(context.attributes.sensorName))
                }
            }
        }
    }
}

private struct IoTAlertActivitySmallView: View {
    let context: ActivityViewContext<IoTAlertActivityAttributes>

    private var tint: Color {
        context.state.isActive
            ? (context.attributes.isCritical ? .brandDanger : .brandWarning)
            : .brandSuccess
    }

    var body: some View {
        SmallStackCard(title: Text(context.attributes.sensorName),
                       detail: context.attributes.zone.map { Text($0) }) {
            AlertSymbol(name: context.attributes.icon, tint: tint,
                        pulses: context.state.isActive)
        } trailing: {
            IslandMetric(Text(verbatim: context.state.valueDisplay),
                         tint: tint, size: .expanded)
        }
    }
}

private struct IoTAlertLockView: View {
    let context: ActivityViewContext<IoTAlertActivityAttributes>

    private var tint: Color {
        context.state.isActive
            ? (context.attributes.isCritical ? .brandDanger : .brandWarning)
            : .brandSuccess
    }

    var body: some View {
        if LA.lockDetails(.iotAlert) {
            VStack(spacing: AppSpacing.sm + 2) {
                HStack(spacing: AppSpacing.base) {
                    ZStack {
                        Circle()
                            .fill(tint.opacity(AppOpacity.tintedFill))
                            .frame(width: IslandMetrics.iconDisc, height: IslandMetrics.iconDisc)
                        AlertSymbol(name: context.attributes.icon, tint: tint,
                                    pulses: context.state.isActive)
                            .font(AppFont.title3)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.sensorName)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        IslandContextLine(kind: .iotAlert,
                                          text: Text(context.attributes.zone ?? ""),
                                          propertyName: context.attributes.propertyName)
                        Label {
                            Text(context.attributes.startedAt, style: .relative)
                        } icon: {
                            Image(systemName: "clock")
                        }
                        .font(AppFont.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Spacer()
                    IslandMetric(Text(verbatim: context.state.valueDisplay),
                                 tint: tint, size: .hero)
                }
                if context.state.isActive {
                    Button(intent: AcknowledgeIoTAlertIntent(sensorId: context.attributes.sensorId)) {
                        Text("la_alert_ack")
                            .font(AppFont.captionEmphasis)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                }
            }
            .padding(AppSpacing.lg)
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .iotAlert, title: Text(context.attributes.sensorName))
        }
    }
}

// MARK: - Energy session
//
// Live gauge over the user's own power sensors: consumption vs tagged
// production. Values only ever come from real polls.

private enum EnergyFace {
    static func watts(_ w: Double?) -> String? {
        guard let w else { return nil }
        return w >= 1000 ? String(format: "%.1f kW", w / 1000)
                         : String(format: "%.0f W", w)
    }
}

struct EnergyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: EnergyActivityAttributes.self) { context in
            ActivityFamilyGate {
                EnergyActivitySmallView(context: context)
            } full: {
                EnergyLockView(context: context)
            }
            .widgetURL(LiveActivityKind.energy.deepLink)
        } dynamicIsland: { context in
            let headline = EnergyFace.watts(context.state.consumptionW)
                ?? EnergyFace.watts(context.state.productionW) ?? "—"

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandHeader(kind: .energy, title: Text(LiveActivityKind.energy.title))
                        .widgetURL(LiveActivityKind.energy.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.energy) {
                        IslandMetric(Text(verbatim: headline),
                                     tint: LiveActivityKind.energy.color, size: .expanded)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.energy) {
                        HStack(spacing: AppSpacing.base) {
                            if let consumption = EnergyFace.watts(context.state.consumptionW) {
                                Label {
                                    Text(verbatim: consumption)
                                        .font(AppFont.captionStrong)
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                } icon: {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .foregroundStyle(LiveActivityKind.energy.color)
                                }
                                .font(AppFont.caption)
                                .accessibilityLabel(Text("la_energy_consumption"))
                            }
                            if let production = EnergyFace.watts(context.state.productionW) {
                                Label {
                                    Text(verbatim: production)
                                        .font(AppFont.captionStrong)
                                        .monospacedDigit()
                                        .contentTransition(.numericText())
                                } icon: {
                                    EnergySunIcon()
                                }
                                .font(AppFont.caption)
                                .accessibilityLabel(Text("la_energy_production"))
                            }
                            Spacer()
                            Button(intent: EndEnergySessionIntent()) {
                                Text("la_session_end")
                                    .font(AppFont.captionStrong)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } compactLeading: {
                IslandCompactLeading(kind: .energy, value: Text(verbatim: headline)) {
                    IslandStateIcon(kind: .energy)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(LiveActivityKind.energy.title))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .energy) {
                    IslandMetric(Text(verbatim: headline), tint: LiveActivityKind.energy.color)
                }
            } minimal: {
                IslandMinimal {
                    IslandStateIcon(kind: .energy)
                        .accessibilityLabel(Text(LiveActivityKind.energy.title))
                }
            }
        }
    }
}

private struct EnergyActivitySmallView: View {
    let context: ActivityViewContext<EnergyActivityAttributes>

    var body: some View {
        SmallStackCard(title: Text(LiveActivityKind.energy.title)) {
            IslandStateIcon(kind: .energy)
        } trailing: {
            IslandMetric(Text(verbatim: EnergyFace.watts(context.state.consumptionW)
                              ?? EnergyFace.watts(context.state.productionW) ?? "—"),
                         tint: LiveActivityKind.energy.color, size: .expanded)
        }
    }
}

/// The production sun: a variable-color cascade while panels are live. The
/// icon renders only when real production watts exist, so the motion can
/// never claim energy that isn't flowing.
private struct EnergySunIcon: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "sun.max.fill")
            .foregroundStyle(Color.brandSuccess)
            .symbolEffect(.variableColor, options: .repeating, isActive: !reduceMotion)
    }
}

private struct EnergyLockView: View {
    let context: ActivityViewContext<EnergyActivityAttributes>

    var body: some View {
        if LA.lockDetails(.energy) {
            VStack(spacing: 0) {
                IslandLockCard(kind: .energy, title: Text(LiveActivityKind.energy.title)) {
                    HStack(spacing: AppSpacing.xxs) {
                        if let consumption = EnergyFace.watts(context.state.consumptionW) {
                            Text("la_energy_consumption") + Text(verbatim: " \(consumption)")
                        }
                        if context.state.consumptionW != nil, context.state.productionW != nil {
                            Text(verbatim: "·")
                        }
                        if let production = EnergyFace.watts(context.state.productionW) {
                            Text("la_energy_production") + Text(verbatim: " \(production)")
                        }
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    IslandContextLine(kind: .energy, text: Text(verbatim: ""),
                                      propertyName: context.attributes.propertyName)
                } trailing: {
                    IslandMetric(Text(verbatim: EnergyFace.watts(context.state.consumptionW)
                                      ?? EnergyFace.watts(context.state.productionW) ?? "—"),
                                 tint: LiveActivityKind.energy.color, size: .hero)
                }
                // Parity with the expanded island: the session can be ended
                // from the Lock Screen too, not only from the Dynamic Island.
                Button(intent: EndEnergySessionIntent()) {
                    Text("la_session_end")
                        .font(AppFont.captionEmphasis)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .energy, title: Text(LiveActivityKind.energy.title))
        }
    }
}

// MARK: - Cover operation (garage / gate)
//
// Follows a single user-issued command. "Open"/"Closed" appear only when a
// feedback sensor confirmed them; otherwise the terminal state is the honest
// "command finished" / "no confirmation".

private enum CoverFace {
    static func label(_ stage: String) -> LocalizedStringKey {
        switch stage {
        case "sent":    return "la_cover_sent"
        case "moving":  return "la_cover_moving"
        case "open":    return "la_cover_open"
        case "closed":  return "la_cover_closed"
        case "stopped": return "la_cover_stopped"
        case "done":    return "la_cover_done"
        case "timeout": return "la_cover_timeout"
        default:        return "la_cover_failed"
        }
    }
    static func tint(_ stage: String) -> Color {
        switch stage {
        case "failed", "timeout":                 return .brandWarning
        case "open", "closed", "done", "stopped": return .brandSuccess
        default:                                  return LiveActivityKind.cover.color
        }
    }
    static func icon(_ stage: String) -> String {
        stage == "open" ? "door.garage.open" : LiveActivityKind.cover.icon
    }
    static func isBusy(_ stage: String) -> Bool {
        stage == "sent" || stage == "moving"
    }
}

/// The cover's door glyph: crossfades when the stage swaps (open ↔ closed) and
/// pulses while the command is in flight — a real motion cue, since an
/// indeterminate `ProgressView()` does not animate inside a Live Activity.
/// Reduce Motion stops the pulse.
private struct CoverSymbol: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let stage: String
    let tint: Color

    var body: some View {
        Image(systemName: CoverFace.icon(stage))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, options: .repeating,
                          isActive: CoverFace.isBusy(stage) && !reduceMotion)
    }
}

struct CoverLiveActivity: Widget {
    var body: some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }

    private var configuration: some WidgetConfiguration {
        ActivityConfiguration(for: CoverActivityAttributes.self) { context in
            ActivityFamilyGate {
                CoverActivitySmallView(context: context)
            } full: {
                CoverLockView(context: context)
            }
            .widgetURL(LiveActivityKind.cover.deepLink)
        } dynamicIsland: { context in
            let stage = context.state.stage
            let tint = CoverFace.tint(stage)

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: AppSpacing.xs) {
                        CoverSymbol(stage: stage, tint: tint)
                            .font(AppFont.captionStrong)
                        if LA.expandedData(.cover) {
                            Text(context.attributes.deviceName)
                                .font(AppFont.captionStrong)
                                .foregroundStyle(tint)
                                .lineLimit(1)
                        }
                    }
                    .widgetURL(LiveActivityKind.cover.deepLink)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if LA.expandedData(.cover) {
                        Text(CoverFace.label(stage))
                            .font(AppFont.captionStrong)
                            .foregroundStyle(tint)
                            .lineLimit(1)
                            .contentTransition(.opacity)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if LA.expandedDetail(.cover), CoverFace.isBusy(stage) {
                        HStack(spacing: AppSpacing.sm) {
                            CoverSymbol(stage: stage, tint: LiveActivityKind.cover.color)
                                .font(AppFont.caption)
                            Text(CoverFace.label(stage))
                                .font(AppFont.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let actuatorId = context.attributes.actuatorId {
                                Button(intent: StopCoverIntent(actuatorId: actuatorId)) {
                                    Label("iot_cmd_stop", systemImage: "stop.fill")
                                        .font(AppFont.captionStrong)
                                }
                                .buttonStyle(.bordered)
                                .tint(LiveActivityKind.cover.color)
                                .transition(.blurReplace)
                            }
                        }
                    }
                }
            } compactLeading: {
                // The symbol and tint already change per stage, so limited
                // width drops only the stage word (VoiceOver still reads it).
                IslandCompactLeading(kind: .cover, value: Text(CoverFace.label(stage))) {
                    CoverSymbol(stage: stage, tint: tint)
                        .font(AppFont.captionStrong)
                        .accessibilityLabel(Text(context.attributes.deviceName))
                }
            } compactTrailing: {
                IslandCompactTrailing(kind: .cover) {
                    Text(CoverFace.label(stage))
                        .font(AppFont.label)
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
            } minimal: {
                IslandMinimal {
                    CoverSymbol(stage: stage, tint: tint)
                        .accessibilityLabel(Text(context.attributes.deviceName))
                }
            }
        }
    }
}

private struct CoverActivitySmallView: View {
    let context: ActivityViewContext<CoverActivityAttributes>

    var body: some View {
        let stage = context.state.stage
        SmallStackCard(title: Text(context.attributes.deviceName),
                       detail: Text(CoverFace.label(stage))) {
            CoverSymbol(stage: stage, tint: CoverFace.tint(stage))
        } trailing: {
            EmptyView()
        }
    }
}

private struct CoverLockView: View {
    let context: ActivityViewContext<CoverActivityAttributes>

    var body: some View {
        let stage = context.state.stage
        if LA.lockDetails(.cover) {
            VStack(spacing: 0) {
                HStack(spacing: AppSpacing.base) {
                    ZStack {
                        Circle()
                            .fill(CoverFace.tint(stage).opacity(AppOpacity.tintedFill))
                            .frame(width: IslandMetrics.iconDisc, height: IslandMetrics.iconDisc)
                        CoverSymbol(stage: stage, tint: CoverFace.tint(stage))
                            .font(AppFont.title3)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.deviceName)
                            .font(AppFont.footnoteEmphasis)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(CoverFace.label(stage))
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(AppSpacing.lg)
                if CoverFace.isBusy(stage), let actuatorId = context.attributes.actuatorId {
                    Button(intent: StopCoverIntent(actuatorId: actuatorId)) {
                        Label("iot_cmd_stop", systemImage: "stop.fill")
                            .font(AppFont.captionEmphasis)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(LiveActivityKind.cover.color)
                    .padding(.horizontal, AppSpacing.lg)
                    .padding(.bottom, AppSpacing.lg)
                    .transition(.blurReplace)
                }
            }
            .activityBackgroundTint(Color.clear)
            .activitySystemActionForegroundColor(.primary)
        } else {
            MinimalLockRow(kind: .cover, title: Text(context.attributes.deviceName))
        }
    }
}
