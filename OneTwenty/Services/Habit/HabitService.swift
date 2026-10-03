import Foundation

enum HabitError: Error, Equatable {
    /// 習慣は 3 件までしか登録できない。
    case limitReached
    /// 並び替えの指定が、アクティブな習慣の一覧と一致しない。
    case invalidOrder
}

/// 習慣の登録・名前変更・並び替え・アーカイブ。
/// リマインダーの同期は、保存に成功したときだけ行う。
final class HabitService {
    private let habits: HabitRepository
    private let notifications: NotificationClient
    private let reminders: ReminderService
    private let clock: WallClock

    init(habits: HabitRepository, notifications: NotificationClient, reminders: ReminderService, clock: WallClock) {
        self.habits = habits
        self.notifications = notifications
        self.reminders = reminders
        self.clock = clock
    }

    func register(title: String, originalIntent: String) async throws {
        let activeCount = habits.activeHabits().count
        guard HabitSlotPolicy.canRegister(activeCount: activeCount) else {
            throw HabitError.limitReached
        }
        try habits.insert(HabitSnapshot(
            id: UUID(),
            title: title,
            originalIntent: originalIntent,
            createdAt: clock.now,
            order: activeCount,
            archivedAt: nil
        ))

        await reminders.sync()
    }

    /// 通知の許可がまだ決まっていないか。
    /// 決まっていなければ、登録した側が使い道を説明してから `requestNotificationAuthorization()` を呼ぶ
    /// （iOS の許可ダイアログには、使い道を書く場所がないため）。
    func needsNotificationAuthorization() async -> Bool {
        await notifications.authorizationStatus() == .notDetermined
    }

    /// 通知の許可を求める。タイマーの完了通知にも許可が要るので、リマインダーがオフでも求める。
    func requestNotificationAuthorization() async {
        guard await needsNotificationAuthorization() else { return }
        _ = await notifications.requestAuthorization()
        await reminders.sync()
    }

    /// 習慣名だけを書き換える。同じ習慣のままなので、履歴と連続日数は引き継がれる。
    func rename(habitID: UUID, title: String) async throws {
        try habits.updateTitle(id: habitID, title: title)
    }

    /// - Parameter orderedIDs: アクティブな習慣すべての id を、新しい並び順で並べたもの。
    func reorder(_ orderedIDs: [UUID]) throws {
        let activeIDs = habits.activeHabits().map(\.id)
        guard orderedIDs.count == activeIDs.count, Set(orderedIDs) == Set(activeIDs) else {
            throw HabitError.invalidOrder
        }
        try habits.updateOrders(Dictionary(uniqueKeysWithValues: zip(orderedIDs, orderedIDs.indices)))
    }

    /// アーカイブは取り消せない。空いた枠は、同じ保存の中で詰められる。
    func archive(habitID: UUID) async throws {
        try habits.archive(id: habitID, at: clock.now)
        await reminders.sync()
    }
}
