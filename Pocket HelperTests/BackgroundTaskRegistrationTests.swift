import BackgroundTasks
import XCTest
@testable import Pocket_Helper

@MainActor
final class BackgroundTaskRegistrationTests: XCTestCase {
    @available(iOS 26.0, *)
    func testDynamicContinuedProcessingIdentifierCanRegisterAgainstWildcard() {
        let identifier = String(ProcessingCoordinator.backgroundTaskPattern.dropLast()) + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { task in
            task.expirationHandler = {}
            task.setTaskCompleted(success: true)
        }

        XCTAssertTrue(
            registered,
            "动态后台任务标识必须能匹配 Info.plist 中的通配标识"
        )
    }
}
