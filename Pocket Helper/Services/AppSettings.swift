import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let defaultAutoConvert = false
    static let defaultAutoDetectionScope: AutoDetectionScope = .videos
    private enum Key {
        static let videoQuality = "videoQuality"
        static let photoQuality = "photoQuality"
        static let liveResolution = "liveResolution"
        static let filenameRule = "filenameRule"
        static let filenameSuffix = "filenameSuffix"
        static let filenameTemplate = "filenameTemplate"
        static let deleteOriginals = "deleteOriginals"
        static let autoConvert = "autoConvert"
        static let autoDetectionScope = "autoDetectionScope"
        static let automaticCounter = "automaticCounter"
        static let completedInitialScan = "completedInitialScan"
        static let lastAutomaticDetectionDate = "lastAutomaticDetectionDate"
        static let automaticScanSeenAssetIdentifiers = "automaticScanSeenAssetIdentifiers"
        static let automaticScanBaselineEstablished = "automaticScanBaselineEstablished"
    }

    private let defaults: UserDefaults

    @Published var videoQuality: VideoQuality { didSet { defaults.set(videoQuality.rawValue, forKey: Key.videoQuality) } }
    @Published var photoQuality: PhotoQuality { didSet { defaults.set(photoQuality.rawValue, forKey: Key.photoQuality) } }
    @Published var liveResolution: LiveMotionResolution { didSet { defaults.set(liveResolution.rawValue, forKey: Key.liveResolution) } }
    @Published var filenameRule: FilenameRule { didSet { defaults.set(filenameRule.rawValue, forKey: Key.filenameRule) } }
    @Published var filenameSuffix: String { didSet { defaults.set(filenameSuffix, forKey: Key.filenameSuffix) } }
    @Published var filenameTemplate: String { didSet { defaults.set(filenameTemplate, forKey: Key.filenameTemplate) } }
    @Published var deleteOriginals: Bool { didSet { defaults.set(deleteOriginals, forKey: Key.deleteOriginals) } }
    @Published var autoConvert: Bool { didSet { defaults.set(autoConvert, forKey: Key.autoConvert) } }
    @Published var autoDetectionScope: AutoDetectionScope { didSet { defaults.set(autoDetectionScope.rawValue, forKey: Key.autoDetectionScope) } }

    var automaticCounter: Int {
        get { max(1, defaults.integer(forKey: Key.automaticCounter)) }
        set { defaults.set(max(1, newValue), forKey: Key.automaticCounter) }
    }

    var completedInitialScan: Bool {
        get { defaults.bool(forKey: Key.completedInitialScan) }
        set { defaults.set(newValue, forKey: Key.completedInitialScan) }
    }

    var lastAutomaticDetectionDate: Date? {
        get { defaults.object(forKey: Key.lastAutomaticDetectionDate) as? Date }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.lastAutomaticDetectionDate)
            } else {
                defaults.removeObject(forKey: Key.lastAutomaticDetectionDate)
            }
        }
    }

    var automaticScanSeenAssetIdentifiers: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.automaticScanSeenAssetIdentifiers) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.automaticScanSeenAssetIdentifiers) }
    }

    var automaticScanBaselineEstablished: Bool {
        get { defaults.bool(forKey: Key.automaticScanBaselineEstablished) }
        set { defaults.set(newValue, forKey: Key.automaticScanBaselineEstablished) }
    }

    var automaticScanCheckpoint: AutomaticScanCheckpoint {
        get {
            AutomaticScanCheckpoint(
                baselineEstablished: automaticScanBaselineEstablished,
                seenIdentifiers: automaticScanSeenAssetIdentifiers
            )
        }
        set {
            automaticScanBaselineEstablished = newValue.baselineEstablished
            automaticScanSeenAssetIdentifiers = newValue.seenIdentifiers
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        videoQuality = VideoQuality(rawValue: defaults.string(forKey: Key.videoQuality) ?? "") ?? .balanced
        photoQuality = PhotoQuality(rawValue: defaults.string(forKey: Key.photoQuality) ?? "") ?? .balanced
        liveResolution = LiveMotionResolution(rawValue: defaults.string(forKey: Key.liveResolution) ?? "") ?? .original
        filenameRule = FilenameRule(rawValue: defaults.string(forKey: Key.filenameRule) ?? "") ?? .originalWithSuffix
        filenameSuffix = defaults.string(forKey: Key.filenameSuffix) ?? "_Compressed"
        filenameTemplate = defaults.string(forKey: Key.filenameTemplate) ?? "{date}_{original}_Small"
        deleteOriginals = defaults.object(forKey: Key.deleteOriginals) as? Bool ?? true
        autoConvert = defaults.object(forKey: Key.autoConvert) as? Bool ?? Self.defaultAutoConvert
        autoDetectionScope = AutoDetectionScope(rawValue: defaults.string(forKey: Key.autoDetectionScope) ?? "") ?? Self.defaultAutoDetectionScope
        if defaults.integer(forKey: Key.automaticCounter) == 0 {
            defaults.set(1, forKey: Key.automaticCounter)
        }
    }
}
