import AppKit
import SwiftUI
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTimer: Timer?
    private var usageData = SharedDefaults.load() ?? UsageData()
    private var hostingController: NSHostingController<UsagePopoverView>!
    private var eventMonitor: Any?
    /// Non-nil while the app is in its 25-second retry window after a failed
    /// fetch — used to show `RefreshingView` and cancel any superseded retry.
    private var refreshTask: Task<Void, Never>?
    /// Mirrors the popover's `isRefreshing` state so `makePopoverView()` can
    /// pass it through without the Task capturing `self` in a cycle.
    private var isRefreshing = false

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

        // Observe cross-device session signal (arrives within seconds via
        // iCloud KVS when another device signs in or out).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteKVSChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: NSUbiquitousKeyValueStore.default
        )
        NSUbiquitousKeyValueStore.default.synchronize()

        // If another device signed us out while this app wasn't running,
        // pick that up immediately before doing anything else.
        observeSessionSignal()

        if UsageService.shared.isConfigured {
            refreshData()
        } else if WelcomeWindowController.hasCompleted {
            showLogin()
        } else {
            showWelcome()
        }

        // Auto-open the popover on every launch so the menu-bar icon's role
        // is self-evident: the user sees either the rings (signed in) or
        // the LoginPromptView (signed out) without having to discover and
        // click the icon. Dispatched one runloop turn later so the status
        // item button has a frame we can anchor to.
        DispatchQueue.main.async { [weak self] in
            self?.openPopover()
        }
    }

    @objc private func handleRemoteKVSChange() {
        // `didChangeExternallyNotification` is delivered on an arbitrary
        // thread. observeSessionSignal ends up touching `statusItem.button`
        // and NSHostingController state, both of which are main-thread only
        // (AppKit raises "NSStatusBarButton.setImage: must be used from main
        // thread only" otherwise). Hop to main before doing anything.
        DispatchQueue.main.async { [weak self] in
            self?.observeSessionSignal()
        }
    }

    /// Inspect the KVS session signal and apply whatever it tells us to do.
    /// Passive — never writes to KVS (only the explicit sign-in/out paths
    /// mutate it). Removing the `isConfigured` guard the previous version
    /// had is intentional: when keychain sync beats the KVS notification,
    /// `isConfigured` can already be false by the time we arrive here, and
    /// we still need to clear the menu bar icon and popover content.
    private func observeSessionSignal() {
        switch SignOutSignal.observe(isConfigured: UsageService.shared.isConfigured) {
        case .shouldSignOut:
            signOut(broadcast: false)
        case .adoptedRemote:
            // Another device's sign-in just landed in iCloud KVS.
            // iCloud Keychain often takes a second or two longer to deliver
            // the credentials, so refresh now and retry a couple of times.
            refreshAfterRemoteSignIn()
        case .inSync:
            // Race: iCloud Keychain may have synced a sign-out before this
            // KVS notification arrived — so observe() reports inSync (both
            // sides empty), but our in-memory `usageData` still holds the
            // last successful fetch. The popover view is driven off
            // `isConfigured` and will re-render correctly when opened, but
            // the menu-bar icon is set imperatively from `usageData` and
            // would otherwise keep showing stale rings. Reset and redraw.
            if !UsageService.shared.isConfigured, usageData.lastRefreshed != nil {
                usageData = UsageData()
                statusItem.button?.image = renderIcon()
                updatePopoverContent()
            }
        }
    }

    /// Retry schedule after picking up a remote sign-in: fire immediately,
    /// then again at +3s and +8s. Each attempt is a no-op if credentials
    /// haven't arrived yet. The first attempt that finds credentials kicks
    /// off refreshData and stops the loop.
    private func refreshAfterRemoteSignIn() {
        Task { @MainActor in
            for delay: Duration in [.zero, .seconds(3), .seconds(8)] {
                if delay > .zero { try? await Task.sleep(for: delay) }
                if UsageService.shared.isConfigured {
                    self.refreshData()
                    return
                }
            }
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

        // Settings opens the SwiftUI `Settings` scene. Visible in the
        // right-click menu so users can reach it even when signed out (the
        // main popover's gear icon only exists on the signed-in layout).
        let settingsItem = NSMenuItem(title: "Settings…",
                                      action: #selector(openSettingsFromMenu),
                                      keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())

        // Route through our own selector so macOS doesn't auto-attach an
        // SF Symbol next to the title (it decorates standard Apple actions
        // like NSApplication.terminate(_:)).
        let quitItem = NSMenuItem(title: "Quit \u{201C}Vibe Your Rings\u{201D}",
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

    /// Opens the SwiftUI `Settings` scene programmatically. Also used by
    /// the popover's gear button via `openSettings()`.
    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    /// Bring the Settings window to front.
    ///
    /// macOS 14 deprecated the `showSettingsWindow:` selector path and now
    /// prints "Please use SettingsLink for opening the Settings scene." and
    /// no-ops when sent from AppKit. The replacement (`openSettings`
    /// environment action) is SwiftUI-only, so we go via
    /// `SettingsCoordinator` — the popover's root view captures the action
    /// from its environment and parks it on the coordinator, letting us
    /// call it synchronously from here.
    func openSettings() {
        // Close the popover so the Settings window doesn't open underneath
        // it (and so the transient popover's own dismiss doesn't fire
        // while we're mid-activation).
        popover.performClose(nil)
        removeEventMonitor()

        NSApp.activate(ignoringOtherApps: true)
        SettingsCoordinator.shared.open()
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
            openPopover(fetchOnOpen: true)
        }
    }

    /// Show the popover anchored to the status item without requiring a
    /// user click. No-op if it's already visible. `fetchOnOpen` triggers a
    /// fresh fetch only when the caller expects interactive usage; the
    /// launch and post-login auto-open paths pass `false` because they
    /// have their own fetch scheduling.
    private func openPopover(fetchOnOpen: Bool = false) {
        guard !popover.isShown, let button = statusItem.button else { return }
        updatePopoverContent()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        addEventMonitor()
        if fetchOnOpen, UsageService.shared.isConfigured { refreshData() }
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

    /// Explicit user sign-out from the popover. Broadcasts via KVS so other
    /// devices pick it up within seconds.
    func signOut() { signOut(broadcast: true) }

    /// Shared sign-out cleanup. Pass `broadcast: false` when reacting to a
    /// remote sign-out signal; rebroadcasting from the reacting device
    /// would cascade across every other device.
    func signOut(broadcast: Bool) {
        if broadcast {
            // Revoke the session on Claude's server *before* we clear the
            // cookies locally. Fire-and-forget — we're signing out locally
            // regardless of whether the POST succeeds.
            let sk = UsageService.shared.sessionKey
            let cf = UsageService.shared.cfClearance
            if !sk.isEmpty {
                Task { await UsageService.revokeSession(sessionKey: sk, cfClearance: cf) }
            }
            SignOutSignal.markSignedOut()
        }
        UsageService.shared.clearCredentials()
        // Clear the per-(ring, kind) "already fired" records so a subsequent
        // sign-in doesn't inherit the previous user's state.
        NotificationManager.shared.resetState()

        // Stamp the cached payload as "signed out" so the watch and any
        // companion widgets switch to a sign-in prompt instead of rendering
        // stale rings.
        let signedOutPayload = UsageData(needsLogin: true)
        SharedDefaults.save(signedOutPayload)

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
                // Auto-open the popover now that the login window is
                // closing, so the user's first view of "success" is the
                // rings themselves — and discovers the menu-bar icon in
                // the process. Refresh is already in flight via
                // refreshData above, so pass fetchOnOpen: false.
                self?.openPopover()
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
        // Cancel any in-flight retry loop before starting a fresh one —
        // e.g. the 5-minute timer fires while a manual refresh is mid-retry.
        refreshTask?.cancel()

        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let data = await UsageService.shared.fetchUsage()

            // Happy path: valid data arrived immediately.
            if data.error == nil && !data.needsLogin {
                self.isRefreshing = false
                self.acceptData(data)
                return
            }

            // If this device was last known to be signed in, enter the
            // "Refreshing Data" spinner and retry for up to 25 seconds.
            // This covers wake-from-sleep races where the network or
            // Cloudflare CDN isn't ready yet — without this the popover
            // would flash to LoginPromptView unnecessarily.
            guard UsageService.shared.lastKnownSignedIn else {
                // Never been successfully signed in on this device — surface
                // the result directly (login screen or error).
                self.isRefreshing = false
                self.usageData = data
                self.statusItem.button?.image = self.renderIcon()
                self.updatePopoverContent()
                return
            }

            // Show spinner immediately.
            self.isRefreshing = true
            self.updatePopoverContent()

            // Retry schedule sums to ~25 seconds: 2 + 5 + 10 + 8 = 25 s.
            var lastData = data
            for delay: Duration in [.seconds(2), .seconds(5), .seconds(10), .seconds(8)] {
                if Task.isCancelled { return }
                try? await Task.sleep(for: delay)
                if Task.isCancelled { return }

                let retryData = await UsageService.shared.fetchUsage()
                lastData = retryData

                if retryData.error == nil && !retryData.needsLogin {
                    self.isRefreshing = false
                    self.acceptData(retryData)
                    return
                }
            }

            // 25 seconds elapsed — draw a conclusion.
            self.isRefreshing = false
            if lastData.isNetworkError {
                // Network is still down — show the offline view.
                self.usageData = lastData
            } else {
                // A prolonged Cloudflare challenge after wake-from-sleep is
                // indistinguishable from a genuine session expiry over a
                // 25-second window. Never auto-clear credentials — only the
                // user can sign out explicitly. Surface a plain error so the
                // user can Retry (recovers silently if session is still valid)
                // or Sign Out (their choice, not ours).
                self.usageData = UsageData(error: "Couldn't refresh data. Your session may have expired.")
            }
            self.statusItem.button?.image = self.renderIcon()
            self.updatePopoverContent()
        }
    }

    /// Accepts a successful fetch result: updates data, icon, and popover,
    /// then fires any qualifying notifications.
    private func acceptData(_ data: UsageData) {
        usageData = data
        statusItem.button?.image = renderIcon()
        updatePopoverContent()
        if data.error == nil && !data.needsLogin {
            Task {
                await NotificationManager.shared.evaluateAndPost(
                    data: data,
                    settings: NotificationSettings.shared
                )
            }
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
            onDemoMode: { [weak self] in
                UsageService.shared.enterDemoMode()
                self?.refreshData()
            },
            onDebugReset: debugReset,
            isRefreshing: isRefreshing
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
