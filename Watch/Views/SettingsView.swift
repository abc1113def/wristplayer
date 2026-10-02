import SwiftUI

struct SettingsView: View {
    @Environment(AudioPlayer.self) private var player
    @Environment(WatchLibrary.self) private var library
    @Environment(WatchSyncManager.self) private var sync
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                Picker("Звук", selection: outputBinding) {
                    ForEach(OutputMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
            } footer: {
                Text(player.outputMode.details)
            }

            Section("Хранилище") {
                LabeledContent("Песни", value: "\(library.songs.count)")
                LabeledContent("Занято", value: Format.bytes(library.usedBytes))
                if let free = library.freeBytes {
                    LabeledContent("Свободно", value: Format.bytes(free))
                }
            }

            Section("iPhone") {
                LabeledContent("Связь", value: sync.isReachable ? "рядом" : "не на связи")
                if let date = sync.lastReceivedAt {
                    LabeledContent("Последняя песня") {
                        Text(date, style: .relative)
                    }
                }
            }

            if !library.songs.isEmpty {
                Section {
                    Button("Удалить все песни", role: .destructive) {
                        confirmDeleteAll = true
                    }
                } footer: {
                    Text("Песни останутся на iPhone, но перестанут отправляться на часы.")
                }
            }
        }
        .navigationTitle("Настройки")
        .confirmationDialog("Удалить все песни с часов?", isPresented: $confirmDeleteAll) {
            Button("Удалить", role: .destructive) {
                let ids = Set(library.songs.map(\.id))
                library.delete(ids: ids)
                sync.reportRemovedOnWatch(ids)
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private var outputBinding: Binding<OutputMode> {
        Binding(
            get: { player.outputMode },
            set: { player.setOutputMode($0) }
        )
    }
}
