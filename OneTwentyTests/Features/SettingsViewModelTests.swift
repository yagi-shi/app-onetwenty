import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct SettingsViewModelTests {
    private let h: ServiceHarness

    /// 呼ばれた通知を記録する。
    private final class Calls {
        var themeChanged = 0
        var habitsChanged = 0
        var renamed: [HabitSnapshot] = []
    }

    init() throws {
        h = try ServiceHarness()
    }

    private func makeViewModel() -> (SettingsViewModel, Calls) {
        let viewModel = SettingsViewModel(
            habits: h.habits,
            habitService: h.habitService,
            reminders: h.reminders,
            settings: h.settings
        )
        let calls = Calls()
        viewModel.onThemeChanged = { calls.themeChanged += 1 }
        viewModel.onHabitsChanged = { calls.habitsChanged += 1 }
        viewModel.onRename = { calls.renamed.append($0) }
        viewModel.reload()
        return (viewModel, calls)
    }

    // MARK: ユーザー設定

    @Test("保存されている設定を表示する")
    func showsStoredSettings() {
        h.settings.reminderTime = ReminderTime(hour: 21, minute: 30)
        h.settings.reminderEnabled = false
        h.settings.theme = .dark

        let (viewModel, _) = makeViewModel()

        #expect(viewModel.reminderTime == ReminderTime(hour: 21, minute: 30))
        #expect(!viewModel.reminderEnabled)
        #expect(viewModel.theme == .dark)
    }

    @Test("通知時刻を変えると保存し、リマインダーの予約をその時刻に入れ替える")
    func changesReminderTime() async throws {
        try h.addHabit()
        let (viewModel, _) = makeViewModel()
        await viewModel.refreshAuthorization()

        // 現在は 7:59。今日の分も含めて確かめるため、現在より後の時刻にする
        await viewModel.setReminderTime(ReminderTime(hour: 9, minute: 15))

        #expect(h.settings.reminderTime == ReminderTime(hour: 9, minute: 15))
        #expect(h.reminderIdentifiers.count == 60)
        #expect(h.reminderIdentifiers.allSatisfy { $0.hasSuffix(".0915") })
    }

    @Test("リマインダーをオフにすると保存し、予約を取り消す")
    func turnsRemindersOff() async throws {
        try h.addHabit()
        await h.reminders.sync()
        let (viewModel, _) = makeViewModel()

        await viewModel.setReminderEnabled(false)

        #expect(!h.settings.reminderEnabled)
        #expect(h.reminderIdentifiers.isEmpty)
    }

    @Test("通知が拒否されていると、通知時刻とオン/オフは操作できない")
    func deniedDisablesReminderControls() async {
        h.notifications.authorization = .denied
        let (viewModel, _) = makeViewModel()
        await viewModel.refreshAuthorization()

        #expect(!viewModel.areReminderControlsEnabled)
        await viewModel.setReminderTime(ReminderTime(hour: 6, minute: 0))
        await viewModel.setReminderEnabled(false)

        #expect(h.settings.reminderTime == .default)
        #expect(h.settings.reminderEnabled)
    }

    @Test("許可状態を取り直すと、拒否から許可に変わっていれば操作できるようになる")
    func refreshesAuthorization() async {
        h.notifications.authorization = .denied
        let (viewModel, _) = makeViewModel()
        await viewModel.refreshAuthorization()
        #expect(!viewModel.areReminderControlsEnabled)

        h.notifications.authorization = .authorized
        await viewModel.refreshAuthorization()

        #expect(viewModel.authorization == .authorized)
        #expect(viewModel.areReminderControlsEnabled)
    }

    @Test("未決定の間は、通知時刻とオン/オフを操作できる")
    func notDeterminedAllowsControls() async {
        h.notifications.authorization = .notDetermined
        let (viewModel, _) = makeViewModel()
        await viewModel.refreshAuthorization()

        #expect(viewModel.areReminderControlsEnabled)
    }

    @Test("テーマを変えると保存し、変わったことを知らせる")
    func changesTheme() {
        let (viewModel, calls) = makeViewModel()

        viewModel.setTheme(.dark)

        #expect(h.settings.theme == .dark)
        #expect(viewModel.theme == .dark)
        #expect(calls.themeChanged == 1)
    }

    // MARK: 習慣の管理

    @Test("アクティブな習慣を並び順で表示し、アーカイブ済みは表示しない")
    func listsActiveHabits() throws {
        try h.addHabit("A")
        let archived = try h.addHabit("B")
        try h.addHabit("C")
        try h.habitStore.archive(id: archived.id, at: h.clock.now)

        let (viewModel, _) = makeViewModel()

        #expect(viewModel.habits.map(\.title) == ["A", "C"])
    }

    @Test("並び替えると保存し、習慣が変わったことを知らせる")
    func reorders() throws {
        let a = try h.addHabit("A")
        let b = try h.addHabit("B")
        let (viewModel, calls) = makeViewModel()

        viewModel.reorder(to: [b.id, a.id])

        #expect(viewModel.habits.map(\.title) == ["B", "A"])
        #expect(h.habitStore.activeHabits().map(\.title) == ["B", "A"])
        #expect(calls.habitsChanged == 1)
    }

    @Test("並び替えを保存できなければ、画面の並びを元に戻してアラートを出す")
    func reorderFailure() throws {
        let a = try h.addHabit("A")
        let b = try h.addHabit("B")
        let (viewModel, calls) = makeViewModel()
        h.habits.failsWrites = true

        viewModel.reorder(to: [b.id, a.id])

        #expect(viewModel.habits.map(\.title) == ["A", "B"])
        #expect(viewModel.showsSaveFailure)
        #expect(calls.habitsChanged == 0)
    }

    @Test("アーカイブの確認で「やめる」を選ぶと、アーカイブしない")
    func cancelArchive() async throws {
        let habit = try h.addHabit()
        let (viewModel, calls) = makeViewModel()

        viewModel.requestArchive(habit)
        #expect(viewModel.archiveCandidate == habit)
        viewModel.cancelArchive()
        await viewModel.confirmArchive()

        #expect(viewModel.archiveCandidate == nil)
        #expect(h.habitStore.activeHabits().map(\.id) == [habit.id])
        #expect(calls.habitsChanged == 0)
    }

    @Test("アーカイブの確認で「アーカイブする」を選ぶと、一覧から消え、習慣が変わったことを知らせる")
    func confirmArchive() async throws {
        let habit = try h.addHabit("A")
        try h.addHabit("B")
        let (viewModel, calls) = makeViewModel()

        viewModel.requestArchive(habit)
        await viewModel.confirmArchive()

        #expect(viewModel.habits.map(\.title) == ["B"])
        #expect(h.habitStore.habit(id: habit.id)?.archivedAt != nil)
        #expect(calls.habitsChanged == 1)
    }

    @Test("アーカイブを保存できなければ、一覧を変えずにアラートを出す")
    func archiveFailure() async throws {
        let habit = try h.addHabit()
        let (viewModel, calls) = makeViewModel()
        h.habits.failsWrites = true

        viewModel.requestArchive(habit)
        await viewModel.confirmArchive()

        #expect(viewModel.habits.map(\.id) == [habit.id])
        #expect(viewModel.showsSaveFailure)
        #expect(calls.habitsChanged == 0)

        viewModel.dismissSaveFailure()
        #expect(!viewModel.showsSaveFailure)
    }

    @Test("名前を変更すると、その習慣で編集のウィザードを開くよう依頼する")
    func rename() throws {
        let habit = try h.addHabit()
        let (viewModel, calls) = makeViewModel()

        viewModel.rename(habit)

        #expect(calls.renamed == [habit])
    }

    @Test("名前の変更後に読み込み直すと、新しい名前が表示される")
    func reloadShowsNewTitle() throws {
        let habit = try h.addHabit("本を1ページ読む")
        let (viewModel, _) = makeViewModel()

        try h.habitStore.updateTitle(id: habit.id, title: "本を開く")
        viewModel.reload()

        #expect(viewModel.habits.map(\.title) == ["本を開く"])
    }
}
