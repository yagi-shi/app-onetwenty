import Foundation

/// 自力で分解しきれないときに選ぶ、行動の型。
nonisolated enum GenericPattern: CaseIterable, Sendable {
    /// 道具を用意する。
    case prepare
    /// その場所に行く。
    case go
    /// 最小単位を 1 つやる。
    case doOne
}

/// 状態機械が呼び出し側に求める処理。
nonisolated enum WizardEffect: Equatable, Sendable {
    case none
    /// 習慣として登録する。成否は状態機械には分からないので、成功したら呼び出し側が画面を閉じる。
    case register(title: String, originalIntent: String)
    case close
}

/// 「やりたいこと」を 2 分で終わる行動に分解するウィザードの進行。
/// 画面を持たず、状態と入力だけで次のステップが決まる。
nonisolated struct WizardStateMachine: Sendable {
    enum Origin: Sendable {
        case home
        case onboarding
    }

    enum Mode: Equatable, Sendable {
        case new(origin: Origin)
    }

    enum ReDecomposeReason: Sendable {
        /// 2 分確認で「いいえ」と答えた。
        case notTwoMinutes
        /// 目標の言い回しを検出した。
        case goalDetected
    }

    enum Step: Equatable, Sendable {
        case freeInput
        case templateSuggest(TemplateCategory)
        case adverbSuggest(term: String, stripped: String)
        case twoMinCheck
        case reDecompose(ReDecomposeReason)
        /// 再分解を繰り返しても決まらなかったので、型から選んでもらう。自由な再分解はできない。
        case genericForced
        case describe(GenericPattern)
    }

    /// 再分解に入った回数がこの値に達したら、型の選択に切り替える。
    static let redecomposeLimit = 3

    let mode: Mode
    private(set) var step: Step = .freeInput
    /// 登録の候補になっている文。
    private(set) var candidate = ""
    /// 最初に自由入力した文。テンプレートを選んでも、再分解しても変わらない。
    private(set) var originalIntent = ""
    /// 再分解に入った回数。戻っても減らない。
    private(set) var redecomposeCount = 0
    private(set) var templateCategory: TemplateCategory?

    private let language: ContentLanguage
    private let templates: [TemplateCategory]
    private let terms: DetectionTerms
    private var history: [Snapshot] = []

    private struct Snapshot: Sendable {
        let step: Step
        let candidate: String
        let originalIntent: String
        let templateCategory: TemplateCategory?
    }

    init(mode: Mode, language: ContentLanguage, content: ContentBundle) {
        self.mode = mode
        self.language = language
        templates = content.templates
        terms = content.terms
    }

    var canGoBack: Bool {
        !history.isEmpty
    }

    /// 型の選択肢を出すかどうか。再分解では、テンプレートに該当しなかった場合だけ任意の選択肢として出す。
    var canChooseGenericPattern: Bool {
        switch step {
        case .genericForced: true
        case .reDecompose: templateCategory == nil
        default: false
        }
    }

    // MARK: 入力

    /// 文を送信する。文字数が上限を超えている・空の場合は何も起きない。
    /// `describe` では、型の文型に入力を差し込んだ後の文を渡す。
    mutating func submitText(_ text: String) -> WizardEffect {
        guard TitleValidator.validate(text, language: language).state == .ok else { return .none }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        switch step {
        case .freeInput:
            pushHistory()
            originalIntent = text
            candidate = text
            templateCategory = TemplateMatcher.match(text, categories: templates)
            if let templateCategory {
                step = .templateSuggest(templateCategory)
            } else {
                detect()
            }
        case .reDecompose:
            pushHistory()
            candidate = text
            detect()
        case .describe:
            // 型は既に行動の形なので検出はかけない。かけると、型の選択に戻され続けて抜けられなくなる
            pushHistory()
            candidate = text
            step = .twoMinCheck
        case .templateSuggest, .adverbSuggest, .twoMinCheck, .genericForced:
            break
        }
        return .none
    }

    mutating func selectTemplate(_ template: String) -> WizardEffect {
        guard case .templateSuggest(let category) = step, category.templates.contains(template) else {
            return .none
        }
        pushHistory()
        candidate = template
        step = .twoMinCheck
        return .none
    }

    mutating func decomposeMyself() -> WizardEffect {
        guard case .templateSuggest = step else { return .none }
        pushHistory()
        candidate = originalIntent
        detect()
        return .none
    }

    mutating func answerTwoMinute(_ fitsInTwoMinutes: Bool) -> WizardEffect {
        guard step == .twoMinCheck else { return .none }
        if fitsInTwoMinutes {
            return .register(title: candidate, originalIntent: originalIntent)
        }
        pushHistory()
        enterReDecompose(reason: .notTwoMinutes)
        return .none
    }

    mutating func acceptSuggestion() -> WizardEffect {
        guard case .adverbSuggest(_, let stripped) = step else { return .none }
        pushHistory()
        candidate = stripped
        step = .twoMinCheck
        return .none
    }

    mutating func keepOriginal() -> WizardEffect {
        guard case .adverbSuggest = step else { return .none }
        pushHistory()
        step = .twoMinCheck
        return .none
    }

    mutating func chooseGenericType(_ pattern: GenericPattern) -> WizardEffect {
        guard canChooseGenericPattern else { return .none }
        pushHistory()
        step = .describe(pattern)
        return .none
    }

    /// 1 問前に戻る。戻った問より後の入力は捨てるが、再分解の回数は減らさない。
    mutating func back() -> WizardEffect {
        guard let previous = history.popLast() else { return .none }
        step = previous.step
        candidate = previous.candidate
        originalIntent = previous.originalIntent
        templateCategory = previous.templateCategory
        return .none
    }

    /// 途中の入力と分解の状態をすべて捨てる。
    mutating func cancel() -> WizardEffect {
        self = WizardStateMachine(
            mode: mode,
            language: language,
            content: ContentBundle(templates: templates, terms: terms, completionMessages: [])
        )
        return .close
    }

    // MARK: 遷移

    /// 候補の文が決まるたびに通る合流点。
    private mutating func detect() {
        switch PhraseDetector.detect(candidate, terms: terms) {
        case .goalSuffix:
            enterReDecompose(reason: .goalDetected)
        case .frequencyAdverb(let term, let stripped):
            step = .adverbSuggest(term: term, stripped: stripped)
        case .none:
            step = .twoMinCheck
        }
    }

    private mutating func enterReDecompose(reason: ReDecomposeReason) {
        redecomposeCount += 1
        step = redecomposeCount >= Self.redecomposeLimit ? .genericForced : .reDecompose(reason)
    }

    private mutating func pushHistory() {
        history.append(Snapshot(
            step: step,
            candidate: candidate,
            originalIntent: originalIntent,
            templateCategory: templateCategory
        ))
    }
}
