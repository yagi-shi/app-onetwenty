import Foundation

nonisolated struct TitleValidation: Equatable, Sendable {
    enum State: Sendable {
        case ok
        /// 前後の空白を除くと 0 文字。
        case empty
        case tooLong
    }

    /// 前後の空白を除いた文字数。画面の「現在の文字数」にもこの値を使う。
    let count: Int
    let limit: Int
    let state: State
}

/// 習慣名の文字数を検証する。ウィザードの入力に対してだけ使い、保存済みの習慣名には適用しない。
nonisolated enum TitleValidator {
    static func validate(_ text: String, language: ContentLanguage) -> TitleValidation {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        let limit = language.titleLimit
        let state: TitleValidation.State
        if count == 0 {
            state = .empty
        } else if count > limit {
            state = .tooLong
        } else {
            state = .ok
        }
        return TitleValidation(count: count, limit: limit, state: state)
    }
}
