import Foundation

enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off, all, one

    var next: RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }
}

/// Очередь воспроизведения: исходный порядок, порядок проигрывания (с учётом перемешивания) и позиция.
struct PlayQueue: Codable, Equatable, Sendable {
    /// Песни в исходном порядке.
    private(set) var items: [String]
    /// Порядок проигрывания.
    private(set) var order: [String]
    /// Индекс текущей песни в `order`.
    private(set) var position: Int
    private(set) var isShuffled: Bool
    var repeatMode: RepeatMode

    init(items: [String], startAt index: Int = 0, shuffled: Bool = false, repeatMode: RepeatMode = .off) {
        var unique: [String] = []
        var seen = Set<String>()
        for id in items where !seen.contains(id) {
            seen.insert(id)
            unique.append(id)
        }
        self.items = unique
        self.order = unique
        self.position = unique.isEmpty ? 0 : min(max(index, 0), unique.count - 1)
        self.isShuffled = false
        self.repeatMode = repeatMode
        if shuffled { setShuffle(true) }
    }

    var isEmpty: Bool { order.isEmpty }
    var count: Int { order.count }
    var current: String? { order.indices.contains(position) ? order[position] : nil }

    /// Что будет играть дальше (без учёта повтора).
    var upNext: [String] {
        guard order.indices.contains(position) else { return [] }
        return Array(order[(position + 1)...])
    }

    /// Включает/выключает перемешивание. Текущая песня остаётся текущей.
    mutating func setShuffle<G: RandomNumberGenerator>(_ on: Bool, using generator: inout G) {
        guard let current else {
            isShuffled = on
            return
        }
        if on {
            var rest = items.filter { $0 != current }
            rest.shuffle(using: &generator)
            order = [current] + rest
            position = 0
        } else {
            order = items
            position = items.firstIndex(of: current) ?? 0
        }
        isShuffled = on
    }

    mutating func setShuffle(_ on: Bool) {
        var generator = SystemRandomNumberGenerator()
        setShuffle(on, using: &generator)
    }

    /// Переход вперёд. `auto == true` — песня доиграла сама (тогда «повтор одной» повторяет её).
    /// Возвращает новую текущую песню или `nil`, если очередь закончилась.
    @discardableResult
    mutating func advance(auto: Bool) -> String? {
        guard !order.isEmpty else { return nil }
        if auto && repeatMode == .one { return current }
        if position + 1 < order.count {
            position += 1
            return current
        }
        if repeatMode != .off {
            position = 0
            return current
        }
        return nil
    }

    /// Переход назад. В начале очереди без повтора остаётся на первой песне.
    @discardableResult
    mutating func goBack() -> String? {
        guard !order.isEmpty else { return nil }
        if position > 0 {
            position -= 1
        } else if repeatMode != .off {
            position = order.count - 1
        }
        return current
    }

    /// Перейти к конкретной песне очереди.
    mutating func jump(to id: String) -> Bool {
        guard let index = order.firstIndex(of: id) else { return false }
        position = index
        return true
    }

    /// Убирает песни (например, удалённые с часов). Возвращает `true`, если сменилась текущая песня.
    @discardableResult
    mutating func remove(_ ids: Set<String>) -> Bool {
        guard !ids.isEmpty else { return false }
        let oldCurrent = current
        let removedBefore = order[..<min(position, order.count)].filter { ids.contains($0) }.count
        items.removeAll { ids.contains($0) }
        order.removeAll { ids.contains($0) }
        position -= removedBefore
        if order.isEmpty {
            position = 0
        } else if position >= order.count {
            position = repeatMode == .off ? order.count - 1 : 0
        }
        return current != oldCurrent
    }
}
