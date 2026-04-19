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
            TabView {
                CirclesPage(data: data)
                DetailPage(data: data)
            }
            .tabViewStyle(.verticalPage)
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

// MARK: - Page 1: Circles

private struct CirclesPage: View {
    let data: UsageData

    var body: some View {
        ConcentricCirclesView(input: circleInput(from: data))
            .padding(4)
    }
}

// MARK: - Page 2: Detail list

private struct DetailPage: View {
    let data: UsageData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                UsageRowView(
                    label: "Session (5h)",
                    utilization: data.sessionUtilization,
                    resetsAt: data.sessionResetsAt,
                    systemImage: "calendar.day.timeline.left"
                )
                Divider()
                UsageRowView(
                    label: "Sonnet Weekly",
                    utilization: data.sonnetWeeklyUtilization,
                    resetsAt: data.sonnetWeeklyResetsAt,
                    systemImage: "calendar"
                )
                Divider()
                UsageRowView(
                    label: "All Models",
                    utilization: data.allModelsWeeklyUtilization,
                    resetsAt: data.allModelsWeeklyResetsAt,
                    systemImage: "shippingbox"
                )

                if let refreshed = data.lastRefreshed {
                    Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
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
