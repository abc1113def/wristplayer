import SwiftUI

@main
struct WristPlayerWatchApp: App {
    @State private var library = WatchLibrary.shared
    @State private var player = AudioPlayer.shared
    @State private var sync = WatchSyncManager.shared

    init() {
        WatchSyncManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
                .environment(player)
                .environment(sync)
        }
        .backgroundTask(.watchConnectivity) {
            // Система разбудила приложение, чтобы доставить песни с телефона.
            await WatchSyncManager.shared.waitUntilIdle()
        }
    }
}
