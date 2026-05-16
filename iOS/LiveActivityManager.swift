import ActivityKit
import Foundation

/// Manages the Claude session Live Activity lifecycle.
///
/// ## Lifecycle
///
/// - **Start**: `update(with:)` is called on every successful fetch. When
///   `sessionUtilization > 0` and no activity is running, a new one is
///   started. Any pre-existing activity from a previous app launch is
///   adopted on `init()` so updates resume seamlessly.
///
/// - **Update**: called from both `ContentView.acceptData()` and the
///   `BGAppRefreshTask` background handler so the lock screen stays fresh.
///
/// - **End**: when `sessionUtilization` drops to 0, or the payload carries
///   an error or signed-out state.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<ClaudeSessionAttributes>?

    private init() {
        // Adopt any activity that survived an app relaunch.
        currentActivity = Activity<ClaudeSessionAttributes>.activities.first
    }

    /// Call after every successful fetch to keep the Live Activity in sync.
    func update(with data: UsageData) {
        // System-level disable (Settings → Vibe Your Rings → Live Activities)
        // OR in-app opt-out both short-circuit. If something is running when
        // either turns off we tear it down rather than leave a stale banner.
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              LiveActivitySettings.shared.enabled else {
            endAll()
            return
        }

        let isActive = data.sessionUtilization > 0
                    && data.error == nil
                    && !data.needsLogin
        let state = contentState(from: data)

        if isActive {
            if let activity = currentActivity {
                Task {
                    await activity.update(
                        ActivityContent(state: state, staleDate: data.sessionResetsAt)
                    )
                }
            } else {
                start(state: state, resetsAt: data.sessionResetsAt)
            }
        } else {
            endIfRunning(state: state)
        }
    }

    /// Called when `LiveActivitySettings.enabled` toggles. On disable we
    /// end any running activity immediately rather than waiting for the
    /// next fetch. On enable we look at the cached payload and start
    /// straight away if a session is active — feels more responsive than
    /// "your activity will appear next time we refresh".
    func applyEnabledChange() {
        if LiveActivitySettings.shared.enabled {
            refreshFromCache()
        } else {
            endAll()
        }
    }

    /// Re-encode the current state from `SharedDefaults` and push it. Used
    /// when a settings change (e.g. the Dynamic Island metric picker) needs
    /// to flow into a running activity without waiting for the next fetch.
    func refreshFromCache() {
        guard let cached = SharedDefaults.load() else { return }
        update(with: cached)
    }

    /// End any running activity. Safe to call when nothing is active.
    func endAll() {
        guard let activity = currentActivity else { return }
        let frozenState = activity.content.state
        currentActivity = nil
        Task {
            await activity.end(
                ActivityContent(state: frozenState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
    }

    // MARK: - Private

    private func start(
        state: ClaudeSessionAttributes.ContentState,
        resetsAt: Date?
    ) {
        do {
            let activity = try Activity.request(
                attributes: ClaudeSessionAttributes(),
                content: ActivityContent(state: state, staleDate: resetsAt),
                pushType: nil
            )
            currentActivity = activity
        } catch {
            #if DEBUG
            print("[LiveActivity] start failed: \(error)")
            #endif
        }
    }

    private func endIfRunning(state: ClaudeSessionAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
            currentActivity = nil
        }
    }

    private func contentState(
        from data: UsageData
    ) -> ClaudeSessionAttributes.ContentState {
        ClaudeSessionAttributes.ContentState(
            sessionUtilization: data.sessionUtilization,
            sonnetWeeklyUtilization: data.sonnetWeeklyUtilization,
            allModelsWeeklyUtilization: data.allModelsWeeklyUtilization,
            designWeeklyUtilization: data.designWeeklyUtilization,
            sonnetApplicable: data.sonnetWeeklyApplicable,
            designApplicable: data.designWeeklyApplicable,
            sessionResetsAt: data.sessionResetsAt,
            sonnetWeeklyResetsAt: data.sonnetWeeklyResetsAt,
            allModelsWeeklyResetsAt: data.allModelsWeeklyResetsAt,
            designWeeklyResetsAt: data.designWeeklyResetsAt,
            dynamicIslandMetric: LiveActivitySettings.shared.dynamicIslandMetric
        )
    }
}
