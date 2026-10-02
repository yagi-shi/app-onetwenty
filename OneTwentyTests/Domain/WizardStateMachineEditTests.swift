import Foundation
import Testing
@testable import OneTwenty

/// 編集フローの状態遷移。新規登録フローとの違いを中心に確かめる。
struct WizardStateMachineEditTests {
    private static let habitID = UUID()
    private static let reading = TemplateCategory(id: "reading", keywords: ["読書", "本"], templates: ["本を開く"])
    private static let content = ContentBundle(
        templates: [reading],
        terms: DetectionTerms(frequencyAdverbs: ["毎日"], goalSuffixes: ["を続ける", "を頑張る"]),
        completionMessages: []
    )

    private func makeMachine(currentTitle: String = "本を1ページ読む", language: ContentLanguage = .ja) -> WizardStateMachine {
        WizardStateMachine(
            mode: .edit(habitID: Self.habitID, currentTitle: currentTitle),
            language: language,
            content: Self.content
        )
    }

    /// 再分解を 3 回くり返して、型の選択に入った状態。
    private func machineAtGenericForced() -> WizardStateMachine {
        var machine = makeMachine()
        _ = machine.submitText("部屋を片付ける")
        _ = machine.answerTwoMinute(false)
        _ = machine.submitText("床を拭く")
        _ = machine.answerTwoMinute(false)
        _ = machine.submitText("雑巾を出す")
        _ = machine.answerTwoMinute(false)
        return machine
    }

    // MARK: 開始

    @Test("現在の習慣名を入力欄に入れた状態から始まる")
    func startsWithCurrentTitle() {
        var machine = makeMachine(currentTitle: "本を1ページ読む")

        #expect(machine.step == .editInput)
        #expect(machine.initialText == "本を1ページ読む")
        #expect(!machine.canGoBack)
        #expect(machine.back() == .none)
        #expect(machine.step == .editInput)
    }

    @Test("新規登録では、入力欄は空から始まる")
    func newFlowStartsEmpty() {
        let machine = WizardStateMachine(mode: .new(origin: .home), language: .ja, content: Self.content)

        #expect(machine.step == .freeInput)
        #expect(machine.initialText.isEmpty)
    }

    // MARK: 通る段階

    @Test("送信すると、検出を経て 2 分確認へ進み、「はい」で名前の変更になる")
    func renamesAfterTwoMinCheck() {
        var machine = makeMachine()

        #expect(machine.submitText("本を開く") == .none)
        #expect(machine.step == .twoMinCheck)
        #expect(machine.answerTwoMinute(true) == .rename(habitID: Self.habitID, title: "本を開く"))
        // 保存の成否は呼び出し側が判断するので、状態機械は 2 分確認に留まる
        #expect(machine.step == .twoMinCheck)
    }

    @Test("テンプレートに該当する文でも、テンプレートは提示しない")
    func neverSuggestsTemplates() {
        var machine = makeMachine()

        _ = machine.submitText("読書の本を開く")

        #expect(machine.step == .twoMinCheck)
        #expect(machine.templateCategory == nil)
    }

    @Test("頻度を表す語を含む文では、新規登録と同じく語を除いた文を提示する")
    func suggestsStrippedText() {
        var machine = makeMachine()

        _ = machine.submitText("毎日本を開く")
        #expect(machine.step == .adverbSuggest(term: "毎日", stripped: "本を開く"))

        _ = machine.acceptSuggestion()
        #expect(machine.answerTwoMinute(true) == .rename(habitID: Self.habitID, title: "本を開く"))
    }

    // MARK: 再分解

    @Test("目標の言い回しを検出すると再分解に入り、回数に数える")
    func goalSuffixEntersReDecompose() {
        var machine = makeMachine()

        _ = machine.submitText("読書を続ける")

        #expect(machine.step == .reDecompose(.goalDetected))
        #expect(machine.redecomposeCount == 1)
    }

    @Test("2 分確認の「いいえ」でも再分解に入り、回数に数える")
    func noEntersReDecompose() {
        var machine = makeMachine()
        _ = machine.submitText("本を開く")

        _ = machine.answerTwoMinute(false)

        #expect(machine.step == .reDecompose(.notTwoMinutes))
        #expect(machine.redecomposeCount == 1)
    }

