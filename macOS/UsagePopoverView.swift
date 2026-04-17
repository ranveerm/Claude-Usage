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

    private var usageView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 20) {
                ConcentricCirclesView(input: circleInput(from: usageData))
                    .frame(width: 100, height: 100)
                    .padding(10)

                VStack(alignment: .leading, spacing: 8) {
                    UsageRowView(label: "Session (5h)",
                                 utilization: usageData.sessionUtilization,
                                 resetsAt: usageData.sessionResetsAt)
                    UsageRowView(label: "Sonnet Weekly",
                                 utilization: usageData.sonnetWeeklyUtilization,
                                 resetsAt: usageData.sonnetWeeklyResetsAt)
                    UsageRowView(label: "All Models Weekly",
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
                .help("Refresh")
                Button(action: {
                    UsageService.shared.clearCredentials()
                    onLogin()
                }) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Sign Out")
                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Quit")
                if let onDebugReset {
                    Button(action: onDebugReset) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset & Re-onboard (DEBUG)")
                }
            }
        }
    }
}
