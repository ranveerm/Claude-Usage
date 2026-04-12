import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var refreshTimer: Timer?
    private var usageData = UsageData()
    private var eventMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = renderIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refreshData()
        }

        if UsageService.shared.isConfigured {
            refreshData()
        } else {
            showLogin()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        removeEventMonitor()
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 300, height: 360)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(rootView: makePopoverView())
        self.popover = pop

        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        addEventMonitor()
        if UsageService.shared.isConfigured { refreshData() }
    }

    private func closePopover() {
        popover?.performClose(nil)
        removeEventMonitor()
    }

    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    // MARK: - Login

    func showLogin() {
        closePopover()
        LoginWindowController.present { [weak self] sessionKey, cfClearance in
            UsageService.shared.saveCredentials(sessionKey: sessionKey, cfClearance: cfClearance)
            self?.refreshData()
        }
    }

    // MARK: - Data

    private func refreshData() {
        Task { @MainActor in
            let data = await UsageService.shared.fetchUsage()
            self.usageData = data
            self.statusItem.button?.image = self.renderIcon()
            self.updatePopoverIfVisible()

            if data.needsLogin { self.showLogin() }
        }
    }

    private func updatePopoverIfVisible() {
        guard let popover, popover.isShown else { return }
        popover.contentViewController = NSHostingController(rootView: makePopoverView())
    }

    private func makePopoverView() -> UsagePopoverView {
        UsagePopoverView(
            usageData: usageData,
            onRefresh: { [weak self] in self?.refreshData() },
            onLogin: { [weak self] in self?.showLogin() }
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
