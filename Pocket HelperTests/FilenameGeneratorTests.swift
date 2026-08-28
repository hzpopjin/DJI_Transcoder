import XCTest
@testable import Pocket_Helper

final class FilenameGeneratorTests: XCTestCase {
    func testOriginalSuffixRule() {
        let stem = FilenameGenerator.stem(
            originalFilename: "DJI_0001.MP4",
            kind: .video,
            rule: .originalWithSuffix,
            suffix: "_Compressed",
            template: "",
            counter: 1,
            date: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(stem, "DJI_0001_Compressed")
        XCTAssertEqual(FilenameGenerator.filenames(stem: stem, kind: .video).primary, "DJI_0001_Compressed.mov")
    }

    func testAutomaticCounterHasStableWidth() {
        let stem = FilenameGenerator.stem(
            originalFilename: "anything.jpg",
            kind: .photo,
            rule: .automaticCounter,
            suffix: "",
            template: "",
            counter: 42,
            date: .now
        )
        XCTAssertEqual(stem, "PH_000042")
    }

    func testCustomTemplateAndSanitization() {
        let date = Date(timeIntervalSince1970: 0)
        let stem = FilenameGenerator.stem(
            originalFilename: "DJI:clip.mp4",
            kind: .livePhoto,
            rule: .customTemplate,
            suffix: "",
            template: "{date}/{original}:{counter}_{media}",
            counter: 7,
            date: date
        )
        XCTAssertFalse(stem.contains("/"))
        XCTAssertFalse(stem.contains(":"))
        XCTAssertTrue(stem.hasSuffix("000007_livePhoto"))
    }

    func testLivePhotoComponentsShareStem() {
        let names = FilenameGenerator.filenames(stem: "DJI_0001_Compressed", kind: .livePhoto)
        XCTAssertEqual(names.primary, "DJI_0001_Compressed.HEIC")
        XCTAssertEqual(names.paired, "DJI_0001_Compressed.mov")
    }
}
