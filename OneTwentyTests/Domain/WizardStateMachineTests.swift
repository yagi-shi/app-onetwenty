import Foundation
import Testing
@testable import OneTwenty

/// 新規登録フローの状態遷移。
struct WizardStateMachineTests {
    private static let reading = TemplateCategory(id: "reading", keywords: ["読書", "本"], templates: ["本を開く", "本を1ページ読む"])
    private static let content = ContentBundle(
        templates: [reading],
        terms: DetectionTerms(frequencyAdverbs: ["毎日", "必ず"], goalSuffixes: ["を続ける", "を頑張る"]),
        completionMessages: []
    )

    private func makeMachine(language: ContentLanguage = .ja, content: ContentBundle = content) -> WizardStateMachine {
        WizardStateMachine(mode: .new(origin: .home), language: language, content: content)
    }

    /// 自由入力を送って 2 分確認まで進めた状態（テンプレート非該当・検出なし）。
    private func machineAtTwoMinCheck() -> WizardStateMachine {
        var machine = makeMachine()
        _ = machine.submitText("部屋を片付ける")
        return machine
    }

    /// 再分解を 3 回くり返して、型の選択に入った状態。
    private func machineAtGenericForced() -> WizardStateMachine {
        var machine = machineAtTwoMinCheck()
        _ = machine.answerTwoMinute(false)
        _ = machine.submitText("床を拭く")
        _ = machine.answerTwoMinute(false)
        _ = machine.submitText("雑巾を出す")
        _ = machine.answerTwoMinute(false)
        return machine
    }

    // MARK: 開始

    @Test("自由入力から始まり、最初の問より前には戻れない")
    func startsAtFreeInput() {
        var machine = makeMachine()

        #expect(machine.step == .freeInput)
        #expect(machine.candidate.isEmpty)
        #expect(machine.originalIntent.isEmpty)
        #expect(machine.redecomposeCount == 0)
        #expect(!machine.canGoBack)

        #expect(machine.back() == .none)
        #expect(machine.step == .freeInput)
    }

    // MARK: 自由入力

    @Test("文字数が上限を超える・空の入力では進まない", arguments: [String(repeating: "あ", count: 31), "", "   "])
    func invalidTextDoesNotAdvance(text: String) {
        var machine = makeMachine()

        #expect(machine.submitText(text) == .none)
        #expect(machine.step == .freeInput)
        #expect(!machine.canGoBack)
    }

    @Test("上限ちょうどの入力は進む")
    func textAtLimitAdvances() {
        var machine = makeMachine()

        _ = machine.submitText(String(repeating: "あ", count: 30))

        #expect(machine.step == .twoMinCheck)
    }

