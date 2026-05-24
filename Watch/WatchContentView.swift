import SwiftUI

struct WatchContentView: View {
    @EnvironmentObject private var receiver: WatchReceiver

    var body: some View {
        WatchBody(usageData: receiver.usageData, onRefresh: receiver.requestRefresh)
    }
}

// MARK: - Display view (data injected directly, no SharedDefaults dependency)

private struct WatchBody: View {
    let usageData: UsageData?
    var onRefresh: () async -> Void = {}

    var body: some View {
        // `needsLogin` means the iPhone explicitly broadcast a signed-out
        // state (via SharedDefaults / WatchConnectivity); `nil` means we
        // simply haven't received anything yet. Either way, point the user
        // back at the iPhone app rather than showing 0% rings.
        if let data = usageData, !data.needsLogin {
            TabView {
                CirclesPage(data: data, onRefresh: onRefresh)
                DetailPage(data: data)
            }
            .tabViewStyle(.verticalPage)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "circle.dashed")
                    .font(.title)
                    .foregroundColor(.secondary)
                Text("Open on iPhone")
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
    var onRefresh: () async -> Void = {}

    @State private var isRefreshing = false

    var body: some View {
        VStack(spacing: 15) {
            // Tap anywhere on the rings to ask the iPhone for fresh usage.
            // ZStack lets the spinner sit centred over the rings while
            // they're dimmed during the round-trip. `.contentShape` makes
            // the whole rectangle tappable, not just the stroke pixels of
            // the rings themselves.
            ZStack {
                ConcentricCirclesView(input: circleInput(from: data))
                    .padding(4)
                    .opacity(isRefreshing ? 0.35 : 1)

                if isRefreshing {
                    ProgressView()
                        .progressViewStyle(.circular)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isRefreshing else { return }
                Task {
                    isRefreshing = true
                    await onRefresh()
                    isRefreshing = false
                }
            }

            if let refreshed = data.lastRefreshed {
                Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                    .font(rowResetFont)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
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
                    systemImage: "calendar",
                    isApplicable: data.sonnetWeeklyApplicable
                )
                Divider()
                UsageRowView(
                    label: "All Models",
                    utilization: data.allModelsWeeklyUtilization,
                    resetsAt: data.allModelsWeeklyResetsAt,
                    systemImage: "shippingbox"
                )
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

private let mockWatchDataElevenMinAgo = UsageData(
    sessionUtilization: 69,
    sessionResetsAt: Date().addingTimeInterval(2.9 * 3600),
    sonnetWeeklyUtilization: 33,
    sonnetWeeklyResetsAt: Date().addingTimeInterval(2.8 * 86400),
    allModelsWeeklyUtilization: 42,
    allModelsWeeklyResetsAt: Date().addingTimeInterval(3.2 * 86400),
    lastRefreshed: Date().addingTimeInterval(-11 * 60)
)

private let mockWatchDataStale = UsageData(
    sessionUtilization: 22,
    sessionResetsAt: Date().addingTimeInterval(4.2 * 3600),
    sonnetWeeklyUtilization: 88,
    sonnetWeeklyResetsAt: Date().addingTimeInterval(1.1 * 86400),
    allModelsWeeklyUtilization: 71,
    allModelsWeeklyResetsAt: Date().addingTimeInterval(2.0 * 86400),
    lastRefreshed: Date().addingTimeInterval(-3 * 3600)
)

private let mockWatchDataNoTimestamp = UsageData(
    sessionUtilization: 45,
    sessionResetsAt: Date().addingTimeInterval(2.5 * 3600),
    sonnetWeeklyUtilization: 60,
    sonnetWeeklyResetsAt: Date().addingTimeInterval(3.0 * 86400),
    allModelsWeeklyUtilization: 55,
    allModelsWeeklyResetsAt: Date().addingTimeInterval(3.5 * 86400),
    lastRefreshed: nil
)

/// Interactive preview wrapper. Holds the displayed data in `@State` so
/// the tap-to-refresh gesture mutates `lastRefreshed` and the timestamp
/// re-renders. Simulates the WatchConnectivity round-trip with a short
/// sleep so the in-place spinner is visible for a moment before the new
/// data lands. Confirms the gesture is wired up end-to-end without
/// needing a paired phone.
private struct CirclesPagePreviewWrapper: View {
    @State private var data: UsageData

    init(initial: UsageData) {
        _data = State(initialValue: initial)
    }

    var body: some View {
        CirclesPage(data: data) {
            try? await Task.sleep(nanoseconds: 600_000_000)
            data.lastRefreshed = Date()
        }
    }
}

#Preview("With Data") {
    WatchBody(usageData: mockWatchData)
}

#Preview("No Data") {
    WatchBody(usageData: nil)
}

#Preview("Circles - tap to refresh (11m ago → now)") {
    CirclesPagePreviewWrapper(initial: mockWatchDataElevenMinAgo)
}

#Preview("Circles - 3h old") {
    CirclesPage(data: mockWatchDataStale)
}

#Preview("Circles - no timestamp") {
    CirclesPage(data: mockWatchDataNoTimestamp)
}

#Preview("Circles - large dynamic type") {
    CirclesPage(data: mockWatchData)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
