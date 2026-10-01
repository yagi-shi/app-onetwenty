import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct RunningSessionStoreTests {
    private let isolated = IsolatedDefaults()
    private var store: UserDefaultsRunningSessionStore { UserDefaultsRunningSessionStore(defaults: isolated.defaults) }

    private func marker(startedAt: TimeInterval = 1_000) -> RunningSessionMarker {
        RunningSessionMarker(sessionID: UUID(), habitID: UUID(), startedAt: Date(timeIntervalSince1970: startedAt))
    }

    // MARK: 実行中

    @Test("何も保存していなければ、実行中の印はない")
    func noMarkerByDefault() {
        #expect(store.load() == nil)
        #expect(store.pendingCompletions().isEmpty)
    }

    @Test("保存した印は、ストアを作り直しても同じ値で読み出せる")
    func saveAndLoad() {
        let marker = marker(startedAt: 1_234.567)

        store.save(marker)

        #expect(UserDefaultsRunningSessionStore(defaults: isolated.defaults).load() == marker)
    }

    @Test("保存し直すと、新しい印に置き換わる")
    func saveReplacesMarker() {
        let newer = marker(startedAt: 2_000)
        store.save(marker(startedAt: 1_000))

        store.save(newer)

        #expect(store.load() == newer)
    }

    @Test("削除すると、実行中の印はなくなる")
    func clear() {
        store.save(marker())

        store.clear()

        #expect(store.load() == nil)
    }

    @Test("壊れた保存値は印なしとして扱い、保存値を消す", arguments: [
        Data("{ not json".utf8),
        Data("{}".utf8),
        Data(#"{"sessionID":"x","habitID":"y","startedAt":"z"}"#.utf8),
        Data(),
    ])
    func brokenMarkerIsTreatedAsMissing(data: Data) {
        isolated.defaults.set(data, forKey: "onetwenty.running.session")

        #expect(store.load() == nil)
        #expect(isolated.defaults.object(forKey: "onetwenty.running.session") == nil)
    }

    @Test("データ以外の型が保存されていても、印なしとして扱い、保存値を消す")
    func nonDataValueIsTreatedAsMissing() {
        isolated.defaults.set("文字列", forKey: "onetwenty.running.session")

        #expect(store.load() == nil)
        #expect(isolated.defaults.object(forKey: "onetwenty.running.session") == nil)
    }

    // MARK: 保存待ち

    @Test("保存待ちは追加した順に、複数持てる")
    func addPending() {
        let first = marker(startedAt: 1_000)
        let second = marker(startedAt: 2_000)

        store.addPending(first)
        store.addPending(second)

        #expect(UserDefaultsRunningSessionStore(defaults: isolated.defaults).pendingCompletions() == [first, second])
    }

    @Test("同じ実行を 2 回追加しても、保存待ちは 1 件のまま")
    func addPendingIsIdempotent() {
        let marker = marker()

        store.addPending(marker)
        store.addPending(marker)

        #expect(store.pendingCompletions() == [marker])
    }

    @Test("指定した実行だけを保存待ちから外せる")
    func removePending() {
        let first = marker(startedAt: 1_000)
        let second = marker(startedAt: 2_000)
        store.addPending(first)
        store.addPending(second)

        store.removePending(sessionID: first.sessionID)

        #expect(store.pendingCompletions() == [second])
    }

    @Test("保存待ちにない実行を外そうとしても、何も変わらない")
    func removeMissingPending() {
        let marker = marker()
        store.addPending(marker)

        store.removePending(sessionID: UUID())

        #expect(store.pendingCompletions() == [marker])
    }

    @Test("壊れた保存待ちは空として扱い、保存値を消す")
    func brokenPendingIsTreatedAsEmpty() {
        isolated.defaults.set(Data("[{]".utf8), forKey: "onetwenty.pending.completions")

        #expect(store.pendingCompletions().isEmpty)
        #expect(isolated.defaults.object(forKey: "onetwenty.pending.completions") == nil)
    }

    @Test("実行中の印と保存待ちは、互いに影響しない")
    func runningAndPendingAreIndependent() {
        let running = marker(startedAt: 1_000)
        let pending = marker(startedAt: 2_000)
        store.save(running)
        store.addPending(pending)

        store.clear()

        #expect(store.load() == nil)
        #expect(store.pendingCompletions() == [pending])

        store.save(running)
        store.removePending(sessionID: pending.sessionID)

        #expect(store.load() == running)
        #expect(store.pendingCompletions().isEmpty)
    }

    @Test("読み取り専用の口として渡しても、同じ保存待ちが読める")
    func readableThroughReadingProtocol() {
        let marker = marker()
        store.addPending(marker)

        let reader: any PendingCompletionsReading = store

        #expect(reader.pendingCompletions() == [marker])
    }
}
