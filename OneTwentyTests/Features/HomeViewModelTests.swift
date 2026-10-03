import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct HomeViewModelTests {
    private let h: ServiceHarness
    private let viewModel: HomeViewModel

    init() throws {
        h = try ServiceHarness()
        viewModel = h.makeHomeViewModel()
    }

    private func day(_ offset: Int) -> DayKey {
        h.today.adding(days: offset, calendar: h.calendar)
    }

    private func label(_ title: String, streak: Int, completed: Bool) -> String {
        HomeText.accessibilityLabel(title: title, streak: streak, isCompleted: completed)
    }

    // MARK: 件数に応じた表示

    @Test("習慣が 0 件なら、「＋」が 3 つと「習慣を追加」の案内。全完了にはならない")
    func emptyState() {
        viewModel.reload(displayDay: h.today)

        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.placeholderCount == 3)
        #expect(viewModel.showsAddLabel)
        #expect(!viewModel.allCompleted)
    }

    @Test("「＋」の数は、3 から習慣の数を引いた数", arguments: [(1, 2), (2, 1), (3, 0)])
    func placeholderCount(habitCount: Int, expected: Int) throws {
        for index in 0..<habitCount { try h.addHabit("習慣\(index)") }

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.rows.count == habitCount)
        #expect(viewModel.placeholderCount == expected)
        #expect(!viewModel.showsAddLabel)
    }

    @Test("習慣は並び順どおりに表示する。アーカイブ済みは表示しない")
    func rowsFollowOrder() throws {
        try h.addHabit("2番目", order: 1)
        try h.addHabit("1番目", order: 0)
        let archived = try h.addHabit("やめた習慣", order: 2)
        try h.habitStore.archive(id: archived.id, at: h.clock.now)

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.rows.map(\.title) == ["1番目", "2番目"])
        #expect(viewModel.placeholderCount == 1)
    }

    // MARK: 連続日数

    @Test("連続 0 日なら、連続日数を表示せず、読み上げにも含めない")
    func noStreak() throws {
        try h.addHabit("本を1ページ読む")

        viewModel.reload(displayDay: h.today)

        let row = try #require(viewModel.rows.first)
        #expect(row.streakText == nil)
        #expect(row.accessibilityLabel == label("本を1ページ読む", streak: 0, completed: false))
        #expect(!row.accessibilityLabel.contains("0"))
        #expect(row.accessibilityLabel.components(separatedBy: String(localized: "common.listSeparator")).count == 2)
    }

    @Test("連続 3 日なら、連続日数を表示し、読み上げにも含める")
    func threeDayStreak() throws {
        let habit = try h.addHabit("本を1ページ読む")
        for offset in [-3, -2, -1] { try h.addSession(for: habit, on: day(offset)) }

        viewModel.reload(displayDay: h.today)

        let row = try #require(viewModel.rows.first)
        #expect(row.streakText == HomeText.streak(3))
        #expect(row.streakText?.contains("3") == true)
        #expect(row.accessibilityLabel == label("本を1ページ読む", streak: 3, completed: false))
        #expect(row.accessibilityLabel.contains("3"))
        #expect(row.accessibilityLabel.components(separatedBy: String(localized: "common.listSeparator")).count == 3)
    }

    @Test("今日が未完了でも、前日までの連続日数を保って表示する")
    func keepsStreakBeforeTodayIsDone() throws {
        let habit = try h.addHabit()
        for offset in [-2, -1] { try h.addSession(for: habit, on: day(offset)) }

        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.first?.streakText == HomeText.streak(2))

        try h.addSession(for: habit, on: h.today)
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.first?.streakText == HomeText.streak(3))
    }

    // MARK: 完了状態

    @Test("完了済みの習慣は押せず、読み上げは「完了」で終わる。未完了は押せて「未完了」で終わる")
    func completedRowIsNotButton() throws {
        let done = try h.addHabit("本を1ページ読む")
        try h.addHabit("靴を履く")
        try h.addSession(for: done, on: h.today)

        viewModel.reload(displayDay: h.today)

        let completed = try #require(viewModel.rows.first)
        let notCompleted = try #require(viewModel.rows.last)
        #expect(completed.isCompleted)
        #expect(!completed.isButton)
        #expect(completed.accessibilityLabel == label("本を1ページ読む", streak: 1, completed: true))
        #expect(completed.accessibilityLabel.hasSuffix(HomeText.completed))
        #expect(!notCompleted.isCompleted)
        #expect(notCompleted.isButton)
        #expect(notCompleted.accessibilityLabel.hasSuffix(HomeText.notCompleted))
        #expect(HomeText.completed != HomeText.notCompleted)
        #expect(!viewModel.allCompleted)
    }

    @Test("すべての習慣が完了していれば、全完了になる")
    func allCompleted() throws {
        let first = try h.addHabit("本を1ページ読む")
        let second = try h.addHabit("靴を履く")
        try h.addSession(for: first, on: h.today)
        try h.addSession(for: second, on: h.today)

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.allCompleted)
        #expect(viewModel.rows.allSatisfy { $0.isCompleted })
    }

    @Test("完了記録の保存に失敗して保存待ちになっていても、完了として表示する")
    func pendingCompletionIsShownAsCompleted() throws {
        let habit = try h.addHabit()
        h.runningStore.addPending(RunningSessionMarker(
            sessionID: UUID(),
            habitID: habit.id,
            startedAt: h.clock.now.addingTimeInterval(-300)
        ))

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.rows.first?.isCompleted == true)
        #expect(viewModel.rows.first?.isButton == false)
        #expect(viewModel.allCompleted)
    }

    @Test("完了状態は、渡された表示する日で決まる")
    func usesDisplayDay() throws {
        let habit = try h.addHabit()
        try h.addSession(for: habit, on: day(-1))

        viewModel.reload(displayDay: day(-1))
        #expect(viewModel.rows.first?.isCompleted == true)

        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.first?.isCompleted == false)
    }

    @Test("データが変わった後に読み込み直すと、表示に反映される")
    func reloadReflectsChanges() throws {
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.isEmpty)

        let habit = try h.addHabit("本を1ページ読む")
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.map(\.title) == ["本を1ページ読む"])

        try h.habitStore.updateTitle(id: habit.id, title: "本を開く")
        viewModel.reload(displayDay: h.today)
        #expect(viewModel.rows.map(\.title) == ["本を開く"])
    }

    // MARK: タップ

    @Test("未完了の習慣をタップすると、確認なしでタイマーが始まり、タイマー画面の表示を依頼する")
    func tapStartsTimer() async throws {
        let habit = try h.addHabit()
        viewModel.reload(displayDay: h.today)
        var started: [RunningSessionMarker] = []
        viewModel.onStartTimer = { started.append($0) }

        await viewModel.tap(habitID: habit.id)

        #expect(started.count == 1)
        #expect(started.first?.habitID == habit.id)
        #expect(h.runningStore.load() == started.first)
    }

    @Test("Live Activity も完了通知も用意できなくても、タイマー画面の表示を依頼する")
    func tapStartsTimerEvenWhenSystemIntegrationsFail() async throws {
        let habit = try h.addHabit()
        viewModel.reload(displayDay: h.today)
        h.liveActivity.startFails = true
        h.notifications.failingPrefixes = ["timer."]
        var started: [RunningSessionMarker] = []
        viewModel.onStartTimer = { started.append($0) }

        await viewModel.tap(habitID: habit.id)

        #expect(started.count == 1)
        #expect(h.runningStore.load() == started.first)
        #expect(h.liveActivity.activities.isEmpty)
        #expect(h.timerIdentifiers.isEmpty)
    }

    @Test("完了済みの習慣をタップしても、何も起きない")
    func tapOnCompletedDoesNothing() async throws {
        let habit = try h.addHabit()
        try h.addSession(for: habit, on: h.today)
        viewModel.reload(displayDay: h.today)
        var startedCount = 0
        viewModel.onStartTimer = { _ in startedCount += 1 }

        await viewModel.tap(habitID: habit.id)

        #expect(startedCount == 0)
        #expect(h.runningStore.load() == nil)
        #expect(h.feedback.prepareCount == 0)
    }

    @Test("表示が古くて開始を断られたときは、タイマー画面を開かず、表示を取り直す")
    func rejectedTapReloads() async throws {
        let habit = try h.addHabit()
        viewModel.reload(displayDay: h.today)
        // 表示した後に、別の経路で完了した
        try h.addSession(for: habit, on: h.today)
        var startedCount = 0
        viewModel.onStartTimer = { _ in startedCount += 1 }

        await viewModel.tap(habitID: habit.id)

        #expect(startedCount == 0)
        #expect(viewModel.rows.first?.isCompleted == true)
    }

    @Test("「＋」をタップすると、ウィザードの表示を依頼する")
    func tapPlaceholderRequestsWizard() {
        var requestCount = 0
        viewModel.onAddHabit = { requestCount += 1 }

        viewModel.tapPlaceholder()

        #expect(requestCount == 1)
    }

    // MARK: 日をまたいだ完了

    @Test("日をまたいで完了した後は当日基準で表示し、前日に完了した習慣も含めて、当日の分として開始できる")
    func afterMidnightCompletion() async throws {
        let crossed = try h.addHabit("本を1ページ読む")
        let other = try h.addHabit("靴を履く")
        try h.addSession(for: other, on: h.today)
        // 23:59 に始めて、日をまたいで完了
        h.clock.now = TestCalendars.date(2026, 10, 1, 23, 59, in: h.calendar)
        guard case .started = await h.sessionService.start(habitID: crossed.id) else {
            Issue.record("開始できるはず")
            return
        }
        h.clock.advance(by: 120)
        _ = await h.sessionService.completeInForeground()

        viewModel.reload(displayDay: h.today)

        #expect(viewModel.rows.map(\.isCompleted) == [false, false])
        #expect(viewModel.rows.allSatisfy { $0.isButton })
        // 前日の完了は、連続日数として残っている
        #expect(viewModel.rows.map(\.streakText) == [HomeText.streak(1), HomeText.streak(1)])

        var startedCount = 0
        viewModel.onStartTimer = { _ in startedCount += 1 }
        await viewModel.tap(habitID: crossed.id)
        #expect(startedCount == 1)
        await h.sessionService.abort()
        await viewModel.tap(habitID: other.id)
        #expect(startedCount == 2)
    }
}
