import SwiftUI

// MARK: - Debug keychain inspector (DEBUG only)

#if DEBUG
/// Shows the live state of every keychain item and UserDefaults entry this app
/// owns, with values masked so they're recognisable but not fully exposed.
/// Includes the Reset & Re-onboard action so you can confirm state before and
/// after a reset in one place.
///
/// Not `private` because AppDelegate presents it from the right-click context
/// menu (so the user can inspect state and reset even while signed out, when
/// the main popover's debug-info button wouldn't otherwise be reachable).
struct KeychainDebugView: View {
    let onReset: () -> Void

    // Read live on each render so the view always reflects current state.
    private var sessionKey:     String { KeychainHelper.load(key: "sessionKey")     ?? "" }
    private var cfClearance:    String { KeychainHelper.load(key: "cfClearance")    ?? "" }
    private var organizationId: String { KeychainHelper.load(key: "organizationId") ?? "" }

    private var hasCompletedWelcome: Bool {
        UserDefaults.standard.bool(forKey: "hasCompletedWelcome")
    }
    /// Cached usage payload written by UsageService after every successful
    /// fetch so the widget and watch can read it.
    private var cachedUsage: UsageData? { SharedDefaults.load() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Debug — App State")
                .font(.headline)
                .padding(.bottom, 10)

            // ── Keychain ──────────────────────────────────────────
            sectionHeader("Keychain  ·  service: com.ranveer.ClaudeYourRings")

            keychainRow("sessionKey",     value: sessionKey)
            keychainRow("cfClearance",    value: cfClearance)
            keychainRow("organizationId", value: organizationId)

            Divider().padding(.vertical, 8)

            // ── UserDefaults (standard suite) ─────────────────────
            sectionHeader("UserDefaults  ·  standard suite")

            flagRow("hasCompletedWelcome", value: hasCompletedWelcome)

            Divider().padding(.vertical, 8)

            // ── UserDefaults (App Group suite) ────────────────────
            sectionHeader("UserDefaults  ·  group.com.ranveer.ClaudeYourRings")

            if let usage = cachedUsage {
                let refreshed = usage.lastRefreshed.map {
                    $0.formatted(date: .omitted, time: .shortened)
                } ?? "–"
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green).font(.caption).frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("latestUsage").font(.caption.monospaced())
                        Text("last refreshed \(refreshed)")
                            .font(.caption2.monospaced()).foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary).font(.caption).frame(width: 14)
                    Text("latestUsage  (absent)")
                        .font(.caption.monospaced()).foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }

            Divider().padding(.vertical, 8)

            // ── Scope of reset ────────────────────────────────────
            Text("Scope of Reset & Re-onboard")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 3) {
                scopeRow("Keychain: deletes the 3 items above")
                scopeRow("UserDefaults (standard): removes hasCompletedWelcome")
                scopeRow("WebKit: clears cookies for this app's webview only")
                scopeRow("In-memory: resets UsageData to empty")
                scopeRow("Note: App Group cache (latestUsage) is NOT cleared")
            }

            Divider().padding(.vertical, 8)

            Button(role: .destructive) {
                onReset()
            } label: {
                Label("Reset & Re-onboard", systemImage: "arrow.counterclockwise.circle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
        }
        .padding()
        .frame(width: 320)
    }

    // MARK: Sub-views

    private func sectionHeader(_ label: String) -> some View {
        Text(label)
            .font(.caption2)
            .foregroundColor(.secondary)
            .padding(.bottom, 6)
    }

    private func keychainRow(_ label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: value.isEmpty ? "xmark.circle" : "checkmark.circle.fill")
                .foregroundColor(value.isEmpty ? .secondary : .green)
                .font(.caption)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption.monospaced())
                if !value.isEmpty {
                    Text(masked(value))
                        .font(.caption2.monospaced())
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func flagRow(_ label: String, value: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(value ? .green : .secondary)
                .font(.caption)
                .frame(width: 14)
            Text(label).font(.caption.monospaced())
            Spacer()
            Text(value ? "true" : "false")
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func scopeRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•").font(.caption2).foregroundColor(.secondary)
            Text(text).font(.caption2).foregroundColor(.secondary)
        }
    }

    /// Shows the first 4 and last 4 characters; replaces the middle with dots.
    /// A value shorter than 9 characters is fully masked.
    private func masked(_ s: String) -> String {
        guard s.count > 8 else { return String(repeating: "•", count: s.count) }
        return "\(s.prefix(4))\(String(repeating: "•", count: min(s.count - 8, 24)))\(s.suffix(4))"
    }
}
#endif

