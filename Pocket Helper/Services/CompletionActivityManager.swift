import ActivityKit
import Foundation
import UIKit

@MainActor
final class CompletionActivityManager {
    static let shared = CompletionActivityManager()
    static let retentionDuration: TimeInterval = 120

    private init() {}

    func showCompletion(completedCount: Int, failedCount: Int) async {
        guard UIApplication.shared.applicationState != .active else {
            PocketLog.debug("App 位于前台，不展示完成实时活动")
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            PocketLog.warning("系统已关闭实时活动，无法展示完成状态")
            return
        }

        await dismissAll()
        let state = CompletionActivityAttributes.ContentState(
            completedCount: completedCount,
            failedCount: failedCount,
            completedAt: .now
        )
        let content = ActivityContent(state: state, staleDate: .now.addingTimeInterval(Self.retentionDuration))
        do {
            let activity = try Activity.request(
                attributes: CompletionActivityAttributes(batchIdentifier: UUID().uuidString),
                content: content,
                pushType: nil
            )
            await activity.end(
                content,
                dismissalPolicy: .after(.now.addingTimeInterval(Self.retentionDuration))
            )
            PocketLog.info("完成实时活动已展示，将保留 120 秒或等待用户移除")
        } catch {
            PocketLog.warning("完成实时活动启动失败：\(error.localizedDescription)")
        }
    }

    func dismissAll() async {
        let activities = Activity<CompletionActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        for activity in activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        PocketLog.info("App 已打开，清除完成实时活动，数量=\(activities.count)")
    }
}
