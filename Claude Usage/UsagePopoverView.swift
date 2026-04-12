import SwiftUI

struct UsagePopoverView: View {
    let usageData: UsageData
    let onRefresh: () -> Void
    let onLogin: () -> Void

    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            if usageData.needsLogin || !UsageService.shared.isConfigured {
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
        VStack(spacing: 14) {
            circlesImage
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
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
            allModelsProgress: usageData.allModelsWeeklyUtilization / 100.0
        )
        return Image(nsImage: ConcentricCirclesRenderer.renderLargeView(input: input))
    }

    private func usageRow(label: String, utilization: Double, resetsAt: Date?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.0f%%", utilization))
                    .font(.caption)
                    .monospacedDigit()
                if let resets = resetsAt {
                    Text("resets \(resets.formatted(.relative(presentation: .named)))")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
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
