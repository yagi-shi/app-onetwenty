import Foundation
import Testing
@testable import OneTwenty

/// 画面の文言が満たすべき制約。ビルドしたアプリに入っている翻訳ファイルを直接読んで確かめる。
@MainActor
struct StringCatalogTests {
    private func directory(_ language: String) throws -> URL {
        try #require(Bundle.main.url(forResource: language, withExtension: "lproj"))
    }

    /// その言語に翻訳があるキーの一覧。単数・複数で文が変わるものは別のファイルに入っているので、両方を合わせる。
    private func keys(_ language: String) throws -> Set<String> {
        let directory = try directory(language)
        var keys: Set<String> = []
        for name in ["Localizable.strings", "Localizable.stringsdict"] {
            let contents = NSDictionary(contentsOf: directory.appendingPathComponent(name)) as? [String: Any]
            keys.formUnion(contents?.keys.map { $0 } ?? [])
        }
        return keys
    }

    private func text(_ key: String, language: String) throws -> String {
        let bundle = try #require(Bundle(url: try directory(language)))
        return bundle.localizedString(forKey: key, value: "（翻訳なし）", table: nil)
    }

    @Test("日本語と英語で、同じキーがすべて翻訳されている")
    func everyKeyIsTranslatedInBothLanguages() throws {
        let japanese = try keys("ja")
        let english = try keys("en")

        #expect(!japanese.isEmpty)
        #expect(japanese.subtracting(english).isEmpty, "英語にない: \(japanese.subtracting(english).sorted())")
        #expect(english.subtracting(japanese).isEmpty, "日本語にない: \(english.subtracting(japanese).sorted())")
    }

    @Test("空の文言がない", arguments: ["ja", "en"])
    func noEmptyText(language: String) throws {
        let contents = NSDictionary(
            contentsOf: try directory(language).appendingPathComponent("Localizable.strings")
        ) as? [String: String]

        for (key, value) in try #require(contents) {
            #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key)")
        }
    }

    @Test("通知の文言は固定で、習慣名などを差し込む場所を持たない", arguments: ["ja", "en"])
    func notificationBodiesHaveNoPlaceholders(language: String) throws {
        for key in ["notification.timer.body", "notification.reminder.body"] {
            let body = try text(key, language: language)

            #expect(body != "（翻訳なし）", "\(key)")
            #expect(!body.contains("%"), "\(key): \(body)")
        }
    }

    @Test("汎用パターンの文型は、入力を差し込む場所をちょうど 1 つ持つ", arguments: ["ja", "en"])
    func genericPatternFormatsHaveOnePlaceholder(language: String) throws {
        for key in ["wizard.generic.prepare.format", "wizard.generic.go.format", "wizard.generic.doOne.format"] {
            let format = try text(key, language: language)

            #expect(format.components(separatedBy: "%@").count == 2, "\(key): \(format)")
        }
    }

    @Test("完了文言の一覧が読めないときに使う一言も、文字数の上限に収まる", arguments: [("ja", 20), ("en", 40)])
    func defaultCompletionMessageIsShortEnough(language: String, limit: Int) throws {
        let message = try text("timer.completion.default", language: language)

        #expect(message != "（翻訳なし）")
        #expect(message.count <= limit)
    }
}
