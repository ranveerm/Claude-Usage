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
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onComplete: (_ sessionKey: String, _ cfClearance: String) -> Void
        private var completed = false

        init(onComplete: @escaping (_ sessionKey: String, _ cfClearance: String) -> Void) {
            self.onComplete = onComplete
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkForSession(webView: webView)
        }

        private func checkForSession(webView: WKWebView) {
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self, !self.completed else { return }
                let sessionKey = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })?.value
                let cfClearance = cookies.first(where: { $0.name == "cf_clearance" && $0.domain.contains("claude.ai") })?.value

                guard let sessionKey, !sessionKey.isEmpty else { return }

                DispatchQueue.main.async {
                    self.completed = true
                    self.onComplete(sessionKey, cfClearance ?? "")
                }
            }
        }
    }
}
