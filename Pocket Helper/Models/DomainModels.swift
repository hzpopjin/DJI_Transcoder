import Foundation
import Photos

enum MediaScanWindow: Sendable {
    case today
    case recentSevenDays

    var title: String {
        switch self {
        case .today: "今天"
        case .recentSevenDays: "最近 7 天"
        }
    }

    func cutoff(referenceDate: Date = .now, calendar: Calendar = .current) -> Date {
        let startOfToday = calendar.startOfDay(for: referenceDate)
        switch self {
        case .today:
            return startOfToday
        case .recentSevenDays:
            return calendar.date(byAdding: .day, value: -6, to: startOfToday) ?? startOfToday
        }
    }
}

enum AutoDetectionScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case photos
    case videos
    case photosAndVideos

    nonisolated var id: String { rawValue }

    nonisolated var title: String {
        switch self {
        case .photos: "照片"
        case .videos: "视频"
        case .photosAndVideos: "照片和视频"
        }
    }

    nonisolated func includes(_ kind: MediaKind) -> Bool {
        switch self {
        case .photos:
            kind == .photo || kind == .livePhoto
        case .videos:
            kind == .video
        case .photosAndVideos:
            true
        }
    }
}

enum MediaKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case photo
    case video
    case livePhoto

    var id: String { rawValue }

    var title: String {
        switch self {
        case .photo: "照片"
        case .video: "视频"
        case .livePhoto: "Live Photo"
        }
    }

    var symbol: String {
        switch self {
        case .photo: "photo"
        case .video: "video"
        case .livePhoto: "livephoto"
        }
    }
}

enum ProcessingState: String, Codable, CaseIterable, Sendable {
    case discovered
    case waitingForConfirmation
    case queued
    case downloading
    case transcoding
    case validating
    case saving
    case readyToDelete
    case completed
    case paused
    case skipped
    case failed

    var title: String {
        switch self {
        case .discovered: "已发现"
        case .waitingForConfirmation: "等待确认"
        case .queued: "等待处理"
        case .downloading: "正在下载"
        case .transcoding: "正在压缩"
        case .validating: "正在校验"
        case .saving: "正在保存"
        case .readyToDelete: "可删除原片"
        case .completed: "已完成"
        case .paused: "已暂停"
        case .skipped: "已跳过"
        case .failed: "失败"
        }
    }

    var isActive: Bool {
        [.queued, .downloading, .transcoding, .validating, .saving].contains(self)
    }

    var isHistoryRecord: Bool { !isActive }
}

enum VideoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case spaceSaving
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaceSaving: "节省空间"
        case .balanced: "均衡"
        case .high: "高质量"
        }
    }

    nonisolated var bitrateMultiplier: Double {
        switch self {
        case .spaceSaving: 0.8
        case .balanced: 1
        case .high: 1.25
        }
    }
}

struct VideoEncodingProfile: Sendable, Equatable {
    let width: Int
    let height: Int
    let frameRate: Double
    let targetBitrate: Double

    var experimentalFrameRate: Int? {
        let longEdge = max(width, height)
        let shortEdge = min(width, height)
        guard longEdge >= 3_800, shortEdge >= 2_100 else { return nil }
        if frameRate >= 100 { return 120 }
        if frameRate >= 50 { return 60 }
        return nil
    }
}

struct ExperimentalVideoConfirmation: Identifiable, Sendable, Equatable {
    let id: String
    let filename: String
    let frameRateMode: Int
    let targetBitrate: Double
}

enum VideoBitratePolicy {
    nonisolated static func targetBitrate(
        width: Int,
        height: Int,
        frameRate: Double,
        quality: VideoQuality = .balanced
    ) -> Double {
        baseBitrate(width: width, height: height)
            * frameRateMultiplier(frameRate)
            * quality.bitrateMultiplier
    }

    nonisolated static func baseBitrate(width: Int, height: Int) -> Double {
        let pixels = Double(max(1, width) * max(1, height))
        let p720 = Double(1280 * 720)
        let p1080 = Double(1920 * 1080)
        let p4K = Double(3840 * 2160)

        if pixels <= p720 {
            return 2_000_000 * pixels / p720
        }
        if pixels <= p1080 {
            return interpolate(pixels, from: p720, to: p1080, lower: 2_000_000, upper: 6_000_000)
        }
        if pixels <= p4K {
            return interpolate(pixels, from: p1080, to: p4K, lower: 6_000_000, upper: 16_000_000)
        }
        return 16_000_000 * pixels / p4K
    }

