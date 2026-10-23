import Foundation
import WatchConnectivity

// MARK: - WatchConnectivity bridge
//
// The only type that touches WCSession. WCSessionDelegate callbacks arrive
// on a background queue, so they are `nonisolated`, extract Sendable values
// (the payload Data, the reachability flag) and hop to the main actor;
// everything else here is main-actor state. The store never sees WCSession.
//
// Channels (frozen contract):
// - applicationContext["payload"] (Data) — the phone's latest snapshot,
//   persisted by the system and re-read on every activation.
// - sendMessage(["action": "refresh"]) → reply ["payload": Data] — the live
//   channel, only when the phone is reachable right now.
// - transferUserInfo — every wrist action; guaranteed delivery that survives
//   unreachability and relaunches.

/// The link to the iPhone, as the UI may want to show it.
enum WatchConnectivityState: Equatable {
    /// WatchConnectivity is not available on this device.
    case unsupported
    /// Activation has not completed yet.
    case activating
    /// Activated, but the session became inactive.
    case inactive
    /// Activated; the phone app answers live messages right now.
    case reachable
    /// Activated; actions still queue, refresh cannot answer now.
    case unreachable
}

/// Where an ingested payload came from — decides how stale data is judged.
enum WatchIngestSource {
    /// `receivedApplicationContext` re-read on activation: possibly older
    /// than the local cache (which carries optimistic edits).
    case activation
    /// A live `didReceiveApplicationContext` push.
    case push
    /// The reply to an explicit refresh request.
    case refresh
}

@MainActor
protocol WatchConnectorDelegate: AnyObject {
    func connector(_ connector: WatchConnector, didReceivePayload data: Data, source: WatchIngestSource)
    func connector(_ connector: WatchConnector, didChangeState state: WatchConnectivityState)
    /// The session is activated — flush whatever waited for it.
    func connectorDidActivate(_ connector: WatchConnector)
}

@MainActor
final class WatchConnector: NSObject {
    weak var delegate: WatchConnectorDelegate?

    private(set) var state: WatchConnectivityState =
        WCSession.isSupported() ? .activating : .unsupported

    /// Transfers requested before activation completed. transferUserInfo on
    /// a session that is not activated fails, so they wait here (in memory —
    /// activation completes within the same launch).
    private var pendingTransfers: [[String: Any]] = []

    func activate() {
        guard WCSession.isSupported() else {
            setState(.unsupported)
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Queues an action to the phone through the guaranteed channel.
    func transfer(_ userInfo: [String: Any]) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingTransfers.append(userInfo)
            return
        }
        _ = session.transferUserInfo(userInfo)
    }

    /// Asks the phone for a fresh payload over the live channel. Returns
    /// false when the phone is not reachable right now (nothing was sent);
    /// otherwise `completion` runs on the main actor with the reply's
    /// payload, or nil on failure.
    func requestPayload(_ completion: @escaping @MainActor @Sendable (Data?) -> Void) -> Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return false }
        session.sendMessage(["action": "refresh"], replyHandler: { reply in
            let data = reply["payload"] as? Data
            Task { @MainActor in completion(data) }
        }, errorHandler: { _ in
            Task { @MainActor in completion(nil) }
        })
        return true
    }

    // MARK: Main-actor handlers

    private func handleActivation(_ activationState: WCSessionActivationState,
                                  reachable: Bool, contextPayload: Data?) {
        guard activationState == .activated else {
            setState(.inactive)
            return
        }
        setState(reachable ? .reachable : .unreachable)
        let waiting = pendingTransfers
        pendingTransfers.removeAll()
        for userInfo in waiting { _ = WCSession.default.transferUserInfo(userInfo) }
        if let contextPayload {
            delegate?.connector(self, didReceivePayload: contextPayload, source: .activation)
        }
        delegate?.connectorDidActivate(self)
    }

    private func setState(_ newState: WatchConnectivityState) {
        guard newState != state else { return }
        state = newState
        delegate?.connector(self, didChangeState: newState)
    }
}

// MARK: - WCSessionDelegate (background queue → main actor)

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        // applicationContext is persisted by the system: the newest push is
        // already waiting here even if the app was not running for it.
        let context = activationState == .activated
            ? session.receivedApplicationContext["payload"] as? Data
            : nil
        let reachable = session.isReachable
        Task { @MainActor in
            self.handleActivation(activationState, reachable: reachable, contextPayload: context)
        }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["payload"] as? Data else { return }
        Task { @MainActor in
            self.delegate?.connector(self, didReceivePayload: data, source: .push)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        let activated = session.activationState == .activated
        Task { @MainActor in
            guard activated else { return }
            self.setState(reachable ? .reachable : .unreachable)
        }
    }
}
