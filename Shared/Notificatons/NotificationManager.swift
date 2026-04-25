import Foundation
import UserNotifications

/// Glue between the pure evaluator and the UserNotifications framework.
/// Owns dedup-state persistence and the actual `UNNotificationRequest`
/// plumbing. Kept as a singleton because `UNUserNotificationCenter` itself
/// is a singleton and there's no state worth parameterising.
final class NotificationManager {
    static let shared = NotificationManager()

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private let stateKey = "notif.dedupState"

    private init() {
        self.defaults = UserDefaults(suiteName: "group.com.ranveer.ClaudeYourRings") ?? .standard
    }

    // MARK: - Authorisation

    /// Ask the system for permission. Only request `.alert` and `.sound` —
    /// deliberately skipping `.badge` and `.criticalAlert` so the app stays
    /// in "banner" territory. iOS only shows the modal once; subsequent
    /// calls return whatever the user's already chosen.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Evaluate + post

    /// Call after every successful fetch. No-ops when notifications are
    /// disabled or not authorised, so it's safe to call unconditionally.
    func evaluateAndPost(data: UsageData, settings: NotificationSettings) async {
        guard settings.notificationsEnabled else { return }
        let status = await currentAuthorizationStatus()
        guard status == .authorized || status == .provisional else { return }

        var state = loadState()
        let alerts = NotificationEvaluator.evaluate(
            data: data,
            settings: settings,
            state: &state
        )
        guard !alerts.isEmpty else { return }

        for alert in alerts {
            let content = UNMutableNotificationContent()
            content.title = alert.title
            content.body  = alert.body
            content.sound = .default
            // `.active` is the default banner priority — visible and audible
            // when not in Focus, but not timeSensitive (which would require
            // an additional entitlement and break through Focus).
            content.interruptionLevel = .active

            // Identifier is keyed on ring, kind, normalised reset date, and
            // (for pace alerts) the 20% usage bucket. This matches the dedup
            // key structure in NotificationState so the OS-level identifier is
            // stable across fetches within the same bucket/window combination.
            let normalisedResets = alert.resetsAt.map { NotificationState.normalise($0) }
            let bucketSuffix = alert.kind == .pace ? ".b\(Int(alert.usagePercent / 20))" : ""
            let id = "\(alert.ring.rawValue).\(alert.kind.rawValue)\(bucketSuffix).\(normalisedResets?.timeIntervalSince1970 ?? 0)"
            let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
            try? await center.add(request)
        }

        saveState(state)
    }

    // MARK: - State persistence

    private func loadState() -> NotificationState {
        guard let data = defaults.data(forKey: stateKey),
              let state = try? JSONDecoder().decode(NotificationState.self, from: data)
        else { return NotificationState() }
        return state
    }

    private func saveState(_ state: NotificationState) {
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    /// Wipe dedup state — called on sign-out so the next signed-in user
    /// doesn't inherit someone else's "already fired" record.
    func resetState() {
        defaults.removeObject(forKey: stateKey)
    }
}
