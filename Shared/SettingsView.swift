import SwiftUI
import UserNotifications

/// Shared settings UI — presented as a sheet on iOS and hosted by the
/// SwiftUI `Settings` scene on macOS. The view is identical; platform
/// chrome (navigation bar, window sizing) is added by the container.
struct SettingsView: View {
    @ObservedObject private var settings = NotificationSettings.shared
    @State private var systemStatus: UNAuthorizationStatus = .notDetermined
    /// Controls the priming alert that appears the first time the user
    /// flips notifications on. Apple's HIG recommends warning the user
    /// before the OS-level prompt appears so they aren't caught off guard;
    /// it also lets us set expectations (what will we notify about?)
    /// which the system prompt itself can't.
    @State private var showPermissionPrimer = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            #if os(iOS)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
            .task { await refreshStatus() }
    }

    // MARK: - Body

    private var content: some View {
        Form {
            masterSection

            // Threshold + pace sections only make sense once the master
            // switch is on *and* the system has granted permission. Hiding
            // them rather than disabling keeps the initial state uncluttered.
            if settings.notificationsEnabled && systemStatus == .authorized {
                thresholdSection
                paceSection
            }
        }
        #if os(macOS)
        // macOS Settings scene doesn't provide a default size for Form-based
        // panes — without this the window opens ~100pt tall and immediately
        // feels broken.
        .frame(width: 440, height: 480)
        .formStyle(.grouped)
        #endif
        // Priming alert: shown once, before the system notification prompt.
        // Continue forwards to the OS prompt via `requestAuth()`; Not now
        // leaves the toggle in the off state the user started from.
        .alert("Enable notifications?", isPresented: $showPermissionPrimer) {
            Button("Not now", role: .cancel) { }
            Button("Continue") { requestAuth() }
        } message: {
            Text("The system will ask for permission to send you notifications. Vibe Your Rings uses this to post a banner when your Claude usage hits the thresholds you configure. You can change this later in System Settings.")
        }
    }

    // MARK: - Sections

    /// Master switch + system-status disclosure. The binding intercepts
    /// a turn-on to request authorisation before persisting; a turn-off
    /// just flips the stored bool.
    @ViewBuilder
    private var masterSection: some View {
        Section {
            Toggle("Enable notifications", isOn: Binding(
                get: { settings.notificationsEnabled },
                set: { newValue in
                    if newValue {
                        // First time: show the priming alert so the user
                        // isn't surprised by the OS prompt. If they've
                        // already been asked (authorized or denied), skip
                        // straight to the underlying action — requestAuth()
                        // is idempotent and the OS won't re-prompt after
                        // the first response anyway.
                        if systemStatus == .notDetermined {
                            showPermissionPrimer = true
                        } else {
                            requestAuth()
                        }
                    } else {
                        settings.notificationsEnabled = false
                    }
                }
            ))

            if settings.notificationsEnabled && systemStatus == .denied {
                // User turned us on but the OS-level permission is denied —
                // probably revoked in Settings after the first prompt. Tell
                // them where to fix it; we can't re-prompt from inside the
                // app once the user has actively denied.
                Label(
                    "Notifications are blocked in System Settings. Enable them there to start receiving alerts.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Banner alerts when your Claude usage hits the limits you set below. Notifications fire while the app can run, either in the foreground or during Background App Refresh (when enabled in iOS Settings).")
        }
    }

    /// Absolute-percentage rule. One slider, 50–95% in 5% steps.
    @ViewBuilder
    private var thresholdSection: some View {
        Section {
            Toggle("Alert at usage threshold", isOn: $settings.thresholdAlertsEnabled)
            if settings.thresholdAlertsEnabled {
                // Label ─ slider ─ value on one row. Fixed-width trailing
                // value column so the slider's right edge doesn't jump as
                // the percentage changes width ("55%" → "100%").
                HStack(spacing: 12) {
                    Text("Threshold")
                    Slider(value: $settings.thresholdPercent, in: 50...95, step: 5)
                    Text("\(Int(settings.thresholdPercent))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        } header: {
            Text("Usage threshold")
        } footer: {
            Text("Fires once per reset window when any ring's usage reaches this percentage.")
        }
    }

    /// Pace rule — per-ring toggles. Copy explains the "usage outpaces
    /// time elapsed" concept rather than leaving it implicit.
    @ViewBuilder
    private var paceSection: some View {
        Section {
            Toggle("Session (5h)",        isOn: $settings.paceAlertSession)
            // The Sonnet-weekly ring is Max-only; leave the toggle visible
            // on Pro accounts but it'll simply never fire (evaluator skips
            // rings where `sonnetWeeklyApplicable == false`).
            Toggle("Sonnet weekly",       isOn: $settings.paceAlertSonnet)
            Toggle("All models weekly",   isOn: $settings.paceAlertAllModels)
        } header: {
            Text("Pace alerts")
        } footer: {
            Text("Fires when a ring's usage outpaces the elapsed time in its reset window. For example, you're at 40% of your quota but only 20% of the window has passed. An early warning before you hit the absolute threshold.")
        }
    }

    // MARK: - Auth helpers

    private func requestAuth() {
        Task {
            let granted = await NotificationManager.shared.requestAuthorization()
            await MainActor.run {
                // Only flip the stored bool on success. If the user denies
                // the system prompt we leave the toggle off rather than
                // stranding them in a "enabled but nothing fires" state.
                settings.notificationsEnabled = granted
            }
            await refreshStatus()
        }
    }

    private func refreshStatus() async {
        let status = await NotificationManager.shared.currentAuthorizationStatus()
        await MainActor.run { systemStatus = status }
    }
}

#if DEBUG
// MARK: - Previews

/// Drives the previews through every meaningful state of the settings
/// screen. `NotificationSettings` is a singleton, so we mutate its
/// published values in `.task` rather than constructing an isolated
/// instance — the view reads the same shared source of truth that the
/// real app does, which keeps the preview faithful.
private struct SettingsPreviewHarness: View {
    /// Mirrors the real auth states the view branches on. `.authorized`
    /// reveals the threshold + pace sections; `.denied` surfaces the
    /// "blocked in System Settings" hint; `.notDetermined` shows only
    /// the master switch.
    enum Scenario: String, CaseIterable, Identifiable {
        case offUnprompted, authorizedAllOn, authorizedDefaults, denied
        var id: String { rawValue }
        var label: String {
            switch self {
            case .offUnprompted:      return "Off (not prompted)"
            case .authorizedAllOn:    return "Authorized, all on"
            case .authorizedDefaults: return "Authorized, defaults"
            case .denied:             return "Denied in system"
            }
        }
    }

    let scenario: Scenario

    var body: some View {
        SettingsView()
            .task { apply(scenario) }
    }

    private func apply(_ s: Scenario) {
        let settings = NotificationSettings.shared
        switch s {
        case .offUnprompted:
            settings.notificationsEnabled = false
        case .authorizedAllOn:
            settings.notificationsEnabled   = true
            settings.thresholdAlertsEnabled = true
            settings.thresholdPercent       = 75
            settings.paceAlertSession       = true
            settings.paceAlertSonnet        = true
            settings.paceAlertAllModels     = true
        case .authorizedDefaults:
            settings.notificationsEnabled   = true
            settings.thresholdAlertsEnabled = true
            settings.thresholdPercent       = 80
            settings.paceAlertSession       = false
            settings.paceAlertSonnet        = false
            settings.paceAlertAllModels     = false
        case .denied:
            // The view reads `systemStatus` from NotificationManager, which
            // we can't mock from a preview. This scenario still renders the
            // master-on layout; the "denied" hint only shows on a real
            // device where the system reports `.denied`.
            settings.notificationsEnabled = true
        }
    }
}

#if os(iOS)
#Preview("iOS sheet, authorized") {
    NavigationStack {
        SettingsPreviewHarness(scenario: .authorizedAllOn)
    }
}

#Preview("iOS sheet, off") {
    NavigationStack {
        SettingsPreviewHarness(scenario: .offUnprompted)
    }
}
#endif

#if os(macOS)
#Preview("macOS, authorized defaults") {
    SettingsPreviewHarness(scenario: .authorizedDefaults)
}

#Preview("macOS, all on") {
    SettingsPreviewHarness(scenario: .authorizedAllOn)
}

#Preview("macOS, off") {
    SettingsPreviewHarness(scenario: .offUnprompted)
}
#endif
#endif
