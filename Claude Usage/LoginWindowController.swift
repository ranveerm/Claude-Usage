import AppKit
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var onComplete: ((String, String) -> Void)?

    static func present(onComplete: @escaping (_ sessionKey: String, _ cfClearance: String) -> Void) {
        let controller = LoginWindowController()
        controller.onComplete = onComplete
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func loadWindow() {
        let config = WKWebViewConfiguration()
        // Use non-persistent data store so it starts clean but can acquire cf_clearance
        config.websiteDataStore = .default()

        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 960, height: 700), configuration: config)
        webView.navigationDelegate = self

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "Sign in to Claude"
        win.center()
        win.contentView = webView
        self.window = win

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    private func checkForSession() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let sessionKey = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })?.value
            let cfClearance = cookies.first(where: { $0.name == "cf_clearance" && $0.domain.contains("claude.ai") })?.value

            guard let sessionKey, !sessionKey.isEmpty else { return }

            DispatchQueue.main.async {
                self.onComplete?(sessionKey, cfClearance ?? "")
                self.close()
            }
        }
    }
}
