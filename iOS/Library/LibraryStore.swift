import AVFoundation
import Foundation
import Observation
import UIKit
import UniformTypeIdentifiers

/// Песня в библиотеке телефона.
struct Song: Codable, Identifiable, Hashable {
    var meta: SongMeta
    /// Пользователь хочет, чтобы песня была на часах.
    var onWatch: Bool

    var id: String { meta.id }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case dateAdded, title, artist

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dateAdded: "По дате добавления"
        case .title: "По названию"
        case .artist: "По исполнителю"
        }
    }
}

/// Библиотека песен на телефоне: файлы, метаданные, обложки, отметки «на часах».
@Observable
final class LibraryStore {
    static let shared = LibraryStore()

    private(set) var songs: [Song] = []
    /// Сколько файлов сейчас импортируется.
    private(set) var importingCount = 0
    /// Сообщение для пользователя после импорта (ошибки, дубликаты).
    var notice: String?

    /// Вызывается на главном потоке после любого изменения, влияющего на синхронизацию.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored let songsDirectory: URL
    @ObservationIgnored let artworkDirectory: URL
    @ObservationIgnored let documentsDirectory: URL
    @ObservationIgnored private let indexURL: URL
    @ObservationIgnored private let artworkCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var importQueue: [URL] = []
    @ObservationIgnored private var isImporting = false
    @ObservationIgnored private var currentImport: URL?
    /// Файлы из папки приложения, которые не удалось импортировать (чтобы не повторять ошибку при каждом открытии).
    @ObservationIgnored private var rejectedDocuments: Set<URL> = []

    static let importableExtensions: Set<String> = [
        "mp3", "m4a", "aac", "m4b", "wav", "aif", "aiff", "aifc", "caf", "flac", "mp4",
    ]

    init(root: URL? = nil) {
        let fm = FileManager.default
        let support = root ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        songsDirectory = support.appendingPathComponent("Songs", isDirectory: true)
        artworkDirectory = support.appendingPathComponent("Artwork", isDirectory: true)
        indexURL = support.appendingPathComponent("library.json")
        documentsDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for dir in [songsDirectory, artworkDirectory] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if DemoContent.isEnabled {
            loadDemo()
        } else {
            load()
        }
    }

    // MARK: - Доступ

    func fileURL(for song: Song) -> URL {
        songsDirectory.appendingPathComponent(song.meta.fileName)
    }

    func artworkURL(for id: String) -> URL {
        artworkDirectory.appendingPathComponent("\(id).jpg")
    }

    func artworkData(for id: String) -> Data? {
        try? Data(contentsOf: artworkURL(for: id))
    }

    func artwork(for id: String) -> UIImage? {
        if let cached = artworkCache.object(forKey: id as NSString) { return cached }
        guard let data = artworkData(for: id), let image = UIImage(data: data) else { return nil }
        artworkCache.setObject(image, forKey: id as NSString)
        return image
    }

    func song(id: String) -> Song? {
        songs.first { $0.id == id }
    }

    var totalBytes: Int64 { songs.reduce(0) { $0 + $1.meta.fileSize } }
    var onWatchBytes: Int64 { songs.filter(\.onWatch).reduce(0) { $0 + $1.meta.fileSize } }

    func sorted(by order: LibrarySort) -> [Song] {
        switch order {
        case .dateAdded:
            songs.sorted { $0.meta.addedAt > $1.meta.addedAt }
        case .title:
            songs.sorted { $0.meta.title.localizedStandardCompare($1.meta.title) == .orderedAscending }
        case .artist:
            songs.sorted { $0.meta.sortKey.localizedStandardCompare($1.meta.sortKey) == .orderedAscending }
        }
    }

    // MARK: - Изменения

    func setOnWatch(_ onWatch: Bool, ids: some Sequence<String>) {
        let ids = Set(ids)
        var changed = false
        for index in songs.indices where ids.contains(songs[index].id) && songs[index].onWatch != onWatch {
            songs[index].onWatch = onWatch
            changed = true
        }
        if changed { didChange() }
    }

