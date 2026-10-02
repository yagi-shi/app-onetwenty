import Foundation
import Testing
@testable import OneTwenty

struct ReminderPlannerTests {
    private let calendar = TestCalendars.gregorian("Asia/Tokyo")
    private let eight = ReminderTime(hour: 8, minute: 0)

    private func now(_ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
        TestCalendars.date(2026, 10, 1, hour, minute, second, in: calendar)
    }

    private func plan(
        now: Date? = nil,
        calendar: Calendar? = nil,
        time: ReminderTime? = nil,
        enabled: Bool = true,
        authorization: NotificationAuthorization = .authorized,
        activeHabitCount: Int = 1,
        todayAllCompleted: Bool = false
    ) -> [PlannedReminder] {
        ReminderPlanner.plan(
            now: now ?? self.now(7, 59),
            calendar: calendar ?? self.calendar,
            time: time ?? eight,
            enabled: enabled,
            authorization: authorization,
            activeHabitCount: activeHabitCount,
            todayAllCompleted: todayAllCompleted
        )
    }

    private func day(_ day: Int, month: Int = 10) -> DayKey {
        DayKey(TestCalendars.date(2026, month, day, 12, in: calendar), calendar: calendar)
    }

    // MARK: 予約する範囲

    @Test("通知時刻の前なら、今日を含む 60 日分")
    func includesTodayBeforeReminderTime() {
        let result = plan(now: now(7, 59))

        #expect(result.count == 60)
        #expect(result.first?.day == day(1))
        #expect(result.last?.day == day(1).adding(days: 59, calendar: calendar))
        #expect(result.map(\.day) == result.map(\.day).sorted())
    }

    @Test("通知時刻を過ぎていれば、今日を含まない 59 日分")
    func excludesTodayAfterReminderTime() {
        let result = plan(now: now(8, 1))

        #expect(result.count == 59)
        #expect(result.first?.day == day(2))
        #expect(result.last?.day == day(1).adding(days: 59, calendar: calendar))
    }

    @Test("通知時刻ちょうどなら、今日を含まない")
    func excludesTodayExactlyAtReminderTime() {
        #expect(plan(now: now(8, 0)).first?.day == day(2))
        #expect(plan(now: now(7, 59, 59)).first?.day == day(1))
    }

    @Test("今日の習慣がすべて完了していれば、通知時刻の前でも今日を含まない")
    func excludesTodayWhenAllCompleted() {
        let result = plan(now: now(7, 59), todayAllCompleted: true)

        #expect(result.count == 59)
        #expect(result.first?.day == day(2))
    }

    @Test("どの時刻に実行しても 60 件を超えない", arguments: [0, 7, 8, 12, 23])
    func neverExceedsSixty(hour: Int) {
        #expect(plan(now: now(hour, 30)).count <= 60)
    }

    // MARK: 予約しない条件

    @Test("リマインダーがオフなら予約しない")
    func emptyWhenDisabled() {
        #expect(plan(enabled: false).isEmpty)
    }

    @Test("通知が許可されていなければ予約しない", arguments: [NotificationAuthorization.notDetermined, .denied])
    func emptyWhenNotAuthorized(authorization: NotificationAuthorization) {
        #expect(plan(authorization: authorization).isEmpty)
    }

    @Test("習慣が 0 件なら予約しない")
    func emptyWithoutHabits() {
        #expect(plan(activeHabitCount: 0).isEmpty)
    }

    // MARK: 発火時刻と識別子

    @Test("毎日、指定した時刻に発火する")
    func firesAtReminderTimeEveryDay() {
        let result = plan(time: ReminderTime(hour: 21, minute: 30))

        for reminder in result {
            let components = calendar.dateComponents([.hour, .minute, .second], from: reminder.fireDate)
            #expect(components.hour == 21 && components.minute == 30 && components.second == 0)
            #expect(DayKey(reminder.fireDate, calendar: calendar) == reminder.day)
        }
    }

    @Test("識別子は reminder.<日付>.<時刻> の形で、日ごとに異なる")
    func identifierFormat() {
        let result = plan(now: now(7, 59))

        #expect(result.first?.identifier == "reminder.2026-10-01.0800")
        #expect(result[1].identifier == "reminder.2026-10-02.0800")
        #expect(result.allSatisfy { $0.identifier.hasPrefix(ReminderPlanner.identifierPrefix) })
        #expect(Set(result.map(\.identifier)).count == result.count)
    }

    @Test("通知時刻を変えると、すべての識別子が変わる")
    func identifiersChangeWithTime() {
        let before = Set(plan(now: now(6, 0), time: eight).map(\.identifier))
        let after = plan(now: now(6, 0), time: ReminderTime(hour: 6, minute: 5))

        #expect(after.first?.identifier == "reminder.2026-10-01.0605")
        #expect(before.isDisjoint(with: after.map(\.identifier)))
    }

    @Test("夏時間に切り替わる日をまたいでも、現地の指定時刻に発火する")
    func firesAtLocalTimeAcrossDaylightSaving() {
        let newYork = TestCalendars.gregorian("America/New_York")
        let march1 = TestCalendars.date(2026, 3, 1, 7, 0, in: newYork)

        let result = plan(now: march1, calendar: newYork)

        #expect(result.count == 60)
        for reminder in result {
            #expect(newYork.component(.hour, from: reminder.fireDate) == 8)
        }
        #expect(Set(result.map(\.day)).count == 60)
    }
}
