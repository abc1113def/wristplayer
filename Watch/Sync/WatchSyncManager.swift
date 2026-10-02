import Foundation
import Observation
import WatchConnectivity

/// Сторона часов: принимает песни и манифест, отчитывается телефону, что лежит на часах.
@Observable
final class WatchSyncManager: NSObject, WCSessionDelegate {
    static let shared = WatchSyncManager()

    private(set) var isActivated = false
    private(set) var isReachable = false
    private(set) var isCompanionAppInstalled = true
    /// Когда последний раз пришла песня.
    private(set) var lastReceivedAt: Date?

    @ObservationIgnored private let library: WatchLibrary
    @ObservationIgnored private var session: WCSession?

    init(library: WatchLibrary = .shared) {
        self.library = library
        super.init()
    }

    func activate() {
        guard session == nil, !DemoContent.isEnabled, WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        self.session = session
        session.activate()
    }

    /// Сообщает телефону, какие песни есть на часах.
    func sendInventory() {
        guard let session, session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(library.inventory().context)
        } catch {
            NSLog("WristPlayer: не удалось отправить инвентарь: \(error)")
        }
    }

    /// Пользователь удалил песни на часах — телефон снимет с них отметку «на часах».
    func reportRemovedOnWatch(_ ids: Set<String>) {
        guard let session, !ids.isEmpty else { return }
        session.transferUserInfo([SyncKeys.removedOnWatch: Array(ids)])
        sendInventory()
    }

    /// Для фоновой задачи `.watchConnectivity`: ждём, пока система доставит все данные.
    func waitUntilIdle() async {
        activate()
        let deadline = Date().addingTimeInterval(25)
        while Date() < deadline {
            if let session, session.activationState == .activated, !session.hasContentPending { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    // MARK: - WCSessionDelegate (фоновая очередь)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let manifest = ManifestMessage(context: session.receivedApplicationContext) {
            library.applyManifest(manifest)
        }
        sendInventory()
        let installed = session.isCompanionAppInstalled
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isActivated = activationState == .activated
            self.isCompanionAppInstalled = installed
            self.isReachable = reachable
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            self.isReachable = reachable
        }
    }

    func sessionCompanionAppInstalledDidChange(_ session: WCSession) {
        let installed = session.isCompanionAppInstalled
        DispatchQueue.main.async {
            self.isCompanionAppInstalled = installed
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let manifest = ManifestMessage(context: applicationContext) else { return }
        library.applyManifest(manifest)
        sendInventory()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // Файл нужно забрать синхронно, до выхода из метода.
        let saved = library.receive(fileAt: file.fileURL, metadata: file.metadata)
        sendInventory()
        if saved {
            DispatchQueue.main.async {
                self.lastReceivedAt = Date()
            }
        }
    }
}
