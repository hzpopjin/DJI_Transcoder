import XCTest
@testable import Pocket_Helper

@MainActor
final class AppIdentityTests: XCTestCase {
    func testChineseLanguageVariantsResolveToChineseName() throws {
        for language in ["zh", "zh-CN", "zh-SG", "zh-TW", "zh-HK", "zh-Hans", "zh-Hant"] {
            XCTAssertEqual(try localizedName(preference: language), "口袋相机助手", language)
        }
    }

    func testEnglishAndUnsupportedLanguagesUseEnglishName() throws {
        for language in ["en", "en-GB", "ja", "ko", "fr", "de", "ar"] {
            XCTAssertEqual(try localizedName(preference: language), "Pocket Helper", language)
        }
    }

    func testInAppNameMatchesSystemDisplayName() {
        XCTAssertEqual(AppIdentity.displayName, Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
        XCTAssertEqual(Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String, "Pocket Helper")
    }

    private func localizedName(preference: String) throws -> String {
        let localization = try XCTUnwrap(Bundle.preferredLocalizations(
            from: Bundle.main.localizations,
            forPreferences: [preference]
        ).first)
        let path = try XCTUnwrap(Bundle.main.path(forResource: localization, ofType: "lproj"))
        let bundle = try XCTUnwrap(Bundle(path: path))
        let name = bundle.localizedString(forKey: "CFBundleDisplayName", value: nil, table: "InfoPlist")
        // Verify the policy resource follows the same name without falling back to the other language.
        let policy = try XCTUnwrap(bundle.url(forResource: "PrivacyPolicy", withExtension: "html"))
        let html = try String(contentsOf: policy, encoding: .utf8)
        XCTAssertTrue(html.contains("适用于 \(name) 1.0"))
        return name
    }
}
