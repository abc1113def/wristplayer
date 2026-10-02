import Foundation

/// Демо-данные для скриншотов и проверки в симуляторе (запуск с аргументом `-demo`).
enum DemoContent {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// Значение аргумента вида `-demoScreen nowPlaying`.
    static func argument(_ name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: name), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static let songs: [(title: String, artist: String, album: String, duration: Double)] = [
        ("Кукушка", "Кино", "Чёрный альбом", 397),
        ("Blinding Lights", "The Weeknd", "After Hours", 200),
        ("Группа крови", "Кино", "Группа крови", 286),
        ("Bohemian Rhapsody", "Queen", "A Night at the Opera", 354),
        ("Звезда по имени Солнце", "Кино", "Звезда по имени Солнце", 225),
        ("Smells Like Teen Spirit", "Nirvana", "Nevermind", 301),
        ("Лето", "Кино", "Чёрный альбом", 345),
    ]

    static func metas(now: Date = Date()) -> [SongMeta] {
        songs.enumerated().map { index, song in
            SongMeta(id: String(format: "00000000-0000-0000-0000-%012d", index + 1),
                     fileName: String(format: "00000000-0000-0000-0000-%012d.wav", index + 1),
                     title: song.title, artist: song.artist, album: song.album,
                     duration: song.duration, fileSize: Int64(song.duration * 32_000),
                     addedAt: now.addingTimeInterval(Double(-index) * 3600))
        }
    }

    /// Пишет короткий WAV-файл с тоном, чтобы демо-песни реально проигрывались.
    static func writeTone(to url: URL, seconds: Double = 3, frequency: Double = 440) throws {
        let sampleRate = 22_050
        let sampleCount = Int(Double(sampleRate) * seconds)
        var pcm = Data(capacity: sampleCount * 2)
        for i in 0..<sampleCount {
            let t = Double(i) / Double(sampleRate)
            let fade = min(1, min(t * 20, (seconds - t) * 20))
            let value = Int16(sin(2 * .pi * frequency * t) * 0.3 * fade * Double(Int16.max))
            withUnsafeBytes(of: value.littleEndian) { pcm.append(contentsOf: $0) }
        }
        var header = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + pcm.count))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))                 // размер fmt-чанка
        append(UInt16(1))                  // PCM
        append(UInt16(1))                  // моно
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * 2))     // байт в секунду
        append(UInt16(2))                  // выравнивание блока
        append(UInt16(16))                 // бит на сэмпл
        header.append(contentsOf: Array("data".utf8))
        append(UInt32(pcm.count))
        try (header + pcm).write(to: url, options: .atomic)
    }
}
