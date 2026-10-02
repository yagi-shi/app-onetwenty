import Foundation
@testable import OneTwenty

/// 音と振動の代わり。呼ばれた回数だけを記録する。
@MainActor
final class FakeFeedbackPlayer: FeedbackPlayer {
    private(set) var prepareCount = 0
    private(set) var playCompletionCount = 0

    func prepare() {
        prepareCount += 1
    }

    func playCompletion() {
        playCompletionCount += 1
    }
}
