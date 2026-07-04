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

    /// Demo mode bypasses the network entirely and serves a hand-picked
    /// `UsageData` fixture from `fetchUsage()`. Exists primarily so App
    /// Store reviewers (and curious users without an Anthropic account)
    /// can evaluate the UI without going through Claude.ai's web sign-in.
    /// Stored in UserDefaults. It isn't a credential, so the keychain
    /// indirection doesn't apply.
    var isDemoMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.demoModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.demoModeKey) }
    }
    private static let demoModeKey = "demoMode"

    /// `isConfigured` is what gates the LoginPromptView vs. the usage
    /// display. Demo mode counts as configured so the rings render without
    /// a real session.
    var isConfigured: Bool { !sessionKey.isEmpty || isDemoMode }

    /// Persisted flag that records whether the user was last known to be
    /// signed in with valid data. Set `true` after every successful fetch;
    /// set `false` when credentials are explicitly cleared. The UI uses
    /// this to decide whether a failed refresh is a "phantom sign-out"
    /// worth retrying (show a spinner) or a genuine first-time sign-in
    /// screen (show the login prompt immediately).
    var lastKnownSignedIn: Bool {
        get { UserDefaults.standard.bool(forKey: Self.lastKnownSignedInKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastKnownSignedInKey) }
    }
    private static let lastKnownSignedInKey = "lastKnownSignedIn"

    private init() {}

    func saveCredentials(sessionKey: String, cfClearance: String) {
        self.sessionKey = sessionKey
        self.cfClearance = cfClearance
        self.organizationId = ""
        // Real sign-in always wins over demo mode.
        isDemoMode = false
        SignOutSignal.markSignedIn()
    }

    /// Flips the app into demo mode and primes the shared cache so the
    /// watch and any widgets pick up the fixture immediately. No KVS
    /// broadcast. Demo mode is a per-device toggle, not a synced state.
    func enterDemoMode() {
        isDemoMode = true
        SharedDefaults.save(Self.demoFixture())
    }

    func clearCredentials() {
        sessionKey = ""
        cfClearance = ""
        organizationId = ""
        isDemoMode = false
        lastKnownSignedIn = false
        // Intentionally does NOT call SignOutSignal.markSignedOut().
        // Broadcasting is the job of the *explicit* sign-out call sites
        // (menu button / confirmation dialog). A reaction to a remote
        // sign-out must not re-broadcast. That cascades across devices.
    }

    func fetchUsage() async -> UsageData {
        // Demo mode short-circuits the network. The fixture is regenerated
        // each call so reset timestamps stay relative to "now". Handy when
        // the reviewer leaves the app open between checks.
        if isDemoMode {
            return Self.demoFixture()
        }
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
                return UsageData(error: msg, needsLogin: Self.isCloudflareError(msg))
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
                return UsageData(error: isCloudflare ? "Cloudflare challenge. Please sign in again." : "Session expired.",
                                 needsLogin: true)
            }
            if http.statusCode != 200 {
                let body = String(data: data, encoding: .utf8) ?? ""
                return UsageData(error: "HTTP \(http.statusCode): \(body.prefix(80))")
            }
            let result = parseUsageResponse(data)
            SharedDefaults.save(result)
            lastKnownSignedIn = true
            return result
        } catch {
            // Distinguish network-layer failures (no connectivity, connection
            // lost, timed out) from auth / server errors. The UI uses this to
            // show an "Offline" recovery screen instead of the login prompt.
            let isNet = Self.isNetworkLayerError(error)
            return UsageData(error: error.localizedDescription, isNetworkError: isNet)
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

    /// Marked `internal` (not `private`) so tests can exercise the pure
    /// JSON→UsageData mapping without going through the network.
    func parseUsageResponse(_ data: Data) -> UsageData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return UsageData(error: "Failed to parse response")
        }

        #if DEBUG
        // One-shot debugging aid: dump the raw response and any top-level
        // keys we don't currently consume. Lets us spot newly-added fields
        // (Claude Design, future labs releases, anything else) without
        // having to MITM the connection. Logs once per fetch on every
        // DEBUG build. No-op in Release.
        Self.logUnconsumedKeys(json: json, raw: data)
        #endif

        // Reset timestamps are ISO-8601. The current API uses 6-digit
        // fractional seconds and a "+00:00" offset (e.g.
        // "2026-07-04T10:19:59.673345+00:00"), which the strict formatter with
        // `.withFractionalSeconds` can reject, so `parseDate` retries without
        // the fractional part before giving up.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        func parseDate(_ raw: String?) -> Date? {
            guard let raw else { return nil }
            if let d = formatter.date(from: raw) { return d }
            let stripped = raw.replacingOccurrences(
                of: #"\.\d+"#, with: "", options: .regularExpression)
            return plainFormatter.date(from: stripped)
        }

        // Anthropic restructured `/usage` into a `limits` array. Each entry has
        // a `kind` ("session", "weekly_all", "weekly_scoped"), a `percent`
        // (0-100) and `resets_at`. The model-scoped weekly cap (currently
        // "Fable", per `scope.model.display_name`) lives here as
        // "weekly_scoped" and no longer as a top-level `seven_day_*` key (those
        // are now null). Read from `limits` where present, and fall back to the
        // legacy top-level blocks for older responses.
        let limits = (json["limits"] as? [[String: Any]]) ?? []
        func limitFor(_ kind: String) -> (utilization: Double, resetsAt: Date?)? {
            guard let entry = limits.first(where: { ($0["kind"] as? String) == kind })
            else { return nil }
            let pct = (entry["percent"] as? Double) ?? 0
            return (pct, parseDate(entry["resets_at"] as? String))
        }
        func parseLimit(_ key: String) -> (utilization: Double, resetsAt: Date?) {
            guard let block = json[key] as? [String: Any] else { return (0, nil) }
            let utilization = (block["utilization"] as? Double) ?? 0
            return (utilization, parseDate(block["resets_at"] as? String))
        }

        let session = limitFor("session")   ?? parseLimit("five_hour")
        let weekly  = limitFor("weekly_all") ?? parseLimit("seven_day")

        // Middle ring ("Fable only"): the model-scoped weekly cap. Prefer the
        // structured `limits` entry; fall back to the legacy seven_day_fable /
        // seven_day_sonnet keys for older responses. Kept in the `sonnet*`
        // fields internally so persisted payloads and settings keys stay
        // compatible. Presence signals a Max plan; Pro plans have no scoped cap.
        let scopedWeekly = limitFor("weekly_scoped")
        let fableLegacy = (json["seven_day_fable"] as? [String: Any])
                       ?? (json["seven_day_sonnet"] as? [String: Any])
        let fableUtil  = scopedWeekly?.utilization ?? (fableLegacy?["utilization"] as? Double) ?? 0
        let fableReset = scopedWeekly?.resetsAt ?? parseDate(fableLegacy?["resets_at"] as? String)
        let sonnetApplicable = scopedWeekly != nil || fableLegacy != nil

        // Claude Design (`seven_day_omelette`) is now null in the response, so
        // designBlock stays nil and the bar hides (the graceful-degrade added
        // in 1.2.0). Left in place in case the block returns.
        let designBlock = (json["seven_day_omelette"] as? [String: Any])
                       ?? (json["seven_day_design"] as? [String: Any])
                       ?? (json["seven_day_claude_design"] as? [String: Any])
                       ?? (json["claude_design"] as? [String: Any])
        let designUtil = (designBlock?["utilization"] as? Double) ?? 0
        let designReset = parseDate(designBlock?["resets_at"] as? String)

        return UsageData(
            sessionUtilization: session.utilization,
            sessionResetsAt: session.resetsAt,
            sonnetWeeklyUtilization: fableUtil,
            sonnetWeeklyResetsAt: fableReset,
            sonnetWeeklyApplicable: sonnetApplicable,
            allModelsWeeklyUtilization: weekly.utilization,
            allModelsWeeklyResetsAt: weekly.resetsAt,
            designWeeklyUtilization: designUtil,
            designWeeklyResetsAt: designReset,
            // Applicable only when the response actually carries a Design
            // block. Anthropic appears to have removed the separate Design
            // meter from `/usage`; deriving this from presence (rather than
            // hardcoding `true`) lets the UI hide the bar instead of showing a
            // misleading 0%. Same graceful-degrade pattern as Sonnet above.
            designWeeklyApplicable: designBlock != nil,
            lastRefreshed: Date()
        )
    }

    #if DEBUG
    /// Prints any top-level JSON keys the parser doesn't currently read,
    /// plus a pretty-printed dump of the full payload. Run once per fetch in
    /// DEBUG builds so we can spot newly-added fields (Claude Design quotas,
    /// future Anthropic Labs metrics) without having to MITM TLS traffic.
    private static func logUnconsumedKeys(json: [String: Any], raw: Data) {
        let known: Set<String> = [
            "five_hour", "seven_day", "limits",
            "seven_day_fable", "seven_day_sonnet",
            // Claude Design internal codename plus possible future renames.
            "seven_day_omelette", "seven_day_design",
            "seven_day_claude_design", "claude_design",
        ]
        let unread = json.keys.filter { !known.contains($0) }.sorted()
        if !unread.isEmpty {
            print("[UsageService] Unread keys in /usage response: \(unread)")
        }
        if let pretty = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]
        ),
           let str = String(data: pretty, encoding: .utf8) {
            print("[UsageService] /usage payload:\n\(str)")
        }
    }
    #endif

    private func applyHeaders(to request: inout URLRequest) {
        Self.applyHeaders(to: &request, sessionKey: sessionKey, cfClearance: cfClearance)
    }

    /// Stateless header application. Used by `verifyCredentials` so we can
    /// test credentials without persisting them to the keychain first.
    static func applyHeaders(to request: inout URLRequest, sessionKey: String, cfClearance: String) {
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

    /// Best-effort server-side session revocation. Fires a POST to Claude's
    /// logout endpoint so the session is invalidated on Anthropic's side,
    /// not just forgotten locally. Without this, every development sign-in
    /// piles up as an "active session" on the claude.ai dashboard, and a
    /// leaked sessionKey stays valid until natural expiry.
    ///
    /// Failures are swallowed silently. The caller has already committed
    /// to signing out regardless of what the server says.
    static func revokeSession(sessionKey: String, cfClearance: String) async {
        guard !sessionKey.isEmpty,
              let url = URL(string: "https://claude.ai/api/auth/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        applyHeaders(to: &request, sessionKey: sessionKey, cfClearance: cfClearance)
        request.timeoutInterval = 8
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Tests whether the given cookies can fetch data from the Claude API.
    /// Used by the login window to detect a successful sign-in without relying
    /// on WKWebView's navigation callbacks (which miss SPA routing changes).
    static func verifyCredentials(sessionKey: String, cfClearance: String) async -> Bool {
        guard !sessionKey.isEmpty,
              let url = URL(string: "https://claude.ai/api/organizations") else { return false }
        var request = URLRequest(url: url)
        applyHeaders(to: &request, sessionKey: sessionKey, cfClearance: cfClearance)
        request.timeoutInterval = 8

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// Marked `internal` so tests can assert detection rules without
    /// spinning up the network stack.
    static func isCloudflareError(_ message: String) -> Bool {
        message.contains("Just a moment") || message.contains("cf-ray") || message.contains("403")
    }

    /// Returns `true` when the error originates in the network transport
    /// layer (no connectivity, connection reset, DNS failure, timeout)
    /// rather than from an auth or server response. The UI uses this to
    /// show an "Offline" recovery screen instead of routing to login when
    /// the session is almost certainly still valid.
    static func isNetworkLayerError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// Hand-picked demo fixture used when `isDemoMode` is on. Numbers are
    /// chosen to exercise every visual state simultaneously: a partly-used
    /// 5-hour session, a moderately-used weekly all-models budget, a low
    /// Sonnet-weekly bar (Max tier), and a low Claude Design bar. The
    /// reviewer sees the full range of rings and the design progress bar
    /// in a single screen. Reset timestamps are anchored to `Date()` so
    /// the "resets in …" hints stay sensible across launches.
    static func demoFixture() -> UsageData {
        let now = Date()
        return UsageData(
            sessionUtilization: 42,
            sessionResetsAt: now.addingTimeInterval(2.5 * 3600),
            sonnetWeeklyUtilization: 33,
            sonnetWeeklyResetsAt: now.addingTimeInterval(4 * 86400),
            sonnetWeeklyApplicable: true,
            allModelsWeeklyUtilization: 51,
            allModelsWeeklyResetsAt: now.addingTimeInterval(4 * 86400),
            designWeeklyUtilization: 18,
            designWeeklyResetsAt: now.addingTimeInterval(4 * 86400),
            designWeeklyApplicable: true,
            lastRefreshed: now
        )
    }
}