    func toggleOnWatch(_ id: String) {
        guard let song = song(id: id) else { return }
        setOnWatch(!song.onWatch, ids: [id])
    }

    func delete(ids: Set<String>) {
        let fm = FileManager.default
        for song in songs where ids.contains(song.id) {
            try? fm.removeItem(at: fileURL(for: song))
            try? fm.removeItem(at: artworkURL(for: song.id))
            artworkCache.removeObject(forKey: song.id as NSString)
        }
        songs.removeAll { ids.contains($0.id) }
        didChange()
    }

    private func didChange() {
        save()
        onChange?()
    }

    // MARK: - Импорт

    /// Импортирует файлы, выбранные пользователем или открытые через «Поделиться».
    func importFiles(_ urls: [URL]) {
        importQueue.append(contentsOf: urls)
        importingCount = importQueue.count + (isImporting ? 1 : 0)
        processImportQueue()
    }

    /// Забирает аудиофайлы, которые пользователь положил в папку приложения
    /// (Файлы → На iPhone → WristPlayer, или Apple Devices / iTunes на компьютере).
    func importFromDocumentsFolder() {
        guard !DemoContent.isEnabled else { return }
        let fm = FileManager.default
        var found: [URL] = []
        for dir in [documentsDirectory, documentsDirectory.appendingPathComponent("Inbox")] {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            for url in items where Self.isImportable(url) && !importQueue.contains(url)
                && url != currentImport && !rejectedDocuments.contains(url) {
                found.append(url)
            }
        }
        if !found.isEmpty { importFiles(found) }
    }

