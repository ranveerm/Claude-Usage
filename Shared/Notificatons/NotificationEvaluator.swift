import Foundation

// MARK: - Ring identity

/// The three quota windows the evaluator knows about. Kept as a separate
/// enum (rather than re-using `UsageData` fields inline) so alerts can be
/// keyed by a stable string value in persisted dedup state.
enum UsageRing: String, CaseIterable {
    case session, sonnet, allModels

    /// Human-readable label used in notification copy.
    var label: String {
        switch self {
        case .session:   return "Session (5h)"
        case .sonnet:    return "Sonnet weekly"
        case .allModels: return "All-models weekly"
        }
    }

    /// Duration of the reset window in seconds. Used to compute
    /// "% of time elapsed" from a future `resetsAt` timestamp.
    var periodSeconds: TimeInterval {
        switch self {
        case .session:              return 5 * 3600
        case .sonnet, .allModels:   return 7 * 86400
        }
    }
}

// MARK: - Alert kinds

/// Which rule fired a notification. String-backed because it's part of
/// the dedup key persisted to UserDefaults.
enum AlertKind: String {
    /// Usage crossed the absolute % threshold the user configured.
    case threshold
    /// Usage outpaced the elapsed time for the reset window (i.e.
    /// `utilization% > timeElapsed%`). Mirrors the curved overshoot
    /// rendering on the ring.
    case pace
}

/// A single notification ready to be posted by `NotificationManager`.
/// Kept POD so the evaluator stays pure and testable.
struct PendingNotification: Equatable {
    let ring: UsageRing
    let kind: AlertKind
    let usagePercent: Double
    let resetsAt: Date?
    let title: String
    let body: String
}

// MARK: - Dedup state

/// Per-(ring, kind) record of "which reset window have we already fired for".
/// When a fresh `resetsAt` arrives (new window started) the stored date no
/// longer matches and the alert is free to fire again.
///
/// Codable so it round-trips through app-group UserDefaults, which is where
/// `NotificationManager` persists it between launches.
struct NotificationState: Codable, Equatable {
    private var firedFor: [String: Date] = [:]

    mutating func markFired(ring: UsageRing, kind: AlertKind, resetsAt: Date?) {
        guard let resetsAt else { return }
        firedFor[Self.key(ring, kind)] = resetsAt
    }

    func hasFired(ring: UsageRing, kind: AlertKind, for resetsAt: Date?) -> Bool {
        guard let resetsAt else { return false }
        return firedFor[Self.key(ring, kind)] == resetsAt
    }

    private static func key(_ ring: UsageRing, _ kind: AlertKind) -> String {
        "\(ring.rawValue).\(kind.rawValue)"
    }
}

// MARK: - Evaluator

/// Pure function layer: turns `(UsageData, Settings, State)` into a list of
/// alerts to fire. No UserNotifications, no UserDefaults, no side effects
/// except the in-out state — which makes this the unit-testable core.
enum NotificationEvaluator {

    static func evaluate(
        data: UsageData,
        settings: NotificationSettings,
        state: inout NotificationState,
        now: Date = Date()
    ) -> [PendingNotification] {
        guard settings.notificationsEnabled else { return [] }
        guard data.error == nil, !data.needsLogin else { return [] }

        var out: [PendingNotification] = []

        for ring in UsageRing.allCases {
            // Pro tier: the Sonnet ring is inactive, don't alert on it.
            if ring == .sonnet && !data.sonnetWeeklyApplicable { continue }

            let utilization = utilization(data: data, ring: ring)
            let resetsAt    = resetsAt(data: data, ring: ring)

            // --- Threshold rule ---
            if settings.thresholdAlertsEnabled,
               utilization >= settings.thresholdPercent,
               !state.hasFired(ring: ring, kind: .threshold, for: resetsAt)
            {
                out.append(PendingNotification(
                    ring: ring,
                    kind: .threshold,
                    usagePercent: utilization,
                    resetsAt: resetsAt,
                    title: "\(ring.label) at \(Int(utilization.rounded()))%",
                    body: "You've crossed your \(Int(settings.thresholdPercent))% threshold for this window."
                ))
                state.markFired(ring: ring, kind: .threshold, resetsAt: resetsAt)
            }

            // --- Pace rule ---
            if settings.paceAlertEnabled(for: ring),
               let timeProgress = timeProgress(resetsAt: resetsAt, period: ring.periodSeconds, now: now),
               utilization / 100.0 > timeProgress,
               !state.hasFired(ring: ring, kind: .pace, for: resetsAt)
            {
                let timePct = Int((timeProgress * 100).rounded())
                out.append(PendingNotification(
                    ring: ring,
                    kind: .pace,
                    usagePercent: utilization,
                    resetsAt: resetsAt,
                    title: "\(ring.label) — pace alert",
                    body: "Usage is at \(Int(utilization.rounded()))% with only \(timePct)% of the window elapsed."
                ))
                state.markFired(ring: ring, kind: .pace, resetsAt: resetsAt)
            }
        }

        return out
    }

    // MARK: - Field lookups

    private static func utilization(data: UsageData, ring: UsageRing) -> Double {
        switch ring {
        case .session:   return data.sessionUtilization
        case .sonnet:    return data.sonnetWeeklyUtilization
        case .allModels: return data.allModelsWeeklyUtilization
        }
    }

    private static func resetsAt(data: UsageData, ring: UsageRing) -> Date? {
        switch ring {
        case .session:   return data.sessionResetsAt
        case .sonnet:    return data.sonnetWeeklyResetsAt
        case .allModels: return data.allModelsWeeklyResetsAt
        }
    }

    /// Returns 0…1 fraction of the window that has elapsed, or `nil` if
    /// `resetsAt` is missing (in which case we can't say where in the
    /// window we are, so pace alerts are skipped).
    private static func timeProgress(resetsAt: Date?, period: TimeInterval, now: Date) -> Double? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        // Window has ended — we're past the reset. Don't fire, the next
        // fetch will bring a fresh resetsAt that resets dedup.
        guard remaining > 0, period > 0 else { return nil }
        let elapsed = period - remaining
        return max(0, min(1, elapsed / period))
    }
}
