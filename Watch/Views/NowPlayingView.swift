import SwiftUI

/// Экран «Исполняется» на часах. Колёсико Digital Crown меняет громкость.
struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(WatchLibrary.self) private var library
    @State private var crownVolume: Double = 0.8

    var body: some View {
        Group {
            if let song = player.current {
                content(for: song)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Ничего не играет")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .background {
            if let song = player.current, let image = library.artwork(for: song.id) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 18)
                    .opacity(0.45)
                    .ignoresSafeArea()
            }
        }
        .focusable()
        .digitalCrownRotation($crownVolume, from: 0, through: 1, by: 0.02, sensitivity: .low,
                              isContinuous: false, isHapticFeedbackEnabled: true)
        .onAppear {
            crownVolume = player.volume
        }
        .onChange(of: crownVolume) { _, value in
            player.setVolume(value)
        }
        .alert("Воспроизведение", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func content(for song: SongMeta) -> some View {
        VStack(spacing: 4) {
            VStack(spacing: 0) {
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 2) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.3))
                        Capsule().fill(Color.accentColor)
                            .frame(width: proxy.size.width * progress)
                    }
                }
                .frame(height: 4)
                .accessibilityElement()
                .accessibilityLabel("Прогресс")
                .accessibilityValue("\(Int(progress * 100))%")
                HStack {
                    Text(Format.duration(player.currentTime))
                    Spacer()
                    Text("-" + Format.duration(max(0, player.duration - player.currentTime)))
                }
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            }

            HStack {
                ControlButton(systemImage: "backward.fill", size: 18, label: "Назад") {
                    player.previous()
                }
                Spacer()
                Button {
                    player.togglePlayPause()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor)
                        if player.isStarting {
                            ProgressView()
                        } else {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")
                Spacer()
                ControlButton(systemImage: "forward.fill", size: 18, label: "Вперёд") {
                    player.next()
                }
            }

            HStack {
                ControlButton(systemImage: "shuffle", size: 13, label: "Перемешать",
                              isActive: player.queue.isShuffled) {
                    player.toggleShuffle()
                }
                Spacer()
                VolumeIndicator(volume: player.volume)
                Spacer()
                ControlButton(systemImage: player.queue.repeatMode == .one ? "repeat.1" : "repeat", size: 13,
                              label: "Повтор", isActive: player.queue.repeatMode != .off) {
                    player.cycleRepeat()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(max(player.currentTime / player.duration, 0), 1)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { player.errorMessage != nil },
            set: { if !$0 { player.errorMessage = nil } }
        )
    }
}

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let label: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: size * 2 + 4, height: size * 2 + 4)
                .background {
                    if isActive {
                        Circle().fill(Color.accentColor.opacity(0.2))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct VolumeIndicator: View {
    let volume: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: volume == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 10))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.3))
                    Capsule().fill(Color.primary)
                        .frame(width: proxy.size.width * volume)
                }
            }
            .frame(width: 40, height: 4)
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Громкость \(Int(volume * 100))%. Крутите колёсико.")
    }
}
