import SwiftUI

/// Карточка состояния часов в начале библиотеки.
struct WatchStatusCard: View {
    @Environment(PhoneSyncManager.self) private var sync

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 40)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = sync.overallProgress {
                    ProgressView(value: progress) {
                        Text("Передаётся: \(Format.songs(sync.progress.count))")
                            .font(.caption)
                    }
                    .padding(.top, 2)
                }
                if sync.isWatchAppInstalled, let free = sync.watchFreeBytes {
                    Text("На часах: \(Format.bytes(sync.watchUsedBytes)) музыки, свободно \(Format.bytes(free))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if sync.isPaired && sync.isWatchAppInstalled {
                Button {
                    sync.forceSync()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 17, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Синхронизировать")
            }
        }
        .padding(.vertical, 6)
    }

    private enum CardState {
        case unsupported, connecting, notPaired, appNotInstalled, nothingSelected, synced, syncing
    }

    private var state: CardState {
        if !sync.isSupported { return .unsupported }
        if !sync.isActivated { return .connecting }
        if !sync.isPaired { return .notPaired }
        if !sync.isWatchAppInstalled { return .appNotInstalled }
        if sync.desiredCount == 0 { return .nothingSelected }
        if sync.syncedCount >= sync.desiredCount { return .synced }
        return .syncing
    }

    private var icon: String {
        switch state {
        case .unsupported, .notPaired: "applewatch.slash"
        case .connecting: "applewatch.radiowaves.left.and.right"
        case .appNotInstalled: "arrow.down.app"
        case .nothingSelected: "applewatch"
        case .synced: "checkmark.circle.fill"
        case .syncing: "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch state {
        case .unsupported, .notPaired: .secondary
        case .appNotInstalled: .orange
        case .synced: .green
        default: .accentColor
        }
    }

    private var title: String {
        switch state {
        case .unsupported: "Apple Watch недоступны"
        case .connecting: "Подключение к часам…"
        case .notPaired: "Apple Watch не подключены"
        case .appNotInstalled: "Установите WristPlayer на часы"
        case .nothingSelected: "Часы подключены"
        case .synced: "Всё на часах"
        case .syncing: "На часах \(sync.syncedCount) из \(sync.desiredCount)"
        }
    }

    private var detail: String {
        switch state {
        case .unsupported:
            "Это устройство не поддерживает Apple Watch."
        case .connecting:
            "Ждём ответа от часов."
        case .notPaired:
            "Создайте пару с часами в приложении Watch."
        case .appNotInstalled:
            "Приложение Watch → Мои часы → WristPlayer → «Установить»."
        case .nothingSelected:
            "Нажмите значок часов у песни, чтобы отправить её на часы."
        case .synced:
            "\(Format.songs(sync.desiredCount)) можно слушать на часах без телефона и интернета."
        case .syncing:
            "Песни передаются в фоне. Быстрее всего — когда часы на зарядке рядом с телефоном."
        }
    }
}
