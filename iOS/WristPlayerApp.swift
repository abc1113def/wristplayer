import SwiftUI

@main
struct WristPlayerApp: App {
    @State private var library = LibraryStore.shared
    @State private var sync = PhoneSyncManager.shared
    @State private var player = PhonePlayer.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        PhoneSyncManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environment(library)
                .environment(sync)
                .environment(player)
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                library.importFromDocumentsFolder()
                sync.syncNow()
            }
        }
    }
}
