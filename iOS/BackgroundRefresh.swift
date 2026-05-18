import BackgroundTasks
import WidgetKit

/// Orchestrates periodic background fetches on iOS so the widget and
/// watch complication stay fresh even when the user hasn't opened the app.
///
/// `BGAppRefreshTask` is a cooperative task: we tell iOS we'd like to run
/// again at least 15 minutes from now, and iOS picks the moment based on
/// recent foreground patterns, network, battery and system load. It won't
/// fire on a strict cadence. That's fine for usage-bar staleness but means:
///   - The `earliestBeginDate` is a floor, not a ceiling.
///   - A brand-new install may not get a single background run until the
///     user has opened the app a few times.
///   - The user must have Background App Refresh enabled (Settings → General
///     → Background App Refresh); otherwise the task never runs.
enum BackgroundRefresh {
    /// Declared in the iOS target's Info settings under
    /// `BGTaskSchedulerPermittedIdentifiers`. Must match exactly.
    static let taskIdentifier = "com.ranveer.ClaudeYourRings.refresh"

    /// Register the launch handler. Must be called before the App finishes
    /// launching, i.e. from the App struct's `init()`. Otherwise iOS
    /// refuses to dispatch the task ("no handler registered" crash).
    static func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Request iOS schedule another run. Call after every successful fetch
    /// (foreground *and* background). The scheduler only keeps the single
    /// most recent pending request, and our BG handler consumes it, so we
    /// need to re-queue continuously to stay in the rotation.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            DebugLog.log("BG schedule: submitted, earliest=\(request.earliestBeginDate?.description ?? "nil")")
        } catch {
            DebugLog.log("BG schedule: FAILED \(error)")
        }
    }

    // MARK: - Private

    private static func handle(_ task: BGAppRefreshTask) {
        DebugLog.log("BG handle: fired")
        // Re-queue *first*: if we crash or time out, at least we have a
        // future slot in the rotation. iOS coalesces duplicate submits.
        schedule()

        let fetchTask = Task {
            let data = await UsageService.shared.fetchUsage()
            DebugLog.log("BG handle: fetched, error=\(data.error ?? "nil"), needsLogin=\(data.needsLogin), sessionPct=\(Int(data.sessionUtilization.rounded()))")

            // Only propagate clean results. Errored or signed-out payloads
            // would otherwise overwrite a still-valid cache that the widget
            // and watch are already showing.
            if data.error == nil && !data.needsLogin {
                SharedDefaults.save(data)
                WatchSender.shared.send(data)
                WidgetCenter.shared.reloadAllTimelines()
                await MainActor.run { LiveActivityManager.shared.update(with: data) }
                await NotificationManager.shared.evaluateAndPost(
                    data: data,
                    settings: NotificationSettings.shared
                )
                DebugLog.log("BG handle: completed success")
                task.setTaskCompleted(success: true)
            } else {
                DebugLog.log("BG handle: skipping (dirty payload); marking failed")
                task.setTaskCompleted(success: false)
            }
        }

        task.expirationHandler = {
            DebugLog.log("BG handle: expiration handler invoked; cancelling fetch")
            // iOS is reclaiming us. Cancel the in-flight fetch so we
            // don't leak work. setTaskCompleted(success:) will have
            // already been called by the Task's completion path.
            fetchTask.cancel()
        }
    }
}
