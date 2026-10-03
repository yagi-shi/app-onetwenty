import Foundation
import os
import SwiftData

enum RepositoryError: Error, Equatable {
    case habitNotFound
}

/// 習慣の読み書き。物理削除と、アーカイブを取り消す操作は用意しない。
protocol HabitRepository {
    /// アーカイブしていない習慣を、並び順で返す。
    func activeHabits() -> [HabitSnapshot]
    /// アーカイブ済みを含むすべての習慣を、登録順で返す。
    func allHabits() -> [HabitSnapshot]
    func habit(id: UUID) -> HabitSnapshot?
    func insert(_ habit: HabitSnapshot) throws
    func updateTitle(id: UUID, title: String) throws
    func updateOrders(_ orders: [UUID: Int]) throws
    /// 残った習慣の並び順も、同じ保存の中で 0 から詰め直す。
    /// 既にアーカイブ済みなら何もしない（アーカイブした時刻は書き換えない）。
    func archive(id: UUID, at date: Date) throws
}

final class SwiftDataHabitRepository: HabitRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func activeHabits() -> [HabitSnapshot] {
        fetch(FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.order)]
        ))
    }

    func allHabits() -> [HabitSnapshot] {
        fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
    }

    func habit(id: UUID) -> HabitSnapshot? {
        fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first
    }

    func insert(_ habit: HabitSnapshot) throws {
        context.insert(Habit(
            id: habit.id,
            title: habit.title,
            originalIntent: habit.originalIntent,
            createdAt: habit.createdAt,
            order: habit.order,
            archivedAt: habit.archivedAt
        ))
        try save()
    }

    func updateTitle(id: UUID, title: String) throws {
        let habit = try model(id: id)
        habit.title = title
        try save()
    }

    func updateOrders(_ orders: [UUID: Int]) throws {
        do {
            for (id, order) in orders {
                try model(id: id).order = order
            }
        } catch {
            context.rollback()
            throw error
        }
        try save()
    }

    func archive(id: UUID, at date: Date) throws {
        let habit = try model(id: id)
        guard habit.archivedAt == nil else { return }
        let remaining = try context.fetch(FetchDescriptor<Habit>(
            predicate: #Predicate { $0.archivedAt == nil },
            sortBy: [SortDescriptor(\.order)]
        )).filter { $0.id != id }

        // 並び順の詰め直しを別の保存にすると、そちらだけ失敗したときに
        // 「アーカイブはされたのに、失敗と表示される」状態になる
        habit.archivedAt = date
        habit.order = -1
        for (order, other) in remaining.enumerated() {
            other.order = order
        }
        try save()
    }

    private func model(id: UUID) throws -> Habit {
        let descriptor = FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })
        guard let habit = try context.fetch(descriptor).first else {
            throw RepositoryError.habitNotFound
        }
        return habit
    }

    private func fetch(_ descriptor: FetchDescriptor<Habit>) -> [HabitSnapshot] {
        do {
            return try context.fetch(descriptor).map { HabitSnapshot($0) }
        } catch {
            Log.data.error("習慣の取得に失敗: \(error)")
            return []
        }
    }

    /// 保存に失敗したら、メモリ上の変更も取り消してから失敗を伝える。
    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}

private extension HabitSnapshot {
    init(_ habit: Habit) {
        self.init(
            id: habit.id,
            title: habit.title,
            originalIntent: habit.originalIntent,
            createdAt: habit.createdAt,
            order: habit.order,
            archivedAt: habit.archivedAt
        )
    }
}
