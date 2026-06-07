import Foundation

struct UsageData: Codable {
    var sessionUtilization: Double = 0
    var sessionResetsAt: Date?
    var sonnetWeeklyUtilization: Double = 0
    var sonnetWeeklyResetsAt: Date?
    /// `false` when the logged-in tier doesn't expose a Sonnet-specific weekly
    /// limit (Pro). `true` for Max (the block is present in the API response
    /// even when utilisation is 0). The UI uses this to show "N/A" and dim
    /// the middle ring rather than a misleading 0%.
    /// Defaults to `true` so previously-cached payloads decode as Max.
    var sonnetWeeklyApplicable: Bool = true
    var allModelsWeeklyUtilization: Double = 0
    var allModelsWeeklyResetsAt: Date?
    /// Claude Design (Anthropic Labs) is metered separately from chat/Claude
    /// Code on a weekly cycle, surfaced under the internal codename
    /// `seven_day_omelette`. The parser reads it (with fallbacks) and derives
    /// `designWeeklyApplicable` from whether the block is present.
    var designWeeklyUtilization: Double = 0
    var designWeeklyResetsAt: Date?
    /// `true` only when the `/usage` response actually contains the Design
    /// block. Anthropic appears to have removed the separate Design meter, so
    /// the parser derives this from block presence (the same graceful-degrade
    /// pattern Sonnet uses on Pro accounts) and every surface hides the Design
    /// bar entirely when it's `false`, rather than showing a misleading 0%.
    /// Defaults to `false` so an empty/placeholder payload doesn't flash a
    /// stray Design bar before the first real fetch.
    var designWeeklyApplicable: Bool = false
    var lastRefreshed: Date?
    var error: String?
    var needsLogin: Bool = false
    /// `true` when the failure is a network-layer error (no connectivity,
    /// connection lost, timeout) rather than an auth / server error. The UI
    /// uses this to show an "Offline" recovery screen with Retry / Sign Out
    /// instead of immediately routing to the login flow.
    /// Defaults to `false` so cached payloads decode safely.
    var isNetworkError: Bool = false
}

struct CircleRendererInput: Equatable {
    let sessionProgress: Double
    let sonnetProgress: Double
    let allModelsProgress: Double
    var sessionTimeProgress: Double = 0
    var sonnetTimeProgress: Double = 0
    var allModelsTimeProgress: Double = 0
    /// When `false`, the middle (Sonnet) ring renders in grey rather than
    /// the usual orange. Mirrors `UsageData.sonnetWeeklyApplicable`.
    var sonnetApplicable: Bool = true
}

struct Organization: Decodable {
    let uuid: String
    let name: String
}
