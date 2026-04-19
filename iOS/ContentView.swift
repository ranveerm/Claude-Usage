import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var usageData = UsageData()
    @State private var showLogin = false
    @State private var isLoading = false
    @Environment(\.scenePhase) private var scenePhase

    private var isConfigured: Bool { UsageService.shared.isConfigured }
    /// True when the app is in its main signed-in state (rings or error shown).
    /// Used to gate the navigation bar's sign-out toolbar item — we don't want
    /// to offer "sign out" on a screen that's already asking the user to sign in.
    private var isSignedIn: Bool { isConfigured && !usageData.needsLogin }

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
            // Use inline title to avoid a large-title layout-state bug that
            // left-clips the title after a fullScreenCover dismiss.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show the sign-out menu when there's actually something
                // to sign out of. On the LoginPromptView screen the icon is
                // confusing — it looks like a sign-in affordance.
                if isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button(role: .destructive) {
                                signOut()
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
        }
        .task {
            // Initial remote-sign-out check before the first fetch.
            if SignOutSignal.shouldSignOutFromRemoteSignal() {
                signOut()
                return
            }
            await fetchData()
        }
        // Re-fetch whenever the app returns to the foreground. Also
        // re-check the remote sign-out signal first.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if SignOutSignal.shouldSignOutFromRemoteSignal() {
                    signOut()
                } else {
                    Task { await fetchData() }
                }
            }
        }
        // React immediately when another device bumps the KVS signal.
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )) { _ in
            if SignOutSignal.shouldSignOutFromRemoteSignal() {
                signOut()
            }
        }
        // Periodic refresh every 5 minutes while the app is active
        .onReceive(refreshTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await fetchData() }
        }
        .fullScreenCover(isPresented: $showLogin) {
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

    private func signOut() {
        UsageService.shared.clearCredentials()
        // Push an empty payload so the watch clears its display too.
        WatchSender.shared.send(UsageData())
        usageData = UsageData()
        // Don't auto-open the login screen — let the user explicitly tap
        // "Sign In" in the LoginPromptView that now shows because
        // !isConfigured.
        showLogin = false
    }

    private func fetchData() async {
        guard isConfigured else { return }
        isLoading = true
        let data = await UsageService.shared.fetchUsage()
        isLoading = false

        // Auth failure: surface it so the body swaps in LoginPromptView,
        // but don't auto-present the WebView sheet — user should tap to
        // sign in explicitly.
        if data.needsLogin {
            usageData = data
            return
        }

        // Transient errors (e.g. network not yet re-established after screen unlock):
        // silently discard if we already have valid data on screen
        if data.error != nil, usageData.lastRefreshed != nil {
            return
        }

        usageData = data
        if data.error == nil {
            SharedDefaults.save(data)
            WatchSender.shared.send(data)
            WidgetCenter.shared.reloadAllTimelines()
        }
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

// MARK: - Login state preview
//
// Mirrors the signed-out screen exactly so we can eyeball the nav bar and
// title behaviour without needing to actually sign out at runtime. The key
// things this preview catches:
//   - `.inline` title mode prevents the large-title left-crop bug.
//   - The toolbar sign-out menu is absent (nothing to sign out of here).
private struct LoginStatePreview: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                LoginPromptView(onLogin: {})
                    .padding(.top, 40)
                    .padding()
            }
            .navigationTitle("Claude Your Rings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview("Login (Light)") {
    LoginStatePreview()
        .preferredColorScheme(.light)
}

#Preview("Login (Dark)") {
    LoginStatePreview()
        .preferredColorScheme(.dark)
}
#endif
