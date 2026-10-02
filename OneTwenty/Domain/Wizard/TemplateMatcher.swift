import Foundation

/// 自由入力に合う「始め方の例」のカテゴリを、キーワードとの部分一致で探す。
nonisolated enum TemplateMatcher {
    /// データの並び順で最初に一致したカテゴリを返す。どれにも一致しなければ `nil`。
    static func match(_ text: String, categories: [TemplateCategory]) -> TemplateCategory? {
        categories.first { category in
            category.keywords.contains { keyword in
                !keyword.isEmpty && text.range(of: keyword, options: .caseInsensitive) != nil
            }
        }
    }
}
