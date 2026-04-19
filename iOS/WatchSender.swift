import WatchConnectivity

/// Pushes fresh UsageData to the paired Apple Watch via WatchConnectivity.
/// `transferUserInfo` queues delivery even when the watch is not immediately reachable.
final class WatchSender: NSObject, WCSessionDelegate {
    static let shared = WatchSender()

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ data: UsageData) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let encoded = try? JSONEncoder().encode(data) else { return }
        WCSession.default.transferUserInfo(["usage": encoded])
    }

    // MARK: - WCSessionDelegate (iOS-only callbacks)

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after Apple Watch switching
        WCSession.default.activate()
    }
}