// MARK: - Preview

#if DEBUG
/// The two subscription tiers the preview can mock. Pro omits the
/// Sonnet-weekly metric; Max has all three.
private enum PreviewTier: String, CaseIterable, Identifiable {
    case max = "Max"
    case pro = "Pro"
    var id: String { rawValue }
}

private struct UsagePopoverPreview: View {
    @State private var sessionUsage: Double = 0.69
    @State private var sonnetUsage: Double = 0.33
    @State private var allModelsUsage: Double = 0.42
    @State private var designUsage: Double = 0.55
    @State private var sessionTime: Double = 0.42
    @State private var sonnetTime: Double = 0.60
    @State private var allModelsTime: Double = 0.55
    @State private var designTime: Double = 0.50
    @State private var tier: PreviewTier = .max
    /// Toggles the Anthropic Labs design block. When `false` the row should
    /// render greyed-out as N/A — same path Pro takes for the Sonnet row.
    @State private var hasDesignAccess: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            UsagePopoverView(
                usageData: mockData,
                isConfigured: true,
                onRefresh: {},
                onLogin: {}
            )

            Divider()

            // Tier picker sits above the sliders so it's the first thing
            // you reach for when debugging Pro-specific rendering. Sliders
            // for the Sonnet row are visually dimmed in Pro mode too,
            // mirroring how the production UI treats the row.
            Picker("Account tier", selection: $tier) {
                ForEach(PreviewTier.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            VStack(spacing: 10) {
                sliderRow("Session Usage",     value: $sessionUsage)
                sliderRow("Session Time",      value: $sessionTime)
                Divider()
                sliderRow("Sonnet Usage",      value: $sonnetUsage)
                    .disabled(tier == .pro)
                sliderRow("Sonnet Time",       value: $sonnetTime)
                    .disabled(tier == .pro)
                Divider()
                sliderRow("All Models Usage",  value: $allModelsUsage)
                sliderRow("All Models Time",   value: $allModelsTime)
                Divider()
                Toggle("Has Design access", isOn: $hasDesignAccess)
                    .font(.caption)
                sliderRow("Design Usage",      value: $designUsage)
                    .disabled(!hasDesignAccess)
                sliderRow("Design Time",       value: $designTime)
                    .disabled(!hasDesignAccess)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 340)
    }

    private var mockData: UsageData {
        UsageData(
            sessionUtilization:       sessionUsage    * 100,
            sessionResetsAt:          resetsAt(timeProgress: sessionTime,    period: 5 * 3600),
            sonnetWeeklyUtilization:  tier == .pro ? 0 : sonnetUsage * 100,
            sonnetWeeklyResetsAt:     tier == .pro ? nil
                                                   : resetsAt(timeProgress: sonnetTime, period: 7 * 86400),
            sonnetWeeklyApplicable:   tier == .max,
            allModelsWeeklyUtilization: allModelsUsage * 100,
            allModelsWeeklyResetsAt:  resetsAt(timeProgress: allModelsTime,  period: 7 * 86400),
            designWeeklyUtilization:  hasDesignAccess ? designUsage * 100 : 0,
            designWeeklyResetsAt:     hasDesignAccess
                                      ? resetsAt(timeProgress: designTime, period: 7 * 86400)
                                      : nil,
            designWeeklyApplicable:   hasDesignAccess,
            lastRefreshed:            Date()
        )
    }

    private func resetsAt(timeProgress: Double, period: TimeInterval) -> Date {
        Date().addingTimeInterval((1.0 - timeProgress) * period)
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

private struct PopoverOnBackground: View {
    let background: Color
    let label: String

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            UsagePopoverView(
                usageData: UsageData(
                    sessionUtilization: 69,
                    sessionResetsAt: Date().addingTimeInterval(0.31 * 5 * 3600),
                    sonnetWeeklyUtilization: 14,
                    sonnetWeeklyResetsAt: Date().addingTimeInterval(0.4 * 7 * 86400),
                    allModelsWeeklyUtilization: 25,
                    allModelsWeeklyResetsAt: Date().addingTimeInterval(0.45 * 7 * 86400),
                    designWeeklyUtilization: 38,
                    designWeeklyResetsAt: Date().addingTimeInterval(0.5 * 7 * 86400),
                    designWeeklyApplicable: true,
                    lastRefreshed: Date()
                ),
                isConfigured: true,
                onRefresh: {},
                onLogin: {}
            )
        }
        .frame(width: 380, height: 260)
    }
}

#Preview("Interactive") {
    UsagePopoverPreview()
}

