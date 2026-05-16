import ActivityKit
import SwiftUI
import WidgetKit

// MARK: - Live Activity Widget

struct UsageLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudeSessionAttributes.self) { context in
            // `.activityBackgroundTint(nil)` explicitly opts out of any
            // tint, so the system renders its default Liquid Glass surround
            // on iOS 26 (and a translucent material on earlier versions).
            // Layering our own `.background(.material)` *inside* the content
            // view would paint on top of that glass and make the banner look
            // flat — keep the content minimal and let the system handle it.
            //
            // NB. Neither this tint nor the system's Liquid Glass banner
            // surround render in the `#Preview(..., as: .content)` canvas:
            // Xcode draws only the inner content view, without the lock-
            // screen banner chrome around it. To verify the runtime look,
            // run on a simulator/device with an active session.
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            // The user-chosen metric (Settings → Live Activities → Dynamic
            // Island) drives the ring + percentage in every slot.
            let metric = context.state.dynamicIslandMetric
            let utilization = context.state.dynamicIslandUtilization
            let applicable = context.state.dynamicIslandApplicable

            return DynamicIsland {
                // Expanded — shown when the user long-presses the island.
                DynamicIslandExpandedRegion(.leading) {
                    DynamicIslandRingView(
                        progress: utilization / 100,
                        systemImage: metric.systemImage,
                        applicable: applicable
                    )
                    .frame(width: 60, height: 60)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(metric.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(applicable ? String(format: "%.0f%%", utilization) : "N/A")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .foregroundStyle(applicable
                                             ? ConcentricCirclesView.anthropicOrange
                                             : .secondary)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        ExpandedMiniBar(
                            label: "Session",
                            utilization: context.state.sessionUtilization,
                            applicable: true
                        )
                        ExpandedMiniBar(
                            label: "Sonnet",
                            utilization: context.state.sonnetWeeklyUtilization,
                            applicable: context.state.sonnetApplicable
                        )
                        ExpandedMiniBar(
                            label: "All Models",
                            utilization: context.state.allModelsWeeklyUtilization,
                            applicable: true
                        )
                        ExpandedMiniBar(
                            label: "Design",
                            utilization: context.state.designWeeklyUtilization,
                            applicable: context.state.designApplicable
                        )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                }
            } compactLeading: {
                // Plain ring on the leading side — the metric identity moves
                // to the trailing slot where the icon now flanks the percentage.
                DynamicIslandRingView(
                    progress: utilization / 100,
                    systemImage: metric.systemImage,
                    applicable: applicable,
                    showsCentreIcon: false
                )
                .padding(2)
            } compactTrailing: {
                // Icon + percentage share the same anthropicOrange tint so
                // they read as a single grouped unit. The icon identifies
                // which metric the percentage is reporting.
                HStack(spacing: 3) {
                    Image(systemName: metric.systemImage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(applicable
                                         ? ConcentricCirclesView.anthropicOrange
                                         : .secondary)
                    Text(applicable ? String(format: "%.0f%%", utilization) : "N/A")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(applicable
                                         ? ConcentricCirclesView.anthropicOrange
                                         : .secondary)
                }
                .padding(.trailing, 4)
            } minimal: {
                // Minimal slot is a single element — keep the icon at the
                // centre of the ring so the metric stays identifiable.
                DynamicIslandRingView(
                    progress: utilization / 100,
                    systemImage: metric.systemImage,
                    applicable: applicable
                )
                .padding(1)
            }
        }
    }
}

// MARK: - Lock Screen / Notification Banner View

/// Four tall horizontal bars with the icon, label, reset hint, and
/// percentage all embedded *inside* the bar — a denser variant of the
/// iOS `UsageProgressBarView`. The lock screen has the room to fit it.
///
/// The container uses the iOS 26 `.glassEffect()` so the lock-screen
/// wallpaper bleeds through with the system Liquid Glass treatment that
/// matches surrounding controls (notifications, the time, the camera/torch
/// affordances).
struct LiveActivityLockScreenView: View {
    let state: ClaudeSessionAttributes.ContentState

