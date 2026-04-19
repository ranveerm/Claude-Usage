import SwiftUI
import WebKit

struct WebLoginView: View {
    let onComplete: (_ sessionKey: String, _ cfClearance: String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            WebViewRepresentable(onComplete: { sessionKey, cfClearance in
                onComplete(sessionKey, cfClearance)
                dismiss()
            })
            .navigationTitle("Sign in to Claude")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct WebViewRepresentable: UIViewRepresentable {
    let onComplete: (_ sessionKey: String, _ cfClearance: String) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Non-persistent store: the WebView starts with zero cookies every
        // time, so it can never auto-dismiss by finding a stale session.
        // Cookies captured during the sign-in flow are read via getAllCookies
        // and saved to the keychain before this WebView is torn down.
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.startPolling(webView: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onComplete: (_ sessionKey: String, _ cfClearance: String) -> Void
        private var completed = false
        private var isVerifying = false
        private var pollTimer: Timer?
        private weak var webView: WKWebView?

        init(onComplete: @escaping (_ sessionKey: String, _ cfClearance: String) -> Void) {
            self.onComplete = onComplete
        }

        deinit { pollTimer?.invalidate() }

        /// Claude.ai's final login redirect uses SPA pushState routing, which
        /// doesn't reliably fire `didFinish`. A cheap 2-second poll covers
        /// the gap — matches the macOS `LoginWindowController` implementation.
        func startPolling(webView: WKWebView) {
            self.webView = webView
            pollTimer?.invalidate()
            pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.checkForSession()
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForSession()
        }

        private func checkForSession() {
            guard !completed, !isVerifying, let webView else { return }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.completed, !self.isVerifying else { return }
                let sessionKey = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })?.value ?? ""
                let cfClearance = cookies.first(where: { $0.name == "cf_clearance" && $0.domain.contains("claude.ai") })?.value ?? ""

                guard !sessionKey.isEmpty else { return }

                // Only complete when the API actually accepts the cookies —
                // avoids false positives from a partially-authenticated
                // intermediate state.
                self.isVerifying = true
                Task { [sessionKey, cfClearance] in
                    let ok = await UsageService.verifyCredentials(
                        sessionKey: sessionKey, cfClearance: cfClearance
                    )
                    await MainActor.run {
                        self.isVerifying = false
                        guard ok else { return }
                        self.completed = true
                        self.pollTimer?.invalidate()
                        self.pollTimer = nil
                        self.onComplete(sessionKey, cfClearance)
                    }
                }
            }
        }
    }
}
