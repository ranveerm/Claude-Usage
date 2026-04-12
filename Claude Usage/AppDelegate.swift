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

        refreshData()
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    @objc private func togglePopover() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            removeEventMonitor()
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        let pop = NSPopover()
        pop.contentSize = NSSize(width: 300, height: 380)
        pop.behavior = .transient
        pop.contentViewController = NSHostingController(
            rootView: UsagePopoverView(
                usageData: usageData,
                onRefresh: { [weak self] in self?.refreshData() }
            )
        )
        self.popover = pop

        if let button = statusItem.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        addEventMonitor()
        refreshData()
    }

    private func addEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.popover?.performClose(nil)
            self?.removeEventMonitor()
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func refreshData() {
        Task { @MainActor in
            let data = await UsageService.shared.fetchUsage()
            self.usageData = data
            self.statusItem.button?.image = self.renderIcon()

            if let popover = self.popover, popover.isShown {
                popover.contentViewController = NSHostingController(
                    rootView: UsagePopoverView(
                        usageData: data,
                        onRefresh: { [weak self] in self?.refreshData() }
                    )
                )
            }
        }
    }

    private func renderIcon() -> NSImage {
        let service = UsageService.shared
        let input = CircleRendererInput(
            sessionProgress: service.sessionLimit > 0 ? Double(usageData.sessionTokens) / Double(service.sessionLimit) : 0,
            sonnetProgress: service.sonnetWeeklyLimit > 0 ? Double(usageData.sonnetWeeklyTokens) / Double(service.sonnetWeeklyLimit) : 0,
            allModelsProgress: service.allModelsWeeklyLimit > 0 ? Double(usageData.allModelsWeeklyTokens) / Double(service.allModelsWeeklyLimit) : 0
        )
        return ConcentricCirclesRenderer.renderMenuBarIcon(input: input)
    }
}
