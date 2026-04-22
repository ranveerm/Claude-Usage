import Foundation

enum SharedDefaults {
    private static let suiteName = "group.com.ranveer.ClaudeYourRings"
    private static let key = "latestUsage"

    static func save(_ data: UsageData) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        if let encoded = try? JSONEncoder().encode(data) {
            defaults.set(encoded, forKey: key)
        }
    }

    static func load() -> UsageData? {
        guard let defaults = UserDefaults(suiteName: suiteName),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(UsageData.self, from: data)
    }
}