#Preview("Dark desktop") {
    PopoverOnBackground(background: Color(white: 0.12), label: "Dark desktop")
}

#Preview("Light desktop") {
    PopoverOnBackground(background: Color(white: 0.85), label: "Light desktop")
}

#Preview("Yellow/vibrant") {
    PopoverOnBackground(background: Color(red: 0.95, green: 0.82, blue: 0.35), label: "Yellow/vibrant")
}

#Preview("Deep blue") {
    PopoverOnBackground(background: Color(red: 0.1, green: 0.2, blue: 0.5), label: "Deep blue")
}
#endif

// MARK: - View

struct UsagePopoverView: View {
    let usageData: UsageData
    let isConfigured: Bool
    let onRefresh: () -> Void
    let onLogin: () -> Void
    let onSignOut: () -> Void
    /// Demo-mode entry — flips `UsageService.isDemoMode` on and triggers
    /// a refresh so the rings populate from the fixture immediately.
    let onDemoMode: () -> Void
    /// Debug-only reset handler. Only non-nil in DEBUG builds, via AppDelegate.
    let onDebugReset: (() -> Void)?
    /// When `true` the popover is in a transient "checking" state — it has a
    /// previous successful session but the last fetch failed. Shows
    /// `RefreshingView` instead of `LoginPromptView` so the user can see that
    /// the app is actively retrying rather than thinking they've been signed out.
    let isRefreshing: Bool

    @State private var showDebugInfo = false
    @State private var showSignOutConfirmation = false
    /// Captured from the environment so the gear button can open the
    /// Settings scene directly — `SettingsLink`'s imperative counterpart.
    /// Same action is re-registered with `SettingsCoordinator` via
    /// `.captureSettingsOpener()` below so AppKit (the right-click menu)
    /// can invoke it too.
    @Environment(\.openSettings) private var openSettings

    init(
        usageData: UsageData,
        isConfigured: Bool,
        onRefresh: @escaping () -> Void,
        onLogin: @escaping () -> Void,
        onSignOut: @escaping () -> Void = {},
        onDemoMode: @escaping () -> Void = {},
        onDebugReset: (() -> Void)? = nil,
        isRefreshing: Bool = false
    ) {
        self.usageData = usageData
        self.isConfigured = isConfigured
        self.onRefresh = onRefresh
        self.onLogin = onLogin
        self.onSignOut = onSignOut
        self.onDemoMode = onDemoMode
        self.onDebugReset = onDebugReset
        self.isRefreshing = isRefreshing
    }

