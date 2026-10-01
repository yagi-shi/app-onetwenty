import Foundation
@testable import OneTwenty

/// テスト用の時計。時刻を直接設定・前進でき、カレンダーも差し替えられる。
/// 既定のカレンダーは実行環境のタイムゾーンに左右されないよう UTC に固定している。
@MainActor
final class TestClock: WallClock {
    var now: Date
    var calendar: Calendar

    init(now: Date = Date(timeIntervalSince1970: 0), calendar: Calendar = TestClock.utcCalendar) {
        self.now = now
        self.calendar = calendar
    }

    func advance(by interval: TimeInterval) {
        now = now.addingTimeInterval(interval)
    }

    nonisolated static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
