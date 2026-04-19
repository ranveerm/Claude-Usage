import SwiftUI

@main
struct ClaudeUsageiOSApp: App {
    init() {
        // Activate WatchConnectivity session early so it's ready when data arrives
        _ = WatchSender.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
