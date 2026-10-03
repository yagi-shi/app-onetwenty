import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct ContentLoaderTests {

    /// 読み込みの失敗を、停止させずに記録する。
    private final class FailureLog {
        var messages: [String] = []
    }

    private func loader(bundle: Bundle = .main, log: FailureLog) -> ContentLoader {
        ContentLoader(bundle: bundle) { log.messages.append($0) }
    }

    // MARK: 同梱ファイルの読み込み

    @Test("日本語・英語とも、同梱した 3 種類のデータを読み込める", arguments: [ContentLanguage.ja, .en])
    func loadsBundledContent(language: ContentLanguage) {
        let log = FailureLog()

        let content = loader(log: log).load(language: language)

        #expect(log.messages.isEmpty)
        #expect(!content.templates.isEmpty)
        #expect(content.templates.allSatisfy { !$0.keywords.isEmpty && !$0.templates.isEmpty })
        #expect(!content.terms.frequencyAdverbs.isEmpty)
        #expect(!content.terms.goalSuffixes.isEmpty)
        #expect(!content.completionMessages.isEmpty)
    }

    @Test("表示言語が日本語なら、検出語とテンプレートは日本語側が選ばれる", arguments: ["ja", "ja-JP"])
    func japaneseLocalizationSelectsJapaneseContent(localization: String) {
        let log = FailureLog()
        let language = LanguageResolver.resolve(preferredLocalization: localization)

        let content = loader(log: log).load(language: language)

        #expect(content.terms.frequencyAdverbs.contains("毎日"))
        #expect(!content.terms.frequencyAdverbs.contains("every day"))
        #expect(content.templates.flatMap(\.templates).contains("本を開く"))
        #expect(content == loader(log: log).load(language: .ja))
    }

    @Test("表示言語が日本語以外なら、検出語とテンプレートは英語側が選ばれる", arguments: ["en", "fr", "zh-Hans"])
    func otherLocalizationSelectsEnglishContent(localization: String) {
        let log = FailureLog()
        let language = LanguageResolver.resolve(preferredLocalization: localization)

        let content = loader(log: log).load(language: language)

        #expect(content.terms.frequencyAdverbs.contains("every day"))
        #expect(!content.terms.frequencyAdverbs.contains("毎日"))
        #expect(content.templates.flatMap(\.templates).contains("Open the book"))
        #expect(content == loader(log: log).load(language: .en))
    }

    // MARK: 欠落・形式不正

    @Test("ファイルがなければ、3 種類とも空のデータになる")
    func missingFilesBecomeEmpty() throws {
        let empty = try TemporaryBundle(files: [:])
        let log = FailureLog()

        let content = loader(bundle: empty.bundle, log: log).load(language: .ja)

        #expect(content == ContentBundle(templates: [], terms: .empty, completionMessages: []))
        #expect(log.messages.count == 3)
    }

    @Test("形式が正しくないファイルだけが空になり、他のデータは読み込める")
    func malformedFileBecomesEmpty() throws {
        let files = try TemporaryBundle(files: [
            "templates.ja.json": "{ これは JSON ではない",
            "detection-terms.ja.json": #"{"frequencyAdverbs":["毎日"],"goalSuffixes":["を続ける"]}"#,
            "completion-messages.ja.json": #"{"messages":["終わりました。"]}"#,
        ])
        let log = FailureLog()

        let content = loader(bundle: files.bundle, log: log).load(language: .ja)

        #expect(content.templates.isEmpty)
        #expect(content.terms == DetectionTerms(frequencyAdverbs: ["毎日"], goalSuffixes: ["を続ける"]))
        #expect(content.completionMessages == ["終わりました。"])
        #expect(log.messages.count == 1)
    }

    @Test("項目が欠けている・型が違うファイルは空になる")
    func wrongShapeBecomesEmpty() throws {
        let files = try TemporaryBundle(files: [
            "templates.en.json": #"{"categories":[{"id":"reading","keywords":["read"]}]}"#,
            "detection-terms.en.json": #"{"frequencyAdverbs":["daily"]}"#,
            "completion-messages.en.json": #"{"messages":"Done."}"#,
        ])
        let log = FailureLog()

        let content = loader(bundle: files.bundle, log: log).load(language: .en)

        #expect(content == ContentBundle(templates: [], terms: .empty, completionMessages: []))
        #expect(log.messages.count == 3)
    }

    @Test("言語はファイル名で選び、別の言語のファイルでは代用しない")
    func doesNotFallBackToAnotherLanguage() throws {
        let files = try TemporaryBundle(files: [
            "completion-messages.en.json": #"{"messages":["Done."]}"#,
        ])
        let log = FailureLog()

        let content = loader(bundle: files.bundle, log: log).load(language: .ja)

        #expect(content.completionMessages.isEmpty)
    }

    // MARK: 同梱データの中身が満たすべき制約

    @Test("テンプレートと完了文言は、日本語・英語とも 20 件以上あり、重複がない", arguments: [ContentLanguage.ja, .en])
    func hasEnoughTemplatesAndMessages(language: ContentLanguage) {
        let content = loader(log: FailureLog()).load(language: language)
        let templates = content.templates.flatMap(\.templates)

        #expect(templates.count >= 20)
        #expect(Set(templates).count == templates.count)
        #expect(content.completionMessages.count >= 20)
        #expect(Set(content.completionMessages).count == content.completionMessages.count)
    }

    @Test("カテゴリの id は重複せず、キーワードとテンプレートに空の文字列がない", arguments: [ContentLanguage.ja, .en])
    func categoriesAreWellFormed(language: ContentLanguage) {
        let categories = loader(log: FailureLog()).load(language: language).templates

        #expect(Set(categories.map(\.id)).count == categories.count)
        for category in categories {
            #expect(category.keywords.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(category.id)")
            #expect(category.templates.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }, "\(category.id)")
        }
    }

    @Test("各テンプレートは、その言語の文字数上限以内で、検出語を含まない", arguments: [ContentLanguage.ja, .en])
    func templatesSatisfyConstraints(language: ContentLanguage) {
        let content = loader(log: FailureLog()).load(language: language)

        for template in content.templates.flatMap(\.templates) {
            #expect(TitleValidator.validate(template, language: language).state == .ok, "\(template)")
            // 選んだテンプレートが、そのまま検出に引っかかって先へ進めなくなることがないように
            #expect(PhraseDetector.detect(template, terms: content.terms) == .none, "\(template)")
        }
    }

    @Test("各完了文言は、日本語 20 文字・英語 40 文字以内", arguments: [(ContentLanguage.ja, 20), (.en, 40)])
    func completionMessagesAreShortEnough(language: ContentLanguage, limit: Int) {
        let content = loader(log: FailureLog()).load(language: language)

        for message in content.completionMessages {
            #expect(!message.isEmpty)
            #expect(message.count <= limit, "\(message)")
        }
    }

    @Test("英語の目標表現は、活用形がそろっている")
    func englishGoalSuffixesListAllInflections() {
        let suffixes = loader(log: FailureLog()).load(language: .en).terms.goalSuffixes

        let inflections = [
            "keep", "keeps", "keeping", "kept",
            "build a habit of", "builds a habit of", "building a habit of", "built a habit of",
            "make a habit of", "makes a habit of", "making a habit of", "made a habit of",
            "try to", "tries to", "trying to", "tried to",
            "work on", "works on", "working on", "worked on",
            "get better at", "gets better at", "getting better at", "got better at", "gotten better at",
        ]
        for inflection in inflections {
            #expect(suffixes.contains(inflection), "\(inflection)")
        }
    }
}
