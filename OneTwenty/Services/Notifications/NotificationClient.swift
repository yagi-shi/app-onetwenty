import Foundation
import UserNotifications

/// 通知センターの窓口。判定は持たず、呼び出しをそのまま OS に渡す。
protocol NotificationClient {
    func authorizationStatus() async -> NotificationAuthorization
    func requestAuthorization() async -> NotificationAuthorization
    /// 予約済みで未発火の通知のうち、識別子が `prefix` で始まるもの。
    func pendingIdentifiers(prefix: String) async -> [String]
    func add(_ request: LocalNotificationRequest) async throws
    func remove(identifiers: [String])
}

final class UserNotificationClient: NSObject, NotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func authorizationStatus() async -> NotificationAuthorization {
        NotificationAuthorization(await center.notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorizationStatus()
    }

    func pendingIdentifiers(prefix: String) async -> [String] {
        await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }
    }

    func add(_ request: LocalNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.body = request.body
        content.sound = .default

        let trigger: UNNotificationTrigger
        switch request.trigger {
        case .calendar(let components):
            trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        case .date(let date):
            // 過去や直近すぎる時刻は予約できないので、最短でも 1 秒後にする
            trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(1, date.timeIntervalSinceNow),
                repeats: false
            )
        }
        try await center.add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        ))
    }

    /// 識別子を指定して取り消す。すべての予約をまとめて消す API は使わない。
    func remove(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// アプリを開いている間に届いた通知を表示するかどうか。
    /// タイマーの完了はアプリ内の表示で伝えるので、完了通知は重ねて出さない。
    nonisolated static func presentationOptions(forIdentifier identifier: String) -> UNNotificationPresentationOptions {
        identifier.hasPrefix(NotificationIdentifier.timerPrefix) ? [] : [.banner, .list, .sound]
    }
}

extension UserNotificationClient: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentationOptions(forIdentifier: notification.request.identifier)
    }
}

extension NotificationAuthorization {
    /// 仮の許可（目立たない形での配信）も、予約できるので許可として扱う。
    nonisolated init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .authorized
        @unknown default: self = .denied
        }
    }
}
