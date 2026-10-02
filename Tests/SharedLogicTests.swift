import XCTest

/// Генератор с фиксированным зерном для воспроизводимых тестов перемешивания.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class SongMetaTests: XCTestCase {
    func testGuessArtistAndTitle() {
        let result = SongMeta.guessTitleAndArtist(fromFileName: "Кино - Группа крови.mp3")
        XCTAssertEqual(result.title, "Группа крови")
        XCTAssertEqual(result.artist, "Кино")
    }

    func testGuessStripsTrackNumber() {
        let result = SongMeta.guessTitleAndArtist(fromFileName: "03 - Queen - Bohemian Rhapsody.m4a")
        XCTAssertEqual(result.title, "Bohemian Rhapsody")
        XCTAssertEqual(result.artist, "Queen")
    }

    func testGuessWithoutArtist() {
        let result = SongMeta.guessTitleAndArtist(fromFileName: "my_song.wav")
        XCTAssertEqual(result.title, "my song")
        XCTAssertNil(result.artist)
    }

    func testNumericTitleIsKept() {
        let result = SongMeta.guessTitleAndArtist(fromFileName: "1979.mp3")
        XCTAssertEqual(result.title, "1979")
    }

    func testRussianPlural() {
        XCTAssertEqual(Format.songs(1), "1 песня")
        XCTAssertEqual(Format.songs(3), "3 песни")
        XCTAssertEqual(Format.songs(5), "5 песен")
        XCTAssertEqual(Format.songs(11), "11 песен")
        XCTAssertEqual(Format.songs(21), "21 песня")
        XCTAssertEqual(Format.songs(112), "112 песен")
    }

    func testDurationFormat() {
        XCTAssertEqual(Format.duration(0), "0:00")
        XCTAssertEqual(Format.duration(65), "1:05")
        XCTAssertEqual(Format.duration(3725), "1:02:05")
        XCTAssertEqual(Format.duration(.nan), "0:00")
    }
}

final class SyncProtocolTests: XCTestCase {
    private let song = SongMeta(id: "A", fileName: "A.mp3", title: "Песня", artist: "Исполнитель", album: nil,
                                duration: 180, fileSize: 4_000_000, addedAt: Date(timeIntervalSince1970: 1000))

    func testManifestRoundTrip() {
        let message = ManifestMessage(ids: ["A", "B"], date: Date(timeIntervalSince1970: 5000))
        XCTAssertEqual(ManifestMessage(context: message.context), message)
        XCTAssertNil(ManifestMessage(context: [:]))
    }

    func testInventoryRoundTrip() {
        let message = InventoryMessage(ids: ["A"], usedBytes: 123, freeBytes: 456, date: Date(timeIntervalSince1970: 7))
        XCTAssertEqual(InventoryMessage(context: message.context), message)
        let noFree = InventoryMessage(ids: [], usedBytes: 0, freeBytes: nil, date: Date(timeIntervalSince1970: 7))
        XCTAssertEqual(InventoryMessage(context: noFree.context), noFree)
    }

    func testFileMetadataRoundTrip() throws {
        let metadata = FileTransferMetadata(song: song, artwork: Data([1, 2, 3]), sentAt: Date(timeIntervalSince1970: 9))
        let decoded = try XCTUnwrap(FileTransferMetadata(dictionary: metadata.dictionary))
        XCTAssertEqual(decoded.song, song)
        XCTAssertEqual(decoded.artwork, Data([1, 2, 3]))
        XCTAssertEqual(decoded.sentAt, Date(timeIntervalSince1970: 9))
        XCTAssertEqual(FileTransferMetadata.songId(in: metadata.dictionary), "A")
        XCTAssertNil(FileTransferMetadata(dictionary: nil))
    }

    func testMetadataIsPropertyList() {
        // WatchConnectivity принимает только plist-типы.
        let metadata = FileTransferMetadata(song: song, artwork: nil, sentAt: Date()).dictionary
        XCTAssertTrue(PropertyListSerialization.propertyList(metadata, isValidFor: .binary))
        let manifest = ManifestMessage(ids: ["A"], date: Date()).context
        XCTAssertTrue(PropertyListSerialization.propertyList(manifest, isValidFor: .binary))
        let inventory = InventoryMessage(ids: ["A"], usedBytes: 1, freeBytes: 2, date: Date()).context
        XCTAssertTrue(PropertyListSerialization.propertyList(inventory, isValidFor: .binary))
    }

    func testSongsToSendKeepsOrderAndSkipsKnown() {
        let result = SyncPlanner.songsToSend(desired: ["A", "B", "C", "D", "B"], onWatch: ["B"], inFlight: ["C"])
        XCTAssertEqual(result, ["A", "D"])
    }

    func testTransfersToCancel() {
        XCTAssertEqual(SyncPlanner.transfersToCancel(desired: ["A"], inFlight: ["A", "B"]), ["B"])
    }

    func testSongsToDelete() {
        XCTAssertEqual(SyncPlanner.songsToDelete(manifest: ["A", "B"], local: ["B", "C"]), ["C"])
    }

