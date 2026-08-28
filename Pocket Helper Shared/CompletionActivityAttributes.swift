import ActivityKit
import Foundation

nonisolated struct CompletionActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let completedCount: Int
        let failedCount: Int
        let completedAt: Date
    }

    let batchIdentifier: String
}