    var body: some View {
        VStack(spacing: 12) {
            if isRefreshing {
                RefreshingView()
            } else if usageData.needsLogin || !isConfigured {
                LoginPromptView(onLogin: onLogin, onDemoMode: onDemoMode)
            } else if usageData.isNetworkError {
                OfflineView(onRetry: onRefresh, onSignOut: onSignOut)
            } else if let error = usageData.error {
                ErrorDisplayView(error: error, onRetry: onRefresh, onReLogin: {
                    onSignOut()
                })
            } else {
                usageView
            }
        }
        .padding(10)
        .frame(width: 300)
        .background(.thickMaterial)
        // Park the SwiftUI `openSettings` action on the shared coordinator
        // so the AppKit right-click menu can reach it. Fires on every
        // on-appear of the popover; registration is idempotent.
        .captureSettingsOpener()
    }

    // MARK: - Usage content (shown when logged in and data is available)

    private var usageView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                ConcentricCirclesView(input: circleInput(from: usageData))
                    .frame(width: 100, height: 100)
                .padding(10)

                VStack(alignment: .leading, spacing: 8) {
                    UsageRowView(label: "Session (5h)",
                                 utilization: usageData.sessionUtilization,
                                 resetsAt: usageData.sessionResetsAt,
                                 systemImage: "calendar.day.timeline.left")
                    UsageRowView(label: "Sonnet Weekly",
                                 utilization: usageData.sonnetWeeklyUtilization,
                                 resetsAt: usageData.sonnetWeeklyResetsAt,
                                 systemImage: "calendar",
                                 isApplicable: usageData.sonnetWeeklyApplicable)
                    UsageRowView(label: "All Models Weekly",
                                 utilization: usageData.allModelsWeeklyUtilization,
                                 resetsAt: usageData.allModelsWeeklyResetsAt,
                                 systemImage: "shippingbox")
                }
            }

            // Claude Design (Anthropic Labs) — separate weekly quota that
            // doesn't fit the concentric-ring metaphor. Renders as a full-
            // width horizontal bar below the ring/row block so it's visually
            // distinct without competing for the same affordance.
            UsageProgressBarView(label: "Claude Design",
                                 utilization: usageData.designWeeklyUtilization,
                                 resetsAt: usageData.designWeeklyResetsAt,
                                 systemImage: "paintbrush.pointed.fill",
                                 isApplicable: usageData.designWeeklyApplicable,
                                 timeProgress: timeElapsed(resetsAt: usageData.designWeeklyResetsAt,
                                                           period: 7 * 86400))

            Divider()

            // Footer: timestamp on the left, action buttons on the right.
            // The debug info button sits in this same row so all controls
            // are grouped together and visible at the same level.
            HStack {
                if let refreshed = usageData.lastRefreshed {
                    Text("Updated \(refreshed.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Not yet refreshed")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()

                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderless)
                .help("Refresh")

                // Settings sits between Refresh and Sign Out — same visual
                // weight as the other footer icons, same help tooltip
                // convention. Opens the macOS SwiftUI Settings scene via
                // the `openSettings` environment action (the macOS 14+
                // replacement for `showSettingsWindow:`).
                Button { openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderless)
                .help("Settings")

                Button(action: { showSignOutConfirmation = true }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderless)
                .help("Sign Out")
                .confirmationDialog("Sign out of Claude?",
                                    isPresented: $showSignOutConfirmation,
                                    titleVisibility: .visible) {
                    Button("Sign Out", role: .destructive) {
                        onSignOut()
                    }
                    Button("Cancel", role: .cancel) { }
                } message: {
                    Text("You will need to sign in again to view your usage data.")
                }

                if let onDebugReset {
                    debugInfoButton(onDebugReset: onDebugReset)
                }
            }
        }
    }

    // MARK: - Debug info button

    /// Orange info button that opens the KeychainDebugView popover.
    /// Extracted so it can be reused in any footer row.
    @ViewBuilder
    private func debugInfoButton(onDebugReset: @escaping () -> Void) -> some View {
        Button(action: { showDebugInfo.toggle() }) {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .buttonStyle(.borderless)
        .help("Debug Info")
        #if DEBUG
        .popover(isPresented: $showDebugInfo) {
            KeychainDebugView(onReset: {
                showDebugInfo = false
                onDebugReset()
            })
        }
        #endif
    }
}
