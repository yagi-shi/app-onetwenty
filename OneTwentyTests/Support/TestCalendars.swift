import Foundation

/// テストで使うカレンダーの生成。実行環境の設定に左右されないよう、暦とタイムゾーンを必ず指定する。
enum TestCalendars {
    static func gregorian(_ timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier)!
        return calendar
    }

    /// 指定したカレンダーでの年月日・時刻から時刻を作る。
    static func date(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
        in calendar: Calendar
    ) -> Date {
        let components = DateComponents(
            year: year, month: month, day: day,
            hour: hour, minute: minute, second: second
        )
        return calendar.date(from: components)!
    }
}
