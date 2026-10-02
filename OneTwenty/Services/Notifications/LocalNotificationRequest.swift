import Foundation

/// 予約するローカル通知。
nonisolated struct LocalNotificationRequest: Equatable, Sendable {
    enum Trigger: Equatable, Sendable {
        /// 現地の日時で発火する（リマインダー）。端末のタイムゾーンが変わっても、現地のその時刻に届く。
        case calendar(DateComponents)
        /// 指定した時刻ちょうどに発火する（タイマーの完了通知）。
        case date(Date)
    }

    let identifier: String
    let body: String
    let trigger: Trigger
}

/// 通知の識別子。種類ごとに接頭辞を分け、取消は必ず接頭辞で絞り込んで行う。
/// リマインダーをオフにしたときに、実行中のタイマーの完了通知まで消さないため。
nonisolated enum NotificationIdentifier {
    static let reminderPrefix = ReminderPlanner.identifierPrefix
    static let timerPrefix = "timer."

    static func timer(sessionID: UUID) -> String {
        timerPrefix + sessionID.uuidString
    }
}

/// 通知の本文。習慣名・残り件数・連続日数は含めない固定の文言。
enum NotificationText {
    static var reminderBody: String {
        String(localized: "notification.reminder.body", defaultValue: "Just two minutes.")
    }

    /// 通知が届いた時点では記録がまだ確定していないので、「完了した」とは言わず、経過の事実だけを伝える。
    static var timerBody: String {
        String(localized: "notification.timer.body", defaultValue: "Two minutes have passed.")
    }
}
