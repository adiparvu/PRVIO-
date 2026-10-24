import Foundation
import WatchKit

// MARK: - The haptic vocabulary (DESIGN.md, "Haptic vocabulary")
//
// One meaning per haptic, and only the HIG's meaning. Every tap the wrist
// plays goes through here — WatchStore's intents, components and alerts —
// so a "success" always means something was done and a "notification"
// always means a real alarm.
//
// | moment                                         | case          | WKHapticType    |
// |------------------------------------------------|---------------|-----------------|
// | task done, plant watered, delivery received,   | .done         | .success        |
// | message sent, task created                     |               |                 |
// | shopping item checked, pantry unit, command,   | .tick         | .click          |
// | refresh answered                               |               |                 |
// | session start / resume                         | .sessionStart | .start          |
// | session stop / pause                           | .sessionStop  | .stop           |
// | command failed (phone answered with nothing)   | .retry        | .retry          |
// | phone unreachable                              | .unreachable  | .failure        |
// | critical sensor alarm, emergency raised        | .alarm        | .notification   |
// | all-clear celebration                          | .celebration  | .success (once) |
//
// Crown detents are NOT played from here: `digitalCrownRotation(detent:…
// isHapticFeedbackEnabled: true)` already clicks once per detent, and a
// second click on top would double every step.

enum WatchHaptic: CaseIterable, Sendable {
    case done
    case tick
    case sessionStart
    case sessionStop
    case retry
    case unreachable
    case alarm
    case celebration

    /// The system haptic this moment speaks.
    var type: WKHapticType {
        switch self {
        case .done, .celebration: return .success
        case .tick:               return .click
        case .sessionStart:       return .start
        case .sessionStop:        return .stop
        case .retry:              return .retry
        case .unreachable:        return .failure
        case .alarm:              return .notification
        }
    }

    /// Plays the haptic. The same system haptic arriving again inside
    /// `coalescingWindow` is dropped: clearing the last task plays `.done`
    /// from the store and `.celebration` from the view in the same beat,
    /// and the brief promises the celebration lands exactly once. An alarm
    /// is never coalesced — every critical alarm must be felt.
    @MainActor
    func play() {
        guard WatchHaptic.isEnabled else { return }
        let now = Date()
        if self != .alarm,
           let last = WatchHaptic.lastPlayed,
           last.type == type,
           now.timeIntervalSince(last.at) < WatchHaptic.coalescingWindow {
            return
        }
        WatchHaptic.lastPlayed = (type, now)
        WKInterfaceDevice.current().play(type)
    }

    /// Off for SwiftUI previews and the preview store (no device to tap).
    @MainActor static var isEnabled = true

    /// Two identical haptics closer than this read as one stutter.
    static let coalescingWindow: TimeInterval = 0.8

    @MainActor private static var lastPlayed: (type: WKHapticType, at: Date)? = nil
}
