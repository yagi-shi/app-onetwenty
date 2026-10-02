import Foundation
import Testing
import UserNotifications
@testable import OneTwenty

struct NotificationClientTests {

    @Test("アプリを開いている間、タイマーの完了通知は表示しない")
    func suppressesTimerNotificationInForeground() {
        let identifier = NotificationIdentifier.timer(sessionID: UUID())

        #expect(UserNotificationClient.presentationOptions(forIdentifier: identifier).isEmpty)
    }

    @Test("アプリを開いている間でも、リマインダーは通常どおり表示する")
    func presentsReminderInForeground() {
        let options = UserNotificationClient.presentationOptions(forIdentifier: "reminder.2026-10-01.0800")

        #expect(options.contains(.banner))
        #expect(options.contains(.sound))
    }

    @Test("リマインダーとタイマーの完了通知は、識別子の接頭辞で区別できる")
    func identifierPrefixes() {
        let sessionID = UUID()

        #expect(NotificationIdentifier.reminderPrefix == "reminder.")
        #expect(NotificationIdentifier.timerPrefix == "timer.")
        #expect(NotificationIdentifier.timer(sessionID: sessionID) == "timer.\(sessionID.uuidString)")
        #expect(!NotificationIdentifier.timer(sessionID: sessionID).hasPrefix(NotificationIdentifier.reminderPrefix))
    }

    @Test("OS の許可状態を 3 つに畳む。仮の許可も許可として扱う", arguments: [
        (UNAuthorizationStatus.notDetermined, NotificationAuthorization.notDetermined),
        (.denied, .denied),
        (.authorized, .authorized),
        (.provisional, .authorized),
        (.ephemeral, .authorized),
    ])
    func mapsAuthorizationStatus(status: UNAuthorizationStatus, expected: NotificationAuthorization) {
        #expect(NotificationAuthorization(status) == expected)
    }
}

@MainActor
struct NotificationTextTests {

    @Test("通知の本文は固定の文言で、差し込みの箇所を持たない")
    func bodiesAreFixedText() {
        for body in [NotificationText.reminderBody, NotificationText.timerBody] {
            #expect(!body.isEmpty)
            #expect(!body.contains("%"))
            #expect(!body.contains("{"))
        }
    }
}
