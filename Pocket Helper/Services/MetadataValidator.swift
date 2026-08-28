import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct MetadataValidator {
    nonisolated init() {}

    nonisolated func validatePhoto(sourceURL: URL, outputURL: URL, expectsMatchingDimensions: Bool = true) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let output = CGImageSourceCreateWithURL(outputURL as CFURL, nil) else {
            throw PipelineError.validationFailed("无法读取照片容器")
        }
        guard let outputType = CGImageSourceGetType(output), UTType(outputType as String)?.conforms(to: .heic) == true else {
            throw PipelineError.validationFailed("输出不是 HEIF/HEIC")
        }
        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let outputProperties = CGImageSourceCopyPropertiesAtIndex(output, 0, nil) as? [CFString: Any] ?? [:]
        if expectsMatchingDimensions {
            let sourceWidth = sourceProperties[kCGImagePropertyPixelWidth] as? Int
            let sourceHeight = sourceProperties[kCGImagePropertyPixelHeight] as? Int
            let outputWidth = outputProperties[kCGImagePropertyPixelWidth] as? Int
            let outputHeight = outputProperties[kCGImagePropertyPixelHeight] as? Int
            guard sourceWidth == outputWidth, sourceHeight == outputHeight else {
                throw PipelineError.validationFailed("照片像素尺寸发生变化")
            }
        }

        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] {
            if sourceProperties[key] != nil, outputProperties[key] == nil {
                throw PipelineError.validationFailed("缺少关键照片元数据：\(key)")
            }
        }

        let sourceGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, kCGImageAuxiliaryDataTypeHDRGainMap)
        let outputGainMap = CGImageSourceCopyAuxiliaryDataInfoAtIndex(output, 0, kCGImageAuxiliaryDataTypeHDRGainMap)
        if sourceGainMap != nil, outputGainMap == nil {
            throw PipelineError.validationFailed("HDR gain map 未保留")
        }
        let sourceHeadroom = sourceProperties["Headroom" as CFString] as? Double
        let outputHeadroom = outputProperties["Headroom" as CFString] as? Double
        if let sourceHeadroom, sourceHeadroom > 1, (outputHeadroom ?? 0) <= 1 {
            throw PipelineError.validationFailed("照片扩展动态范围未保留")
        }
        PocketLog.debug("照片校验通过：HEIF=true，gainMap=\(sourceGainMap != nil)，尺寸匹配=\(expectsMatchingDimensions)")
    }

    nonisolated func validateVideo(sourceURL: URL, outputURL: URL, maximumSize: CGSize? = nil) async throws {
        let source = AVURLAsset(url: sourceURL)
        let output = AVURLAsset(url: outputURL)
        let sourceDuration = try await source.load(.duration)
        let outputDuration = try await output.load(.duration)
        let delta = abs(CMTimeGetSeconds(sourceDuration) - CMTimeGetSeconds(outputDuration))
        guard delta <= 0.12 else {
            throw PipelineError.validationFailed("视频时长不一致")
        }
        guard let outputTrack = try await output.loadTracks(withMediaType: .video).first else {
            throw PipelineError.validationFailed("输出缺少视频轨道")
        }
        let descriptions = try await outputTrack.load(.formatDescriptions)
        guard descriptions.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC }) else {
            throw PipelineError.validationFailed("输出视频不是 HEVC")
        }

        let sourceTracks = try await source.loadTracks(withMediaType: .video)
        var sourceHDR = false
        let outputHDR = descriptions.contains(where: Self.isHDR)
        if let sourceTrack = sourceTracks.first {
            let sourceDescriptions = try await sourceTrack.load(.formatDescriptions)
            sourceHDR = sourceDescriptions.contains(where: Self.isHDR)
            if sourceHDR, !outputHDR {
                throw PipelineError.validationFailed("HDR 色彩信息未保留")
            }
        }

        let naturalSize = try await outputTrack.load(.naturalSize)
        let transform = try await outputTrack.load(.preferredTransform)
        let oriented = naturalSize.applying(transform)
        let actual = CGSize(width: abs(oriented.width), height: abs(oriented.height))
        if let maximumSize {
            let landscapeBound = CGSize(width: max(maximumSize.width, maximumSize.height), height: min(maximumSize.width, maximumSize.height))
            let sortedActual = CGSize(width: max(actual.width, actual.height), height: min(actual.width, actual.height))
            guard sortedActual.width <= landscapeBound.width + 2, sortedActual.height <= landscapeBound.height + 2 else {
                throw PipelineError.validationFailed("Live Photo 动态部分超过设定分辨率")
            }
        }

        let sourceAudioCount = try await source.loadTracks(withMediaType: .audio).count
        let outputAudioCount = try await output.loadTracks(withMediaType: .audio).count
        if sourceAudioCount > 0, outputAudioCount == 0 {
            throw PipelineError.validationFailed("输出缺少音轨")
        }
        PocketLog.debug(
            "视频校验通过：HEVC=true，尺寸=\(Int(actual.width))x\(Int(actual.height))，HDR输入=\(sourceHDR)，HDR输出=\(outputHDR)，音轨=\(outputAudioCount)"
        )
    }

    nonisolated func validateLivePhoto(
        photoURL: URL,
        videoURL: URL,
        expectedContentIdentifier: String
    ) async throws {
        guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any],
              let photoIdentifier = maker["17"] as? String,
              photoIdentifier == expectedContentIdentifier else {
            throw PipelineError.validationFailed("Live Photo 静态资源缺少配对标识")
        }

        let asset = AVURLAsset(url: videoURL)
        let metadata = try await asset.load(.metadata)
        var movieIdentifier: String?
        for item in metadata where item.identifier == .quickTimeMetadataContentIdentifier {
            movieIdentifier = try await item.load(.stringValue)
            if movieIdentifier != nil { break }
        }
        guard movieIdentifier == expectedContentIdentifier else {
            throw PipelineError.validationFailed("Live Photo 动态资源配对标识不一致")
        }

        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        var hasStillImageTime = false
        for track in metadataTracks {
            for description in try await track.load(.formatDescriptions) {
                let identifiers = CMMetadataFormatDescriptionGetIdentifiers(description) as? [String] ?? []
                if identifiers.contains(where: { $0.contains("com.apple.quicktime.still-image-time") }) {
                    hasStillImageTime = true
                    break
                }
            }
            if hasStillImageTime { break }
        }
        guard hasStillImageTime else {
            throw PipelineError.validationFailed("Live Photo 动态资源缺少 still-image-time")
        }
        PocketLog.debug("Live Photo 文件级校验通过：配对标识一致，still-image-time=true，元数据轨道=\(metadataTracks.count)")
    }

    nonisolated private static func isHDR(_ description: CMFormatDescription) -> Bool {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [CFString: Any] else { return false }
        let transfer = extensions[kCMFormatDescriptionExtension_TransferFunction] as? String
        let primaries = extensions[kCMFormatDescriptionExtension_ColorPrimaries] as? String
        return transfer?.localizedCaseInsensitiveContains("HLG") == true
            || transfer?.localizedCaseInsensitiveContains("2084") == true
            || primaries?.localizedCaseInsensitiveContains("2020") == true
    }
}
