import CoreGraphics
import Foundation
import Observation

/// タイマーが完了したことの通知。フォアグラウンドでの完了と、裏で完了していた場合の両方で同じものを使う。
struct TimerCompletion: Equatable {
    let habitID: UUID
    let attributedDay: DayKey
    /// 画面に表示する完了文言。
    let message: String
    /// 完了記録を保存できたか。
    let saved: Bool
}

/// タイマー画面の状態。画面を閉じるのはこの型ではなく、提示している側（`AppCoordinator`）。
@Observable
final class TimerViewModel: Identifiable {
    enum Phase: Equatable {
        case running(RunningSessionMarker)
        case completed(message: String)
        /// 中断した、または実行が無効になった。画面が閉じられるのを待っている。
        case terminated
    }

    /// 中断が確定する下方向のドラッグ量。
    static let abortThreshold: CGFloat = 120
    /// 通知センターを引き出す操作と区別するため、画面上端からこの範囲で始めたドラッグには反応しない。
    static let ignoredTopInset: CGFloat = 80
    /// 完了文言を表示しておく時間。
    static let completionDisplayDuration: Duration = .milliseconds(2_500)

    private(set) var phase: Phase
    /// 中断ジェスチャで下へ引いている量（0 以上）。
    private(set) var dragOffset: CGFloat = 0

    @ObservationIgnored var onCompleted: ((TimerCompletion) -> Void)?
    @ObservationIgnored var onCompletionDisplayEnded: (() async -> Void)?
    @ObservationIgnored var onAborted: (() -> Void)?

    /// 完了・中断の処理。テストが終わりを待てるように保持している。
    @ObservationIgnored private(set) var pendingWork: Task<Void, Never>?

    @ObservationIgnored private let sessionService: SessionService
    @ObservationIgnored private let clock: WallClock
    @ObservationIgnored private let messages: [String]
    @ObservationIgnored private let previousMessage: String?
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var rng: any RandomNumberGenerator
    @ObservationIgnored private var isCompleting = false

    /// - Parameter previousMessage: 直前に表示した完了文言。同じものを続けて出さないために受け取る。
    init(
        marker: RunningSessionMarker,
        sessionService: SessionService,
        clock: WallClock,
        messages: [String],
        previousMessage: String?,
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        phase = .running(marker)
        self.sessionService = sessionService
        self.clock = clock
        self.messages = messages
        self.previousMessage = previousMessage
        self.rng = rng
        self.sleep = sleep
    }

    /// 現在の進み具合。実行中でなければ `nil`。
    var progress: TimerProgress? {
        guard case .running(let marker) = phase else { return nil }
        return TimerEngine.progress(startedAt: marker.startedAt, now: clock.now)
    }

    /// 中断ジェスチャの進み具合に応じた不透明度。離せば中断されることを予告する。
    var dragOpacity: Double {
        1 - 0.6 * min(Double(dragOffset / Self.abortThreshold), 1)
    }

    // MARK: 描き直しのたびに呼ぶ

    /// 2 分たっていれば完了の処理を始める。何度呼んでも、完了の処理は 1 回しか走らない。
    func tick() {
        guard case .running = phase, !isCompleting, progress?.isFinished == true else { return }
        isCompleting = true
        pendingWork = Task {
            guard let result = await sessionService.completeInForeground() else { return }
            await showCompletion(habitID: result.habitID, attributedDay: result.attributedDay, saved: result.saved)
        }
    }

    // MARK: 中断

    /// - Parameter startY: ドラッグを始めた位置（画面全体の座標）。
    /// - Parameter translationY: 始めた位置からの縦の移動量。
    /// - Parameter safeAreaTop: セーフエリア上端の位置。
    func dragChanged(startY: CGFloat, translationY: CGFloat, safeAreaTop: CGFloat) {
        guard case .running = phase, isValidDragStart(startY, safeAreaTop: safeAreaTop) else { return }
        dragOffset = max(0, translationY)
    }

    func dragEnded(startY: CGFloat, translationY: CGFloat, safeAreaTop: CGFloat) {
        guard case .running = phase else { return }
        dragOffset = 0
        guard isValidDragStart(startY, safeAreaTop: safeAreaTop), translationY >= Self.abortThreshold else { return }
        abort()
    }

    /// VoiceOver のエスケープ操作。下方向のドラッグと同じ中断として扱う。
    func escape() {
        guard case .running = phase else { return }
        abort()
    }

    // MARK: アプリが裏にいた間に起きたこと

    /// 裏にいる間に 2 分たち、完了として記録された。音と振動は鳴らさず、完了文言だけを出す。
    func completedInBackground(habitID: UUID, attributedDay: DayKey) {
        guard case .running = phase else { return }
        isCompleting = true
        pendingWork = Task {
            await showCompletion(habitID: habitID, attributedDay: attributedDay, saved: true)
        }
    }

    /// 裏にいる間に実行が無効になった（開始から 24 時間以上たった、対象の習慣がなくなった）。
    func discardedInBackground() {
        phase = .terminated
    }

    // MARK: 内部

    private func isValidDragStart(_ startY: CGFloat, safeAreaTop: CGFloat) -> Bool {
        startY > safeAreaTop + Self.ignoredTopInset
    }

    private func abort() {
        phase = .terminated
        pendingWork = Task {
            await sessionService.abort()
            onAborted?()
        }
    }

    private func showCompletion(habitID: UUID, attributedDay: DayKey, saved: Bool) async {
        // 完了の通知は 1 回だけ。文言を選んでから、その文言を載せて送る
        let message = CompletionMessagePicker.pick(from: messages, excluding: previousMessage, using: &rng)
            ?? String(localized: "timer.completion.default", defaultValue: "Two minutes, done.")
        onCompleted?(TimerCompletion(habitID: habitID, attributedDay: attributedDay, message: message, saved: saved))
        phase = .completed(message: message)

        await sleep(Self.completionDisplayDuration)
        await onCompletionDisplayEnded?()
    }
}
