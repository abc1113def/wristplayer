import SwiftUI

struct SongRow: View {
    let song: Song
    @Environment(LibraryStore.self) private var library
    @Environment(PhoneSyncManager.self) private var sync
    @Environment(PhonePlayer.self) private var player

    var body: some View {
        let status = sync.status(for: song)
        let isCurrent = player.currentId == song.id
        HStack(spacing: 12) {
            ArtworkThumbnail(image: library.artwork(for: song.id), size: 50,
                             overlay: isCurrent ? (player.isPlaying ? "speaker.wave.2.fill" : "pause.fill") : nil)
            VStack(alignment: .leading, spacing: 3) {
                Text(song.meta.title)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                SyncStatusLine(status: status)
            }
            Spacer(minLength: 8)
            WatchToggleButton(status: status) {
                library.toggleOnWatch(song.id)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            player.toggle(song, library: library)
        }
        .swipeActions(edge: .leading) {
            Button {
                library.toggleOnWatch(song.id)
            } label: {
                Label(song.onWatch ? "Убрать с часов" : "На часы",
                      systemImage: song.onWatch ? "applewatch.slash" : "applewatch")
            }
            .tint(song.onWatch ? Color.gray : Color.accentColor)
        }
    }

    /// «Исполнитель · 3:45» — длительность не обрезается длинным названием альбома.
    private var subtitle: String {
        let parts = [song.meta.artist ?? "", Format.duration(song.meta.duration)].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}

struct SyncStatusLine: View {
    let status: SongSyncStatus

    var body: some View {
        switch status {
        case .off:
            EmptyView()
        case .onWatch:
            StatusText(icon: "checkmark.circle.fill", text: "На часах", color: .green)
        case .waiting:
            StatusText(icon: "clock", text: "Ожидает отправки", color: .secondary)
        case .preparing:
            StatusText(icon: "waveform", text: "Подготовка…", color: .secondary)
        case .transferring(let value):
            HStack(spacing: 6) {
                ProgressView(value: value)
                    .frame(maxWidth: 90)
                Text("\(Int(value * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        case .failed(let message):
            StatusText(icon: "exclamationmark.triangle.fill", text: message, color: .red)
        }
    }
}

private struct StatusText: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: icon)
            Text(text)
                .lineLimit(2)
        }
        .font(.caption)
        .foregroundStyle(color)
    }
}

/// Кнопка-тумблер «на часах».
struct WatchToggleButton: View {
    let status: SongSyncStatus
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if case .transferring(let value) = status {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: max(0.03, value))
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: status == .off ? "applewatch.slash" : "applewatch")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(status == .off ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.tint))
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(status == .off ? "Отправить на часы" : "Убрать с часов")
    }
}

struct ArtworkThumbnail: View {
    let image: UIImage?
    var size: CGFloat = 50
    var overlay: String?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(colors: [Color(red: 1, green: 0.37, blue: 0.38), Color(red: 0.49, green: 0.23, blue: 0.93)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            if let overlay {
                Color.black.opacity(0.35)
                Image(systemName: overlay)
                    .font(.system(size: size * 0.36, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}
