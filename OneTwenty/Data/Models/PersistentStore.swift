import Foundation
import SwiftData

enum PersistentStore {
    /// - Parameter inMemory: テスト用。`true` ならディスクに書かない。
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: OneTwentyMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
