import SwiftUI

struct RootView: View {
    let environment: AppEnvironment

    var body: some View {
        switch environment.rootState {
        case .storeUnavailable:
            StoreUnavailableView {
                await environment.retryContainer()
            }
        case .ready(let coordinator):
            CoordinatedRootView(environment: environment, coordinator: coordinator)
        }
    }
}

private struct CoordinatedRootView: View {
    let coordinator: AppCoordinator
    @State private var homeViewModel: HomeViewModel

    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _homeViewModel = State(initialValue: environment.makeHomeViewModel())
    }

    var body: some View {
        Group {
            switch coordinator.route {
            case .onboarding, .home:
                // オンボーディングの画面は T-46 で差し替える。それまではホームを出す
                NavigationStack {
                    HomeView(viewModel: homeViewModel, coordinator: coordinator)
                }
            }
        }
        // タイマーは全画面で出し、その間ホームを覆う。
        // 完了の表示中にホームのリングを見せないという要件を、この出し方で満たしている
        .fullScreenCover(item: presentedTimer) { timer in
            TimerView(viewModel: timer)
        }
        .preferredColorScheme(coordinator.theme.colorScheme)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            Task { await coordinator.activate() }
        }
        .task {
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                coordinator.dayDidChange()
            }
        }
    }

    /// 画面を閉じるのは `AppCoordinator` だけなので、ここからは書き換えない。
    private var presentedTimer: Binding<TimerViewModel?> {
        Binding(get: { coordinator.presentedTimer }, set: { _ in })
    }
}

private extension AppTheme {
    /// 「端末に合わせる」は `nil`。
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// データを保存する場所を開けなかったときの画面。空のデータを黙って見せると、履歴が消えたように見えてしまう。
private struct StoreUnavailableView: View {
    let retry: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("storeUnavailable.message")
                .font(.body)
                .multilineTextAlignment(.center)
            Button("storeUnavailable.retry") {
                Task { await retry() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