    nonisolated static func frameRateMultiplier(_ frameRate: Double) -> Double {
        let fps = max(1, frameRate)
        if fps <= 30 { return 1 }
        if fps <= 60 { return 1 + (fps - 30) / 60 }
        if fps <= 120 { return 1.5 + (fps - 60) / 120 }
        return 2
    }

    nonisolated private static func interpolate(
        _ value: Double,
        from lowerBound: Double,
        to upperBound: Double,
        lower: Double,
        upper: Double
    ) -> Double {
        let progress = (value - lowerBound) / (upperBound - lowerBound)
        return lower + (upper - lower) * progress
    }
}

enum PhotoQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case spaceSaving
    case balanced
    case high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spaceSaving: "节省空间"
        case .balanced: "均衡"
        case .high: "高质量"
        }
    }

    nonisolated var compressionQuality: Double {
        switch self {
        case .spaceSaving: 0.65
        case .balanced: 0.82
        case .high: 0.92
        }
    }
}

enum LiveMotionResolution: String, Codable, CaseIterable, Identifiable, Sendable {
    case original
    case p1080
    case p720

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: "原始分辨率"
        case .p1080: "最高 1080P"
        case .p720: "最高 720P"
        }
    }

    nonisolated var boundingSize: CGSize? {
        switch self {
        case .original: nil
        case .p1080: CGSize(width: 1920, height: 1080)
        case .p720: CGSize(width: 1280, height: 720)
        }
    }
}

enum FilenameRule: String, Codable, CaseIterable, Identifiable, Sendable {
    case originalWithSuffix
    case automaticCounter
    case customTemplate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .originalWithSuffix: "原名加后缀"
        case .automaticCounter: "自动编号"
        case .customTemplate: "自定义模板"
        }
    }
}

enum MessageSeverity: String, Codable, CaseIterable, Identifiable, Sendable {
    case warning
    case error

    var id: String { rawValue }
    var title: String { self == .error ? "错误" : "警告" }
    var symbol: String { self == .error ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill" }
}

enum MessageAction: String, Codable, Sendable {
    case retry
    case openSettings
    case retryDownload
    case none
}

enum MediaSource: String, Codable, Sendable {
    case dji
    case other
}

struct MediaAssetDescriptor: Identifiable, Sendable {
    let id: String
    let kind: MediaKind
    let originalFilename: String
    let creationDate: Date?
    let estimatedBytes: Int64
    let pixelWidth: Int
    let pixelHeight: Int
    let source: MediaSource

    init(asset: PHAsset, resource: PHAssetResource, estimatedBytes: Int64, source: MediaSource) {
        id = asset.localIdentifier
        kind = asset.mediaSubtypes.contains(.photoLive) ? .livePhoto : (asset.mediaType == .video ? .video : .photo)
        originalFilename = resource.originalFilename
        creationDate = asset.creationDate
        self.estimatedBytes = estimatedBytes
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        self.source = source
    }
}

struct AssetSelectionResolution: Sendable {
    let descriptors: [MediaAssetDescriptor]
    let unsupportedCount: Int
    let outputCount: Int
}

struct PickerAssetResolution: Sendable {
    let identifiers: [String]
    let unresolvedCount: Int
}

struct DownloadedMedia: Sendable {
    let descriptor: MediaAssetDescriptor
    let primaryURL: URL
    let pairedVideoURL: URL?
    let creationDate: Date?
    let location: SendableLocation?
}

struct SendableLocation: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
}

struct TranscodeResult: Sendable {
    let primaryURL: URL
    let pairedVideoURL: URL?
    let originalBytes: Int64
    let outputBytes: Int64
    let warnings: [String]

    var bytesSaved: Int64 { max(0, originalBytes - outputBytes) }
}

enum PipelineError: LocalizedError, Sendable {
    case permissionDenied
    case resourceMissing(String)
    case downloadFailed(String)
    case unsupported(String)
    case transcodeFailed(String)
    case validationFailed(String)
    case noSavings
    case saveFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "需要完整的照片访问权限"
        case .resourceMissing(let detail): "找不到原始资源：\(detail)"
        case .downloadFailed(let detail): "下载原片失败：\(detail)"
        case .unsupported(let detail): "暂不支持该素材：\(detail)"
        case .transcodeFailed(let detail): "压缩失败：\(detail)"
        case .validationFailed(let detail): "输出校验失败：\(detail)"
        case .noSavings: "压缩后没有节省空间"
        case .saveFailed(let detail): "保存到相册失败：\(detail)"
        case .cancelled: "处理已取消"
        }
    }
}
