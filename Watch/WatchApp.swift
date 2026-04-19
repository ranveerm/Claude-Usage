import SwiftUI

@main
struct ClaudeUsageWatchApp: App {
    @StateObject private var receiver = WatchReceiver()

    var body: some Scene {
        WindowGroup {
            WatchContentView()
                .environmentObject(receiver)
        }
    }
}
