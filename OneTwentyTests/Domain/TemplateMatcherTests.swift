import Testing
@testable import OneTwenty

struct TemplateMatcherTests {
    private let reading = TemplateCategory(id: "reading", keywords: ["読書", "本", "read"], templates: ["本を開く"])
    private let exercise = TemplateCategory(id: "exercise", keywords: ["運動", "走", "run"], templates: ["靴を履く"])

    @Test("キーワードを含む入力は、そのカテゴリに一致する")
    func matchesByKeyword() {
        let categories = [reading, exercise]

        #expect(TemplateMatcher.match("読書を続けたい", categories: categories) == reading)
        #expect(TemplateMatcher.match("毎朝走る", categories: categories) == exercise)
    }

    @Test("どのキーワードも含まない入力は、どのカテゴリにも一致しない")
    func noMatch() {
        #expect(TemplateMatcher.match("部屋を片付ける", categories: [reading, exercise]) == nil)
        #expect(TemplateMatcher.match("読書", categories: []) == nil)
    }

    @Test("複数のカテゴリに一致するときは、データの並びで先のカテゴリを選ぶ")
    func prefersEarlierCategory() {
        let text = "本を読んでから走る"

        #expect(TemplateMatcher.match(text, categories: [reading, exercise]) == reading)
        #expect(TemplateMatcher.match(text, categories: [exercise, reading]) == exercise)
    }

    @Test("英語は大文字と小文字を区別しない")
    func caseInsensitive() {
        #expect(TemplateMatcher.match("I want to READ more", categories: [reading, exercise]) == reading)
        #expect(TemplateMatcher.match("Run every morning", categories: [reading, exercise]) == exercise)
    }
}