    var body: some View {
        // Just the content — no Rectangle, no `.background(.material)`.
        // The lock screen Live Activity banner is rendered by the system
        // with its own Liquid Glass surround. Layering a material on top
        // would obscure that glass and make the banner look flat.
        VStack(alignment: .leading, spacing: 5) {
            LiveActivityBarRow(
                label: "Session (5h)",
                utilization: state.sessionUtilization,
                resetsAt: state.sessionResetsAt,
                systemImage: "calendar.day.timeline.left",
                applicable: true,
                timeProgress: timeElapsed(resetsAt: state.sessionResetsAt,
                                          period: 5 * 3600)
            )
            LiveActivityBarRow(
                label: "Sonnet Weekly",
                utilization: state.sonnetWeeklyUtilization,
                resetsAt: state.sonnetWeeklyResetsAt,
                systemImage: "calendar",
                applicable: state.sonnetApplicable,
                timeProgress: timeElapsed(resetsAt: state.sonnetWeeklyResetsAt,
                                          period: 7 * 86400)
            )
            LiveActivityBarRow(
                label: "All Models Weekly",
                utilization: state.allModelsWeeklyUtilization,
                resetsAt: state.allModelsWeeklyResetsAt,
                systemImage: "shippingbox",
                applicable: true,
                timeProgress: timeElapsed(resetsAt: state.allModelsWeeklyResetsAt,
                                          period: 7 * 86400)
            )
            LiveActivityBarRow(
                label: "Claude Design",
                utilization: state.designWeeklyUtilization,
                resetsAt: state.designWeeklyResetsAt,
                systemImage: "paintbrush.pointed.fill",
                applicable: state.designApplicable,
                timeProgress: timeElapsed(resetsAt: state.designWeeklyResetsAt,
                                          period: 7 * 86400)
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Single bar with icon + label + reset hint + percentage all inside.
/// The row sizes itself to its content (semantic fonts + standard padding)
/// rather than declaring a fixed height — that way Dynamic Type and the
/// system's preferred metrics flow through automatically.
private struct LiveActivityBarRow: View {
    let label: String
    let utilization: Double
    let resetsAt: Date?
    let systemImage: String
    let applicable: Bool
    let timeProgress: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.footnote.weight(.semibold))

            Text(label)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)

            if applicable, let resets = resetsAt {
                Text("Resets \(resets.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .opacity(0.85)
            }

            Spacer(minLength: 4)

            Text(applicable ? String(format: "%.0f%%", utilization) : "N/A")
                .font(.footnote.weight(.semibold).monospacedDigit())
        }
        // White text with a soft black shadow stays legible on every shade
        // of orange (full fill, time-progress fill, and faint track) and
        // across whatever lock-screen wallpaper bleeds through the glass.
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.28), radius: 1, x: 0, y: 0.5)
        .opacity(applicable ? 1 : 0.65)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background {
            // Rendering the capsule layers as the row's background lets
            // the bar size itself to whatever the HStack content needs.
            GeometryReader { geo in
                let usageFraction = min(max(utilization / 100.0, 0), 1)
                let timeFraction  = min(max(timeProgress,         0), 1)

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ConcentricCirclesView.anthropicOrange.opacity(0.2))

                    if applicable && timeFraction > 0 {
                        Capsule()
                            .fill(ConcentricCirclesView.anthropicOrange.opacity(0.35))
                            .frame(width: geo.size.width * timeFraction)
                    }

                    if applicable {
                        Capsule()
                            .fill(ConcentricCirclesView.anthropicOrange)
                            .frame(width: geo.size.width * usageFraction)
                    }
                }
            }
        }
        .clipShape(Capsule())
    }
}

// MARK: - Shared sub-views

/// Compact label + thin bar used in the Dynamic Island expanded bottom region.
private struct ExpandedMiniBar: View {
    let label: String
    let utilization: Double
    let applicable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(ConcentricCirclesView.anthropicOrange.opacity(0.2))
                    if applicable {
                        Capsule()
                            .fill(ConcentricCirclesView.anthropicOrange)
                            .frame(width: geo.size.width * min(max(utilization / 100, 0), 1))
                    }
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Dynamic Island Ring View

/// Single ring with the selected metric's icon at the centre.
/// Used in all three Dynamic Island presentations (compact leading,
/// minimal, expanded leading). The ring's lineWidth is set to ≈13 % of
/// the view diameter so the icon at the centre has room to breathe at
/// every size from 22 pt (minimal) up to 60 pt (expanded).
struct DynamicIslandRingView: View {
    let progress: Double
    let systemImage: String
    let applicable: Bool
    /// When `false` the ring renders without the centre icon. The compact
    /// leading slot turns this off because the icon is shown next to the
    /// percentage in the trailing slot instead.
    var showsCentreIcon: Bool = true

