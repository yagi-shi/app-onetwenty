import Foundation

/// 端末のカレンダーとタイムゾーンにおける「日」。
/// 日は保存せず、集計のたびに時刻からこの型へ変換する。
nonisolated struct DayKey: Hashable, Comparable, Sendable {
    /// 和暦など、年だけでは日が決まらない暦でも一意になるよう紀元も持つ。
    let era: Int
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        era = components.era ?? 0
        year = components.year ?? 0
        month = components.month ?? 0
        day = components.day ?? 0
    }

    func adding(days: Int, calendar: Calendar) -> DayKey {
        let moved = calendar.date(byAdding: .day, value: days, to: noon(calendar: calendar))
        return DayKey(moved ?? noon(calendar: calendar), calendar: calendar)
    }

    func startOfDay(calendar: Calendar) -> Date {
        calendar.startOfDay(for: noon(calendar: calendar))
    }

    /// `from` から `to` までの日数。`to` が後なら正、同じ日なら 0。
    static func days(from: DayKey, to: DayKey, calendar: Calendar) -> Int {
        let components = calendar.dateComponents(
            [.day],
            from: from.noon(calendar: calendar),
            to: to.noon(calendar: calendar)
        )
        return components.day ?? 0
    }

    static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.era, lhs.year, lhs.month, lhs.day) < (rhs.era, rhs.year, rhs.month, rhs.day)
    }

    /// その日の正午。夏時間の切り替えで 0:00 が存在しない日でも必ず存在する時刻を基準にする。
    private func noon(calendar: Calendar) -> Date {
        let components = DateComponents(era: era, year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components) else {
            assertionFailure("DayKey を作ったカレンダーと異なるカレンダーが渡された可能性がある")
            return .distantPast
        }
        return date
    }
}
