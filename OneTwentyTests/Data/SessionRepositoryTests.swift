import Foundation
import SwiftData
import Testing
@testable import OneTwenty

@MainActor
struct SessionRepositoryTests {
    private let container: ModelContainer
    private let habits: SwiftDataHabitRepository
    private let repository: SwiftDataSessionRepository
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")
    private let habit = HabitSnapshot.fixture(title: "本を1ページ読む", order: 0)

    /// 2026/10/1 の 0:00 から、翌 10/2 の 0:00 の直前まで。
    private var october1: Range<Date> {
        TestCalendars.date(2026, 10, 1, in: calendar)..<TestCalendars.date(2026, 10, 2, in: calendar)
    }

    init() throws {
        container = try PersistentStore.makeContainer(inMemory: true)
        habits = SwiftDataHabitRepository(context: container.mainContext)
        repository = SwiftDataSessionRepository(context: container.mainContext)
        try habits.insert(habit)
    }

    private func time(_ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        TestCalendars.date(2026, 10, day, hour, minute, second, in: calendar)
    }

    @Test("追加した記録を同じ値で読み出せる")
    func insertAndRead() throws {
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))

        let inserted = try repository.insertIfAbsent(session, sameDayRange: october1)

        #expect(inserted)
        #expect(repository.allSessions() == [session])
    }

    @Test("同じ id の記録は 2 回目には追加されない")
    func sameIDIsNotInsertedTwice() throws {
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))

        let first = try repository.insertIfAbsent(session, sameDayRange: october1)
        let second = try repository.insertIfAbsent(session, sameDayRange: october1)

        #expect(first)
        #expect(!second)
        #expect(repository.allSessions().count == 1)
    }

    @Test("同じ習慣・同じ日の 2 件目は、id が違っても追加されない")
    func sameHabitAndDayIsNotInsertedTwice() throws {
        let morning = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))
        let evening = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 20))

        _ = try repository.insertIfAbsent(morning, sameDayRange: october1)
        let inserted = try repository.insertIfAbsent(evening, sameDayRange: october1)

        #expect(!inserted)
        #expect(repository.allSessions() == [morning])
    }

    @Test("その日の 0:00 ちょうどの記録は、同じ日の記録として扱う")
    func lowerBoundIsInclusive() throws {
        let atMidnight = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 0, 0, 0))
        let later = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 12))

        _ = try repository.insertIfAbsent(atMidnight, sameDayRange: october1)
        let inserted = try repository.insertIfAbsent(later, sameDayRange: october1)

        #expect(!inserted)
    }

    @Test("翌日の 0:00 ちょうどの記録は、同じ日の記録として扱わない")
    func upperBoundIsExclusive() throws {
        let nextMidnight = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(2, 0, 0, 0))
        let october2 = time(2)..<time(3)
        _ = try repository.insertIfAbsent(nextMidnight, sameDayRange: october2)
        let lastSecond = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 23, 59, 59))

        let inserted = try repository.insertIfAbsent(lastSecond, sameDayRange: october1)

        #expect(inserted)
        #expect(repository.allSessions().count == 2)
    }

    @Test("同じ習慣でも、日が変われば追加できる")
    func sameHabitOnAnotherDay() throws {
        let first = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 23, 59))
        let second = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(2, 0, 1))

        _ = try repository.insertIfAbsent(first, sameDayRange: october1)
        let inserted = try repository.insertIfAbsent(second, sameDayRange: time(2)..<time(3))

        #expect(inserted)
    }

    @Test("同じ日でも、別の習慣なら追加できる")
    func anotherHabitOnSameDay() throws {
        let other = HabitSnapshot.fixture(title: "靴を履く", order: 1)
        try habits.insert(other)
        let first = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))
        let second = SessionSnapshot.fixture(habitID: other.id, startedAt: time(1, 8))

        _ = try repository.insertIfAbsent(first, sameDayRange: october1)
        let inserted = try repository.insertIfAbsent(second, sameDayRange: october1)

        #expect(inserted)
        #expect(Set(repository.allSessions().map(\.habitID)) == [habit.id, other.id])
    }

    @Test("存在しない習慣の記録は失敗し、何も追加されない")
    func missingHabit() {
        let session = SessionSnapshot.fixture(habitID: UUID(), startedAt: time(1, 8))

        #expect(throws: RepositoryError.habitNotFound) {
            try repository.insertIfAbsent(session, sameDayRange: october1)
        }
        #expect(repository.allSessions().isEmpty)
    }

    @Test("範囲取得は開始を含み、終了を含まず、開始時刻の順で返る")
    func rangeBounds() throws {
        let other = HabitSnapshot.fixture(title: "靴を履く", order: 1)
        let third = HabitSnapshot.fixture(title: "水を飲む", order: 2)
        try habits.insert(other)
        try habits.insert(third)
        let justBefore = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1).addingTimeInterval(-1))
        let atStart = SessionSnapshot.fixture(habitID: other.id, startedAt: time(1, 0, 0, 0))
        let lastSecond = SessionSnapshot.fixture(habitID: third.id, startedAt: time(1, 23, 59, 59))
        let atEnd = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(2, 0, 0, 0))
        let september30 = time(1).addingTimeInterval(-86_400)..<time(1)
        _ = try repository.insertIfAbsent(lastSecond, sameDayRange: october1)
        _ = try repository.insertIfAbsent(atEnd, sameDayRange: time(2)..<time(3))
        _ = try repository.insertIfAbsent(justBefore, sameDayRange: september30)
        _ = try repository.insertIfAbsent(atStart, sameDayRange: october1)

        let result = repository.sessions(from: time(1), to: time(2))

        #expect(result == [atStart, lastSecond])
        #expect(repository.allSessions() == [justBefore, atStart, lastSecond, atEnd])
    }

    @Test("アーカイブした習慣の記録も残る")
    func sessionsOfArchivedHabitRemain() throws {
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))
        _ = try repository.insertIfAbsent(session, sameDayRange: october1)

        try habits.archive(id: habit.id, at: time(1, 9))

        #expect(repository.allSessions() == [session])
    }

    @Test("書き込みは保存まで行われ、別の読み取り口からも見える")
    func writesArePersisted() throws {
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: time(1, 8))
        _ = try repository.insertIfAbsent(session, sameDayRange: october1)

        let another = SwiftDataSessionRepository(context: ModelContext(container))

        #expect(another.allSessions() == [session])
    }
}
