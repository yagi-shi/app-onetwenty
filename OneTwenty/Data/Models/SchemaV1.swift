import Foundation
import SwiftData

/// 出荷時点のデータの形。形を変えるときは `SchemaV2` を追加し、ここは書き換えない。
nonisolated enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Habit.self, Session.self]
    }

    @Model
    final class Habit {
        @Attribute(.unique) var id: UUID
        var title: String
        var originalIntent: String
        var createdAt: Date
        var order: Int
        var archivedAt: Date?
        @Relationship(deleteRule: .cascade, inverse: \Session.habit)
        var sessions: [Session] = []

        init(id: UUID, title: String, originalIntent: String, createdAt: Date, order: Int, archivedAt: Date?) {
            self.id = id
            self.title = title
            self.originalIntent = originalIntent
            self.createdAt = createdAt
            self.order = order
            self.archivedAt = archivedAt
        }
    }

    @Model
    final class Session {
        #Index<Session>([\.startedAt])

        @Attribute(.unique) var id: UUID
        var startedAt: Date
        var completedAt: Date
        var habit: Habit?

        init(id: UUID, startedAt: Date, completedAt: Date, habit: Habit?) {
            self.id = id
            self.startedAt = startedAt
            self.completedAt = completedAt
            self.habit = habit
        }
    }
}

nonisolated enum OneTwentyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias Habit = SchemaV1.Habit
typealias Session = SchemaV1.Session
