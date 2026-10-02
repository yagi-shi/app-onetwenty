import Foundation
import SwiftData
import Testing
@testable import OneTwenty

@MainActor
struct ReminderServiceTests {
    private let container: ModelContainer
    private let habits: SwiftDataHabitRepository
    private let sessions: SwiftDataSessionRepository
    private let isolated = IsolatedDefaults()
    private let settings: UserDefaultsSettingsStore
    private let runningStore: UserDefaultsRunningSessionStore
    private let notifications = FakeNotificationClient()
    private let clock: TestClock
    private let service: ReminderService
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")

    private static let todayIdentifier = "reminder.2026-10-01.0800"

    /// 既定では 2026/10/1 の 7:59（東京）。通知時刻 8:00 の直前。
    init() throws {
        container = try PersistentStore.makeContainer(inMemory: true)
        habits = SwiftDataHabitRepository(context: container.mainContext)
        sessions = SwiftDataSessionRepository(context: container.mainContext)
        settings = UserDefaultsSettingsStore(defaults: isolated.defaults)
        runningStore = UserDefaultsRunningSessionStore(defaults: isolated.defaults)
        clock = TestClock(now: TestCalendars.date(2026, 10, 1, 7, 59, in: calendar), calendar: calendar)
        service = ReminderService(
            notifications: notifications,
            settings: settings,
            habits: habits,
            sessions: sessions,
            pending: runningStore,
            clock: clock
        )
    }

    @discardableResult
    private func addHabit(_ title: String = "本を1ページ読む", order: Int = 0) throws -> HabitSnapshot {
        let habit = HabitSnapshot.fixture(title: title, order: order)
        try habits.insert(habit)
        return habit
    }

    /// 今日の完了記録を追加する。
    private func complete(_ habit: HabitSnapshot) throws {
        let today = DayKey(clock.now, calendar: calendar)
        let range = today.startOfDay(calendar: calendar)..<today.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
        _ = try sessions.insertIfAbsent(
            .fixture(habitID: habit.id, startedAt: clock.now.addingTimeInterval(-600)),
            sameDayRange: range
        )
    }

    private var reminderIdentifiers: Set<String> {
        notifications.pendingIdentifiers.filter { $0.hasPrefix("reminder.") }
    }

    // MARK: 予約

    @Test("許可済み・オン・習慣 1 件以上なら、60 日分を予約する")
    func schedulesSixtyDays() async throws {
        try addHabit()

        await service.sync()

        #expect(reminderIdentifiers.count == 60)
        #expect(reminderIdentifiers.contains(Self.todayIdentifier))
        #expect(reminderIdentifiers.contains("reminder.2026-11-29.0800"))
        #expect(!reminderIdentifiers.contains("reminder.2026-11-30.0800"))
    }

    @Test("予約済みの状態でもう一度同期しても、何も追加・取消しない")
    func secondSyncChangesNothing() async throws {
        try addHabit()
        await service.sync()
        notifications.resetCallHistory()

        await service.sync()

        #expect(notifications.addedIdentifiers.isEmpty)
        #expect(notifications.removedIdentifiers.isEmpty)
        #expect(reminderIdentifiers.count == 60)
    }

    @Test("日が変わったら、過ぎた日を外し、足りない 1 日分だけを補充する")
    func refillsAfterDayChange() async throws {
        try addHabit()
        await service.sync()
        notifications.resetCallHistory()
        clock.now = TestCalendars.date(2026, 10, 2, 7, 59, in: calendar)

        await service.sync()

        #expect(notifications.addedIdentifiers == ["reminder.2026-11-30.0800"])
        #expect(notifications.removedIdentifiers == [Self.todayIdentifier])
        #expect(reminderIdentifiers.count == 60)
    }

