import XCTest
@testable import Pocket_Helper

@MainActor
final class AppIntroductionTests: XCTestCase {
    func testFirstLaunchShowsGuideBeforeReleaseNotes() {
        XCTAssertEqual(destination(completed: false, seen: ""), .welcome)
    }

    func testCompletedCurrentReleaseGoesStraightToApp() {
        XCTAssertNil(destination(completed: true, seen: "1.0"))
    }

    func testNewReleaseShowsWhatsNewWithoutRepeatingGuide() {
        XCTAssertEqual(destination(completed: true, seen: "0.9"), .whatsNew)
    }

    func testUnfinishedGuideResumesEvenIfReleaseWasMarkedSeen() {
        XCTAssertEqual(destination(completed: false, seen: "1.0"), .welcome)
    }

    func testExistingGuideCompletionWithMissingReleaseShowsWhatsNew() {
        XCTAssertEqual(destination(completed: true, seen: ""), .whatsNew)
    }

    private func destination(completed: Bool, seen: String) -> IntroductionDestination? {
        IntroductionDestination.automatic(
            hasCompletedGuide: completed,
            lastSeenRelease: seen,
            currentRelease: "1.0"
        )
    }
}
