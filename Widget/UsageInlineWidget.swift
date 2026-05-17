import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Inline metric selection

/// The metric the user pins to the inline lock-screen widget. Exposed
/// through `InlineMetricIntent` so iOS renders a Picker in the lock-screen
/// "Edit Widget" sheet with each case as a row.
///
/// Every variant uses the `timelapse` SF Symbol as its leading icon. This
/// symbol supports **variable values** (`Image(systemName:variableValue:)`)
/// — a value between 0 and 1 renders a proportional pie-slice fill,
/// giving us a real dynamic progress indicator inside the strict inline-
/// widget constraints (Label only allows a single SF Symbol).
///
/// `.allRings` reports the *maximum* of the three rings — the most useful
/// "watch this" signal: whichever ring is closest to its cap drives the
/// fill, so the user can spot pressure across any of them.
enum InlineMetric: String, AppEnum {
    case session, sonnetWeekly, allModelsWeekly, allRings, allRingsAndDesign

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Metric"

    static let caseDisplayRepresentations: [InlineMetric: DisplayRepresentation] = [
        .session:           "Session (5h)",
        .sonnetWeekly:      "Sonnet Weekly",
        .allModelsWeekly:   "All Models Weekly",
        .allRings:          "All Rings",
        .allRingsAndDesign: "All Rings + Design",
    ]

    /// Whether this case renders the multi-ring layout (`allRingsBody`).
    /// Single-metric cases use `singleMetricBody`.
    var isMultiRing: Bool {
        self == .allRings || self == .allRingsAndDesign
    }

    /// `timelapse` for every variant — clock-face symbol with a pie-slice
    /// fill driven by `variableValue` on the call site. The differentiator
    /// between metrics is which value drives the fill (see
    /// `UsageInlineView.progress`).
    var systemImage: String { "timelapse" }

    /// Metric-specific SF Symbol shown *between* `timelapse` and the
    /// label text in single-metric mode. Same symbols used elsewhere in
    /// the app so the imagery is consistent. `.allRings` has no single
    /// icon — it renders three pairs instead.
    var metricIcon: String {
        switch self {
        case .session:                          "calendar.day.timeline.left"
        case .sonnetWeekly:                     "calendar"
        case .allModelsWeekly:                  "shippingbox"
        case .allRings, .allRingsAndDesign:     ""
        }
    }

    /// Plain-text description shown after the icon. No percentage — the
    /// inline widget only describes the metric, not its current value.
    /// `.allRings` deliberately renders no text (the user's spec — the
    /// three icon pairs already convey the meaning).
    var displayLabel: String {
        switch self {
        case .session:                          "Session"
        case .sonnetWeekly:                     "Sonnet Weekly"
        case .allModelsWeekly:                  "All Models Weekly"
        case .allRings, .allRingsAndDesign:     ""
        }
    }
}

/// The intent that drives the inline widget's configuration UI. The single
/// `metric` parameter is enough — there's no other knob worth surfacing
/// since the inline slot can only render one line of text and one symbol.
struct InlineMetricIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Inline Widget"
    static let description = IntentDescription(
        "Choose which Claude usage metric to show above the lock-screen clock."
    )

    @Parameter(title: "Metric", default: .allModelsWeekly)
    var metric: InlineMetric
}

// MARK: - Timeline entry

struct InlineUsageEntry: TimelineEntry {
    let date: Date
    /// `nil` when no cached payload exists yet — the view treats that as
    /// "signed out" and renders the sign-in prompt.
    let usage: UsageData?
    let metric: InlineMetric

    var needsLogin: Bool { usage?.needsLogin ?? true }
}

// MARK: - Timeline provider

struct InlineTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> InlineUsageEntry {
        InlineUsageEntry(date: .now, usage: nil, metric: .allModelsWeekly)
    }

    func snapshot(
        for configuration: InlineMetricIntent,
        in context: Context
    ) async -> InlineUsageEntry {
        InlineUsageEntry(
            date: .now,
            usage: SharedDefaults.load(),
            metric: configuration.metric
        )
    }

    func timeline(
        for configuration: InlineMetricIntent,
        in context: Context
    ) async -> Timeline<InlineUsageEntry> {
        let entry = InlineUsageEntry(
            date: .now,
            usage: SharedDefaults.load(),
            metric: configuration.metric
        )
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }
}

// MARK: - View

struct UsageInlineView: View {
    let entry: InlineUsageEntry

    var body: some View {
        if entry.needsLogin || entry.usage == nil {
            Label("Sign in to Claude",
                  systemImage: "person.crop.circle.badge.questionmark")
        } else if entry.metric.isMultiRing {
            allRingsBody
        } else {
            singleMetricBody
        }
    }

    /// Single-metric layout: `[metric icon] [timelapse-with-fill] Label`
    /// The metric icon is the Label's leading symbol (identifies which
    /// ring); the timelapse-with-fill is interpolated into the title
    /// `Text` between the symbol and the descriptive name.
    private var singleMetricBody: some View {
        Label {
            Text("\(Image(systemName: entry.metric.systemImage, variableValue: singleProgress)) \(entry.metric.displayLabel)")
        } icon: {
            Image(systemName: entry.metric.metricIcon)
        }
    }

