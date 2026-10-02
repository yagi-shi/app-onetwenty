import Foundation

nonisolated struct TimerProgress: Equatable, Sendable {
    /// 開始からの経過秒数。端末の時刻が開始より前に戻された場合は 0。
    let elapsed: TimeInterval
    /// 残り秒数（0〜120）。
    let remaining: TimeInterval
    /// 進み具合（0〜1）。
    let fraction: Double
    let isFinished: Bool
    let endsAt: Date
}

/// 2 分タイマーの計算。経過は毎回「開始時刻と現在時刻の差」から求め、刻みを積み上げない。
/// 画面の描き直しは計算のきっかけにすぎないので、アプリが裏に回っていた間の分もそのまま反映される。
nonisolated enum TimerEngine {
    static let duration: TimeInterval = 120

    static func progress(startedAt: Date, now: Date) -> TimerProgress {
        let endsAt = startedAt.addingTimeInterval(duration)
        // 通知と Live Activity は endsAt に発火するので、完了の判定も同じ時刻との比較でそろえる
        let isFinished = now >= endsAt
        let elapsed = max(0, now.timeIntervalSince(startedAt))
        let remaining = isFinished ? 0 : min(duration, endsAt.timeIntervalSince(now))
        return TimerProgress(
            elapsed: elapsed,
            remaining: remaining,
            fraction: 1 - remaining / duration,
            isFinished: isFinished,
            endsAt: endsAt
        )
    }
}
