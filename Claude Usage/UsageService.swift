import Foundation

struct UsageRecord: Decodable {
    let snapshot_at: String
    let model: String?
    let input_tokens: Int
    let output_tokens: Int
    let cache_creation_input_tokens: Int?
    let cache_read_input_tokens: Int?
}

struct UsageResponse: Decodable {
    let data: [UsageRecord]
    let has_more: Bool
    let next_page: String?
}

struct UsageData {
    var sessionTokens: Int = 0
    var sonnetWeeklyTokens: Int = 0
    var allModelsWeeklyTokens: Int = 0
    var lastRefreshed: Date?
    var error: String?
}

final class UsageService {
    static let shared = UsageService()

    private let baseURL = "https://api.anthropic.com/v1/organizations/usage_report/messages"
    private let apiVersion = "2023-06-01"
    private var appLaunchDate = Date()

    var apiKey: String {
        get { UserDefaults.standard.string(forKey: "anthropic_api_key") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "anthropic_api_key") }
    }

    var sessionLimit: Int {
        get { UserDefaults.standard.integer(forKey: "session_limit").nonZero ?? 1_000_000 }
        set { UserDefaults.standard.set(newValue, forKey: "session_limit") }
    }

    var sonnetWeeklyLimit: Int {
        get { UserDefaults.standard.integer(forKey: "sonnet_weekly_limit").nonZero ?? 10_000_000 }
        set { UserDefaults.standard.set(newValue, forKey: "sonnet_weekly_limit") }
    }

    var allModelsWeeklyLimit: Int {
        get { UserDefaults.standard.integer(forKey: "all_models_weekly_limit").nonZero ?? 20_000_000 }
        set { UserDefaults.standard.set(newValue, forKey: "all_models_weekly_limit") }
    }

    private init() {}

    func resetSessionStart() {
        appLaunchDate = Date()
    }

    func fetchUsage() async -> UsageData {
        guard !apiKey.isEmpty else {
            return UsageData(error: "No API key configured")
        }

        let weekStart = Self.startOfISOWeek()
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let weekStartStr = formatter.string(from: weekStart)
        let nowStr = formatter.string(from: now)
        let sessionStartStr = formatter.string(from: appLaunchDate)

        async let weeklyResult = fetchUsageData(from: weekStartStr, to: nowStr)
        async let sessionResult = fetchUsageData(from: sessionStartStr, to: nowStr)

        let weekly = await weeklyResult
        let session = await sessionResult

        switch (weekly, session) {
        case (.failure(let err), _):
            return UsageData(error: err.localizedDescription)
        case (_, .failure(let err)):
            return UsageData(error: err.localizedDescription)
        case (.success(let weeklyRecords), .success(let sessionRecords)):
            let sessionTokens = Self.totalTokens(weeklyRecords: sessionRecords)
            let sonnetWeekly = Self.totalTokens(weeklyRecords: weeklyRecords, modelFilter: "claude-sonnet")
            let allWeekly = Self.totalTokens(weeklyRecords: weeklyRecords)

            return UsageData(
                sessionTokens: sessionTokens,
                sonnetWeeklyTokens: sonnetWeekly,
                allModelsWeeklyTokens: allWeekly,
                lastRefreshed: Date()
            )
        }
    }

    private func fetchUsageData(from startingAt: String, to endingAt: String) async -> Result<[UsageRecord], Error> {
        var allRecords: [UsageRecord] = []
        var nextPage: String? = nil

        repeat {
            var components = URLComponents(string: baseURL)!
            var queryItems = [
                URLQueryItem(name: "starting_at", value: startingAt),
                URLQueryItem(name: "ending_at", value: endingAt),
                URLQueryItem(name: "bucket_width", value: "1d"),
                URLQueryItem(name: "group_by", value: "model"),
            ]
            if let page = nextPage {
                queryItems.append(URLQueryItem(name: "page", value: page))
            }
            components.queryItems = queryItems

            guard let url = components.url else {
                return .failure(URLError(.badURL))
            }

            var request = URLRequest(url: url)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    return .failure(URLError(.badServerResponse))
                }
                if httpResponse.statusCode != 200 {
                    let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                    return .failure(NSError(domain: "API", code: httpResponse.statusCode,
                                           userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)"]))
                }
                let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
                allRecords.append(contentsOf: decoded.data)
                nextPage = decoded.has_more ? decoded.next_page : nil
            } catch {
                return .failure(error)
            }
        } while nextPage != nil

        return .success(allRecords)
    }

    private static func totalTokens(weeklyRecords records: [UsageRecord], modelFilter: String? = nil) -> Int {
        records
            .filter { record in
                guard let filter = modelFilter else { return true }
                return record.model?.lowercased().contains(filter) ?? false
            }
            .reduce(0) { sum, record in
                sum + record.input_tokens + record.output_tokens
                    + (record.cache_creation_input_tokens ?? 0)
                    + (record.cache_read_input_tokens ?? 0)
            }
    }

    private static func startOfISOWeek() -> Date {
        var cal = Calendar(identifier: .iso8601)
        cal.firstWeekday = 2 // Monday
        let now = Date()
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        return cal.date(from: components) ?? now
    }
}

private extension Int {
    var nonZero: Int? { self == 0 ? nil : self }
}
