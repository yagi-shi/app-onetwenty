import Foundation
@testable import OneTwenty

extension HabitSnapshot {
    /// テスト用の習慣。関心のある値だけを指定する。
    static func fixture(
        id: UUID = UUID(),
        title: String = "本を1ページ読む",
        originalIntent: String = "読書を続ける",
        createdAt: Date = Date(timeIntervalSince1970: 0),
        order: Int = 0,
        archivedAt: Date? = nil
    ) -> HabitSnapshot {
        HabitSnapshot(
            id: id,
            title: title,
            originalIntent: originalIntent,
            createdAt: createdAt,
            order: order,
            archivedAt: archivedAt
        )
    }
}

extension SessionSnapshot {
    /// テスト用の完了記録。完了時刻は開始の 120 秒後。
    static func fixture(id: UUID = UUID(), habitID: UUID, startedAt: Date) -> SessionSnapshot {
        SessionSnapshot(
            id: id,
            habitID: habitID,
            startedAt: startedAt,
            completedAt: startedAt.addingTimeInterval(120)
        )
    }
}
