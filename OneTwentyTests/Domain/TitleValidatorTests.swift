import Testing
@testable import OneTwenty

struct TitleValidatorTests {

    @Test("日本語は 30 文字まで", arguments: [
        (29, TitleValidation.State.ok),
        (30, .ok),
        (31, .tooLong),
    ])
    func japaneseBoundary(length: Int, expected: TitleValidation.State) {
        let result = TitleValidator.validate(String(repeating: "あ", count: length), language: .ja)

        #expect(result == TitleValidation(count: length, limit: 30, state: expected))
    }

    @Test("英語は 60 文字まで", arguments: [
        (59, TitleValidation.State.ok),
        (60, .ok),
        (61, .tooLong),
    ])
    func englishBoundary(length: Int, expected: TitleValidation.State) {
        let result = TitleValidator.validate(String(repeating: "a", count: length), language: .en)

        #expect(result == TitleValidation(count: length, limit: 60, state: expected))
    }

    @Test("見た目の 1 文字を 1 文字と数える", arguments: [
        "👨‍👩‍👧‍👦",        // 複数の絵文字を結合した家族
        "👍🏽",          // 肌の色を指定した絵文字
        "か\u{3099}",   // 「か」と濁点の結合形
        "🇯🇵",          // 国旗
    ])
    func countsGraphemeClusters(character: String) {
        let result = TitleValidator.validate(character, language: .ja)

        #expect(result.count == 1)
        #expect(result.state == .ok)
    }

    @Test("絵文字を含んでも上限ちょうどなら通る")
    func emojiAtLimit() {
        let text = String(repeating: "あ", count: 29) + "👨‍👩‍👧‍👦"

        #expect(TitleValidator.validate(text, language: .ja).state == .ok)
        #expect(TitleValidator.validate(text + "あ", language: .ja).state == .tooLong)
    }

    @Test("空と空白のみは空として扱う", arguments: ["", " ", "　", " \t　\n "])
    func emptyOrWhitespaceOnly(text: String) {
        let result = TitleValidator.validate(text, language: .ja)

        #expect(result == TitleValidation(count: 0, limit: 30, state: .empty))
    }

    @Test("前後の空白は文字数に含めない")
    func trimsSurroundingWhitespace() {
        let text = "  " + String(repeating: "あ", count: 30) + "　\n"

        let result = TitleValidator.validate(text, language: .ja)

        #expect(result == TitleValidation(count: 30, limit: 30, state: .ok))
    }

    @Test("文中の空白は文字数に含める")
    func countsInnerWhitespace() {
        let result = TitleValidator.validate("read one page", language: .en)

        #expect(result.count == 13)
    }

    @Test("上限以内でも文字数と上限を返す")
    func returnsCountAndLimitWhenValid() {
        let result = TitleValidator.validate("本を1ページ読む", language: .ja)

        #expect(result == TitleValidation(count: 8, limit: 30, state: .ok))
    }
}
