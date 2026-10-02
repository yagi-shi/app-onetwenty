import Foundation

nonisolated struct DailyStatus: Equatable, Sendable {
    /// その日に完了している、アクティブな習慣。
    let completedHabitIDs: Set<UUID>
    let activeCount: Int
    /// アクティブな習慣が 1 件以上あり、そのすべてが完了している。
    let allCompleted: Bool
}

/// ある日における、各習慣の完了状態を判定する。
nonisolated enum DailyStatusResolver {
    /// - Parameter pending: 2 分を走り切ったが、完了記録の保存に失敗して保存待ちになっている実行。
    ///   同じ日にもう一度実行させないので、表示のうえでも完了として数える。
    static func status(
        activeHabits: [HabitSnapshot],
        sessions: [SessionSnapshot],
        pending: [RunningSessionMarker],
        day: DayKey,
        calendar: Calendar
    ) -> DailyStatus {
        let activeIDs = Set(activeHabits.map(\.id))
        var completed: Set<UUID> = []

        // 記録が属する日は、完了時刻ではなく開始時刻で決まる
        for session in sessions where activeIDs.contains(session.habitID) {
            if DayKey(session.startedAt, calendar: calendar) == day {
                completed.insert(session.habitID)
            }
        }
        for marker in pending where activeIDs.contains(marker.habitID) {
            if DayKey(marker.startedAt, calendar: calendar) == day {
                completed.insert(marker.habitID)
            }
        }

        return DailyStatus(
            completedHabitIDs: completed,
            activeCount: activeIDs.count,
            allCompleted: !activeIDs.isEmpty && completed == activeIDs
        )
    }
}
