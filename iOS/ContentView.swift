import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var usageData = UsageData()
    @State private var showLogin = false
    @State private var isLoading = false
    @Environment(\.scenePhase) private var scenePhase

    private var isConfigured: Bool { UsageService.shared.isConfigured }

    private let refreshTimer = Timer.publish(every: 300, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if usageData.needsLogin || !isConfigured {
                        LoginPromptView(onLogin: { showLogin = true })
                            .padding(.top, 40)
                    } else if let error = usageData.error {
                        ErrorDisplayView(error: error, onRetry: { Task { await fetchData() } }, onReLogin: {
                            UsageService.shared.clearCredentials()
                            showLogin = true
                        })
                        .padding(.top, 40)
                    } else {
                        usageContent
                    }
                }
                .padding()
            }
            .refreshable { await fetchData() }
            .navigationTitle("Claude Your Rings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            UsageService.shared.clearCredentials()
                            usageData = UsageData()
                            showLogin = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.circle")
                            .imageScale(.large)
                    }
                }
            }
        }
        .task { await fetchData() }
        // Re-fetch whenever the app returns to the foreground
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await fetchData() } }
        }
        // Periodic refresh every 5 minutes while the app is active
        .onReceive(refreshTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await fetchData() }
        }
        .sheet(isPresented: $showLogin) {
            WebLoginView { sessionKey, cfClearance in
                UsageService.shared.saveCredentials(sessionKey: sessionKey, cfClearance: cfClearance)
                showLogin = false
                Task { await fetchData() }
            }
        }
    }

    private var usageContent: some View {
        VStack(spacing: 24) {
            ConcentricCirclesView(input: circleInput(from: usageData))
                .frame(width: 250, height: 250)
                .padding(.top, 8)

            VStack(spacing: 16) {
                UsageRowView(label: "Session (5h)",
                             utilization: usageData.sessionUtilization,
                             resetsAt: usageData.sessionResetsAt,
                             systemImage: "calendar.day.timeline.left")
                Divider()
                UsageRowView(label: "Sonnet Weekly",
                             utilization: usageData.sonnetWeeklyUtilization,
                             resetsAt: usageData.sonnetWeeklyResetsAt,
                             systemImage: "calendar")
                Divider()
                UsageRowView(label: "All Models Weekly",
                             utilization: usageData.allModelsWeeklyUtilization,
                             resetsAt: usageData.allModelsWeeklyResetsAt,
                             systemImage: "shippingbox")
            }
            .padding(.horizontal)

            if let refreshed = usageData.lastRefreshed {
                Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func fetchData() async {
        guard isConfigured else {
            showLogin = true
            return
        }
        isLoading = true
        let data = await UsageService.shared.fetchUsage()
        usageData = data
        isLoading = false
        if data.needsLogin { showLogin = true }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Preview

#if DEBUG
private struct ContentViewPreview: View {
    @State private var sessionUsage: Double = 0.69
    @State private var sonnetUsage: Double = 0.33
    @State private var allModelsUsage: Double = 0.42
    @State private var sessionTime: Double = 0.42
    @State private var sonnetTime: Double = 0.60
    @State private var allModelsTime: Double = 0.55

    private func resetsAt(timeProgress: Double, period: TimeInterval) -> Date {
        Date().addingTimeInterval((1.0 - timeProgress) * period)
    }

    private var mockData: UsageData {
        UsageData(
            sessionUtilization:         sessionUsage   * 100,
            sessionResetsAt:            resetsAt(timeProgress: sessionTime,   period: 5 * 3600),
            sonnetWeeklyUtilization:    sonnetUsage    * 100,
            sonnetWeeklyResetsAt:       resetsAt(timeProgress: sonnetTime,    period: 7 * 86400),
            allModelsWeeklyUtilization: allModelsUsage * 100,
            allModelsWeeklyResetsAt:    resetsAt(timeProgress: allModelsTime, period: 7 * 86400),
            lastRefreshed:              Date()
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    ConcentricCirclesView(input: circleInput(from: mockData))
                        .frame(width: 250, height: 250)
                        .padding(.top, 8)

                    VStack(spacing: 16) {
                        UsageRowView(label: "Session (5h)",
                                     utilization: mockData.sessionUtilization,
                                     resetsAt: mockData.sessionResetsAt,
                                     systemImage: "calendar.day.timeline.left")
                        Divider()
                        UsageRowView(label: "Sonnet Weekly",
                                     utilization: mockData.sonnetWeeklyUtilization,
                                     resetsAt: mockData.sonnetWeeklyResetsAt,
                                     systemImage: "calendar")
                        Divider()
                        UsageRowView(label: "All Models Weekly",
                                     utilization: mockData.allModelsWeeklyUtilization,
                                     resetsAt: mockData.allModelsWeeklyResetsAt,
                                     systemImage: "shippingbox")
                    }
                    .padding(.horizontal)

                    Text("Updated just now")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Divider()

                    VStack(spacing: 10) {
                        sliderRow("Session Usage",    value: $sessionUsage)
                        sliderRow("Session Time",     value: $sessionTime)
                        Divider()
                        sliderRow("Sonnet Usage",     value: $sonnetUsage)
                        sliderRow("Sonnet Time",      value: $sonnetTime)
                        Divider()
                        sliderRow("All Models Usage", value: $allModelsUsage)
                        sliderRow("All Models Time",  value: $allModelsTime)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Claude Your Rings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Image(systemName: "person.circle")
                        .imageScale(.large)
                }
            }
        }
    }

    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 130, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}

#Preview("Light") {
    ContentViewPreview()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentViewPreview()
        .preferredColorScheme(.dark)
}
#endif
