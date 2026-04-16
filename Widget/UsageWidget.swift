import WidgetKit
import SwiftUI

struct UsageEntry: TimelineEntry {
    let date: Date
    let input: CircleRendererInput
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
            ))
        }
        return UsageEntry(date: .now, input: circleInput(from: data))
    }
}

struct UsageWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        ConcentricCirclesView(input: entry.input)
    }
}

// MARK: - Preview

#if DEBUG
private let previewEntry = UsageEntry(date: .now, input: CircleRendererInput(
    sessionProgress: 0.69, sonnetProgress: 0.33, allModelsProgress: 0.42,
    sessionTimeProgress: 0.42, sonnetTimeProgress: 0.60, allModelsTimeProgress: 0.55
))

#Preview("Widget", as: .systemSmall) {
    UsageWidget()
} timeline: {
    previewEntry
    UsageEntry(date: .now, input: CircleRendererInput(
        sessionProgress: 0.95, sonnetProgress: 0.80, allModelsProgress: 0.72,
        sessionTimeProgress: 0.88, sonnetTimeProgress: 0.90, allModelsTimeProgress: 0.90
    ))
}
#endif

struct UsageWidget: Widget {
    let kind = "com.ranveer.ClaudeYourRings.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageTimelineProvider()) { entry in
            UsageWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Claude Your Rings")
        .description("See your Claude usage rings at a glance.")
        .supportedFamilies([.systemSmall])
    }
}
