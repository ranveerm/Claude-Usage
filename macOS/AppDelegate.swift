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
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Claude Your Rings",
                     action: #selector(NSApplication.terminate(_:)),
                     keyEquivalent: "q")
        if let button = statusItem.button, let event = NSApp.currentEvent {
            NSMenu.popUpContextMenu(menu, with: event, for: button)
        }
    }

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
        // Clear WebKit cookies so the login window doesn't auto-dismiss
        // by finding the stale session cookie on its first navigation.
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) { }
        UsageService.shared.clearCredentials()
        // Reset displayed state immediately.
        usageData = UsageData()
        statusItem.button?.image = renderIcon()
        updatePopoverContent()
        showLogin()
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

            if data.needsLogin { self.showLogin() }
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
