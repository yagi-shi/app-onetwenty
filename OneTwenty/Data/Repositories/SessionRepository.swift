import Foundation
import os
import SwiftData

/// 完了記録の読み書き。追加だけを行い、更新と削除は用意しない。
protocol SessionRepository {
    /// 開始時刻が `from` 以上 `to` 未満の記録を、開始時刻の順で返す。
    func sessions(from: Date, to: Date) -> [SessionSnapshot]
    func allSessions() -> [SessionSnapshot]
    /// 同じ `id` の記録、または同じ習慣で開始時刻が `sameDayRange` に入る記録が既にあれば、追加せず `false` を返す。
    /// - Parameter sameDayRange: 記録が属する日の始まりから、翌日の始まりの直前まで。日付の計算は呼び出し側が行う。
    func insertIfAbsent(_ session: SessionSnapshot, sameDayRange: Range<Date>) throws -> Bool
}

final class SwiftDataSessionRepository: SessionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func sessions(from: Date, to: Date) -> [SessionSnapshot] {
        fetch(FetchDescriptor<Session>(
            predicate: #Predicate { $0.startedAt >= from && $0.startedAt < to },
            sortBy: [SortDescriptor(\.startedAt)]
        ))
    }

    func allSessions() -> [SessionSnapshot] {
        fetch(FetchDescriptor<Session>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    func insertIfAbsent(_ session: SessionSnapshot, sameDayRange: Range<Date>) throws -> Bool {
        let id = session.id
        let sameID = FetchDescriptor<Session>(predicate: #Predicate { $0.id == id })
        guard try context.fetchCount(sameID) == 0 else { return false }

        let habitID = session.habitID
        let lower = sameDayRange.lowerBound
        let upper = sameDayRange.upperBound
        let sameHabitAndDay = FetchDescriptor<Session>(predicate: #Predicate {
            $0.habit?.id == habitID && $0.startedAt >= lower && $0.startedAt < upper
        })
        guard try context.fetchCount(sameHabitAndDay) == 0 else { return false }

        let habitDescriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == habitID })
        guard let habit = try context.fetch(habitDescriptor).first else {
            throw RepositoryError.habitNotFound
        }

        context.insert(Session(
            id: session.id,
            startedAt: session.startedAt,
            completedAt: session.completedAt,
            habit: habit
        ))
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return true
    }

    private func fetch(_ descriptor: FetchDescriptor<Session>) -> [SessionSnapshot] {
        do {
            return try context.fetch(descriptor).compactMap { SessionSnapshot($0) }
        } catch {
            Log.data.error("完了記録の取得に失敗: \(error)")
            return []
        }
    }
}

private extension SessionSnapshot {
    init?(_ session: Session) {
        guard let habitID = session.habit?.id else { return nil }
        self.init(
            id: session.id,
            habitID: habitID,
            startedAt: session.startedAt,
            completedAt: session.completedAt
        )
    }
}
