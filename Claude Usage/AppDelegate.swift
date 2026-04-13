import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var refreshTimer: Timer?
    private var usageData = UsageData()
    private var hostingController: NSHostingController<UsagePopoverView>!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = renderIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }

        hostingController = NSHostingController(rootView: makePopoverView())
        popover.contentViewController = hostingController
        popover.behavior = .transient

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
    }

    // MARK: - Popover

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            guard let button = statusItem.button else { return }
            updatePopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if UsageService.shared.isConfigured { refreshData() }
        }
    }

    // MARK: - Login

    func showLogin() {
        popover.performClose(nil)
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
            self.updatePopoverContent()

            if data.needsLogin { self.showLogin() }
        }
    }

    private func updatePopoverContent() {
        hostingController.rootView = makePopoverView()
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
