import Foundation

/// 完了した 2 分間の記録。中断した実行は記録として存在しない。
nonisolated struct SessionSnapshot: Identifiable, Hashable, Sendable {
    let id: UUID
    let habitID: UUID
    let startedAt: Date
    let completedAt: Date
}
