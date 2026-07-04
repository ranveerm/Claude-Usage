import SwiftUI
import TipKit

// MARK: - TipKit tips

/// Surfaces the "Try Demo Mode" button to anyone who lands on the sign-in
/// screen, including App Store reviewers, who Apple specifically asks us
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

// MARK: - Platform-adaptive fonts for list rows
//
// iOS has more screen real estate per row and a touch target to fill, so the
// list text steps up one rung on the type scale. macOS uses the compact sizes
// that fit inside the menu-bar popover.

#if os(iOS)
let rowLabelFont: Font = .subheadline
let rowResetFont: Font = .footnote
#elseif os(watchOS)
let rowLabelFont: Font = .footnote
let rowResetFont: Font = .caption
#else // macOS
let rowLabelFont: Font = .footnote
let rowResetFont: Font = .caption
#endif

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

    /// When `true` the row shows the next-precision unit in parentheses
    /// next to the relative label. Toggled by tapping the row.
    @State private var showPrecise = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(rowLabelFont)
                    .foregroundStyle(iconTint)
                    .frame(width: 14)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label)
                        .font(rowLabelFont)
                        .foregroundStyle(isApplicable ? .primary : .secondary)
                    Spacer()
                    Text(isApplicable ? String(format: "%.0f%%", utilization) : "N/A")
                        .font(rowLabelFont)
                        .monospacedDigit()
                        .foregroundStyle(isApplicable ? .primary : .secondary)
                }
                // When not applicable there's no reset date anyway, and even
                // if one snuck through we'd rather suppress it than imply
                // this metric is ticking down.
                if isApplicable, let resets = resetsAt {
                    // Collapsed: "Resets in 2 days" (system formatter, rounds).
                    // Expanded: "🔄 3 days (and 12 hours)" — custom floor-based
                    // label so the parts add up and "in" is absent. The whole
                    // collapsed/expanded blocks carry .transition(.opacity) so
                    // SwiftUI cross-fades them; the parenthetical fades in
                    // independently at the trailing end of the HStack.
                    HStack(spacing: 4) {
                        if showPrecise {
                            Image(systemName: "arrow.trianglehead.clockwise")
                                .imageScale(.small)
                            Text(expandedMainLabel(for: resets))
                        } else {
                            Text("Resets \(resets.formatted(.relative(presentation: .named)))")
                        }
                        if showPrecise, let detail = preciseParenthetical(for: resets) {
                            Text("(\(detail))")
                                .transition(.opacity)
                        }
                    }
                    .font(rowResetFont)
                    .foregroundColor(.secondary)
                    .animation(.easeInOut(duration: 0.3), value: showPrecise)
                }
            }
        }
        .opacity(isApplicable ? 1.0 : 0.65)
        // Tap anywhere on the row to reveal / hide the sub-unit breakdown.
        // Guard means N/A rows and rows with no reset date are inert.
        .contentShape(Rectangle())
        .onTapGesture {
            guard isApplicable, resetsAt != nil else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showPrecise.toggle() }
        }
    }

    private var iconTint: Color {
        isApplicable ? ConcentricCirclesView.anthropicOrange.opacity(0.8) : .secondary
    }

    /// Floored main label for the expanded state — "3 days", "5 hours",
    /// "45 minutes". Uses integer division rather than the system formatter's
    /// rounding, so 3.5 days yields "3 days" and the parenthetical "and 12 hours"
    /// adds up correctly.
    private func expandedMainLabel(for date: Date) -> String {
        let interval = max(0, date.timeIntervalSinceNow)
        let days = Int(interval / 86400)
        if days > 0 { return "\(days) \(days == 1 ? "day" : "days")" }
        let hours = Int(interval / 3600)
        if hours > 0 { return "\(hours) \(hours == 1 ? "hour" : "hours")" }
        let mins = Int(interval / 60)
        return mins > 0 ? "\(mins) \(mins == 1 ? "minute" : "minutes")" : "soon"
    }

    /// Sub-unit detail shown in parentheses, e.g. "and 12 hours" when the main
    /// label conveys days, or "and 45 minutes" when it conveys hours. Returns
    /// `nil` when the interval is already exact at the displayed unit so the
    /// parenthetical is suppressed (e.g. precisely 2 days with 0 hours left).
    private func preciseParenthetical(for date: Date) -> String? {
        let interval   = max(0, date.timeIntervalSinceNow)
        let totalDays  = Int(interval / 86400)
        let remHours   = Int(interval.truncatingRemainder(dividingBy: 86400) / 3600)
        let totalHours = Int(interval / 3600)
        let remMins    = Int(interval.truncatingRemainder(dividingBy: 3600) / 60)
        if totalDays  > 0 { return remHours > 0 ? "and \(remHours) \(remHours == 1 ? "hour" : "hours")"     : nil }
        if totalHours > 0 { return remMins  > 0 ? "and \(remMins) \(remMins  == 1 ? "minute" : "minutes")"  : nil }
        return nil
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
    /// Matches the visual weight of an individual ring stroke. Default of 14
    /// is tuned for the macOS popover (rings are 100 pt → `dim * 0.13` ≈ 13).
    /// iOS callers should pass the matching value for their ring frame
    /// (e.g. 32 when the rings are sized at 250 pt) so the bar looks like
    /// a fourth ring laid out flat rather than a thinner sibling element.
    var barHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Label · reset hint · percentage all on one header row so the
            // reset cadence sits visually distinct from the ring rows below.
            HStack(spacing: 4) {
                Text(label)
                    .font(rowLabelFont)
                    .foregroundStyle(isApplicable ? .primary : .secondary)
                if isApplicable, let resets = resetsAt {
                    Text("·")
                        .font(rowResetFont)
                        .foregroundColor(.secondary)
                    Text("Resets \(resets.formatted(.relative(presentation: .named)))")
                        .font(rowResetFont)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(isApplicable ? String(format: "%.0f%%", utilization) : "N/A")
                    .font(rowLabelFont)
                    .monospacedDigit()
                    .foregroundStyle(isApplicable ? .primary : .secondary)
            }

            // Custom capsule bar styled to match the ring palette.
            //
            // Layout strategy: the Capsule track is the layout-driving view.
            // its width comes directly from the parent VStack, guaranteeing a
            // true capsule shape. Fill layers are applied as overlays so that
            // a GeometryReader inside the overlay reads the already-resolved
            // capsule frame (avoiding the zero-width pitfall that affects a
            // bare GeometryReader placed as a sibling in the VStack).
            //
            // Fill layers use `Rectangle` (not `Capsule`) so that at low
            // fractions the shape hugs the leading curve instead of collapsing
            // into a floating circle. The `clipShape(Capsule())` on the inner
            // ZStack trims both ends of each fill to the capsule boundary.
            let usageFraction = min(max(utilization / 100.0, 0), 1)
            let timeFraction  = min(max(timeProgress,         0), 1)

            Capsule()
                .fill(ConcentricCirclesView.anthropicOrange.opacity(0.2))
                .frame(height: barHeight)
                // Fill layers overlaid so the capsule track drives layout.
                .overlay(alignment: .leading) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            // Time-elapsed fill. Faded layer behind solid usage.
                            // Same UnevenRoundedRectangle treatment as the usage
                            // fill: zero leading radius (outer capsule clip owns
                            // the left curve) and a clamped trailing radius so the
                            // right cap is rounded without becoming a vertical pill.
                            if isApplicable && timeFraction > 0 {
                                let timeWidth = geo.size.width * timeFraction
                                let timeTrailingR = min(barHeight / 2, timeWidth / 2)
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: timeTrailingR,
                                    topTrailingRadius: timeTrailingR
                                )
                                .fill(ConcentricCirclesView.anthropicOrange.opacity(0.35))
                                .frame(width: timeWidth, height: geo.size.height)
                            }

                            // Usage fill. Solid arc drawn on top of time layer.
                            // UnevenRoundedRectangle gives the fill a rounded
                            // trailing cap (visible when usage < time progress)
                            // while keeping the leading corners at zero so the
                            // outer clipShape(Capsule()) is the sole authority
                            // on the left-side curve. The trailing radius is
                            // clamped to half the fill width so the shape never
                            // becomes a vertical pill at very low fractions.
                            if isApplicable {
                                let fillWidth = geo.size.width * usageFraction
                                let trailingR = min(barHeight / 2, fillWidth / 2)
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 0,
                                    bottomLeadingRadius: 0,
                                    bottomTrailingRadius: trailingR,
                                    topTrailingRadius: trailingR
                                )
                                .fill(ConcentricCirclesView.anthropicOrange)
                                .frame(width: fillWidth, height: geo.size.height)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height,
                               alignment: .leading)
                        .clipShape(Capsule())
                    }
                }
                // Icon overlay sits on top of all fill layers
                .overlay(alignment: .leading) {
                    if let systemImage {
                        Image(systemName: systemImage)
                            .font(.system(size: barHeight * 0.55, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.leading, 6)
                    }
                }
        }
        .opacity(isApplicable ? 1.0 : 0.65)
    }
}

