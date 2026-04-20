import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var usageData = UsageData()
    @State private var showLogin = false
    @State private var isLoading = false
    @State private var transition: SessionTransition?
    @State private var transitionDismissTask: Task<Void, Never>?
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
            observeSessionSignal()
            if isConfigured { await fetchData() }
        }
        // Re-fetch whenever the app returns to the foreground. Also
        // re-check the remote session signal first.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                observeSessionSignal()
                if isConfigured { Task { await fetchData() } }
            }
        }
        // React immediately when another device bumps the KVS signal.
        .onReceive(NotificationCenter.default.publisher(
            for: NSUbiquitousKeyValueStore.didChangeExternallyNotification
        )) { _ in
            observeSessionSignal()
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
                showTransition(.signedIn(remote: false))
                Task { await fetchData() }
            }
        }
        // Brief centred overlay that confirms a sign-in or sign-out, then
        // fades itself out. Non-interactive — just acknowledgement. See the
        // SessionTransition enum below for copy variants.
        .overlay(alignment: .center) {
            if let transition {
                TransitionOverlay(transition: transition)
                    .allowsHitTesting(false)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: transition)
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

    /// Explicit user sign-out. Broadcasts via KVS so other devices pick it
    /// up within seconds. Also clears the cached payload the widget and
    /// watch read from so they stop showing stale rings.
    private func signOut() { signOut(broadcast: true) }

    /// Shared sign-out cleanup. Pass `broadcast: false` when reacting to a
    /// remote sign-out signal — rebroadcasting from every reacting device
    /// would cascade sign-outs back to the originator.
    private func signOut(broadcast: Bool) {
        if broadcast {
            // Revoke the session on Claude's server *before* we clear the
            // cookies locally, so the POST can carry them. Fire-and-forget
            // so the UI stays responsive — the caller has committed to
            // signing out regardless of the server's response.
            let sk = UsageService.shared.sessionKey
            let cf = UsageService.shared.cfClearance
            if !sk.isEmpty {
                Task { await UsageService.revokeSession(sessionKey: sk, cfClearance: cf) }
            }
            SignOutSignal.markSignedOut()
        }
        UsageService.shared.clearCredentials()

        publishSignedOutState()

        usageData = UsageData()
        // Don't auto-open the login screen — let the user explicitly tap
        // "Sign In" in the LoginPromptView that now shows because
        // !isConfigured.
        showLogin = false
        showTransition(.signedOut(remote: !broadcast))
    }

    /// Display a transient sign-in / sign-out confirmation overlay. Cancels
    /// any in-flight dismiss from a previous transition so overlapping
    /// events don't clear the latest one early.
    private func showTransition(_ t: SessionTransition) {
        transitionDismissTask?.cancel()
        transition = t
        transitionDismissTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            await MainActor.run { transition = nil }
        }
    }

    /// Stamps the cached payload as "signed out" for every downstream
    /// consumer (widget, watch, complication). Idempotent — safe to call
    /// whenever we detect we aren't configured, so no consumer keeps
    /// rendering stale rings.
    private func publishSignedOutState() {
        let payload = UsageData(needsLogin: true)
        SharedDefaults.save(payload)
        WatchSender.shared.send(payload)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Read the KVS session signal and apply whatever it tells us to do.
    /// Never writes to KVS — only mutation happens in the explicit sign-in
    /// (`saveCredentials` → `markSignedIn`) and sign-out paths.
    private func observeSessionSignal() {
        switch SignOutSignal.observe(isConfigured: isConfigured) {
        case .shouldSignOut:
            signOut(broadcast: false)
        case .adoptedRemote:
            // Another device's sign-in just landed in iCloud KVS.
            // iCloud Keychain often takes a second or two longer to deliver
            // the credentials, so refresh now and retry a couple of times.
            refreshAfterRemoteSignIn()
        case .inSync:
            // If iCloud Keychain already synced a sign-out (so we're
            // !isConfigured) before the KVS notification arrived, we'd
            // otherwise miss the chance to tell the widget. Make sure its
            // cached payload reflects reality — idempotent, so cheap.
            if !isConfigured, SharedDefaults.load()?.needsLogin != true {
                publishSignedOutState()
            }
        }
    }

    /// Retry schedule after picking up a remote sign-in: fire immediately,
    /// then again at +3s and +8s. Each attempt is a no-op if credentials
    /// haven't arrived yet (fetchData's isConfigured guard). The first
    /// attempt that finds credentials runs the fetch and stops the loop.
    private func refreshAfterRemoteSignIn() {
        Task {
            for delay: Duration in [.zero, .seconds(3), .seconds(8)] {
                if delay > .zero { try? await Task.sleep(for: delay) }
                if isConfigured {
                    await fetchData()
                    showTransition(.signedIn(remote: true))
                    return
                }
            }
        }
    }

    private func fetchData() async {
        guard isConfigured else { return }
        isLoading = true
        let data = await UsageService.shared.fetchUsage()
        isLoading = false

        // Auth failure: surface it so the body swaps in LoginPromptView,
        // but don't auto-present the WebView sheet — user should tap to
        // sign in explicitly. Also propagate the signed-out state
        // downstream so the widget and watch don't keep rendering rings
        // from the last successful fetch.
        if data.needsLogin {
            usageData = data
            publishSignedOutState()
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

// MARK: - Session transition overlay

/// What to show when sign-in / sign-out state flips. We distinguish local
/// from remote so the overlay can annotate cross-device events.
enum SessionTransition: Equatable {
    case signedIn(remote: Bool)
    case signedOut(remote: Bool)

    var systemImage: String {
        switch self {
        case .signedIn:  "checkmark.circle.fill"
        case .signedOut: "rectangle.portrait.and.arrow.right"
        }
    }

    var title: String {
        switch self {
        case .signedIn:  "Signed In"
        case .signedOut: "Signed Out"
        }
    }

    var subtitle: String? {
        switch self {
        case .signedIn(let remote), .signedOut(let remote):
            remote ? "From another device" : nil
        }
    }

    var tint: Color {
        switch self {
        case .signedIn:  .green
        case .signedOut: .orange
        }
    }
}

struct TransitionOverlay: View {
    let transition: SessionTransition

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: transition.systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(transition.tint)
                .symbolEffect(.bounce, value: transition)
            Text(transition.title)
                .font(.title3.weight(.semibold))
            if let subtitle = transition.subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 18, y: 6)
        .padding(.horizontal, 40)
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
