import Foundation
import Observation
import SwiftUI

/// 提示しているウィザード。
struct WizardPresentation: Identifiable, Equatable {
    let id = UUID()
    /// 新規か編集か。どこから開いたか（閉じた後に戻る先）もここから決まる。
    let mode: WizardStateMachine.Mode
    let viewModel: WizardViewModel

    static func == (lhs: WizardPresentation, rhs: WizardPresentation) -> Bool {
        lhs.id == rhs.id
    }
}

enum WizardFinish {
    /// 登録・名前の変更に成功した。
    case succeeded
    case cancelled
    /// 習慣が上限に達していて登録できなかった。
    case limitReached
}

/// 画面をまたぐ調停役。最初に出す画面、表示する日、全画面で出す画面（タイマー・ウィザード）を持つ。
/// 全画面の画面を出すのも閉じるのもこの型だけが行い、各画面は終わったことを知らせるだけにする。
@Observable
final class AppCoordinator {
    enum Route: Equatable {
        case onboarding
        case home
    }

    private(set) var route: Route
    /// ホームと統計が基準にする日。アプリがアクティブになったときと、日付が変わったときにだけ更新する。
    private(set) var displayDay: DayKey
    /// 習慣や完了記録が変わるたびに増える。画面はこの値の変化を見て読み込み直す。
    private(set) var dataVersion = 0
    private(set) var presentedTimer: TimerViewModel?
    private(set) var presentedWizard: WizardPresentation?
    /// 直前に表示した完了文言。同じ文言を続けて出さないために覚えておく（アプリを終了すると忘れる）。
    private(set) var lastCompletionMessage: String?
    private(set) var theme: AppTheme

    @ObservationIgnored private let sessionService: SessionService
    @ObservationIgnored private let reminders: ReminderService
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let clock: WallClock
    @ObservationIgnored private let makeTimerViewModel: (RunningSessionMarker, String?) -> TimerViewModel
    @ObservationIgnored private let makeWizardViewModel: (WizardStateMachine.Mode) -> WizardViewModel
    @ObservationIgnored private let prefersReducedMotion: () -> Bool
    @ObservationIgnored private var hasActivatedSinceLaunch = false

    init(
        sessionService: SessionService,
        reminders: ReminderService,
        settings: SettingsStore,
        clock: WallClock,
        makeTimerViewModel: @escaping (RunningSessionMarker, String?) -> TimerViewModel,
        makeWizardViewModel: @escaping (WizardStateMachine.Mode) -> WizardViewModel,
        prefersReducedMotion: @escaping () -> Bool
    ) {
        self.sessionService = sessionService
        self.reminders = reminders
        self.settings = settings
        self.clock = clock
        self.makeTimerViewModel = makeTimerViewModel
        self.makeWizardViewModel = makeWizardViewModel
        self.prefersReducedMotion = prefersReducedMotion
        route = settings.onboardingCompleted ? .home : .onboarding
        displayDay = DayKey(clock.now, calendar: clock.calendar)
        theme = settings.theme
    }

    /// 「視差効果を減らす」が有効なら、画面の切り替えにアニメーションを付けない。
    var disablesTransitionAnimations: Bool {
        prefersReducedMotion()
    }

    // MARK: アクティブ化・日付の変更

    /// アプリがアクティブになるたびに呼ぶ（起動、裏からの復帰、通知センターを閉じたとき など）。
    /// 順序に意味がある：実行中だったタイマーの扱いを決めてから、表示する日とリマインダーを合わせる。
    func activate() async {
        let launch: LaunchKind = hasActivatedSinceLaunch ? .warm : .cold
        hasActivatedSinceLaunch = true

        let outcome = await sessionService.recoverOnActivation(launch: launch)
        updateDisplayDay()

        switch outcome {
        case .none:
            break
        case .completed(let habitID, let attributedDay):
            dataVersion += 1
            presentedTimer?.completedInBackground(habitID: habitID, attributedDay: attributedDay)
        case .discarded:
            dataVersion += 1
            if let timer = presentedTimer {
                timer.discardedInBackground()
                transition { presentedTimer = nil }
            }
        }

        await reminders.refreshAuthorization()
        await reminders.sync()
    }

    /// アプリを開いている間に日付が変わった。
    func dayDidChange() {
        updateDisplayDay()
    }

    private func updateDisplayDay() {
        let today = DayKey(clock.now, calendar: clock.calendar)
        guard today != displayDay else { return }
        displayDay = today
        dataVersion += 1
    }

    // MARK: オンボーディング・テーマ

    /// オンボーディングを見終えた。ホームに切り替え、続けて最初の習慣の登録を促す。
    func onboardingDidFinish() {
        transition { route = .home }
        presentWizard(mode: .new(origin: .onboarding))
    }

    func themeDidChange() {
        theme = settings.theme
    }

    /// 並び替え・アーカイブなど、ウィザードを通らずに習慣が変わった。
    func habitsDidChange() {
        dataVersion += 1
    }

    // MARK: タイマー画面

    func presentTimer(marker: RunningSessionMarker) {
        let timer = makeTimerViewModel(marker, lastCompletionMessage)
        timer.onCompleted = { [weak self] completion in
            self?.timerDidComplete(completion)
        }
        timer.onCompletionDisplayEnded = { [weak self] in
            await self?.timerCompletionDisplayDidEnd()
        }
        timer.onAborted = { [weak self] in
            self?.timerDidAbort()
        }
        transition { presentedTimer = timer }
    }

    private func timerDidComplete(_ completion: TimerCompletion) {
        lastCompletionMessage = completion.message
        // 保存待ちに回った場合はまだ記録がないので、ここでは進めない
        if completion.saved {
            dataVersion += 1
        }
    }

    /// 完了文言の表示が終わった。保存待ちがあれば保存し直してから閉じるので、
    /// ホームに戻った時点では保存済みの状態で表示される。
    private func timerCompletionDisplayDidEnd() async {
        await sessionService.flushPendingCompletion()
        dataVersion += 1
        transition { presentedTimer = nil }
    }

    /// 中断では記録が残らないので、データが変わったことにはしない。
    private func timerDidAbort() {
        transition { presentedTimer = nil }
    }

    // MARK: ウィザード

    /// 開くたびに新しく作るので、前回の入力や分解の状態は残らない。
    func presentWizard(mode: WizardStateMachine.Mode) {
        let wizard = makeWizardViewModel(mode)
        wizard.onFinish = { [weak self] finish in
            self?.wizardDidFinish(finish)
        }
        transition { presentedWizard = WizardPresentation(mode: mode, viewModel: wizard) }
    }

    /// ウィザードが終わった。閉じた後は、開いた元の画面に戻る
    /// （ホーム・オンボーディングから開いたならホーム、設定から開いたなら設定）。
    private func wizardDidFinish(_ finish: WizardFinish) {
        if finish == .succeeded {
            dataVersion += 1
        }
        transition { presentedWizard = nil }
    }

    // MARK: 内部

    private func transition(_ change: () -> Void) {
        if disablesTransitionAnimations {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction, change)
        } else {
            change()
        }
    }
}
