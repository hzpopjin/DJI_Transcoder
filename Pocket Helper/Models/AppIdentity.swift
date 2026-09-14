import Foundation

/// Use the same localized bundle name as the Home Screen and system permission sheets.
enum AppIdentity {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Pocket Helper"
    }
}
