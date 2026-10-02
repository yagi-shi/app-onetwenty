import Foundation
import Testing
@testable import OneTwenty

struct StreakCalculatorTests {
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")
    private var today: DayKey { DayKey(TestCalendars.date(2026, 10, 10, 12, in: calendar), calendar: calendar) }

    /// 今日から `offset` 日ずれた日（-1 なら昨日）。
    private func day(_ offset: Int) -> DayKey {
        today.adding(days: offset, calendar: calendar)
    }

    private func habitStreak(_ offsets: [Int], createdOffset: Int = -100) -> Int {
        StreakCalculator.habitStreak(
            sessionDays: Set(offsets.map(day)),
            createdDay: day(createdOffset),
            today: today,
            calendar: calendar
        )
    }

    // MARK: 習慣ごとの連続日数

    @Test("昨日まで 3 日連続で、今日がまだなら 3")
    func keepsStreakWhenTodayIsNotDoneYet() {
        #expect(habitStreak([-3, -2, -1]) == 3)
    }

    @Test("昨日まで 3 日連続で、今日も完了なら 4")
    func countsTodayWhenDone() {
        #expect(habitStreak([-3, -2, -1, 0]) == 4)
    }

    @Test("昨日が未完了なら、それ以前に連続があっても 0")
    func breaksWhenYesterdayIsMissing() {
        #expect(habitStreak([-4, -3, -2]) == 0)
    }

    @Test("昨日が未完了でも、今日完了していれば 1")
    func restartsFromToday() {
        #expect(habitStreak([-4, -3, -2, 0]) == 1)
    }

    @Test("記録がなければ 0")
    func noSessions() {
        #expect(habitStreak([]) == 0)
    }

    @Test("登録した日より前の日は数えない")
    func ignoresDaysBeforeCreation() {
        #expect(habitStreak([-3, -2, -1], createdOffset: -2) == 2)
        #expect(habitStreak([-3, -2, -1, 0], createdOffset: 0) == 1)
    }

    @Test("登録した当日でまだ完了していなければ 0、完了していれば 1")
    func createdToday() {
        #expect(habitStreak([], createdOffset: 0) == 0)
        #expect(habitStreak([0], createdOffset: 0) == 1)
    }

    @Test("月をまたいでも連続として数える")
    func acrossMonthBoundary() {
        let october2 = DayKey(TestCalendars.date(2026, 10, 2, 12, in: calendar), calendar: calendar)
        let days = Set((-3...0).map { october2.adding(days: $0, calendar: calendar) })

        let streak = StreakCalculator.habitStreak(
            sessionDays: days,
            createdDay: october2.adding(days: -30, calendar: calendar),
            today: october2,
            calendar: calendar
        )

        #expect(streak == 4)
    }

    @Test("夏時間に切り替わる日をまたいでも連続として数える")
    func acrossDaylightSavingChange() {
        let newYork = TestCalendars.gregorian("America/New_York")
        let march9 = DayKey(TestCalendars.date(2026, 3, 9, 12, in: newYork), calendar: newYork)
        let days = Set((-3...0).map { march9.adding(days: $0, calendar: newYork) })

        #expect(StreakCalculator.currentStreak(completedDays: days, today: march9, calendar: newYork) == 4)
        #expect(StreakCalculator.longestStreak(completedDays: days, calendar: newYork) == 4)
    }

    // MARK: 全体の連続日数

    @Test("全体の現在の連続日数も、今日が未完了なら昨日までを保つ")
    func overallCurrentStreak() {
        func current(_ offsets: [Int]) -> Int {
            StreakCalculator.currentStreak(completedDays: Set(offsets.map(day)), today: today, calendar: calendar)
        }

        #expect(current([-3, -2, -1]) == 3)
        #expect(current([-3, -2, -1, 0]) == 4)
        #expect(current([-4, -3, -2]) == 0)
        #expect(current([]) == 0)
    }

    @Test("最長の連続日数は、途中の区間も含めて最も長い区間の日数")
    func longestStreak() {
        func longest(_ offsets: [Int]) -> Int {
            StreakCalculator.longestStreak(completedDays: Set(offsets.map(day)), calendar: calendar)
        }

        #expect(longest([]) == 0)
        #expect(longest([-5]) == 1)
        #expect(longest([-20, -19, -18, -15, -14, -10, -9, -8, -7, -2, -1]) == 4)
        #expect(longest([-3, -1]) == 1)
    }

    @Test("通算の完了回数は、アーカイブ済みの習慣の分も含む記録の件数")
    func totalCompletions() {
        let active = UUID()
        let archived = UUID()
        let sessions = [
            SessionSnapshot.fixture(habitID: active, startedAt: Date(timeIntervalSince1970: 0)),
            SessionSnapshot.fixture(habitID: archived, startedAt: Date(timeIntervalSince1970: 100)),
            SessionSnapshot.fixture(habitID: archived, startedAt: Date(timeIntervalSince1970: 90_000)),
        ]

        #expect(StreakCalculator.totalCompletions(sessions: sessions) == 3)
        #expect(StreakCalculator.totalCompletions(sessions: []) == 0)
    }
}
