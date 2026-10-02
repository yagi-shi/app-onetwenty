import Foundation
import Testing
@testable import OneTwenty

struct HeatmapCalculatorTests {
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")
    private var today: DayKey { DayKey(noon(0), calendar: calendar) }

    /// 今日から `offset` 日ずれた日の正午。
    private func noon(_ offset: Int) -> Date {
        TestCalendars.date(2026, 10, 10, 12, in: calendar).addingTimeInterval(TimeInterval(offset) * 86_400)
    }

    private func cells(habits: [HabitSnapshot], sessions: [SessionSnapshot]) -> [HeatmapCell] {
        HeatmapCalculator.cells(today: today, habits: habits, sessions: sessions, calendar: calendar)
    }

    /// 今日から `offset` 日ずれた日のセル。
    private func cell(_ offset: Int, in cells: [HeatmapCell]) -> HeatmapCell {
        cells[cells.count - 1 + offset]
    }

    @Test("ちょうど 84 件で、先頭が 83 日前、末尾が今日")
    func rangeIsLast84Days() {
        let result = cells(habits: [], sessions: [])

        #expect(result.count == 84)
        #expect(result.first?.day == today.adding(days: -83, calendar: calendar))
        #expect(result.last?.day == today)
        #expect(result.map(\.day) == result.map(\.day).sorted())
        #expect(Set(result.map(\.day)).count == 84)
    }

    @Test("習慣が 1 件もなければ、すべての日が空欄")
    func noHabits() {
        #expect(cells(habits: [], sessions: []).allSatisfy { $0.ratio == nil })
    }

    @Test("登録した日より前は空欄、登録した日からは達成率が入る")
    func emptyBeforeCreation() {
        let habit = HabitSnapshot.fixture(createdAt: noon(-5))

        let result = cells(habits: [habit], sessions: [])

        #expect(cell(-6, in: result).ratio == nil)
        #expect(cell(-5, in: result).ratio == 0)
        #expect(cell(0, in: result).ratio == 0)
    }

    @Test("1 件登録して 1 件完了した日は 1.0")
    func fullyCompletedDay() {
        let habit = HabitSnapshot.fixture(createdAt: noon(-10))
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: noon(-2))

        let result = cells(habits: [habit], sessions: [session])

        #expect(cell(-2, in: result).ratio == 1)
        #expect(cell(-1, in: result).ratio == 0)
    }

    @Test("3 件のうち 2 件完了した日は 3 分の 2")
    func partiallyCompletedDay() {
        let habits = (0..<3).map { _ in HabitSnapshot.fixture(createdAt: noon(-10)) }
        let sessions = habits.prefix(2).map { SessionSnapshot.fixture(habitID: $0.id, startedAt: noon(-1)) }

        let result = cells(habits: habits, sessions: Array(sessions))

        #expect(cell(-1, in: result).ratio == 2.0 / 3.0)
    }

    @Test("23:59 に始めた記録は、始めた日の達成として数える")
    func attributesToStartDay() {
        let habit = HabitSnapshot.fixture(createdAt: noon(-10))
        let lateStart = TestCalendars.date(2026, 10, 8, 23, 59, 0, in: calendar)
        let session = SessionSnapshot.fixture(habitID: habit.id, startedAt: lateStart)

        let result = cells(habits: [habit], sessions: [session])

        #expect(cell(-2, in: result).ratio == 1)
        #expect(cell(-1, in: result).ratio == 0)
    }

    @Test("アーカイブした日までは分母に含め、翌日からは含めない")
    func archivedHabitCountsThroughArchiveDay() {
        let kept = HabitSnapshot.fixture(createdAt: noon(-10))
        let archived = HabitSnapshot.fixture(createdAt: noon(-10), order: -1, archivedAt: noon(-3))
        let session = SessionSnapshot.fixture(habitID: kept.id, startedAt: noon(-3))
        let later = SessionSnapshot.fixture(habitID: kept.id, startedAt: noon(-2))

        let result = cells(habits: [kept, archived], sessions: [session, later])

        #expect(cell(-3, in: result).ratio == 0.5)
        #expect(cell(-2, in: result).ratio == 1)
    }

    @Test("唯一の習慣をアーカイブすると、翌日からは空欄になる")
    func emptyAfterOnlyHabitIsArchived() {
        let archived = HabitSnapshot.fixture(createdAt: noon(-10), order: -1, archivedAt: noon(-3))

        let result = cells(habits: [archived], sessions: [])

        #expect(cell(-3, in: result).ratio == 0)
        #expect(cell(-2, in: result).ratio == nil)
    }

    @Test("アーカイブしても、それより前の日の達成率は変わらない")
    func archivingDoesNotChangePastDays() {
        let kept = HabitSnapshot.fixture(createdAt: noon(-10))
        let other = HabitSnapshot.fixture(createdAt: noon(-10))
        let sessions = [
            SessionSnapshot.fixture(habitID: kept.id, startedAt: noon(-6)),
            SessionSnapshot.fixture(habitID: other.id, startedAt: noon(-6)),
            SessionSnapshot.fixture(habitID: other.id, startedAt: noon(-5)),
        ]
        let before = cells(habits: [kept, other], sessions: sessions)

        let archivedOther = HabitSnapshot.fixture(id: other.id, createdAt: other.createdAt, order: -1, archivedAt: noon(-4))
        let after = cells(habits: [kept, archivedOther], sessions: sessions)

        for offset in -83...(-4) {
            #expect(cell(offset, in: after) == cell(offset, in: before))
        }
        #expect(cell(-6, in: after).ratio == 1)
        #expect(cell(-5, in: after).ratio == 0.5)
    }

    @Test("84 日より前の記録は無視する")
    func ignoresSessionsOutsideRange() {
        let habit = HabitSnapshot.fixture(createdAt: noon(-200))
        let old = SessionSnapshot.fixture(habitID: habit.id, startedAt: noon(-84))

        let result = cells(habits: [habit], sessions: [old])

        #expect(result.allSatisfy { $0.ratio == 0 })
    }

    @Test("記録 1,000 件でも、ヒートマップと連続日数の集計が 200 ミリ秒以内に終わる")
    func performanceWithThousandSessions() {
        let habits = (0..<3).map { _ in HabitSnapshot.fixture(createdAt: noon(-400)) }
        let sessions = (0..<1_000).map { index in
            SessionSnapshot.fixture(habitID: habits[index % 3].id, startedAt: noon(-(index / 3)))
        }
        #expect(sessions.count == 1_000)

        let clock = ContinuousClock()
        let elapsed = clock.measure {
            _ = cells(habits: habits, sessions: sessions)
            let days = Set(sessions.map { DayKey($0.startedAt, calendar: calendar) })
            _ = StreakCalculator.currentStreak(completedDays: days, today: today, calendar: calendar)
            _ = StreakCalculator.longestStreak(completedDays: days, calendar: calendar)
            _ = StreakCalculator.totalCompletions(sessions: sessions)
        }

        #expect(elapsed < .milliseconds(200))
    }
}
