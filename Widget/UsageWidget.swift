import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let input: CircleRendererInput
    /// True when the iOS app has signalled a signed-out state. The widget
    /// renders a sign-in prompt instead of rings so the user isn't staring
    /// at stale percentages from the last fetch before sign-out.
    var needsLogin: Bool = false
    /// True for a future-dated entry that the system reaches only when it has
    /// stopped reloading the widget. The view swaps the rings for a
    /// tap-to-refresh prompt so the user knows the numbers are old and a tap
    /// (which opens the app) will refresh them. See `getTimeline`.
    var needsRefresh: Bool = false
}

struct UsageTimelineProvider: TimelineProvider {
    /// Tells the system to reload the widget at most this often. The
    /// system may defer past this, but won't reload sooner unless the
    /// app explicitly calls `WidgetCenter.shared.reloadAllTimelines()`.
    private static let reloadInterval: TimeInterval = 15 * 60

    /// How old the displayed data may get before the widget flips to the
    /// tap-to-refresh prompt. Set above `reloadInterval` so ordinary
    /// system throttling (a late reload or two) doesn't trip the prompt;
    /// it only fires once the widget has genuinely gone unrefreshed, which
    /// is the dormant-app case the user hits.
    private static let staleThreshold: TimeInterval = 45 * 60

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, input: CircleRendererInput(
            sessionProgress: 0.5, sonnetProgress: 0.3, allModelsProgress: 0.4
        ))
    }

    /// Snapshot is shown in the widget gallery / transitional states.
    /// Reading from cache here is fine. Gallery doesn't need live data.
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(entry(from: SharedDefaults.load()))
    }

    /// Timeline reload. The system calls this when it wants fresh
    /// content (every ~15 minutes by our policy, or sooner when the app
    /// triggers `WidgetCenter.shared.reloadAllTimelines()`).
    ///
    /// **The widget does its own fetch here** rather than relying purely
    /// on the cache. Without this, the only way the rings would ever
    /// move is if the iOS app or its background-refresh handler had run
    /// since the last reload, which doesn't happen often enough on
    /// real devices. The cached `SharedDefaults` value still acts as a
    /// fallback when the fetch fails (no network, auth error, etc.).
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let now = Date()
            let fetched = await UsageService.shared.fetchUsage()
            let usable: UsageData?

            if fetched.error == nil && !fetched.needsLogin {
                // Fresh data. Promote it into the shared cache so the
                // main app, watch, and Live Activity all see the same
                // payload the rings just rendered.
                SharedDefaults.save(fetched)
                usable = fetched
            } else {
                // Network/auth failure. Fall back to whatever the app
                // last cached so the rings don't go blank.
                usable = SharedDefaults.load()
            }

            // Signed out (or nothing cached yet): a single sign-in entry.
            guard let data = usable, !data.needsLogin else {
                let entry = UsageEntry(date: now, input: Self.zeroInput, needsLogin: true)
                completion(Timeline(entries: [entry],
                                    policy: .after(now.addingTimeInterval(Self.reloadInterval))))
                return
            }

            // Self-staling timeline. We can't force iOS to reload a dormant
            // widget, but we *can* hand it a future-dated entry that flips to
            // the refresh prompt on its own. While iOS keeps reloading us the
            // fresh "now" entry is always replaced before the stale one is
            // reached; once it stops, the widget shows the prompt at `staleAt`
            // with no code running. This is the widget analogue of the Live
            // Activity's background TTL.
            let staleAt = (data.lastRefreshed ?? now).addingTimeInterval(Self.staleThreshold)
            let input = circleInput(from: data)

            var entries: [UsageEntry] = [
                UsageEntry(date: now, input: input, needsRefresh: now >= staleAt)
            ]
            if staleAt > now {
                entries.append(UsageEntry(date: staleAt, input: input, needsRefresh: true))
            }

            // Nudge iOS to try a real refresh around the staleness boundary.
            let reloadAt = max(staleAt, now.addingTimeInterval(Self.reloadInterval))
            completion(Timeline(entries: entries, policy: .after(reloadAt)))
        }
    }

    private static let zeroInput = CircleRendererInput(
        sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0
    )

    private func entry(from data: UsageData?) -> UsageEntry {
        guard let data else {
            return UsageEntry(date: .now, input: CircleRendererInput(
                sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0
            ), needsLogin: true)
        }
        return UsageEntry(
            date: .now,
            input: circleInput(from: data),
            needsLogin: data.needsLogin
        )
    }
}

// MARK: - Home Screen Widget View (systemSmall)

struct UsageWidgetView: View {
    let entry: UsageEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular: accessoryCircularBody
        default:                 systemSmallBody
        }
    }

    // MARK: systemSmall - full-colour rings (unchanged behaviour)

    private var systemSmallBody: some View {
        Group {
            if entry.needsLogin {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Sign In")
                        .font(.caption.weight(.semibold))
                    Text("Open App")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else if entry.needsRefresh {
                refreshPromptBody
            } else {
                ConcentricCirclesView(input: entry.input)
            }
        }
    }

    // MARK: needsRefresh - tap-to-refresh prompt (data went stale)

    private var refreshPromptBody: some View {
        VStack(spacing: 8) {
            RefreshGlyph()
                .frame(width: 64, height: 64)
                .foregroundStyle(ConcentricCirclesView.anthropicOrange)
            Text("Tap to refresh")
                .font(.caption.weight(.semibold))
            Text("Open app for fresh usage")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: accessoryCircular - compact rings matching the macOS status bar

    private var accessoryCircularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.needsLogin {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .widgetAccentable()
            } else if entry.needsRefresh {
                RefreshGlyph()
                    .padding(6)
                    .widgetAccentable()
            } else {
                LockScreenRingsView(input: entry.input)
                    .padding(5)
            }
        }
    }

}

