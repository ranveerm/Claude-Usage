import SwiftUI

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

    /// Convert a 0–1 time-elapsed fraction back to the Date when the period resets.
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

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            if usageData.needsLogin || !isConfigured {
                loginPromptView
            } else if let error = usageData.error {
                errorView(error)
            } else {
                usageView
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var loginPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Sign in to Claude")
                .font(.headline)
            Text("Opens a browser window to sign in.\nCloudflare clearance is handled automatically.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("Sign In") { onLogin() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 8)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.secondary)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Retry", action: onRefresh)
                Button("Sign In Again") {
                    UsageService.shared.clearCredentials()
                    onLogin()
                }
            }
        }
    }

    private var usageView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                circlesImage
                    .frame(width: 100, height: 100)
                    .padding(10)

                VStack(alignment: .leading, spacing: 8) {
                    usageRow(label: "Session (5h)",
                             utilization: usageData.sessionUtilization,
                             resetsAt: usageData.sessionResetsAt)
                    usageRow(label: "Sonnet Weekly",
                             utilization: usageData.sonnetWeeklyUtilization,
                             resetsAt: usageData.sonnetWeeklyResetsAt)
                    usageRow(label: "All Models Weekly",
                             utilization: usageData.allModelsWeeklyUtilization,
                             resetsAt: usageData.allModelsWeeklyResetsAt)
                }
            }

            Divider()

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
                    Image(systemName: "arrow.clockwise").font(.caption)
                }
                .buttonStyle(.borderless)
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear").font(.caption)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showSettings) { settingsView }
            }
        }
    }

    private var circlesImage: some View {
        let input = CircleRendererInput(
            sessionProgress: usageData.sessionUtilization / 100.0,
            sonnetProgress: usageData.sonnetWeeklyUtilization / 100.0,
            allModelsProgress: usageData.allModelsWeeklyUtilization / 100.0,
            sessionTimeProgress: Self.timeElapsed(resetsAt: usageData.sessionResetsAt, period: 5 * 3600),
            sonnetTimeProgress: Self.timeElapsed(resetsAt: usageData.sonnetWeeklyResetsAt, period: 7 * 86400),
            allModelsTimeProgress: Self.timeElapsed(resetsAt: usageData.allModelsWeeklyResetsAt, period: 7 * 86400)
        )
        return Image(nsImage: ConcentricCirclesRenderer.renderLargeView(input: input))
    }

    /// Fraction of the period that has elapsed (0.0–1.0).
    private static func timeElapsed(resetsAt: Date?, period: TimeInterval) -> Double {
        guard let resets = resetsAt, period > 0 else { return 0 }
        let remaining = resets.timeIntervalSinceNow
        return max(0, min(1, 1.0 - remaining / period))
    }

    private func usageRow(label: String, utilization: Double, resetsAt: Date?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text(String(format: "%.0f%%", utilization))
                    .font(.caption)
                    .monospacedDigit()
            }
            if let resets = resetsAt {
                Text("resets \(resets.formatted(.relative(presentation: .named)))")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button("Sign Out") {
                UsageService.shared.clearCredentials()
                showSettings = false
                onLogin()
            }
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 180)
    }
}
