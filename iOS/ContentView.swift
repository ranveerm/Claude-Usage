import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var usageData = UsageData()
    @State private var showLogin = false
    @State private var showSettings = false
    @State private var isLoading = false
    @State private var isRefreshing = false
    @State private var refreshTask: Task<Void, Never>?
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
                    if isRefreshing {
                        RefreshingView()
                            .padding(.top, 40)
                    } else if usageData.needsLogin || !isConfigured {
                        LoginPromptView(
                            onLogin: { showLogin = true },
                            onDemoMode: {
                                UsageService.shared.enterDemoMode()
                                Task { await fetchData() }
                            }
                        )
                            .padding(.top, 40)
                    } else if usageData.isNetworkError {
                        OfflineView(
                            onRetry: { Task { await fetchData() } },
                            onSignOut: { signOut() }
                        )
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
            .navigationTitle("Vibe Your Rings")
            // Use inline title to avoid a large-title layout-state bug that
            // left-clips the title after a fullScreenCover dismiss.
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Only show the sign-out menu when there's actually something
                // to sign out of. On the LoginPromptView screen the icon is
                // confusing — it looks like a sign-in affordance.
                if isSignedIn {
                    ToolbarItem(placement: .topBarTrailing) {
                        // "More actions" menu replaces the old person.circle
                        // (which read as a sign-in affordance). Settings and
                        // Sign Out live here together — Settings opens a
                        // sheet, Sign Out is destructive and uses the system
                        // confirmation style from the sheet's own binding.
                        Menu {
                            Button {
                                showSettings = true
                            } label: {
                                Label("Settings", systemImage: "gearshape")
                            }
                            Divider()
                            Button(role: .destructive) {
                                signOut()
                            } label: {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
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
        // Settings lives in a sheet rather than a push so it feels like a
        // modal side-trip; NavigationStack inside gives us the title bar +
        // Done button the user expects on iOS modals.
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
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
            // ConcentricCirclesView uses SwiftUI Shapes (Circle().trim), whose
            // animatableData SwiftUI interpolates natively. Wrapping the
            // `usageData` assignments below in `withAnimation` is what drives
            // the fill animation — no separate wrapper view is needed.
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
                             systemImage: "calendar",
                             isApplicable: usageData.sonnetWeeklyApplicable)
                Divider()
                UsageRowView(label: "All Models Weekly",
                             utilization: usageData.allModelsWeeklyUtilization,
                             resetsAt: usageData.allModelsWeeklyResetsAt,
                             systemImage: "shippingbox")
            }
            .padding(.horizontal)

            // Claude Design (Anthropic Labs) — separate weekly quota, no ring
            // mapping. Shown as a horizontal bar to set it apart visually
            // from the ring-backed rows above.
            UsageProgressBarView(label: "Claude Design",
                                 utilization: usageData.designWeeklyUtilization,
                                 resetsAt: usageData.designWeeklyResetsAt,
                                 systemImage: "paintbrush.pointed.fill",
                                 isApplicable: usageData.designWeeklyApplicable,
                                 timeProgress: timeElapsed(resetsAt: usageData.designWeeklyResetsAt,
                                                           period: 7 * 86400))
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
        // Wipe notification dedup state so a subsequent sign-in (possibly a
        // different account) doesn't inherit the previous user's "already
        // fired for this reset window" records.
        NotificationManager.shared.resetState()

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

        // Cancel any in-flight retry loop before starting fresh (e.g. user
        // pulls to refresh while a retry loop is running).
        refreshTask?.cancel()

        isLoading = true
        let data = await UsageService.shared.fetchUsage()
        isLoading = false

        // Happy path — accept immediately.
        if data.error == nil && !data.needsLogin {
            isRefreshing = false
            acceptData(data)
            return
        }

        // Confirmed auth failure with no prior successful session — surface
        // it directly; don't start a retry loop.
        if data.needsLogin && !UsageService.shared.lastKnownSignedIn {
            isRefreshing = false
            usageData = data
            publishSignedOutState()
            return
        }

        // If the user was last known to be signed in, enter the "Refreshing
        // Data" state and retry for up to 25 seconds before drawing any
        // conclusions. This covers iPhone/iPad screen-unlock and other brief
        // network-not-ready windows.
        guard UsageService.shared.lastKnownSignedIn else {
            isRefreshing = false
            usageData = data
            return
        }

        isRefreshing = true

        let innerTask = Task { @MainActor in
            var lastData = data
            for delay: Duration in [.seconds(2), .seconds(5), .seconds(10), .seconds(8)] {
                if Task.isCancelled { return }
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }

                let retryData = await UsageService.shared.fetchUsage()
                lastData = retryData

                if retryData.error == nil && !retryData.needsLogin {
                    isRefreshing = false
                    acceptData(retryData)
                    return
                }
            }

            // 25 seconds elapsed — draw a conclusion.
            isRefreshing = false
            if lastData.isNetworkError {
                // Network still down — show offline view, keep session intact.
                usageData = lastData
            } else if lastData.needsLogin {
                // Auth failure confirmed — clear credentials.
                usageData = lastData
                publishSignedOutState()
            } else {
                usageData = lastData
            }
        }
        refreshTask = innerTask
    }

    /// Applies a successful fetch: animates rings, updates downstream
    /// consumers (widget, watch), and fires notifications.
    private func acceptData(_ data: UsageData) {
        // Animate the ring fill: the `Circle().trim` inside
        // ConcentricCirclesView is Shape-animatable, so wrapping the state
        // change in `withAnimation` makes SwiftUI interpolate the trim
        // values over the duration — producing the "rings fill in from the
        // top" effect on cold boot as well as ease transitions on later refreshes.
        withAnimation(.easeInOut(duration: 0.6)) {
            usageData = data
        }
        SharedDefaults.save(data)
        WatchSender.shared.send(data)
        WidgetCenter.shared.reloadAllTimelines()
        Task {
            await NotificationManager.shared.evaluateAndPost(
                data: data,
                settings: NotificationSettings.shared
            )
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
        case .signedOut: .secondary
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
/// The two subscription tiers the preview can mock. Pro omits the
/// Sonnet-weekly metric; Max has all three.
private enum PreviewTier: String, CaseIterable, Identifiable {
    case max = "Max"
    case pro = "Pro"
    var id: String { rawValue }
}

private struct ContentViewPreview: View {
    @State private var sessionUsage: Double = 0.69
    @State private var sonnetUsage: Double = 0.33
    @State private var allModelsUsage: Double = 0.42
    @State private var designUsage: Double = 0.55
    @State private var sessionTime: Double = 0.42
    @State private var sonnetTime: Double = 0.60
    @State private var allModelsTime: Double = 0.55
    @State private var designTime: Double = 0.50
    @State private var tier: PreviewTier = .max
    /// Whether the API response includes the Anthropic Labs design block.
    /// Toggling exercises the greyed-out "N/A" rendering path.
    @State private var hasDesignAccess: Bool = true

    private func resetsAt(timeProgress: Double, period: TimeInterval) -> Date {
        Date().addingTimeInterval((1.0 - timeProgress) * period)
    }

    private var mockData: UsageData {
        UsageData(
            sessionUtilization:         sessionUsage   * 100,
            sessionResetsAt:            resetsAt(timeProgress: sessionTime,   period: 5 * 3600),
            sonnetWeeklyUtilization:    tier == .pro ? 0 : sonnetUsage * 100,
            sonnetWeeklyResetsAt:       tier == .pro ? nil
                                                     : resetsAt(timeProgress: sonnetTime, period: 7 * 86400),
            sonnetWeeklyApplicable:     tier == .max,
            allModelsWeeklyUtilization: allModelsUsage * 100,
            allModelsWeeklyResetsAt:    resetsAt(timeProgress: allModelsTime, period: 7 * 86400),
            designWeeklyUtilization:    hasDesignAccess ? designUsage * 100 : 0,
            designWeeklyResetsAt:       hasDesignAccess
                                        ? resetsAt(timeProgress: designTime, period: 7 * 86400)
                                        : nil,
            designWeeklyApplicable:     hasDesignAccess,
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
                                     systemImage: "calendar",
                                     isApplicable: mockData.sonnetWeeklyApplicable)
                        Divider()
                        UsageRowView(label: "All Models Weekly",
                                     utilization: mockData.allModelsWeeklyUtilization,
                                     resetsAt: mockData.allModelsWeeklyResetsAt,
                                     systemImage: "shippingbox")
                    }
                    .padding(.horizontal)

                    UsageProgressBarView(label: "Claude Design",
                                         utilization: mockData.designWeeklyUtilization,
                                         resetsAt: mockData.designWeeklyResetsAt,
                                         systemImage: "paintbrush.pointed.fill",
                                         isApplicable: mockData.designWeeklyApplicable,
                                         timeProgress: timeElapsed(resetsAt: mockData.designWeeklyResetsAt,
                                                                   period: 7 * 86400))
                        .padding(.horizontal)

                    Text("Updated just now")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Divider()

                    // Tier picker sits just above the sliders so it's the
                    // first thing you reach for when verifying the Pro-tier
                    // greyed-out rendering.
                    Picker("Account tier", selection: $tier) {
                        ForEach(PreviewTier.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    VStack(spacing: 10) {
                        sliderRow("Session Usage",    value: $sessionUsage)
                        sliderRow("Session Time",     value: $sessionTime)
                        Divider()
                        sliderRow("Sonnet Usage",     value: $sonnetUsage)
                            .disabled(tier == .pro)
                        sliderRow("Sonnet Time",      value: $sonnetTime)
                            .disabled(tier == .pro)
                        Divider()
                        sliderRow("All Models Usage", value: $allModelsUsage)
                        sliderRow("All Models Time",  value: $allModelsTime)
                        Divider()
                        Toggle("Has Design access", isOn: $hasDesignAccess)
                            .font(.caption)
                        sliderRow("Design Usage",     value: $designUsage)
                            .disabled(!hasDesignAccess)
                        sliderRow("Design Time",      value: $designTime)
                            .disabled(!hasDesignAccess)
                    }
                    .padding(.horizontal)
                }
                .padding()
            }
            .navigationTitle("Vibe Your Rings")
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
                LoginPromptView(onLogin: {}, onDemoMode: {})
                    .padding(.top, 40)
                    .padding()
            }
            .navigationTitle("Vibe Your Rings")
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

// MARK: - Ring animation preview
//
// Interactive preview: tap the button to animate the rings between a
// zero state and a populated state. Verifies the cold-boot fill animation
// visually without needing to launch the app and sign in.
//
// Lives in this iOS-target file (rather than Shared/ConcentricCirclesView.swift)
// so Xcode Previews resolves the translation unit unambiguously to the iOS
// app target — the shared file is compiled by every target, and the preview
// subsystem was picking the watchOS target and failing to build.
//
// The populated state deliberately uses the overshoot configuration
// (session usage 0.78 vs time 0.42) so the preview also exercises the
// semi-transparent-overlap-with-angular-gradient path.
private struct RingAnimationPreview: View {
    @State private var filled = false

    var body: some View {
        VStack(spacing: 28) {
            ConcentricCirclesView(input: filled ? populated : zeroInput)
                .frame(width: 240, height: 240)

            Button(filled ? "Reset" : "Fill rings") {
                withAnimation(.easeInOut(duration: 1.0)) {
                    filled.toggle()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var zeroInput: CircleRendererInput {
        CircleRendererInput(
            sessionProgress:   0,
            sonnetProgress:    0,
            allModelsProgress: 0
        )
    }

    private var populated: CircleRendererInput {
        // Mix of scenarios across the three rings so the preview exercises
        // both branches of the compositing logic:
        //   - Session:   heavy overshoot (0.82 usage vs 0.35 time)
        //   - Sonnet:    time ahead of usage (0.28 usage vs 0.65 time)
        //   - All Models: mild overshoot (0.45 usage vs 0.30 time)
        CircleRendererInput(
            sessionProgress:       0.82,
            sonnetProgress:        0.28,
            allModelsProgress:     0.45,
            sessionTimeProgress:   0.35,
            sonnetTimeProgress:    0.65,
            allModelsTimeProgress: 0.30
        )
    }
}

#Preview("Rings animation — tap to toggle") {
    RingAnimationPreview()
}
#endif
