import SwiftUI

struct UsagePopoverView: View {
    let usageData: UsageData
    let onRefresh: () -> Void

    @State private var apiKey: String = UsageService.shared.apiKey
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 12) {
            if UsageService.shared.apiKey.isEmpty {
                apiKeyEntryView
            } else if let error = usageData.error {
                errorView(error)
            } else {
                usageView
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private var apiKeyEntryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("Enter Anthropic Admin API Key")
                .font(.headline)
            SecureField("sk-ant-admin-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveAPIKey() }
            Button("Save") { saveAPIKey() }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
        }
        .padding(.vertical, 8)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.yellow)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("Retry", action: onRefresh)
                Button("Change Key") {
                    UsageService.shared.apiKey = ""
                    apiKey = ""
                }
            }
        }
    }

    private var usageView: some View {
        VStack(spacing: 14) {
            circlesImage
                .frame(width: 120, height: 120)

            VStack(spacing: 8) {
                usageRow(
                    label: "Session",
                    tokens: usageData.sessionTokens,
                    limit: UsageService.shared.sessionLimit,
                    color: CircleColor.color(for: progress(usageData.sessionTokens, UsageService.shared.sessionLimit))
                )
                usageRow(
                    label: "Sonnet Weekly",
                    tokens: usageData.sonnetWeeklyTokens,
                    limit: UsageService.shared.sonnetWeeklyLimit,
                    color: CircleColor.color(for: progress(usageData.sonnetWeeklyTokens, UsageService.shared.sonnetWeeklyLimit))
                )
                usageRow(
                    label: "All Models Weekly",
                    tokens: usageData.allModelsWeeklyTokens,
                    limit: UsageService.shared.allModelsWeeklyLimit,
                    color: CircleColor.color(for: progress(usageData.allModelsWeeklyTokens, UsageService.shared.allModelsWeeklyLimit))
                )
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
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                Button(action: { showSettings.toggle() }) {
                    Image(systemName: "gear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showSettings) {
                    settingsView
                }
            }
        }
    }

    private var circlesImage: some View {
        let service = UsageService.shared
        let input = CircleRendererInput(
            sessionProgress: progress(usageData.sessionTokens, service.sessionLimit),
            sonnetProgress: progress(usageData.sonnetWeeklyTokens, service.sonnetWeeklyLimit),
            allModelsProgress: progress(usageData.allModelsWeeklyTokens, service.allModelsWeeklyLimit)
        )
        let nsImage = ConcentricCirclesRenderer.renderLargeView(input: input)
        return Image(nsImage: nsImage)
    }

    private func usageRow(label: String, tokens: Int, limit: Int, color: NSColor) -> some View {
        HStack {
            Circle()
                .fill(Color(nsColor: color))
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(Self.formatTokens(tokens)) / \(Self.formatTokens(limit))")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
        }
    }

    @State private var sessionLimitText = String(UsageService.shared.sessionLimit)
    @State private var sonnetLimitText = String(UsageService.shared.sonnetWeeklyLimit)
    @State private var allModelsLimitText = String(UsageService.shared.allModelsWeeklyLimit)

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Limits (tokens)")
                .font(.headline)
            LabeledContent("Session") {
                TextField("", text: $sessionLimitText)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Sonnet Weekly") {
                TextField("", text: $sonnetLimitText)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("All Models Weekly") {
                TextField("", text: $allModelsLimitText)
                    .frame(width: 100)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Button("Change API Key") {
                    UsageService.shared.apiKey = ""
                    apiKey = ""
                    showSettings = false
                }
                Spacer()
                Button("Save") {
                    if let v = Int(sessionLimitText) { UsageService.shared.sessionLimit = v }
                    if let v = Int(sonnetLimitText) { UsageService.shared.sonnetWeeklyLimit = v }
                    if let v = Int(allModelsLimitText) { UsageService.shared.allModelsWeeklyLimit = v }
                    showSettings = false
                    onRefresh()
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Quit App") {
                NSApplication.shared.terminate(nil)
            }
            .foregroundColor(.red)
        }
        .padding()
        .frame(width: 260)
    }

    private func saveAPIKey() {
        UsageService.shared.apiKey = apiKey
        onRefresh()
    }

    private func progress(_ tokens: Int, _ limit: Int) -> Double {
        guard limit > 0 else { return 0 }
        return Double(tokens) / Double(limit)
    }

    static func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.0fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}
