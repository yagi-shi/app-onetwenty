import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct HabitServiceTests {
    private let h: ServiceHarness
    private var service: HabitService { h.habitService }

    init() throws {
        h = try ServiceHarness()
    }

    private func register(_ title: String) async throws -> HabitSnapshot {
        try await service.register(title: title, originalIntent: "\(title)（元の入力）")
        return try #require(h.habitStore.activeHabits().last)
    }

    // MARK: 登録

    @Test("登録すると、登録時刻と末尾の並び順が入る")
    func registerSetsValues() async throws {
        let first = try await register("本を1ページ読む")
        let second = try await register("靴を履く")

        #expect(first.title == "本を1ページ読む")
        #expect(first.originalIntent == "本を1ページ読む（元の入力）")
        #expect(first.createdAt == h.clock.now)
        #expect(first.archivedAt == nil)
        #expect(first.order == 0)
        #expect(second.order == 1)
        #expect(h.habitStore.activeHabits().map(\.title) == ["本を1ページ読む", "靴を履く"])
    }

    @Test("3 件あるときは、4 件目を登録できない")
    func rejectsFourthHabit() async throws {
        for title in ["A", "B", "C"] { _ = try await register(title) }

        await #expect(throws: HabitError.limitReached) {
            try await service.register(title: "D", originalIntent: "D")
        }
        #expect(h.habitStore.allHabits().count == 3)
    }

    @Test("上限の判定は 3 件未満なら登録可")
    func slotPolicy() {
        #expect(HabitSlotPolicy.canRegister(activeCount: 0))
        #expect(HabitSlotPolicy.canRegister(activeCount: 2))
        #expect(!HabitSlotPolicy.canRegister(activeCount: 3))
        #expect(!HabitSlotPolicy.canRegister(activeCount: 4))
    }

    // MARK: アーカイブ

    @Test("アーカイブすると枠が空き、もう 1 件登録できる。並び順は欠番なく振り直される")
    func archiveFreesSlotAndRenumbers() async throws {
        let a = try await register("A")
        let b = try await register("B")
        let c = try await register("C")

        try await service.archive(habitID: b.id)

        #expect(h.habitStore.activeHabits().map(\.title) == ["A", "C"])
        #expect(h.habitStore.activeHabits().map(\.order) == [0, 1])
        let archived = try #require(h.habitStore.habit(id: b.id))
        #expect(archived.archivedAt == h.clock.now)
        #expect(archived.order == -1)

        let d = try await register("D")
        #expect(d.order == 2)
        #expect(h.habitStore.activeHabits().map(\.id) == [a.id, c.id, d.id])
        #expect(h.habitStore.allHabits().count == 4)
    }

    @Test("存在しない習慣はアーカイブできない")
    func archiveMissingHabit() async {
        await #expect(throws: RepositoryError.habitNotFound) {
            try await service.archive(habitID: UUID())
        }
    }

    // MARK: リマインダーとの連動

    @Test("0 件から 1 件登録するとリマインダーを予約し、すべてアーカイブすると全て取り消す")
    func remindersFollowHabitCount() async throws {
        #expect(h.reminderIdentifiers.isEmpty)

        let habit = try await register("本を1ページ読む")
        #expect(h.reminderIdentifiers.count == 60)

        try await service.archive(habitID: habit.id)
        #expect(h.reminderIdentifiers.isEmpty)

        _ = try await register("靴を履く")
        #expect(h.reminderIdentifiers.count == 60)
    }

    // MARK: 通知の許可

    @Test("初めての登録で、通知の許可を 1 回だけ求める。許可されたらその場でリマインダーを予約する")
    func requestsAuthorizationOnFirstRegister() async throws {
        h.notifications.authorization = .notDetermined

        _ = try await register("本を1ページ読む")
        #expect(h.notifications.requestAuthorizationCount == 1)
        #expect(h.reminderIdentifiers.count == 60)

        _ = try await register("靴を履く")
        #expect(h.notifications.requestAuthorizationCount == 1)
    }

    @Test("リマインダーがオフでも、通知の許可は求める")
    func requestsAuthorizationEvenIfRemindersAreOff() async throws {
        h.notifications.authorization = .notDetermined
        h.settings.reminderEnabled = false

        _ = try await register("本を1ページ読む")

        #expect(h.notifications.requestAuthorizationCount == 1)
        #expect(h.reminderIdentifiers.isEmpty)
    }

    @Test("許可・拒否が決まっていれば、通知の許可は求めない", arguments: [NotificationAuthorization.authorized, .denied])
    func doesNotRequestWhenDetermined(authorization: NotificationAuthorization) async throws {
        h.notifications.authorization = authorization

        _ = try await register("本を1ページ読む")

        #expect(h.notifications.requestAuthorizationCount == 0)
    }

    // MARK: 名前変更

    @Test("名前を変更しても同じ習慣のままで、履歴と連続日数が引き継がれる")
    func renameKeepsHistory() async throws {
        let habit = try h.addHabit("本を1ページ読む")
        let calendar = h.calendar
        for offset in [-3, -2, -1] {
            let day = h.today.adding(days: offset, calendar: calendar)
            _ = try h.sessions.insertIfAbsent(
                .fixture(habitID: habit.id, startedAt: day.startOfDay(calendar: calendar).addingTimeInterval(3_600)),
                sameDayRange: day.startOfDay(calendar: calendar)..<day.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
            )
        }
        func streak() -> Int {
            let days = Set(h.sessions.allSessions().filter { $0.habitID == habit.id }.map { DayKey($0.startedAt, calendar: calendar) })
            return StreakCalculator.habitStreak(
                sessionDays: days,
                createdDay: DayKey(habit.createdAt, calendar: calendar),
                today: h.today,
                calendar: calendar
            )
        }
        #expect(streak() == 3)

        try await service.rename(habitID: habit.id, title: "本を開く")

        let renamed = try #require(h.habitStore.habit(id: habit.id))
        #expect(renamed.title == "本を開く")
        #expect(renamed.originalIntent == habit.originalIntent)
        #expect(renamed.createdAt == habit.createdAt)
        #expect(renamed.order == habit.order)
        #expect(h.habitStore.allHabits().count == 1)
        #expect(h.sessions.allSessions().count == 3)
        #expect(streak() == 3)
    }

    @Test("存在しない習慣の名前は変更できない")
    func renameMissingHabit() async {
        await #expect(throws: RepositoryError.habitNotFound) {
            try await service.rename(habitID: UUID(), title: "本を開く")
        }
    }

    // MARK: 並び替え

    @Test("並び替えると、指定した順に並び順が振り直される")
    func reorder() async throws {
        let a = try await register("A")
        let b = try await register("B")
        let c = try await register("C")

        try service.reorder([c.id, a.id, b.id])

        #expect(h.habitStore.activeHabits().map(\.title) == ["C", "A", "B"])
        #expect(h.habitStore.activeHabits().map(\.order) == [0, 1, 2])
    }

    @Test("アクティブな習慣の一覧と一致しない並び替えは受け付けず、並び順は変わらない")
    func rejectsInvalidReorder() async throws {
        let a = try await register("A")
        let b = try await register("B")

        #expect(throws: HabitError.invalidOrder) { try service.reorder([a.id]) }
        #expect(throws: HabitError.invalidOrder) { try service.reorder([a.id, UUID()]) }
        #expect(throws: HabitError.invalidOrder) { try service.reorder([a.id, a.id]) }
        #expect(throws: HabitError.invalidOrder) { try service.reorder([a.id, b.id, UUID()]) }

        #expect(h.habitStore.activeHabits().map(\.title) == ["A", "B"])
    }

    // MARK: 保存の失敗

    @Test("登録の保存に失敗したら、通知の許可も求めず、リマインダーも同期しない")
    func registerFailureHasNoSideEffects() async {
        h.notifications.authorization = .notDetermined
        h.habits.failsWrites = true

        await #expect(throws: FailingHabitRepository.Failure.self) {
            try await service.register(title: "本を1ページ読む", originalIntent: "読書")
        }

        #expect(h.habitStore.allHabits().isEmpty)
        #expect(h.notifications.requestAuthorizationCount == 0)
        #expect(h.notifications.addedIdentifiers.isEmpty)
    }

    @Test("アーカイブの保存に失敗したら、習慣もリマインダーも変わらない")
    func archiveFailureChangesNothing() async throws {
        let habit = try await register("本を1ページ読む")
        h.notifications.resetCallHistory()
        h.habits.failsWrites = true

        await #expect(throws: FailingHabitRepository.Failure.self) {
            try await service.archive(habitID: habit.id)
        }

        #expect(h.habitStore.activeHabits().map(\.id) == [habit.id])
        #expect(h.notifications.removedIdentifiers.isEmpty)
        #expect(h.reminderIdentifiers.count == 60)
    }

    @Test("名前変更・並び替えの保存に失敗したら、元の値のまま")
    func renameAndReorderFailure() async throws {
        let a = try await register("A")
        let b = try await register("B")
        h.habits.failsWrites = true

        await #expect(throws: FailingHabitRepository.Failure.self) {
            try await service.rename(habitID: a.id, title: "変更後")
        }
        #expect(throws: FailingHabitRepository.Failure.self) { try service.reorder([b.id, a.id]) }

        #expect(h.habitStore.activeHabits().map(\.title) == ["A", "B"])
    }
}
