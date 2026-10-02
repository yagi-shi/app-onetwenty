import Foundation
@testable import OneTwenty

/// Live Activity の代わり。開始した Activity をメモリ上に持つ。
@MainActor
final class FakeLiveActivityClient: LiveActivityClient {
    struct StartFailure: Error {}

    /// `true` なら開始を失敗させる。
    var startFails = false
    private(set) var activities: [ActivitySnapshot] = []
    private(set) var endedActivityIDs: [String] = []
    private(set) var startCount = 0

    /// 既に残っている Activity がある状態を作る。
    func seed(_ activity: ActivitySnapshot) {
        activities.append(activity)
    }

    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws {
        startCount += 1
        if startFails { throw StartFailure() }
        activities.append(ActivitySnapshot(activityID: UUID().uuidString, sessionID: sessionID, endsAt: endsAt))
    }

    func currentActivities() -> [ActivitySnapshot] {
        activities
    }

    func end(activityIDs: Set<String>) async {
        endedActivityIDs.append(contentsOf: activities.map(\.activityID).filter(activityIDs.contains))
        activities.removeAll { activityIDs.contains($0.activityID) }
    }

    func end(sessionID: UUID) async {
        await end(activityIDs: Set(activities.filter { $0.sessionID == sessionID }.map(\.activityID)))
    }
}
