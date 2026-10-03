import Foundation

/// 自由入力に合う「始め方の例」のカテゴリを、キーワードとの照合で探す。
/// 英語のキーワードは単語の先頭からだけ一致する（`TermSearch`）。
nonisolated enum TemplateMatcher {
    /// データの並び順で最初に一致したカテゴリを返す。どれにも一致しなければ `nil`。
    static func match(_ text: String, categories: [TemplateCategory]) -> TemplateCategory? {
        categories.first { category in
            category.keywords.contains { keyword in
                TermSearch.firstRange(of: keyword, in: text, boundary: .wordStart) != nil
            }
        }
    }
}
