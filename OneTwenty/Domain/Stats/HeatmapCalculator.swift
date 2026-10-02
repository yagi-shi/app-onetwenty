import Foundation

nonisolated struct HeatmapCell: Equatable, Sendable {
    let day: DayKey
    /// その日に有効だった習慣のうち、完了した割合（0〜1）。有効な習慣がなかった日は `nil`。
    let ratio: Double?
}

/// 直近 84 日の、日ごとの達成率を算出する。
nonisolated enum HeatmapCalculator {
    static let dayCount = 84

    /// - Returns: 古い日から順に、ちょうど 84 件。末尾が `today`。
    /// - Parameter habits: アーカイブ済みを含むすべての習慣。
    static func cells(
        today: DayKey,
        habits: [HabitSnapshot],
        sessions: [SessionSnapshot],
        calendar: Calendar
    ) -> [HeatmapCell] {
        let firstDay = today.adding(days: -(dayCount - 1), calendar: calendar)
        let windowStart = firstDay.startOfDay(calendar: calendar)
        let windowEnd = today.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)

        // 完了記録を日ごとに 1 回だけ振り分ける
        var completedHabitsByDay: [DayKey: Set<UUID>] = [:]
        for session in sessions where session.startedAt >= windowStart && session.startedAt < windowEnd {
            completedHabitsByDay[DayKey(session.startedAt, calendar: calendar), default: []].insert(session.habitID)
        }

        // 習慣が有効だった期間は、登録した日からアーカイブした日まで（両端を含む）
        let lifetimes = habits.map { habit in
            (
                id: habit.id,
                createdDay: DayKey(habit.createdAt, calendar: calendar),
                archivedDay: habit.archivedAt.map { DayKey($0, calendar: calendar) }
            )
        }

        return (0..<dayCount).map { offset in
            let day = firstDay.adding(days: offset, calendar: calendar)
            let valid = lifetimes.filter { lifetime in
                lifetime.createdDay <= day && (lifetime.archivedDay.map { day <= $0 } ?? true)
            }
            guard !valid.isEmpty else {
                return HeatmapCell(day: day, ratio: nil)
            }
            let completedIDs = completedHabitsByDay[day] ?? []
            let completedCount = valid.filter { completedIDs.contains($0.id) }.count
            return HeatmapCell(day: day, ratio: Double(completedCount) / Double(valid.count))
        }
    }
}
