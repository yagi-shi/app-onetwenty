import Foundation
import Testing
@testable import OneTwenty

struct TimerActivityAttributesTests {

    @Test("属性は JSON に変換して戻しても同じ値になる")
    func attributesRoundTrip() throws {
        let attributes = TimerActivityAttributes(sessionID: UUID(), endedLabel: "終了")

        let data = try JSONEncoder().encode(attributes)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.self, from: data)

        #expect(decoded.sessionID == attributes.sessionID)
        #expect(decoded.endedLabel == "終了")
    }

    @Test("コンテンツ状態は JSON に変換して戻しても同じ値になる")
    func contentStateRoundTrip() throws {
        let startedAt = Date(timeIntervalSince1970: 1_000)
        let state = TimerActivityAttributes.ContentState(
            startedAt: startedAt,
            endsAt: startedAt.addingTimeInterval(120)
        )

        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(TimerActivityAttributes.ContentState.self, from: data)

        #expect(decoded == state)
    }
}
