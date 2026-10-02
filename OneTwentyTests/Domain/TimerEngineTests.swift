import Foundation
import Testing
@testable import OneTwenty

struct TimerEngineTests {
    private let startedAt = Date(timeIntervalSince1970: 1_000_000)

    private func progress(after seconds: TimeInterval) -> TimerProgress {
        TimerEngine.progress(startedAt: startedAt, now: startedAt.addingTimeInterval(seconds))
    }

    @Test("120 秒で完了する", arguments: [
        (0.0, false),
        (119.999, false),
        (120.0, true),
        (121.0, true),
    ])
    func finishesAt120Seconds(seconds: TimeInterval, expected: Bool) {
        #expect(progress(after: seconds).isFinished == expected)
    }

    @Test("開始直後は、経過 0・残り 120・進み具合 0")
    func atStart() {
        let result = progress(after: 0)

        #expect(result.elapsed == 0)
        #expect(result.remaining == 120)
        #expect(result.fraction == 0)
        #expect(result.endsAt == startedAt.addingTimeInterval(120))
    }

    @Test("60 秒で、残り 60・進み具合 0.5")
    func atHalf() {
        let result = progress(after: 60)

        #expect(result.elapsed == 60)
        #expect(result.remaining == 60)
        #expect(result.fraction == 0.5)
    }

    @Test("120 秒を超えても、残りは 0・進み具合は 1 で止まる", arguments: [120.0, 121.0, 3_600.0, 100_000.0])
    func clampsAfterFinish(seconds: TimeInterval) {
        let result = progress(after: seconds)

        #expect(result.elapsed == seconds)
        #expect(result.remaining == 0)
        #expect(result.fraction == 1)
    }

    @Test("端末の時刻が開始より前に戻されたら、経過 0 として扱う")
    func clockRewound() {
        let result = progress(after: -300)

        #expect(result.elapsed == 0)
        #expect(result.remaining == 120)
        #expect(result.fraction == 0)
        #expect(!result.isFinished)
    }

    @Test("途中の時刻を飛ばしても、開始時刻との差だけで正しい値になる")
    func dependsOnlyOnDifference() {
        // 10 秒の時点を見た後、裏に回って 115 秒の時点に戻ってきた場合
        _ = progress(after: 10)
        let result = progress(after: 115)

        #expect(result.elapsed == 115)
        #expect(result.remaining == 5)
        #expect(!result.isFinished)
    }

    @Test("開始時刻に端数があっても、終了時刻ちょうどで完了する")
    func finishesExactlyAtEndsAtWithFractionalStart() {
        let fractional = Date(timeIntervalSinceReferenceDate: 800_000_000.123_456_7)
        let endsAt = TimerEngine.progress(startedAt: fractional, now: fractional).endsAt

        #expect(TimerEngine.progress(startedAt: fractional, now: endsAt).isFinished)
        #expect(TimerEngine.progress(startedAt: fractional, now: endsAt).remaining == 0)
        #expect(!TimerEngine.progress(startedAt: fractional, now: endsAt.addingTimeInterval(-0.001)).isFinished)
    }
}
