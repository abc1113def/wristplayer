import SwiftUI

/// Как добавить музыку и как слушать её на часах.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Добавить музыку на телефон") {
                    HelpItem(icon: "plus.circle.fill", title: "Кнопка «+»",
                             text: "Выберите один или несколько файлов в приложении «Файлы» (iCloud Drive, «На iPhone», Загрузки).")
                    HelpItem(icon: "square.and.arrow.up.fill", title: "«Поделиться» из другого приложения",
                             text: "В Telegram, почте, браузере: откройте аудиофайл → «Поделиться» → WristPlayer.")
                    HelpItem(icon: "folder.fill", title: "Папка WristPlayer",
                             text: "Положите файлы в «Файлы» → «На iPhone» → WristPlayer. Они добавятся при следующем открытии приложения.")
                    HelpItem(icon: "desktopcomputer", title: "С компьютера (Windows)",
                             text: "Подключите iPhone кабелем, откройте Apple Devices (или iTunes) → Файлы → WristPlayer и перетащите туда музыку.")
                }
                Section("Отправить на часы") {
                    HelpItem(icon: "applewatch", title: "Значок часов у песни",
                             text: "Новые песни сразу отмечены для часов. Нажмите значок, чтобы убрать песню с часов или вернуть её.")
                    HelpItem(icon: "bolt.fill", title: "Передача идёт в фоне",
                             text: "Можно закрыть приложение. Быстрее всего — когда часы на зарядке рядом с телефоном.")
                    HelpItem(icon: "waveform", title: "Форматы",
                             text: "MP3 и M4A передаются как есть. WAV, AIFF и FLAC перед отправкой сжимаются в AAC, чтобы занимать меньше места.")
                }
                Section("Слушать на часах") {
                    HelpItem(icon: "airpods", title: "Нужны Bluetooth-наушники",
                             text: "watchOS разрешает фоновую музыку только через Bluetooth-наушники или колонку. Подключите их к часам, откройте WristPlayer и выберите песню.")
                    HelpItem(icon: "wifi.slash", title: "Без интернета и телефона",
                             text: "Песни хранятся на самих часах — телефон и интернет не нужны.")
                }
            }
            .navigationTitle("Справка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

private struct HelpItem: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
