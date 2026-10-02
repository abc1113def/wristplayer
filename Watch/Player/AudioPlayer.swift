import AVFoundation
import Foundation
import MediaPlayer
import Observation
import WatchKit

/// Куда выводить звук.
enum OutputMode: String, CaseIterable, Identifiable {
    /// Bluetooth-наушники или колонка; музыка продолжает играть при опущенной руке.
    case headphones
    /// Динамик часов: только пока приложение на экране (ограничение watchOS).
    case speaker

    var id: String { rawValue }

    var title: String {
        switch self {
        case .headphones: "Наушники"
        case .speaker: "Динамик часов"
        }
    }

    var details: String {
        switch self {
        case .headphones:
            "Bluetooth-наушники или колонка. Музыка играет в фоне, управление — в «Исполняется»."
        case .speaker:
            "Экспериментально: watchOS может не пустить звук в динамик, а при опускании руки воспроизведение остановится."
        }
    }
}

/// Плеер на часах.
@Observable
final class AudioPlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioPlayer()

    private(set) var queue = PlayQueue(items: [])
    private(set) var current: SongMeta?
    private(set) var isPlaying = false
    /// Идёт подключение аудиосессии (система может показать выбор наушников).
    private(set) var isStarting = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var volume: Double = 0.8
    private(set) var outputMode: OutputMode = .headphones
    var errorMessage: String?

    @ObservationIgnored private let library: WatchLibrary
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var activeSessionMode: OutputMode?
    @ObservationIgnored private var lastSaved = Date.distantPast
    @ObservationIgnored private var commandsConfigured = false
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum DefaultsKey {
        static let queue = "player.queue"
        static let time = "player.time"
        static let volume = "player.volume"
        static let output = "player.output"
    }

    init(library: WatchLibrary = .shared) {
        self.library = library
        super.init()
        if defaults.object(forKey: DefaultsKey.volume) != nil {
            volume = defaults.double(forKey: DefaultsKey.volume)
        }
        if let raw = defaults.string(forKey: DefaultsKey.output), let mode = OutputMode(rawValue: raw) {
            outputMode = mode
        }
        library.onSongsRemoved = { [weak self] ids in
            self?.handleRemoved(ids)
        }
        observeAudioSession()
        if DemoContent.isEnabled {
            setUpDemo()
        } else {
            restoreState()
        }
    }

    // MARK: - Управление

    /// Играть список песен, начиная с `index`. `shuffle` — перемешать (со случайной песни).
    func play(ids: [String], startAt index: Int = 0, shuffle: Bool = false) {
        guard !ids.isEmpty else { return }
        let start = shuffle ? Int.random(in: 0..<ids.count) : index
        queue = PlayQueue(items: ids, startAt: start, shuffled: shuffle || queue.isShuffled,
                          repeatMode: queue.repeatMode)
        loadCurrent(autoplay: true)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else if player != nil {
            startPlayback()
        } else if queue.current != nil {
            loadCurrent(autoplay: true, startTime: currentTime)
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        resumeAfterInterruption = false
        stopTimer()
        updateNowPlaying()
        saveState()
    }

    func next() {
        let wasPlaying = isPlaying || isStarting
        guard queue.advance(auto: false) != nil else {
            WKInterfaceDevice.current().play(.failure)
            return
        }
        loadCurrent(autoplay: wasPlaying)
    }

    func previous() {
        let wasPlaying = isPlaying || isStarting
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        queue.goBack()
        loadCurrent(autoplay: wasPlaying)
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        updateNowPlaying()
        saveState()
    }

    func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        saveState()
    }

    func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        saveState()
    }

    func setVolume(_ value: Double) {
        volume = min(max(value, 0), 1)
        player?.volume = Float(volume)
        defaults.set(volume, forKey: DefaultsKey.volume)
    }

    func setOutputMode(_ mode: OutputMode) {
        guard mode != outputMode else { return }
        let wasPlaying = isPlaying
        if wasPlaying { pause() }
        outputMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.output)
        activeSessionMode = nil
        if wasPlaying { startPlayback() }
    }

    // MARK: - Воспроизведение

    private func loadCurrent(autoplay: Bool, startTime: Double = 0) {
        player?.stop()
        player = nil
        stopTimer()
        guard let id = queue.current, let meta = library.song(id: id) else {
            current = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            updateNowPlaying()
            saveState()
            return
        }
        current = meta
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: library.fileURL(for: meta))
            newPlayer.delegate = self
            newPlayer.volume = Float(volume)
            newPlayer.prepareToPlay()
            if startTime > 0 && startTime < newPlayer.duration - 1 {
                newPlayer.currentTime = startTime
            }
            player = newPlayer
            duration = newPlayer.duration
            currentTime = newPlayer.currentTime
        } catch {
            isPlaying = false
            errorMessage = "Не удалось открыть «\(meta.title)»: \(error.localizedDescription)"
            updateNowPlaying()
            return
        }
        if autoplay {
            startPlayback()
        } else {
            updateNowPlaying()
            saveState()
        }
    }

    private func startPlayback() {
        guard let player else { return }
        errorMessage = nil
        if activeSessionMode == outputMode {
            beginPlaying(player)
            return
        }
        isStarting = true
        Task { @MainActor in
            do {
                try await self.activateSession()
                self.isStarting = false
                self.beginPlaying(player)
            } catch {
                self.isStarting = false
                self.isPlaying = false
                self.errorMessage = self.outputMode == .headphones
                    ? "Подключите Bluetooth-наушники к часам и нажмите ▶︎ ещё раз."
                    : "Не удалось включить звук: \(error.localizedDescription)"
                self.updateNowPlaying()
            }
        }
    }

    private func beginPlaying(_ target: AVAudioPlayer) {
        guard target === player else { return }
        target.volume = Float(volume)
        guard target.play() else {
            isPlaying = false
            errorMessage = "Не удалось начать воспроизведение"
            return
        }
        isPlaying = true
        configureRemoteCommands()
        startTimer()
        updateNowPlaying()
        saveState()
    }

    private func activateSession() async throws {
        let session = AVAudioSession.sharedInstance()
        switch outputMode {
        case .headphones:
            try session.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        case .speaker:
            try session.setCategory(.playback, mode: .default, policy: .default, options: [])
        }
        let activated = try await session.activate(options: [])
        guard activated else { throw CocoaError(.userCancelled) }
        activeSessionMode = outputMode
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if Date().timeIntervalSince(lastSaved) > 5 { saveState() }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ finished: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard finished === self.player else { return }
            if self.queue.advance(auto: true) != nil {
                self.loadCurrent(autoplay: true)
            } else {
                // Очередь закончилась: остаёмся на последней песне, в начале.
                self.isPlaying = false
                self.stopTimer()
                self.player?.currentTime = 0
                self.currentTime = 0
                self.updateNowPlaying()
                self.saveState()
            }
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ failed: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            guard failed === self.player else { return }
            self.errorMessage = "Файл повреждён или не поддерживается"
            self.isPlaying = false
        }
    }

    // MARK: - Удалённые песни

    private func handleRemoved(_ ids: Set<String>) {
        let wasPlaying = isPlaying
        guard queue.remove(ids) else {
            saveState()
            return
        }
        if queue.current == nil {
            player?.stop()
            player = nil
            current = nil
            isPlaying = false
            stopTimer()
            updateNowPlaying()
            saveState()
        } else {
            loadCurrent(autoplay: wasPlaying)
        }
    }

    // MARK: - Прерывания и смена выхода

    private func observeAudioSession() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            if isPlaying {
                resumeAfterInterruption = true
                isPlaying = false
                stopTimer()
                updateNowPlaying()
                saveState()
            }
        case .ended:
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsRaw)
            if resumeAfterInterruption && options.contains(.shouldResume), let player {
                resumeAfterInterruption = false
                beginPlaying(player)
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable && isPlaying {
            // Наушники отключились — ставим на паузу, как системный плеер.
            pause()
        }
    }

    // MARK: - «Исполняется» и пульты

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let current else {
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: current.title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player?.currentTime ?? currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artist = current.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = current.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let image = library.artwork(for: current.id) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        center.nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            guard let self, self.queue.current != nil else { return .noActionableNowPlayingItem }
            if !self.isPlaying { self.togglePlayPause() }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.togglePlayPause()
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - Сохранение состояния

    private func saveState() {
        guard !DemoContent.isEnabled else { return }
        lastSaved = Date()
        if let data = try? JSONEncoder().encode(queue) {
            defaults.set(data, forKey: DefaultsKey.queue)
        }
        defaults.set(player?.currentTime ?? currentTime, forKey: DefaultsKey.time)
    }

    private func restoreState() {
        guard let data = defaults.data(forKey: DefaultsKey.queue),
              var saved = try? JSONDecoder().decode(PlayQueue.self, from: data) else { return }
        let missing = Set(saved.items.filter { library.song(id: $0) == nil })
        saved.remove(missing)
        guard saved.current != nil else { return }
        queue = saved
        loadCurrent(autoplay: false, startTime: defaults.double(forKey: DefaultsKey.time))
    }

    private func setUpDemo() {
        let ids = library.songs.map(\.id)
        guard !ids.isEmpty else { return }
        queue = PlayQueue(items: ids, startAt: 0, shuffled: false, repeatMode: .all)
        loadCurrent(autoplay: false)
        if let current {
            // Для скриншота показываем «реальную» длину песни, а не короткого демо-тона.
            duration = current.duration
            currentTime = current.duration * 0.38
        }
    }
}
