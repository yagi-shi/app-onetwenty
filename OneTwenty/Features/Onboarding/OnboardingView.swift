import SwiftUI

struct OnboardingView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(title)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .padding(.top, 48)
            }

            // ボタンでだけ進む。左右のスワイプでの送りは置かない
            HStack {
                if viewModel.page == .second {
                    Button("onboarding.back") { viewModel.back() }
                }
                Spacer()
                switch viewModel.page {
                case .first:
                    Button("onboarding.next") { viewModel.next() }
                        .buttonStyle(.borderedProminent)
                case .second:
                    Button("onboarding.start") { viewModel.finish() }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private var title: String {
        switch viewModel.page {
        case .first: String(localized: "onboarding.page1.title")
        case .second: String(localized: "onboarding.page2.title")
        }
    }

    private var message: String {
        switch viewModel.page {
        case .first: String(localized: "onboarding.page1.message")
        case .second: String(localized: "onboarding.page2.message")
        }
    }
}
