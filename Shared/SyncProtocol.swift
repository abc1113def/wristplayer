import Foundation

/// Протокол обмена между телефоном и часами через WatchConnectivity.
///
/// - Телефон → часы, `applicationContext`: манифест — список id песен, которые должны быть на часах.
/// - Телефон → часы, `transferFile`: сам аудиофайл + `FileTransferMetadata`.
/// - Часы → телефон, `applicationContext`: инвентарь — какие песни реально лежат на часах и сколько места.
/// - Часы → телефон, `transferUserInfo`: песни, удалённые пользователем прямо на часах.
enum SyncKeys {
    static let manifest = "manifest"
    static let manifestDate = "manifestDate"

    static let songId = "songId"
    static let song = "song"
    static let artwork = "artwork"
    static let sentAt = "sentAt"

    static let inventory = "inventory"
    static let usedBytes = "usedBytes"
    static let freeBytes = "freeBytes"
    static let inventoryDate = "inventoryDate"

    static let removedOnWatch = "removedOnWatch"
}

/// Желаемый набор песен на часах.
struct ManifestMessage: Equatable {
    var ids: [String]
    /// Момент, когда набор последний раз менялся (часы телефона).
    var date: Date

    var context: [String: Any] {
        [SyncKeys.manifest: ids, SyncKeys.manifestDate: date]
    }

    init(ids: [String], date: Date) {
        self.ids = ids
        self.date = date
    }

    init?(context: [String: Any]) {
        guard let ids = context[SyncKeys.manifest] as? [String],
              let date = context[SyncKeys.manifestDate] as? Date else { return nil }
        self.init(ids: ids, date: date)
    }
}

/// Что лежит на часах.
struct InventoryMessage: Equatable {
    var ids: [String]
    var usedBytes: Int64
    var freeBytes: Int64?
    var date: Date

    var context: [String: Any] {
        var dict: [String: Any] = [
            SyncKeys.inventory: ids,
            SyncKeys.usedBytes: NSNumber(value: usedBytes),
            SyncKeys.inventoryDate: date,
        ]
        if let freeBytes { dict[SyncKeys.freeBytes] = NSNumber(value: freeBytes) }
        return dict
    }

    init(ids: [String], usedBytes: Int64, freeBytes: Int64?, date: Date) {
        self.ids = ids
        self.usedBytes = usedBytes
        self.freeBytes = freeBytes
        self.date = date
    }

    init?(context: [String: Any]) {
        guard let ids = context[SyncKeys.inventory] as? [String],
              let date = context[SyncKeys.inventoryDate] as? Date else { return nil }
        let used = (context[SyncKeys.usedBytes] as? NSNumber)?.int64Value ?? 0
        let free = (context[SyncKeys.freeBytes] as? NSNumber)?.int64Value
        self.init(ids: ids, usedBytes: used, freeBytes: free, date: date)
    }
}

/// Метаданные, которые едут вместе с аудиофайлом.
struct FileTransferMetadata {
    var song: SongMeta
    /// Миниатюра обложки (JPEG), если есть.
    var artwork: Data?
    var sentAt: Date

    var dictionary: [String: Any] {
        var dict: [String: Any] = [
            SyncKeys.songId: song.id,
            SyncKeys.sentAt: sentAt,
        ]
        if let data = try? JSONEncoder().encode(song) { dict[SyncKeys.song] = data }
        if let artwork { dict[SyncKeys.artwork] = artwork }
        return dict
    }

    init(song: SongMeta, artwork: Data?, sentAt: Date) {
        self.song = song
        self.artwork = artwork
        self.sentAt = sentAt
    }

    init?(dictionary: [String: Any]?) {
        guard let dictionary,
              let data = dictionary[SyncKeys.song] as? Data,
              let song = try? JSONDecoder().decode(SongMeta.self, from: data) else { return nil }
        self.init(song: song,
                  artwork: dictionary[SyncKeys.artwork] as? Data,
                  sentAt: dictionary[SyncKeys.sentAt] as? Date ?? .distantPast)
    }

    static func songId(in dictionary: [String: Any]?) -> String? {
        dictionary?[SyncKeys.songId] as? String
    }
}

/// Чистая логика синхронизации (покрыта тестами).
enum SyncPlanner {
    /// Песни, которые нужно отправить: желаемые − уже на часах − уже в пути. Порядок как в `desired`.
    static func songsToSend(desired: [String], onWatch: Set<String>, inFlight: Set<String>) -> [String] {
        var seen = Set<String>()
        return desired.filter { id in
            guard !onWatch.contains(id), !inFlight.contains(id), !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    /// Передачи, которые больше не нужны (песню убрали с часов, пока она ехала).
    static func transfersToCancel(desired: Set<String>, inFlight: Set<String>) -> Set<String> {
        inFlight.subtracting(desired)
    }

    /// На часах: какие локальные песни удалить, получив манифест.
    static func songsToDelete(manifest: Set<String>, local: Set<String>) -> Set<String> {
        local.subtracting(manifest)
    }

    /// На часах: оставлять ли пришедший файл.
    ///
    /// Файл и манифест идут разными каналами и могут прийти в любом порядке. Если песни нет
    /// в известном манифесте, но файл отправлен *после* этого манифеста — значит, новый манифест
    /// с этой песней ещё в пути, и файл надо оставить.
    static func shouldKeepIncoming(id: String, sentAt: Date, manifest: Set<String>?, manifestDate: Date?) -> Bool {
        guard let manifest, let manifestDate else { return true }
        if manifest.contains(id) { return true }
        return sentAt > manifestDate
    }

    /// Телефон: какие локальные отметки «доставлено» можно забыть, получив свежий инвентарь.
    /// Отметка нужна, чтобы не отправлять песню повторно, пока инвентарь с часов ещё не пришёл.
    static func deliveriesToForget(delivered: [String: Date], inventory: InventoryMessage,
                                   slack: TimeInterval = 60) -> Set<String> {
        let present = Set(inventory.ids)
        return Set(delivered.compactMap { id, deliveredAt in
            if present.contains(id) { return id }
            return deliveredAt < inventory.date.addingTimeInterval(-slack) ? id : nil
        })
    }
}
