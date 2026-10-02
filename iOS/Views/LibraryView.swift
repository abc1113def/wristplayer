import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PhoneSyncManager.self) private var sync
    @Environment(PhonePlayer.self) private var player
    @AppStorage("sortOrder") private var sortOrder: LibrarySort = .dateAdded
    @State private var showImporter = false
    @State private var showHelp = false
    @State private var searchText = ""

    private var visibleSongs: [Song] {
        let sorted = library.sorted(by: sortOrder)
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return sorted }
        return sorted.filter { song in
            [song.meta.title, song.meta.artist ?? "", song.meta.album ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    WatchStatusCard()
                }
                if library.songs.isEmpty {
                    Section {
                        EmptyLibraryView(onImport: { showImporter = true }, onHelp: { showHelp = true })
                    }
                } else {
                    Section {
                        ForEach(visibleSongs) { song in
                            SongRow(song: song)
                        }
                        .onDelete { offsets in
                            delete(offsets.map { visibleSongs[$0].id })
                        }
                    } header: {
                        Text("\(Format.songs(library.songs.count)) · \(Format.bytes(library.totalBytes))")
                    }
                }
            }
            .navigationTitle("WristPlayer")
            .searchable(text: $searchText, prompt: "Название, исполнитель, альбом")
            .refreshable {
                library.importFromDocumentsFolder()
                sync.forceSync()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Добавить песни")
                }
                ToolbarItem(placement: .topBarLeading) {
                    menu
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio],
                          allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls): library.importFiles(urls)
                case .failure(let error): library.notice = error.localizedDescription
                }
            }
            .sheet(isPresented: $showHelp) {
                HelpView()
            }
            .safeAreaInset(edge: .bottom) {
                if player.currentId != nil {
                    MiniPlayerBar()
                }
            }
            .overlay(alignment: .bottom) {
                if library.importingCount > 0 {
                    ImportingBanner(count: library.importingCount)
                        .padding(.bottom, player.currentId != nil ? 90 : 24)
                }
            }
            .alert("WristPlayer", isPresented: noticeBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.notice ?? player.errorMessage ?? "")
            }
        }
    }

    private var menu: some View {
        Menu {
            Picker("Сортировка", selection: $sortOrder) {
                ForEach(LibrarySort.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            Divider()
            Button {
                library.setOnWatch(true, ids: library.songs.map(\.id))
            } label: {
                Label("Отправить всё на часы", systemImage: "applewatch")
            }
            Button {
                library.setOnWatch(false, ids: library.songs.map(\.id))
            } label: {
                Label("Убрать всё с часов", systemImage: "applewatch.slash")
            }
            Divider()
            Button {
                showHelp = true
            } label: {
                Label("Как добавить музыку", systemImage: "questionmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Меню")
    }

    private var noticeBinding: Binding<Bool> {
        Binding(
            get: { library.notice != nil || player.errorMessage != nil },
            set: { shown in
                if !shown {
                    library.notice = nil
                    player.errorMessage = nil
                }
            }
        )
    }

    private func delete(_ ids: [String]) {
        if let current = player.currentId, ids.contains(current) {
            player.stop()
        }
        library.delete(ids: Set(ids))
    }
}

private struct ImportingBanner: View {
    let count: Int

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Добавляю: \(Format.songs(count))")
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
    }
}

struct EmptyLibraryView: View {
    var onImport: () -> Void
    var onHelp: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Библиотека пуста")
                .font(.title3.weight(.semibold))
            Text("Добавьте аудиофайлы (MP3, M4A, WAV, FLAC…) — они попадут на часы и будут играть без интернета.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: onImport) {
                Label("Добавить песни", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            Button("Другие способы добавить музыку", action: onHelp)
                .font(.footnote)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
}
