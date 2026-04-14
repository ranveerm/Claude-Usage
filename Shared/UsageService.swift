import Foundation

final class UsageService {
    static let shared = UsageService()

    var sessionKey: String {
        get { KeychainHelper.load(key: "sessionKey") ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(key: "sessionKey") }
            else { KeychainHelper.save(key: "sessionKey", value: newValue) }
        }
    }

    var cfClearance: String {
        get { KeychainHelper.load(key: "cfClearance") ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(key: "cfClearance") }
            else { KeychainHelper.save(key: "cfClearance", value: newValue) }
        }
    }

    var organizationId: String {
        get { KeychainHelper.load(key: "organizationId") ?? "" }
        set {
            if newValue.isEmpty { KeychainHelper.delete(key: "organizationId") }
            else { KeychainHelper.save(key: "organizationId", value: newValue) }
        }
    }

    var isConfigured: Bool { !sessionKey.isEmpty }

    private init() {}

    func saveCredentials(sessionKey: String, cfClearance: String) {
        self.sessionKey = sessionKey
        self.cfClearance = cfClearance
        self.organizationId = ""
    }

    func clearCredentials() {
        sessionKey = ""
        cfClearance = ""
        organizationId = ""
    }

    func fetchUsage() async -> UsageData {
        guard isConfigured else {
            return UsageData(needsLogin: true)
        }

        if organizationId.isEmpty {
            do {
                let orgs = try await fetchOrganizations()
                guard let first = orgs.first else {
                    return UsageData(error: "No organizations found")
                }
                organizationId = first.uuid
            } catch {
                let msg = error.localizedDescription
                return UsageData(error: msg, needsLogin: isCloudflareError(msg))
            }
        }

        let urlString = "https://claude.ai/api/organizations/\(organizationId)/usage"
        guard let url = URL(string: urlString) else {
            return UsageData(error: "Invalid URL")
        }

        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return UsageData(error: "Bad response")
            }
            if http.statusCode == 403 {
                let body = String(data: data, encoding: .utf8) ?? ""
                let isCloudflare = body.contains("cf-ray") || body.contains("Just a moment")
                return UsageData(error: isCloudflare ? "Cloudflare challenge — please sign in again." : "Session expired.",
                                 needsLogin: true)
            }
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                return UsageData(error: "HTTP \(http.statusCode): \(body.prefix(80))")
            }
            let result = parseUsageResponse(data)
            SharedDefaults.save(result)
            return result
        } catch {
            return UsageData(error: error.localizedDescription)
        }
    }

    private func fetchOrganizations() async throws -> [Organization] {
        guard let url = URL(string: "https://claude.ai/api/organizations") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        applyHeaders(to: &request)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "API", code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                          userInfo: [NSLocalizedDescriptionKey: body])
        }
        return try JSONDecoder().decode([Organization].self, from: data)
    }

    private func parseUsageResponse(_ data: Data) -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UsageData(error: "Failed to parse response")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func parseLimit(_ key: String) -> (utilization: Double, resetsAt: Date?) {
            guard let block = json[key] as? [String: Any] else { return (0, nil) }
            let utilization = (block["utilization"] as? Double) ?? 0
            let resetsAt = (block["resets_at"] as? String).flatMap { formatter.date(from: $0) }
            return (utilization, resetsAt)
        }

        let session = parseLimit("five_hour")
        let weekly = parseLimit("seven_day")
        let sonnet = parseLimit("seven_day_sonnet")

        return UsageData(
            sessionUtilization: session.utilization,
            sessionResetsAt: session.resetsAt,
            sonnetWeeklyUtilization: sonnet.utilization,
            sonnetWeeklyResetsAt: sonnet.resetsAt,
            allModelsWeeklyUtilization: weekly.utilization,
            allModelsWeeklyResetsAt: weekly.resetsAt,
            lastRefreshed: Date()
        )
    }

    private func applyHeaders(to request: inout URLRequest) {
        var cookieParts = ["sessionKey=\(sessionKey)"]
        if !cfClearance.isEmpty { cookieParts.append("cf_clearance=\(cfClearance)") }

        let headers: [String: String] = [
            "accept": "*/*",
            "content-type": "application/json",
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "anthropic-client-platform": "web_claude_ai",
            "anthropic-client-version": "1.0.0",
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
            "origin": "https://claude.ai",
            "referer": "https://claude.ai/",
            "cookie": cookieParts.joined(separator: "; "),
        ]
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func isCloudflareError(_ message: String) -> Bool {
        message.contains("Just a moment") || message.contains("cf-ray") || message.contains("403")
    }
}
