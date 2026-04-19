import AppKit
import SwiftUI
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTimer: Timer?
    private var usageData = UsageData()
    private var hostingController: NSHostingController<UsagePopoverView>!
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = renderIcon()
            button.action = #selector(handleStatusItemClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        hostingController = NSHostingController(rootView: makePopoverView())
        popover.contentViewController = hostingController
        popover.behavior = .transient

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshData()
        }

        // Observe cross-device sign-out signal (arrives within seconds via
        // iCloud KVS when another device signs out).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteKVSChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()

        // If another device signed us out while this app wasn't running,
        // pick that up immediately before doing anything else.
        if UsageService.shared.isConfigured, SignOutSignal.shouldSignOutFromRemoteSignal() {
            signOut()
            return
        }

        if UsageService.shared.isConfigured {
            refreshData()
        } else if WelcomeWindowController.hasCompleted {
            showLogin()
        } else {
            showWelcome()
        }
    }

    @objc private func handleRemoteKVSChange() {
        guard UsageService.shared.isConfigured else { return }
        if SignOutSignal.shouldSignOutFromRemoteSignal() {
            signOut()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        removeEventMonitor()
    }

    // MARK: - Popover

    @objc private func handleStatusItemClick() {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            showStatusMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusMenu() {
        // Close the main popover first — we're showing a right-click context
        // menu and don't want the popover floating alongside it.
        popover.performClose(nil)
        removeEventMonitor()

        let menu = NSMenu()

        #if DEBUG
        let debugItem = NSMenuItem(title: "Debug Info",
                                   action: #selector(showDebugInfoFromMenu),
                                   keyEquivalent: "")
        debugItem.target = self
        menu.addItem(debugItem)
        menu.addItem(NSMenuItem.separator())
        #endif

        // Route through our own selector so macOS doesn't auto-attach an
        // SF Symbol next to the title (it decorates standard Apple actions
        // like NSApplication.terminate(_:)).
        let quitItem = NSMenuItem(title: "Quit \u{201C}Claude Your Rings\u{201D}",
                                  action: #selector(handleQuit),
                                  keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        if let button = statusItem.button, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    #if DEBUG
    /// Stand-alone popover that hosts KeychainDebugView. Kept as a member so
    /// it isn't collected while showing.
    private var debugInfoPopover: NSPopover?

    @objc private func showDebugInfoFromMenu() {
        debugInfoPopover?.performClose(nil)

        let pop = NSPopover()
        pop.behavior = .transient
        let view = KeychainDebugView(onReset: { [weak self] in
            self?.debugInfoPopover?.performClose(nil)
            self?.resetAndReonboard()
        })
        pop.contentViewController = NSHostingController(rootView: view)

        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        debugInfoPopover = pop
    }
    #endif

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            removeEventMonitor()
        } else {
            guard let button = statusItem.button else { return }
            updatePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            addEventMonitor()
            if UsageService.shared.isConfigured { refreshData() }
        }
    }

    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.popover.isShown else { return }
            // Don't close if the click is on the status bar button (togglePopover handles that)
            if let button = self.statusItem.button,
               let buttonWindow = button.window,
               event.window == buttonWindow {
                return
            }
            self.popover.performClose(nil)
            self.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Onboarding / Login

    func showWelcome() {
        popover.performClose(nil)
        WelcomeWindowController.present { [weak self] in
            self?.showLogin()
        }
    }

    func signOut() {
        UsageService.shared.clearCredentials()
        // Reset displayed state immediately.
        usageData = UsageData()
        statusItem.button?.image = renderIcon()
        updatePopoverContent()
        // Don't auto-open the login window — the popover's LoginPromptView
        // (shown because !isConfigured) has a "Sign In" button that the
        // user can tap to explicitly open the login flow.
    }

    func showLogin() {
        popover.performClose(nil)
        removeEventMonitor()
        WelcomeWindowController.dismiss()
        // Defer to the next run loop turn so the popover finishes closing
        // before the login window is created and ordered front.
        DispatchQueue.main.async {
            LoginWindowController.present { [weak self] sessionKey, cfClearance in
                UsageService.shared.saveCredentials(sessionKey: sessionKey, cfClearance: cfClearance)
                self?.refreshData()
            }
        }
    }

    #if DEBUG
    /// Wipes credentials, welcome flag, and in-memory state so the next
    /// launch re-runs the full onboarding flow. Wired up to a debug-only
    /// button in the popover.
    func resetAndReonboard() {
        UsageService.shared.clearCredentials()
        WelcomeWindowController.resetForDebug()
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { }
        usageData = UsageData()
        statusItem.button?.image = renderIcon()
        popover.performClose(nil)
        removeEventMonitor()
        showWelcome()
    }
    #endif

    // MARK: - Data

    private func refreshData() {
        Task { @MainActor in
            let data = await UsageService.shared.fetchUsage()
            self.usageData = data
            self.statusItem.button?.image = self.renderIcon()
            self.updatePopoverContent()
            // Intentionally do NOT auto-call showLogin() here. If the user
            // has signed out (or their session expired) while the app is
            // running, updatePopoverContent() will swap in LoginPromptView
            // and the user can tap its "Sign In" button when ready. The
            // login window is only auto-opened on app launch from
            // applicationDidFinishLaunching.
        }
    }

    private func updatePopoverContent() {
        hostingController.rootView = makePopoverView()
    }

    private func makePopoverView() -> UsagePopoverView {
        #if DEBUG
        let debugReset: (() -> Void)? = { [weak self] in self?.resetAndReonboard() }
        #else
        let debugReset: (() -> Void)? = nil
        #endif

        return UsagePopoverView(
            usageData: usageData,
            isConfigured: UsageService.shared.isConfigured,
            onRefresh: { [weak self] in self?.refreshData() },
            onLogin: { [weak self] in self?.showLogin() },
            onSignOut: { [weak self] in self?.signOut() },
            onDebugReset: debugReset
        )
    }

    private func renderIcon() -> NSImage {
        let input = CircleRendererInput(
            sessionProgress: usageData.sessionUtilization / 100.0,
            sonnetProgress: usageData.sonnetWeeklyUtilization / 100.0,
            allModelsProgress: usageData.allModelsWeeklyUtilization / 100.0
        )
        return ConcentricCirclesRenderer.renderMenuBarIcon(input: input)
    }
}
