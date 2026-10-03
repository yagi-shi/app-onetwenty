import Foundation
@testable import OneTwenty

/// 保存の失敗を再現するための包み。失敗させない間は、中の本物にそのまま渡す。
@MainActor
final class FailingSessionRepository: SessionRepository {
    struct Failure: Error {}

    var failsInsert = false
    private(set) var insertAttempts = 0
    private let wrapped: SessionRepository

    init(wrapping wrapped: SessionRepository) {
        self.wrapped = wrapped
    }

    func sessions(from: Date, to: Date) -> [SessionSnapshot] {
        wrapped.sessions(from: from, to: to)
    }

    func allSessions() -> [SessionSnapshot] {
        wrapped.allSessions()
    }

    func insertIfAbsent(_ session: SessionSnapshot, sameDayRange: Range<Date>) throws -> Bool {
        insertAttempts += 1
        if failsInsert { throw Failure() }
        return try wrapped.insertIfAbsent(session, sameDayRange: sameDayRange)
    }
}

@MainActor
final class FailingHabitRepository: HabitRepository {
    struct Failure: Error {}

    var failsWrites = false
    /// 並び順の書き換えだけを失敗させる。
    var failsOrderUpdates = false
    private let wrapped: HabitRepository

    init(wrapping wrapped: HabitRepository) {
        self.wrapped = wrapped
    }

    func activeHabits() -> [HabitSnapshot] { wrapped.activeHabits() }
    func allHabits() -> [HabitSnapshot] { wrapped.allHabits() }
    func habit(id: UUID) -> HabitSnapshot? { wrapped.habit(id: id) }

    func insert(_ habit: HabitSnapshot) throws {
        try failIfNeeded()
        try wrapped.insert(habit)
    }

    func updateTitle(id: UUID, title: String) throws {
        try failIfNeeded()
        try wrapped.updateTitle(id: id, title: title)
    }

    func updateOrders(_ orders: [UUID: Int]) throws {
        try failIfNeeded()
        if failsOrderUpdates { throw Failure() }
        try wrapped.updateOrders(orders)
    }

    func archive(id: UUID, at date: Date) throws {
        try failIfNeeded()
        try wrapped.archive(id: id, at: date)
    }

    private func failIfNeeded() throws {
        if failsWrites { throw Failure() }
    }
}
