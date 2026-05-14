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
        case .session:   return "Current Session"
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

    /// - Parameters:
    ///   - usageBucket: For pace alerts, pass `Int(utilization / 20)` so each
    ///     20% segment (0–19, 20–39, …) gets its own dedup slot. Omit (nil)
    ///     for threshold alerts, which fire once per window regardless of level.
    mutating func markFired(ring: UsageRing, kind: AlertKind, resetsAt: Date?, usageBucket: Int? = nil) {
        guard let resetsAt else { return }
        firedFor[Self.key(ring, kind, bucket: usageBucket)] = Self.normalise(resetsAt)
    }

    func hasFired(ring: UsageRing, kind: AlertKind, for resetsAt: Date?, usageBucket: Int? = nil) -> Bool {
        guard let resetsAt else { return false }
        return firedFor[Self.key(ring, kind, bucket: usageBucket)] == Self.normalise(resetsAt)
    }

    private static func key(_ ring: UsageRing, _ kind: AlertKind, bucket: Int? = nil) -> String {
        if let bucket {
            return "\(ring.rawValue).\(kind.rawValue).b\(bucket)"
        }
        return "\(ring.rawValue).\(kind.rawValue)"
    }

    /// Round to the nearest minute to absorb server-side timestamp jitter.
    /// The server recomputes `resetsAt` as "now + remaining" on every request,
    /// so two fetches within the same window produce slightly different Dates.
    /// Rounding to the minute ensures exact equality holds across fetches
    /// while still detecting a genuine window rollover (≥ 1 minute apart).
    static func normalise(_ date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (t / 60).rounded() * 60)
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
                    body: timeRemainingString(resetsAt: resetsAt, now: now)
                ))
                state.markFired(ring: ring, kind: .threshold, resetsAt: resetsAt)
            }

            // --- Pace rule ---
            // Dedup by 20% bucket so alerts at 63% and 75% count as the same
            // event, but crossing into 80% (bucket 4) fires a fresh alert.
            let paceBucket = Int(utilization / 20)
            if settings.paceAlertEnabled(for: ring),
               let timeProgress = timeProgress(resetsAt: resetsAt, period: ring.periodSeconds, now: now),
               utilization / 100.0 > timeProgress,
               !state.hasFired(ring: ring, kind: .pace, for: resetsAt, usageBucket: paceBucket)
            {
                out.append(PendingNotification(
                    ring: ring,
                    kind: .pace,
                    usagePercent: utilization,
                    resetsAt: resetsAt,
                    title: "\(ring.label) at \(Int(utilization.rounded()))% — pace alert",
                    body: timeRemainingString(resetsAt: resetsAt, now: now)
                ))
                state.markFired(ring: ring, kind: .pace, resetsAt: resetsAt, usageBucket: paceBucket)
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

    /// Human-readable countdown used as the notification body for all alert
    /// kinds. Examples: "Resets in 4h 23m", "Resets in 45m", "Resets soon".
    private static func timeRemainingString(resetsAt: Date?, now: Date) -> String {
        guard let resetsAt else { return "Resets soon" }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 60 else { return "Resets soon" }
        let totalMinutes = Int(remaining / 60)
        let days    = totalMinutes / (60 * 24)
        let hours   = (totalMinutes % (60 * 24)) / 60
        let minutes = totalMinutes % 60
        if days > 0 {
            return hours > 0 ? "Resets in \(days)d \(hours)h" : "Resets in \(days)d"
        } else if hours > 0 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        } else {
            return "Resets in \(minutes)m"
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