    func testKeepIncomingFile() {
        let manifestDate = Date(timeIntervalSince1970: 100)
        // В манифесте — оставляем.
        XCTAssertTrue(SyncPlanner.shouldKeepIncoming(id: "A", sentAt: Date(timeIntervalSince1970: 50),
                                                     manifest: ["A"], manifestDate: manifestDate))
        // Нет в манифесте, но отправлен позже него — новый манифест ещё в пути.
        XCTAssertTrue(SyncPlanner.shouldKeepIncoming(id: "B", sentAt: Date(timeIntervalSince1970: 150),
                                                     manifest: ["A"], manifestDate: manifestDate))
        // Нет в манифесте и отправлен раньше — песню уже убрали с часов.
        XCTAssertFalse(SyncPlanner.shouldKeepIncoming(id: "B", sentAt: Date(timeIntervalSince1970: 50),
                                                      manifest: ["A"], manifestDate: manifestDate))
        // Манифеста ещё не было.
        XCTAssertTrue(SyncPlanner.shouldKeepIncoming(id: "B", sentAt: .distantPast, manifest: nil, manifestDate: nil))
    }

    func testDeliveriesToForget() {
        let inventory = InventoryMessage(ids: ["A"], usedBytes: 0, freeBytes: nil, date: Date(timeIntervalSince1970: 1000))
        let delivered: [String: Date] = [
            "A": Date(timeIntervalSince1970: 990),   // подтверждено инвентарём
            "B": Date(timeIntervalSince1970: 100),   // давно доставлено, но на часах нет — забыть
            "C": Date(timeIntervalSince1970: 995),   // только что доставлено — инвентарь мог не успеть
        ]
        XCTAssertEqual(SyncPlanner.deliveriesToForget(delivered: delivered, inventory: inventory), ["A", "B"])
    }
}

final class PlayQueueTests: XCTestCase {
    func testSequentialPlaybackStopsAtEnd() {
        var queue = PlayQueue(items: ["A", "B", "C"], startAt: 1)
        XCTAssertEqual(queue.current, "B")
        XCTAssertEqual(queue.advance(auto: true), "C")
        XCTAssertNil(queue.advance(auto: true))
        XCTAssertEqual(queue.current, "C")
    }

    func testRepeatAllWraps() {
        var queue = PlayQueue(items: ["A", "B"], startAt: 1, repeatMode: .all)
        XCTAssertEqual(queue.advance(auto: true), "A")
        XCTAssertEqual(queue.goBack(), "B")
    }

    func testRepeatOneRepeatsOnlyAutomatically() {
        var queue = PlayQueue(items: ["A", "B"], repeatMode: .one)
        XCTAssertEqual(queue.advance(auto: true), "A")
        XCTAssertEqual(queue.advance(auto: false), "B")
    }

    func testGoBackAtStartStays() {
        var queue = PlayQueue(items: ["A", "B"])
        XCTAssertEqual(queue.goBack(), "A")
    }

    func testShuffleKeepsCurrentFirstAndAllItems() {
        var generator = SeededGenerator(state: 42)
        let items = (1...20).map { "S\($0)" }
        var queue = PlayQueue(items: items, startAt: 5)
        queue.setShuffle(true, using: &generator)
        XCTAssertTrue(queue.isShuffled)
        XCTAssertEqual(queue.current, "S6")
        XCTAssertEqual(queue.order.first, "S6")
        XCTAssertEqual(Set(queue.order), Set(items))
        XCTAssertEqual(queue.order.count, items.count)
        queue.setShuffle(false, using: &generator)
        XCTAssertEqual(queue.order, items)
        XCTAssertEqual(queue.current, "S6")
    }

    func testDuplicatesAreRemoved() {
        let queue = PlayQueue(items: ["A", "B", "A"])
        XCTAssertEqual(queue.items, ["A", "B"])
    }

    func testRemoveCurrentMovesToNext() {
        var queue = PlayQueue(items: ["A", "B", "C"], startAt: 1)
        XCTAssertTrue(queue.remove(["B"]))
        XCTAssertEqual(queue.current, "C")
    }

    func testRemoveBeforeCurrentKeepsCurrent() {
        var queue = PlayQueue(items: ["A", "B", "C"], startAt: 2)
        XCTAssertFalse(queue.remove(["A"]))
        XCTAssertEqual(queue.current, "C")
        XCTAssertEqual(queue.position, 1)
    }

    func testRemoveEverything() {
        var queue = PlayQueue(items: ["A"])
        XCTAssertTrue(queue.remove(["A"]))
        XCTAssertNil(queue.current)
        XCTAssertTrue(queue.isEmpty)
    }

    func testCodableRoundTrip() throws {
        var queue = PlayQueue(items: ["A", "B", "C"], startAt: 2, repeatMode: .all)
        queue.setShuffle(true)
        let data = try JSONEncoder().encode(queue)
        XCTAssertEqual(try JSONDecoder().decode(PlayQueue.self, from: data), queue)
    }

    func testRepeatModeCycle() {
        XCTAssertEqual(RepeatMode.off.next, .all)
        XCTAssertEqual(RepeatMode.all.next, .one)
        XCTAssertEqual(RepeatMode.one.next, .off)
    }
}

final class DemoContentTests: XCTestCase {
    func testToneIsValidWav() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tone-\(UUID().uuidString).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        try DemoContent.writeTone(to: url, seconds: 1, frequency: 440)
        let data = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(data.count, 44 + 22_050 * 2)
    }
}
