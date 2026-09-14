import Foundation
import SwiftData
import XCTest
@testable import Pocket_Helper

@MainActor
final class QueueResetTests: XCTestCase {
    // Keep observable services alive for the test host's lifetime, as in AppSettingsDefaultsTests.
    private static var retainedFixtures: [Fixture] = []

    func testKeepingOriginalsPersistsCompletionAndSurvivesQueueReset() throws {
        let fixture = try makeFixture()
        let ready = fixture.insert(.readyToDelete)
        ready.outputLocalIdentifier = "retained-output"
        ready.outputFilename = "converted.hevc.mov"
        ready.outputBytes = 400
        ready.progress = 1
        let completionDate = Date(timeIntervalSince1970: 1_700_000_000)
        ready.completedAt = completionDate
        let otherReady = fixture.insert(.readyToDelete)
        let waiting = fixture.insert(.queued)
        let failed = fixture.insert(.failed)
        let skipped = fixture.insert(.skipped)
        try fixture.context.save()
        fixture.coordinator.requestDeleteConfirmation()
        XCTAssertNotNil(fixture.coordinator.deleteConfirmationRequestID)

        fixture.coordinator.keepReadyOriginals()

        XCTAssertEqual(fixture.coordinator.readyToDeleteCount, 0)
        XCTAssertNil(fixture.coordinator.deleteConfirmationRequestID)
        XCTAssertEqual(otherReady.state, .completed)
        XCTAssertEqual(waiting.state, .queued)
        XCTAssertEqual(failed.state, .failed)
        XCTAssertEqual(skipped.state, .skipped)
        // A fresh context reads the persisted decision, with source/output identity intact.
        let reader = ModelContext(fixture.container)
        let records = try reader.fetch(FetchDescriptor<MediaJob>())
        let saved = try XCTUnwrap(records.first { $0.sourceLocalIdentifier == ready.sourceLocalIdentifier })
        XCTAssertEqual(saved.state, .completed)
        XCTAssertEqual(saved.outputLocalIdentifier, "retained-output")
        XCTAssertEqual(saved.outputFilename, "converted.hevc.mov")
        XCTAssertEqual(saved.outputBytes, 400)
        XCTAssertEqual(saved.progress, 1)
        XCTAssertEqual(saved.completedAt, completionDate)
        XCTAssertEqual(records.count, 5)

        fixture.coordinator.resetPendingJobs()
        fixture.coordinator.resetPendingJobs()
        XCTAssertEqual(ready.state, .completed)
        XCTAssertEqual(otherReady.state, .completed)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<MediaJob>()), 3)
        fixture.coordinator.requestDeleteConfirmation()
        XCTAssertNil(fixture.coordinator.deleteConfirmationRequestID)
    }

    func testKeepingOriginalsDoesNotDisablePromptsForFutureConversions() throws {
        let fixture = try makeFixture()
        let previous = fixture.insert(.readyToDelete)
        try fixture.context.save()
        fixture.coordinator.keepReadyOriginals()
        let savedDate = previous.updatedAt
        fixture.coordinator.keepReadyOriginals()
        XCTAssertEqual(previous.updatedAt, savedDate)

        let next = fixture.insert(.readyToDelete)
        try fixture.context.save()
        fixture.coordinator.requestDeleteConfirmation()
        XCTAssertEqual(fixture.coordinator.readyToDeleteCount, 1)
        XCTAssertNotNil(fixture.coordinator.deleteConfirmationRequestID)
        XCTAssertEqual(previous.state, .completed)
        XCTAssertEqual(next.state, .readyToDelete)
        XCTAssertTrue(fixture.coordinator.settings.deleteOriginals)
    }

    func testPausedOtherMediaResetsThenClearsWithoutRemovingFinishedHistory() throws {
        let fixture = try makeFixture()
        let paused = fixture.insert(.paused)
        paused.progress = 0.6
        paused.errorDetails = "已暂停"
        paused.completedAt = .now
        let waiting = fixture.insert(.queued)
        let failed = fixture.insert(.failed)
        let completed = fixture.insert(.completed)
        completed.outputLocalIdentifier = "saved-copy"
        let ready = fixture.insert(.readyToDelete)
        let skipped = fixture.insert(.skipped)
        let preserved = Set([completed, ready, skipped].map(\.sourceLocalIdentifier))
        try fixture.context.save()
        fixture.coordinator.pauseProcessing()

        XCTAssertFalse(fixture.coordinator.canClearPendingQueue)
        fixture.coordinator.resetPendingJobs()

        XCTAssertEqual(paused.state, .queued)
        XCTAssertEqual(waiting.state, .queued)
        XCTAssertEqual(failed.state, .queued)
        XCTAssertEqual(paused.progress, 0)
        XCTAssertNil(paused.errorDetails)
        XCTAssertNil(paused.completedAt)
        XCTAssertFalse(fixture.coordinator.isQueuePaused)
        XCTAssertTrue(fixture.coordinator.canClearPendingQueue)
        XCTAssertEqual(skipped.state, .skipped)

        fixture.coordinator.resetPendingJobs()

        let reader = ModelContext(fixture.container)
        XCTAssertEqual(Set(try reader.fetch(FetchDescriptor<MediaJob>()).map(\.sourceLocalIdentifier)), preserved)
        XCTAssertEqual(completed.outputLocalIdentifier, "saved-copy")
        XCTAssertFalse(fixture.coordinator.canClearPendingQueue)
        fixture.coordinator.resetPendingJobs()
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<MediaJob>()), 3)
    }

    func testClearingOnlyRemovesTemporaryFilesForQueuedJobs() throws {
        let fixture = try makeFixture()
        let queued = fixture.insert(.queued)
        let completed = fixture.insert(.completed)
        try fixture.context.save()
        let queuedDirectory = temporaryDirectory(queued.sourceLocalIdentifier)
        let completedDirectory = temporaryDirectory(completed.sourceLocalIdentifier)
        for directory in [queuedDirectory, completedDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("test-only".utf8).write(to: directory.appendingPathComponent("fixture.tmp"))
        }
        defer {
            try? FileManager.default.removeItem(at: queuedDirectory)
            try? FileManager.default.removeItem(at: completedDirectory)
        }

        XCTAssertTrue(fixture.coordinator.canClearPendingQueue)
        fixture.coordinator.resetPendingJobs()

        XCTAssertFalse(FileManager.default.fileExists(atPath: queuedDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: completedDirectory.path))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<MediaJob>()), 1)
    }

    func testResetCannotRemoveJobsBetweenTaskCreationAndProcessingStart() async throws {
        let fixture = try makeFixture()
        let queued = fixture.insert(.queued)
        try fixture.context.save()

        fixture.coordinator.startProcessingIfNeeded()
        // processQueue has not entered its actor turn yet: isProcessing is still false.
        XCTAssertFalse(fixture.coordinator.isProcessing)
        fixture.coordinator.resetPendingJobs()
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<MediaJob>()), 1)
        XCTAssertEqual(queued.state, .queued)
        fixture.coordinator.pauseProcessing()
        await Task.yield()
    }

    private func makeFixture() throws -> Fixture {
        let fixture = try Fixture()
        Self.retainedFixtures.append(fixture)
        return fixture
    }

    private func temporaryDirectory(_ identifier: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PocketHelper", isDirectory: true)
            .appendingPathComponent(FilenameGenerator.sanitize(identifier), isDirectory: true)
    }

    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let coordinator: ProcessingCoordinator

        init() throws {
            container = try ModelContainer(
                for: MediaJob.self, AppMessage.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            context = ModelContext(container)
            context.autosaveEnabled = false
            let defaults = UserDefaults(suiteName: "QueueResetTests.\(UUID().uuidString)")!
            coordinator = ProcessingCoordinator(
                settings: AppSettings(defaults: defaults),
                messageCenter: MessageCenter(),
                photoLibrary: PhotoLibraryService(),
                transcoder: MediaTranscoder()
            )
            coordinator.configure(context: context)
        }

        func insert(_ state: ProcessingState) -> MediaJob {
            let job = MediaJob(
                descriptor: MediaAssetDescriptor(
                    id: "queue-test-\(UUID().uuidString)",
                    kind: .video,
                    originalFilename: "OTHER_CAMERA.MOV",
                    creationDate: .now,
                    estimatedBytes: 1_000,
                    pixelWidth: 1920,
                    pixelHeight: 1080,
                    source: .other
                ),
                state: state
            )
            context.insert(job)
            return job
        }
    }
}