    @Test("再分解では、型を任意で選ぶ選択肢を出さない")
    func noOptionalGenericPattern() {
        var machine = makeMachine()
        _ = machine.submitText("本を開く")
        _ = machine.answerTwoMinute(false)

        #expect(!machine.canChooseGenericPattern)
        #expect(machine.chooseGenericType(.prepare) == .none)
        #expect(machine.step == .reDecompose(.notTwoMinutes))
    }

    @Test("再分解の回数が上限に達したときだけ、型の選択に入る")
    func reachesGenericForcedAtLimit() {
        var machine = machineAtGenericForced()

        #expect(machine.step == .genericForced)
        #expect(machine.canChooseGenericPattern)

        _ = machine.chooseGenericType(.prepare)
        #expect(machine.step == .describe(.prepare))

        // 型から作った文には検出をかけない
        _ = machine.submitText("読書を続ける本を用意する")
        #expect(machine.step == .twoMinCheck)
        #expect(machine.answerTwoMinute(true) == .rename(habitID: Self.habitID, title: "読書を続ける本を用意する"))
    }

    @Test("目標の言い回しの検出だけでも、3 回目で型の選択に入る")
    func goalDetectionAloneReachesLimit() {
        var machine = makeMachine()

        _ = machine.submitText("読書を続ける")
        _ = machine.submitText("英語を頑張る")
        #expect(machine.step == .reDecompose(.goalDetected))
        _ = machine.submitText("運動を続ける")

        #expect(machine.step == .genericForced)
    }

    // MARK: 現在の上限を超えた習慣名

    @Test("現在の上限を超えた習慣名でも開けて、そのままでは送信できず、短くすれば送信できる")
    func titleOverCurrentLimit() {
        // 英語（上限 60）で登録した後に、表示言語を日本語（上限 30）に変えた場合
        let longTitle = String(repeating: "a", count: 45)
        var machine = makeMachine(currentTitle: longTitle, language: .ja)

        #expect(machine.step == .editInput)
        #expect(machine.initialText == longTitle)

        _ = machine.submitText(longTitle)
        #expect(machine.step == .editInput)

        _ = machine.submitText(String(repeating: "a", count: 30))
        #expect(machine.step == .twoMinCheck)
    }

    // MARK: 戻る・キャンセル

    @Test("2 分確認から最初の問へ戻れる")
    func backToEditInput() {
        var machine = makeMachine()
        _ = machine.submitText("本を開く")

        _ = machine.back()

        #expect(machine.step == .editInput)
        #expect(machine.candidate.isEmpty)
        #expect(!machine.canGoBack)
    }

    @Test("どのステップでキャンセルしても、名前の変更にも登録にもならず、対象の習慣は変わらない")
    func cancelNeverRenames() {
        var steps: [WizardStateMachine] = []
        var machine = makeMachine()
        steps.append(machine)                           // 最初の問
        _ = machine.submitText("毎日本を開く")
        steps.append(machine)                           // 頻度を表す語の提示
        _ = machine.keepOriginal()
        steps.append(machine)                           // 2 分確認
        _ = machine.answerTwoMinute(false)
        steps.append(machine)                           // 再分解
        steps.append(machineAtGenericForced())          // 型の選択
        var describing = machineAtGenericForced()
        _ = describing.chooseGenericType(.go)
        steps.append(describing)                        // 具体の記述
        #expect(Set(steps.map { "\($0.step)" }).count == 6)

        for var machine in steps {
            #expect(machine.cancel() == .close)

            #expect(machine.step == .editInput)
            #expect(machine.mode == .edit(habitID: Self.habitID, currentTitle: "本を1ページ読む"))
            #expect(machine.initialText == "本を1ページ読む")
            #expect(machine.candidate.isEmpty)
            #expect(machine.redecomposeCount == 0)
        }
    }

    @Test("編集では登録にならず、新規登録では名前の変更にならない")
    func effectMatchesMode() {
        var editing = makeMachine()
        _ = editing.submitText("本を開く")
        var creating = WizardStateMachine(mode: .new(origin: .onboarding), language: .ja, content: Self.content)
        _ = creating.submitText("部屋を片付ける")

        #expect(editing.answerTwoMinute(true) == .rename(habitID: Self.habitID, title: "本を開く"))
        #expect(creating.answerTwoMinute(true) == .register(title: "部屋を片付ける", originalIntent: "部屋を片付ける"))
    }
}
