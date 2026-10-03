import SwiftUI

/// 統計。ヒートマップ 1 枚と、全体の数値 3 つだけを置く。
struct StatsView: View {
    let viewModel: StatsViewModel
    let coordinator: AppCoordinator

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private struct ReloadTrigger: Equatable {
        let day: DayKey
        let version: Int
    }

    var body: some View {
        // 標準の文字サイズでは 1 画面に収まり、文字を大きくしたときだけスクロールする
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                heatmap
                VStack(spacing: 16) {
                    figure(String(localized: "stats.current"), value: String(localized: "stats.days \(viewModel.currentStreak)"))
                    figure(String(localized: "stats.longest"), value: String(localized: "stats.days \(viewModel.longestStreak)"))
                    figure(String(localized: "stats.total"), value: String(localized: "stats.times \(viewModel.totalCompletions)"))
                }
            }
            .padding()
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle(Text("stats.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: ReloadTrigger(day: coordinator.displayDay, version: coordinator.dataVersion)) {
            viewModel.reload(displayDay: coordinator.displayDay)
        }
    }

    /// セルは押しても何も起きない。読み上げはヒートマップ全体で 1 つにまとめる。
    private var heatmap: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            ForEach(0..<StatsViewModel.rowCount, id: \.self) { row in
                GridRow {
                    ForEach(0..<viewModel.columns.count, id: \.self) { column in
                        cell(viewModel.columns[column][row])
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("stats.heatmap.accessibility \(viewModel.completedDayCount)"))
    }

    @ViewBuilder
    private func cell(_ cell: HeatmapCell?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3)
        Group {
            if let cell {
                switch cell.ratio {
                case nil:
                    // その日に有効な習慣がない日は空欄。輪郭だけを描く
                    shape.strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                case 0:
                    shape.fill(Color(.systemFill))
                case let ratio?:
                    shape.fill(Color.accentColor.opacity(0.25 + 0.75 * ratio))
                }
            } else {
                // 84 日に入らない位置は何も描かない
                Color.clear
            }
        }
        .frame(width: 18, height: 18)
    }

    /// 見出しと値。文字を大きくしているときは、見出しが折れないよう値をその下に置く。
    private func figure(_ title: String, value: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(title)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }
            Text(value)
                .font(.title2.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
