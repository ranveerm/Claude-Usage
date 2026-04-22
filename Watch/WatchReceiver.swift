import WatchConnectivity
import SwiftUI
import WidgetKit

/// Receives UsageData pushed from the paired iPhone via WatchConnectivity.
/// On init, loads any previously cached data from SharedDefaults so the UI
/// is never blank when the watch app opens between iPhone syncs.
final class WatchReceiver: NSObject, ObservableObject, WCSessionDelegate {
    @Published var usageData: UsageData?

    override init() {
        super.init()
        usageData = SharedDefaults.load()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let encoded = userInfo["usage"] as? Data,
              let data = try? JSONDecoder().decode(UsageData.self, from: encoded) else { return }
        SharedDefaults.save(data)
        DispatchQueue.main.async { self.usageData = data }
        // The complication runs in a separate process that reads from
        // SharedDefaults — without this it happily keeps showing whatever
        // was on the face last, even though fresh data has landed. Reload
        // so watchOS asks the complication provider for a new timeline.
        WidgetCenter.shared.reloadAllTimelines()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {}
}
