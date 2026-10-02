import AVFoundation
import Foundation

/// Перекодирует «тяжёлые» форматы (WAV, AIFF, FLAC…) в AAC перед отправкой на часы:
/// меньше места на часах, быстрее передача, гарантированно воспроизводится на watchOS.
enum Transcoder {
    static let extensionsToConvert: Set<String> = ["wav", "aif", "aiff", "aifc", "caf", "flac"]

    static func needsConversion(_ meta: SongMeta) -> Bool {
        extensionsToConvert.contains(meta.fileExtension)
    }

    static var cacheDirectory: URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchCopies", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func convertedURL(for meta: SongMeta) -> URL {
        cacheDirectory.appendingPathComponent("\(meta.id).m4a")
    }

    /// Возвращает файл в AAC (из кеша или только что сконвертированный).
    static func convertToAAC(source: URL, meta: SongMeta) async throws -> URL {
        let output = convertedURL(for: meta)
        if FileManager.default.fileExists(atPath: output.path) { return output }
        let temp = cacheDirectory.appendingPathComponent("\(meta.id)-\(UUID().uuidString).m4a")
        let asset = AVURLAsset(url: source)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try await session.export(to: temp, as: .m4a)
        try FileManager.default.moveItem(at: temp, to: output)
        return output
    }

    static func removeCached(ids: Set<String>) {
        for id in ids {
            try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent("\(id).m4a"))
        }
    }
}
