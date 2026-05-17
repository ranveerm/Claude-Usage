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
/// - **End**: when `sessionUtilization` drops to 0, the payload carries an
///   error or signed-out state, or the percentage hasn't moved for
///   `idleTimeout` — the user has stopped using Claude and the banner has
///   nothing useful to add.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Dismiss the activity if the displayed percentage hasn't changed for
    /// this long. Set at 10 minutes — a typical Claude reply burst moves
    /// the bar by ≥1 %, so a flat percentage for 10 minutes is a reliable
    /// signal the user has stepped away.
    private static let idleTimeout: TimeInterval = 10 * 60

    private var currentActivity: Activity<ClaudeSessionAttributes>?

    /// The wall-clock time at which we last saw the rounded session
    /// percentage change. Reset on start, on every observed change, and
    /// cleared on end. `nil` while no activity is running.
    private var lastPercentChangeAt: Date?

    /// Rounded session percentage at which the manager last idle-ended an
    /// activity. While this is set, `update(with:)` refuses to restart an
    /// activity at the same percentage — otherwise the very next fetch
    /// (foreground tick or BGAppRefreshTask) would silently re-create
    /// what we just dismissed and the user would perceive the banner as
    /// "never going away". Cleared when the percentage moves to a
    /// different integer value (signalling real Claude usage has
    /// resumed) or when the session resets / settings toggle off.
    private var suppressedAtPercent: Int?

    private init() {
        // Adopt any activity that survived an app relaunch. We can't
        // reconstruct exactly when its percentage last moved, so treat
        // adoption as a fresh observation — gives the user the full idle
        // window before we'd dismiss something we just inherited.
        currentActivity = Activity<ClaudeSessionAttributes>.activities.first
        if currentActivity != nil {
            lastPercentChangeAt = Date()
        }
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

        let currentPct = Int(data.sessionUtilization.rounded())
        let isActive = data.sessionUtilization > 0
                    && data.error == nil
                    && !data.needsLogin

        // Session naturally ended (rollover, error, or signed out): tear
        // down anything still running and clear suppression so the next
        // session can start fresh.
        if !isActive {
            endIfRunning(state: contentState(from: data))
            suppressedAtPercent = nil
            return
        }

        // Idle-suppression gate. If we recently dismissed an activity due
        // to inactivity, refuse to restart it at the same percentage.
        // Only a real change in usage clears the suppression.
        if let suppressed = suppressedAtPercent {
            if currentPct == suppressed {
                return
            }
            suppressedAtPercent = nil
        }

        let state = contentState(from: data)

        if let activity = currentActivity {
            let previous = Int(activity.content.state.sessionUtilization.rounded())

            if previous != currentPct {
                // Percentage moved — user is actively using Claude.
                lastPercentChangeAt = Date()
            } else if let last = lastPercentChangeAt,
                      Date().timeIntervalSince(last) >= Self.idleTimeout {
                // No movement for the full idle window — dismiss the
                // banner and remember the percentage so the next fetch
                // doesn't immediately recreate it.
                suppressedAtPercent = currentPct
                endAll()
                return
            }

            Task {
                await activity.update(
                    ActivityContent(state: state, staleDate: data.sessionResetsAt)
                )
            }
        } else {
            lastPercentChangeAt = Date()
            start(state: state, resetsAt: data.sessionResetsAt)
        }
    }

    /// Called when `LiveActivitySettings.enabled` toggles. On disable we
    /// end any running activity immediately rather than waiting for the
    /// next fetch. On enable we look at the cached payload and start
    /// straight away if a session is active — feels more responsive than
    /// "your activity will appear next time we refresh".
    func applyEnabledChange() {
        if LiveActivitySettings.shared.enabled {
            // Clear suppression on explicit re-enable — the user has just
            // opted back in, so any in-flight idle-end shouldn't keep them
            // from seeing the activity on the next fetch.
            suppressedAtPercent = nil
            refreshFromCache()
        } else {
            endAll()
            suppressedAtPercent = nil
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
        lastPercentChangeAt = nil
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
        lastPercentChangeAt = nil
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
