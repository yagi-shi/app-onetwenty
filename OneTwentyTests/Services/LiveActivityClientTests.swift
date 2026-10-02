import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct LiveActivityClientTests {

    @Test("Live Activity を開始できない環境でも、アプリは止まらない")
    func startDoesNotCrash() async {
        let client = ActivityKitLiveActivityClient()
        let sessionID = UUID()
        let startedAt = Date()

        // 無効にされている・開始に失敗する、のどちらでも呼び出し側が続行できること
        try? await client.start(sessionID: sessionID, startedAt: startedAt, endsAt: startedAt.addingTimeInterval(120))
        await client.end(sessionID: sessionID)

        #expect(!client.currentActivities().contains { $0.sessionID == sessionID })
    }

    @Test("該当する Live Activity がなくても、終了の呼び出しは何も起こさない")
    func endingNothingIsNoOp() async {
        let client = ActivityKitLiveActivityClient()

        await client.end(activityIDs: [])
        await client.end(activityIDs: ["存在しないID"])
        await client.end(sessionID: UUID())
    }
}

@MainActor
struct FakeLiveActivityClientTests {

    @Test("フェイクは、開始した Activity を保持し、指定したものだけを終了する")
    func tracksActivities() async throws {
        let client = FakeLiveActivityClient()
        let first = UUID()
        let second = UUID()
        let now = Date(timeIntervalSince1970: 1_000)
        try await client.start(sessionID: first, startedAt: now, endsAt: now.addingTimeInterval(120))
        try await client.start(sessionID: second, startedAt: now, endsAt: now.addingTimeInterval(120))

        await client.end(sessionID: first)

        #expect(client.currentActivities().map(\.sessionID) == [second])
        #expect(client.endedActivityIDs.count == 1)
    }

    @Test("フェイクは、開始の失敗を再現できる")
    func canFailToStart() async {
        let client = FakeLiveActivityClient()
        client.startFails = true
        let now = Date(timeIntervalSince1970: 1_000)

        await #expect(throws: FakeLiveActivityClient.StartFailure.self) {
            try await client.start(sessionID: UUID(), startedAt: now, endsAt: now.addingTimeInterval(120))
        }
        #expect(client.currentActivities().isEmpty)
    }
}
