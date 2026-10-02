import SwiftUI

/// Мини-плеер внизу экрана для прослушивания на телефоне.
struct MiniPlayerBar: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PhonePlayer.self) private var player

    var body: some View {
        if let id = player.currentId, let song = library.song(id: id) {
            VStack(spacing: 0) {
                ProgressView(value: player.duration > 0 ? min(player.currentTime / player.duration, 1) : 0)
                    .progressViewStyle(.linear)
                HStack(spacing: 12) {
                    ArtworkThumbnail(image: library.artwork(for: id), size: 42)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.meta.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text("\(Format.duration(player.currentTime)) / \(Format.duration(player.duration))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        player.isPlaying ? player.pause() : player.resume()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(player.isPlaying ? "Пауза" : "Играть")
                    Button {
                        player.stop()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, height: 44)
                    }
                    .accessibilityLabel("Закрыть")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(.bar)
        }
    }
}
