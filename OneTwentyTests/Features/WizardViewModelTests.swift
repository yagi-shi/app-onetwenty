import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct WizardViewModelTests {
    private let h: ServiceHarness

    /// 終わりの通知を受け取った順に記録する。
    private final class Finishes {
        var values: [WizardFinish] = []
    }

    init() throws {
        h = try ServiceHarness()
    }

    private func makeViewModel(_ mode: WizardStateMachine.Mode = .new(origin: .home)) -> (WizardViewModel, Finishes) {
        let viewModel = h.makeWizardViewModel(mode: mode)
        let finishes = Finishes()
        viewModel.onFinish = { finishes.values.append($0) }
        return (viewModel, finishes)
    }

    /// 入力して送る。
    private func submit(_ viewModel: WizardViewModel, _ text: String) async {
        viewModel.text = text
        await viewModel.submit()
    }

    /// 「いいえ」を 3 回くり返して、型の選択まで進める。
    private func reachGenericForced(_ viewModel: WizardViewModel) async {
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(false)
        await submit(viewModel, "床を拭く")
        await viewModel.answerTwoMinute(false)
        await submit(viewModel, "雑巾を出す")
        await viewModel.answerTwoMinute(false)
    }

    // MARK: 入力欄と文字数

    @Test("新規は空の入力欄から、編集は現在の習慣名を入れた状態から始まる")
    func initialText() {
        #expect(makeViewModel().0.text.isEmpty)
        let (editing, _) = makeViewModel(.edit(habitID: UUID(), currentTitle: "本を1ページ読む"))
        #expect(editing.text == "本を1ページ読む")
        #expect(editing.validation == TitleValidation(count: 8, limit: 30, state: .ok))
    }

    @Test("文字数は入力のたびに数え直し、上限以内でも「何文字 / 上限」を持つ")
    func countsOnEveryInput() {
        let (viewModel, _) = makeViewModel()

        viewModel.text = "本を開く"
        #expect(viewModel.validation == TitleValidation(count: 4, limit: 30, state: .ok))

        viewModel.text = "  本を1ページ読む  "
        #expect(viewModel.validation.count == 8)
    }

    @Test("上限を超えている間は送信できず、ダイアログも出さない")
    func tooLongCannotBeSubmitted() async {
        let (viewModel, finishes) = makeViewModel()
        viewModel.text = String(repeating: "あ", count: 31)

        #expect(!viewModel.canSubmit)
        #expect(viewModel.submitBlocker == .tooLong)
        await viewModel.submit()

        #expect(viewModel.step == .freeInput)
        #expect(viewModel.alert == nil)
        #expect(finishes.values.isEmpty)
    }

    @Test("空・空白だけでは送信できない", arguments: ["", "  ", "　"])
    func emptyCannotBeSubmitted(text: String) {
        let (viewModel, _) = makeViewModel()
        viewModel.text = text

        #expect(!viewModel.canSubmit)
        #expect(viewModel.submitBlocker == .emptyInput)
    }

    @Test("次の問に進むと、入力欄は空になる")
    func clearsTextOnNextStep() async {
        let (viewModel, _) = makeViewModel()

        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(false)

        #expect(viewModel.step == .reDecompose(.notTwoMinutes))
        #expect(viewModel.text.isEmpty)
    }

    // MARK: 登録・名前変更

    @Test("2 分確認で「はい」なら登録し、成功してから終わりを知らせる")
    func registersOnYes() async throws {
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        viewModel.onFinish = { finish in
            // 終わりを知らせた時点で、もう保存されている
            #expect(self.h.habitStore.activeHabits().map(\.title) == ["部屋を片付ける"])
            finishes.values.append(finish)
        }

        await viewModel.answerTwoMinute(true)

        #expect(finishes.values == [.succeeded])
        let habit = try #require(h.habitStore.activeHabits().first)
        #expect(habit.title == "部屋を片付ける")
        #expect(habit.originalIntent == "部屋を片付ける")
    }

    @Test("テンプレートを選んで登録すると、習慣名はテンプレート、登録時の文は最初の入力になる")
    func registersTemplate() async throws {
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "読書をしたい")

        await viewModel.selectTemplate("本を開く")
        await viewModel.answerTwoMinute(true)

        #expect(finishes.values == [.succeeded])
        let habit = try #require(h.habitStore.activeHabits().first)
        #expect(habit.title == "本を開く")
        #expect(habit.originalIntent == "読書をしたい")
    }

    @Test("保存に失敗したら、閉じずにアラートを出し、入力と分解の状態を保ったままやり直せる")
    func saveFailureKeepsState() async {
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(false)
        await submit(viewModel, "床の物を1つ拾う")
        h.habits.failsWrites = true

        await viewModel.answerTwoMinute(true)

        #expect(viewModel.alert == .saveFailed)
        #expect(finishes.values.isEmpty)
        #expect(viewModel.step == .twoMinCheck)
        #expect(viewModel.machine.candidate == "床の物を1つ拾う")
        #expect(viewModel.machine.redecomposeCount == 1)

        await viewModel.dismissAlert()
        #expect(viewModel.alert == nil)
        #expect(finishes.values.isEmpty)

        h.habits.failsWrites = false
        await viewModel.answerTwoMinute(true)
        #expect(finishes.values == [.succeeded])
        #expect(h.habitStore.activeHabits().map(\.title) == ["床の物を1つ拾う"])
    }

    @Test("習慣が上限に達していたら、アラートの OK で閉じ、上限に達したことを知らせる")
    func limitReachedClosesOnOK() async throws {
        for title in ["A", "B", "C"] { try h.addHabit(title) }
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")

        await viewModel.answerTwoMinute(true)
        #expect(viewModel.alert == .limitReached)
        #expect(finishes.values.isEmpty)

        await viewModel.dismissAlert()

        #expect(finishes.values == [.limitReached])
        #expect(viewModel.step == .freeInput)
        #expect(h.habitStore.activeHabits().count == 3)
    }

    @Test("編集で「はい」なら名前を変更し、登録時の文は変えない")
    func renames() async throws {
        let habit = try h.addHabit("本を1ページ読む")
        let (viewModel, finishes) = makeViewModel(.edit(habitID: habit.id, currentTitle: habit.title))

        await submit(viewModel, "本を開く")
        await viewModel.answerTwoMinute(true)

        #expect(finishes.values == [.succeeded])
        let renamed = try #require(h.habitStore.habit(id: habit.id))
        #expect(renamed.title == "本を開く")
        #expect(renamed.originalIntent == habit.originalIntent)
        #expect(h.habitStore.allHabits().count == 1)
    }

    // MARK: 通知の許可の説明

    @Test("通知の許可が未決定なら、登録の後に説明を出す。「次へ」で許可を求めてから、終わったことを知らせる")
    func explainsNotificationsBeforeRequesting() async {
        h.notifications.authorization = .notDetermined
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")

        await viewModel.answerTwoMinute(true)

        // 登録は済んでいるが、説明を読んでもらうまでは許可を求めず、閉じもしない
        #expect(h.habitStore.activeHabits().map(\.title) == ["部屋を片付ける"])
        #expect(viewModel.alert == .notificationExplanation)
        #expect(h.notifications.requestAuthorizationCount == 0)
        #expect(finishes.values.isEmpty)

        await viewModel.dismissAlert()

        #expect(viewModel.alert == nil)
        #expect(h.notifications.requestAuthorizationCount == 1)
        #expect(h.reminderIdentifiers.count == 60)
        #expect(finishes.values == [.succeeded])
    }

    @Test("説明の「次へ」が二重に届いても、許可を求めるのも、終わりを知らせるのも 1 回だけ")
    func explanationIsHandledOnce() async {
        h.notifications.authorization = .notDetermined
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(true)

        await viewModel.dismissAlert()
        await viewModel.dismissAlert()

        #expect(h.notifications.requestAuthorizationCount == 1)
        #expect(finishes.values == [.succeeded])
    }

    @Test("説明を出している間は、ウィザードの操作を受け付けない（二重に登録しない）")
    func ignoresInputWhileExplaining() async {
        h.notifications.authorization = .notDetermined
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(true)

        await viewModel.answerTwoMinute(true)

        #expect(viewModel.alert == .notificationExplanation)
        #expect(h.habitStore.activeHabits().count == 1)
        #expect(finishes.values.isEmpty)
    }

    @Test("許可を拒否されても、登録は済んでいて、終わったことを知らせる")
    func deniedAuthorizationStillFinishes() async {
        h.notifications.authorization = .notDetermined
        h.notifications.authorizationAfterRequest = .denied
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(true)

        await viewModel.dismissAlert()

        #expect(finishes.values == [.succeeded])
        #expect(h.habitStore.activeHabits().count == 1)
        #expect(h.reminderIdentifiers.isEmpty)
    }

    @Test("通知の許可が決まっていれば、説明を出さずに終わる", arguments: [NotificationAuthorization.authorized, .denied])
    func noExplanationWhenDetermined(authorization: NotificationAuthorization) async {
        h.notifications.authorization = authorization
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")

        await viewModel.answerTwoMinute(true)

        #expect(viewModel.alert == nil)
        #expect(finishes.values == [.succeeded])
        #expect(h.notifications.requestAuthorizationCount == 0)
    }

    @Test("名前の変更では、通知の許可が未決定でも説明を出さない")
    func renameDoesNotExplain() async throws {
        let habit = try h.addHabit("本を開く")
        h.notifications.authorization = .notDetermined
        let (viewModel, finishes) = makeViewModel(.edit(habitID: habit.id, currentTitle: habit.title))
        await submit(viewModel, "本を1ページ読む")

        await viewModel.answerTwoMinute(true)

        #expect(viewModel.alert == nil)
        #expect(finishes.values == [.succeeded])
        #expect(h.notifications.requestAuthorizationCount == 0)
    }

    @Test("名前変更の保存に失敗したら、閉じずにアラートを出す")
    func renameFailure() async throws {
        let habit = try h.addHabit("本を1ページ読む")
        let (viewModel, finishes) = makeViewModel(.edit(habitID: habit.id, currentTitle: habit.title))
        await submit(viewModel, "本を開く")
        h.habits.failsWrites = true

        await viewModel.answerTwoMinute(true)

        #expect(viewModel.alert == .saveFailed)
        #expect(finishes.values.isEmpty)
        #expect(h.habitStore.habit(id: habit.id)?.title == "本を1ページ読む")
    }

    // MARK: キャンセル

    @Test("キャンセルすると、何も保存せずに終わりを知らせる")
    func cancel() async {
        let (viewModel, finishes) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")

        viewModel.cancel()

        #expect(finishes.values == [.cancelled])
        #expect(h.habitStore.allHabits().isEmpty)
    }

    @Test("編集をキャンセルしても、習慣名は変わらない")
    func cancelEdit() async throws {
        let habit = try h.addHabit("本を1ページ読む")
        let (viewModel, finishes) = makeViewModel(.edit(habitID: habit.id, currentTitle: habit.title))
        await submit(viewModel, "本を開く")

        viewModel.cancel()

        #expect(finishes.values == [.cancelled])
        #expect(h.habitStore.habit(id: habit.id)?.title == "本を1ページ読む")
    }

    // MARK: 型から作る文

    @Test("型を選んだ後は、入力を型の文型に差し込んだ文を数え、検出を通さず 2 分確認へ進む")
    func composesGenericPattern() async {
        let (viewModel, _) = makeViewModel()
        await reachGenericForced(viewModel)
        await viewModel.chooseGenericType(.doOne)

        viewModel.text = "読書を続ける"
        let composed = WizardText.compose(.doOne, with: "読書を続ける")
        #expect(viewModel.composedText == composed)
        #expect(viewModel.validation.count == composed.count)

        await viewModel.submit()

        #expect(viewModel.step == .twoMinCheck)
        #expect(viewModel.machine.candidate == composed)
    }

    @Test("型を選んだ後、入力が空なら、合成した文が空でなくても送信できない")
    func emptyInputAfterChoosingPattern() async {
        let (viewModel, _) = makeViewModel()
        await reachGenericForced(viewModel)
        await viewModel.chooseGenericType(.prepare)

        viewModel.text = "  "

        #expect(viewModel.composedText?.isEmpty == false)
        #expect(viewModel.submitBlocker == .emptyInput)
        #expect(!viewModel.canSubmit)
    }

    @Test("型を選んだ後、合成した文が上限を超えるなら送信できない")
    func composedTooLong() async {
        let (viewModel, _) = makeViewModel()
        await reachGenericForced(viewModel)
        await viewModel.chooseGenericType(.prepare)

        viewModel.text = String(repeating: "あ", count: 30)

        #expect(viewModel.validation.state == .tooLong)
        #expect(viewModel.submitBlocker == .tooLong)
    }

    // MARK: 戻る

    @Test("1 問前に戻ると、その問で入力していた文が入力欄に戻る")
    func backRestoresInput() async {
        let (viewModel, _) = makeViewModel()
        await submit(viewModel, "部屋を片付ける")
        await viewModel.answerTwoMinute(false)
        await submit(viewModel, "床を拭く")
        #expect(viewModel.step == .twoMinCheck)

        viewModel.back()
        #expect(viewModel.step == .reDecompose(.notTwoMinutes))
        #expect(viewModel.text == "床を拭く")

        viewModel.back()
        #expect(viewModel.step == .twoMinCheck)

        viewModel.back()
        #expect(viewModel.step == .freeInput)
        #expect(viewModel.text == "部屋を片付ける")

        viewModel.back()
        #expect(viewModel.step == .freeInput)
        #expect(viewModel.text == "部屋を片付ける")
    }

    @Test("型を選んだ後の入力も、戻ると入力した語のまま戻る")
    func backRestoresDescribeInput() async {
        let (viewModel, _) = makeViewModel()
        await reachGenericForced(viewModel)
        await viewModel.chooseGenericType(.go)
        await submit(viewModel, "図書館")

        viewModel.back()

        #expect(viewModel.step == .describe(.go))
        #expect(viewModel.text == "図書館")
    }
}
