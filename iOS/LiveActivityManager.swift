import ActivityKit
import Foundation
import UIKit

/// Manages the Claude session Live Activity lifecycle.
///
/// ## Lifecycle
///
/// - **Start**: `update(with:)` starts a banner when `sessionUtilization > 0`
///   and none is running. Starting is foreground-only (ActivityKit forbids it
///   from the background). A banner from a previous launch is adopted in
///   `init()` so background refreshes keep updating it.
///
/// - **Update**: called from `ContentView.acceptData()` (foreground) and the
///   `BGAppRefreshTask` handler (background). Each call pushes fresh numbers
///   and resets the rolling TTL (`ttl`). Updating an existing banner is
///   permitted from the background, so a background refresh keeps it current.
///
/// - **End**: when the session ends (`sessionUtilization` drops to 0, or an
///   error / signed-out payload arrives), when Live Activities are disabled,
///   or when the TTL lapses with no further refresh. The TTL end is
///   **best-effort**: it can only fire when iOS runs our code (a background
///   wake or the app being reopened), so a fully dormant device may keep the
///   banner until reopen or the system's own ~8-12h cap.
@MainActor
final class LiveActivityManager {
    static let shared = LiveActivityManager()

    /// Rolling time-to-live for the Live Activity. Every refresh (foreground
    /// tick or background poll) pushes the removal deadline out to `now + ttl`.
    /// If no refresh lands within the window the banner is dismissed on the
    /// next wake that notices (see `dismissIfExpired`). Also drives
    /// `ActivityContent.staleDate`, so the banner becomes `isStale` at the same
    /// moment it becomes eligible for dismissal.
    ///
    /// **`staleDate` only restyles the banner, it never removes it.** Removal
    /// is always our job via `endAll()` / `endIfRunning()`. That is why the TTL
    /// is best-effort: it fires only when iOS runs our code. A dormant device
    /// that gets no background wake keeps the banner until the app is reopened.
    private static let ttl: TimeInterval = 15 * 60

    private var currentActivity: Activity<ClaudeSessionAttributes>?

    /// App-group defaults shared with the iOS app and the widget extension,
    /// used to persist the TTL deadline. **Persistence is the whole point**:
    /// iOS kills suspended apps to reclaim memory and `BGAppRefreshTask` wakes
    /// a fresh process, so an in-memory deadline would reset to zero on every
    /// cold launch and the banner would never time out.
    private let defaults: UserDefaults

