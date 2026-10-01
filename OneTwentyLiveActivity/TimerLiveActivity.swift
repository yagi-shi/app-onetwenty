import ActivityKit
import SwiftUI
import WidgetKit

/// タイマー実行中の Live Activity。
/// いまは拡張をビルドできる最小の表示だけを置いている。見た目は T-61 で実装する。
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
                }
            } compactLeading: {
                EmptyView()
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...context.state.endsAt, countsDown: true)
            } minimal: {
                EmptyView()
            }
        }
    }
}
