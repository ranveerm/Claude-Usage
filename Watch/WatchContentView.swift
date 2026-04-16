import SwiftUI

struct WatchContentView: View {
    @State private var usageData: UsageData?

    var body: some View {
        WatchBody(usageData: usageData)
            .onAppear { usageData = SharedDefaults.load() }
    }
}

// MARK: - Display view (data injected directly, no SharedDefaults dependency)

private struct WatchBody: View {
    let usageData: UsageData?

    var body: some View {
        if let data = usageData {
            ConcentricCirclesView(input: circleInput(from: data))
                .padding(4)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "circle.dashed")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Open Claude Your Rings\non iPhone")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
private let mockWatchData = UsageData(
    sessionUtilization: 69,
    sessionResetsAt: Date().addingTimeInterval(2.9 * 3600),
    sonnetWeeklyUtilization: 33,
    sonnetWeeklyResetsAt: Date().addingTimeInterval(2.8 * 86400),
    allModelsWeeklyUtilization: 42,
    allModelsWeeklyResetsAt: Date().addingTimeInterval(3.2 * 86400),
    lastRefreshed: Date()
)

#Preview("With Data") {
    WatchBody(usageData: mockWatchData)
}

#Preview("No Data") {
    WatchBody(usageData: nil)
}
#endif