    @Test("テンプレートにも検出語にも当たらない入力は、そのまま 2 分確認へ進む")
    func plainTextGoesToTwoMinCheck() {
        var machine = makeMachine()

        _ = machine.submitText("  部屋を片付ける ")

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "部屋を片付ける")
        #expect(machine.originalIntent == "部屋を片付ける")
        #expect(machine.templateCategory == nil)
        #expect(machine.redecomposeCount == 0)
    }

    @Test("入力をそのまま登録することはできず、2 分確認の「はい」を経てはじめて登録になる")
    func registersOnlyAfterTwoMinCheck() {
        var machine = makeMachine()

        #expect(machine.submitText("部屋を片付ける") == .none)
        #expect(machine.answerTwoMinute(true) == .register(title: "部屋を片付ける", originalIntent: "部屋を片付ける"))
        // 保存の成否は呼び出し側が判断するので、状態機械は 2 分確認に留まる
        #expect(machine.step == .twoMinCheck)
    }

    // MARK: テンプレート

    @Test("テンプレートに該当する入力では、テンプレートを提示する")
    func suggestsTemplates() {
        var machine = makeMachine()

        _ = machine.submitText("読書をしたい")

        #expect(machine.step == .templateSuggest(Self.reading))
        #expect(machine.templateCategory == Self.reading)
    }

    @Test("テンプレートを選んでも、登録時の文は最初の自由入力のまま")
    func templateKeepsOriginalIntent() {
        var machine = makeMachine()
        _ = machine.submitText("読書をしたい")

        _ = machine.selectTemplate("本を開く")

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "本を開く")
        #expect(machine.answerTwoMinute(true) == .register(title: "本を開く", originalIntent: "読書をしたい"))
    }

    @Test("提示していないテンプレートは選べない")
    func unknownTemplateIsIgnored() {
        var machine = makeMachine()
        _ = machine.submitText("読書をしたい")

        _ = machine.selectTemplate("靴を履く")

        #expect(machine.step == .templateSuggest(Self.reading))
    }

    @Test("「自分で分解する」を選ぶと、入力した文が候補になる")
    func decomposeMyself() {
        var machine = makeMachine()
        _ = machine.submitText("読書をしたい")

        _ = machine.decomposeMyself()

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "読書をしたい")
    }

    @Test("テンプレートに該当した入力は、自分で分解するときに目標の言い回しを検出する")
    func decomposeMyselfRunsDetection() {
        var machine = makeMachine()
        _ = machine.submitText("読書を続ける")
        #expect(machine.step == .templateSuggest(Self.reading))
        #expect(machine.redecomposeCount == 0)

        _ = machine.decomposeMyself()

        #expect(machine.step == .reDecompose(.goalDetected))
        #expect(machine.redecomposeCount == 1)
    }

    // MARK: 検出の 2 分岐

    @Test("「毎日新聞を1ページ読む」は拒否されず、「毎日」を除いた文が提示される")
    func frequencyAdverbSuggestsStrippedText() {
        var machine = makeMachine()

        _ = machine.submitText("毎日新聞を1ページ読む")

        #expect(machine.step == .adverbSuggest(term: "毎日", stripped: "新聞を1ページ読む"))
        #expect(machine.redecomposeCount == 0)
    }

    @Test("提示を採用すると、語を除いた文が候補になる")
    func acceptSuggestion() {
        var machine = makeMachine()
        _ = machine.submitText("毎日新聞を1ページ読む")

        _ = machine.acceptSuggestion()

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "新聞を1ページ読む")
        #expect(machine.answerTwoMinute(true)
            == .register(title: "新聞を1ページ読む", originalIntent: "毎日新聞を1ページ読む"))
    }

    @Test("提示を採用しなければ、入力した文のまま次へ進む")
    func keepOriginal() {
        var machine = makeMachine()
        _ = machine.submitText("毎日新聞を1ページ読む")

        _ = machine.keepOriginal()

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "毎日新聞を1ページ読む")
        #expect(machine.redecomposeCount == 0)
    }

    @Test("目標の言い回しを検出すると、代替案を出さずに再分解へ戻す")
    func goalSuffixGoesToReDecompose() {
        var machine = makeMachine()

        _ = machine.submitText("英語を頑張る")

        #expect(machine.step == .reDecompose(.goalDetected))
        #expect(machine.redecomposeCount == 1)
    }

    @Test("2 分確認で「いいえ」なら再分解へ戻す")
    func noGoesToReDecompose() {
        var machine = machineAtTwoMinCheck()

        #expect(machine.answerTwoMinute(false) == .none)

        #expect(machine.step == .reDecompose(.notTwoMinutes))
        #expect(machine.redecomposeCount == 1)
    }

    @Test("再分解の答えにも、同じ検出がかかる")
    func reDecomposeAnswerIsDetected() {
        var machine = machineAtTwoMinCheck()
        _ = machine.answerTwoMinute(false)

        _ = machine.submitText("必ず床を拭く")

        #expect(machine.step == .adverbSuggest(term: "必ず", stripped: "床を拭く"))
    }

    @Test("再分解でも、文字数が上限を超える入力では進まない")
    func reDecomposeRejectsTooLongText() {
        var machine = machineAtTwoMinCheck()
        _ = machine.answerTwoMinute(false)

        _ = machine.submitText(String(repeating: "あ", count: 31))

        #expect(machine.step == .reDecompose(.notTwoMinutes))
        #expect(machine.candidate == "部屋を片付ける")
    }

    // MARK: 再分解の回数

    @Test("「いいえ」が 3 回目になると、型の選択に入る")
    func thirdNoEntersGenericForced() {
        var machine = machineAtTwoMinCheck()

        _ = machine.answerTwoMinute(false)
        #expect(machine.step == .reDecompose(.notTwoMinutes))
        _ = machine.submitText("床を拭く")
        _ = machine.answerTwoMinute(false)
        #expect(machine.step == .reDecompose(.notTwoMinutes))
        _ = machine.submitText("雑巾を出す")
        _ = machine.answerTwoMinute(false)

        #expect(machine.step == .genericForced)
        #expect(machine.redecomposeCount == 3)
    }

    @Test("「いいえ」と目標の言い回しの検出は、同じ回数として数える")
    func noAndGoalDetectionShareCounter() {
        var machine = makeMachine()

        _ = machine.submitText("英語を頑張る")          // 検出で 1 回目
        #expect(machine.redecomposeCount == 1)
        _ = machine.submitText("単語帳を開く")
        _ = machine.answerTwoMinute(false)               // 「いいえ」で 2 回目
        #expect(machine.redecomposeCount == 2)
        #expect(machine.step == .reDecompose(.notTwoMinutes))
        _ = machine.submitText("英語を頑張る")          // 検出で 3 回目

        #expect(machine.redecomposeCount == 3)
        #expect(machine.step == .genericForced)
    }

    // MARK: 型の選択

    @Test("型の選択では、自由な再分解はできない")
    func genericForcedIgnoresFreeText() {
        var machine = machineAtGenericForced()

        _ = machine.submitText("棚を拭く")

        #expect(machine.step == .genericForced)
        #expect(machine.canChooseGenericPattern)
    }

    @Test("型を選ぶと、具体を記述するステップへ進む", arguments: GenericPattern.allCases)
    func choosingPatternGoesToDescribe(pattern: GenericPattern) {
        var machine = machineAtGenericForced()

        _ = machine.chooseGenericType(pattern)

        #expect(machine.step == .describe(pattern))
    }

    @Test("型を選んだ後の送信は、検出を通さず 2 分確認へ進む")
    func describeSkipsDetection() {
        var machine = machineAtGenericForced()
        _ = machine.chooseGenericType(.doOne)

        // 「を続ける」は目標の言い回しだが、ここでは検出しない
        _ = machine.submitText("読書を続けるを1つやる")

        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "読書を続けるを1つやる")
        #expect(machine.redecomposeCount == 3)
        #expect(machine.answerTwoMinute(true)
            == .register(title: "読書を続けるを1つやる", originalIntent: "部屋を片付ける"))
    }

    @Test("型を選んだ後でも、文字数が上限を超える文では進まない")
    func describeRejectsTooLongText() {
        var machine = machineAtGenericForced()
        _ = machine.chooseGenericType(.prepare)

        _ = machine.submitText(String(repeating: "あ", count: 26) + "を用意する")

        #expect(machine.step == .describe(.prepare))
    }

    @Test("型から作った文に「いいえ」と答えると、もう一度型の選択に入る")
    func noAfterDescribeReturnsToGenericForced() {
        var machine = machineAtGenericForced()
        _ = machine.chooseGenericType(.go)
        _ = machine.submitText("図書館に行く")

        _ = machine.answerTwoMinute(false)

        #expect(machine.step == .genericForced)
        #expect(machine.redecomposeCount == 4)
    }

    @Test("再分解では、テンプレートに該当しなかった場合だけ、型を任意で選べる")
    func optionalGenericPatternInReDecompose() {
        var noTemplate = machineAtTwoMinCheck()
        _ = noTemplate.answerTwoMinute(false)
        #expect(noTemplate.canChooseGenericPattern)
        _ = noTemplate.chooseGenericType(.prepare)
        #expect(noTemplate.step == .describe(.prepare))

        var withTemplate = makeMachine()
        _ = withTemplate.submitText("読書をしたい")
        _ = withTemplate.decomposeMyself()
        _ = withTemplate.answerTwoMinute(false)
        #expect(withTemplate.step == .reDecompose(.notTwoMinutes))
        #expect(!withTemplate.canChooseGenericPattern)
        _ = withTemplate.chooseGenericType(.prepare)
        #expect(withTemplate.step == .reDecompose(.notTwoMinutes))
    }

    @Test("型を選べるステップ以外では、型の選択肢を出さない")
    func genericPatternNotOfferedElsewhere() {
        var machine = makeMachine()
        #expect(!machine.canChooseGenericPattern)

        _ = machine.chooseGenericType(.prepare)
        #expect(machine.step == .freeInput)

        _ = machine.submitText("部屋を片付ける")
        #expect(!machine.canChooseGenericPattern)
    }

    // MARK: 戻る

    @Test("1 問前に戻ると、その問より後の入力は破棄される")
    func backDiscardsLaterInput() {
        var machine = machineAtTwoMinCheck()
        _ = machine.answerTwoMinute(false)
        _ = machine.submitText("床の物を1つ拾う")
        #expect(machine.candidate == "床の物を1つ拾う")

        _ = machine.back()
        #expect(machine.step == .reDecompose(.notTwoMinutes))
        #expect(machine.candidate == "部屋を片付ける")

        _ = machine.back()
        #expect(machine.step == .twoMinCheck)
        #expect(machine.candidate == "部屋を片付ける")

        _ = machine.back()
        #expect(machine.step == .freeInput)
        #expect(machine.candidate.isEmpty)
        #expect(machine.originalIntent.isEmpty)
        #expect(!machine.canGoBack)
    }

    @Test("テンプレートの提示から戻ると、テンプレートの該当も取り消される")
    func backFromTemplateSuggest() {
        var machine = makeMachine()
        _ = machine.submitText("読書をしたい")

        _ = machine.back()

        #expect(machine.step == .freeInput)
        #expect(machine.templateCategory == nil)

        _ = machine.submitText("部屋を片付ける")
        #expect(machine.step == .twoMinCheck)
    }

    @Test("頻度を表す語の提示から戻り、採用をやり直せる")
    func backFromAdverbSuggestion() {
        var machine = makeMachine()
        _ = machine.submitText("毎日新聞を1ページ読む")
        _ = machine.acceptSuggestion()

        _ = machine.back()

        #expect(machine.step == .adverbSuggest(term: "毎日", stripped: "新聞を1ページ読む"))
        #expect(machine.candidate == "毎日新聞を1ページ読む")
    }

    @Test("戻っても再分解の回数は減らない")
    func backDoesNotDecrementCounter() {
        var machine = machineAtTwoMinCheck()
        _ = machine.answerTwoMinute(false)
        #expect(machine.redecomposeCount == 1)

        _ = machine.back()

        #expect(machine.step == .twoMinCheck)
        #expect(machine.redecomposeCount == 1)
    }

    @Test("戻って「いいえ」をくり返すだけでも、3 回目で型の選択に入る")
    func repeatedNoViaBackReachesLimit() {
        var machine = machineAtTwoMinCheck()

        _ = machine.answerTwoMinute(false)
        _ = machine.back()
        _ = machine.answerTwoMinute(false)
        _ = machine.back()
        _ = machine.answerTwoMinute(false)

        #expect(machine.step == .genericForced)
    }

    @Test("上限に達した後に戻って再び進むと、型の選択に入る")
    func afterLimitGoingForwardAgainEntersGenericForced() {
        var machine = machineAtGenericForced()

        _ = machine.back()
        #expect(machine.step == .twoMinCheck)
        #expect(machine.redecomposeCount == 3)
        _ = machine.answerTwoMinute(false)
        #expect(machine.step == .genericForced)

        // さらに前の再分解まで戻り、目標の言い回しを送っても型の選択に入る
        _ = machine.back()
        _ = machine.back()
        #expect(machine.step == .reDecompose(.notTwoMinutes))
        _ = machine.submitText("掃除を頑張る")
        #expect(machine.step == .genericForced)
    }

    // MARK: キャンセル

    @Test("どのステップからでもキャンセルでき、登録にはならず、入力と分解の状態は残らない")
    func cancelFromAnyStep() {
        var steps: [WizardStateMachine] = []
        var machine = makeMachine()
        steps.append(machine)                                   // 自由入力
        _ = machine.submitText("読書をしたい")
        steps.append(machine)                                   // テンプレート提示
        _ = machine.decomposeMyself()
        steps.append(machine)                                   // 2 分確認
        _ = machine.answerTwoMinute(false)
        steps.append(machine)                                   // 再分解
        _ = machine.submitText("必ず本を開く")
        steps.append(machine)                                   // 頻度を表す語の提示
        steps.append(machineAtGenericForced())                  // 型の選択
        var describing = machineAtGenericForced()
        _ = describing.chooseGenericType(.go)
        steps.append(describing)                                // 具体の記述
        #expect(Set(steps.map { "\($0.step)" }).count == 7)

        for var machine in steps {
            #expect(machine.cancel() == .close)

            #expect(machine.step == .freeInput)
            #expect(machine.candidate.isEmpty)
            #expect(machine.originalIntent.isEmpty)
            #expect(machine.redecomposeCount == 0)
            #expect(machine.templateCategory == nil)
            #expect(!machine.canGoBack)
        }
    }

    @Test("キャンセルした後に開き直したウィザードは、自由入力から始まる")
    func reopenedWizardStartsFresh() {
        var cancelled = machineAtGenericForced()
        _ = cancelled.cancel()

        let reopened = makeMachine()

        #expect(reopened.step == .freeInput)
        #expect(reopened.redecomposeCount == 0)
        #expect(reopened.candidate.isEmpty)
    }

    // MARK: そのステップで受け付けない操作

    @Test("そのステップで受け付けない操作は、何も変えない")
    func irrelevantEventsAreIgnored() {
        var machine = makeMachine()
        #expect(machine.answerTwoMinute(true) == .none)
        #expect(machine.selectTemplate("本を開く") == .none)
        #expect(machine.decomposeMyself() == .none)
        #expect(machine.acceptSuggestion() == .none)
        #expect(machine.keepOriginal() == .none)
        #expect(machine.step == .freeInput)
        #expect(!machine.canGoBack)

        var atCheck = machineAtTwoMinCheck()
        #expect(atCheck.submitText("床を拭く") == .none)
        #expect(atCheck.acceptSuggestion() == .none)
        #expect(atCheck.step == .twoMinCheck)
        #expect(atCheck.candidate == "部屋を片付ける")
    }

    // MARK: 言語

    @Test("英語では上限が 60 文字で、英語の検出語がかかる")
    func english() {
        let content = ContentBundle(
            templates: [],
            terms: DetectionTerms(frequencyAdverbs: ["every day"], goalSuffixes: ["keep", "kept"]),
            completionMessages: []
        )
        var machine = makeMachine(language: .en, content: content)

        _ = machine.submitText(String(repeating: "a", count: 61))
        #expect(machine.step == .freeInput)

        _ = machine.submitText("Keep reading")
        #expect(machine.step == .reDecompose(.goalDetected))

        _ = machine.submitText("Read a page every day")
        #expect(machine.step == .adverbSuggest(term: "every day", stripped: "Read a page"))
    }
}
