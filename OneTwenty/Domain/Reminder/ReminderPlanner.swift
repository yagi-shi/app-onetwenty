import Foundation

nonisolated enum NotificationAuthorization: Sendable {
    case notDetermined
    case authorized
    case denied
}

nonisolated struct PlannedReminder: Equatable, Sendable {
    let day: DayKey
    let fireDate: Date
    let identifier: String
}

/// 予約しておくべきリマインダーの一覧を算出する。
/// ローカル通知は「今日は完了済みだから送らない」を発火時に判定できないため、
/// 繰り返し通知にせず、日付ごとの通知を先の分まで予約しておく。
nonisolated enum ReminderPlanner {
    /// 予約しておく日数。iOS が保留できる通知は 64 件までで、タイマーの完了通知の分を残す。
    static let horizonDays = 60
    static let identifierPrefix = "reminder."

    static func plan(
        now: Date,
        calendar: Calendar,
        time: ReminderTime,
        enabled: Bool,
        authorization: NotificationAuthorization,
        activeHabitCount: Int,
        todayAllCompleted: Bool
    ) -> [PlannedReminder] {
        guard enabled, authorization == .authorized, activeHabitCount > 0 else { return [] }

        let today = DayKey(now, calendar: calendar)
        return (0..<horizonDays).compactMap { offset in
            let day = today.adding(days: offset, calendar: calendar)
            if day == today, todayAllCompleted { return nil }
            guard let fireDate = fireDate(on: day, at: time, calendar: calendar), fireDate > now else {
                return nil
            }
            return PlannedReminder(day: day, fireDate: fireDate, identifier: identifier(day: day, time: time))
        }
    }

    private static func fireDate(on day: DayKey, at time: ReminderTime, calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(
            era: day.era, year: day.year, month: day.month, day: day.day,
            hour: time.hour, minute: time.minute
        ))
    }

    /// 時刻も含めることで、通知時刻を変えたときに古い予約と新しい予約を区別できる。
    private static func identifier(day: DayKey, time: ReminderTime) -> String {
        String(
            format: "%@%04d-%02d-%02d.%02d%02d",
            identifierPrefix, day.year, day.month, day.day, time.hour, time.minute
        )
    }
}
