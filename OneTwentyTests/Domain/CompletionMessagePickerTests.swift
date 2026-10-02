import Testing
@testable import OneTwenty

struct CompletionMessagePickerTests {
    private let messages = ["2分、終わりました。", "今日の分はここまで。", "記録しました。"]

    @Test("続けて選んでも、直前と同じ文言にはならない", arguments: [UInt64(1), 42, 2026])
    func neverRepeatsPrevious(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        var previous: String?

        for _ in 0..<500 {
            let picked = CompletionMessagePicker.pick(from: messages, excluding: previous, using: &rng)

            #expect(picked != nil)
            #expect(picked != previous)
            previous = picked
        }
    }

    @Test("くり返し選ぶと、一覧のどの文言も選ばれる")
    func everyMessageIsEventuallyPicked() {
        var rng = SeededGenerator(seed: 7)
        var previous: String?
        var seen: Set<String> = []

        for _ in 0..<200 {
            previous = CompletionMessagePicker.pick(from: messages, excluding: previous, using: &rng)
            if let previous { seen.insert(previous) }
        }

        #expect(seen == Set(messages))
    }

    @Test("同じ種の乱数からは、同じ文言が選ばれる")
    func deterministicWithSameSeed() {
        var first = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)

        #expect(CompletionMessagePicker.pick(from: messages, excluding: nil, using: &first)
            == CompletionMessagePicker.pick(from: messages, excluding: nil, using: &second))
    }

    @Test("一覧が 1 件なら、直前と同じでもその 1 件を返す")
    func singleMessage() {
        var rng = SeededGenerator(seed: 1)

        #expect(CompletionMessagePicker.pick(from: ["終わりました。"], excluding: nil, using: &rng) == "終わりました。")
        #expect(CompletionMessagePicker.pick(from: ["終わりました。"], excluding: "終わりました。", using: &rng) == "終わりました。")
    }

    @Test("一覧が空なら nil")
    func emptyMessages() {
        var rng = SeededGenerator(seed: 1)

        #expect(CompletionMessagePicker.pick(from: [], excluding: nil, using: &rng) == nil)
        #expect(CompletionMessagePicker.pick(from: [], excluding: "終わりました。", using: &rng) == nil)
    }

    @Test("直前の文言が一覧にない場合は、一覧のどれかを返す")
    func previousNotInList() {
        var rng = SeededGenerator(seed: 3)

        let picked = CompletionMessagePicker.pick(from: messages, excluding: "一覧にない文言", using: &rng)

        #expect(picked.map(messages.contains) == true)
    }

    @Test("2 件なら、必ず交互になる")
    func twoMessagesAlternate() {
        var rng = SeededGenerator(seed: 5)
        let two = ["A", "B"]

        #expect(CompletionMessagePicker.pick(from: two, excluding: "A", using: &rng) == "B")
        #expect(CompletionMessagePicker.pick(from: two, excluding: "B", using: &rng) == "A")
    }
}
