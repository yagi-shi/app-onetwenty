import SwiftUI

struct HomeView: View {
    let viewModel: HomeViewModel
    let coordinator: AppCoordinator

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Destination: Hashable {
        case stats
        case settings
    }

    /// 読み込み直すきっかけ。表示する日か、データのどちらかが変わったとき。
    private struct ReloadTrigger: Equatable {
        let day: DayKey
        let version: Int
    }

    private let ringDiameter: CGFloat = 72

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 32) {
                    slots
                    if viewModel.showsAddLabel {
                        Text("home.addHabit")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                    if viewModel.allCompleted {
                        Text("home.allCompleted")
                            .font(.body)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: Destination.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel(Text("home.settings"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: Destination.stats) {
                    Image(systemName: "chart.bar")
                }
                .accessibilityLabel(Text("home.stats"))
            }
        }
        .task(id: ReloadTrigger(day: coordinator.displayDay, version: coordinator.dataVersion)) {
            viewModel.reload(displayDay: coordinator.displayDay)
        }
    }

    /// 習慣と、空いている枠の「＋」。文字を大きくしているときは縦に並べる。
    @ViewBuilder
    private var slots: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(viewModel.rows) { row in
                    habit(row) {
                        HStack(alignment: .center, spacing: 16) {
                            ring(isCompleted: row.isCompleted)
                            VStack(alignment: .leading, spacing: 4) {
                                title(row.title, alignment: .leading)
                                if let streak = row.streakText {
                                    streakLabel(streak)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                ForEach(0..<viewModel.placeholderCount, id: \.self) { _ in
                    placeholder
                }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(viewModel.rows) { row in
                    habit(row) {
                        VStack(spacing: 12) {
                            ring(isCompleted: row.isCompleted)
                                .overlay(alignment: .topTrailing) {
                                    // リングのすぐ右に、並びを崩さずに置く。
                                    // 条件分岐で包むと位置の指定が効かなくなるので、常に 1 つの Text として置く
                                    streakLabel(row.streakText ?? "")
                                        .fixedSize()
                                        .alignmentGuide(.trailing) { $0[.leading] - 4 }
                                }
                            title(row.title, alignment: .center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                ForEach(0..<viewModel.placeholderCount, id: \.self) { _ in
                    placeholder
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// 未完了の習慣は押せるボタンにする。完了済みは押せないので、ボタンにしない。
    @ViewBuilder
    private func habit(_ row: HabitRow, @ViewBuilder content: () -> some View) -> some View {
        if row.isButton {
            Button {
                Task { await viewModel.tap(habitID: row.id) }
            } label: {
                content()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.accessibilityLabel)
        } else {
            content()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(row.accessibilityLabel)
        }
    }

    private func ring(isCompleted: Bool) -> some View {
        Circle()
            .fill(isCompleted ? Color.accentColor : .clear)
            .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            .frame(width: ringDiameter, height: ringDiameter)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: isCompleted)
    }

    private func title(_ text: String, alignment: TextAlignment) -> some View {
        Text(text)
            .font(.body)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func streakLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var placeholder: some View {
        Button {
            viewModel.tapPlaceholder()
        } label: {
            Image(systemName: "plus")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: ringDiameter, height: ringDiameter)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("home.addHabit"))
    }
}