    var body: some View {
        GeometryReader { geo in
            let dim = min(geo.size.width, geo.size.height)
            let lw  = dim * 0.13
            // Inner diameter once the stroke has been subtracted on both
            // sides; the icon should sit comfortably inside this circle.
            let innerDiameter = dim - 2 * lw

            ZStack {
                Canvas { ctx, size in
                    let cx = size.width / 2
                    let cy = size.height / 2
                    let r  = min(size.width, size.height) / 2 - lw / 2

                    // Track — faint full circle
                    var track = Path()
                    track.addEllipse(in: CGRect(x: cx - r, y: cy - r,
                                                width: r * 2, height: r * 2))
                    ctx.stroke(track, with: .color(.primary.opacity(0.2)),
                               lineWidth: lw)

                    // Fill arc — clockwise from 12 o'clock
                    let p = min(max(progress, 0), 1)
                    if applicable && p > 0 {
                        var arc = Path()
                        arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                                   startAngle: .degrees(-90),
                                   endAngle:   .degrees(-90 + 360 * p),
                                   clockwise: false)
                        ctx.stroke(arc,
                                   with: .color(ConcentricCirclesView.anthropicOrange),
                                   style: StrokeStyle(lineWidth: lw, lineCap: .round))
                    }
                }

                if showsCentreIcon {
                    // Centred icon — sized to fill ~55 % of the inner
                    // diameter so it reads at minimal-slot sizes but
                    // doesn't crowd the ring at the larger expanded size.
                    Image(systemName: systemImage)
                        .font(.system(size: innerDiameter * 0.55, weight: .semibold))
                        .foregroundStyle(applicable ? .primary : .secondary)
                }
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Previews

#if DEBUG
private let previewState = ClaudeSessionAttributes.ContentState(
    sessionUtilization: 68,
    sonnetWeeklyUtilization: 33,
    allModelsWeeklyUtilization: 42,
    designWeeklyUtilization: 55,
    sonnetApplicable: true,
    designApplicable: true,
    sessionResetsAt: Date().addingTimeInterval(2.5 * 3600),
    sonnetWeeklyResetsAt: Date().addingTimeInterval(3 * 86400),
    allModelsWeeklyResetsAt: Date().addingTimeInterval(4 * 86400),
    designWeeklyResetsAt: Date().addingTimeInterval(2 * 86400)
)

private let nearLimitState = ClaudeSessionAttributes.ContentState(
    sessionUtilization: 93,
    sonnetWeeklyUtilization: 88,
    allModelsWeeklyUtilization: 91,
    designWeeklyUtilization: 78,
    sonnetApplicable: true,
    designApplicable: true,
    sessionResetsAt: Date().addingTimeInterval(0.4 * 3600),
    sonnetWeeklyResetsAt: Date().addingTimeInterval(1 * 86400),
    allModelsWeeklyResetsAt: Date().addingTimeInterval(1 * 86400),
    designWeeklyResetsAt: Date().addingTimeInterval(1 * 86400)
)

private let proState = ClaudeSessionAttributes.ContentState(
    sessionUtilization: 55,
    sonnetWeeklyUtilization: 0,
    allModelsWeeklyUtilization: 40,
    designWeeklyUtilization: 20,
    sonnetApplicable: false,
    designApplicable: true,
    sessionResetsAt: Date().addingTimeInterval(1.5 * 3600),
    sonnetWeeklyResetsAt: nil,
    allModelsWeeklyResetsAt: Date().addingTimeInterval(5 * 86400),
    designWeeklyResetsAt: Date().addingTimeInterval(3 * 86400)
)

#Preview("Lock Screen — normal", as: .content,
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    previewState
}

#Preview("Lock Screen — near limit", as: .content,
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    nearLimitState
}

#Preview("Lock Screen — Pro (no Sonnet)", as: .content,
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    proState
}

// Dynamic Island — three presentations.

#Preview("Dynamic Island — compact", as: .dynamicIsland(.compact),
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    previewState
    nearLimitState
}

#Preview("Dynamic Island — expanded", as: .dynamicIsland(.expanded),
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    previewState
    nearLimitState
    proState
}

#Preview("Dynamic Island — minimal", as: .dynamicIsland(.minimal),
         using: ClaudeSessionAttributes()) {
    UsageLiveActivity()
} contentStates: {
    previewState
}
#endif