// MARK: - Login Prompt

struct LoginPromptView: View {
    let onLogin: () -> Void
    /// Optional. When supplied, surfaces a "Try Demo" secondary button
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
/// its 25-second confirmation window. It has a past successful session but the
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
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.secondary)
            Text(error)
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

// MARK: - Previews

#if DEBUG
/// Interactive wrapper that lets the preview confirm:
/// - The clock icon replaces "Resets in"
/// - Tapping reveals the parenthetical detail with an opacity + layout animation
/// - N/A rows are inert
private struct UsageRowPreviewWrapper: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Session row — tap reveals "(and N minutes)" sub-unit
            UsageRowView(
                label: "Session (5h)",
                utilization: 57,
                resetsAt: Date().addingTimeInterval(1.8 * 3600),
                systemImage: "calendar.day.timeline.left"
            )
            Divider()
            // Weekly row — tap reveals "(and N hours)" — the motivating case
            UsageRowView(
                label: "Fable Only",
                utilization: 33,
                resetsAt: Date().addingTimeInterval(2.5 * 86400),
                systemImage: "book"
            )
            Divider()
            // Exactly whole days — parenthetical suppressed (nothing to add)
            UsageRowView(
                label: "All Models Weekly",
                utilization: 42,
                resetsAt: Date().addingTimeInterval(3 * 86400),
                systemImage: "shippingbox"
            )
            Divider()
            // N/A row — tap should be inert
            UsageRowView(
                label: "Fable Only",
                utilization: 0,
                resetsAt: nil,
                systemImage: "book",
                isApplicable: false
            )
        }
        .padding()
    }
}

#Preview("Row — tap to reveal parenthetical") {
    UsageRowPreviewWrapper()
}

#Preview("Row — dark mode") {
    UsageRowPreviewWrapper()
        .preferredColorScheme(.dark)
}

#Preview("Row — large dynamic type") {
    UsageRowPreviewWrapper()
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