    /// Для сквозного теста в CI: добавляет три тоновых WAV-файла (они же проверяют перекодирование в AAC).
    func seedForEndToEndTest() {
        guard songs.isEmpty else { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("e2e", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let urls = (1...3).compactMap { index -> URL? in
            let url = dir.appendingPathComponent("E2E Artist - Tone \(index).wav")
            do {
                try DemoContent.writeTone(to: url, seconds: 5, frequency: 300 + Double(index) * 100)
                return url
            } catch {
                return nil
            }
        }
        importFiles(urls)
    }

    static func isImportable(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if importableExtensions.contains(ext) { return true }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .audio) { return true }
        return false
    }

    private func processImportQueue() {
        guard !isImporting, !importQueue.isEmpty else { return }
        isImporting = true
        let url = importQueue.removeFirst()
        currentImport = url
        Task {
            let result = await Self.importFile(url, into: self.songsDirectory, artworkDirectory: self.artworkDirectory,
                                               documentsDirectory: self.documentsDirectory)
            await MainActor.run {
                self.finishImport(result, source: url)
            }
        }
    }

    private func finishImport(_ result: Result<SongMeta, ImportError>, source: URL) {
        switch result {
        case .success(let meta):
            if let duplicate = songs.first(where: { $0.meta.title == meta.title && $0.meta.artist == meta.artist
                && $0.meta.fileSize == meta.fileSize }) {
                // Такой файл уже есть — убираем копию.
                try? FileManager.default.removeItem(at: songsDirectory.appendingPathComponent(meta.fileName))
                try? FileManager.default.removeItem(at: artworkURL(for: meta.id))
                notice = "«\(duplicate.meta.title)» уже есть в библиотеке"
            } else {
                songs.append(Song(meta: meta, onWatch: true))
                didChange()
            }
        case .failure(let error):
            notice = error.message
            rejectedDocuments.insert(source)
        }
        currentImport = nil
        isImporting = false
        importingCount = importQueue.count
        processImportQueue()
    }

    enum ImportError: Error {
        case unsupported(String)
        case copyFailed(String, Error)

        var message: String {
            switch self {
            case .unsupported(let name): "«\(name)» — не аудиофайл или формат не поддерживается"
            case .copyFailed(let name, let error): "Не удалось добавить «\(name)»: \(error.localizedDescription)"
            }
        }
    }

    /// Копирует файл в библиотеку и читает его теги. Выполняется вне главного потока.
    private static func importFile(_ source: URL, into songsDirectory: URL, artworkDirectory: URL,
                                   documentsDirectory: URL) async -> Result<SongMeta, ImportError> {
        let name = source.lastPathComponent
        guard isImportable(source) else { return .failure(.unsupported(name)) }

        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let id = UUID().uuidString
        let ext = source.pathExtension.lowercased()
        let fileName = "\(id).\(ext)"
        let destination = songsDirectory.appendingPathComponent(fileName)

        // Файлы из нашей папки Documents переносим, остальные копируем.
        let isOwnDocument = source.resolvingSymlinksInPath().path
            .hasPrefix(documentsDirectory.resolvingSymlinksInPath().path)
        do {
            var coordinationError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { url in
                do {
                    if isOwnDocument {
                        try fm.moveItem(at: url, to: destination)
                    } else {
                        try fm.copyItem(at: url, to: destination)
                    }
                } catch {
                    copyError = error
                }
            }
            if let error = coordinationError ?? copyError { throw error }
        } catch {
            return .failure(.copyFailed(name, error))
        }

        let asset = AVURLAsset(url: destination)
        let playable = (try? await asset.load(.isPlayable)) ?? false
        guard playable else {
            try? fm.removeItem(at: destination)
            return .failure(.unsupported(name))
        }

        let guess = SongMeta.guessTitleAndArtist(fromFileName: name)
        var title: String?
        var artist: String?
        var album: String?
        var artworkData: Data?
        let duration = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle: title = try? await item.load(.stringValue)
                case .commonKeyArtist: artist = try? await item.load(.stringValue)
                case .commonKeyAlbumName: album = try? await item.load(.stringValue)
                case .commonKeyArtwork: artworkData = try? await item.load(.dataValue)
                default: break
                }
            }
        }

        if let artworkData, let thumbnail = Self.thumbnail(from: artworkData, side: 240) {
            try? thumbnail.write(to: artworkDirectory.appendingPathComponent("\(id).jpg"), options: .atomic)
        }

        let size = (try? fm.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.int64Value ?? 0
        let meta = SongMeta(id: id, fileName: fileName,
                            title: title.nonEmpty ?? guess.title,
                            artist: artist.nonEmpty ?? guess.artist,
                            album: album.nonEmpty,
                            duration: duration.isFinite ? duration : 0,
                            fileSize: size,
                            addedAt: Date())
        return .success(meta)
    }

    /// Квадратная JPEG-миниатюра обложки.
    static func thumbnail(from data: Data, side: CGFloat) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        let scaled = renderer.image { _ in
            let size = image.size
            let scale = max(side / max(size.width, 1), side / max(size.height, 1))
            let drawSize = CGSize(width: size.width * scale, height: size.height * scale)
            image.draw(in: CGRect(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
                                  width: drawSize.width, height: drawSize.height))
        }
        return scaled.jpegData(compressionQuality: 0.75)
    }

    // MARK: - Хранение

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([Song].self, from: data) else { return }
        // Пропускаем записи, чьи файлы пропали.
        let fm = FileManager.default
        songs = decoded.filter { fm.fileExists(atPath: songsDirectory.appendingPathComponent($0.meta.fileName).path) }
    }

    private func save() {
        guard !DemoContent.isEnabled else { return }
        do {
            let data = try JSONEncoder().encode(songs)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            notice = "Не удалось сохранить библиотеку: \(error.localizedDescription)"
        }
    }

    private func loadDemo() {
        let metas = DemoContent.metas()
        for meta in metas {
            let url = songsDirectory.appendingPathComponent(meta.fileName)
            if !FileManager.default.fileExists(atPath: url.path) {
                try? DemoContent.writeTone(to: url, seconds: 3, frequency: 330 + Double(metas.firstIndex(of: meta) ?? 0) * 55)
            }
        }
        songs = metas.enumerated().map { index, meta in Song(meta: meta, onWatch: index != 3) }
    }
}

private extension Optional where Wrapped == String {
    /// `nil`, если строка пустая или из одних пробелов.
    var nonEmpty: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
