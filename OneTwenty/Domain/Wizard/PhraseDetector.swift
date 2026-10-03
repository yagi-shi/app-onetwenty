import Foundation

nonisolated enum Detection: Equatable, Sendable {
    case none
    /// 目標を表す言い回し。行動に分解し直してもらう。
    case goalSuffix(term: String)
    /// 頻度を表す語。`stripped` はその語を取り除いた文。
    case frequencyAdverb(term: String, stripped: String)
}

/// 習慣名に含まれる「目標の言い回し」と「頻度を表す語」を、検出語リストとの照合で見つける。
/// リストにない語は検出しない。英語の語は単語の区切りでだけ一致する（`TermSearch`）。
nonisolated enum PhraseDetector {
    static func detect(_ text: String, terms: DetectionTerms) -> Detection {
        if let goal = firstMatch(in: text, terms: terms.goalSuffixes) {
            return .goalSuffix(term: goal.term)
        }
        guard let adverb = firstMatch(in: text, terms: terms.frequencyAdverbs) else {
            return .none
        }
        var stripped = text
        stripped.removeSubrange(adverb.range)
        stripped = collapsingWhitespace(stripped)
        // 頻度を表す語だけの入力では、取り除くと何も残らない。空の代替案は出さない
        return stripped.isEmpty ? .none : .frequencyAdverb(term: adverb.term, stripped: stripped)
    }

    /// 文の中で最も手前にある一致を返す。同じ位置で複数の語が一致する場合は長い語を選ぶ。
    private static func firstMatch(in text: String, terms: [String]) -> (term: String, range: Range<String.Index>)? {
        var best: (term: String, range: Range<String.Index>)?
        for term in terms where !term.isEmpty {
            guard let range = TermSearch.firstRange(of: term, in: text, boundary: .wholeWord) else { continue }
            guard let current = best else {
                best = (term, range)
                continue
            }
            let isEarlier = range.lowerBound < current.range.lowerBound
            let isLongerAtSamePosition = range.lowerBound == current.range.lowerBound
                && range.upperBound > current.range.upperBound
            if isEarlier || isLongerAtSamePosition {
                best = (term, range)
            }
        }
        return best
    }

    /// 連続する空白を 1 つにまとめ、前後の空白を削る。
    private static func collapsingWhitespace(_ text: String) -> String {
        var result = ""
        for character in text {
            if character.isWhitespace, result.last?.isWhitespace == true { continue }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