    @Test("通知の本文は固定の文言で、習慣名を含まず、現地の指定時刻に発火する")
    func requestContents() async throws {
        try addHabit("本を1ページ読む")

        await service.sync()

        for request in notifications.pending {
            #expect(request.body == NotificationText.reminderBody)
            #expect(!request.body.contains("本を1ページ読む"))
            guard case .calendar(let components) = request.trigger else {
                Issue.record("リマインダーは現地の日時で予約するはず")
                continue
            }
            #expect(components.hour == 8 && components.minute == 0)
            #expect(components.calendar?.timeZone.identifier == "Asia/Tokyo")
        }
        let today = notifications.pending.first { $0.identifier == Self.todayIdentifier }
        guard case .calendar(let components) = today?.trigger else {
            Issue.record("今日の分が予約されているはず")
            return
        }
        #expect(components.year == 2026 && components.month == 10 && components.day == 1)
    }

    // MARK: 予約しない条件

    @Test("習慣が 0 件なら予約せず、残っていた予約もすべて取り消す")
    func noHabits() async throws {
        notifications.seed(LocalNotificationRequest(identifier: "reminder.2026-09-30.0800", body: "", trigger: .date(clock.now)))

        await service.sync()

        #expect(reminderIdentifiers.isEmpty)
    }

    @Test("習慣をすべてアーカイブしたら、リマインダーをすべて取り消す。登録し直すと再び予約する")
    func archivingAllHabitsCancelsReminders() async throws {
        let habit = try addHabit()
        await service.sync()
        #expect(reminderIdentifiers.count == 60)

        try habits.archive(id: habit.id, at: clock.now)
        await service.sync()
        #expect(reminderIdentifiers.isEmpty)

        try addHabit("靴を履く")
        await service.sync()
        #expect(reminderIdentifiers.count == 60)
    }

    @Test("リマインダーをオフにすると全て取り消し、オンに戻すと予約し直す")
    func togglingEnabled() async throws {
        try addHabit()
        await service.sync()

        await service.setReminderEnabled(false)
        #expect(reminderIdentifiers.isEmpty)
        #expect(settings.reminderEnabled == false)

        await service.setReminderEnabled(true)
        #expect(reminderIdentifiers.count == 60)
        #expect(settings.reminderEnabled == true)
    }

    @Test("タイマーの完了通知には、どの操作でも触れない")
    func neverTouchesTimerNotifications() async throws {
        let timerIdentifier = NotificationIdentifier.timer(sessionID: UUID())
        notifications.seed(LocalNotificationRequest(
            identifier: timerIdentifier,
            body: NotificationText.timerBody,
            trigger: .date(clock.now.addingTimeInterval(120))
        ))
        let habit = try addHabit()

        await service.sync()
        await service.setReminderTime(ReminderTime(hour: 21, minute: 0))
        await service.setReminderEnabled(false)
        await service.setReminderEnabled(true)
        try habits.archive(id: habit.id, at: clock.now)
        await service.sync()

        #expect(reminderIdentifiers.isEmpty)
        #expect(notifications.pendingIdentifiers == [timerIdentifier])
        #expect(!notifications.removedIdentifiers.contains(timerIdentifier))
        #expect(notifications.removedIdentifiers.allSatisfy { $0.hasPrefix("reminder.") })
    }

    // MARK: 通知時刻の変更

    @Test("通知時刻を変えると、古い時刻の予約が消え、新しい時刻の予約に入れ替わる")
    func changingTimeReplacesReminders() async throws {
        try addHabit()
        await service.sync()

        await service.setReminderTime(ReminderTime(hour: 21, minute: 30))

        #expect(settings.reminderTime == ReminderTime(hour: 21, minute: 30))
        #expect(reminderIdentifiers.count == 60)
        #expect(reminderIdentifiers.allSatisfy { $0.hasSuffix(".2130") })
        #expect(reminderIdentifiers.contains("reminder.2026-10-01.2130"))
    }

    // MARK: 許可状態

    @Test("通知が拒否されていれば予約せず、許可に変わった後の同期で予約する")
    func deniedThenAuthorized() async throws {
        try addHabit()
        notifications.authorization = .denied

        await service.sync()
        #expect(reminderIdentifiers.isEmpty)
        #expect(service.authorization == .denied)

        notifications.authorization = .authorized
        await service.sync()
        #expect(reminderIdentifiers.count == 60)
        #expect(service.authorization == .authorized)
    }

