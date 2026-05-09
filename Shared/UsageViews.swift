import SwiftUI
import TipKit

// MARK: - TipKit tips

/// Surfaces the "Try Demo Mode" button to anyone who lands on the sign-in
/// screen — including App Store reviewers, who Apple specifically asks us
/// to give a way of evaluating the app without an Anthropic account. The
/// tip is keyed off `Events.signInScreenShown` so it appears the first
/// time the LoginPromptView is presented and dismisses itself once the
/// user interacts (or after Apple's default `maxDisplayCount`).
@available(iOS 17.0, macOS 14.0, *)
struct DemoModeTip: Tip {
    /// Bumped each time `LoginPromptView` appears.
    static let signInShown = Event(id: "signInScreenShown")

    var title: Text {
        Text("Try Demo Mode")
    }

    var message: Text? {
        Text("No Anthropic account? Tap **Try Demo** to explore the app with sample usage data.")
    }

    var image: Image? {
        Image(systemName: "wand.and.stars")
    }

    var rules: [Rule] {
        // Show after the sign-in screen has appeared at least once.
        [#Rule(Self.signInShown) { $0.donations.count >= 1 }]
    }
}

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

// MARK: - Horizontal progress bar (Claude Design)

/// Horizontal progress-bar variant of `UsageRowView`. Used for Claude Design
/// usage, which gets its own visual treatment since it's a separate-from-chat
/// quota that doesn't map onto the concentric rings.
///
/// The bar uses the same colour palette as the concentric rings:
/// `anthropicOrange` for the fill and `anthropicOrange.opacity(0.2)` for the
/// track. The optional SF symbol is overlaid at the leading edge of the track,
/// mirroring how ring arcs carry their own visual weight at the start point.
///
/// Layout:
///   `Label  ·  X%`
///   `[icon|=====fill===|--------track--------]`
///   `resets …`                     (when applicable)
struct UsageProgressBarView: View {
    let label: String
    let utilization: Double
    let resetsAt: Date?
    var systemImage: String? = nil
    var isApplicable: Bool = true
    /// Fraction of the quota period that has elapsed (0–1). Rendered as a
    /// faded arc behind the solid usage fill, matching the ring treatment.
    var timeProgress: Double = 0

    /// Matches the visual weight of the ring strokes when rendered at a
    /// typical popover width (~240 pt). Adjust if the rings' `lineWidth`
    /// formula (`dim * 0.13`) ever changes for the popover layout.
    private let barHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Label · reset hint · percentage — all on one header row so the
            // reset cadence sits visually distinct from the ring rows below.
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(isApplicable ? .primary : .secondary)
                if isApplicable, let resets = resetsAt {
                    Text("·")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    Text("resets \(resets.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(isApplicable ? String(format: "%.0f%%", utilization) : "N/A")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isApplicable ? .primary : .secondary)
            }

            // Custom capsule bar styled to match the ring palette.
            // Width is capped at 90 % of the available row so it doesn't
            // visually crowd the trailing edge.
            GeometryReader { geo in
                let usageFraction = min(max(utilization  / 100.0, 0), 1)
                let timeFraction  = min(max(timeProgress,          0), 1)

                ZStack(alignment: .leading) {
                    // Track — same as ring unfilled arc
                    Capsule()
                        .fill(ConcentricCirclesView.anthropicOrange.opacity(0.2))

                    // Time-elapsed fill — same faded layer the rings use
                    if isApplicable && timeFraction > 0 {
                        Capsule()
                            .fill(ConcentricCirclesView.anthropicOrange.opacity(0.35))
                            .frame(width: geo.size.width * timeFraction)
                    }

                    // Usage fill — same as ring solid arc; drawn on top so it
                    // covers the faded time layer when usage has outrun time.
                    if isApplicable {
                        Capsule()
                            .fill(ConcentricCirclesView.anthropicOrange)
                            .frame(width: geo.size.width * usageFraction)
                    }

                    // Icon at the leading edge, overlaid on whatever is behind it
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: barHeight * 0.55, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.leading, 6)
                    }
                }
                .frame(height: barHeight)
            }
            .frame(height: barHeight)
        }
        .opacity(isApplicable ? 1.0 : 0.65)
    }
}

// MARK: - Login Prompt

struct LoginPromptView: View {
    let onLogin: () -> Void
    /// Optional — when supplied, surfaces a "Try Demo" secondary button
    /// that flips the app into mock-data mode. Required by App Review
    /// (Guideline 2.1(a)) so reviewers can evaluate the UI without going
    /// through Claude.ai's web sign-in.
    var onDemoMode: (() -> Void)? = nil

    /// Single instance of the TipKit tip so it survives re-renders.
    @available(iOS 17.0, macOS 14.0, *)
    private static let demoTip = DemoModeTip()

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

            if let onDemoMode {
                demoButton(onDemoMode)
            }
        }
        .padding(.vertical, 8)
        .task {
            if #available(iOS 17.0, macOS 14.0, *) {
                // Donate the event so the tip's display rule can fire next
                // time the view appears.
                await DemoModeTip.signInShown.donate()
            }
        }
    }

    @ViewBuilder
    private func demoButton(_ onDemoMode: @escaping () -> Void) -> some View {
        let base = Button("Try Demo", action: onDemoMode)
            .buttonStyle(.bordered)
            .controlSize(.small)

        // `popoverTip` only exists on iOS / macOS; the shared file is also
        // compiled into the watch target where the modifier is unavailable.
        #if os(iOS) || os(macOS)
        if #available(iOS 17.0, macOS 14.0, *) {
            base.popoverTip(Self.demoTip)
        } else {
            base
        }
        #else
        base
        #endif
    }
}

// MARK: - Refreshing View

/// Shown in place of the rings/login screen while the app is in the middle of
/// its 25-second confirmation window — it has a past successful session but the
/// current fetch failed. Replaces the old transient-error silencer: instead of
/// silently swallowing errors and keeping stale rings on screen, we show an
/// explicit "we're checking" state so the user always knows what's happening.
struct RefreshingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Refreshing Data")
                .font(.headline)
            Text("Reconnecting…")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Offline View

/// Shown when the 25-second retry window expires and the last failure was a
/// network-layer error (no connectivity, connection reset, timeout). Gives the
/// user explicit Retry and Sign Out options rather than routing them to the
/// login screen when their session is almost certainly still valid.
struct OfflineView: View {
    let onRetry: () -> Void
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Connection")
                .font(.headline)
            Text("Unable to reach Claude. Check your internet connection and try again.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button("Sign Out", action: onSignOut)
                    .buttonStyle(.bordered)
            }
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
