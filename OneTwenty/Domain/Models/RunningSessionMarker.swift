import Foundation

/// 実行中のタイマーを表す印。アプリが終了しても、次に開いたときに実行を復元できるよう保存する。
nonisolated struct RunningSessionMarker: Codable, Hashable, Sendable {
    /// 実行の識別子。完了時にそのまま完了記録の id になる。
    let sessionID: UUID
    let habitID: UUID
    let startedAt: Date
}
