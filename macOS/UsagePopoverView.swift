import SwiftUI

// MARK: - Debug keychain inspector (DEBUG only)

#if DEBUG
/// Shows the live state of every keychain item and UserDefaults entry this app
/// owns, with values masked so they're recognisable but not fully exposed.
/// Includes the Reset & Re-onboard action so you can confirm state before and
/// after a reset in one place.
private struct KeychainDebugView: View {
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
private struct UsagePopoverPreview: View {
    @State private var sessionUsage: Double = 0.69
    @State private var sonnetUsage: Double = 0.33
    @State private var allModelsUsage: Double = 0.42
    @State private var sessionTime: Double = 0.42
    @State private var sonnetTime: Double = 0.60
    @State private var allModelsTime: Double = 0.55

    var body: some View {
        VStack(spacing: 16) {
            UsagePopoverView(
                usageData: mockData,
                isConfigured: true,
                onRefresh: {},
                onLogin: {}
            )

            Divider()

            VStack(spacing: 10) {
                sliderRow("Session Usage",     value: $sessionUsage)
                sliderRow("Session Time",      value: $sessionTime)
                Divider()
                sliderRow("Sonnet Usage",      value: $sonnetUsage)
                sliderRow("Sonnet Time",       value: $sonnetTime)
                Divider()
                sliderRow("All Models Usage",  value: $allModelsUsage)
                sliderRow("All Models Time",   value: $allModelsTime)
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
            sonnetWeeklyUtilization:  sonnetUsage     * 100,
            sonnetWeeklyResetsAt:     resetsAt(timeProgress: sonnetTime,     period: 7 * 86400),
            allModelsWeeklyUtilization: allModelsUsage * 100,
            allModelsWeeklyResetsAt:  resetsAt(timeProgress: allModelsTime,  period: 7 * 86400),
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

#Preview {
    UsagePopoverPreview()
}
#endif

// MARK: - View

struct UsagePopoverView: View {
    let usageData: UsageData
    let isConfigured: Bool
    let onRefresh: () -> Void
    let onLogin: () -> Void
    /// Debug-only reset handler. Only non-nil in DEBUG builds, via AppDelegate.
    let onDebugReset: (() -> Void)?

    @State private var showDebugInfo = false
    @State private var showSignOutConfirmation = false

    init(
        usageData: UsageData,
        isConfigured: Bool,
        onRefresh: @escaping () -> Void,
        onLogin: @escaping () -> Void,
        onDebugReset: (() -> Void)? = nil
    ) {
        self.usageData = usageData
        self.isConfigured = isConfigured
        self.onRefresh = onRefresh
        self.onLogin = onLogin
        self.onDebugReset = onDebugReset
    }

    var body: some View {
        VStack(spacing: 12) {
            if usageData.needsLogin || !isConfigured {
                LoginPromptView(onLogin: onLogin)
            } else if let error = usageData.error {
                ErrorDisplayView(error: error, onRetry: onRefresh, onReLogin: {
                    UsageService.shared.clearCredentials()
                    onLogin()
                })
            } else {
                usageView
            }
        }
        .padding(16)
        .frame(width: 300)
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
                                 systemImage: "calendar")
                    UsageRowView(label: "All Models Weekly",
                                 utilization: usageData.allModelsWeeklyUtilization,
                                 resetsAt: usageData.allModelsWeeklyResetsAt,
                                 systemImage: "shippingbox")
                }
            }

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
                        UsageService.shared.clearCredentials()
                        onLogin()
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
