import XCTest
@testable import Pocket_Helper

final class VideoBitratePolicyTests: XCTestCase {
    func testBalancedThirtyFPSBaselines() {
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 3840, height: 2160, frameRate: 30), 16_000_000)
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 1920, height: 1080, frameRate: 30), 6_000_000)
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 1280, height: 720, frameRate: 30), 2_000_000)
    }

    func testHighFrameRateMultipliers() {
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 3840, height: 2160, frameRate: 60), 24_000_000)
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 3840, height: 2160, frameRate: 120), 32_000_000)
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 1920, height: 1080, frameRate: 60), 9_000_000)
        XCTAssertEqual(VideoBitratePolicy.targetBitrate(width: 1280, height: 720, frameRate: 120), 4_000_000)
    }

    func testQualityMultipliers() {
        XCTAssertEqual(
            VideoBitratePolicy.targetBitrate(width: 3840, height: 2160, frameRate: 30, quality: .spaceSaving),
            12_800_000
        )
        XCTAssertEqual(
            VideoBitratePolicy.targetBitrate(width: 3840, height: 2160, frameRate: 30, quality: .high),
            20_000_000
        )
    }

    func testOnly4KHighFrameRateProfilesRequireExperimentalConfirmation() {
        XCTAssertEqual(
            VideoEncodingProfile(width: 3840, height: 2160, frameRate: 59.94, targetBitrate: 24_000_000).experimentalFrameRate,
            60
        )
        XCTAssertEqual(
            VideoEncodingProfile(width: 3840, height: 2160, frameRate: 119.88, targetBitrate: 32_000_000).experimentalFrameRate,
            120
        )
        XCTAssertNil(
            VideoEncodingProfile(width: 1920, height: 1080, frameRate: 120, targetBitrate: 12_000_000).experimentalFrameRate
        )
    }
}
