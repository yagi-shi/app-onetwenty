import Foundation
import Observation

@Observable
final class SettingsViewModel {
    private(set) var reminderTime: ReminderTime
    private(set) var reminderEnabled: Bool
    private(set) var theme: AppTheme
    private(set) var authorization: NotificationAuthorization
    private(set) var habits: [HabitSnapshot] = []
    /// アーカイブの確認を出している習慣。
    private(set) var archiveCandidate: HabitSnapshot?
    private(set) var showsSaveFailure = false

    @ObservationIgnored var onThemeChanged: (() -> Void)?
    @ObservationIgnored var onHabitsChanged: (() -> Void)?
    @ObservationIgnored var onRename: ((HabitSnapshot) -> Void)?

    @ObservationIgnored private let habitRepository: HabitRepository
    @ObservationIgnored private let habitService: HabitService
    @ObservationIgnored private let reminders: ReminderService
    @ObservationIgnored private let settings: SettingsStore

    init(habits: HabitRepository, habitService: HabitService, reminders: ReminderService, settings: SettingsStore) {
        habitRepository = habits
        self.habitService = habitService
        self.reminders = reminders
        self.settings = settings
        reminderTime = settings.reminderTime
        reminderEnabled = settings.reminderEnabled
        theme = settings.theme
        authorization = reminders.authorization
    }

    /// 通知が拒否されていると、時刻とオン/オフは操作できない。iOS の設定で許可してもらうしかないため。
    var areReminderControlsEnabled: Bool {
        authorization != .denied
    }

    /// 画面を表示したとき、データが変わったときに呼ぶ。
    func reload() {
        reminderTime = settings.reminderTime
        reminderEnabled = settings.reminderEnabled
        theme = settings.theme
        habits = habitRepository.activeHabits()
    }

    /// 画面を表示したとき、アプリに戻ってきたときに、通知の許可状態を取り直す。
    func refreshAuthorization() async {
        authorization = await reminders.refreshAuthorization()
    }

    func setReminderTime(_ time: ReminderTime) async {
        guard areReminderControlsEnabled else { return }
        reminderTime = time
        await reminders.setReminderTime(time)
    }

    func setReminderEnabled(_ enabled: Bool) async {
        guard areReminderControlsEnabled else { return }
        reminderEnabled = enabled
        await reminders.setReminderEnabled(enabled)
    }

    func setTheme(_ theme: AppTheme) {
        self.theme = theme
        settings.theme = theme
        onThemeChanged?()
    }

    /// - Parameter orderedIDs: 並べ替えた後の、習慣の id の並び。
    func reorder(to orderedIDs: [UUID]) {
        do {
            try habitService.reorder(orderedIDs)
            habits = habitRepository.activeHabits()
            onHabitsChanged?()
        } catch {
            // 保存できなければ、画面の並びを元に戻す
            habits = habitRepository.activeHabits()
            showsSaveFailure = true
        }
    }

    func rename(_ habit: HabitSnapshot) {
        onRename?(habit)
    }

    func requestArchive(_ habit: HabitSnapshot) {
        archiveCandidate = habit
    }

    func cancelArchive() {
        archiveCandidate = nil
    }

    /// アーカイブは取り消せない。確認で「アーカイブする」を選んだときだけ実行する。
    func confirmArchive() async {
        guard let habit = archiveCandidate else { return }
        archiveCandidate = nil
        do {
            try await habitService.archive(habitID: habit.id)
            habits = habitRepository.activeHabits()
            onHabitsChanged?()
        } catch {
            showsSaveFailure = true
        }
    }

    func dismissSaveFailure() {
        showsSaveFailure = false
    }
}
