import Foundation

/// 「待つ」処理を、テストが好きなときに終わらせられるようにする。実際には時間を待たない。
@MainActor
final class ControlledSleeper {
    private(set) var durations: [Duration] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func sleep(_ duration: Duration) async {
        durations.append(duration)
        await withCheckedContinuation { waiting.append($0) }
    }

    /// 待ちに入るまで待つ。
    func waitUntilSleeping() async {
        while waiting.isEmpty {
            await Task.yield()
        }
    }

    /// 待っている処理を先へ進める。
    func wakeUp() {
        let continuations = waiting
        waiting = []
        continuations.forEach { $0.resume() }
    }
}
