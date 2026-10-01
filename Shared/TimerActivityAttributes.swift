import ActivityKit
import Foundation

/// タイマー実行中の Live Activity で、本体と拡張の間を受け渡すデータ。
/// ロック画面に出る表示のため、習慣名は載せない。
nonisolated struct TimerActivityAttributes: ActivityAttributes {
    /// 実行中マーカーと同じ値。復帰時に、どの Activity が実行中のものかを見分けるのに使う。
    let sessionID: UUID

    nonisolated struct ContentState: Codable, Hashable {
        let startedAt: Date
        let endsAt: Date
    }
}
