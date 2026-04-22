import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct WatchUsageEntry: TimelineEntry {
    let date: Date
    let input: CircleRendererInput
    /// True when the paired iPhone has broadcast a signed-out state.
    /// The complication renders a small sign-in glyph rather than rings.
    var needsLogin: Bool = false
}

// MARK: - Timeline provider

struct WatchUsageProvider: TimelineProvider {
    private static let placeholderInput = CircleRendererInput(
        sessionProgress:       0.50,
        sonnetProgress:        0.30,
        allModelsProgress:     0.40,
        sessionTimeProgress:   0.35,
        sonnetTimeProgress:    0.25,
        allModelsTimeProgress: 0.30
    )

    func placeholder(in context: Context) -> WatchUsageEntry {
        WatchUsageEntry(date: .now, input: Self.placeholderInput)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchUsageEntry) -> Void) {
        completion(entry(from: SharedDefaults.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchUsageEntry>) -> Void) {
        let current = entry(from: SharedDefaults.load())
        // Watch complications should refresh roughly every 15 min; watchOS
        // may throttle further based on budget.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: .now) ?? .now
        completion(Timeline(entries: [current], policy: .after(next)))
    }

    private func entry(from data: UsageData?) -> WatchUsageEntry {
        guard let data else {
            return WatchUsageEntry(date: .now, input: CircleRendererInput(
                sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0
            ), needsLogin: true)
        }
        return WatchUsageEntry(
            date: .now,
            input: circleInput(from: data),
            needsLogin: data.needsLogin
        )
    }
}

// MARK: - Complication view

/// Circular complication that renders the three concentric usage rings,
/// modelled after the Fitness activity complication. Icons are hidden to
/// keep the tiny slot legible on the watch face.
struct WatchComplicationView: View {
    let entry: WatchUsageEntry

    var body: some View {
        Group {
            if entry.needsLogin {
                // Signed out — show a small sign-in glyph so the user isn't
                // staring at a stale snapshot of rings from before sign-out.
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                ConcentricCirclesView(
                    input: entry.input,
                    outerIcon: nil,
                    middleIcon: nil,
                    innerIcon: nil
                )
            }
        }
        // AccessoryWidgetBackground is the system-defined translucent
        // backdrop that matches how built-in complications look on
        // photo/colourful faces.
        .widgetAccentable()
    }
}

// MARK: - Widget definition

struct WatchComplication: Widget {
    let kind = "com.ranveer.ClaudeYourRings.watch.complication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchUsageProvider()) { entry in
            WatchComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Claude Rings")
        .description("Your Claude usage rings on the watch face.")
        .supportedFamilies([.accessoryCircular])
    }
}

// MARK: - Widget bundle

@main
struct WatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        WatchComplication()
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Circular · usage ahead", as: .accessoryCircular) {
    WatchComplication()
} timeline: {
    WatchUsageEntry(date: .now, input: CircleRendererInput(
        sessionProgress:       0.80,
        sonnetProgress:        0.65,
        allModelsProgress:     0.50,
        sessionTimeProgress:   0.30,
        sonnetTimeProgress:    0.20,
        allModelsTimeProgress: 0.15
    ))
}

#Preview("Circular · time ahead", as: .accessoryCircular) {
    WatchComplication()
} timeline: {
    WatchUsageEntry(date: .now, input: CircleRendererInput(
        sessionProgress:       0.30,
        sonnetProgress:        0.20,
        allModelsProgress:     0.15,
        sessionTimeProgress:   0.70,
        sonnetTimeProgress:    0.60,
        allModelsTimeProgress: 0.50
    ))
}

#Preview("Circular · empty", as: .accessoryCircular) {
    WatchComplication()
} timeline: {
    WatchUsageEntry(date: .now, input: CircleRendererInput(
        sessionProgress: 0, sonnetProgress: 0, allModelsProgress: 0
    ))
}
#endif
