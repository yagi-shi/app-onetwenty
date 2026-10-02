import Foundation

nonisolated enum LaunchKind: Sendable {
    /// アプリのプロセスが起動してから最初のアクティブ化。
    case cold
    /// 2 回目以降のアクティブ化（裏から戻った、通知センターを閉じた、など）。
    case warm
}

/// 残っている Live Activity の、判定に必要な値だけを抜き出したもの。
nonisolated struct ActivitySnapshot: Equatable, Sendable {
    let activityID: String
    let sessionID: UUID
    let endsAt: Date
}

nonisolated struct RecoveryDecision: Equatable, Sendable {
    enum MarkerAction: Equatable, Sendable {
        /// 実行中のタイマーはない。
        case none
        /// 計測を続ける。
        case keepRunning
        /// 2 分を走り切っているので、完了として記録する。
        case complete(RunningSessionMarker)
        /// 記録せずに破棄する。
        case discard(RunningSessionMarker)
    }

    let markerAction: MarkerAction
    /// 終了させる Live Activity の ID。
    let activitiesToEnd: Set<String>
}

/// アプリがアクティブになるたびに、実行中だったタイマーをどう扱うかと、
/// どの Live Activity を消すかを 1 回の呼び出しで決める。
/// 2 つを別々に決めると、マーカーを消した後の状態を知らずに実行中の Live Activity を消しうるため。
nonisolated enum SessionRecoveryResolver {
    /// 開始からこの時間以上たった実行は、完了していても記録しない。
    static let discardAfter: TimeInterval = 24 * 60 * 60

    static func resolve(
        marker: RunningSessionMarker?,
        activities: [ActivitySnapshot],
        now: Date,
        launch: LaunchKind
    ) -> RecoveryDecision {
        let action = markerAction(marker: marker, now: now, launch: launch)

        // 判定の後も実行が続くのは keepRunning のときだけ
        let runningSessionID = action == .keepRunning ? marker?.sessionID : nil
        let activitiesToEnd = activities
            .filter { $0.sessionID != runningSessionID || $0.endsAt <= now }
            .map(\.activityID)

        return RecoveryDecision(markerAction: action, activitiesToEnd: Set(activitiesToEnd))
    }

    private static func markerAction(
        marker: RunningSessionMarker?,
        now: Date,
        launch: LaunchKind
    ) -> RecoveryDecision.MarkerAction {
        guard let marker else { return .none }

        if now >= marker.startedAt.addingTimeInterval(discardAfter) {
            return .discard(marker)
        }
        if TimerEngine.progress(startedAt: marker.startedAt, now: now).isFinished {
            return .complete(marker)
        }
        switch launch {
        case .cold:
            // 2 分たたないうちにアプリが終了していた。走り切ったとはみなさない
            return .discard(marker)
        case .warm:
            return .keepRunning
        }
    }
}
