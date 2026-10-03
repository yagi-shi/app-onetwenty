import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct StatsViewModelTests {
    private let h: ServiceHarness
    private let viewModel: StatsViewModel

    init() throws {
        h = try ServiceHarness()
        viewModel = StatsViewModel(habits: h.habits, sessions: h.sessions, clock: h.clock)
    }

    private func day(_ offset: Int) -> DayKey {
        h.today.adding(days: offset, calendar: h.calendar)
    }

    @Test("記録が 0 件でも、3 つの数値は 0 として持ち、ヒートマップは 84 日分ある")
    func emptyStats() {
        viewModel.reload(displayDay: h.today)

        #expect(viewModel.currentStreak == 0)
        #expect(viewModel.longestStreak == 0)
        #expect(viewModel.totalCompletions == 0)
        #expect(viewModel.completedDayCount == 0)
        #expect(viewModel.cells.count == 84)
        #expect(viewModel.cells.allSatisfy { $0.ratio == nil })
    }

    @Test("全体の現在の連続日数・最長連続日数・通算完了回数を出す")
    func figures() throws {
        let a = try h.addHabit("本を1ページ読む")
        let b = try h.addHabit("靴を履く")
        for offset in [-10, -9, -8, -7, -2, -1] { try h.addSession(for: a, on: day(offset)) }
        try h.addSession(for: b, on: day(-1))

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.currentStreak == 2)
        #expect(viewModel.longestStreak == 4)
        #expect(viewModel.totalCompletions == 7)
        #expect(viewModel.completedDayCount == 6)
    }

    @Test("ヒートマップの最後の日と連続日数の起点は、渡された表示する日")
    func usesDisplayDay() throws {
        let habit = try h.addHabit()
        try h.addSession(for: habit, on: day(-1))

        // 0 時をまたいでも表示する日がまだ前日のまま、という状況
        viewModel.reload(displayDay: day(-1))

        #expect(viewModel.cells.last?.day == day(-1))
        #expect(viewModel.cells.last?.ratio == 1)
        #expect(viewModel.currentStreak == 1)
    }

    @Test("データが変わった後に読み込み直すと、数値に反映される")
    func reloadReflectsChanges() throws {
        let habit = try h.addHabit()
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.totalCompletions == 0)

        try h.addSession(for: habit, on: h.today)
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.totalCompletions == 1)
        #expect(viewModel.currentStreak == 1)
    }

    // MARK: ヒートマップの並べ方

    /// 2026/10/10（土曜日）を今日とする 84 日分のセル。
    private func cells(calendar: Calendar) -> [HeatmapCell] {
        let today = DayKey(TestCalendars.date(2026, 10, 10, 12, in: calendar), calendar: calendar)
        return HeatmapCalculator.cells(today: today, habits: [], sessions: [], calendar: calendar)
    }

    @Test("13 列 × 7 行に並べ、84 日がちょうど 1 回ずつ入る")
    func gridShape() {
        let calendar = TestCalendars.gregorian("Asia/Tokyo")

        let grid = StatsViewModel.layout(cells: cells(calendar: calendar), calendar: calendar)

        #expect(grid.count == 13)
        #expect(grid.allSatisfy { $0.count == 7 })
        let placed = grid.flatMap { $0 }.compactMap { $0?.day }
        #expect(placed.count == 84)
        #expect(Set(placed).count == 84)
    }

    @Test("週の始まりが日曜なら、今日（土曜）は右端の列の一番下。84 日前の日曜は左から 2 列目の一番上")
    func sundayFirst() {
        var calendar = TestCalendars.gregorian("Asia/Tokyo")
        calendar.firstWeekday = 1
        let cells = cells(calendar: calendar)

        let grid = StatsViewModel.layout(cells: cells, calendar: calendar)

        #expect(grid[12][6]?.day == cells.last?.day)
        #expect(grid[1][0]?.day == cells.first?.day)
        #expect(grid[0].allSatisfy { $0 == nil })
    }

    @Test("週の始まりが月曜なら、今日（土曜）は右端の列の下から 2 番目で、その下（日曜）は空ける")
    func mondayFirst() {
        var calendar = TestCalendars.gregorian("Asia/Tokyo")
        calendar.firstWeekday = 2
        let cells = cells(calendar: calendar)

        let grid = StatsViewModel.layout(cells: cells, calendar: calendar)

        #expect(grid[12][5]?.day == cells.last?.day)
        #expect(grid[12][6] == nil)
        #expect(grid[0][6]?.day == cells.first?.day)
        #expect(grid[0][0..<6].allSatisfy { $0 == nil })
    }

    @Test("同じ列には、同じ週の日が上から曜日の順に並ぶ")
    func columnsAreWeeks() {
        let calendar = TestCalendars.gregorian("Asia/Tokyo")

        let grid = StatsViewModel.layout(cells: cells(calendar: calendar), calendar: calendar)

        for column in grid {
            let days = column.compactMap { $0?.day }
            for (earlier, later) in zip(days, days.dropFirst()) {
                #expect(earlier.adding(days: 1, calendar: calendar) == later)
            }
        }
    }
}
