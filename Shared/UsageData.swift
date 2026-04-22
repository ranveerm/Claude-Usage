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
