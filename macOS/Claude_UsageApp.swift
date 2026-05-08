import SwiftUI
import TipKit

@main
struct Claude_UsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // TipKit — surfaces the "Try Demo" affordance on the sign-in
        // screen (DemoModeTip). Using `.immediate` so the tip appears the
        // first time the popover opens on a freshly-installed app, which
        // matters most for App Store reviewers.
        if #available(macOS 14.0, *) {
            try? Tips.configure([.displayFrequency(.immediate),
                                 .datastoreLocation(.applicationDefault)])
        }
    }

    var body: some Scene {
        // macOS `Settings` scene — opens as a standard preferences window
        // when triggered by the menu bar's Settings item, the ⌘, key, or
        // our programmatic `showSettingsWindow:` call from AppDelegate.
        Settings {
            SettingsView()
        }
    }
}
