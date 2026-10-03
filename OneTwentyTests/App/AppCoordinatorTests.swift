import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct AppCoordinatorTests {
    private let h: ServiceHarness
    private let habit: HabitSnapshot

    init() throws {
        h = try ServiceHarness()
        habit = try h.addHabit()
    }

    /// タイマーを開始し、タイマー画面を出す。
    private func startAndPresentTimer(on coordinator: AppCoordinator) async throws -> RunningSessionMarker {
        guard case .started(let marker) = await h.sessionService.start(habitID: habit.id) else {
            throw StartFailed()
        }
        coordinator.presentTimer(marker: marker)
        return marker
    }

    private struct StartFailed: Error {}

    /// 2 分を走り切らせ、完了文言が出ているところまで進める。
    private func runToCompletion(_ coordinator: AppCoordinator) async throws -> TimerViewModel {
        let timer = try #require(coordinator.presentedTimer)
        h.clock.advance(by: 120)
        timer.tick()
        await h.sleeper.waitUntilSleeping()
        return timer
    }

    // MARK: 最初に出す画面

    @Test("オンボーディングを見終えていなければオンボーディング、見終えていればホームから始まる")
    func routeFollowsOnboardingFlag() {
        #expect(h.makeCoordinator().route == .onboarding)

        h.settings.onboardingCompleted = true
        #expect(h.makeCoordinator().route == .home)
    }

    @Test("オンボーディングを見終えたら、ホームに切り替えて、新規登録のウィザードを出す")
    func onboardingDidFinish() {
        let coordinator = h.makeCoordinator()

        coordinator.onboardingDidFinish()

        #expect(coordinator.route == .home)
        #expect(coordinator.presentedWizard?.mode == .new(origin: .onboarding))
    }

    // MARK: アクティブ化

    @Test("アクティブ化では、タイマーの復元を先に行ってから、リマインダーを合わせる")
    func activationOrder() async throws {
        // 7:00 に始めたタイマーが、裏にいる間に走り切っていた
        h.clock.now = TestCalendars.date(2026, 10, 1, 7, 0, in: h.calendar)
        _ = await h.sessionService.start(habitID: habit.id)
        h.clock.advance(by: 300)
        let coordinator = h.makeCoordinator()

        await coordinator.activate()

        #expect(h.sessions.allSessions().count == 1)
        #expect(h.reminders.authorization == .authorized)
        // 復元より先に同期していたら、今日のリマインダーが残ってしまう
        #expect(!h.reminderIdentifiers.contains(h.todayReminderIdentifier))
        #expect(h.reminderIdentifiers.count == 59)
    }

    @Test("最初のアクティブ化はアプリの起動として、2 回目以降は裏からの復帰として扱う")
    func firstActivationIsCold() async throws {
        let coordinator = h.makeCoordinator()
        _ = await h.sessionService.start(habitID: habit.id)
        h.clock.advance(by: 60)

        // 起動直後に 120 秒未満の実行が残っていたら、破棄する
        await coordinator.activate()
        #expect(h.runningStore.load() == nil)

        // 2 回目以降は、120 秒未満なら計測を続ける
        guard case .started(let marker) = await h.sessionService.start(habitID: habit.id) else {
            Issue.record("開始できるはず")
            return
        }
        h.clock.advance(by: 60)
        await coordinator.activate()
        #expect(h.runningStore.load() == marker)
    }

    @Test("アクティブ化しても、実行中のタイマーの Live Activity は消さない")
    func activationKeepsRunningActivity() async throws {
        let coordinator = h.makeCoordinator()
        await coordinator.activate()
        let marker = try await startAndPresentTimer(on: coordinator)
        h.clock.advance(by: 30)

        await coordinator.activate()

        #expect(h.liveActivity.currentActivities().map(\.sessionID) == [marker.sessionID])
        #expect(coordinator.presentedTimer?.phase == .running(marker))
    }

    @Test("通知の許可状態は、アクティブ化のたびに取得し直す")
    func activationRefreshesAuthorization() async {
        let coordinator = h.makeCoordinator()
        h.notifications.authorization = .denied
        await coordinator.activate()
        #expect(h.reminders.authorization == .denied)
        #expect(h.reminderIdentifiers.isEmpty)

        h.notifications.authorization = .authorized
        await coordinator.activate()
        #expect(h.reminders.authorization == .authorized)
        #expect(h.reminderIdentifiers.count == 60)
    }

    // MARK: 表示する日

    @Test("アクティブ化のとき、表示する日を今日に更新する")
    func activationUpdatesDisplayDay() async {
        let coordinator = h.makeCoordinator()
        let before = coordinator.displayDay
        let version = coordinator.dataVersion
        h.clock.advance(by: 86_400)

        await coordinator.activate()

        #expect(coordinator.displayDay == before.adding(days: 1, calendar: h.calendar))
        #expect(coordinator.dataVersion == version + 1)
    }

    @Test("アプリを開いている間に日付が変わったら、表示する日を更新する。同じ日なら何も変えない")
    func dayChange() {
        let coordinator = h.makeCoordinator()
        let before = coordinator.displayDay

        coordinator.dayDidChange()
        #expect(coordinator.displayDay == before)
        #expect(coordinator.dataVersion == 0)

        h.clock.now = TestCalendars.date(2026, 10, 2, 0, 0, in: h.calendar)
        coordinator.dayDidChange()
        #expect(coordinator.displayDay == before.adding(days: 1, calendar: h.calendar))
        #expect(coordinator.dataVersion == 1)
    }

    @Test("日をまたいで完了しても、表示する日は当日に切り替わる")
    func displayDayIsNotHeldAfterMidnightCompletion() async throws {
        h.clock.now = TestCalendars.date(2026, 10, 1, 23, 59, in: h.calendar)
        let coordinator = h.makeCoordinator()
        await coordinator.activate()
        let startDay = coordinator.displayDay
        _ = try await startAndPresentTimer(on: coordinator)

        let timer = try await runToCompletion(coordinator)          // 10/2 0:01
        coordinator.dayDidChange()

        #expect(timer.phase != .terminated)
        #expect(coordinator.displayDay == startDay.adding(days: 1, calendar: h.calendar))
        #expect(h.sessions.allSessions().map { DayKey($0.startedAt, calendar: h.calendar) } == [startDay])
    }

    // MARK: タイマー画面の提示と終了

    @Test("タイマー画面は、実行中の印を持った状態で出す")
    func presentsTimer() async throws {
        let coordinator = h.makeCoordinator()

        let marker = try await startAndPresentTimer(on: coordinator)

        #expect(coordinator.presentedTimer?.phase == .running(marker))
    }

    @Test("完了：完了文言の表示が終わってから閉じる。データが変わったことを 2 回知らせる")
    func closesAfterCompletionDisplay() async throws {
        let coordinator = h.makeCoordinator()
        _ = try await startAndPresentTimer(on: coordinator)

        let timer = try await runToCompletion(coordinator)
        // 完了文言の表示中は、まだ閉じない
        #expect(coordinator.presentedTimer === timer)
        #expect(coordinator.dataVersion == 1)

        h.sleeper.wakeUp()
        await timer.pendingWork?.value

        #expect(coordinator.presentedTimer == nil)
        #expect(coordinator.dataVersion == 2)
    }

    @Test("完了：保存に失敗していたら、閉じる前に保存し直す。データの変更は保存できてから知らせる")
    func flushesPendingBeforeClosing() async throws {
        let coordinator = h.makeCoordinator()
        _ = try await startAndPresentTimer(on: coordinator)
        h.sessions.failsInsert = true

        let timer = try await runToCompletion(coordinator)
        #expect(coordinator.dataVersion == 0)
        #expect(h.sessionService.pendingCompletions().count == 1)

        h.sessions.failsInsert = false
        h.sleeper.wakeUp()
        await timer.pendingWork?.value

        #expect(h.sessionService.pendingCompletions().isEmpty)
        #expect(h.sessions.allSessions().count == 1)
        #expect(coordinator.dataVersion == 1)
        #expect(coordinator.presentedTimer == nil)
    }

    @Test("中断：すぐに閉じる。記録が残らないので、データが変わったことは知らせない")
    func closesOnAbort() async throws {
        let coordinator = h.makeCoordinator()
        _ = try await startAndPresentTimer(on: coordinator)
        let timer = try #require(coordinator.presentedTimer)

        timer.escape()
        await timer.pendingWork?.value

        #expect(coordinator.presentedTimer == nil)
        #expect(coordinator.dataVersion == 0)
        #expect(coordinator.lastCompletionMessage == nil)
    }

    @Test("裏で破棄された：完了文言を出さずに閉じる")
    func closesWhenDiscardedInBackground() async throws {
        let coordinator = h.makeCoordinator()
        await coordinator.activate()
        _ = try await startAndPresentTimer(on: coordinator)
        let timer = try #require(coordinator.presentedTimer)
        h.clock.advance(by: 86_400)

        await coordinator.activate()

        #expect(timer.phase == .terminated)
        #expect(coordinator.presentedTimer == nil)
        #expect(coordinator.lastCompletionMessage == nil)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.feedback.playCompletionCount == 0)
    }

    @Test("裏で完了した：音と振動なしで完了文言を出し、表示が終わってから閉じる")
    func showsCompletionWhenCompletedInBackground() async throws {
        let coordinator = h.makeCoordinator()
        await coordinator.activate()
        _ = try await startAndPresentTimer(on: coordinator)
        let timer = try #require(coordinator.presentedTimer)
        h.clock.advance(by: 300)

        await coordinator.activate()
        await h.sleeper.waitUntilSleeping()

        guard case .completed(let message) = timer.phase else {
            Issue.record("完了文言を表示しているはず")
            return
        }
        #expect(coordinator.lastCompletionMessage == message)
        #expect(coordinator.presentedTimer === timer)
        #expect(h.feedback.playCompletionCount == 0)

        h.sleeper.wakeUp()
        await timer.pendingWork?.value
        #expect(coordinator.presentedTimer == nil)
    }

    // MARK: 完了文言

    @Test("2 回続けて完了すると、完了文言が前回と変わる")
    func completionMessageChangesBetweenRuns() async throws {
        h.completionMessages = ["A", "B"]
        let coordinator = h.makeCoordinator()
        let other = try h.addHabit("靴を履く")

        _ = try await startAndPresentTimer(on: coordinator)
        let first = try await runToCompletion(coordinator)
        let firstMessage = try #require(coordinator.lastCompletionMessage)
        h.sleeper.wakeUp()
        await first.pendingWork?.value

        guard case .started(let marker) = await h.sessionService.start(habitID: other.id) else {
            Issue.record("開始できるはず")
            return
        }
        coordinator.presentTimer(marker: marker)
        _ = try await runToCompletion(coordinator)

        let secondMessage = try #require(coordinator.lastCompletionMessage)
        #expect(secondMessage != firstMessage)
        #expect(Set([firstMessage, secondMessage]) == ["A", "B"])
    }

    // MARK: ウィザード

    @Test("ウィザードは、新規か編集かと、どこから開いたかを伴って出す")
    func presentsWizard() {
        let coordinator = h.makeCoordinator()

        coordinator.presentWizard(mode: .edit(habitID: habit.id, currentTitle: habit.title))

        #expect(coordinator.presentedWizard?.mode == .edit(habitID: habit.id, currentTitle: habit.title))
    }

    @Test("ウィザードの終了：成功ならデータが変わったことを知らせて閉じる。キャンセルと上限到達は閉じるだけ", arguments: [
        (WizardFinish.succeeded, 1),
        (.cancelled, 0),
        (.limitReached, 0),
    ])
    func wizardFinish(finish: WizardFinish, expectedVersion: Int) {
        let coordinator = h.makeCoordinator()
        coordinator.presentWizard(mode: .new(origin: .home))

        coordinator.wizardDidFinish(finish)

        #expect(coordinator.presentedWizard == nil)
        #expect(coordinator.dataVersion == expectedVersion)
    }

    // MARK: その他の通知

    @Test("ウィザードを通らない習慣の変更（並び替え・アーカイブ）も、データが変わったこととして知らせられる")
    func habitsDidChange() {
        let coordinator = h.makeCoordinator()

        coordinator.habitsDidChange()

        #expect(coordinator.dataVersion == 1)
    }

    @Test("起動時に走り切っていたタイマーを記録したときも、データが変わったことを知らせる")
    func recoveryBumpsDataVersion() async {
        _ = await h.sessionService.start(habitID: habit.id)
        h.clock.advance(by: 300)
        let coordinator = h.makeCoordinator()

        await coordinator.activate()

        #expect(coordinator.dataVersion == 1)
        #expect(coordinator.presentedTimer == nil)
    }

    @Test("テーマは保存されている設定に従い、変更の通知で読み直す")
    func theme() {
        h.settings.theme = .light
        let coordinator = h.makeCoordinator()
        #expect(coordinator.theme == .light)

        h.settings.theme = .dark
        #expect(coordinator.theme == .light)
        coordinator.themeDidChange()
        #expect(coordinator.theme == .dark)
    }

    @Test("「視差効果を減らす」が有効なら、画面の切り替えにアニメーションを付けない")
    func reducedMotionDisablesTransitionAnimations() {
        #expect(h.makeCoordinator(prefersReducedMotion: true).disablesTransitionAnimations)
        #expect(!h.makeCoordinator(prefersReducedMotion: false).disablesTransitionAnimations)
    }
}
