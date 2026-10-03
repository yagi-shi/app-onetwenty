import Foundation
import os

enum StartRejection: Equatable, Sendable {
    /// その習慣は今日すでに完了している（保存待ちを含む）。
    case alreadyCompletedToday
    /// 別のタイマーが実行中。
    case alreadyRunning
    /// 習慣が存在しないか、アーカイブ済み。
    case habitNotActive
}

enum StartResult: Equatable, Sendable {
    case started(RunningSessionMarker)
    case rejected(StartRejection)
}

struct CompletionResult: Equatable, Sendable {
    let habitID: UUID
    /// 記録が属する日。完了した日ではなく、開始した日。
    let attributedDay: DayKey
    /// 完了記録を保存できたか。`false` なら保存待ちに回っている。
    let saved: Bool
}

enum RecoveryOutcome: Equatable, Sendable {
    case none
    /// アプリが裏にいる間に 2 分を走り切っていたので、完了として記録した。
    case completed(habitID: UUID, attributedDay: DayKey)
    case discarded
}

/// タイマーの開始・完了・中断と、アプリがアクティブになったときの復元。
/// 実行中かどうかは `RunningSessionStore` の印だけで判断し、この型は状態を持たない。
final class SessionService {
    /// 終了時刻からこの時間以内に完了を確かめた場合だけ、その場で走り切ったとみなして音と振動を鳴らす。
    /// 画面を開いている間は毎フレーム確かめるので遅れはごくわずか。これを超えて遅れたなら、
    /// アプリは裏にいて、戻ってきたところで完了に気づいたことになる。
    static let liveCompletionWindow: TimeInterval = 1

    private let sessions: SessionRepository
    private let habits: HabitRepository
    private let store: RunningSessionStore
    private let notifications: NotificationClient
    private let liveActivity: LiveActivityClient
    private let feedback: FeedbackPlayer
    private let reminders: ReminderService
    private let clock: WallClock

    /// 通知の許可を求めている最中の処理。タイマーの開始はこれを待たない。
    private(set) var authorizationRequest: Task<Void, Never>?

    init(
        sessions: SessionRepository,
        habits: HabitRepository,
        store: RunningSessionStore,
        notifications: NotificationClient,
        liveActivity: LiveActivityClient,
        feedback: FeedbackPlayer,
        reminders: ReminderService,
        clock: WallClock
    ) {
        self.sessions = sessions
        self.habits = habits
        self.store = store
        self.notifications = notifications
        self.liveActivity = liveActivity
        self.feedback = feedback
        self.reminders = reminders
        self.clock = clock
    }

    // MARK: 開始

    func start(habitID: UUID) async -> StartResult {
        await flushPendingCompletion()

        // ここから印を保存するまでは途中で中断しない（二重タップで 2 つ始まらないようにする）
        guard isActive(habitID: habitID) else { return .rejected(.habitNotActive) }
        guard !isCompletedToday(habitID: habitID) else { return .rejected(.alreadyCompletedToday) }
        guard store.load() == nil else { return .rejected(.alreadyRunning) }

        let marker = RunningSessionMarker(sessionID: UUID(), habitID: habitID, startedAt: clock.now)
        store.save(marker)
        feedback.prepare()

        let endsAt = TimerEngine.progress(startedAt: marker.startedAt, now: marker.startedAt).endsAt
        do {
            try await liveActivity.start(sessionID: marker.sessionID, startedAt: marker.startedAt, endsAt: endsAt)
        } catch {
            // Live Activity がなくてもタイマーは動く。裏での完了は通知が伝える
            Log.session.error("Live Activity を開始できない: \(error)")
        }

        switch await notifications.authorizationStatus() {
        case .authorized:
            await scheduleTimerNotification(for: marker, endsAt: endsAt)
        case .notDetermined:
            requestAuthorizationInBackground()
        case .denied:
            break
        }
        return .started(marker)
    }

    // MARK: 完了・中断

    /// 実行中のタイマーが 2 分を走り切っていれば、完了として記録し、音と振動を鳴らす。
    /// 終了時刻から大きく遅れて気づいた場合（裏から戻ってきた直後など）は、音と振動を鳴らさない。
    /// - Returns: 完了すべきものがなければ `nil`。保存に失敗した場合も `nil` にはならない。
    func completeInForeground() async -> CompletionResult? {
        guard let marker = store.load() else { return nil }
        let progress = TimerEngine.progress(startedAt: marker.startedAt, now: clock.now)
        guard progress.isFinished else { return nil }
        let isLive = clock.now.timeIntervalSince(progress.endsAt) < Self.liveCompletionWindow
        guard isActive(habitID: marker.habitID) else {
            await discard(marker)
            return nil
        }

        var saved = record(marker)
        clearRunning(marker)
        if isLive {
            feedback.playCompletion()
        }

        await liveActivity.end(sessionID: marker.sessionID)
        var synced = false
        if !saved {
            // 保存に失敗した直後に、1 回だけやり直す
            synced = await flushPendingCompletion()
            saved = !store.pendingCompletions().contains { $0.sessionID == marker.sessionID }
        }
        if !synced {
            // 保存待ちのままでも今日の完了として数えるので、リマインダーはここで合わせる
            await reminders.sync()
        }
        return CompletionResult(habitID: marker.habitID, attributedDay: day(of: marker), saved: saved)
    }

    /// 実行中のタイマーを中断する。記録は残さない。
    func abort() async {
        guard let marker = store.load() else { return }
        await discard(marker)
    }

    // MARK: 復元

