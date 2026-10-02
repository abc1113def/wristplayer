import SwiftUI

enum WatchRoute: Hashable {
    case nowPlaying
    case settings
}

/// Главный экран часов: список песен.
struct RootView: View {
    @Environment(WatchLibrary.self) private var library
    @Environment(AudioPlayer.self) private var player
    @Environment(WatchSyncManager.self) private var sync
    @State private var path: [WatchRoute] = RootView.initialPath

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let current = player.current {
                    NavigationLink(value: WatchRoute.nowPlaying) {
                        NowPlayingRow(song: current, isPlaying: player.isPlaying)
                    }
                }

                if library.songs.isEmpty {
                    EmptyWatchLibraryView(pendingCount: library.pendingCount)
                        .listRowBackground(Color.clear)
                } else {
                    Button {
                        player.play(ids: library.songs.map(\.id), shuffle: true)
                        path.append(.nowPlaying)
                    } label: {
                        Label("Перемешать всё", systemImage: "shuffle")
                    }

                    Section {
                        ForEach(Array(library.songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                player.play(ids: library.songs.map(\.id), startAt: index)
                                path.append(.nowPlaying)
                            } label: {
                                WatchSongRow(song: song, artwork: library.artwork(for: song.id),
                                             isCurrent: player.current?.id == song.id)
                            }
                        }
                        .onDelete { offsets in
                            let ids = Set(offsets.map { library.songs[$0].id })
                            library.delete(ids: ids)
                            sync.reportRemovedOnWatch(ids)
                        }
                    } header: {
                        Text(Format.songs(library.songs.count))
                    }

                    if library.pendingCount > 0 {
                        Label("Загружается ещё \(Format.songs(library.pendingCount))", systemImage: "arrow.down.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    }
                }

                NavigationLink(value: WatchRoute.settings) {
                    Label("Настройки", systemImage: "gearshape")
                }
            }
            .navigationTitle("Музыка")
            .navigationDestination(for: WatchRoute.self) { route in
                switch route {
                case .nowPlaying: NowPlayingView()
                case .settings: SettingsView()
                }
            }
        }
    }

    private static var initialPath: [WatchRoute] {
        switch DemoContent.argument("-demoScreen") {
        case "nowPlaying": [.nowPlaying]
        case "settings": [.settings]
        default: []
        }
    }
}

private struct NowPlayingRow: View {
    let song: SongMeta
    let isPlaying: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                .foregroundStyle(.tint)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            VStack(alignment: .leading, spacing: 1) {
                Text("Исполняется")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(song.title)
                    .font(.headline)
                    .lineLimit(1)
            }
        }
    }
}

struct WatchSongRow: View {
    let song: SongMeta
    let artwork: UIImage?
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 8) {
            WatchArtwork(image: artwork, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(song.title)
                    .font(.body)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                if let artist = song.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct WatchArtwork: View {
    let image: UIImage?
    var size: CGFloat

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
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}

private struct EmptyWatchLibraryView: View {
    let pendingCount: Int

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: pendingCount > 0 ? "arrow.down.circle" : "iphone.and.arrow.forward")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            if pendingCount > 0 {
                Text("Загружается \(Format.songs(pendingCount))")
                    .font(.headline)
                Text("Держите часы рядом с iPhone. На зарядке — быстрее.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Пока нет песен")
                    .font(.headline)
                Text("Добавьте музыку в WristPlayer на iPhone — она появится здесь.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}
