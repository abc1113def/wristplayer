import Foundation
import Observation
import UIKit

/// Песни, лежащие на часах.
///
/// Файловые операции могут выполняться на фоновой очереди WatchConnectivity, поэтому
/// источник истины (`index`) защищён блокировкой, а `songs` для интерфейса обновляется на главном потоке.
@Observable
final class WatchLibrary {
    static let shared = WatchLibrary()

    /// Песни для интерфейса (отсортированы по исполнителю и названию).
    private(set) var songs: [SongMeta] = []
    /// Песни из манифеста, которые ещё не пришли.
    private(set) var pendingCount = 0

    /// Вызывается (на главном потоке), когда песни удалены — плеер убирает их из очереди.
    @ObservationIgnored var onSongsRemoved: ((Set<String>) -> Void)?

    @ObservationIgnored let songsDirectory: URL
    @ObservationIgnored let artworkDirectory: URL
    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var index: [String: SongMeta] = [:]
    @ObservationIgnored private var manifestIds: Set<String>?
    @ObservationIgnored private var manifestDate: Date?
    @ObservationIgnored private let artworkCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let manifestIds = "library.manifestIds"
        static let manifestDate = "library.manifestDate"
    }

    init() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        songsDirectory = documents.appendingPathComponent("Songs", isDirectory: true)
        artworkDirectory = documents.appendingPathComponent("Artwork", isDirectory: true)
        indexURL = documents.appendingPathComponent("library.json")
        for dir in [songsDirectory, artworkDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if let ids = defaults.stringArray(forKey: DefaultsKey.manifestIds) {
            manifestIds = Set(ids)
        }
        manifestDate = defaults.object(forKey: DefaultsKey.manifestDate) as? Date
        if DemoContent.isEnabled {
            loadDemo()
        } else {
            load()
        }
    }

    // MARK: - Доступ

    func fileURL(for song: SongMeta) -> URL {
        songsDirectory.appendingPathComponent(song.fileName)
    }

    func song(id: String) -> SongMeta? {
        lock.withLock { index[id] }
    }

    func artwork(for id: String) -> UIImage? {
        if let cached = artworkCache.object(forKey: id as NSString) { return cached }
        let url = artworkDirectory.appendingPathComponent("\(id).jpg")
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        artworkCache.setObject(image, forKey: id as NSString)
        return image
    }

    func artworkData(for id: String) -> Data? {
        try? Data(contentsOf: artworkDirectory.appendingPathComponent("\(id).jpg"))
    }

    var usedBytes: Int64 {
        lock.withLock { index.values.reduce(0) { $0 + $1.fileSize } }
    }

    var freeBytes: Int64? {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: songsDirectory.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }

    /// Отчёт для телефона: что лежит на часах.
    func inventory() -> InventoryMessage {
        let ids = lock.withLock { Array(index.keys) }
        return InventoryMessage(ids: ids.sorted(), usedBytes: usedBytes, freeBytes: freeBytes, date: Date())
    }

    // MARK: - Приём с телефона (фоновая очередь)

    /// Сохраняет пришедший файл. Должен выполниться синхронно: после возврата из делегата
    /// WatchConnectivity удаляет временный файл.
    @discardableResult
    func receive(fileAt url: URL, metadata: [String: Any]?) -> Bool {
        guard let info = FileTransferMetadata(dictionary: metadata) else {
            NSLog("WristPlayer: файл без метаданных, пропускаю")
            return false
        }
        let keep = lock.withLock {
            SyncPlanner.shouldKeepIncoming(id: info.song.id, sentAt: info.sentAt,
                                           manifest: manifestIds, manifestDate: manifestDate)
        }
        guard keep else { return false }

        let fm = FileManager.default
        var meta = info.song
        let ext = meta.fileExtension.isEmpty ? url.pathExtension.lowercased() : meta.fileExtension
        meta.fileName = "\(meta.id).\(ext.isEmpty ? "m4a" : ext)"
        let destination = songsDirectory.appendingPathComponent(meta.fileName)
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.moveItem(at: url, to: destination)
        } catch {
            NSLog("WristPlayer: не удалось сохранить файл: \(error)")
            return false
        }
        if let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value {
            meta.fileSize = size
        }
        if let artwork = info.artwork {
            try? artwork.write(to: artworkDirectory.appendingPathComponent("\(meta.id).jpg"), options: .atomic)
        }
        lock.withLock {
            index[meta.id] = meta
        }
        persistAndPublish()
        return true
    }

    /// Применяет манифест с телефона: удаляет лишние песни.
    func applyManifest(_ manifest: ManifestMessage) {
        let removed: Set<String> = lock.withLock {
            if let manifestDate, manifest.date < manifestDate { return [] }
            manifestIds = Set(manifest.ids)
            manifestDate = manifest.date
            return SyncPlanner.songsToDelete(manifest: Set(manifest.ids), local: Set(index.keys))
        }
        defaults.set(manifest.ids, forKey: DefaultsKey.manifestIds)
        defaults.set(manifest.date, forKey: DefaultsKey.manifestDate)
        removeFiles(removed)
        persistAndPublish(removed: removed)
    }

    /// Удаление пользователем прямо на часах.
    func delete(ids: Set<String>) {
        lock.withLock {
            manifestIds?.subtract(ids)
        }
        if let manifestIds {
            defaults.set(Array(manifestIds), forKey: DefaultsKey.manifestIds)
        }
        removeFiles(ids)
        persistAndPublish(removed: ids)
    }

    private func removeFiles(_ ids: Set<String>) {
        guard !ids.isEmpty else { return }
        let fm = FileManager.default
        let removed: [SongMeta] = lock.withLock {
            let metas = ids.compactMap { index[$0] }
            for id in ids { index[id] = nil }
            return metas
        }
        for meta in removed {
            try? fm.removeItem(at: songsDirectory.appendingPathComponent(meta.fileName))
            try? fm.removeItem(at: artworkDirectory.appendingPathComponent("\(meta.id).jpg"))
        }
        for id in ids { artworkCache.removeObject(forKey: id as NSString) }
    }

    // MARK: - Хранение

    private func persistAndPublish(removed: Set<String> = []) {
        let (snapshot, pending): ([SongMeta], Int) = lock.withLock {
            let values = Array(index.values)
            let pending = manifestIds.map { $0.subtracting(index.keys).count } ?? 0
            return (values, pending)
        }
        if !DemoContent.isEnabled, let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: indexURL, options: .atomic)
        }
        let sorted = Self.sort(snapshot)
        DispatchQueue.main.async {
            self.songs = sorted
            self.pendingCount = pending
            if !removed.isEmpty { self.onSongsRemoved?(removed) }
        }
    }

    private static func sort(_ songs: [SongMeta]) -> [SongMeta] {
        songs.sorted { $0.sortKey.localizedStandardCompare($1.sortKey) == .orderedAscending }
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([SongMeta].self, from: data) else { return }
        let fm = FileManager.default
        let existing = decoded.filter { fm.fileExists(atPath: songsDirectory.appendingPathComponent($0.fileName).path) }
        index = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        songs = Self.sort(existing)
        pendingCount = manifestIds.map { $0.subtracting(index.keys).count } ?? 0
    }

    private func loadDemo() {
        let metas = DemoContent.metas()
        for (offset, meta) in metas.enumerated() {
            let url = songsDirectory.appendingPathComponent(meta.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? DemoContent.writeTone(to: url, seconds: 4, frequency: 330 + Double(offset) * 55)
            }
        }
        index = Dictionary(uniqueKeysWithValues: metas.map { ($0.id, $0) })
        songs = Self.sort(metas)
        pendingCount = 2
    }
}
