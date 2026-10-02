import Foundation
import Testing
@testable import OneTwenty

struct DailyStatusResolverTests {
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")
    private let habits = (0..<3).map { HabitSnapshot.fixture(title: "習慣\($0)", order: $0) }

    private func time(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        TestCalendars.date(2026, 10, day, hour, minute, in: calendar)
    }

    private func status(
        habits: [HabitSnapshot]? = nil,
        sessions: [SessionSnapshot] = [],
        pending: [RunningSessionMarker] = [],
        day: Int
    ) -> DailyStatus {
        DailyStatusResolver.status(
            activeHabits: habits ?? self.habits,
            sessions: sessions,
            pending: pending,
            day: DayKey(time(day), calendar: calendar),
            calendar: calendar
        )
    }

    @Test("23:59 に始めた記録は、完了が翌日でも始めた日の完了になる")
    func attributesToStartDay() {
        // 23:59 開始 → 0:01 完了
        let session = SessionSnapshot.fixture(habitID: habits[0].id, startedAt: time(1, 23, 59))

        #expect(status(sessions: [session], day: 1).completedHabitIDs == [habits[0].id])
        #expect(status(sessions: [session], day: 2).completedHabitIDs.isEmpty)
    }

    @Test("日が変わると、前日に完了した習慣は未完了に戻る")
    func resetsOnNextDay() {
        let sessions = habits.map { SessionSnapshot.fixture(habitID: $0.id, startedAt: time(1)) }

        #expect(status(sessions: sessions, day: 1).allCompleted)
        #expect(status(sessions: sessions, day: 2) == DailyStatus(completedHabitIDs: [], activeCount: 3, allCompleted: false))
    }

    @Test("習慣が 0 件なら、全完了にはならない")
    func noHabitsIsNotAllCompleted() {
        #expect(status(habits: [], day: 1) == DailyStatus(completedHabitIDs: [], activeCount: 0, allCompleted: false))
    }

    @Test("3 件中 3 件完了で全完了、2 件では全完了にならない")
    func allCompletedRequiresEveryHabit() {
        let all = habits.map { SessionSnapshot.fixture(habitID: $0.id, startedAt: time(1)) }

        #expect(status(sessions: all, day: 1).allCompleted)
        #expect(!status(sessions: Array(all.prefix(2)), day: 1).allCompleted)
        #expect(status(sessions: Array(all.prefix(2)), day: 1).completedHabitIDs == Set(habits.prefix(2).map(\.id)))
    }

    @Test("1 件だけ登録していて、それが完了なら全完了")
    func singleHabit() {
        let only = [habits[0]]
        let session = SessionSnapshot.fixture(habitID: habits[0].id, startedAt: time(1))

        #expect(status(habits: only, sessions: [session], day: 1).allCompleted)
        #expect(!status(habits: only, day: 1).allCompleted)
    }

    @Test("記録がなくても、同じ日の保存待ちがあれば完了として数え、全完了にも含める")
    func pendingCountsAsCompleted() {
        let sessions = habits.prefix(2).map { SessionSnapshot.fixture(habitID: $0.id, startedAt: time(1)) }
        let pending = RunningSessionMarker(sessionID: UUID(), habitID: habits[2].id, startedAt: time(1, 20))

        let result = status(sessions: Array(sessions), pending: [pending], day: 1)

        #expect(result.completedHabitIDs == Set(habits.map(\.id)))
        #expect(result.allCompleted)
    }

    @Test("別の日の保存待ちは、完了として数えない")
    func pendingOfAnotherDayIsIgnored() {
        let pending = RunningSessionMarker(sessionID: UUID(), habitID: habits[0].id, startedAt: time(1, 23, 59))

        #expect(status(pending: [pending], day: 2).completedHabitIDs.isEmpty)
    }

    @Test("アクティブでない習慣の記録は、完了にも件数にも含めない")
    func ignoresSessionsOfInactiveHabits() {
        let archivedID = UUID()
        let session = SessionSnapshot.fixture(habitID: archivedID, startedAt: time(1))
        let pending = RunningSessionMarker(sessionID: UUID(), habitID: archivedID, startedAt: time(1))

        let result = status(sessions: [session], pending: [pending], day: 1)

        #expect(result == DailyStatus(completedHabitIDs: [], activeCount: 3, allCompleted: false))
    }

    @Test("同じ時刻の記録でも、タイムゾーンが違えば属する日が変わる")
    func dayDependsOnTimeZone() {
        let utc = TestCalendars.gregorian("UTC")
        // 東京の 10/2 5:00 は、UTC では 10/1 20:00
        let session = SessionSnapshot.fixture(habitID: habits[0].id, startedAt: time(2, 5))

        let inUTC = DailyStatusResolver.status(
            activeHabits: habits, sessions: [session], pending: [],
            day: DayKey(session.startedAt, calendar: utc), calendar: utc
        )

        #expect(DayKey(session.startedAt, calendar: utc).day == 1)
        #expect(inUTC.completedHabitIDs == [habits[0].id])
        #expect(status(sessions: [session], day: 1).completedHabitIDs.isEmpty)
        #expect(status(sessions: [session], day: 2).completedHabitIDs == [habits[0].id])
    }
}
