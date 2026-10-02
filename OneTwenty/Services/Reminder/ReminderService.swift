import Foundation
import os

/// リマインダーの予約を、あるべき状態にそろえる。
/// 予約の状態を変える経路は `sync()` だけにする。
final class ReminderService {
    /// 最後に取得した通知の許可状態。設定画面の表示に使う。
    private(set) var authorization: NotificationAuthorization = .notDetermined

    private let notifications: NotificationClient
    private let settings: SettingsStore
    private let habits: HabitRepository
    private let sessions: SessionRepository
    private let pending: PendingCompletionsReading
    private let clock: WallClock
    private var lastSync: Task<Void, Never>?

    init(
        notifications: NotificationClient,
        settings: SettingsStore,
        habits: HabitRepository,
        sessions: SessionRepository,
        pending: PendingCompletionsReading,
        clock: WallClock
    ) {
        self.notifications = notifications
        self.settings = settings
        self.habits = habits
        self.sessions = sessions
        self.pending = pending
        self.clock = clock
    }

    /// 予約すべきリマインダーと予約済みのリマインダーを比べ、差分だけを追加・取消する。
    /// 追加に失敗した日があっても、次の同期で足りない分として再び追加される。
    func sync() async {
        // 同期が重なると、古い計画で新しい計画を上書きしうるので、呼ばれた順に 1 つずつ実行する
        let previous = lastSync
        let task = Task {
            await previous?.value
            await performSync()
        }
        lastSync = task
        await task.value
    }

    func setReminderTime(_ time: ReminderTime) async {
        settings.reminderTime = time
        await sync()
    }

    func setReminderEnabled(_ enabled: Bool) async {
        settings.reminderEnabled = enabled
        await sync()
    }

    @discardableResult
    func refreshAuthorization() async -> NotificationAuthorization {
        authorization = await notifications.authorizationStatus()
        return authorization
    }

    private func performSync() async {
        // 許可を求めた直後に呼ばれることがあるので、保持している値は使わず毎回取得し直す
        let authorization = await refreshAuthorization()
        let calendar = clock.calendar
        let planned = ReminderPlanner.plan(
            now: clock.now,
            calendar: calendar,
            time: settings.reminderTime,
            enabled: settings.reminderEnabled,
            authorization: authorization,
            activeHabitCount: habits.activeHabits().count,
            todayAllCompleted: todayStatus().allCompleted
        )

        let scheduled = Set(await notifications.pendingIdentifiers(prefix: NotificationIdentifier.reminderPrefix))
        let wanted = Set(planned.map(\.identifier))

        notifications.remove(identifiers: Array(scheduled.subtracting(wanted)))

        for reminder in planned where !scheduled.contains(reminder.identifier) {
            var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute], from: reminder.fireDate)
            components.calendar = calendar
            do {
                try await notifications.add(LocalNotificationRequest(
                    identifier: reminder.identifier,
                    body: NotificationText.reminderBody,
                    trigger: .calendar(components)
                ))
            } catch {
                Log.notification.error("リマインダーを予約できない（次の同期でやり直す）: \(error)")
            }
        }
    }

    /// 今日の完了状態。保存待ちの実行も完了として数える。
    private func todayStatus() -> DailyStatus {
        let calendar = clock.calendar
        let today = DayKey(clock.now, calendar: calendar)
        let todaySessions = sessions.sessions(
            from: today.startOfDay(calendar: calendar),
            to: today.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
        )
        return DailyStatusResolver.status(
            activeHabits: habits.activeHabits(),
            sessions: todaySessions,
            pending: pending.pendingCompletions(),
            day: today,
            calendar: calendar
        )
    }
}
