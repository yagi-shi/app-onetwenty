import Foundation
import Observation
import os
import SwiftData
import UIKit

/// アプリの部品を組み立てる場所。具体的な実装（SwiftData、通知センター など）を知っているのはここだけ。
@Observable
final class AppEnvironment {
    enum RootState {
        /// データを保存する場所を開けなかった。
        case storeUnavailable
        case ready(AppCoordinator)
    }

    /// OS や保存先とのつなぎ目。テストでは偽物に差し替える。
    struct Dependencies {
        var makeContainer: () throws -> ModelContainer
        var defaults: UserDefaults
        var notifications: NotificationClient
        var liveActivity: LiveActivityClient
        var feedback: FeedbackPlayer
        var clock: WallClock
        var contentLoader: ContentLoader
        var preferredLocalization: String?
        var prefersReducedMotion: () -> Bool
    }

    private(set) var rootState: RootState = .storeUnavailable

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var services: Services?

    /// データを保存する場所を開けた後にだけ組み立てられる部品。
    private struct Services {
        /// 読み書きの窓口（`ModelContext`）はデータベース本体を保持しないので、ここで保持し続ける。
        /// 手放すと、次の読み書きでアプリが落ちる。
        let container: ModelContainer
        let habits: HabitRepository
        let sessions: SessionRepository
        let settings: SettingsStore
        let reminders: ReminderService
        let sessionService: SessionService
        let habitService: HabitService
        let clock: WallClock
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
        assemble()
    }

    static func live() -> AppEnvironment {
        AppEnvironment(dependencies: Dependencies(
            makeContainer: { try PersistentStore.makeContainer() },
            defaults: .standard,
            notifications: UserNotificationClient(),
            liveActivity: ActivityKitLiveActivityClient(),
            feedback: SystemFeedbackPlayer(),
            clock: SystemClock(),
            contentLoader: ContentLoader(),
            preferredLocalization: Bundle.main.preferredLocalizations.first,
            prefersReducedMotion: { UIAccessibility.isReduceMotionEnabled }
        ))
    }

    /// データを保存する場所をもう一度開いてみる。開けたら、起動直後と同じ処理を行う。
    func retryContainer() async {
        guard case .storeUnavailable = rootState else { return }
        assemble()
        if case .ready(let coordinator) = rootState {
            await coordinator.activate()
        }
    }

    func makeHomeViewModel() -> HomeViewModel {
        let (services, coordinator) = assembled()
        let viewModel = HomeViewModel(
            habits: services.habits,
            sessions: services.sessions,
            sessionService: services.sessionService,
            clock: services.clock
        )
        viewModel.onStartTimer = { [weak coordinator] marker in
            coordinator?.presentTimer(marker: marker)
        }
        viewModel.onAddHabit = { [weak coordinator] in
            coordinator?.presentWizard(mode: .new(origin: .home))
        }
        return viewModel
    }

    func makeStatsViewModel() -> StatsViewModel {
        let (services, _) = assembled()
        return StatsViewModel(habits: services.habits, sessions: services.sessions, clock: services.clock)
    }

    func makeSettingsViewModel() -> SettingsViewModel {
        let (services, coordinator) = assembled()
        let viewModel = SettingsViewModel(
            habits: services.habits,
            habitService: services.habitService,
            reminders: services.reminders,
            settings: services.settings
        )
        viewModel.onThemeChanged = { [weak coordinator] in
            coordinator?.themeDidChange()
        }
        viewModel.onHabitsChanged = { [weak coordinator] in
            coordinator?.habitsDidChange()
        }
        viewModel.onRename = { [weak coordinator] habit in
            coordinator?.presentWizard(mode: .edit(habitID: habit.id, currentTitle: habit.title))
        }
        return viewModel
    }

    func makeOnboardingViewModel() -> OnboardingViewModel {
        let (services, coordinator) = assembled()
        let viewModel = OnboardingViewModel(settings: services.settings)
        viewModel.onFinished = { [weak coordinator] in
            coordinator?.onboardingDidFinish()
        }
        return viewModel
    }

    private func assembled() -> (Services, AppCoordinator) {
        guard let services, case .ready(let coordinator) = rootState else {
            preconditionFailure("データを保存する場所を開けていない状態で画面を作ろうとした")
        }
        return (services, coordinator)
    }

    /// 保存する場所を開き、その上に部品を組み立てる。開けなければ何も組み立てない。
    private func assemble() {
        let container: ModelContainer
        do {
            container = try dependencies.makeContainer()
        } catch {
            Log.data.error("データを保存する場所を開けない: \(error)")
            rootState = .storeUnavailable
            return
        }

        let clock = dependencies.clock
        let habits = SwiftDataHabitRepository(context: container.mainContext)
        let sessions = SwiftDataSessionRepository(context: container.mainContext)
        let settings = UserDefaultsSettingsStore(defaults: dependencies.defaults)
        let runningStore = UserDefaultsRunningSessionStore(defaults: dependencies.defaults)
        let reminders = ReminderService(
            notifications: dependencies.notifications,
            settings: settings,
            habits: habits,
            sessions: sessions,
            pending: runningStore,
            clock: clock
        )
        let sessionService = SessionService(
            sessions: sessions,
            habits: habits,
            store: runningStore,
            notifications: dependencies.notifications,
            liveActivity: dependencies.liveActivity,
            feedback: dependencies.feedback,
            reminders: reminders,
            clock: clock
        )

        let habitService = HabitService(
            habits: habits,
            notifications: dependencies.notifications,
            reminders: reminders,
            clock: clock
        )

        let language = LanguageResolver.resolve(preferredLocalization: dependencies.preferredLocalization)
        let content = dependencies.contentLoader.load(language: language)

        let coordinator = AppCoordinator(
            sessionService: sessionService,
            reminders: reminders,
            settings: settings,
            clock: clock,
            makeTimerViewModel: { marker, previousMessage in
                TimerViewModel(
                    marker: marker,
                    sessionService: sessionService,
                    clock: clock,
                    messages: content.completionMessages,
                    previousMessage: previousMessage
                )
            },
            makeWizardViewModel: { mode in
                WizardViewModel(mode: mode, habitService: habitService, language: language, content: content)
            },
            prefersReducedMotion: dependencies.prefersReducedMotion
        )

        services = Services(
            container: container,
            habits: habits,
            sessions: sessions,
            settings: settings,
            reminders: reminders,
            sessionService: sessionService,
            habitService: habitService,
            clock: clock
        )
        rootState = .ready(coordinator)
    }
}
