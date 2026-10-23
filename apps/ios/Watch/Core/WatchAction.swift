import Foundation

// MARK: - Wrist → phone actions (frozen wire contract)
//
// Every action the watch can ask of the phone, typed. `userInfo()` renders
// the exact `transferUserInfo` dictionary the phone's WatchSyncService
// parses — the action names and keys below are frozen (ARCHITECTURE.md,
// "Frozen contract"); renaming one silently drops that action on the phone.
//
// Every transfer carries a fresh `actionId`: transferUserInfo guarantees
// delivery, not exactly-once processing, and the phone drops a re-delivered
// id. Two intentional taps get two ids and both count.

/// Where a dictated chat message lands on the phone.
enum WatchMessageTarget: Equatable {
    /// The household chat.
    case group
    /// A direct thread, keyed by the peer's auth user id.
    case direct(UUID)

    var wireValue: String {
        switch self {
        case .group:          return "group"
        case .direct(let id): return "dm:\(id.uuidString)"
        }
    }
}

enum WatchAction: Equatable {
    case completeTask(UUID)
    case waterPlant(UUID)
    case checkSupply(UUID)
    case consumePantry(UUID)
    case deliveryReceived(UUID)
    case pantryToList(UUID)
    case createTask(title: String)
    case sendMessage(text: String, target: WatchMessageTarget)
    case alertFamily
    case sessionStart(taskId: UUID, title: String, startedAt: Date)
    case sessionPause
    case sessionResume
    /// `completesTask` rides as `complete` = "1"/"0"; a phone build that
    /// predates the key treats every end as a completion.
    case sessionEnd(completesTask: Bool)
    case iotCommand(actuatorId: UUID, command: String)
    case startEmergency
    case watchCrash(text: String)
    /// An entry queued in `WatchActionRelay` by the complications or Siri
    /// (which cannot reach WCSession), forwarded verbatim.
    case relayed(action: String, id: String)

    /// The frozen `action` value.
    var name: String {
        switch self {
        case .completeTask:     return "completeTask"
        case .waterPlant:       return "waterPlant"
        case .checkSupply:      return "checkSupply"
        case .consumePantry:    return "consumePantry"
        case .deliveryReceived: return "deliveryReceived"
        case .pantryToList:     return "pantryToList"
        case .createTask:       return "createTask"
        case .sendMessage:      return "sendMessage"
        case .alertFamily:      return "alertFamily"
        case .sessionStart:     return "sessionStart"
        case .sessionPause:     return "sessionPause"
        case .sessionResume:    return "sessionResume"
        case .sessionEnd:       return "sessionEnd"
        case .iotCommand:       return "iotCommand"
        case .startEmergency:   return "startEmergency"
        case .watchCrash:       return "watchCrash"
        case .relayed(let action, _): return action
        }
    }

    /// The `transferUserInfo` dictionary. Values are property-list types
    /// only (String), as WatchConnectivity requires.
    func userInfo(actionId: UUID = UUID()) -> [String: Any] {
        var info: [String: Any] = ["action": name, "actionId": actionId.uuidString]
        switch self {
        case .completeTask(let id), .waterPlant(let id), .checkSupply(let id),
             .consumePantry(let id), .deliveryReceived(let id), .pantryToList(let id):
            info["id"] = id.uuidString
        case .createTask(let title):
            info["title"] = title
        case .sendMessage(let text, let target):
            info["text"] = text
            info["target"] = target.wireValue
        case .sessionStart(let taskId, let title, let startedAt):
            info["id"] = taskId.uuidString
            info["title"] = title
            info["startedAt"] = String(startedAt.timeIntervalSince1970)
        case .sessionEnd(let completesTask):
            info["complete"] = completesTask ? "1" : "0"
        case .iotCommand(let actuatorId, let command):
            info["actuatorId"] = actuatorId.uuidString
            info["command"] = command
        case .watchCrash(let text):
            info["text"] = text
        case .relayed(_, let id):
            info["id"] = id
        case .alertFamily, .sessionPause, .sessionResume, .startEmergency:
            break
        }
        return info
    }
}
