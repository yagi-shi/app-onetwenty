import Foundation
import SwiftData
import Testing
@testable import OneTwenty

@MainActor
struct AppEnvironmentTests {
    private let isolated = IsolatedDefaults()
    private let notifications = FakeNotificationClient()
    private let liveActivity = FakeLiveActivityClient()
    private let clock = TestClock(
        now: TestCalendars.date(2026, 10, 1, 7, 59, in: TestCalendars.gregorian("Asia/Tokyo")),
        calendar: TestCalendars.gregorian("Asia/Tokyo")
    )

    /// データを保存する場所を開けるかどうかを切り替えられる。
    @MainActor
    private final class ContainerSource {
        struct Failure: Error {}
        var fails = false
        private(set) var attempts = 0

        func make() throws -> ModelContainer {
            attempts += 1
            if fails { throw Failure() }
            return try PersistentStore.makeContainer(inMemory: true)
        }
    }

    private func makeEnvironment(_ source: ContainerSource) -> AppEnvironment {
        AppEnvironment(dependencies: AppEnvironment.Dependencies(
            makeContainer: { try source.make() },
            defaults: isolated.defaults,
            notifications: notifications,
            liveActivity: liveActivity,
            feedback: FakeFeedbackPlayer(),
            clock: clock,
            contentLoader: ContentLoader(),
            preferredLocalization: "ja",
            prefersReducedMotion: { false }
        ))
    }

    private func readyCoordinator(of environment: AppEnvironment) -> AppCoordinator? {
        if case .ready(let coordinator) = environment.rootState { return coordinator }
        return nil
    }

    @Test("データを保存する場所を開けたら、調停役を組み立てる")
    func readyWhenContainerOpens() throws {
        let environment = makeEnvironment(ContainerSource())

        let coordinator = try #require(readyCoordinator(of: environment))
        #expect(coordinator.route == .onboarding)
    }

    @Test("オンボーディングを見終えている場合は、ホームから始まる")
    func routeFromStoredFlag() throws {
        UserDefaultsSettingsStore(defaults: isolated.defaults).onboardingCompleted = true

        let environment = makeEnvironment(ContainerSource())

        #expect(try #require(readyCoordinator(of: environment)).route == .home)
    }

    @Test("組み立てた後も、データベースを保持し続けていて読み書きできる")
    func keepsContainerAlive() async throws {
        // 組み立てに使ったデータベースを手放すと、最初の読み込みでアプリが落ちる
        let environment = makeEnvironment(ContainerSource())
        let coordinator = try #require(readyCoordinator(of: environment))
        let home = environment.makeHomeViewModel()

        home.reload(displayDay: coordinator.displayDay)
        await coordinator.activate()

        #expect(home.rows.isEmpty)
        #expect(home.placeholderCount == 3)
    }

    @Test("ホームの「＋」は、新規登録のウィザードの表示につながっている")
    func homeIsWiredToCoordinator() throws {
        let environment = makeEnvironment(ContainerSource())
        let coordinator = try #require(readyCoordinator(of: environment))

        environment.makeHomeViewModel().tapPlaceholder()

        #expect(coordinator.presentedWizard?.mode == .new(origin: .home))
    }

    @Test("設定の画面は、テーマ・習慣の変更・名前の変更を調停役につないでいる")
    func settingsAreWiredToCoordinator() async throws {
        let environment = makeEnvironment(ContainerSource())
        let coordinator = try #require(readyCoordinator(of: environment))
        let settings = environment.makeSettingsViewModel()

        settings.setTheme(.dark)
        #expect(coordinator.theme == .dark)

        coordinator.presentWizard(mode: .new(origin: .home))
        let wizard = try #require(coordinator.presentedWizard?.viewModel)
        // 同梱のテンプレートのどのキーワードにも一致しない文（一致すると、テンプレートの提示に進む）
        wizard.text = "窓を開ける"
        await wizard.submit()
        await wizard.answerTwoMinute(true)
        settings.reload()
        let habit = try #require(settings.habits.first)

        settings.rename(habit)
        #expect(coordinator.presentedWizard?.mode == .edit(habitID: habit.id, currentTitle: "窓を開ける"))
        coordinator.presentedWizard?.viewModel.cancel()

        let version = coordinator.dataVersion
        settings.requestArchive(habit)
        await settings.confirmArchive()
        #expect(coordinator.dataVersion == version + 1)
    }

    @Test("オンボーディングを見終えると、ホームに切り替わり、新規登録のウィザードが開く。キャンセルすればホームのまま")
    func onboardingIsWiredToCoordinator() throws {
        let environment = makeEnvironment(ContainerSource())
        let coordinator = try #require(readyCoordinator(of: environment))
        let onboarding = environment.makeOnboardingViewModel()

        onboarding.next()
        onboarding.finish()

        #expect(coordinator.route == .home)
        #expect(coordinator.presentedWizard?.mode == .new(origin: .onboarding))

        coordinator.presentedWizard?.viewModel.cancel()
        #expect(coordinator.presentedWizard == nil)
        #expect(coordinator.route == .home)
        // 次に起動してもオンボーディングは出ない
        #expect(makeEnvironment(ContainerSource()).rootState.coordinatorRoute == .home)
    }

    @Test("データを保存する場所を開けなければ、調停役を組み立てない")
    func storeUnavailable() {
        let source = ContainerSource()
        source.fails = true

        let environment = makeEnvironment(source)

        #expect(readyCoordinator(of: environment) == nil)
        #expect(source.attempts == 1)
    }

    @Test("再試行しても開けなければ、開けない状態のまま留まる")
    func retryStillFailing() async {
        let source = ContainerSource()
        source.fails = true
        let environment = makeEnvironment(source)

        await environment.retryContainer()

        #expect(readyCoordinator(of: environment) == nil)
        #expect(source.attempts == 2)
    }

    @Test("再試行で開けたら、調停役を組み立て、起動直後と同じ処理を行う")
    func retrySucceeds() async throws {
        // 120 秒未満の実行中の印と、取り残された Live Activity が残っている状態
        let store = UserDefaultsRunningSessionStore(defaults: isolated.defaults)
        store.save(RunningSessionMarker(sessionID: UUID(), habitID: UUID(), startedAt: clock.now.addingTimeInterval(-60)))
        liveActivity.seed(ActivitySnapshot(activityID: "取り残し", sessionID: UUID(), endsAt: clock.now.addingTimeInterval(60)))
        let source = ContainerSource()
        source.fails = true
        let environment = makeEnvironment(source)

        source.fails = false
        await environment.retryContainer()

        #expect(try #require(readyCoordinator(of: environment)).route == .onboarding)
        // 起動として扱うので、120 秒未満の実行は計測を続けずに破棄する
        #expect(store.load() == nil)
        #expect(liveActivity.currentActivities().isEmpty)
    }

    @Test("既に開けている場合、再試行は何もしない")
    func retryWhenReadyDoesNothing() async throws {
        let source = ContainerSource()
        let environment = makeEnvironment(source)
        let before = try #require(readyCoordinator(of: environment))

        await environment.retryContainer()

        #expect(readyCoordinator(of: environment) === before)
        #expect(source.attempts == 1)
    }
}

private extension AppEnvironment.RootState {
    var coordinatorRoute: AppCoordinator.Route? {
        if case .ready(let coordinator) = self { return coordinator.route }
        return nil
    }
}
