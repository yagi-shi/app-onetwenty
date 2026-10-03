import ActivityKit
import Foundation

/// タイマー実行中の Live Activity で、本体と拡張の間を受け渡すデータ。
/// ロック画面に出る表示のため、習慣名は載せない。
nonisolated struct TimerActivityAttributes: ActivityAttributes {
    /// 実行中マーカーと同じ値。復帰時に、どの Activity が実行中のものかを見分けるのに使う。
    let sessionID: UUID
    /// 2 分たった後に、残り時間の代わりに出す文言。拡張は翻訳ファイルを持たないので、本体が翻訳して渡す。
    let endedLabel: String

    nonisolated struct ContentState: Codable, Hashable {
        let startedAt: Date
        let endsAt: Date
    }
}
