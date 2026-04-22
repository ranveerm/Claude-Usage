import SwiftUI

@main
struct ClaudeUsageiOSApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Activate WatchConnectivity session early so it's ready when data arrives.
        _ = WatchSender.shared

        // Register the BGAppRefreshTask handler *before* the app finishes
        // launching. Submitting the first request is deferred until we hit
        // background (see `.onChange` below) so we don't queue up a slot
        // before the user has ever opened the app.
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            // iOS only runs BG tasks if the app has been backgrounded after
            // launch; request a slot each time the user sends us to the
            // background so we're always on the rotation.
            if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }
}