    /// アプリがアクティブになるたびに呼ぶ。実行中だったタイマーの扱いを決めて実行し、
    /// 不要になった Live Activity を終了させる。
    func recoverOnActivation(launch: LaunchKind) async -> RecoveryOutcome {
        let now = clock.now
        let decision = SessionRecoveryResolver.resolve(
            marker: store.load(),
            activities: liveActivity.currentActivities(),
            now: now,
            launch: launch
        )

        let outcome: RecoveryOutcome
        switch decision.markerAction {
        case .none, .keepRunning:
            outcome = .none
        case .complete(let marker) where isActive(habitID: marker.habitID):
            _ = record(marker)
            clearRunning(marker)
            outcome = .completed(habitID: marker.habitID, attributedDay: day(of: marker))
        case .complete(let marker), .discard(let marker):
            clearRunning(marker)
            outcome = .discarded
        }

        // 保存待ちのまま 1 日たった実行は、過去の日にさかのぼって書き込むことになるので捨てる
        for pending in store.pendingCompletions()
        where now >= pending.startedAt.addingTimeInterval(SessionRecoveryResolver.discardAfter) {
            store.removePending(sessionID: pending.sessionID)
        }
        let flushed = await flushPendingCompletion()
        if case .completed = outcome, !flushed {
            await reminders.sync()
        }

        await liveActivity.end(activityIDs: decision.activitiesToEnd)
        return outcome
    }

    // MARK: 保存待ち

    func pendingCompletions() -> [RunningSessionMarker] {
        store.pendingCompletions()
    }

    /// 保存待ちになっている実行の保存をやり直す。
    /// - Returns: 1 件以上保存できたら `true`。
    @discardableResult
    func flushPendingCompletion() async -> Bool {
        var savedAny = false
        for marker in store.pendingCompletions() {
            guard isActive(habitID: marker.habitID) else {
                store.removePending(sessionID: marker.sessionID)
                continue
            }
            do {
                try insert(marker)
                store.removePending(sessionID: marker.sessionID)
                savedAny = true
            } catch {
                Log.session.error("保存待ちの完了記録を保存できない（次の機会にやり直す）: \(error)")
            }
        }
        if savedAny {
            await reminders.sync()
        }
        return savedAny
    }

    // MARK: 内部

    /// 完了記録を保存する。失敗したら保存待ちに回す。
    /// - Returns: 保存できたら `true`。
    private func record(_ marker: RunningSessionMarker) -> Bool {
        do {
            try insert(marker)
            return true
        } catch {
            Log.session.error("完了記録を保存できないため、保存待ちに回す: \(error)")
            store.addPending(marker)
            return false
        }
    }

    /// 同じ実行を何度保存しても 1 件にしかならない（id は実行の識別子をそのまま使う）。
    private func insert(_ marker: RunningSessionMarker) throws {
        let calendar = clock.calendar
        let day = day(of: marker)
        let session = SessionSnapshot(
            id: marker.sessionID,
            habitID: marker.habitID,
            startedAt: marker.startedAt,
            completedAt: marker.startedAt.addingTimeInterval(TimerEngine.duration)
        )
        _ = try sessions.insertIfAbsent(
            session,
            sameDayRange: day.startOfDay(calendar: calendar)
                ..< day.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
        )
    }

    /// 実行中の印と、その実行の完了通知を消す。
    private func clearRunning(_ marker: RunningSessionMarker) {
        store.clear()
        notifications.remove(identifiers: [NotificationIdentifier.timer(sessionID: marker.sessionID)])
    }

    private func discard(_ marker: RunningSessionMarker) async {
        clearRunning(marker)
        await liveActivity.end(sessionID: marker.sessionID)
    }

    private func day(of marker: RunningSessionMarker) -> DayKey {
        DayKey(marker.startedAt, calendar: clock.calendar)
    }

    private func isActive(habitID: UUID) -> Bool {
        guard let habit = habits.habit(id: habitID) else { return false }
        return habit.archivedAt == nil
    }

    /// 画面に表示している日ではなく、実際の現在の日で判定する。
    private func isCompletedToday(habitID: UUID) -> Bool {
        let calendar = clock.calendar
        let today = DayKey(clock.now, calendar: calendar)
        let todaySessions = sessions.sessions(
            from: today.startOfDay(calendar: calendar),
            to: today.adding(days: 1, calendar: calendar).startOfDay(calendar: calendar)
        )
        return DailyStatusResolver.status(
            activeHabits: habits.activeHabits(),
            sessions: todaySessions,
            pending: store.pendingCompletions(),
            day: today,
            calendar: calendar
        ).completedHabitIDs.contains(habitID)
    }

    private func scheduleTimerNotification(for marker: RunningSessionMarker, endsAt: Date) async {
        do {
            try await notifications.add(LocalNotificationRequest(
                identifier: NotificationIdentifier.timer(sessionID: marker.sessionID),
                body: NotificationText.timerBody,
                trigger: .date(endsAt)
            ))
        } catch {
            Log.session.error("完了通知を予約できない: \(error)")
        }
    }

    /// 許可のダイアログに答えるのを待たずにタイマーを進める。
    /// 許可された時点で実行中のタイマーがあれば、その完了通知を予約する
    /// （答えるまでの間に中断していれば予約しない）。
    private func requestAuthorizationInBackground() {
        guard authorizationRequest == nil else { return }
        authorizationRequest = Task { [weak self] in
            guard let self else { return }
            let result = await notifications.requestAuthorization()
            if result == .authorized, let running = store.load() {
                let endsAt = running.startedAt.addingTimeInterval(TimerEngine.duration)
                await scheduleTimerNotification(for: running, endsAt: endsAt)
            }
            await reminders.sync()
            authorizationRequest = nil
        }
    }
}
