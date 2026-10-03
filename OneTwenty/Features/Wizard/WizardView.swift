import SwiftUI

/// 「やりたいこと」を 2 分で終わる行動に分解するウィザード。1 問を 1 画面で聞く。
struct WizardView: View {
    @Bindable var viewModel: WizardViewModel
    @FocusState private var isTextFieldFocused: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            // キャンセルは、どのステップでも同じ位置に出す
            HStack {
                Button("wizard.cancel") { viewModel.cancel() }
                Spacer()
            }
            .padding()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(WizardText.question(for: viewModel.step))
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)

            HStack {
                if viewModel.machine.canGoBack {
                    Button("wizard.back") { viewModel.back() }
                }
                Spacer()
                if viewModel.acceptsText {
                    Button("wizard.next") {
                        Task { await viewModel.submit() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canSubmit)
                    .accessibilityHint(blockerHint ?? "")
                }
            }
            .padding()
        }
        .disabled(viewModel.isSaving)
        .alert(alertTitle, isPresented: isAlertPresented) {
            Button("common.ok") { viewModel.dismissAlert() }
        }
        .onChange(of: viewModel.step, initial: true) {
            isTextFieldFocused = viewModel.acceptsText
        }
    }

    // MARK: ステップごとの中身

    @ViewBuilder
    private var content: some View {
        switch viewModel.step {
        case .freeInput, .editInput:
            textInput
        case .reDecompose:
            textInput
            if viewModel.machine.canChooseGenericPattern {
                // テンプレートに当たらなかったときは、型から選ぶこともできる
                Text("wizard.generic.optional")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                patternButtons
            }
        case .describe:
            textInput
            if let composed = viewModel.composedText {
                Text(composed)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text("wizard.describe.preview \(composed)"))
            }
        case .templateSuggest(let category):
            VStack(alignment: .leading, spacing: 12) {
                ForEach(category.templates, id: \.self) { template in
                    choiceButton(template) { await viewModel.selectTemplate(template) }
                }
                choiceButton(String(localized: "wizard.decomposeMyself")) { await viewModel.decomposeMyself() }
            }
        case .adverbSuggest:
            VStack(alignment: .leading, spacing: 12) {
                choiceButton(String(localized: "wizard.adverb.accept")) { await viewModel.acceptSuggestion() }
                choiceButton(String(localized: "wizard.adverb.keep")) { await viewModel.keepOriginal() }
            }
        case .twoMinCheck:
            Text(viewModel.machine.candidate)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)
            // 文字を大きくしているときは、横に並べると語の途中で折れるので縦に並べる
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                choiceButton(String(localized: "wizard.yes")) { await viewModel.answerTwoMinute(true) }
                choiceButton(String(localized: "wizard.no")) { await viewModel.answerTwoMinute(false) }
            }
        case .genericForced:
            patternButtons
        }
    }

    private var textInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1 文だけを受け付けるので、改行できない 1 行の入力欄にする
            TextField(text: $viewModel.text, prompt: Text(placeholder)) {
                Text(WizardText.question(for: viewModel.step))
            }
            .textFieldStyle(.roundedBorder)
            .font(.body)
            .focused($isTextFieldFocused)
            .submitLabel(.next)
            .onSubmit { Task { await viewModel.submit() } }
            .accessibilityHint(blockerHint ?? "")

            let validation = viewModel.validation
            Text(verbatim: "\(validation.count) / \(validation.limit)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(validation.state == .tooLong ? Color.red : Color.secondary)
                .accessibilityLabel(Text("wizard.count.accessibility \(validation.count) \(validation.limit)"))
        }
    }

    private var patternButtons: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(GenericPattern.allCases, id: \.self) { pattern in
                choiceButton(WizardText.patternTitle(pattern)) { await viewModel.chooseGenericType(pattern) }
            }
        }
    }

    private func choiceButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }

    // MARK: 文言

    private var placeholder: String {
        if case .describe(let pattern) = viewModel.step {
            return WizardText.describePrompt(pattern)
        }
        return ""
    }

    /// 送信できない理由。読み上げで伝える。
    private var blockerHint: String? {
        switch viewModel.submitBlocker {
        case .tooLong:
            String(localized: "wizard.count.tooLongHint \(viewModel.validation.limit)")
        case .emptyInput:
            String(localized: "wizard.emptyHint")
        case nil:
            nil
        }
    }

    private var alertTitle: String {
        switch viewModel.alert {
        case .limitReached: String(localized: "wizard.alert.limitReached")
        case .saveFailed, nil: String(localized: "common.alert.saveFailed")
        }
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { viewModel.alert != nil },
            set: { if !$0 { viewModel.dismissAlert() } }
        )
    }
}

extension WizardText {
    static func question(for step: WizardStateMachine.Step) -> String {
        switch step {
        case .freeInput:
            String(localized: "wizard.question.freeInput")
        case .editInput:
            String(localized: "wizard.question.editInput")
        case .templateSuggest:
            String(localized: "wizard.question.templates")
        case .adverbSuggest(let term, let stripped):
            String(localized: "wizard.question.adverb \(term) \(stripped)")
        case .twoMinCheck:
            String(localized: "wizard.question.twoMinutes")
        case .reDecompose(.notTwoMinutes):
            String(localized: "wizard.question.firstAction")
        case .reDecompose(.goalDetected):
            String(localized: "wizard.question.goal")
        case .genericForced:
            String(localized: "wizard.question.generic")
        case .describe(let pattern):
            describePrompt(pattern)
        }
    }

    static func patternTitle(_ pattern: GenericPattern) -> String {
        switch pattern {
        case .prepare: String(localized: "wizard.generic.prepare")
        case .go: String(localized: "wizard.generic.go")
        case .doOne: String(localized: "wizard.generic.doOne")
        }
    }

    static func describePrompt(_ pattern: GenericPattern) -> String {
        switch pattern {
        case .prepare: String(localized: "wizard.describe.prepare")
        case .go: String(localized: "wizard.describe.go")
        case .doOne: String(localized: "wizard.describe.doOne")
        }
    }
}
