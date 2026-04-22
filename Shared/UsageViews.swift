import SwiftUI

/// Fraction of the period that has elapsed (0.0–1.0).
func timeElapsed(resetsAt: Date?, period: TimeInterval) -> Double {
    guard let resets = resetsAt, period > 0 else { return 0 }
    let remaining = resets.timeIntervalSinceNow
    return max(0, min(1, 1.0 - remaining / period))
}

/// Builds a CircleRendererInput from UsageData.
func circleInput(from data: UsageData) -> CircleRendererInput {
    CircleRendererInput(
        sessionProgress: data.sessionUtilization / 100.0,
        sonnetProgress: data.sonnetWeeklyUtilization / 100.0,
        allModelsProgress: data.allModelsWeeklyUtilization / 100.0,
        sessionTimeProgress: timeElapsed(resetsAt: data.sessionResetsAt, period: 5 * 3600),
        sonnetTimeProgress: timeElapsed(resetsAt: data.sonnetWeeklyResetsAt, period: 7 * 86400),
        allModelsTimeProgress: timeElapsed(resetsAt: data.allModelsWeeklyResetsAt, period: 7 * 86400),
        sonnetApplicable: data.sonnetWeeklyApplicable
    )
}

// MARK: - Shared Row View

struct UsageRowView: View {
    let label: String
    let utilization: Double
    let resetsAt: Date?
    /// Optional SF symbol shown to the left as a subtle ring legend indicator.
    var systemImage: String? = nil
    /// When `false`, the row is rendered in a dimmed grey state with "N/A"
    /// instead of a percentage, for tiers where this particular metric
    /// isn't exposed by the API (e.g. Pro users have no Sonnet-weekly limit).
    /// Defaults to `true` so existing call sites are unaffected.
    var isApplicable: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(iconTint)
                    .frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(isApplicable ? .primary : .secondary)
                    Spacer()
                    Text(isApplicable ? String(format: "%.0f%%", utilization) : "N/A")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isApplicable ? .primary : .secondary)
                }
                // When not applicable there's no reset date anyway, and even
                // if one snuck through we'd rather suppress it than imply
                // this metric is ticking down.
                if isApplicable, let resets = resetsAt {
                    Text("resets \(resets.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
        }
        .opacity(isApplicable ? 1.0 : 0.65)
    }

    private var iconTint: Color {
        isApplicable ? ConcentricCirclesView.anthropicOrange.opacity(0.8) : .secondary
    }
}

// MARK: - Login Prompt

struct LoginPromptView: View {
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Sign in to Claude")
                .font(.headline)
            Text("Sign in with your Claude account to view usage data.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign In") { onLogin() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Error View

struct ErrorDisplayView: View {
    let error: String
    let onRetry: () -> Void
    let onReLogin: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.secondary)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Retry", action: onRetry)
                Button("Sign In Again", action: onReLogin)
            }
        }
    }
}
