import PhotosUI
import SwiftUI
import XCTest
@testable import Pocket_Helper

@MainActor
final class PickerAssetResolutionTests: XCTestCase {
    func testPickerItemWithPhotoLibraryIdentifierUsesDirectPath() async {
        let item = PhotosPickerItem(itemIdentifier: "test-photo-library-identifier")
        let resolution = await PhotoLibraryService().resolvePickerItems([item])

        XCTAssertEqual(resolution.identifiers, ["test-photo-library-identifier"])
        XCTAssertEqual(resolution.unresolvedCount, 0)
    }
}
