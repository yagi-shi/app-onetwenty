import Foundation
import Observation

/// ホーム画面の 1 つの習慣の表示内容。
struct HabitRow: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// 連続日数の表示。0 日のときは何も出さないので `nil`。
    let streakText: String?
    let isCompleted: Bool
    let accessibilityLabel: String
    /// 押せるかどうか。完了済みの習慣は押せない。
    var isButton: Bool { !isCompleted }
}

@Observable
final class HomeViewModel {
    private(set) var rows: [HabitRow] = []
    /// まだ使っていない枠の数（「＋」の数）。
    private(set) var placeholderCount = HabitSlotPolicy.maxActiveHabits
    /// 習慣が 1 件もないときだけ、「＋」の下に案内を出す。
    private(set) var showsAddLabel = true
    private(set) var allCompleted = false

    @ObservationIgnored var onStartTimer: ((RunningSessionMarker) -> Void)?
    @ObservationIgnored var onAddHabit: (() -> Void)?

    @ObservationIgnored private let habits: HabitRepository
    @ObservationIgnored private let sessions: SessionRepository
    @ObservationIgnored private let sessionService: SessionService
    @ObservationIgnored private let clock: WallClock
    @ObservationIgnored private var displayDay: DayKey?

    init(habits: HabitRepository, sessions: SessionRepository, sessionService: SessionService, clock: WallClock) {
        self.habits = habits
        self.sessions = sessions
        self.sessionService = sessionService
        self.clock = clock
    }

    /// 表示する日が変わったとき、データが変わったときに呼ぶ。
    func reload(displayDay: DayKey) {
        self.displayDay = displayDay
        let calendar = clock.calendar
        let activeHabits = habits.activeHabits()
        let allSessions = sessions.allSessions()
        // 保存待ち（走り切ったが保存に失敗した実行）も、完了として数える
        let status = DailyStatusResolver.status(
            activeHabits: activeHabits,
            sessions: allSessions,
            pending: sessionService.pendingCompletions(),
            day: displayDay,
            calendar: calendar
        )

        let sessionDaysByHabit = Dictionary(grouping: allSessions, by: \.habitID)
            .mapValues { Set($0.map { DayKey($0.startedAt, calendar: calendar) }) }

        rows = activeHabits.map { habit in
            let streak = StreakCalculator.habitStreak(
                sessionDays: sessionDaysByHabit[habit.id] ?? [],
                createdDay: DayKey(habit.createdAt, calendar: calendar),
                today: displayDay,
                calendar: calendar
            )
            let isCompleted = status.completedHabitIDs.contains(habit.id)
            return HabitRow(
                id: habit.id,
                title: habit.title,
                streakText: streak > 0 ? HomeText.streak(streak) : nil,
                isCompleted: isCompleted,
                accessibilityLabel: HomeText.accessibilityLabel(title: habit.title, streak: streak, isCompleted: isCompleted)
            )
        }
        placeholderCount = max(0, HabitSlotPolicy.maxActiveHabits - activeHabits.count)
        showsAddLabel = activeHabits.isEmpty
        allCompleted = status.allCompleted
    }

    /// 習慣をタップした。未完了なら、確認なしでタイマーを始める。
    func tap(habitID: UUID) async {
        guard let row = rows.first(where: { $0.id == habitID }), !row.isCompleted else { return }
        switch await sessionService.start(habitID: habitID) {
        case .started(let marker):
            onStartTimer?(marker)
        case .rejected:
            // 表示と実際の状態がずれていたので、表示を取り直す。エラーは出さない
            if let displayDay { reload(displayDay: displayDay) }
        }
    }

    func tapPlaceholder() {
        onAddHabit?()
    }
}

/// ホーム画面の文言。
enum HomeText {
    static func streak(_ days: Int) -> String {
        String(localized: "home.streak \(days)")
    }

    /// 「習慣名、連続N日、完了／未完了」の形。連続が 0 日なら連続日数は読み上げない。
    static func accessibilityLabel(title: String, streak: Int, isCompleted: Bool) -> String {
        var parts = [title]
        if streak > 0 {
            parts.append(String(localized: "home.row.accessibility.streak \(streak)"))
        }
        parts.append(isCompleted ? completed : notCompleted)
        return parts.joined(separator: String(localized: "common.listSeparator", defaultValue: ", "))
    }

    static var completed: String {
        String(localized: "home.row.accessibility.completed", defaultValue: "completed")
    }

    static var notCompleted: String {
        String(localized: "home.row.accessibility.notCompleted", defaultValue: "not completed")
    }
}
