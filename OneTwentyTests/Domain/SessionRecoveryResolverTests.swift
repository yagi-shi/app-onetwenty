import Foundation
import Testing
@testable import OneTwenty

struct SessionRecoveryResolverTests {
    private let startedAt = Date(timeIntervalSince1970: 1_000_000)
    private var marker: RunningSessionMarker {
        RunningSessionMarker(sessionID: Self.sessionID, habitID: Self.habitID, startedAt: startedAt)
    }
    private static let sessionID = UUID()
    private static let habitID = UUID()

    private func resolve(
        marker: RunningSessionMarker?,
        after seconds: TimeInterval,
        launch: LaunchKind,
        activities: [ActivitySnapshot] = []
    ) -> RecoveryDecision {
        SessionRecoveryResolver.resolve(
            marker: marker,
            activities: activities,
            now: startedAt.addingTimeInterval(seconds),
            launch: launch
        )
    }

    /// 実行中のタイマーに対応する Live Activity。
    private func activity(id: String = "running", sessionID: UUID = sessionID, endsAfter seconds: TimeInterval = 120) -> ActivitySnapshot {
        ActivitySnapshot(activityID: id, sessionID: sessionID, endsAt: startedAt.addingTimeInterval(seconds))
    }

    // MARK: マーカーの判定

    @Test("実行中のタイマーがなければ、何もしない", arguments: [LaunchKind.cold, .warm])
    func noMarker(launch: LaunchKind) {
        #expect(resolve(marker: nil, after: 500, launch: launch).markerAction == .none)
    }

    @Test("120 秒未満で、アプリが終了していた場合は破棄する", arguments: [-60.0, 0.0, 60.0, 119.999])
    func discardsUnfinishedOnColdLaunch(seconds: TimeInterval) {
        #expect(resolve(marker: marker, after: seconds, launch: .cold).markerAction == .discard(marker))
    }

    @Test("120 秒未満で、裏に回っていただけなら計測を続ける", arguments: [-60.0, 0.0, 60.0, 119.999])
    func keepsRunningOnWarmLaunch(seconds: TimeInterval) {
        #expect(resolve(marker: marker, after: seconds, launch: .warm).markerAction == .keepRunning)
    }

    @Test("120 秒以上 24 時間未満なら、起動の種類によらず完了として記録する", arguments: [
        (120.0, LaunchKind.cold), (120.0, .warm),
        (121.0, .cold), (121.0, .warm),
        (3_600.0, .cold), (3_600.0, .warm),
        (86_399.999, .cold), (86_399.999, .warm),
    ])
    func completesFinishedSession(seconds: TimeInterval, launch: LaunchKind) {
        #expect(resolve(marker: marker, after: seconds, launch: launch).markerAction == .complete(marker))
    }

    @Test("24 時間以上たっていたら、起動の種類によらず破棄する", arguments: [
        (86_400.0, LaunchKind.cold), (86_400.0, .warm),
        (100_000.0, .cold), (100_000.0, .warm),
    ])
    func discardsAfter24Hours(seconds: TimeInterval, launch: LaunchKind) {
        #expect(resolve(marker: marker, after: seconds, launch: launch).markerAction == .discard(marker))
    }

    // MARK: Live Activity の掃除

    @Test("計測を続けるとき、実行中の Live Activity は終了させない")
    func keepsRunningActivity() {
        let decision = resolve(marker: marker, after: 30, launch: .warm, activities: [activity()])

        #expect(decision.markerAction == .keepRunning)
        #expect(decision.activitiesToEnd.isEmpty)
    }

    @Test("完了として記録するとき、その Live Activity は終了させる")
    func endsActivityOfCompletedSession() {
        let decision = resolve(marker: marker, after: 300, launch: .warm, activities: [activity()])

        #expect(decision.markerAction == .complete(marker))
        #expect(decision.activitiesToEnd == ["running"])
    }

    @Test("破棄するとき、その Live Activity は終了させる", arguments: [(30.0, LaunchKind.cold), (90_000.0, .warm)])
    func endsActivityOfDiscardedSession(seconds: TimeInterval, launch: LaunchKind) {
        let decision = resolve(marker: marker, after: seconds, launch: launch, activities: [activity()])

        #expect(decision.markerAction == .discard(marker))
        #expect(decision.activitiesToEnd == ["running"])
    }

    @Test("実行中のタイマーがないとき、残っている Live Activity はすべて終了させる")
    func endsLeftoversWithoutMarker() {
        let leftovers = [activity(id: "a", sessionID: UUID()), activity(id: "b", sessionID: UUID(), endsAfter: 9_999)]

        let decision = resolve(marker: nil, after: 30, launch: .warm, activities: leftovers)

        #expect(decision.activitiesToEnd == ["a", "b"])
    }

    @Test("計測を続けるとき、別の実行の取り残しだけを終了させる")
    func endsOnlyLeftoversWhileRunning() {
        let activities = [activity(id: "running"), activity(id: "leftover", sessionID: UUID(), endsAfter: 9_999)]

        let decision = resolve(marker: marker, after: 30, launch: .warm, activities: activities)

        #expect(decision.markerAction == .keepRunning)
        #expect(decision.activitiesToEnd == ["leftover"])
    }

    @Test("実行と同じ ID でも、終了時刻を過ぎている Live Activity は終了させる")
    func endsExpiredActivityEvenIfSessionMatches() {
        let expired = activity(id: "expired", endsAfter: 20)

        let decision = resolve(marker: marker, after: 30, launch: .warm, activities: [expired])

        #expect(decision.markerAction == .keepRunning)
        #expect(decision.activitiesToEnd == ["expired"])
    }

    @Test("終了時刻ちょうどの Live Activity は終了させる")
    func endsActivityExactlyAtEndTime() {
        let decision = resolve(marker: marker, after: 120, launch: .warm, activities: [activity()])

        #expect(decision.activitiesToEnd == ["running"])
    }

    @Test("Live Activity が残っていなければ、終了させるものはない")
    func noActivities() {
        #expect(resolve(marker: marker, after: 30, launch: .warm).activitiesToEnd.isEmpty)
        #expect(resolve(marker: nil, after: 30, launch: .cold).activitiesToEnd.isEmpty)
    }
}
