import Foundation

/// 言語によって中身が変わるもの（文字数上限・検出語・テンプレート・完了文言）の切り替え先。
nonisolated enum ContentLanguage: String, Sendable {
    case ja
    case en

    var titleLimit: Int {
        switch self {
        case .ja: 30
        case .en: 60
        }
    }
}

/// 「表示言語が日本語なら日本語、それ以外は英語」の判定を1か所に集める。
nonisolated enum LanguageResolver {
    /// - Parameter preferredLocalization: 本番では `Bundle.main.preferredLocalizations.first` を渡す。
    static func resolve(preferredLocalization: String?) -> ContentLanguage {
        let languageCode = preferredLocalization?
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first?
            .lowercased()
        return languageCode == "ja" ? .ja : .en
    }
}
