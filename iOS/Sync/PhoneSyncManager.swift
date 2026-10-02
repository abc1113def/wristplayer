import Foundation
import Observation
import WatchConnectivity

/// Состояние песни относительно часов.
enum SongSyncStatus: Equatable {
    /// Не отмечена для часов.
    case off
    /// Уже на часах.
    case onWatch
    /// Ждёт отправки (часы недоступны, приложение на часах не установлено и т.п.).
    case waiting
    /// Перекодируется перед отправкой.
    case preparing
    /// Передаётся, 0…1.
    case transferring(Double)
    case failed(String)
}

/// Телефонная сторона синхронизации: держит часы в соответствии с отметками «на часах».
@Observable
final class PhoneSyncManager: NSObject, WCSessionDelegate {
    static let shared = PhoneSyncManager()

    private(set) var isSupported = WCSession.isSupported()
    private(set) var isActivated = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false

    /// Что лежит на часах по последнему отчёту часов.
    private(set) var watchSongIds: Set<String> = []
    private(set) var watchUsedBytes: Int64 = 0
    private(set) var watchFreeBytes: Int64?
    private(set) var lastInventoryDate: Date?

    /// Прогресс текущих передач: id → 0…1.
    private(set) var progress: [String: Double] = [:]
    private(set) var preparing: Set<String> = []
    private(set) var failures: [String: String] = [:]
    /// Передачи, завершённые успешно, но ещё не подтверждённые инвентарём часов.
    private(set) var delivered: [String: Date] = [:]

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var session: WCSession?
    @ObservationIgnored private var failureDates: [String: Date] = [:]
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private var retryWork: DispatchWorkItem?
    @ObservationIgnored private var lastManifest: ManifestMessage?
    @ObservationIgnored private let defaults = UserDefaults.standard

    private static let retryInterval: TimeInterval = 30
    /// Сколько места оставлять свободным на часах.
    private static let reserveBytes: Int64 = 100 * 1024 * 1024

    private enum DefaultsKey {
        static let manifestIds = "sync.manifestIds"
        static let manifestDate = "sync.manifestDate"
        static let delivered = "sync.delivered"
    }

    init(library: LibraryStore = .shared) {
        self.library = library
        super.init()
        if let ids = defaults.stringArray(forKey: DefaultsKey.manifestIds),
           let date = defaults.object(forKey: DefaultsKey.manifestDate) as? Date {
            lastManifest = ManifestMessage(ids: ids, date: date)
        }
        delivered = defaults.dictionary(forKey: DefaultsKey.delivered) as? [String: Date] ?? [:]
    }

    // MARK: - Публичный интерфейс

    func activate() {
        library.onChange = { [weak self] in self?.syncNow() }
        if DemoContent.isEnabled {
            applyDemoState()
            return
        }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        self.session = session
        session.activate()
    }

    func status(for song: Song) -> SongSyncStatus {
        guard song.onWatch else { return .off }
        if watchSongIds.contains(song.id) || delivered[song.id] != nil { return .onWatch }
        if preparing.contains(song.id) { return .preparing }
        if let value = progress[song.id] { return .transferring(value) }
        if let message = failures[song.id] { return .failed(message) }
        return .waiting
    }

    /// Сколько отмеченных песен уже на часах.
    var syncedCount: Int {
        library.songs.filter { $0.onWatch && (watchSongIds.contains($0.id) || delivered[$0.id] != nil) }.count
    }

    var desiredCount: Int { library.songs.filter(\.onWatch).count }

    /// Средний прогресс активных передач.
    var overallProgress: Double? {
        guard !progress.isEmpty else { return nil }
        return progress.values.reduce(0, +) / Double(progress.count)
    }

    /// Принудительная синхронизация (кнопка «Синхронизировать»): заново отправляет манифест и повторяет ошибки.
    func forceSync() {
        lastManifest = nil
        failures = [:]
        failureDates = [:]
        syncNow()
    }

    /// Приводит часы в соответствие с библиотекой. Вызывать на главном потоке.
    func syncNow() {
        guard let session, session.activationState == .activated else { return }
        refreshState(session)
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let desired = library.songs.filter(\.onWatch).map(\.id)
        let desiredSet = Set(desired)
        pushManifest(desired, session: session)

        var inFlight = Set<String>()
        var inFlightBytes: Int64 = 0
        for transfer in session.outstandingFileTransfers {
            guard let id = FileTransferMetadata.songId(in: transfer.file.metadata) else { continue }
            if desiredSet.contains(id) {
                inFlight.insert(id)
                inFlightBytes += library.song(id: id)?.meta.fileSize ?? 0
            } else {
                transfer.cancel()
                progress[id] = nil
            }
        }

        let now = Date()
        let onWatch = watchSongIds.union(delivered.keys)
        let candidates = SyncPlanner.songsToSend(desired: desired, onWatch: onWatch,
                                                 inFlight: inFlight.union(preparing))
        var budget = watchFreeBytes.map { $0 - Self.reserveBytes - inFlightBytes }
        for id in candidates {
            if let failedAt = failureDates[id], now.timeIntervalSince(failedAt) < Self.retryInterval { continue }
            guard let song = library.song(id: id) else { continue }
            if let remaining = budget {
                guard song.meta.fileSize <= remaining else {
                    markFailure(id, "Недостаточно места на часах")
                    continue
                }
                budget = remaining - song.meta.fileSize
            }
            send(song, via: session)
        }

        failures = failures.filter { desiredSet.contains($0.key) }
        preparing = preparing.intersection(desiredSet)
        updateProgress()
        scheduleRetryIfNeeded()
    }

    // MARK: - Отправка