    /// Wall-clock time of the most recent push to the Live Activity (start or
    /// update). The TTL deadline is `lastUpdateAt + ttl`. Reset on every
    /// refresh, cleared on end, `nil` while nothing is running. **Persisted**
    /// to the app group so the deadline survives the process being killed
    /// between a background refresh and the wake that enforces the TTL.
    private var lastUpdateAt: Date? {
        get {
            let raw = defaults.double(forKey: Keys.lastUpdateAt)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set {
            if let value = newValue {
                defaults.set(value.timeIntervalSince1970, forKey: Keys.lastUpdateAt)
            } else {
                defaults.removeObject(forKey: Keys.lastUpdateAt)
            }
        }
    }

    private init() {
        defaults = UserDefaults(suiteName: "group.com.ranveer.ClaudeYourRings") ?? .standard
        // Adopt a banner that survived an app relaunch (warm, or a cold launch
        // from a BGAppRefreshTask) so background refreshes can keep updating it.
        // Never adopt an `.ended` one: pushing into a corpse is a no-op and
        // would block starting a fresh banner.
        currentActivity = Activity<ClaudeSessionAttributes>.activities.first {
            $0.activityState == .active || $0.activityState == .stale
        }

        // Seed the TTL clock if we adopted a banner but lost the timestamp
        // (first launch on this build, or the store was cleared). Don't
        // overwrite a live value: persistence exists so the deadline keeps
        // running even when our process didn't.
        if currentActivity != nil, lastUpdateAt == nil {
            lastUpdateAt = Date()
        }
    }

    private enum Keys {
        static let lastUpdateAt = "liveActivity.lastUpdateAt"
    }

    /// When the running banner's TTL lapses, or `nil` if nothing is running.
    /// `BackgroundRefresh` targets its next wake here so iOS has the best
    /// chance of either delivering a refresh (which resets the TTL) or letting
    /// us dismiss the lapsed banner. Read straight from app-group defaults so
    /// `BackgroundRefresh` can call it without hopping to the main actor.
    static func nextTTLExpiry() -> Date? {
        let defaults = UserDefaults(suiteName: "group.com.ranveer.ClaudeYourRings") ?? .standard
        let raw = defaults.double(forKey: Keys.lastUpdateAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw).addingTimeInterval(ttl)
    }

    /// A Live Activity can only be *started* while the app is in the
    /// foreground. We gate `start()` on this so a background caller (a
    /// `BGAppRefreshTask` running `update()`) never attempts a request that
    /// would fail.
    private var isForeground: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// Call after every successful fetch to keep the Live Activity in sync.
    /// Each call pushes fresh numbers and resets the rolling TTL.
    func update(with data: UsageData) {
        let isActive = data.sessionUtilization > 0
                    && data.error == nil
                    && !data.needsLogin
        let systemAllowed = ActivityAuthorizationInfo().areActivitiesEnabled
        let userAllowed = LiveActivitySettings.shared.enabled

        // System-level disable (Settings → Vibe Your Rings → Live Activities)
        // or in-app opt-out both short-circuit. Tear down anything running.
        guard systemAllowed, userAllowed else {
            endAll()
            return
        }

        // Session ended (rollover, error, or signed out): tear down.
        if !isActive {
            endIfRunning(state: contentState(from: data))
            return
        }

        let state = contentState(from: data)

        if let activity = currentActivity {
            // A refresh arrived (foreground tick or background poll). Push the
            // fresh numbers and reset the TTL. Updating an existing banner is
            // allowed from the background, which is what lets a BGAppRefreshTask
            // keep the lock screen current.
            lastUpdateAt = Date()
            let staleDate = Date().addingTimeInterval(Self.ttl)
            Task {
                await activity.update(
                    ActivityContent(state: state, staleDate: staleDate)
                )
            }
        } else {
            // No running banner. Start one, foreground-only: ActivityKit forbids
            // starting from the background. A background fetch that reaches here
            // (e.g. after a TTL-dismiss) just waits for the next foreground
            // fetch to start a fresh banner.
            guard isForeground else { return }
            lastUpdateAt = Date()
            start(state: state, resetsAt: data.sessionResetsAt)
        }
    }

    /// Best-effort enforcement of the "dismiss when no refresh arrives within
    /// `ttl`" rule. Called from a background wake that did **not** receive a
    /// fresh refresh (e.g. the fetch failed). If the running banner's TTL has
    /// lapsed, remove it. It can only fire when iOS actually wakes us: a fully
    /// dormant device that gets no wake leaves the banner up until the app is
    /// reopened or the system's own cap removes it.
    func dismissIfExpired() {
        guard currentActivity != nil, let last = lastUpdateAt else { return }
        if Date().timeIntervalSince(last) >= Self.ttl {
            endAll()
        }
    }

    /// Called when `LiveActivitySettings.enabled` toggles. On disable we end
    /// any running activity immediately. On enable we look at the cached
    /// payload and start straight away if a session is active.
    func applyEnabledChange() {
        if LiveActivitySettings.shared.enabled {
            refreshFromCache()
        } else {
            endAll()
        }
    }

    /// Re-encode the current state from `SharedDefaults` and push it. Used when
    /// a settings change (e.g. the Dynamic Island metric picker) needs to flow
    /// into a running activity without waiting for the next fetch.
    func refreshFromCache() {
        guard let cached = SharedDefaults.load() else { return }
        update(with: cached)
    }

    /// End any running activity. Safe to call when nothing is active.
    func endAll() {
        guard let activity = currentActivity else { return }
        let frozenState = activity.content.state
        currentActivity = nil
        lastUpdateAt = nil
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
        // Clear any banner the system is still showing (e.g. a leftover from a
        // previous run) so requesting a new activity never stacks two banners.
        for stray in Activity<ClaudeSessionAttributes>.activities {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }
        do {
            // Fresh now, so the TTL / staleDate is one window out.
            let staleDate = Date().addingTimeInterval(Self.ttl)
            let activity = try Activity.request(
                attributes: ClaudeSessionAttributes(),
                content: ActivityContent(state: state, staleDate: staleDate),
                pushType: nil
            )
            currentActivity = activity
        } catch {
        }
    }

    private func endIfRunning(state: ClaudeSessionAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        lastUpdateAt = nil
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
