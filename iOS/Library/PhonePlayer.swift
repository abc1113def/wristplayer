import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Простой плеер на телефоне — чтобы прослушать песню из библиотеки.
@Observable
final class PhonePlayer: NSObject, AVAudioPlayerDelegate {
    static let shared = PhonePlayer()

    private(set) var currentId: String?
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var nowPlayingTitle = ""
    @ObservationIgnored private var nowPlayingArtist: String?
    @ObservationIgnored private var commandsConfigured = false

    func toggle(_ song: Song, library: LibraryStore) {
        if currentId == song.id {
            isPlaying ? pause() : resume()
        } else {
            play(song, library: library)
        }
    }

    func play(_ song: Song, library: LibraryStore) {
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: library.fileURL(for: song))
            player.delegate = self
            player.prepareToPlay()
            player.play()
            self.player = player
            currentId = song.id
            duration = player.duration
            currentTime = 0
            isPlaying = true
            nowPlayingTitle = song.meta.title
            nowPlayingArtist = song.meta.artist
            configureRemoteCommands()
            startTimer()
            updateNowPlaying()
        } catch {
            errorMessage = "Не удалось воспроизвести «\(song.meta.title)»: \(error.localizedDescription)"
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard let player else { return }
        player.play()
        isPlaying = true
        startTimer()
        updateNowPlaying()
    }

    func seek(to time: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(time, player.duration))
        currentTime = player.currentTime
        updateNowPlaying()
    }

    func stop() {
        player?.stop()
        player = nil
        currentId = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        timer?.invalidate()
        timer = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
    }

    private func updateNowPlaying() {
        guard let player else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyPlaybackDuration: player.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let nowPlayingArtist { info[MPMediaItemPropertyArtist] = nowPlayingArtist }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            self?.resume()
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.isPlaying ? self.pause() : self.resume()
            return .success
        }
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.stop()
        }
    }
}
