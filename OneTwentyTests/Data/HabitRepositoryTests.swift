import Foundation
import SwiftData
import Testing
@testable import OneTwenty

@MainActor
struct HabitRepositoryTests {
    private let container: ModelContainer
    private let repository: SwiftDataHabitRepository

    init() throws {
        container = try PersistentStore.makeContainer(inMemory: true)
        repository = SwiftDataHabitRepository(context: container.mainContext)
    }

    @Test("追加した習慣を同じ値で読み出せる")
    func insertAndRead() throws {
        let habit = HabitSnapshot.fixture(title: "靴を履く", originalIntent: "毎朝走る", order: 0)

        try repository.insert(habit)

        #expect(repository.habit(id: habit.id) == habit)
        #expect(repository.activeHabits() == [habit])
    }

    @Test("存在しない習慣は nil になる")
    func missingHabit() {
        #expect(repository.habit(id: UUID()) == nil)
        #expect(repository.activeHabits().isEmpty)
    }

    @Test("アクティブな習慣はアーカイブ済みを含まず、並び順で返る")
    func activeHabitsAreSortedAndExcludeArchived() throws {
        let second = HabitSnapshot.fixture(title: "2番目", order: 1)
        let first = HabitSnapshot.fixture(title: "1番目", order: 0)
        let archived = HabitSnapshot.fixture(title: "やめた習慣", order: -1, archivedAt: Date(timeIntervalSince1970: 100))
        try repository.insert(second)
        try repository.insert(archived)
        try repository.insert(first)

        #expect(repository.activeHabits().map(\.title) == ["1番目", "2番目"])
    }

    @Test("すべての習慣はアーカイブ済みを含み、登録順で返る")
    func allHabitsIncludeArchived() throws {
        let older = HabitSnapshot.fixture(title: "古い", createdAt: Date(timeIntervalSince1970: 10), order: -1, archivedAt: Date(timeIntervalSince1970: 50))
        let newer = HabitSnapshot.fixture(title: "新しい", createdAt: Date(timeIntervalSince1970: 20), order: 0)
        try repository.insert(newer)
        try repository.insert(older)

        #expect(repository.allHabits().map(\.title) == ["古い", "新しい"])
    }

    @Test("名前を変更しても、登録時の文とその他の値は変わらない")
    func updateTitleKeepsOtherValues() throws {
        let habit = HabitSnapshot.fixture(title: "本を1ページ読む", originalIntent: "読書を続ける", order: 2)
        try repository.insert(habit)

        try repository.updateTitle(id: habit.id, title: "本を開く")

        let updated = try #require(repository.habit(id: habit.id))
        #expect(updated.title == "本を開く")
        #expect(updated.id == habit.id)
        #expect(updated.originalIntent == "読書を続ける")
        #expect(updated.createdAt == habit.createdAt)
        #expect(updated.order == 2)
        #expect(updated.archivedAt == nil)
    }

    @Test("存在しない習慣の名前変更は失敗する")
    func updateTitleOfMissingHabit() {
        #expect(throws: RepositoryError.habitNotFound) {
            try repository.updateTitle(id: UUID(), title: "本を開く")
        }
    }

    @Test("並び順をまとめて書き換えられる")
    func updateOrders() throws {
        let a = HabitSnapshot.fixture(title: "A", order: 0)
        let b = HabitSnapshot.fixture(title: "B", order: 1)
        let c = HabitSnapshot.fixture(title: "C", order: 2)
        for habit in [a, b, c] { try repository.insert(habit) }

        try repository.updateOrders([a.id: 2, b.id: 0, c.id: 1])

        #expect(repository.activeHabits().map(\.title) == ["B", "C", "A"])
    }

    @Test("存在しない習慣を含む並び替えは失敗し、他の習慣の並び順も変わらない")
    func updateOrdersWithMissingHabitChangesNothing() throws {
        let a = HabitSnapshot.fixture(title: "A", order: 0)
        let b = HabitSnapshot.fixture(title: "B", order: 1)
        for habit in [a, b] { try repository.insert(habit) }

        #expect(throws: RepositoryError.habitNotFound) {
            try repository.updateOrders([a.id: 1, b.id: 0, UUID(): 2])
        }

        #expect(repository.activeHabits().map(\.title) == ["A", "B"])
    }

    @Test("アーカイブするとアクティブから外れるが、すべての習慣には残る")
    func archiveKeepsHabitInAllHabits() throws {
        let habit = HabitSnapshot.fixture(order: 0)
        try repository.insert(habit)
        let archivedAt = Date(timeIntervalSince1970: 1_000)

        try repository.archive(id: habit.id, at: archivedAt)

        #expect(repository.activeHabits().isEmpty)
        let archived = try #require(repository.allHabits().first)
        #expect(archived.id == habit.id)
        #expect(archived.archivedAt == archivedAt)
        #expect(archived.order == -1)
    }

    @Test("アーカイブすると、残りの習慣の並び順が 0 から詰め直される。既にアーカイブ済みの習慣には触れない")
    func archiveRenumbersRemainingHabits() throws {
        let old = HabitSnapshot.fixture(title: "やめた習慣", order: -1, archivedAt: Date(timeIntervalSince1970: 100))
        let a = HabitSnapshot.fixture(title: "A", order: 0)
        let b = HabitSnapshot.fixture(title: "B", order: 1)
        let c = HabitSnapshot.fixture(title: "C", order: 2)
        for habit in [old, a, b, c] {
            try repository.insert(habit)
        }

        try repository.archive(id: a.id, at: Date(timeIntervalSince1970: 1_000))

        #expect(repository.activeHabits().map(\.title) == ["B", "C"])
        #expect(repository.activeHabits().map(\.order) == [0, 1])
        #expect(repository.habit(id: old.id) == old)
    }

    @Test("アーカイブ済みの習慣をもう一度アーカイブしても、残りの並び順は変わらない")
    func archiveTwiceKeepsOrders() throws {
        let a = HabitSnapshot.fixture(title: "A", order: 0)
        let b = HabitSnapshot.fixture(title: "B", order: 1)
        try repository.insert(a)
        try repository.insert(b)
        try repository.archive(id: a.id, at: Date(timeIntervalSince1970: 1_000))
        try repository.updateOrders([b.id: 5])

        try repository.archive(id: a.id, at: Date(timeIntervalSince1970: 2_000))

        #expect(repository.activeHabits().map(\.order) == [5])
    }

    @Test("アーカイブ済みの習慣をもう一度アーカイブしても、アーカイブした時刻は変わらない")
    func archiveTwiceKeepsFirstDate() throws {
        let habit = HabitSnapshot.fixture(order: 0)
        try repository.insert(habit)
        let first = Date(timeIntervalSince1970: 1_000)

        try repository.archive(id: habit.id, at: first)
        try repository.archive(id: habit.id, at: Date(timeIntervalSince1970: 2_000))

        #expect(repository.habit(id: habit.id)?.archivedAt == first)
    }

    @Test("存在しない習慣のアーカイブは失敗する")
    func archiveMissingHabit() {
        #expect(throws: RepositoryError.habitNotFound) {
            try repository.archive(id: UUID(), at: Date())
        }
    }

    @Test("書き込みは保存まで行われ、別の読み取り口からも見える")
    func writesArePersisted() throws {
        let habit = HabitSnapshot.fixture(title: "変更前", order: 0)
        try repository.insert(habit)
        try repository.updateTitle(id: habit.id, title: "変更後")

        let another = SwiftDataHabitRepository(context: ModelContext(container))

        #expect(another.habit(id: habit.id)?.title == "変更後")
    }
}
