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
            let sourceWidth = Self.number(sourceProperties[kCGImagePropertyPixelWidth])?.intValue
            let sourceHeight = Self.number(sourceProperties[kCGImagePropertyPixelHeight])?.intValue
            let outputWidth = Self.number(outputProperties[kCGImagePropertyPixelWidth])?.intValue
            let outputHeight = Self.number(outputProperties[kCGImagePropertyPixelHeight])?.intValue
            guard sourceWidth == outputWidth, sourceHeight == outputHeight else {
                throw PipelineError.validationFailed("照片像素尺寸发生变化")
            }
        }

        for key in [kCGImagePropertyExifDictionary, kCGImagePropertyTIFFDictionary, kCGImagePropertyGPSDictionary] {
            if sourceProperties[key] != nil, outputProperties[key] == nil {
                throw PipelineError.validationFailed("缺少关键照片元数据")
            }
        }
        try Self.validatePhotoMetadata(source: sourceProperties, output: outputProperties)

        for auxiliaryType in [
            kCGImageAuxiliaryDataTypeHDRGainMap,
            kCGImageAuxiliaryDataTypeDepth,
            kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte
        ] {
            let sourceAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType)
            let outputAuxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(output, 0, auxiliaryType)
            if sourceAuxiliary != nil, outputAuxiliary == nil {
                throw PipelineError.validationFailed("照片辅助图像数据未保留")
            }
        }

        let sourceHeadroom = Self.number(sourceProperties["Headroom" as CFString])?.doubleValue
        let outputHeadroom = Self.number(outputProperties["Headroom" as CFString])?.doubleValue
        if let sourceHeadroom, sourceHeadroom > 1, (outputHeadroom ?? 0) <= 1 {
            throw PipelineError.validationFailed("照片扩展动态范围未保留")
        }
        PocketLog.debug("照片校验通过：HEIF=true，HDR辅助数据已核对，关键元数据已核对，尺寸匹配=\(expectsMatchingDimensions)")
    }

    nonisolated func validateVideo(sourceURL: URL, outputURL: URL, maximumSize: CGSize? = nil) async throws {
        let source = AVURLAsset(url: sourceURL)
        let output = AVURLAsset(url: outputURL)
        let sourceDuration = try await source.load(.duration)
        let outputDuration = try await output.load(.duration)
        let sourceSeconds = CMTimeGetSeconds(sourceDuration)
        let outputSeconds = CMTimeGetSeconds(outputDuration)
        guard sourceSeconds.isFinite, outputSeconds.isFinite else {
            throw PipelineError.validationFailed("视频时长无法读取")
        }
        let delta = abs(sourceSeconds - outputSeconds)
        guard delta <= 0.12 else {
            throw PipelineError.validationFailed("视频时长不一致")
        }

        guard let sourceTrack = try await source.loadTracks(withMediaType: .video).first,
              let outputTrack = try await output.loadTracks(withMediaType: .video).first else {
            throw PipelineError.validationFailed("输出缺少视频轨道")
        }
        let outputDescriptions = try await outputTrack.load(.formatDescriptions)
        guard outputDescriptions.contains(where: { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC }) else {
            throw PipelineError.validationFailed("输出视频不是 HEVC")
        }

        let sourceSnapshot = try await Self.videoSnapshot(for: sourceTrack)
        let outputSnapshot = try await Self.videoSnapshot(for: outputTrack)
        try Self.validateDimensions(source: sourceSnapshot, output: outputSnapshot, maximumSize: maximumSize)
        let dimensionsChanged = abs(sourceSnapshot.dimensions.width - outputSnapshot.dimensions.width) > 2
            || abs(sourceSnapshot.dimensions.height - outputSnapshot.dimensions.height) > 2
        if maximumSize == nil || !dimensionsChanged {
            guard sourceSnapshot.orientation == outputSnapshot.orientation else {
                throw PipelineError.validationFailed("视频方向发生变化")
            }
        } else {
            // A resizing AVVideoComposition can bake a 90°/270° preferred
            // transform into the rendered pixels and legitimately emit an
            // identity transform. Compare the resulting display orientation
            // while still rejecting an accidental portrait/landscape swap.
            guard Self.displayOrientationMatches(
                source: sourceSnapshot.dimensions,
                output: outputSnapshot.dimensions
            ) else {
                throw PipelineError.validationFailed("视频显示方向发生变化")
            }
        }
        let frameRateTolerance = max(1.0, sourceSnapshot.frameRate * 0.03)
        guard abs(sourceSnapshot.frameRate - outputSnapshot.frameRate) <= frameRateTolerance else {
            throw PipelineError.validationFailed("视频实际帧率发生变化")
        }

        if let sourceBitDepth = sourceSnapshot.bitDepth, sourceBitDepth >= 10 {
            guard let outputBitDepth = outputSnapshot.bitDepth, outputBitDepth >= min(10, sourceBitDepth) else {
                throw PipelineError.validationFailed("视频 10-bit 色深未保留")
            }
        }

        if sourceSnapshot.isHDR {
            guard outputSnapshot.isHDR else {
                throw PipelineError.validationFailed("HDR 色彩信息未保留")
            }
            guard Self.normalizedColorValue(sourceSnapshot.transferFunction) == Self.normalizedColorValue(outputSnapshot.transferFunction) else {
                throw PipelineError.validationFailed("HDR 传递函数发生变化")
            }
            if sourceSnapshot.colorPrimaries != nil {
                guard Self.normalizedColorValue(sourceSnapshot.colorPrimaries) == Self.normalizedColorValue(outputSnapshot.colorPrimaries) else {
                    throw PipelineError.validationFailed("HDR 色域基色发生变化")
                }
            }
            if sourceSnapshot.matrix != nil {
                guard Self.normalizedColorValue(sourceSnapshot.matrix) == Self.normalizedColorValue(outputSnapshot.matrix) else {
                    throw PipelineError.validationFailed("HDR 色彩矩阵发生变化")
                }
            }
        }

        let sourceAudioCount = try await source.loadTracks(withMediaType: .audio).count
        let outputAudioCount = try await output.loadTracks(withMediaType: .audio).count
        if sourceAudioCount > 0, outputAudioCount == 0 {
            throw PipelineError.validationFailed("输出缺少音轨")
        }
        PocketLog.debug(
            "视频校验通过：HEVC=true，尺寸=\(Int(outputSnapshot.dimensions.width))x\(Int(outputSnapshot.dimensions.height))，帧率=\(String(format: "%.3f", outputSnapshot.frameRate))，10-bit=\(outputSnapshot.bitDepth ?? 0 >= 10)，HDR=\(outputSnapshot.isHDR)，音轨=\(outputAudioCount)"
        )
    }

    nonisolated func validateLivePhoto(
        photoURL: URL,
        videoURL: URL,
        expectedContentIdentifier: String
    ) async throws {
        guard let source = CGImageSourceCreateWithURL(photoURL as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let maker = Self.stringDictionary(properties[kCGImagePropertyMakerAppleDictionary]),
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

    private struct VideoOrientation: Equatable {
        let quarterTurns: Int
        let mirrored: Bool
    }

    private struct VideoSnapshot {
        let dimensions: CGSize
        let orientation: VideoOrientation
        let frameRate: Double
        let bitDepth: Int?
        let transferFunction: String?
        let colorPrimaries: String?
        let matrix: String?
        let isHDR: Bool
    }

    private static func videoSnapshot(for track: AVAssetTrack) async throws -> VideoSnapshot {
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let dimensions = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let frameRate = Double(try await track.load(.nominalFrameRate))
        guard frameRate.isFinite, frameRate > 0 else {
            throw PipelineError.validationFailed("视频实际帧率无法读取")
        }
        let descriptions = try await track.load(.formatDescriptions)
        guard !descriptions.isEmpty else {
            throw PipelineError.validationFailed("视频格式描述无法读取")
        }
        let extensions = descriptions.compactMap { CMFormatDescriptionGetExtensions($0) as? [CFString: Any] }
        let firstExtensions = extensions.first ?? [:]
        let bitDepth = descriptions.compactMap(Self.bitDepth(from:)).max()
        let transfer = Self.stringValue(firstExtensions[kCMFormatDescriptionExtension_TransferFunction])
        let primaries = Self.stringValue(firstExtensions[kCMFormatDescriptionExtension_ColorPrimaries])
        let matrix = Self.stringValue(firstExtensions[kCMFormatDescriptionExtension_YCbCrMatrix])
        let hdrTransfer = Self.isHDRTransferFunction(transfer)
        let mediaCharacteristics = try await track.load(.mediaCharacteristics)
        let hdrCharacteristic = mediaCharacteristics.contains(.containsHDRVideo)
        return VideoSnapshot(
            dimensions: dimensions,
            orientation: Self.orientation(for: transform),
            frameRate: frameRate,
            bitDepth: bitDepth,
            transferFunction: transfer,
            colorPrimaries: primaries,
            matrix: matrix,
            isHDR: hdrTransfer || hdrCharacteristic
        )
    }

    nonisolated static func displayOrientationMatches(source: CGSize, output: CGSize) -> Bool {
        guard source.width > 0, source.height > 0, output.width > 0, output.height > 0 else {
            return false
        }
        return (source.height > source.width) == (output.height > output.width)
    }

    private nonisolated static func validateDimensions(
        source: VideoSnapshot,
        output: VideoSnapshot,
        maximumSize: CGSize?
    ) throws {
        guard source.dimensions.width > 0, source.dimensions.height > 0,
              output.dimensions.width > 0, output.dimensions.height > 0 else {
            throw PipelineError.validationFailed("视频像素尺寸无法读取")
        }
        if let maximumSize {
            let bound = CGSize(width: max(maximumSize.width, maximumSize.height), height: min(maximumSize.width, maximumSize.height))
            let outputSorted = CGSize(width: max(output.dimensions.width, output.dimensions.height), height: min(output.dimensions.width, output.dimensions.height))
            guard outputSorted.width <= bound.width + 2, outputSorted.height <= bound.height + 2 else {
                throw PipelineError.validationFailed("Live Photo 动态部分超过设定分辨率")
            }
            let sourceAspect = max(source.dimensions.width, source.dimensions.height) / min(source.dimensions.width, source.dimensions.height)
            let outputAspect = max(output.dimensions.width, output.dimensions.height) / min(output.dimensions.width, output.dimensions.height)
            guard abs(sourceAspect - outputAspect) <= 0.02 else {
                throw PipelineError.validationFailed("视频宽高比例发生变化")
            }
        } else {
            guard abs(source.dimensions.width - output.dimensions.width) <= 2,
                  abs(source.dimensions.height - output.dimensions.height) <= 2 else {
                throw PipelineError.validationFailed("视频像素尺寸发生变化")
            }
        }
    }

    private nonisolated static func orientation(for transform: CGAffineTransform) -> VideoOrientation {
        let angle = atan2(transform.b, transform.a)
        let turns = Int((angle / (.pi / 2)).rounded())
        let normalizedTurns = ((turns % 4) + 4) % 4
        let determinant = transform.a * transform.d - transform.b * transform.c
        return VideoOrientation(quarterTurns: normalizedTurns, mirrored: determinant < 0)
    }

    private nonisolated static func bitDepth(from description: CMFormatDescription) -> Int? {
        guard let extensions = CMFormatDescriptionGetExtensions(description) as? [CFString: Any] else { return nil }
        if let number = number(extensions[kCMFormatDescriptionExtension_BitsPerComponent]) {
            return number.intValue
        }
        guard let atoms = extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms] as? [String: Any],
              let payload = atoms["hvcC"] as? Data,
              payload.count > 20 else { return nil }
        return hevcBitDepth(fromHVCC: payload)
    }

    /// Reads `bit_depth_luma_minus8` from the hvcC configuration record. The
    /// field occupies the low three bits of byte 17; byte 18 is the chroma
    /// depth field and bytes 19-20 are the average frame rate.
    nonisolated static func hevcBitDepth(fromHVCC payload: Data) -> Int? {
        guard payload.count > 20 else { return nil }
        return (Int(payload[17]) & 0x07) + 8
    }

    private nonisolated static func isHDRTransferFunction(_ value: String?) -> Bool {
        guard let value = value?.lowercased() else { return false }
        return value.contains("hlg") || value.contains("2084") || value.contains("pq")
    }

    private nonisolated static func normalizedColorValue(_ value: String?) -> String? {
        value?.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private nonisolated static func validatePhotoMetadata(
        source: [CFString: Any],
        output: [CFString: Any]
    ) throws {
        let sourceExif = stringDictionary(source[kCGImagePropertyExifDictionary]) ?? [:]
        let outputExif = stringDictionary(output[kCGImagePropertyExifDictionary]) ?? [:]
        let sourceTIFF = stringDictionary(source[kCGImagePropertyTIFFDictionary]) ?? [:]
        let outputTIFF = stringDictionary(output[kCGImagePropertyTIFFDictionary]) ?? [:]
        let sourceGPS = stringDictionary(source[kCGImagePropertyGPSDictionary]) ?? [:]
        let outputGPS = stringDictionary(output[kCGImagePropertyGPSDictionary]) ?? [:]

        for key in ["DateTimeOriginal", "DateTimeDigitized", "ExposureTime", "FNumber", "ISOSpeedRatings", "FocalLength"] {
            try validatePhotoMetadataValue(key: key, source: sourceExif, output: outputExif)
        }
        for key in ["Make", "Model", "Orientation"] {
            try validatePhotoMetadataValue(key: key, source: sourceTIFF, output: outputTIFF)
        }
        for key in ["Latitude", "Longitude", "Altitude", "LatitudeRef", "LongitudeRef", "AltitudeRef"] {
            try validatePhotoMetadataValue(key: key, source: sourceGPS, output: outputGPS)
        }
        if let sourceOrientation = source[kCGImagePropertyOrientation] {
            guard let outputOrientation = output[kCGImagePropertyOrientation], valuesEqual(sourceOrientation, outputOrientation) else {
                throw PipelineError.validationFailed("照片方向元数据发生变化")
            }
        }
    }

    private nonisolated static func validatePhotoMetadataValue(
        key: String,
        source: [String: Any],
        output: [String: Any]
    ) throws {
        guard let sourceValue = source[key] else { return }
        guard let outputValue = output[key], valuesEqual(sourceValue, outputValue) else {
            throw PipelineError.validationFailed("照片关键元数据发生变化")
        }
    }

    private nonisolated static func valuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let left = number(lhs), let right = number(rhs) {
            if left.objCType == NSNumber(value: true).objCType || right.objCType == NSNumber(value: true).objCType {
                return left.boolValue == right.boolValue
            }
            let tolerance = max(0.000_001, max(abs(left.doubleValue), abs(right.doubleValue)) * 0.000_01)
            return abs(left.doubleValue - right.doubleValue) <= tolerance
        }
        if let left = lhs as? String, let right = rhs as? String {
            return left == right
        }
        if let left = lhs as? [Any], let right = rhs as? [Any] {
            return left.count == right.count && zip(left, right).allSatisfy { valuesEqual($0, $1) }
        }
        return String(describing: lhs) == String(describing: rhs)
    }

    private nonisolated static func number(_ value: Any?) -> NSNumber? {
        if let value = value as? NSNumber { return value }
        if let value = value as? Int { return NSNumber(value: value) }
        if let value = value as? UInt32 { return NSNumber(value: value) }
        if let value = value as? Double { return NSNumber(value: value) }
        if let value = value as? Float { return NSNumber(value: value) }
        return nil
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSString { return value as String }
        return nil
    }

    private nonisolated static func stringDictionary(_ value: Any?) -> [String: Any]? {
        if let dictionary = value as? [String: Any] { return dictionary }
        if let dictionary = value as? [AnyHashable: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, entry in
                if let key = entry.key as? String {
                    result[key] = entry.value
                }
            }
        }
        return nil
    }
}
