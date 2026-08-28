import XCTest
@testable import Pocket_Helper

@MainActor
final class CompletionActivityTests: XCTestCase {
    func testCompletionActivityRetentionIsTwoMinutes() {
        XCTAssertEqual(CompletionActivityManager.retentionDuration, 120)
    }

    func testCompletionContentKeepsSuccessAndFailureCounts() {
        let state = CompletionActivityAttributes.ContentState(
            completedCount: 3,
            failedCount: 1,
            completedAt: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(state.completedCount, 3)
        XCTAssertEqual(state.failedCount, 1)
    }
}
