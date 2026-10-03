import SwiftUI

/// タイマー画面。閉じるボタンも戻るボタンも置かない。
/// 出る方法は、下へ引いて中断するか、2 分を走り切るかだけ。
struct TimerView: View {
    let viewModel: TimerViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// リングをこれより小さくはしない（最終的な値は実機での確認で決める）。
    private let minimumRingDiameter: CGFloat = 120
    private let ringLineWidth: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let diameter = max(minimumRingDiameter, min(proxy.size.width * 0.7, proxy.size.height * 0.45))
            VStack(spacing: 32) {
                TimelineView(.animation(paused: !isRunning)) { context in
                    ring(diameter: diameter)
                        .onChange(of: context.date) {
                            // 裏にいる間は完了させない。裏で 2 分たった場合は、戻ったときの復元が扱う
                            guard scenePhase == .active else { return }
                            viewModel.tick()
                        }
                }
                if case .completed(let message) = viewModel.phase {
                    Text(message)
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: viewModel.dragOffset)
            .opacity(viewModel.dragOpacity)
            // 中断を取り消して元の位置へ戻るときの動き。引いている間は指にそのまま追従させる
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: viewModel.dragOffset == 0)
            .contentShape(Rectangle())
            .gesture(abortGesture(safeAreaTop: proxy.safeAreaInsets.top))
        }
        .background(Color(.systemBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAction(.escape) {
            viewModel.escape()
        }
    }

    private var isRunning: Bool {
        if case .running = viewModel.phase { return true }
        return false
    }

    private func ring(diameter: CGFloat) -> some View {
        let progress = viewModel.progress
        return ZStack {
            Circle()
                .stroke(Color.accentColor.opacity(0.2), lineWidth: ringLineWidth)
            Circle()
                .trim(from: 0, to: progress?.fraction ?? 1)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let progress {
                Text(verbatim: "\(Int(progress.remaining.rounded(.up)))")
                    .font(.largeTitle.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, ringLineWidth * 3)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    private func abortGesture(safeAreaTop: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                viewModel.dragChanged(
                    startY: value.startLocation.y,
                    translationY: value.translation.height,
                    safeAreaTop: safeAreaTop
                )
            }
            .onEnded { value in
                viewModel.dragEnded(
                    startY: value.startLocation.y,
                    translationY: value.translation.height,
                    safeAreaTop: safeAreaTop
                )
            }
    }

    /// 毎秒読み上げると読み上げが終わらないので、残り時間は 10 秒きざみで伝える。
    private var accessibilityLabel: String {
        switch viewModel.phase {
        case .running:
            let remaining = viewModel.progress?.remaining ?? 0
            let rounded = Int((remaining / 10).rounded(.up)) * 10
            return String(localized: "timer.remaining \(rounded)")
        case .completed(let message):
            return message
        case .terminated:
            return ""
        }
    }
}