    /// All-rings layout: three or four `(metric icon, timelapse)` pairs
    /// with extra whitespace between pairs and no descriptive text. Each
    /// `timelapse` is fed the matching ring's progress so the indicators
    /// tick independently. `.allRings` shows the three chat rings only
    /// (Session, Sonnet Weekly, All Models Weekly); `.allRingsAndDesign`
    /// appends the Design pair as a fourth. Pro / no-Design accounts
    /// collapse the affected pairs to a 0-fill timelapse for layout
    /// stability.
    private var allRingsBody: some View {
        // Built with `Text + Text` concatenation rather than a single
        // interpolated string — easier to read, and `Text(" ")` lets us
        // tune inter-pair spacing without buried whitespace literals.
        let gap = Text("   ")   // three spaces; widens the gaps between
                                // adjacent pairs so the sets read as
                                // distinct groups in the inline slot.

        var result = pair(icon: InlineMetric.session.metricIcon,
                          progress: ringProgress(.session))
                   + gap
                   + pair(icon: InlineMetric.sonnetWeekly.metricIcon,
                          progress: ringProgress(.sonnetWeekly))
                   + gap
                   + pair(icon: InlineMetric.allModelsWeekly.metricIcon,
                          progress: ringProgress(.allModelsWeekly))

        if entry.metric == .allRingsAndDesign {
            result = result
                + gap
                + pair(icon: "paintbrush.pointed.fill",
                       progress: designProgress)
        }

        return result
    }

    /// One `(metric icon, timelapse-with-fill)` cluster as a `Text`,
    /// composable with `+` to build the all-rings row.
    private func pair(icon: String, progress: Double) -> Text {
        Text("\(Image(systemName: icon))\(Image(systemName: "timelapse", variableValue: progress))")
    }

    /// Design ring's fill value — separate from `ringProgress(_:)` because
    /// design isn't surfaced as a single-metric option in the picker.
    /// Returns 0 when the API didn't expose the design block for this tier.
    private var designProgress: Double {
        guard let usage = entry.usage,
              usage.designWeeklyApplicable else { return 0 }
        return min(max(usage.designWeeklyUtilization / 100, 0), 1)
    }

    // MARK: - Progress helpers

    /// 0–1 fill value for the single-metric variant.
    private var singleProgress: Double {
        ringProgress(entry.metric)
    }

    /// 0–1 fill value for the supplied metric, against the entry's
    /// usage payload. Pro tiers' Sonnet returns 0 (its `applicable` flag
    /// is false). `.allRings` is meaningless here — only the single-metric
    /// cases are addressed.
    private func ringProgress(_ metric: InlineMetric) -> Double {
        guard let usage = entry.usage else { return 0 }

        let clamp: (Double) -> Double = { min(max($0 / 100, 0), 1) }

        switch metric {
        case .session:
            return clamp(usage.sessionUtilization)
        case .sonnetWeekly:
            return usage.sonnetWeeklyApplicable
                ? clamp(usage.sonnetWeeklyUtilization)
                : 0
        case .allModelsWeekly:
            return clamp(usage.allModelsWeeklyUtilization)
        case .allRings, .allRingsAndDesign:
            return 0  // unused — multi-ring variants render pairs directly
        }
    }
}

// MARK: - Widget

struct UsageInlineWidget: Widget {
    let kind = "com.ranveer.ClaudeYourRings.widget.inline"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: InlineMetricIntent.self,
            provider: InlineTimelineProvider()
        ) { entry in
            UsageInlineView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Vibe Your Rings")
        .description("Show a Claude usage metric above the lock-screen clock.")
        .supportedFamilies([.accessoryInline])
    }
}

// MARK: - Previews

#if DEBUG
private let inlinePreviewUsage = UsageData(
    sessionUtilization: 68,
    sonnetWeeklyUtilization: 33,
    sonnetWeeklyApplicable: true,
    allModelsWeeklyUtilization: 42,
    designWeeklyUtilization: 55,
    designWeeklyApplicable: true
)

private let inlineNearLimitUsage = UsageData(
    sessionUtilization: 95,
    sonnetWeeklyUtilization: 88,
    sonnetWeeklyApplicable: true,
    allModelsWeeklyUtilization: 91,
    designWeeklyUtilization: 78,
    designWeeklyApplicable: true
)

#Preview("Inline — Session", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlinePreviewUsage, metric: .session)
}

#Preview("Inline — Sonnet Weekly", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlinePreviewUsage, metric: .sonnetWeekly)
}

#Preview("Inline — All Models Weekly", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlinePreviewUsage, metric: .allModelsWeekly)
}

#Preview("Inline — All Rings", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlinePreviewUsage, metric: .allRings)
}

#Preview("Inline — All Rings + Design", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlinePreviewUsage, metric: .allRingsAndDesign)
}

#Preview("Inline — Session (near limit)", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlineNearLimitUsage, metric: .session)
}

#Preview("Inline — All Rings (near limit)", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: inlineNearLimitUsage, metric: .allRings)
}

#Preview("Inline — Signed out", as: .accessoryInline) {
    UsageInlineWidget()
} timeline: {
    InlineUsageEntry(date: .now, usage: nil, metric: .session)
}
#endif
