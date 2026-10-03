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
    let environment: AppEnvironment
    let coordinator: AppCoordinator
    @State private var homeViewModel: HomeViewModel
    @State private var onboardingViewModel: OnboardingViewModel

    @Environment(\.scenePhase) private var scenePhase

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.environment = environment
        self.coordinator = coordinator
        _homeViewModel = State(initialValue: environment.makeHomeViewModel())
        _onboardingViewModel = State(initialValue: environment.makeOnboardingViewModel())
    }

    var body: some View {
        Group {
            switch coordinator.route {
            case .onboarding:
                OnboardingView(viewModel: onboardingViewModel)
            case .home:
                NavigationStack {
                    HomeView(viewModel: homeViewModel, coordinator: coordinator)
                        .navigationDestination(for: HomeView.Destination.self) { destination in
                            switch destination {
                            case .stats: StatsScreen(environment: environment, coordinator: coordinator)
                            case .settings: SettingsScreen(environment: environment, coordinator: coordinator)
                            }
                        }
                }
            }
        }
        // ウィザードも全画面で出す。設定から開いた場合も、閉じれば設定に戻る
        .fullScreenCover(item: presentedWizard) { wizard in
            WizardView(viewModel: wizard.viewModel)
        }
        .background {
            // タイマーは全画面で出し、その間ホームを覆う。
            // 完了の表示中にホームのリングを見せないという要件を、この出し方で満たしている
            Color.clear
                .fullScreenCover(item: presentedTimer) { timer in
                    TimerView(viewModel: timer)
                }
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

    private var presentedWizard: Binding<WizardPresentation?> {
        Binding(get: { coordinator.presentedWizard }, set: { _ in })
    }
}

/// 統計の画面。開くたびに ViewModel を作る。
private struct StatsScreen: View {
    let coordinator: AppCoordinator
    @State private var viewModel: StatsViewModel

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: environment.makeStatsViewModel())
    }

    var body: some View {
        StatsView(viewModel: viewModel, coordinator: coordinator)
    }
}

/// 設定の画面。開くたびに ViewModel を作る。
private struct SettingsScreen: View {
    let coordinator: AppCoordinator
    @State private var viewModel: SettingsViewModel

    init(environment: AppEnvironment, coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _viewModel = State(initialValue: environment.makeSettingsViewModel())
    }

    var body: some View {
        SettingsView(viewModel: viewModel, coordinator: coordinator)
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
        // 文字を大きくしていて画面に収まらないときは、スクロールで全文とボタンに届く
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    Text("storeUnavailable.message")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("storeUnavailable.retry") {
                        Task { await retry() }
                    }
                    .buttonStyle(.borderedProminent)
                    .prominentButtonLabel()
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
