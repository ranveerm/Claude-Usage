import AppKit
import WebKit

final class LoginWindowController: NSWindowController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var onComplete: ((String, String) -> Void)?
    private static var current: LoginWindowController?

    static func present(onComplete: @escaping (_ sessionKey: String, _ cfClearance: String) -> Void) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

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

        current = controller
        controller.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        checkForSession()
    }

    private func checkForSession() {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let sessionKey = cookies.first(where: { $0.name == "sessionKey" && $0.domain.contains("claude.ai") })?.value
            let cfClearance = cookies.first(where: { $0.name == "cf_clearance" && $0.domain.contains("claude.ai") })?.value

            guard let sessionKey, !sessionKey.isEmpty else { return }

            DispatchQueue.main.async {
                self.onComplete?(sessionKey, cfClearance ?? "")
                self.close()
                Self.current = nil
            }
        }
    }
}
