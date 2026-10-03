import ActivityKit
import SwiftUI
import WidgetKit

/// タイマー実行中の Live Activity。アプリが止まっていても、残り時間は OS が 0 まで進める。
/// ロック画面に出るので、習慣名は出さない。
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            // ロック画面（Dynamic Island のない機種では、これだけで成り立つ）
            HStack(spacing: 16) {
                Image(systemName: context.isStale ? "checkmark.circle.fill" : "timer")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    RemainingTime(context: context)
                        .font(.title.monospacedDigit())
                    TimerProgress(context: context)
                }
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    RemainingTime(context: context)
                        .font(.title.monospacedDigit())
                }
                DynamicIslandExpandedRegion(.bottom) {
                    TimerProgress(context: context)
                        .padding(.horizontal)
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            } compactTrailing: {
                RemainingTime(context: context)
                    .monospacedDigit()
                    .frame(maxWidth: 52)
            } minimal: {
                Image(systemName: context.isStale ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

/// 残り時間。終了時刻を過ぎたら、残り時間の代わりに終わったことを出す。
private struct RemainingTime: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        if context.isStale {
            Text(context.attributes.endedLabel)
        } else {
            Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                .multilineTextAlignment(.center)
        }
    }
}

private struct TimerProgress: View {
    let context: ActivityViewContext<TimerActivityAttributes>

    var body: some View {
        if context.isStale {
            ProgressView(value: 1)
                .tint(Color.accentColor)
        } else {
            ProgressView(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(Color.accentColor)
        }
    }
}
