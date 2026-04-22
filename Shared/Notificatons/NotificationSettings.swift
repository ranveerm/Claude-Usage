import Foundation
import Combine

/// User-facing notification preferences, persisted to the app-group
/// UserDefaults so widget/complication processes can read them later
/// without their own copy of the values.
///
/// Exposed as a singleton `ObservableObject` — SettingsView binds to it
/// directly, and mutations fan out through the `didSet` on each published
/// property. There's no explicit save method; every setter persists.
final class NotificationSettings: ObservableObject {
    static let shared = NotificationSettings()

    private let defaults: UserDefaults

    // MARK: Published preferences

    /// Master switch. `false` short-circuits every evaluation and suppresses
    /// the permission prompt — the system prompt is only requested the first
    /// time the user flips this on.
    @Published var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    /// Whether the absolute-threshold rule is active. Separate from the
    /// master switch so a user can leave notifications on but only receive
    /// pace alerts.
    @Published var thresholdAlertsEnabled: Bool {
        didSet { defaults.set(thresholdAlertsEnabled, forKey: Keys.thresholdAlertsEnabled) }
    }

    /// 50…95 in increments of 5. Bound to a slider.
    @Published var thresholdPercent: Double {
        didSet { defaults.set(thresholdPercent, forKey: Keys.thresholdPercent) }
    }

    // Pace alerts are opt-in per ring so a user can track e.g. the 5h
    // session without noise from the weekly rings.
    @Published var paceAlertSession: Bool {
        didSet { defaults.set(paceAlertSession, forKey: Keys.paceAlertSession) }
    }
    @Published var paceAlertSonnet: Bool {
        didSet { defaults.set(paceAlertSonnet, forKey: Keys.paceAlertSonnet) }
    }
    @Published var paceAlertAllModels: Bool {
        didSet { defaults.set(paceAlertAllModels, forKey: Keys.paceAlertAllModels) }
    }

    // MARK: Init

    private init() {
        let defaults = UserDefaults(suiteName: "group.com.ranveer.ClaudeYourRings") ?? .standard
        self.defaults = defaults

        // Threshold defaults: alerts on, 80%. Using `object(forKey:)` to
        // distinguish "never set" from "set to false/0" — a plain `bool(...)`
        // would silently default thresholdAlertsEnabled to false.
        self.notificationsEnabled    = defaults.bool(forKey: Keys.notificationsEnabled)
        self.thresholdAlertsEnabled  = (defaults.object(forKey: Keys.thresholdAlertsEnabled) as? Bool) ?? true
        self.thresholdPercent        = (defaults.object(forKey: Keys.thresholdPercent) as? Double) ?? 80
        self.paceAlertSession        = defaults.bool(forKey: Keys.paceAlertSession)
        self.paceAlertSonnet         = defaults.bool(forKey: Keys.paceAlertSonnet)
        self.paceAlertAllModels      = defaults.bool(forKey: Keys.paceAlertAllModels)
    }

    /// Is pace alerting enabled for a given ring? Single lookup helper so
    /// the evaluator doesn't care which backing property matches which ring.
    func paceAlertEnabled(for ring: UsageRing) -> Bool {
        switch ring {
        case .session:   return paceAlertSession
        case .sonnet:    return paceAlertSonnet
        case .allModels: return paceAlertAllModels
        }
    }

    // MARK: Keys

    private enum Keys {
        static let notificationsEnabled   = "notif.enabled"
        static let thresholdAlertsEnabled = "notif.thresholdEnabled"
        static let thresholdPercent       = "notif.thresholdPercent"
        static let paceAlertSession       = "notif.paceSession"
        static let paceAlertSonnet        = "notif.paceSonnet"
        static let paceAlertAllModels     = "notif.paceAllModels"
    }
}
