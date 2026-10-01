import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct TestClockTests {

    @Test("advance(by:) の前後で now が進む")
    func advanceMovesNowForward() {
        let start = Date(timeIntervalSince1970: 1_000)
        let clock = TestClock(now: start)

        clock.advance(by: 120)

        #expect(clock.now == start.addingTimeInterval(120))
    }

    @Test("now を直接設定できる")
    func nowCanBeSetDirectly() {
        let clock = TestClock()
        let target = Date(timeIntervalSince1970: 86_400)

        clock.now = target

        #expect(clock.now == target)
    }

    @Test("カレンダーを差し替えられる")
    func calendarCanBeReplaced() throws {
        let clock = TestClock()
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = try #require(TimeZone(identifier: "Asia/Tokyo"))

        clock.calendar = tokyo

        #expect(clock.calendar.timeZone.identifier == "Asia/Tokyo")
    }

    @Test("WallClock として渡しても同じ時刻を返す")
    func usableThroughProtocol() {
        let clock = TestClock(now: Date(timeIntervalSince1970: 500))
        let wallClock: any WallClock = clock

        clock.advance(by: 60)

        #expect(wallClock.now == Date(timeIntervalSince1970: 560))
    }
}