    private func pushManifest(_ desired: [String], session: WCSession) {
        if let lastManifest, lastManifest.ids == desired { return }
        let message = ManifestMessage(ids: desired, date: Date())
        do {
            try session.updateApplicationContext(message.context)
            lastManifest = message
            defaults.set(message.ids, forKey: DefaultsKey.manifestIds)
            defaults.set(message.date, forKey: DefaultsKey.manifestDate)
        } catch {
            NSLog("WristPlayer: не удалось отправить манифест: \(error)")
        }
    }

    private func send(_ song: Song, via session: WCSession) {
        let source = library.fileURL(for: song)
        let artwork = library.artworkData(for: song.id)
        guard Transcoder.needsConversion(song.meta) else {
            startTransfer(of: source, meta: song.meta, artwork: artwork, session: session)
            return
        }
        // Перекодируем по одной песне за раз; остальные подхватятся следующим проходом.
        guard preparing.isEmpty else { return }
        preparing.insert(song.id)
        Task {
            do {
                let converted = try await Transcoder.convertToAAC(source: source, meta: song.meta)
                await MainActor.run {
                    self.preparing.remove(song.id)
                    if self.library.song(id: song.id)?.onWatch == true {
                        var meta = song.meta
                        meta.fileName = "\(meta.id).m4a"
                        let size = (try? FileManager.default.attributesOfItem(atPath: converted.path)[.size] as? NSNumber)?
                            .int64Value
                        meta.fileSize = size ?? meta.fileSize
                        self.startTransfer(of: converted, meta: meta, artwork: artwork, session: session)
                    }
                    self.syncNow()
                }
            } catch {
                await MainActor.run {
                    self.preparing.remove(song.id)
                    self.markFailure(song.id, "Не удалось перекодировать: \(error.localizedDescription)")
                    self.syncNow()
                }
            }
        }
    }

    private func startTransfer(of url: URL, meta: SongMeta, artwork: Data?, session: WCSession) {
        let metadata = FileTransferMetadata(song: meta, artwork: artwork, sentAt: Date())
        session.transferFile(url, metadata: metadata.dictionary)
        progress[meta.id] = 0
        failures[meta.id] = nil
        failureDates[meta.id] = nil
        startProgressTimer()
    }

    private func markFailure(_ id: String, _ message: String) {
        failures[id] = message
        failureDates[id] = Date()
        progress[id] = nil
    }

    private func scheduleRetryIfNeeded() {
        retryWork?.cancel()
        guard !failures.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in self?.syncNow() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retryInterval + 1, execute: work)
    }

    // MARK: - Прогресс

    private func startProgressTimer() {
        guard progressTimer == nil else { return }
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateProgress()
        }
    }

    private func updateProgress() {
        guard let session else { return }
        var current: [String: Double] = [:]
        for transfer in session.outstandingFileTransfers {
            guard let id = FileTransferMetadata.songId(in: transfer.file.metadata) else { continue }
            current[id] = transfer.isTransferring ? transfer.progress.fractionCompleted : 0
        }
        if current != progress { progress = current }
        if current.isEmpty {
            progressTimer?.invalidate()
            progressTimer = nil
        }
    }

    // MARK: - Состояние

    private func refreshState(_ session: WCSession) {
        isActivated = session.activationState == .activated
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    private func apply(_ inventory: InventoryMessage) {
        if let lastInventoryDate, inventory.date < lastInventoryDate { return }
        watchSongIds = Set(inventory.ids)
        watchUsedBytes = inventory.usedBytes
        watchFreeBytes = inventory.freeBytes
        lastInventoryDate = inventory.date
        let forget = SyncPlanner.deliveriesToForget(delivered: delivered, inventory: inventory)
        if !forget.isEmpty {
            for id in forget { delivered[id] = nil }
            defaults.set(delivered, forKey: DefaultsKey.delivered)
        }
    }

    // MARK: - WCSessionDelegate (вызывается на фоновой очереди)

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        let context = session.receivedApplicationContext
        DispatchQueue.main.async {
            self.refreshState(session)
            if let inventory = InventoryMessage(context: context) { self.apply(inventory) }
            // После запуска заново отправляем манифест: часы могли переустановить приложение.
            self.lastManifest = nil
            self.syncNow()
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Пользователь переключился на другие часы.
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            let wasInstalled = self.isWatchAppInstalled
            self.refreshState(session)
            if !wasInstalled && session.isWatchAppInstalled {
                self.lastManifest = nil
            }
            self.syncNow()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            if let inventory = InventoryMessage(context: applicationContext) {
                self.apply(inventory)
                self.syncNow()
            }
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let removed = userInfo[SyncKeys.removedOnWatch] as? [String] else { return }
        DispatchQueue.main.async {
            self.library.setOnWatch(false, ids: removed)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard let id = FileTransferMetadata.songId(in: fileTransfer.file.metadata) else { return }
        DispatchQueue.main.async {
            self.progress[id] = nil
            if let error {
                if self.library.song(id: id)?.onWatch == true {
                    self.markFailure(id, error.localizedDescription)
                }
            } else {
                self.delivered[id] = Date()
                self.defaults.set(self.delivered, forKey: DefaultsKey.delivered)
                Transcoder.removeCached(ids: [id])
            }
            self.syncNow()
        }
    }

    // MARK: - Демо

    private func applyDemoState() {
        let ids = library.songs.map(\.id)
        isActivated = true
        isPaired = true
        isWatchAppInstalled = true
        isReachable = true
        watchSongIds = Set(ids.prefix(3))
        watchUsedBytes = 38 * 1024 * 1024
        watchFreeBytes = 21 * 1024 * 1024 * 1024
        if ids.count > 4 { progress[ids[4]] = 0.42 }
        if ids.count > 6 { failures[ids[6]] = "Часы недоступны" }
    }
}
