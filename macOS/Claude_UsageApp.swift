import SwiftUI

@main
struct Claude_UsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // macOS `Settings` scene — opens as a standard preferences window
        // when triggered by the menu bar's Settings item, the ⌘, key, or
        // our programmatic `showSettingsWindow:` call from AppDelegate.
        Settings {
            SettingsView()
        }
    }
}
