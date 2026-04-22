import SwiftUI

/// AppKit ↔ SwiftUI bridge for opening the macOS `Settings` scene from
/// outside a SwiftUI view — e.g. the status-item right-click menu.
///
/// macOS 14 deprecated `NSApp.sendAction(#selector(showSettingsWindow:)...)`
/// ("Please use SettingsLink for opening the Settings scene.") in favour of
/// `@Environment(\.openSettings)` and `SettingsLink`. Both are SwiftUI-only
/// APIs with no AppKit equivalent, so to reach them from an `NSMenuItem`
/// action we capture the environment action from a live SwiftUI view and
/// park it in a singleton that AppKit can call synchronously.
///
/// Registration happens via `.captureSettingsOpener()` applied to a view
/// that's guaranteed to be alive at launch — the popover's root view, which
/// the app auto-shows in `applicationDidFinishLaunching`. After that first
/// on-appear, `SettingsCoordinator.shared.open()` is callable from anywhere
/// on the main actor.
@MainActor
final class SettingsCoordinator {
    static let shared = SettingsCoordinator()

    private var openAction: (() -> Void)?

    private init() {}

    func register(_ action: @escaping () -> Void) {
        openAction = action
    }

    /// No-op if the bridge hasn't been registered yet (e.g. called before
    /// any SwiftUI view has appeared). In practice the popover auto-opens
    /// at launch, so this is always populated by the time a user can
    /// right-click the status item.
    func open() {
        openAction?()
    }
}

extension View {
    /// Capture `@Environment(\.openSettings)` from this view's environment
    /// and register it with `SettingsCoordinator.shared`, letting AppKit
    /// code programmatically open the Settings scene.
    func captureSettingsOpener() -> some View {
        modifier(SettingsOpenerCapture())
    }
}

private struct SettingsOpenerCapture: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear {
            SettingsCoordinator.shared.register { openSettings() }
        }
    }
}