    @Test("未決定の状態から許可が下りた直後の同期で、60 日分を予約する")
    func schedulesRightAfterPermissionIsGranted() async throws {
        try addHabit()
        notifications.authorization = .notDetermined
        await service.sync()
        #expect(reminderIdentifiers.isEmpty)
        #expect(service.authorization == .notDetermined)

        // 別の処理（習慣の登録やタイマーの開始）が許可を求め、ユーザーが許可した
        _ = await notifications.requestAuthorization()
        await service.sync()

        #expect(reminderIdentifiers.count == 60)
    }

    @Test("許可状態の再取得は、取得した値を返し、保持する")
    func refreshAuthorization() async {
        notifications.authorization = .denied

        let result = await service.refreshAuthorization()

        #expect(result == .denied)
        #expect(service.authorization == .denied)
    }

    // MARK: 当日の完了

    @Test("今日の習慣がすべて完了したら、今日の分だけを取り消す")
    func cancelsTodayWhenAllCompleted() async throws {
        let first = try addHabit("本を1ページ読む", order: 0)
        let second = try addHabit("靴を履く", order: 1)
        await service.sync()
        notifications.resetCallHistory()

        try complete(first)
        await service.sync()
        #expect(reminderIdentifiers.count == 60)

        try complete(second)
        await service.sync()
        #expect(notifications.removedIdentifiers == [Self.todayIdentifier])
        #expect(reminderIdentifiers.count == 59)
    }

    @Test("保存待ちが残っている習慣も完了として数え、今日の分を取り消す")
    func pendingCompletionCountsAsCompleted() async throws {
        let first = try addHabit("本を1ページ読む", order: 0)
        let second = try addHabit("靴を履く", order: 1)
        await service.sync()
        try complete(first)
        runningStore.addPending(RunningSessionMarker(
            sessionID: UUID(),
            habitID: second.id,
            startedAt: clock.now.addingTimeInterval(-300)
        ))

        await service.sync()

        #expect(!reminderIdentifiers.contains(Self.todayIdentifier))
        #expect(reminderIdentifiers.count == 59)
    }

    @Test("前日の完了記録は、今日の完了には数えない")
    func yesterdaysSessionDoesNotCount() async throws {
        let habit = try addHabit()
        let yesterday = TestCalendars.date(2026, 9, 30, 20, in: calendar)
        _ = try sessions.insertIfAbsent(
            .fixture(habitID: habit.id, startedAt: yesterday),
            sameDayRange: TestCalendars.date(2026, 9, 30, in: calendar)..<TestCalendars.date(2026, 10, 1, in: calendar)
        )

        await service.sync()

        #expect(reminderIdentifiers.contains(Self.todayIdentifier))
    }

    // MARK: 失敗と同時実行

    @Test("予約に失敗した日は、次の同期でその分だけ追加し直す")
    func retriesFailedReminders() async throws {
        try addHabit()
        let failing: Set = [Self.todayIdentifier, "reminder.2026-10-15.0800"]
        notifications.failingIdentifiers = failing

        await service.sync()
        #expect(reminderIdentifiers.count == 58)
        #expect(reminderIdentifiers.isDisjoint(with: failing))

        notifications.failingIdentifiers = []
        notifications.resetCallHistory()
        await service.sync()

        #expect(Set(notifications.addedIdentifiers) == failing)
        #expect(reminderIdentifiers.count == 60)
    }

    @Test("同期が同時に呼ばれても、同じ日を二重に予約しない")
    func concurrentSyncs() async throws {
        try addHabit()

        async let first: Void = service.sync()
        async let second: Void = service.sync()
        _ = await (first, second)

        #expect(reminderIdentifiers.count == 60)
        #expect(notifications.addedIdentifiers.count == 60)
    }
}
