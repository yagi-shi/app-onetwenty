import Foundation
import Testing
@testable import OneTwenty

struct DayKeyTests {
    private let tokyo = TestCalendars.gregorian("Asia/Tokyo")

    @Test("23:59:59 と 0:00:00 は別の日になる")
    func midnightSeparatesDays() {
        let lastSecond = TestCalendars.date(2026, 10, 1, 23, 59, 59, in: tokyo)
        let midnight = lastSecond.addingTimeInterval(1)

        let before = DayKey(lastSecond, calendar: tokyo)
        let after = DayKey(midnight, calendar: tokyo)

        #expect(before != after)
        #expect(before < after)
        #expect(before.adding(days: 1, calendar: tokyo) == after)
    }

    @Test("同じ日の中の時刻は同じ日になる")
    func sameDayTimesAreEqual() {
        let morning = TestCalendars.date(2026, 10, 1, 0, 0, 0, in: tokyo)
        let night = TestCalendars.date(2026, 10, 1, 23, 59, 59, in: tokyo)

        #expect(DayKey(morning, calendar: tokyo) == DayKey(night, calendar: tokyo))
    }

    @Test("同じ時刻でも、タイムゾーンが違えば別の日になる")
    func timeZoneChangesTheDay() {
        let utc = TestCalendars.gregorian("UTC")
        // UTC の 10/1 20:00 は、東京では 10/2 5:00
        let instant = TestCalendars.date(2026, 10, 1, 20, 0, 0, in: utc)

        let inUTC = DayKey(instant, calendar: utc)
        let inTokyo = DayKey(instant, calendar: tokyo)

        #expect(inUTC.day == 1)
        #expect(inTokyo.day == 2)
        #expect(inUTC != inTokyo)
    }

    @Test("夏時間に切り替わる日をまたいでも、日の加減算が崩れない")
    func arithmeticAcrossDaylightSavingStart() {
        // ニューヨークは 2026/3/8 の 2:00 に 3:00 へ進む（この日は 23 時間しかない）
        let newYork = TestCalendars.gregorian("America/New_York")
        let march7 = DayKey(TestCalendars.date(2026, 3, 7, 12, in: newYork), calendar: newYork)
        let march8 = DayKey(TestCalendars.date(2026, 3, 8, 12, in: newYork), calendar: newYork)
        let march9 = DayKey(TestCalendars.date(2026, 3, 9, 12, in: newYork), calendar: newYork)

        #expect(march7.adding(days: 1, calendar: newYork) == march8)
        #expect(march8.adding(days: 1, calendar: newYork) == march9)
        #expect(march9.adding(days: -2, calendar: newYork) == march7)
        #expect(DayKey.days(from: march7, to: march9, calendar: newYork) == 2)
        #expect(DayKey.days(from: march9, to: march7, calendar: newYork) == -2)
    }

    @Test("夏時間が終わる日をまたいでも、日の加減算が崩れない")
    func arithmeticAcrossDaylightSavingEnd() {
        // ニューヨークは 2026/11/1 の 2:00 に 1:00 へ戻る（この日は 25 時間ある）
        let newYork = TestCalendars.gregorian("America/New_York")
        let october31 = DayKey(TestCalendars.date(2026, 10, 31, 12, in: newYork), calendar: newYork)
        let november2 = DayKey(TestCalendars.date(2026, 11, 2, 12, in: newYork), calendar: newYork)

        #expect(october31.adding(days: 2, calendar: newYork) == november2)
        #expect(DayKey.days(from: october31, to: november2, calendar: newYork) == 2)
    }

    @Test("0:00 が存在しない日でも、その日の始まりが同じ日に収まる")
    func startOfDayWhenMidnightDoesNotExist() {
        // ハバナは夏時間の開始で 0:00 が 1:00 に進むため、2026/3/8 には 0:00 が存在しない
        let havana = TestCalendars.gregorian("America/Havana")
        let key = DayKey(TestCalendars.date(2026, 3, 8, 12, in: havana), calendar: havana)

        let start = key.startOfDay(calendar: havana)

        #expect(DayKey(start, calendar: havana) == key)
        #expect(DayKey(start.addingTimeInterval(-1), calendar: havana) == key.adding(days: -1, calendar: havana))
    }

    @Test("その日の始まりは 0:00、翌日の始まりの直前までが同じ日")
    func startOfDayBounds() {
        let key = DayKey(TestCalendars.date(2026, 10, 1, 15, in: tokyo), calendar: tokyo)

        let start = key.startOfDay(calendar: tokyo)
        let nextStart = key.adding(days: 1, calendar: tokyo).startOfDay(calendar: tokyo)

        #expect(start == TestCalendars.date(2026, 10, 1, 0, 0, 0, in: tokyo))
        #expect(nextStart.timeIntervalSince(start) == 86_400)
        #expect(DayKey(nextStart.addingTimeInterval(-0.001), calendar: tokyo) == key)
        #expect(DayKey(nextStart, calendar: tokyo) != key)
    }

    @Test("月末・年末をまたぐ加算")
    func addingAcrossMonthAndYear() {
        let december31 = DayKey(TestCalendars.date(2026, 12, 31, 12, in: tokyo), calendar: tokyo)

        let january1 = december31.adding(days: 1, calendar: tokyo)

        #expect(january1.year == 2027)
        #expect(january1.month == 1)
        #expect(january1.day == 1)
        #expect(december31 < january1)
    }

    @Test("和暦でも、改元をまたいで日の前後関係と加減算が保たれる")
    func japaneseCalendarAcrossEraChange() {
        var japanese = Calendar(identifier: .japanese)
        japanese.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        // 平成 31/4/30 の翌日が 令和 1/5/1
        let lastDayOfHeisei = DayKey(TestCalendars.date(2019, 4, 30, 12, in: tokyo), calendar: japanese)
        let firstDayOfReiwa = DayKey(TestCalendars.date(2019, 5, 1, 12, in: tokyo), calendar: japanese)

        #expect(lastDayOfHeisei < firstDayOfReiwa)
        #expect(lastDayOfHeisei.adding(days: 1, calendar: japanese) == firstDayOfReiwa)
        #expect(DayKey.days(from: lastDayOfHeisei, to: firstDayOfReiwa, calendar: japanese) == 1)
        #expect(DayKey(firstDayOfReiwa.startOfDay(calendar: japanese), calendar: japanese) == firstDayOfReiwa)
    }
}

@MainActor
struct SystemClockTests {

    @Test("現在時刻と、端末のカレンダーを返す")
    func returnsCurrentTimeAndCalendar() {
        let clock = SystemClock()

        let before = Date()
        let now = clock.now
        let after = Date()

        #expect(before <= now && now <= after)
        #expect(clock.calendar.identifier == Calendar.current.identifier)
        #expect(clock.calendar.timeZone == Calendar.current.timeZone)
    }
}
