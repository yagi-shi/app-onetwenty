import Foundation
import SwiftData
@testable import OneTwenty

/// サービス層のテストで使う部品一式。
/// 保存はメモリ上のデータベース、OS とのやりとりは偽物に差し替えてある。
@MainActor
final class ServiceHarness {
    let calendar = TestCalendars.gregorian("Asia/Tokyo")
    let container: ModelContainer
    let habitStore: SwiftDataHabitRepository
    let habits: FailingHabitRepository
    let sessions: FailingSessionRepository
    let isolated = IsolatedDefaults()
    let settings: UserDefaultsSettingsStore
    let runningStore: UserDefaultsRunningSessionStore
    let notifications = FakeNotificationClient()
    let liveActivity = FakeLiveActivityClient()
    let feedback = FakeFeedbackPlayer()
    let clock: TestClock
    let reminders: ReminderService
    let sessionService: SessionService
    let habitService: HabitService

    /// 既定の現在時刻は 2026/10/1 の 7:59（東京）。
    init() throws {
        container = try PersistentStore.makeContainer(inMemory: true)
        habitStore = SwiftDataHabitRepository(context: container.mainContext)
        habits = FailingHabitRepository(wrapping: habitStore)
        sessions = FailingSessionRepository(wrapping: SwiftDataSessionRepository(context: container.mainContext))
        settings = UserDefaultsSettingsStore(defaults: isolated.defaults)
        runningStore = UserDefaultsRunningSessionStore(defaults: isolated.defaults)
        clock = TestClock(now: TestCalendars.date(2026, 10, 1, 7, 59, in: calendar), calendar: calendar)
        reminders = ReminderService(
            notifications: notifications,
            settings: settings,
            habits: habits,
            sessions: sessions,
            pending: runningStore,
            clock: clock
        )
        sessionService = SessionService(
            sessions: sessions,
            habits: habits,
            store: runningStore,
            notifications: notifications,
            liveActivity: liveActivity,
            feedback: feedback,
            reminders: reminders,
            clock: clock
        )
        habitService = HabitService(habits: habits, notifications: notifications, reminders: reminders, clock: clock)
    }

    /// 完了文言の表示時間（2.5 秒）を、テストが終わらせるまで待たせる。
    let sleeper = ControlledSleeper()
    var completionMessages = ["2分、終わりました。", "今日の分はここまで。"]

    func makeTimerViewModel(marker: RunningSessionMarker, previousMessage: String? = nil) -> TimerViewModel {
        TimerViewModel(
            marker: marker,
            sessionService: sessionService,
            clock: clock,
            messages: completionMessages,
            previousMessage: previousMessage,
            rng: SeededGenerator(seed: 1),
            sleep: { [sleeper] in await sleeper.sleep($0) }
        )
    }

    func makeCoordinator(prefersReducedMotion: Bool = false) -> AppCoordinator {
        AppCoordinator(
            sessionService: sessionService,
            reminders: reminders,
            settings: settings,
            clock: clock,
            makeTimerViewModel: { [unowned self] marker, previousMessage in
                makeTimerViewModel(marker: marker, previousMessage: previousMessage)
            },
            makeWizardViewModel: { [unowned self] mode in
                makeWizardViewModel(mode: mode)
            },
            prefersReducedMotion: { prefersReducedMotion }
        )
    }

    /// ウィザードで使う検出語とテンプレート（日本語）。
    var wizardContent = ContentBundle(
        templates: [TemplateCategory(id: "reading", keywords: ["読書"], templates: ["本を開く"])],
        terms: DetectionTerms(frequencyAdverbs: ["毎日"], goalSuffixes: ["を続ける"]),
        completionMessages: []
    )

    func makeWizardViewModel(mode: WizardStateMachine.Mode) -> WizardViewModel {
        WizardViewModel(mode: mode, habitService: habitService, language: .ja, content: wizardContent)
    }

    func makeHomeViewModel() -> HomeViewModel {
        HomeViewModel(habits: habits, sessions: sessions, sessionService: sessionService, clock: clock)
    }

    /// 指定した日に完了記録を追加する（開始はその日の 12:00）。
    func addSession(for habit: HabitSnapshot, on day: DayKey) throws {
        let start = day.startOfDay(calendar: calendar)
        _ = try sessions.insertIfAbsent(
            .fixture(habitID: habit.id, startedAt: start.addingTimeInterval(12 * 3_600)),
            sameDayRange: start..<day.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
        )
    }

    /// サービスを通さずに、習慣を直接追加する。
    @discardableResult
    func addHabit(_ title: String = "本を1ページ読む", order: Int? = nil) throws -> HabitSnapshot {
        let habit = HabitSnapshot.fixture(
            title: title,
            createdAt: clock.now.addingTimeInterval(-86_400 * 30),
            order: order ?? habitStore.activeHabits().count
        )
        try habitStore.insert(habit)
        return habit
    }

    var today: DayKey {
        DayKey(clock.now, calendar: calendar)
    }

    var reminderIdentifiers: Set<String> {
        notifications.pendingIdentifiers.filter { $0.hasPrefix("reminder.") }
    }

    var timerIdentifiers: Set<String> {
        notifications.pendingIdentifiers.filter { $0.hasPrefix("timer.") }
    }

    /// 今日のリマインダーの識別子（通知時刻は既定の 8:00）。
    var todayReminderIdentifier: String {
        String(format: "reminder.%04d-%02d-%02d.0800", today.year, today.month, today.day)
    }
}
