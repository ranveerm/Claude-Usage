import AppKit
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate, NSWindowDelegate {
    private var webView: WKWebView!
    private var onComplete: ((String, String) -> Void)?
    private var pollTimer: Timer?
    private var isVerifying = false
    private static var current: LoginWindowController?

    /// Presents the login window. If one is already open, brings it to the
    /// front instead of stacking another on top (fixes the multi-window bug
    /// where the refresh timer would spawn new windows on every tick while
    /// the user was still signing in).
    static func present(onComplete: @escaping (_ sessionKey: String, _ cfClearance: String) -> Void) {
        if let existing = current {
            existing.onComplete = onComplete
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        // Keep the webview's surface area small to minimise chances of
        // triggering local-network / WebRTC permission prompts.
        config.allowsAirPlayForMediaPlayback = false
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.center()
        win.contentView = webView

        let controller = LoginWindowController(window: win)
        controller.webView = webView
        controller.onComplete = onComplete
        webView.navigationDelegate = controller
        win.delegate = controller

        current = controller
        controller.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        controller.startPolling()
    }

    // MARK: - Session detection

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForSession()
        }
    }

    /// Also triggered by the navigation delegate on each full-page load. The
    /// timer covers SPA/pushState routing that skips `didFinish`.
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    private func checkForSession() {
        guard !isVerifying else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let sessionKey = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })?.value ?? ""
            let cfClearance = cookies.first(where: { $0.name == "cf_clearance" && $0.domain.contains("claude.ai") })?.value ?? ""

            guard !sessionKey.isEmpty else { return }

            self.isVerifying = true
            Task { [sessionKey, cfClearance] in
                // Only close the window when the API actually accepts the
                // cookies — avoids false positives from partial login states.
                let ok = await UsageService.verifyCredentials(
                    sessionKey: sessionKey, cfClearance: cfClearance
                )
                await MainActor.run {
                    self.isVerifying = false
                    guard ok else { return }
                    self.onComplete?(sessionKey, cfClearance)
                    self.close()
                }
            }
        }
    }

    // MARK: - Cleanup

    func windowWillClose(_ notification: Notification) {
        pollTimer?.invalidate()
        pollTimer = nil
        Self.current = nil
    }
}
