import Foundation
import os.log

/// Thin wrapper around `os.Logger` used while investigating the Live
/// Activity idle-dismissal flakiness. Routed to the unified system log
/// so it can be tailed from Console.app on the connected Mac without
/// needing Xcode attached.
///
/// **This whole file is temporary scaffolding.** When the investigation
/// is done, delete `iOS/DebugLog.swift` and strip the `DebugLog.log(...)`
/// call sites from `LiveActivityManager` / `BackgroundRefresh`.
///
/// ## Viewing in Console.app
///
/// 1. Open **Console.app** on the Mac with the device tethered.
/// 2. Select the device in the sidebar (left column).
/// 3. In the search bar, filter by **subsystem**.
///    `subsystem:com.ranveer.ClaudeYourRings` shows everything; add
///    `category:live-activity` to narrow further.
/// 4. Under **Action → Include Info Messages** make sure info/debug
///    messages are visible (default off for some Mac versions).
///
/// `.notice` is the level used here because it survives default Console
/// filters even in Release / TestFlight builds. `.debug` and `.info`
/// can be elided by the system unless explicitly enabled.
enum DebugLog {
    private static let logger = Logger(
        subsystem: "com.ranveer.ClaudeYourRings",
        category: "live-activity"
    )

    /// Append a log entry visible in Console.app at `.notice` level.
    ///
    /// The interpolation uses `privacy: .public` so messages render
    /// verbatim instead of being redacted to `<private>`. The dynamic
    /// parts of these log lines (percentages, elapsed seconds, activity
    /// IDs) carry no PII.
    static func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
    }
}
