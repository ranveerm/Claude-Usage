import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let input: CircleRendererInput
    /// True when the iOS app has signalled a signed-out state. The widget
    /// renders a sign-in prompt instead of rings so the user isn't staring
    /// at stale percentages from the last fetch before sign-out.
    var needsLogin: Bool = false
}

struct UsageTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, input: CircleRendererInput(
            sessionProgress: 0.5, sonnetProgress: 0.3, allModelsProgress: 0.4
        ))
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(entry(from: SharedDefaults.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let currentEntry = entry(from: SharedDefaults.load())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [currentEntry], policy: .after(nextUpdate)))
    }

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

    // MARK: systemSmall — full-colour rings (unchanged behaviour)

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
            } else {
                ConcentricCirclesView(input: entry.input)
            }
        }
    }

    // MARK: accessoryCircular — compact rings matching the macOS status bar

    private var accessoryCircularBody: some View {
        ZStack {
            AccessoryWidgetBackground()
            if entry.needsLogin {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .widgetAccentable()
            } else {
                LockScreenRingsView(input: entry.input)
                    .padding(5)
            }
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
            // Fill the full canvas — lw is tuned so the inner edge of the
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

                // Track — faint full circle
                var track = Path()
                track.addEllipse(in: CGRect(x: cx - r, y: cy - r,
                                            width: r * 2, height: r * 2))
                ctx.stroke(track, with: .color(.primary.opacity(0.2)), lineWidth: lw)

                // Fill arc — clockwise from 12 o'clock
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

// Home screen
#Preview("Home — normal", as: .systemSmall) {
    UsageWidget()
} timeline: { previewEntry; nearLimitEntry }

// Lock screen — circular
#Preview("Lock — circular (normal)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { previewEntry }

#Preview("Lock — circular (near limit)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { nearLimitEntry }

#Preview("Lock — circular (Pro, no Sonnet)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { proEntry }

#Preview("Lock — circular (signed out)", as: .accessoryCircular) {
    UsageWidget()
} timeline: { signedOutEntry }
#endif
