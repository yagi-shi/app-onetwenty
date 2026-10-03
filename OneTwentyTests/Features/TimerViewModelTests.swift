import Foundation
import Testing
@testable import OneTwenty

@MainActor
struct TimerViewModelTests {
    private let h: ServiceHarness
    private let habit: HabitSnapshot
    /// セーフエリア上端の位置（ダイナミックアイランドのある機種を想定）。
    private let safeAreaTop: CGFloat = 59

    /// 通知を受け取った順に記録する。
    private final class Events {
        var completions: [TimerCompletion] = []
        var displayEndedCount = 0
        var abortedCount = 0
    }

    init() throws {
        h = try ServiceHarness()
        habit = try h.addHabit()
    }

    /// タイマーを開始し、その画面の ViewModel を作る。
    private func startTimer(previousMessage: String? = nil) async throws -> (TimerViewModel, Events, RunningSessionMarker) {
        guard case .started(let marker) = await h.sessionService.start(habitID: habit.id) else {
            throw StartFailed()
        }
        let viewModel = h.makeTimerViewModel(marker: marker, previousMessage: previousMessage)
        let events = Events()
        viewModel.onCompleted = { events.completions.append($0) }
        viewModel.onCompletionDisplayEnded = { events.displayEndedCount += 1 }
        viewModel.onAborted = { events.abortedCount += 1 }
        return (viewModel, events, marker)
    }

    private struct StartFailed: Error {}

    // MARK: 進み具合

    @Test("実行中は、残り時間と進み具合を返す")
    func progressWhileRunning() async throws {
        let (viewModel, _, marker) = try await startTimer()
        h.clock.advance(by: 30)

        #expect(viewModel.phase == .running(marker))
        #expect(viewModel.progress?.remaining == 90)
        #expect(viewModel.progress?.fraction == 0.25)
    }

    // MARK: 完了

    @Test("120 秒たつ前は、描き直しても完了にならない")
    func noCompletionBefore120Seconds() async throws {
        let (viewModel, events, marker) = try await startTimer()
        h.clock.advance(by: 119.999)

        viewModel.tick()
        await viewModel.pendingWork?.value

        #expect(viewModel.phase == .running(marker))
        #expect(events.completions.isEmpty)
        #expect(h.sessions.allSessions().isEmpty)
    }

    @Test("120 秒たつと、完了の処理が 1 回だけ走る。何度描き直しても 2 回目は起きない")
    func completesExactlyOnce() async throws {
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 120)

        viewModel.tick()
        viewModel.tick()
        await h.sleeper.waitUntilSleeping()
        viewModel.tick()

