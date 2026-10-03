import Testing
@testable import OneTwenty

@MainActor
struct OnboardingViewModelTests {
    private let isolated = IsolatedDefaults()
    private var settings: UserDefaultsSettingsStore { UserDefaultsSettingsStore(defaults: isolated.defaults) }

    @Test("1 画面目から始まり、1 画面目より前には戻れない")
    func startsOnFirstPage() {
        let viewModel = OnboardingViewModel(settings: settings)

        #expect(viewModel.page == .first)
        viewModel.back()
        #expect(viewModel.page == .first)
    }

    @Test("1 画面目からは完了できない（読み飛ばしはできない）")
    func cannotFinishFromFirstPage() {
        let viewModel = OnboardingViewModel(settings: settings)
        var finishedCount = 0
        viewModel.onFinished = { finishedCount += 1 }

        viewModel.finish()

        #expect(finishedCount == 0)
        #expect(!settings.onboardingCompleted)
    }

    @Test("2 画面目から 1 画面目に戻れる")
    func canGoBackFromSecondPage() {
        let viewModel = OnboardingViewModel(settings: settings)

        viewModel.next()
        #expect(viewModel.page == .second)
        viewModel.back()
        #expect(viewModel.page == .first)
    }

    @Test("「はじめる」を押すまでは、見終えた記録を残さない")
    func flagIsNotSetBeforeFinish() {
        let viewModel = OnboardingViewModel(settings: settings)

        viewModel.next()

        #expect(!settings.onboardingCompleted)
    }

    @Test("2 画面目で「はじめる」を押すと、見終えたことを記録し、終わりを知らせる")
    func finish() {
        let viewModel = OnboardingViewModel(settings: settings)
        var finishedCount = 0
        viewModel.onFinished = { finishedCount += 1 }

        viewModel.next()
        viewModel.finish()

        #expect(settings.onboardingCompleted)
        #expect(finishedCount == 1)
    }
}
