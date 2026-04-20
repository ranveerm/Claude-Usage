import Foundation

struct UsageData: Codable {
    var sessionUtilization: Double = 0
    var sessionResetsAt: Date?
    var sonnetWeeklyUtilization: Double = 0
    var sonnetWeeklyResetsAt: Date?
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
}

struct Organization: Decodable {
    let uuid: String
    let name: String
}