        #expect(events.completions.count == 1)
        #expect(h.sessions.allSessions().count == 1)
        #expect(h.feedback.playCompletionCount == 1)
    }

    @Test("完了の通知は 1 本で、習慣・属する日・完了文言・保存の成否を載せ、表示する文言と一致する")
    func completionNotification() async throws {
        let (viewModel, events, _) = try await startTimer()
        let startDay = h.today
        h.clock.advance(by: 120)

        viewModel.tick()
        await h.sleeper.waitUntilSleeping()

        let completion = try #require(events.completions.first)
        #expect(completion.habitID == habit.id)
        #expect(completion.attributedDay == startDay)
        #expect(completion.saved)
        #expect(h.completionMessages.contains(completion.message))
        #expect(viewModel.phase == .completed(message: completion.message))
        #expect(viewModel.progress == nil)
    }

    @Test("完了文言を 2.5 秒表示してから、表示の終わりを知らせる")
    func notifiesDisplayEndAfterDelay() async throws {
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 120)

        viewModel.tick()
        await h.sleeper.waitUntilSleeping()
        #expect(h.sleeper.durations == [.milliseconds(2_500)])
        #expect(events.displayEndedCount == 0)

        h.sleeper.wakeUp()
        await viewModel.pendingWork?.value
        #expect(events.displayEndedCount == 1)
    }

    @Test("直前に表示した完了文言と同じ文言は選ばない")
    func avoidsPreviousMessage() async throws {
        h.completionMessages = ["A", "B"]
        let (viewModel, events, _) = try await startTimer(previousMessage: "A")
        h.clock.advance(by: 120)

        viewModel.tick()
        await h.sleeper.waitUntilSleeping()

        #expect(events.completions.first?.message == "B")
    }

    @Test("完了文言の一覧が空なら、既定の一言を表示する")
    func fallsBackToDefaultMessage() async throws {
        h.completionMessages = []
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 120)

        viewModel.tick()
        await h.sleeper.waitUntilSleeping()

        let message = try #require(events.completions.first?.message)
        #expect(!message.isEmpty)
        #expect(viewModel.phase == .completed(message: message))
    }

    @Test("保存に失敗しても完了として表示し、保存できなかったことを通知に載せる")
    func completionWithSaveFailure() async throws {
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 120)
        h.sessions.failsInsert = true

        viewModel.tick()
        await h.sleeper.waitUntilSleeping()

        #expect(events.completions.first?.saved == false)
        guard case .completed = viewModel.phase else {
            Issue.record("保存に失敗しても完了の表示になるはず")
            return
        }
    }

    // MARK: 中断ジェスチャ

    @Test("下へ引いている間は、引いた量だけ追従し、不透明度が下がる")
    func dragFollowsFinger() async throws {
        let (viewModel, _, _) = try await startTimer()

        viewModel.dragChanged(startY: 400, translationY: 60, safeAreaTop: safeAreaTop)
        #expect(viewModel.dragOffset == 60)
        #expect(abs(viewModel.dragOpacity - 0.7) < 0.000_1)

        viewModel.dragChanged(startY: 400, translationY: 300, safeAreaTop: safeAreaTop)
        #expect(viewModel.dragOffset == 300)
        #expect(abs(viewModel.dragOpacity - 0.4) < 0.000_1)
    }

    @Test("上へ引いても追従しない")
    func upwardDragIsIgnored() async throws {
        let (viewModel, _, _) = try await startTimer()

        viewModel.dragChanged(startY: 400, translationY: -80, safeAreaTop: safeAreaTop)

        #expect(viewModel.dragOffset == 0)
        #expect(viewModel.dragOpacity == 1)
    }

    @Test("119pt で離すと中断せず、元の位置に戻る")
    func releaseBelowThresholdDoesNotAbort() async throws {
        let (viewModel, events, marker) = try await startTimer()
        viewModel.dragChanged(startY: 400, translationY: 119, safeAreaTop: safeAreaTop)

        viewModel.dragEnded(startY: 400, translationY: 119, safeAreaTop: safeAreaTop)
        await viewModel.pendingWork?.value

        #expect(viewModel.phase == .running(marker))
        #expect(viewModel.dragOffset == 0)
        #expect(events.abortedCount == 0)
        #expect(h.runningStore.load() == marker)
    }

    @Test("120pt で離すと中断し、記録を残さず、中断したことを知らせる")
    func releaseAtThresholdAborts() async throws {
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 40)
        viewModel.dragChanged(startY: 400, translationY: 120, safeAreaTop: safeAreaTop)

        viewModel.dragEnded(startY: 400, translationY: 120, safeAreaTop: safeAreaTop)
        #expect(viewModel.phase == .terminated)
        await viewModel.pendingWork?.value

        #expect(events.abortedCount == 1)
        #expect(events.completions.isEmpty)
        #expect(h.runningStore.load() == nil)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.timerIdentifiers.isEmpty)
    }

    @Test("画面上端から 80pt 以内で始めたドラッグには反応しない")
    func ignoresDragStartingNearTop() async throws {
        let (viewModel, events, marker) = try await startTimer()
        let startY = safeAreaTop + 80

        viewModel.dragChanged(startY: startY, translationY: 300, safeAreaTop: safeAreaTop)
        #expect(viewModel.dragOffset == 0)

        viewModel.dragEnded(startY: startY, translationY: 300, safeAreaTop: safeAreaTop)
        await viewModel.pendingWork?.value

        #expect(viewModel.phase == .running(marker))
        #expect(events.abortedCount == 0)
    }

    @Test("上端から 80pt を超えた位置で始めたドラッグには反応する")
    func acceptsDragStartingBelowTopInset() async throws {
        let (viewModel, events, _) = try await startTimer()
        let startY = safeAreaTop + 80.5

        viewModel.dragEnded(startY: startY, translationY: 120, safeAreaTop: safeAreaTop)
        await viewModel.pendingWork?.value

        #expect(events.abortedCount == 1)
    }

    @Test("VoiceOver のエスケープ操作でも中断する")
    func escapeAborts() async throws {
        let (viewModel, events, _) = try await startTimer()

        viewModel.escape()
        await viewModel.pendingWork?.value

        #expect(viewModel.phase == .terminated)
        #expect(events.abortedCount == 1)
        #expect(h.runningStore.load() == nil)
        #expect(h.sessions.allSessions().isEmpty)
    }

    // MARK: アプリが裏にいた間に起きたこと

    @Test("裏で完了していた場合も、完了文言を出し、2.5 秒後に表示の終わりを知らせる。音と振動は鳴らさない")
    func completedInBackground() async throws {
        let (viewModel, events, marker) = try await startTimer()
        h.clock.advance(by: 300)
        _ = await h.sessionService.recoverOnActivation(launch: .warm)

        viewModel.completedInBackground(habitID: habit.id, attributedDay: DayKey(marker.startedAt, calendar: h.calendar))
        await h.sleeper.waitUntilSleeping()

        let completion = try #require(events.completions.first)
        #expect(events.completions.count == 1)
        #expect(completion.saved)
        #expect(viewModel.phase == .completed(message: completion.message))
        #expect(h.feedback.playCompletionCount == 0)
        #expect(events.displayEndedCount == 0)

        h.sleeper.wakeUp()
        await viewModel.pendingWork?.value
        #expect(events.displayEndedCount == 1)
    }

    @Test("裏で破棄された場合は、完了文言を出さず、その後に描き直しても完了の処理を呼ばない")
    func discardedInBackground() async throws {
        let (viewModel, events, _) = try await startTimer()

        viewModel.discardedInBackground()
        h.clock.advance(by: 300)
        viewModel.tick()
        await viewModel.pendingWork?.value

        #expect(viewModel.phase == .terminated)
        #expect(events.completions.isEmpty)
        #expect(events.displayEndedCount == 0)
        #expect(events.abortedCount == 0)
        #expect(h.sessions.allSessions().isEmpty)
        #expect(h.feedback.playCompletionCount == 0)
    }

    @Test("完了した後は、中断の操作を受け付けない")
    func noAbortAfterCompletion() async throws {
        let (viewModel, events, _) = try await startTimer()
        h.clock.advance(by: 120)
        viewModel.tick()
        await h.sleeper.waitUntilSleeping()

        viewModel.dragEnded(startY: 400, translationY: 200, safeAreaTop: safeAreaTop)
        viewModel.escape()

        #expect(events.abortedCount == 0)
        #expect(h.sessions.allSessions().count == 1)
    }
}
