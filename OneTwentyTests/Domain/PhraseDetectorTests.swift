import Testing
@testable import OneTwenty

struct PhraseDetectorTests {
    private let ja = DetectionTerms(
        frequencyAdverbs: ["毎日", "毎朝", "必ず"],
        goalSuffixes: ["を続ける", "を頑張る"]
    )
    private let en = DetectionTerms(
        frequencyAdverbs: ["every day", "everyday", "daily", "always", "every morning"],
        goalSuffixes: ["keep", "keeps", "keeping", "kept", "try to", "work on"]
    )

    // MARK: 検出する・しない

    @Test("リストにない語は検出しない", arguments: ["本を1ページ読む", "たまに走る", "毎週掃除する", "靴を履く"])
    func ignoresTermsOutsideTheList(text: String) {
        #expect(PhraseDetector.detect(text, terms: ja) == .none)
    }

    @Test("検出語リストが空なら何も検出しない")
    func emptyTermsDetectNothing() {
        #expect(PhraseDetector.detect("毎日読書を続ける", terms: .empty) == .none)
    }

    @Test("目標の言い回しを検出する")
    func detectsGoalSuffix() {
        #expect(PhraseDetector.detect("読書を続ける", terms: ja) == .goalSuffix(term: "を続ける"))
        #expect(PhraseDetector.detect("英語を頑張る", terms: ja) == .goalSuffix(term: "を頑張る"))
    }

    @Test("英語の活用形は、リストに並んだ形をすべて検出する", arguments: [
        ("Keep reading", "keep"),
        ("He keeps a diary", "keeps"),
        ("keeping fit", "keeping"),
        ("I kept running", "kept"),
    ])
    func detectsEnglishInflections(text: String, term: String) {
        #expect(PhraseDetector.detect(text, terms: en) == .goalSuffix(term: term))
    }

    @Test("英語の語が別の単語の一部として現れても、検出しない", arguments: [
        "Add an entry to my journal",
        "Put my homework on the desk",
        "Do some housekeeping",
        "Read the skeptical review",
    ])
    func ignoresEnglishTermsInsideOtherWords(text: String) {
        #expect(PhraseDetector.detect(text, terms: en) == .none)
    }

    @Test("英語は大文字と小文字を区別しない", arguments: ["KEEP READING", "Try To Run", "tRy tO run"])
    func englishIsCaseInsensitive(text: String) {
        guard case .goalSuffix = PhraseDetector.detect(text, terms: en) else {
            Issue.record("目標の言い回しとして検出されるはず: \(text)")
            return
        }
    }

    @Test("目標の言い回しと頻度を表す語の両方を含むなら、目標の言い回しを優先する")
    func goalSuffixTakesPriority() {
        #expect(PhraseDetector.detect("毎日読書を続ける", terms: ja) == .goalSuffix(term: "を続ける"))
        #expect(PhraseDetector.detect("Keep reading every day", terms: en) == .goalSuffix(term: "keep"))
    }

    // MARK: 頻度を表す語の除去

    @Test("「毎日新聞を1ページ読む」は拒否せず、「毎日」を除いた文を示す")
    func stripsFrequencyAdverb() {
        let result = PhraseDetector.detect("毎日新聞を1ページ読む", terms: ja)

        #expect(result == .frequencyAdverb(term: "毎日", stripped: "新聞を1ページ読む"))
    }

    @Test("頻度を表す語だけの入力は、除くと空になるので検出しない", arguments: ["毎日", " 毎日 ", "　必ず　", "daily"])
    func adverbOnlyIsNotDetected(text: String) {
        let terms = text == "daily" ? en : ja

        #expect(PhraseDetector.detect(text, terms: terms) == .none)
    }

    @Test("語を除いた後の空白を整える", arguments: [
        ("Read a page every day", "every day", "Read a page"),
        ("Every day read a page", "every day", "read a page"),
        ("Read every day one page", "every day", "Read one page"),
        ("Run everyday", "everyday", "Run"),
        ("毎朝　ストレッチする", "毎朝", "ストレッチする"),
        ("水を1杯　飲む 必ず", "必ず", "水を1杯　飲む"),
    ])
    func normalizesWhitespaceAfterStripping(text: String, term: String, stripped: String) {
        let terms = text.unicodeScalars.contains { $0.value > 0x2E7F } ? ja : en

        #expect(PhraseDetector.detect(text, terms: terms) == .frequencyAdverb(term: term, stripped: stripped))
    }

    @Test("複数の語を含むときは、文の中で最初に現れる 1 語だけを除く")
    func stripsOnlyTheFirstMatch() {
        #expect(PhraseDetector.detect("Always stretch daily", terms: en)
            == .frequencyAdverb(term: "always", stripped: "stretch daily"))
        #expect(PhraseDetector.detect("毎日毎日走る", terms: ja)
            == .frequencyAdverb(term: "毎日", stripped: "毎日走る"))
    }

    @Test("同じ位置で複数の語が一致するときは、長い語を除く")
    func prefersLongerTermAtSamePosition() {
        let terms = DetectionTerms(frequencyAdverbs: ["every", "every morning"], goalSuffixes: [])

        #expect(PhraseDetector.detect("Stretch every morning", terms: terms)
            == .frequencyAdverb(term: "every morning", stripped: "Stretch"))
    }
}

@MainActor
struct PhraseDetectorBundledTermsTests {

    @Test("同梱した検出語は、どの語も検出される", arguments: [ContentLanguage.ja, .en])
    func everyBundledTermIsDetected(language: ContentLanguage) {
        let terms = ContentLoader().load(language: language).terms
        let filler = language == .ja ? "本" : "book "

        for term in terms.goalSuffixes {
            #expect(PhraseDetector.detect(filler + term, terms: terms) == .goalSuffix(term: term))
        }
        for term in terms.frequencyAdverbs {
            guard case .frequencyAdverb = PhraseDetector.detect(filler + term, terms: terms) else {
                Issue.record("頻度を表す語として検出されるはず: \(term)")
                continue
            }
        }
    }
}
