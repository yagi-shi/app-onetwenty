import ActivityKit
import Foundation

/// Live Activity の窓口。
protocol LiveActivityClient {
    /// ユーザーが Live Activity を無効にしている場合は、何もせず戻る。
    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws
    func currentActivities() -> [ActivitySnapshot]
    func end(activityIDs: Set<String>) async
    func end(sessionID: UUID) async
}

final class ActivityKitLiveActivityClient: LiveActivityClient {
    func start(sessionID: UUID, startedAt: Date, endsAt: Date) async throws {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = TimerActivityAttributes.ContentState(startedAt: startedAt, endsAt: endsAt)
        // アプリが止まっていても、終了時刻を過ぎたら OS が「終了」の表示に切り替えられるようにする
        _ = try Activity.request(
            attributes: TimerActivityAttributes(sessionID: sessionID),
            content: ActivityContent(state: state, staleDate: endsAt),
            pushType: nil
        )
    }

    func currentActivities() -> [ActivitySnapshot] {
        Activity<TimerActivityAttributes>.activities.map { activity in
            ActivitySnapshot(
                activityID: activity.id,
                sessionID: activity.attributes.sessionID,
                endsAt: activity.content.state.endsAt
            )
        }
    }

    func end(activityIDs: Set<String>) async {
        for activity in Activity<TimerActivityAttributes>.activities where activityIDs.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func end(sessionID: UUID) async {
        for activity in Activity<TimerActivityAttributes>.activities where activity.attributes.sessionID == sessionID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
