import Testing
@testable import OneTwenty

struct TermSearchTests {
    private func found(_ term: String, in text: String, _ boundary: TermSearch.Boundary = .wholeWord) -> Bool {
        TermSearch.firstRange(of: term, in: text, boundary: boundary) != nil
    }

    // MARK: 英語の語（単語の区切り）

    @Test("英語の語は、単語の途中にあっても一致しない", arguments: [
        ("try to", "Add an entry to my journal"),
        ("work on", "Put my homework on the desk"),
        ("keep", "Do some housekeeping"),
        ("kept", "Be skeptical"),
        ("keep", "keeps a diary"),
        ("daily", "dailyish"),
        ("keep", "keep2"),
    ])
    func englishTermInsideAnotherWord(term: String, text: String) {
        #expect(!found(term, in: text))
    }

    @Test("英語の語は、前後が単語の区切りなら一致する", arguments: [
        ("try to", "Try to read"),
        ("try to", "I will try to."),
        ("keep", "keep"),
        ("keep", "Just keep going"),
        ("keep", "keep-fit class"),
        ("keep", "(keep)"),
        ("every day", "Read a page every day"),
    ])
    func englishTermAtWordBoundaries(term: String, text: String) {
        #expect(found(term, in: text))
    }

    @Test("区切りに合わない一致は読み飛ばし、その先にある一致を返す")
    func skipsNonBoundaryOccurrence() throws {
        let text = "housekeeping to keep fit"

        let range = try #require(TermSearch.firstRange(of: "keep", in: text, boundary: .wholeWord))

        #expect(text[range] == "keep")
        #expect(text[range.upperBound...] == " fit")
    }

    @Test("大文字と小文字は区別しない")
    func caseInsensitive() {
        #expect(found("keep", in: "KEEP reading"))
        #expect(found("Every Day", in: "read every day"))
    }

    // MARK: キーワード（単語の先頭）

    @Test("単語の先頭からの一致は、語尾が続いていても一致する", arguments: ["read", "Read more", "reading time", "I reads"])
    func wordStartMatchesPrefix(text: String) {
        #expect(found("read", in: text, .wordStart))
    }

    @Test("単語の先頭からの一致は、単語の途中から始まるものを拾わない", arguments: ["Bake bread", "already done", "spreadsheet"])
    func wordStartIgnoresMidWord(text: String) {
        #expect(!found("read", in: text, .wordStart))
    }

    // MARK: 日本語の語（区切りを見ない）

    @Test("日本語の語は、文のどこにあっても一致する", arguments: [
        ("毎日", "毎日新聞を1ページ読む"),
        ("を続ける", "読書を続ける"),
        ("を続ける", "TOEICを続ける"),
        ("走", "毎朝走る"),
    ])
    func japaneseTermMatchesAnywhere(term: String, text: String) {
        #expect(found(term, in: text))
        #expect(found(term, in: text, .wordStart))
    }

    @Test("英字の語でも、隣が日本語の文字なら単語の区切りとして扱う")
    func japaneseNeighborsCountAsBoundary() {
        #expect(found("TOEIC", in: "新TOEICの勉強"))
        #expect(!found("TOEIC", in: "TOEICS"))
    }

    @Test("空の語は一致しない")
    func emptyTerm() {
        #expect(!found("", in: "何か"))
        #expect(!found("", in: ""))
    }
}
