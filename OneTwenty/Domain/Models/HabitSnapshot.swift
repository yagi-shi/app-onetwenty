import Foundation

/// 保存されている習慣の、ある時点の値。ドメイン層と ViewModel はこの型だけを扱う。
nonisolated struct HabitSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    /// 登録時に入力した文。名前を変更しても書き換えない。
    let originalIntent: String
    let createdAt: Date
    /// アクティブな習慣の中での並び順（0 から）。アーカイブ済みは -1。
    let order: Int
    /// アーカイブした時刻。アクティブなら `nil`。
    let archivedAt: Date?
}
