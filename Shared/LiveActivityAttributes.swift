import ActivityKit
import Foundation

/// Attributes for the Claude session Live Activity.
///
/// There are no static attributes — the activity is purely data-driven.
///
/// ContentState holds the four usage metrics and is refreshed on every
/// successful fetch (foreground and background). The activity is started
/// when `sessionUtilization > 0` and ended when the session resets or
/// the user signs out.
struct ClaudeSessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 0–100 for all utilization fields.
        var sessionUtilization: Double
        var sonnetWeeklyUtilization: Double
        var allModelsWeeklyUtilization: Double
        var designWeeklyUtilization: Double
        /// `false` for Pro accounts where the Sonnet metric isn't exposed.
        var sonnetApplicable: Bool
        /// `false` when the Design quota block is absent from the API response.
        var designApplicable: Bool
        /// Reset timestamps — drive both the "Resets in X" text and the
        /// faded time-progress fill in the underlying UsageProgressBarView.
        var sessionResetsAt: Date?
        var sonnetWeeklyResetsAt: Date?
        var allModelsWeeklyResetsAt: Date?
        var designWeeklyResetsAt: Date?
        /// Which metric the Dynamic Island ring should track. Driven by the
        /// user's choice in Settings. Defaults to `.session` so payloads
        /// from older app versions still decode sensibly.
        var dynamicIslandMetric: DynamicIslandMetric = .session
    }
}

// MARK: - Dynamic Island metric selection

/// The four metrics the user can pin to the Dynamic Island ring.
/// Defined here (alongside the activity attributes) rather than in an
/// iOS-only file because the widget extension also has to switch on it.
enum DynamicIslandMetric: String, CaseIterable, Codable, Identifiable, Hashable {
    case session, sonnetWeekly, allModelsWeekly, design

    var id: String { rawValue }

    var label: String {
        switch self {
        case .session:         "Session (5h)"
        case .sonnetWeekly:    "Sonnet Weekly"
        case .allModelsWeekly: "All Models Weekly"
        case .design:          "Claude Design"
        }
    }

    /// SF Symbol shown at the centre of the Dynamic Island ring.
    var systemImage: String {
        switch self {
        case .session:         "calendar.day.timeline.left"
        case .sonnetWeekly:    "calendar"
        case .allModelsWeekly: "shippingbox"
        case .design:          "paintbrush.pointed.fill"
        }
    }
}

extension ClaudeSessionAttributes.ContentState {
    /// Utilization of the user-selected Dynamic Island metric.
    var dynamicIslandUtilization: Double {
        switch dynamicIslandMetric {
        case .session:         sessionUtilization
        case .sonnetWeekly:    sonnetWeeklyUtilization
        case .allModelsWeekly: allModelsWeeklyUtilization
        case .design:          designWeeklyUtilization
        }
    }

    /// Whether the user-selected metric is exposed by the API for this tier.
    /// Returns `false` on Pro accounts when the user has picked Sonnet, for
    /// example — the widget renders the ring greyed out with N/A.
    var dynamicIslandApplicable: Bool {
        switch dynamicIslandMetric {
        case .session:         true
        case .sonnetWeekly:    sonnetApplicable
        case .allModelsWeekly: true
        case .design:          designApplicable
        }
    }
}
