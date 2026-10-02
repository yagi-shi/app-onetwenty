import Foundation

/// 連続日数・最長連続日数・通算完了回数を、完了記録から毎回算出する。
/// 0 も含めてそのまま返す。0 を表示するかどうかは画面側が決める。
nonisolated enum StreakCalculator {
    /// 習慣ごとの現在の連続日数。
    /// - Parameter sessionDays: その習慣の完了記録がある日。
    /// - Parameter createdDay: 習慣を登録した日。これより前の日は数えない。
    static func habitStreak(sessionDays: Set<DayKey>, createdDay: DayKey, today: DayKey, calendar: Calendar) -> Int {
        streak(in: sessionDays, today: today, notBefore: createdDay, calendar: calendar)
    }

    /// 全体の現在の連続日数。
    /// - Parameter completedDays: 1 件以上完了した日（アーカイブ済みの習慣の分も含む）。
    static func currentStreak(completedDays: Set<DayKey>, today: DayKey, calendar: Calendar) -> Int {
        streak(in: completedDays, today: today, notBefore: nil, calendar: calendar)
    }

    static func longestStreak(completedDays: Set<DayKey>, calendar: Calendar) -> Int {
        var longest = 0
        var current = 0
        var previous: DayKey?
        for day in completedDays.sorted() {
            if let previous, previous.adding(days: 1, calendar: calendar) == day {
                current += 1
            } else {
                current = 1
            }
            longest = max(longest, current)
            previous = day
        }
        return longest
    }

    static func totalCompletions(sessions: [SessionSnapshot]) -> Int {
        sessions.count
    }

    /// 今日が完了済みなら今日から、未完了なら前日からさかのぼって数える。
    /// 今日がまだ未完了というだけでは、前日までの連続を途切れさせない。
    private static func streak(in days: Set<DayKey>, today: DayKey, notBefore: DayKey?, calendar: Calendar) -> Int {
        var day = days.contains(today) ? today : today.adding(days: -1, calendar: calendar)
        var count = 0
        while days.contains(day) {
            if let notBefore, day < notBefore { break }
            count += 1
            day = day.adding(days: -1, calendar: calendar)
        }
        return count
    }
}
