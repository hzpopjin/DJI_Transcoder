import Foundation
import Testing
@testable import Pocket_Helper

struct AutomaticScanPolicyTests {
    @Test func firstAutomaticScanIsAllowed() {
        #expect(ProcessingCoordinator.shouldPerformAutomaticScan(lastScan: nil, now: .now))
    }

    @Test func repeatedScanInsideCooldownIsRejected() {
        let now = Date()
        #expect(!ProcessingCoordinator.shouldPerformAutomaticScan(lastScan: now.addingTimeInterval(-10), now: now))
    }

    @Test func scanAfterCooldownIsAllowed() {
        let now = Date()
        #expect(ProcessingCoordinator.shouldPerformAutomaticScan(
            lastScan: now.addingTimeInterval(-ProcessingCoordinator.automaticScanCooldown),
            now: now
        ))
    }

    @Test func firstDetectionStartsAtBeginningOfToday() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_787_310_000)

        #expect(ProcessingCoordinator.automaticScanStartDate(
            lastDetection: nil,
            now: now,
            calendar: calendar
        ) == calendar.startOfDay(for: now))
    }

    @Test func laterDetectionStartsAtPersistedCheckpoint() {
        let previousDetection = Date(timeIntervalSince1970: 1_787_300_000)

        #expect(ProcessingCoordinator.automaticScanStartDate(
            lastDetection: previousDetection,
            now: Date(timeIntervalSince1970: 1_787_310_000)
        ) == previousDetection)
    }
}
