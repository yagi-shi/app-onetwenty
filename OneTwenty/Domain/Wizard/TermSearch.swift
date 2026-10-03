import Foundation

/// 文の中から語を探す。大文字と小文字は区別しない。
///
/// 英数字で始まる（終わる）語は、その側が単語の区切りになっているときだけ一致とみなす。
/// 「entry to」の中の「try to」や、「bread」の中の「read」を拾わないようにするため。
/// 日本語の語は端が英数字ではないので、文のどこにあっても一致する。
/// 言語による違いは語そのものの文字で決まり、探し方は日本語・英語で共通。
nonisolated enum TermSearch {
    enum Boundary: Sendable {
        /// 語の前後とも、単語の区切りであること（検出語に使う）。
        case wholeWord
        /// 語の前だけ、単語の区切りであること。「read」が「reading」にも一致する（キーワードに使う）。
        case wordStart
    }

    /// 文の中で最も手前にある一致を返す。
    static func firstRange(of term: String, in text: String, boundary: Boundary) -> Range<String.Index>? {
        guard let first = term.first, let last = term.last else { return nil }

        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: term, options: .caseInsensitive, range: searchRange) {
            let startsAtBoundary = !isWordCharacter(first)
                || range.lowerBound == text.startIndex
                || !isWordCharacter(text[text.index(before: range.lowerBound)])
            let endsAtBoundary = boundary == .wordStart
                || !isWordCharacter(last)
                || range.upperBound == text.endIndex
                || !isWordCharacter(text[range.upperBound])
            if startsAtBoundary, endsAtBoundary {
                return range
            }
            // 区切りに合わない一致は読み飛ばして、その先を探す
            searchRange = text.index(after: range.lowerBound)..<text.endIndex
        }
        return nil
    }

    /// 英単語を形づくる文字（半角の英字と数字）。
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
}
