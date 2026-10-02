import Foundation

/// Описание песни, общее для телефона и часов.
/// На часы передаётся вместе с файлом (в метаданных `WCSessionFileTransfer`).
struct SongMeta: Codable, Hashable, Identifiable, Sendable {
    /// Стабильный идентификатор (UUID-строка), одинаковый на телефоне и часах.
    var id: String
    /// Имя файла в хранилище: `<id>.<ext>`.
    var fileName: String
    var title: String
    var artist: String?
    var album: String?
    /// Длительность в секундах.
    var duration: Double
    /// Размер файла в байтах.
    var fileSize: Int64
    var addedAt: Date

    var fileExtension: String { (fileName as NSString).pathExtension.lowercased() }

    /// «Исполнитель — Альбом» или то, что из этого есть.
    var subtitle: String {
        [artist, album].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " — ")
    }

    /// Ключ сортировки: исполнитель, затем название.
    var sortKey: String {
        ((artist ?? "") + "\u{1}" + title).lowercased()
    }
}

extension SongMeta {
    /// Название и исполнитель, угаданные из имени файла вида «Исполнитель - Название.mp3»
    /// (используется, когда в файле нет тегов).
    static func guessTitleAndArtist(fromFileName fileName: String) -> (title: String, artist: String?) {
        var base = (fileName as NSString).deletingPathExtension
        base = base.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
        // Убираем ведущий номер трека: «01 - », «01. », «1 »
        if let range = base.range(of: #"^\d{1,3}\s*[-.)]?\s+"#, options: .regularExpression) {
            let rest = base[range.upperBound...]
            if !rest.isEmpty { base = String(rest) }
        }
        for separator in [" - ", " – ", " — "] {
            if let range = base.range(of: separator) {
                let artist = base[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
                let title = base[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !artist.isEmpty && !title.isEmpty { return (title, artist) }
            }
        }
        return (base.isEmpty ? fileName : base, nil)
    }
}

enum Format {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// «1 песня», «3 песни», «7 песен».
    static func songs(_ count: Int) -> String {
        let n = abs(count) % 100, n1 = n % 10
        let word: String
        if n > 10 && n < 20 { word = "песен" }
        else if n1 == 1 { word = "песня" }
        else if n1 >= 2 && n1 <= 4 { word = "песни" }
        else { word = "песен" }
        return "\(count) \(word)"
    }
}
