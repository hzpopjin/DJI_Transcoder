import Foundation
import XCTest
@testable import Pocket_Helper

@MainActor
final class AppSettingsDefaultsTests: XCTestCase {
    private static var retainedSettings: [AppSettings] = []

    func testAutomaticConversionDefaultsToOff() {
        XCTAssertFalse(AppSettings.defaultAutoConvert)
    }

    func testAutomaticDetectionDefaultsToVideos() {
        XCTAssertEqual(AppSettings.defaultAutoDetectionScope, .videos)
    }

    func testAutomaticDetectionScopeMatchesMediaKinds() {
        XCTAssertTrue(AutoDetectionScope.photos.includes(.photo))
        XCTAssertTrue(AutoDetectionScope.photos.includes(.livePhoto))
        XCTAssertFalse(AutoDetectionScope.photos.includes(.video))
        XCTAssertTrue(AutoDetectionScope.videos.includes(.video))
        XCTAssertFalse(AutoDetectionScope.videos.includes(.livePhoto))
        XCTAssertTrue(AutoDetectionScope.photosAndVideos.includes(.photo))
        XCTAssertTrue(AutoDetectionScope.photosAndVideos.includes(.video))
        XCTAssertTrue(AutoDetectionScope.photosAndVideos.includes(.livePhoto))
    }

    func testHistoryRecordsExcludeActiveQueueStates() {
        let activeStates: [ProcessingState] = [.queued, .downloading, .transcoding, .validating, .saving]
        let historyStates: [ProcessingState] = [.paused, .failed, .skipped, .completed, .readyToDelete]

        XCTAssertTrue(activeStates.allSatisfy { !$0.isHistoryRecord })
        XCTAssertTrue(historyStates.allSatisfy(\.isHistoryRecord))
    }

    func testLastAutomaticDetectionDatePersists() {
        let suiteName = "AppSettingsDefaultsTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("Unable to create isolated UserDefaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let expected = Date(timeIntervalSince1970: 1_787_300_000)
        let writer = AppSettings(defaults: defaults)
        let reader = AppSettings(defaults: defaults)
        Self.retainedSettings.append(contentsOf: [writer, reader])

        writer.lastAutomaticDetectionDate = expected

        XCTAssertEqual(reader.lastAutomaticDetectionDate, expected)
    }
}
