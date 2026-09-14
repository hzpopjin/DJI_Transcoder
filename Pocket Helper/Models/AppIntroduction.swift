import Foundation

enum IntroductionDestination: String, Identifiable {
    case welcome
    case whatsNew

    var id: String { rawValue }

    static func automatic(hasCompletedGuide: Bool, lastSeenRelease: String, currentRelease: String) -> Self? {
        if !hasCompletedGuide { return .welcome }
        return lastSeenRelease == currentRelease ? nil : .whatsNew
    }
}

enum AppIntroduction {
    static let completedGuideKey = "PocketHelper.hasCompletedGuide"
    static let seenReleaseKey = "PocketHelper.lastSeenRelease"

    // Advance this together with the release notes; build-number changes don't show them again.
    static let releaseVersion = "1.0"

    static var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? releaseVersion
    }

    static var installedBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }
}
