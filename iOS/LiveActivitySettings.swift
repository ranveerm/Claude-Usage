import Combine
import Foundation

/// User preference for whether Live Activities should run on this device.
///
/// **Default: off.** Live Activities are opt-in because they consume lock-
/// screen and Dynamic Island real estate every time a session is active —
/// users who prefer the widget-only experience shouldn't have an activity
/// banner foisted on them on first launch.
///
/// Toggling the value fans out to `LiveActivityManager`:
/// - **On**: the manager looks at the cached `SharedDefaults` payload and
///   starts an activity immediately if a session is currently active, so
///   the user sees a result without waiting for the next refresh.
/// - **Off**: the manager ends any running activity right away rather than
///   waiting for the next fetch to no-op into an end state.
///
/// Persisted to the app-group suite so the toggle survives reinstalls of
/// the widget extension (extensions read the same group).
final class LiveActivitySettings: ObservableObject {
    static let shared = LiveActivitySettings()

    private let defaults: UserDefaults

    /// `true` when the user has opted in. Default `false` (off) — matches
    /// the rest of the on-demand surfaces (notifications also default off).
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: Keys.enabled)
            Task { @MainActor in
                LiveActivityManager.shared.applyEnabledChange()
            }
        }
    }

    /// Which metric the Dynamic Island ring tracks. Defaults to `.session`
    /// since that's the only ring that meaningfully changes during a Claude
    /// session — the weekly rings barely budge over five hours.
    @Published var dynamicIslandMetric: DynamicIslandMetric {
        didSet {
            defaults.set(dynamicIslandMetric.rawValue, forKey: Keys.dynamicIslandMetric)
            Task { @MainActor in
                LiveActivityManager.shared.refreshFromCache()
            }
        }
    }

    private init() {
        let defaults = UserDefaults(suiteName: "group.com.ranveer.ClaudeYourRings") ?? .standard
        self.defaults = defaults
        // `bool(forKey:)` returns false for unset keys — exactly the
        // default we want, no `object(forKey:)` dance needed.
        self.enabled = defaults.bool(forKey: Keys.enabled)
        let storedMetric = defaults.string(forKey: Keys.dynamicIslandMetric) ?? ""
        self.dynamicIslandMetric = DynamicIslandMetric(rawValue: storedMetric) ?? .session
    }

    private enum Keys {
        static let enabled = "liveActivity.enabled"
        static let dynamicIslandMetric = "liveActivity.dynamicIslandMetric"
    }
}
