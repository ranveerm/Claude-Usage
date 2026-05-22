import WatchConnectivity
import WidgetKit

/// Pushes fresh UsageData to the paired Apple Watch via WatchConnectivity.
/// `transferUserInfo` queues delivery even when the watch is not immediately reachable.
/// `sendMessage` handles watch-initiated refresh requests, replying inline with fresh data.
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

    /// Handles a watch-initiated refresh request. Fetches fresh usage from the
    /// Claude API and replies directly so the watch updates immediately without
    /// waiting for the next scheduled background fetch.
    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message["requestRefresh"] as? Bool == true else {
            replyHandler([:])
            return
        }
        Task {
            let data = await UsageService.shared.fetchUsage()
            guard data.error == nil, !data.needsLogin,
                  let encoded = try? JSONEncoder().encode(data) else {
                replyHandler([:])
                return
            }
            SharedDefaults.save(data)
            WidgetCenter.shared.reloadAllTimelines()
            await MainActor.run { LiveActivityManager.shared.update(with: data) }
            replyHandler(["usage": encoded])
        }
    }
}
