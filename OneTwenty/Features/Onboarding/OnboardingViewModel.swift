import Foundation
import Observation

/// 初回起動時の 2 画面。読み飛ばされないよう、スキップは置かない。
@Observable
final class OnboardingViewModel {
    enum Page: Int {
        case first = 1
        case second = 2
    }

    private(set) var page: Page = .first

    @ObservationIgnored var onFinished: (() -> Void)?

    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func next() {
        page = .second
    }

    /// 1 画面目より前には戻れない。
    func back() {
        page = .first
    }

    /// 2 画面目まで読み終えた時点で、二度と表示しないよう記録する。
    func finish() {
        guard page == .second else { return }
        settings.onboardingCompleted = true
        onFinished?()
    }
}
