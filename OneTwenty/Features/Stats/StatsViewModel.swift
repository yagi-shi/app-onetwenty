import Foundation
import Observation

@Observable
final class StatsViewModel {
    /// 古い日から順に 84 日分。
    private(set) var cells: [HeatmapCell] = []
    /// ヒートマップを 13 列（週）× 7 行（曜日）に並べたもの。84 日に入らない位置は `nil`。
    private(set) var columns: [[HeatmapCell?]] = []
    /// 3 つの数値は、0 でも表示するので常に値を持つ。
    private(set) var currentStreak = 0
    private(set) var longestStreak = 0
    private(set) var totalCompletions = 0
    /// 1 件以上完了した日の数（直近 84 日）。ヒートマップの読み上げに使う。
    private(set) var completedDayCount = 0

    static let columnCount = 13
    static let rowCount = 7

    @ObservationIgnored private let habits: HabitRepository
    @ObservationIgnored private let sessions: SessionRepository
    @ObservationIgnored private let clock: WallClock

    init(habits: HabitRepository, sessions: SessionRepository, clock: WallClock) {
        self.habits = habits
        self.sessions = sessions
        self.clock = clock
    }

    /// - Parameter displayDay: ホームと同じ「表示する日」。0 時をまたいでもホームとずれないよう、現在時刻からは求めない。
    func reload(displayDay: DayKey) {
        let calendar = clock.calendar
        let allSessions = sessions.allSessions()

        cells = HeatmapCalculator.cells(
            today: displayDay,
            habits: habits.allHabits(),
            sessions: allSessions,
            calendar: calendar
        )
        columns = Self.layout(cells: cells, calendar: calendar)
        completedDayCount = cells.filter { ($0.ratio ?? 0) > 0 }.count

        let completedDays = Set(allSessions.map { DayKey($0.startedAt, calendar: calendar) })
        currentStreak = StreakCalculator.currentStreak(completedDays: completedDays, today: displayDay, calendar: calendar)
        longestStreak = StreakCalculator.longestStreak(completedDays: completedDays, calendar: calendar)
        totalCompletions = StreakCalculator.totalCompletions(sessions: allSessions)
    }

    /// 曜日をそろえて並べる。列が週（左が古い）、行が曜日（週の始まりは端末の暦の設定に従う）。
    static func layout(cells: [HeatmapCell], calendar: Calendar) -> [[HeatmapCell?]] {
        var grid = Array(repeating: Array(repeating: HeatmapCell?.none, count: rowCount), count: columnCount)
        guard let today = cells.last?.day else { return grid }
        let todayRow = row(of: today, calendar: calendar)

        for cell in cells {
            // その日の週の始まりが、今日の週の始まりから何週前か。今日の週が右端の列になる
            let cellRow = row(of: cell.day, calendar: calendar)
            let daysBack = DayKey.days(from: cell.day, to: today, calendar: calendar)
            let weeksBack = (daysBack - todayRow + cellRow) / 7
            let column = columnCount - 1 - weeksBack
            guard (0..<columnCount).contains(column) else { continue }
            grid[column][cellRow] = cell
        }
        return grid
    }

    private static func row(of day: DayKey, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: day.startOfDay(calendar: calendar))
        return (weekday - calendar.firstWeekday + 7) % 7
    }
}
