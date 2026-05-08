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
    /// Code on a weekly cycle. The API field isn't officially documented yet
    /// (the help article notes Design "doesn't support audit logs or usage
    /// tracking yet"); the parser speculatively reads `seven_day_design` and
    /// sets `designWeeklyApplicable = false` when the block is absent — same
    /// graceful-degrade pattern Sonnet uses on Pro accounts.
    var designWeeklyUtilization: Double = 0
    var designWeeklyResetsAt: Date?
    /// Optimistically defaults to `true` so the bar renders even when the
    /// API response omits the design block. Anthropic's help article notes
    /// Design "doesn't support audit logs or usage tracking yet", so we'd
    /// rather show 0% honestly than hide the row behind an N/A. The parser
    /// keeps it at `true` regardless of field presence; only an explicit
    /// signal from elsewhere (future work) would set it `false`.
    var designWeeklyApplicable: Bool = true
    var lastRefreshed: Date?
    var error: String?
    var needsLogin: Bool = false
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
