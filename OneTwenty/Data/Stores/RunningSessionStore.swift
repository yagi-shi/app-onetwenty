import Foundation
import os

/// 保存待ち（2 分を走り切ったが、完了記録の保存に失敗した実行）の読み取りだけを行う口。
protocol PendingCompletionsReading {
    func pendingCompletions() -> [RunningSessionMarker]
}

protocol RunningSessionStore: PendingCompletionsReading {
    /// 実行中のタイマーの印。実行中でなければ `nil`。
    func load() -> RunningSessionMarker?
    func save(_ marker: RunningSessionMarker)
    func clear()

    func addPending(_ marker: RunningSessionMarker)
    func removePending(sessionID: UUID)
}

final class UserDefaultsRunningSessionStore: RunningSessionStore {
    private enum Key {
        static let running = "onetwenty.running.session"
        static let pending = "onetwenty.pending.completions"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> RunningSessionMarker? {
        decode(RunningSessionMarker.self, forKey: Key.running)
    }

    func save(_ marker: RunningSessionMarker) {
        encode(marker, forKey: Key.running)
    }

    func clear() {
        defaults.removeObject(forKey: Key.running)
    }

    func pendingCompletions() -> [RunningSessionMarker] {
        decode([RunningSessionMarker].self, forKey: Key.pending) ?? []
    }

    func addPending(_ marker: RunningSessionMarker) {
        var pending = pendingCompletions()
        guard !pending.contains(where: { $0.sessionID == marker.sessionID }) else { return }
        pending.append(marker)
        encode(pending, forKey: Key.pending)
    }

    func removePending(sessionID: UUID) {
        let remaining = pendingCompletions().filter { $0.sessionID != sessionID }
        if remaining.isEmpty {
            defaults.removeObject(forKey: Key.pending)
        } else {
            encode(remaining, forKey: Key.pending)
        }
    }

    /// 保存値が壊れていて読めない場合は、値がないものとして扱い、壊れた値を消す。
    private func decode<Value: Decodable>(_ type: Value.Type, forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            if defaults.object(forKey: key) != nil {
                defaults.removeObject(forKey: key)
            }
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Log.data.error("\(key) の保存値を読めないため破棄: \(error)")
            defaults.removeObject(forKey: key)
            return nil
        }
    }

    private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            Log.data.error("\(key) を保存できない: \(error)")
        }
    }
}
