import Foundation

/// 現在時刻と、日付計算に使うカレンダーの取得口。
/// テストで差し替えられるよう、`Date()` や `Calendar.current` を各所で直接使わずここを経由する。
protocol WallClock {
    var now: Date { get }
    var calendar: Calendar { get }
}

struct SystemClock: WallClock {
    var now: Date { Date() }
    var calendar: Calendar { .current }
}
