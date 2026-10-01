import Testing
@testable import OneTwenty

struct LanguageResolverTests {

    @Test("日本語の表示言語は日本語になる", arguments: ["ja", "ja-JP", "ja_JP", "JA"])
    func japanese(localization: String) {
        #expect(LanguageResolver.resolve(preferredLocalization: localization) == .ja)
    }

    @Test("日本語以外の表示言語は英語になる", arguments: ["en", "en-GB", "fr", "zh-Hans", "ko", ""])
    func nonJapanese(localization: String) {
        #expect(LanguageResolver.resolve(preferredLocalization: localization) == .en)
    }

    @Test("表示言語が取れないときは英語になる")
    func missingLocalization() {
        #expect(LanguageResolver.resolve(preferredLocalization: nil) == .en)
    }

    @Test("文字数の上限は日本語 30・英語 60")
    func titleLimits() {
        #expect(ContentLanguage.ja.titleLimit == 30)
        #expect(ContentLanguage.en.titleLimit == 60)
    }
}
