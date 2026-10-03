import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct SessionServiceTests {
    private let h: ServiceHarness
    private let habit: HabitSnapshot
    private var service: SessionService { h.sessionService }

    init() throws {
        h = try ServiceHarness()
        habit = try h.addHabit("本を1ページ読む")
    }

    /// タイマーを開始し、その印を返す。
    private func start(_ habit: HabitSnapshot? = nil) async throws -> RunningSessionMarker {
        guard case .started(let marker) = await service.start(habitID: (habit ?? self.habit).id) else {
            throw StartFailed()
        }
        return marker
    }

    private struct StartFailed: Error {}

    // MARK: 開始

    @Test("開始すると、実行中の印・Live Activity・完了通知を用意し、完了音を読み込んでおく")
    func startPreparesEverything() async throws {
        let marker = try await start()
        let endsAt = h.clock.now.addingTimeInterval(120)

        #expect(marker.habitID == habit.id)
        #expect(marker.startedAt == h.clock.now)
        #expect(h.runningStore.load() == marker)
        #expect(h.liveActivity.currentActivities().map(\.sessionID) == [marker.sessionID])
        #expect(h.liveActivity.currentActivities().first?.endsAt == endsAt)
        #expect(h.feedback.prepareCount == 1)
        #expect(h.feedback.playCompletionCount == 0)

        let timer = try #require(h.notifications.pending.first { $0.identifier.hasPrefix("timer.") })
        #expect(timer.identifier == NotificationIdentifier.timer(sessionID: marker.sessionID))
        #expect(timer.trigger == .date(endsAt))
        #expect(timer.body == NotificationText.timerBody)
        #expect(!timer.body.contains(habit.title))
    }

    @Test("今日すでに完了した習慣は開始できない")
    func rejectsCompletedHabit() async throws {
        _ = try await start()
        h.clock.advance(by: 120)
        _ = await service.completeInForeground()

        #expect(await service.start(habitID: habit.id) == .rejected(.alreadyCompletedToday))
        #expect(h.runningStore.load() == nil)
    }

    @Test("開始できるかどうかは、実際の現在の日で判定する（前日の完了は妨げない）")
    func judgesByActualCurrentDay() async throws {
        h.clock.now = TestCalendars.date(2026, 10, 1, 23, 58, in: h.calendar)
        _ = try await start()
        h.clock.advance(by: 120)                       // 10/2 0:00 に完了
        _ = await service.completeInForeground()

        h.clock.advance(by: 60)                        // 10/2 0:01

        guard case .started = await service.start(habitID: habit.id) else {
            Issue.record("日が変わったので開始できるはず")
            return
        }
    }

    @Test("別のタイマーが実行中なら開始できない")
    func rejectsWhileRunning() async throws {
        let other = try h.addHabit("靴を履く")
        let running = try await start()

        #expect(await service.start(habitID: other.id) == .rejected(.alreadyRunning))
        #expect(h.runningStore.load() == running)
    }

    @Test("存在しない・アーカイブ済みの習慣は開始できない")
    func rejectsInactiveHabit() async throws {
        let archived = try h.addHabit("靴を履く")
        try h.habitStore.archive(id: archived.id, at: h.clock.now)

        #expect(await service.start(habitID: UUID()) == .rejected(.habitNotActive))
        #expect(await service.start(habitID: archived.id) == .rejected(.habitNotActive))
    }

    @Test("Live Activity を開始できなくても、タイマーは始まる")
    func startsWithoutLiveActivity() async throws {
        h.liveActivity.startFails = true

        let marker = try await start()

        #expect(h.runningStore.load() == marker)
        #expect(h.timerIdentifiers.count == 1)
    }

    @Test("完了通知を予約できなくても、タイマーは始まる")
    func startsEvenIfNotificationFails() async throws {
        h.notifications.failingPrefixes = ["timer."]

        let marker = try await start()

        #expect(h.runningStore.load() == marker)
        #expect(h.timerIdentifiers.isEmpty)
    }

    // MARK: 通知の許可

    @Test("リマインダーがオフでも、完了通知は予約する")
    func schedulesTimerEvenIfRemindersAreOff() async throws {
        h.settings.reminderEnabled = false

        _ = try await start()

        #expect(h.timerIdentifiers.count == 1)
        #expect(h.reminderIdentifiers.isEmpty)
    }

    @Test("通知が拒否されていれば、完了通知を予約せず、許可も求めない")
    func deniedSchedulesNothing() async throws {
        h.notifications.authorization = .denied

        _ = try await start()

        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.notifications.requestAuthorizationCount == 0)
    }

    @Test("許可が未決定なら 1 回だけ求め、許可されたら完了通知とリマインダーを予約する")
    func requestsAuthorizationOnce() async throws {
        h.notifications.authorization = .notDetermined

        let marker = try await start()
        await service.authorizationRequest?.value

        #expect(h.notifications.requestAuthorizationCount == 1)
        #expect(h.timerIdentifiers == [NotificationIdentifier.timer(sessionID: marker.sessionID)])
        #expect(h.reminderIdentifiers.count == 60)

        // 2 回目の開始では、もう決定済みなので求めない
        await service.abort()
        _ = try await start()
        await service.authorizationRequest?.value
        #expect(h.notifications.requestAuthorizationCount == 1)
    }

    @Test("許可を求めて拒否されたら、完了通知を予約しない")
    func requestDenied() async throws {
        h.notifications.authorization = .notDetermined
        h.notifications.authorizationAfterRequest = .denied

        _ = try await start()
        await service.authorizationRequest?.value

        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.reminderIdentifiers.isEmpty)
    }

    @Test("許可に答える前に中断していたら、完了通知を予約しない")
    func abortedBeforeAuthorizationIsGranted() async throws {
        h.notifications.authorization = .notDetermined
        h.notifications.whileRequestingAuthorization = { [service] in await service.abort() }

        _ = try await start()
        await service.authorizationRequest?.value

        #expect(h.runningStore.load() == nil)
        #expect(h.timerIdentifiers.isEmpty)
    }

    // MARK: 中断

    @Test("中断すると記録は残らず、印・完了通知・Live Activity が消える。リマインダーには触れない")
    func abortLeavesNoRecord() async throws {
        await h.reminders.sync()
        let reminders = h.reminderIdentifiers
        _ = try await start()
        h.clock.advance(by: 30)

        await service.abort()

        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.runningStore.load() == nil)
        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.liveActivity.currentActivities().isEmpty)
        #expect(h.feedback.playCompletionCount == 0)
        #expect(h.reminderIdentifiers == reminders)
        #expect(reminders.count == 60)
    }

    @Test("中断した習慣は同じ日にやり直せて、経過は 0 秒から始まる")
    func canRetryAfterAbort() async throws {
        let first = try await start()
        h.clock.advance(by: 90)
        await service.abort()

        let second = try await start()

        #expect(second.sessionID != first.sessionID)
        #expect(second.startedAt == h.clock.now)
        #expect(TimerEngine.progress(startedAt: second.startedAt, now: h.clock.now).elapsed == 0)
    }

    @Test("実行中でなければ、中断は何もしない")
    func abortWithoutRunning() async {
        await service.abort()

        #expect(h.notifications.removedIdentifiers.isEmpty)
    }

    // MARK: フォアグラウンドでの完了

    @Test("120 秒たつ前は、完了にならない")
    func notFinishedYet() async throws {
        let marker = try await start()
        h.clock.advance(by: 119.999)

        #expect(await service.completeInForeground() == nil)
        #expect(h.runningStore.load() == marker)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.feedback.playCompletionCount == 0)
    }

    @Test("120 秒たつと、完了を記録し、音と振動を鳴らし、印・完了通知・Live Activity を片付ける")
    func completesInForeground() async throws {
        let marker = try await start()
        h.clock.advance(by: 120)

        let result = await service.completeInForeground()

        #expect(result == CompletionResult(habitID: habit.id, attributedDay: h.today, saved: true))
        #expect(h.sessions.allSessions() == [SessionSnapshot(
            id: marker.sessionID,
            habitID: habit.id,
            startedAt: marker.startedAt,
            completedAt: marker.startedAt.addingTimeInterval(120)
        )])
        #expect(h.feedback.playCompletionCount == 1)
        #expect(h.runningStore.load() == nil)
        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.liveActivity.currentActivities().isEmpty)
    }

    @Test("終了時刻から 1 秒以上遅れて気づいた完了では、記録はするが音と振動は鳴らさない", arguments: [
        (120.0, 1),
        (120.999, 1),
        (121.0, 0),
        (300.0, 0),
    ])
    func feedbackOnlyWhenObservedLive(seconds: TimeInterval, expectedPlays: Int) async throws {
        _ = try await start()
        h.clock.advance(by: seconds)

        let result = await service.completeInForeground()

        #expect(result?.saved == true)
        #expect(h.sessions.allSessions().count == 1)
        #expect(h.feedback.playCompletionCount == expectedPlays)
    }

    @Test("完了の処理は 1 回だけ。続けて呼んでも、復元が走っても、記録は 1 件")
    func completesOnlyOnce() async throws {
        _ = try await start()
        h.clock.advance(by: 120)

        #expect(await service.completeInForeground() != nil)
        #expect(await service.completeInForeground() == nil)
        #expect(await service.recoverOnActivation(launch: .warm) == RecoveryOutcome.none)

        #expect(h.sessions.allSessions().count == 1)
        #expect(h.feedback.playCompletionCount == 1)
    }

    @Test("23:59 に始めて日をまたいで完了しても、記録は始めた日に属する")
    func attributedToStartDay() async throws {
        h.clock.now = TestCalendars.date(2026, 10, 1, 23, 59, in: h.calendar)
        let startDay = h.today
        _ = try await start()
        h.clock.advance(by: 120)

        let result = await service.completeInForeground()

        #expect(result?.attributedDay == startDay)
        #expect(h.today != startDay)
        let session = try #require(h.sessions.allSessions().first)
        #expect(DayKey(session.startedAt, calendar: h.calendar) == startDay)
    }

    @Test("今日の習慣がすべて完了した時点で、今日のリマインダーを取り消す")
    func cancelsTodayReminderWhenAllCompleted() async throws {
        // 通知時刻（8:00）を過ぎると完了に関係なく今日の分は外れるので、十分に早い時刻で確かめる
        h.clock.now = TestCalendars.date(2026, 10, 1, 7, 0, in: h.calendar)
        let other = try h.addHabit("靴を履く")
        await h.reminders.sync()
        #expect(h.reminderIdentifiers.contains(h.todayReminderIdentifier))

        _ = try await start(habit)
        h.clock.advance(by: 120)
        _ = await service.completeInForeground()
        #expect(h.reminderIdentifiers.contains(h.todayReminderIdentifier))

        _ = try await start(other)
        h.clock.advance(by: 120)
        _ = await service.completeInForeground()

        #expect(!h.reminderIdentifiers.contains(h.todayReminderIdentifier))
        #expect(h.reminderIdentifiers.count == 59)
    }

    // MARK: 保存の失敗

    @Test("保存に失敗しても完了として扱い、その実行を保存待ちに移して印を消す")
    func saveFailureMovesToPending() async throws {
        let marker = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true

        let result = await service.completeInForeground()

        #expect(result == CompletionResult(habitID: habit.id, attributedDay: h.today, saved: false))
        #expect(h.runningStore.load() == nil)
        #expect(service.pendingCompletions() == [marker])
        #expect(h.feedback.playCompletionCount == 1)
        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.liveActivity.currentActivities().isEmpty)
    }

    @Test("保存に失敗した直後に、1 回だけやり直す")
    func retriesOnceRightAfterFailure() async throws {
        _ = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true

        _ = await service.completeInForeground()

        // 開始時の保存待ちの確認では保存を試みない（保存待ちが空のため）。完了時の 1 回＋やり直しの 1 回
        #expect(h.sessions.insertAttempts == 2)
    }

    @Test("保存待ちが残っていても、別の習慣は開始できる")
    func pendingDoesNotBlockOtherHabits() async throws {
        let other = try h.addHabit("靴を履く")
        _ = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true
        _ = await service.completeInForeground()

        guard case .started(let marker) = await service.start(habitID: other.id) else {
            Issue.record("別の習慣は開始できるはず")
            return
        }
        #expect(marker.habitID == other.id)
        #expect(service.pendingCompletions().count == 1)
    }

    @Test("保存待ちが残っている習慣は、同じ日にもう一度は開始できない")
    func pendingBlocksSameHabit() async throws {
        _ = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true
        _ = await service.completeInForeground()

        #expect(await service.start(habitID: habit.id) == .rejected(.alreadyCompletedToday))
    }

    @Test("開始の前に保存待ちを解消し、その習慣が今日完了済みになれば開始しない")
    func startFlushesPending() async throws {
        let marker = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true
        _ = await service.completeInForeground()
        h.sessions.failsInsert = false

        #expect(await service.start(habitID: habit.id) == .rejected(.alreadyCompletedToday))

        #expect(service.pendingCompletions().isEmpty)
        #expect(h.sessions.allSessions().map(\.id) == [marker.sessionID])
    }

    @Test("保存待ちの再試行は、保存できたときだけ true を返す")
    func flushResult() async throws {
        #expect(await service.flushPendingCompletion() == false)

        _ = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true
        _ = await service.completeInForeground()
        #expect(await service.flushPendingCompletion() == false)
        #expect(service.pendingCompletions().count == 1)

        h.sessions.failsInsert = false
        #expect(await service.flushPendingCompletion() == true)
        #expect(service.pendingCompletions().isEmpty)
        #expect(h.sessions.allSessions().count == 1)
    }

    @Test("保存待ちのままでも今日の完了として数え、今日のリマインダーを取り消す")
    func pendingCountsForReminders() async throws {
        await h.reminders.sync()
        h.clock.now = TestCalendars.date(2026, 10, 1, 7, 50, in: h.calendar)
        _ = try await start()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true

        _ = await service.completeInForeground()

        #expect(!h.reminderIdentifiers.contains(h.todayReminderIdentifier))
    }

    // MARK: 復元

    @Test("実行中のタイマーがなければ、復元は何もしない")
    func recoverWithoutMarker() async {
        #expect(await service.recoverOnActivation(launch: .cold) == RecoveryOutcome.none)
        #expect(await service.recoverOnActivation(launch: .warm) == RecoveryOutcome.none)
    }

    @Test("裏に回って 120 秒未満で戻ったら、計測を続ける。Live Activity も消さない")
    func keepsRunning() async throws {
        let marker = try await start()
        h.clock.advance(by: 60)

        let outcome = await service.recoverOnActivation(launch: .warm)

        #expect(outcome == RecoveryOutcome.none)
        #expect(h.runningStore.load() == marker)
        #expect(h.liveActivity.currentActivities().map(\.sessionID) == [marker.sessionID])
        #expect(h.timerIdentifiers.count == 1)
        #expect(h.sessions.allSessions().isEmpty)
    }

    @Test("裏で 120 秒たっていたら、音と振動なしで完了を記録し、片付ける", arguments: [LaunchKind.cold, .warm])
    func completesInBackground(launch: LaunchKind) async throws {
        let marker = try await start()
        h.clock.advance(by: 300)

        let outcome = await service.recoverOnActivation(launch: launch)

        #expect(outcome == .completed(habitID: habit.id, attributedDay: DayKey(marker.startedAt, calendar: h.calendar)))
        #expect(h.sessions.allSessions().map(\.id) == [marker.sessionID])
        #expect(h.sessions.allSessions().first?.completedAt == marker.startedAt.addingTimeInterval(120))
        #expect(h.feedback.playCompletionCount == 0)
        #expect(h.runningStore.load() == nil)
        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.liveActivity.currentActivities().isEmpty)
    }

    @Test("120 秒たたないうちにアプリが終了していたら、記録せずに破棄する")
    func discardsUnfinishedAfterTermination() async throws {
        _ = try await start()
        h.clock.advance(by: 60)

        let outcome = await service.recoverOnActivation(launch: .cold)

        #expect(outcome == .discarded)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.runningStore.load() == nil)
        #expect(h.timerIdentifiers.isEmpty)
        #expect(h.liveActivity.currentActivities().isEmpty)
    }

    @Test("開始から 24 時間以上たっていたら、記録せずに破棄する", arguments: [LaunchKind.cold, .warm])
    func discardsAfter24Hours(launch: LaunchKind) async throws {
        _ = try await start()
        h.clock.advance(by: 86_400)

        #expect(await service.recoverOnActivation(launch: launch) == .discarded)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.runningStore.load() == nil)
    }

    @Test("対象の習慣がアーカイブ済みなら、走り切っていても記録せずに破棄する")
    func discardsWhenHabitIsArchived() async throws {
        _ = try await start()
        try h.habitStore.archive(id: habit.id, at: h.clock.now)
        h.clock.advance(by: 300)

        #expect(await service.recoverOnActivation(launch: .warm) == .discarded)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.runningStore.load() == nil)
        #expect(service.pendingCompletions().isEmpty)
    }

    @Test("対象の習慣が存在しない印は、記録せずに破棄する")
    func discardsWhenHabitIsMissing() async {
        h.runningStore.save(RunningSessionMarker(sessionID: UUID(), habitID: UUID(), startedAt: h.clock.now))
        h.clock.advance(by: 300)

        #expect(await service.recoverOnActivation(launch: .warm) == .discarded)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.runningStore.load() == nil)
    }

    @Test("取り残された Live Activity だけを終了し、実行中のものは残す")
    func endsOnlyLeftoverActivities() async throws {
        h.liveActivity.seed(ActivitySnapshot(activityID: "取り残し", sessionID: UUID(), endsAt: h.clock.now.addingTimeInterval(-500)))
        let marker = try await start()
        h.clock.advance(by: 30)

        _ = await service.recoverOnActivation(launch: .warm)

        #expect(h.liveActivity.endedActivityIDs == ["取り残し"])
        #expect(h.liveActivity.currentActivities().map(\.sessionID) == [marker.sessionID])
    }

    @Test("実行中の印が壊れていたら、印なしとして扱い、残った Live Activity を終了する")
    func brokenMarker() async {
        h.isolated.defaults.set(Data("壊れた値".utf8), forKey: "onetwenty.running.session")
        h.liveActivity.seed(ActivitySnapshot(activityID: "取り残し", sessionID: UUID(), endsAt: h.clock.now.addingTimeInterval(60)))

        #expect(await service.recoverOnActivation(launch: .cold) == RecoveryOutcome.none)
        #expect(h.liveActivity.currentActivities().isEmpty)
    }

    @Test("復元のとき、保存待ちの保存をやり直す。24 時間以上たった保存待ちは捨てる")
    func recoverRetriesPending() async throws {
        let other = try h.addHabit("靴を履く")
        let recent = RunningSessionMarker(sessionID: UUID(), habitID: habit.id, startedAt: h.clock.now.addingTimeInterval(-3_600))
        let stale = RunningSessionMarker(sessionID: UUID(), habitID: other.id, startedAt: h.clock.now.addingTimeInterval(-86_400))
        h.runningStore.addPending(recent)
        h.runningStore.addPending(stale)

        _ = await service.recoverOnActivation(launch: .cold)

        #expect(service.pendingCompletions().isEmpty)
        #expect(h.sessions.allSessions().map(\.id) == [recent.sessionID])
    }

    @Test("裏で完了した記録の保存に失敗しても、保存待ちに回して完了として扱う")
    func backgroundCompletionSaveFailure() async throws {
        let marker = try await start()
        h.clock.advance(by: 300)
        h.sessions.failsInsert = true

        let outcome = await service.recoverOnActivation(launch: .warm)

        #expect(outcome == .completed(habitID: habit.id, attributedDay: DayKey(marker.startedAt, calendar: h.calendar)))
        #expect(h.runningStore.load() == nil)
        #expect(service.pendingCompletions() == [marker])
    }
}
