import Foundation
import Observation

/// ウィザードの画面の状態。進行の規則は `WizardStateMachine` が持ち、この型は入力欄と保存を受け持つ。
/// 画面を閉じるのはこの型ではなく、提示している側（`AppCoordinator`）。
@Observable
final class WizardViewModel {
    enum Alert: Equatable {
        /// 保存に失敗した。閉じずに、同じ操作をやり直せる。
        case saveFailed
        /// 習慣が上限に達していて登録できない。OK で閉じる。
        case limitReached
    }

    private(set) var machine: WizardStateMachine
    /// 入力欄の文字列。
    var text: String
    private(set) var alert: Alert?
    private(set) var isSaving = false

    @ObservationIgnored var onFinish: ((WizardFinish) -> Void)?

    @ObservationIgnored private let habitService: HabitService
    @ObservationIgnored private let language: ContentLanguage
    /// 進んだ問ごとに、その問で入力していた文字列。戻ったときに入力欄へ戻す。
    @ObservationIgnored private var inputHistory: [String] = []

    init(mode: WizardStateMachine.Mode, habitService: HabitService, language: ContentLanguage, content: ContentBundle) {
        let machine = WizardStateMachine(mode: mode, language: language, content: content)
        self.machine = machine
        self.habitService = habitService
        self.language = language
        text = machine.initialText
    }

    var step: WizardStateMachine.Step {
        machine.step
    }

    /// 入力欄を出すステップか。
    var acceptsText: Bool {
        switch step {
        case .freeInput, .editInput, .reDecompose, .describe: true
        default: false
        }
    }

    /// 「具体の記述」で、型の文型に入力を差し込んだ後の文。それ以外のステップでは `nil`。
    var composedText: String? {
        guard case .describe(let pattern) = step else { return nil }
        return WizardText.compose(pattern, with: trimmedText)
    }

    /// 文字数の表示と送信の可否に使う検証結果。「具体の記述」では、合成後の文を数える。
    var validation: TitleValidation {
        TitleValidator.validate(composedText ?? text, language: language)
    }

    /// 送信できない理由。送信できるなら `nil`。
    var submitBlocker: SubmitBlocker? {
        if case .describe = step, trimmedText.isEmpty {
            // 型の文型は空でないので、合成後の文だけを見ると空の入力が通ってしまう
            return .emptyInput
        }
        switch validation.state {
        case .ok: return nil
        case .empty: return .emptyInput
        case .tooLong: return .tooLong
        }
    }

    enum SubmitBlocker: Equatable {
        case emptyInput
        case tooLong
    }

    var canSubmit: Bool {
        acceptsText && submitBlocker == nil && !isSaving
    }

    // MARK: 操作

    func submit() async {
        guard canSubmit else { return }
        // 状態機械を書き換えている最中に状態機械を読まないよう、送る文を先に決める
        let submission = composedText ?? text
        await perform { $0.submitText(submission) }
    }

    func selectTemplate(_ template: String) async {
        await perform { $0.selectTemplate(template) }
    }

    func decomposeMyself() async {
        await perform { $0.decomposeMyself() }
    }

    func answerTwoMinute(_ fitsInTwoMinutes: Bool) async {
        await perform { $0.answerTwoMinute(fitsInTwoMinutes) }
    }

    func acceptSuggestion() async {
        await perform { $0.acceptSuggestion() }
    }

    func keepOriginal() async {
        await perform { $0.keepOriginal() }
    }

    func chooseGenericType(_ pattern: GenericPattern) async {
        await perform { $0.chooseGenericType(pattern) }
    }

    func back() {
        guard !isSaving else { return }
        let depth = machine.historyDepth
        _ = machine.back()
        if machine.historyDepth < depth {
            text = inputHistory.popLast() ?? ""
        }
    }

    func cancel() {
        _ = machine.cancel()
        onFinish?(.cancelled)
    }

    /// アラートの OK。上限に達していた場合は、やり直しても登録できないので閉じる。
    func dismissAlert() {
        let dismissed = alert
        alert = nil
        if dismissed == .limitReached {
            _ = machine.cancel()
            onFinish?(.limitReached)
        }
    }

    // MARK: 内部

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func perform(_ event: (inout WizardStateMachine) -> WizardEffect) async {
        guard !isSaving else { return }
        let depth = machine.historyDepth
        let input = text
        let effect = event(&machine)
        if machine.historyDepth > depth {
            inputHistory.append(input)
            text = ""
        }
        await handle(effect)
    }

    private func handle(_ effect: WizardEffect) async {
        switch effect {
        case .none:
            break
        case .close:
            onFinish?(.cancelled)
        case .register(let title, let originalIntent):
            await save { try await habitService.register(title: title, originalIntent: originalIntent) }
        case .rename(let habitID, let title):
            await save { try await habitService.rename(habitID: habitID, title: title) }
        }
    }

    /// 保存に成功したときだけ終わったことを知らせる。失敗したら状態を保ったまま知らせる。
    private func save(_ operation: () async throws -> Void) async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await operation()
            onFinish?(.succeeded)
        } catch HabitError.limitReached {
            alert = .limitReached
        } catch {
            alert = .saveFailed
        }
    }
}

/// ウィザードの文言。
enum WizardText {
    /// 型の文型に入力を差し込んで、1 つの文にする。
    static func compose(_ pattern: GenericPattern, with input: String) -> String {
        String(format: format(pattern), input)
    }

    private static func format(_ pattern: GenericPattern) -> String {
        switch pattern {
        case .prepare: String(localized: "wizard.generic.prepare.format", defaultValue: "Get out your %@")
        case .go: String(localized: "wizard.generic.go.format", defaultValue: "Go to %@")
        case .doOne: String(localized: "wizard.generic.doOne.format", defaultValue: "Do one %@")
        }
    }
}
