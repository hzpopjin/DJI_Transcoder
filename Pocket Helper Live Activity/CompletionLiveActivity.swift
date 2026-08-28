import ActivityKit
import SwiftUI
import WidgetKit

struct CompletionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CompletionActivityAttributes.self) { context in
            HStack(spacing: 14) {
                completionSymbol(failedCount: context.state.failedCount)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(context.state.failedCount == 0 ? "压缩完成" : "转换已结束")
                        .font(.headline)
                    Text(summary(for: context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding()
            .activityBackgroundTint(Color(.secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
            .widgetURL(URL(string: "pockethelper://completion"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    completionSymbol(failedCount: context.state.failedCount)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.state.failedCount == 0 ? "压缩完成" : "转换已结束")
                            .font(.headline)
                        Text(summary(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                completionSymbol(failedCount: context.state.failedCount)
            } compactTrailing: {
                Text("\(context.state.completedCount)")
                    .font(.caption.monospacedDigit())
            } minimal: {
                completionSymbol(failedCount: context.state.failedCount)
            }
            .widgetURL(URL(string: "pockethelper://completion"))
            .keylineTint(context.state.failedCount == 0 ? .green : .orange)
        }
    }

    @ViewBuilder
    private func completionSymbol(failedCount: Int) -> some View {
        Image(systemName: failedCount == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .foregroundStyle(failedCount == 0 ? .green : .orange)
            .accessibilityLabel(failedCount == 0 ? "完成" : "有失败项目")
    }

    private func summary(for state: CompletionActivityAttributes.ContentState) -> String {
        if state.failedCount > 0 {
            return "完成 \(state.completedCount) 个，失败 \(state.failedCount) 个"
        }
        return "已保存 \(state.completedCount) 个项目"
    }
}