// MARK: - Refresh glyph

/// Composite "tap to refresh" glyph: a circular refresh arrow with a tap
/// gesture symbol nested at its centre. Shown when the widget's data has gone
/// stale because iOS stopped reloading it. Tapping anywhere on a widget opens
/// the app, which fetches fresh usage. Scales to its frame so it reads at both
/// the systemSmall and accessoryCircular sizes.
struct RefreshGlyph: View {
    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)
            ZStack {
                // Circular arrow: thin, frame-filling, and subdued so the
                // finger reads as the focal element. Opacity (rather than a
                // fixed colour) keeps it subdued on both the orange home-screen
                // tint and the lock screen's vibrancy.
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: d, weight: .light))
                    .opacity(0.45)
                // Finger seated in the clear opening below the arrowhead, and
                // nudged down-and-right so it sits in the opening without
                // overlapping the inward-jutting arrowhead.
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: d * 0.29, weight: .semibold))
                    .offset(x: d * 0.05, y: d * 0.19)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Lock Screen Rings View

/// Three concentric rings for the lock screen accessory circular widget.
/// Outer = session (5h), middle = Sonnet weekly, inner = all-models weekly.
///
/// Sizing rationale: the accessoryCircular canvas is ~44 pt. lw is set to
/// ≈10.7 % of the full canvas diameter so the outer ring fills the available
/// space while the inner edge of the inner ring stays at the same absolute
/// position as the previous design (inner edge ≈ 10.4 % of canvas from
/// centre). A gap of 35 % of lw keeps the rings visually separated.
/// At dim=44: outerR≈19.6, midR≈13.8, innerR≈8.0 pt; inner edge ≈4.3 pt.
///
/// Uses `Color.primary` throughout so the system applies vibrancy on the lock
/// screen, full colour on the Home Screen, and accent tinting in accented mode.
struct LockScreenRingsView: View {
    let input: CircleRendererInput

    var body: some View {
        Canvas { ctx, size in
            // Fill the full canvas. lw is tuned so the inner edge of the
            // inner ring lands at the same absolute position as before.
            let dim = min(size.width, size.height)
            let lw  = dim * 0.107
            let gap = lw  * 0.35
            let cx  = size.width  / 2
            let cy  = size.height / 2
            let rings: [(progress: Double, applicable: Bool)] = [
                (input.sessionProgress,   true),
                (input.sonnetProgress,    input.sonnetApplicable),
                (input.allModelsProgress, true),
            ]

            for (i, ring) in rings.enumerated() {
                let r = dim / 2 - lw / 2 - CGFloat(i) * (lw + gap)
                guard r > lw / 2 else { continue }

                // Track - faint full circle
                var track = Path()
                track.addEllipse(in: CGRect(x: cx - r, y: cy - r,
                                            width: r * 2, height: r * 2))
                ctx.stroke(track, with: .color(.primary.opacity(0.2)), lineWidth: lw)

                // Fill arc - clockwise from 12 o'clock
                let p = min(max(ring.progress, 0), 1)
                if p > 0 && ring.applicable {
                    var arc = Path()
                    arc.addArc(center: CGPoint(x: cx, y: cy), radius: r,
                               startAngle: .degrees(-90),
                               endAngle:   .degrees(-90 + 360 * p),
                               clockwise: false)
                    ctx.stroke(arc, with: .color(.primary),
                               style: StrokeStyle(lineWidth: lw, lineCap: .round))
                }
            }
        }
        .widgetAccentable()
    }
}

// MARK: - Widget declarations

struct UsageWidget: Widget {
    let kind = "com.ranveer.ClaudeYourRings.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vibe Your Rings")
        .description("See your Claude usage rings at a glance.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Previews

#if DEBUG
private let previewEntry = UsageEntry(date: .now, input: CircleRendererInput(
    sessionProgress: 0.69, sonnetProgress: 0.33, allModelsProgress: 0.42,
    sessionTimeProgress: 0.42, sonnetTimeProgress: 0.60, allModelsTimeProgress: 0.55,
    sonnetApplicable: true
))

private let nearLimitEntry = UsageEntry(date: .now, input: CircleRendererInput(
    sessionProgress: 0.95, sonnetProgress: 0.88, allModelsProgress: 0.92,
    sessionTimeProgress: 0.88, sonnetTimeProgress: 0.90, allModelsTimeProgress: 0.90,
    sonnetApplicable: true
))

private let proEntry = UsageEntry(date: .now, input: CircleRendererInput(
    sessionProgress: 0.55, sonnetProgress: 0, allModelsProgress: 0.40,
    sonnetApplicable: false
))

private let signedOutEntry = UsageEntry(date: .now,
    input: CircleRendererInput(sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0),
    needsLogin: true
)

private let needsRefreshEntry = UsageEntry(date: .now, input: CircleRendererInput(
    sessionProgress: 0.69, sonnetProgress: 0.33, allModelsProgress: 0.42
), needsRefresh: true)

// Home screen
#Preview("Home - normal", as: .systemSmall) {
    UsageWidget()
} timeline: { previewEntry; nearLimitEntry }

#Preview("Home - needs refresh", as: .systemSmall) {
    UsageWidget()
} timeline: { needsRefreshEntry }

#Preview("Lock - circular (needs refresh)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { needsRefreshEntry }

// Lock screen - circular
#Preview("Lock - circular (normal)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { previewEntry }

#Preview("Lock - circular (near limit)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { nearLimitEntry }

#Preview("Lock - circular (Pro, no Fable)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { proEntry }

#Preview("Lock - circular (signed out)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { signedOutEntry }
#endif
