import AVFoundation
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

actor MediaTranscoder {
    private let validator = MetadataValidator()

    func videoEncodingProfile(
        for media: DownloadedMedia,
        quality: VideoQuality
    ) async throws -> VideoEncodingProfile? {
        guard media.descriptor.kind == .video else { return nil }
        return try await loadVideoEncodingProfile(
            sourceURL: media.primaryURL,
            quality: quality,
            maximumSize: nil
        )
    }

    func transcode(
        _ media: DownloadedMedia,
        videoQuality: VideoQuality,
        photoQuality: PhotoQuality,
        liveResolution: LiveMotionResolution,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeResult {
        try Task.checkCancellation()
        let startedAt = Date()
        PocketLog.info("开始转码：\(media.descriptor.originalFilename)，类型=\(media.descriptor.kind.rawValue)，视频质量=\(videoQuality.rawValue)，照片质量=\(photoQuality.rawValue)，Live分辨率=\(liveResolution.rawValue)")
        let result: TranscodeResult
        switch media.descriptor.kind {
        case .photo:
            result = try await transcodePhoto(media, quality: photoQuality, progress: progress)
        case .video:
            result = try await transcodeVideo(media, quality: videoQuality, progress: progress)
        case .livePhoto:
            result = try await transcodeLivePhoto(
                media,
                videoQuality: videoQuality,
                photoQuality: photoQuality,
                resolution: liveResolution,
                progress: progress
            )
        }
        PocketLog.performance(
            "媒体管线",
            durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
            originalBytes: result.originalBytes,
            outputBytes: result.outputBytes,
            bytesSaved: result.bytesSaved
        )
        return result
    }

    private func transcodePhoto(
        _ media: DownloadedMedia,
        quality: PhotoQuality,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeResult {
        let startedAt = Date()
        progress(0.05)
        let output = media.primaryURL.deletingLastPathComponent().appendingPathComponent("output.HEIC")
        try writeHEIF(sourceURL: media.primaryURL, outputURL: output, quality: quality.compressionQuality, contentIdentifier: nil)
        progress(0.75)
        try validator.validatePhoto(sourceURL: media.primaryURL, outputURL: output)
        progress(1)
        let originalBytes = try fileSize(media.primaryURL)
        let outputBytes = try fileSize(output)
        guard outputBytes < originalBytes else {
            try? FileManager.default.removeItem(at: output)
            throw PipelineError.noSavings
        }
        PocketLog.performance(
            "照片转码",
            durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
            originalBytes: originalBytes,
            outputBytes: outputBytes
        )
        return TranscodeResult(
            primaryURL: output,
            pairedVideoURL: nil,
            originalBytes: originalBytes,
            outputBytes: outputBytes,
            warnings: []
        )
    }

    private func transcodeVideo(
        _ media: DownloadedMedia,
        quality: VideoQuality,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeResult {
        let startedAt = Date()
        let output = media.primaryURL.deletingLastPathComponent().appendingPathComponent("output.mov")
        try await exportHEVC(
            sourceURL: media.primaryURL,
            outputURL: output,
            quality: quality,
            maximumSize: nil,
            contentIdentifier: nil,
            progress: progress
        )
        try await validator.validateVideo(sourceURL: media.primaryURL, outputURL: output)
        let originalBytes = try fileSize(media.primaryURL)
        let outputBytes = try fileSize(output)
        guard outputBytes < originalBytes else {
            try? FileManager.default.removeItem(at: output)
            throw PipelineError.noSavings
        }
        PocketLog.performance(
            "视频转码",
            durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
            originalBytes: originalBytes,
            outputBytes: outputBytes
        )
        return TranscodeResult(
            primaryURL: output,
            pairedVideoURL: nil,
            originalBytes: originalBytes,
            outputBytes: outputBytes,
            warnings: []
        )
    }

    private func transcodeLivePhoto(
        _ media: DownloadedMedia,
        videoQuality: VideoQuality,
        photoQuality: PhotoQuality,
        resolution: LiveMotionResolution,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> TranscodeResult {
        let startedAt = Date()
        guard let pairedInput = media.pairedVideoURL else {
            throw PipelineError.resourceMissing("Live Photo 动态资源")
        }
        let identifier = UUID().uuidString
        let photoOutput = media.primaryURL.deletingLastPathComponent().appendingPathComponent("live-output.HEIC")
        let videoOutput = media.primaryURL.deletingLastPathComponent().appendingPathComponent("live-output.mov")

        progress(0.02)
        try writeHEIF(
            sourceURL: media.primaryURL,
            outputURL: photoOutput,
            quality: photoQuality.compressionQuality,
            contentIdentifier: identifier
        )
        progress(0.22)
        try await exportHEVC(
            sourceURL: pairedInput,
            outputURL: videoOutput,
            quality: videoQuality,
            maximumSize: resolution.boundingSize,
            contentIdentifier: identifier
        ) { videoProgress in
            progress(0.22 + videoProgress * 0.68)
        }
        try validator.validatePhoto(sourceURL: media.primaryURL, outputURL: photoOutput)
        try await validator.validateVideo(sourceURL: pairedInput, outputURL: videoOutput, maximumSize: resolution.boundingSize)
        try await validator.validateLivePhoto(
            photoURL: photoOutput,
            videoURL: videoOutput,
            expectedContentIdentifier: identifier
        )
        progress(1)

        let originalBytes = try fileSize(media.primaryURL) + fileSize(pairedInput)
        let outputBytes = try fileSize(photoOutput) + fileSize(videoOutput)
        let warnings = outputBytes < originalBytes
            ? []
            : ["Live Photo 输出未减小，但已保留并保存完整的静态与动态配对资源。"]
        PocketLog.performance(
            "Live Photo 转码",
            durationMilliseconds: Self.elapsedMilliseconds(since: startedAt),
            originalBytes: originalBytes,
            outputBytes: outputBytes
        )
        return TranscodeResult(
            primaryURL: photoOutput,
            pairedVideoURL: videoOutput,
            originalBytes: originalBytes,
            outputBytes: outputBytes,
            warnings: warnings
        )
    }

    private func writeHEIF(
        sourceURL: URL,
        outputURL: URL,
        quality: Double,
        contentIdentifier: String?
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let destination = CGImageDestinationCreateWithURL(
                outputURL as CFURL,
                UTType.heic.identifier as CFString,
                1,
                nil
              ) else {
            throw PipelineError.transcodeFailed("无法创建 HEIF 编码器")
        }

        var properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        properties[kCGImageDestinationMergeMetadata] = true
        properties[kCGImageDestinationPreserveGainMap] = true
        properties[kCGImageMetadataShouldExcludeGPS] = false
        properties[kCGImageMetadataShouldExcludeXMP] = false
        if let contentIdentifier {
            var maker = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any] ?? [:]
            maker["17"] = contentIdentifier
            properties[kCGImagePropertyMakerAppleDictionary] = maker
        }

        CGImageDestinationAddImageFromSource(destination, source, 0, properties as CFDictionary)
        for auxiliaryType in [
            kCGImageAuxiliaryDataTypeHDRGainMap,
            kCGImageAuxiliaryDataTypeDepth,
            kCGImageAuxiliaryDataTypeDisparity,
            kCGImageAuxiliaryDataTypePortraitEffectsMatte
        ] {
            if let auxiliary = CGImageSourceCopyAuxiliaryDataInfoAtIndex(source, 0, auxiliaryType) {
                CGImageDestinationAddAuxiliaryDataInfo(destination, auxiliaryType, auxiliary)
            }
        }
        guard CGImageDestinationFinalize(destination) else {
            throw PipelineError.transcodeFailed("HEIF 写入失败")
        }
    }

    private func exportHEVC(
        sourceURL: URL,
        outputURL: URL,
        quality: VideoQuality,
        maximumSize: CGSize?,
        contentIdentifier: String?,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try? FileManager.default.removeItem(at: outputURL)
        let sourceAsset = AVURLAsset(url: sourceURL)
        let profile = try await loadVideoEncodingProfile(
            sourceAsset: sourceAsset,
            quality: quality,
            maximumSize: maximumSize
        )
        let (asset, videoTrack) = try await makeExportComposition(sourceAsset: sourceAsset)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw PipelineError.unsupported("设备不支持 HEVC 导出")
        }
        let duration = try await sourceAsset.load(.duration)
        let targetBytes = Int64(max(1, CMTimeGetSeconds(duration)) * profile.targetBitrate / 8)
        session.fileLengthLimit = targetBytes
        session.shouldOptimizeForNetworkUse = true
        PocketLog.performance(
            "视频输入",
            width: profile.width,
            height: profile.height,
            frameRate: profile.frameRate,
            targetBitrate: Int64(profile.targetBitrate.rounded())
        )

        var metadata = try await sourceAsset.load(.metadata)
        if let contentIdentifier {
            metadata.removeAll { $0.identifier == .quickTimeMetadataContentIdentifier }
            let item = AVMutableMetadataItem()
            item.identifier = .quickTimeMetadataContentIdentifier
            item.dataType = kCMMetadataBaseDataType_UTF8 as String
            item.value = contentIdentifier as NSString
            metadata.append(item)
        }
        session.metadata = metadata

        if let maximumSize,
           let composition = try await makeVideoComposition(asset: asset, track: videoTrack, maximumSize: maximumSize) {
            session.videoComposition = composition
        }

        progress(0.05)
        let exportStartedAt = Date()
        do {
            try await session.export(to: outputURL, as: .mov)
        } catch is CancellationError {
            session.cancelExport()
            throw CancellationError()
        } catch {
            throw PipelineError.transcodeFailed(error.localizedDescription)
        }
        let outputBytes = try fileSize(outputURL)
        let durationSeconds = max(0.001, CMTimeGetSeconds(duration))
        let actualBitrate = Double(outputBytes * 8) / durationSeconds
        PocketLog.performance(
            "视频输出",
            durationMilliseconds: Self.elapsedMilliseconds(since: exportStartedAt),
            outputBytes: outputBytes,
            actualBitrate: Int64(actualBitrate.rounded())
        )
        progress(1)
    }

    private func loadVideoEncodingProfile(
        sourceURL: URL,
        quality: VideoQuality,
        maximumSize: CGSize?
    ) async throws -> VideoEncodingProfile {
        try await loadVideoEncodingProfile(
            sourceAsset: AVURLAsset(url: sourceURL),
            quality: quality,
            maximumSize: maximumSize
        )
    }

    private func loadVideoEncodingProfile(
        sourceAsset: AVAsset,
        quality: VideoQuality,
        maximumSize: CGSize?
    ) async throws -> VideoEncodingProfile {
        guard let track = try await sourceAsset.loadTracks(withMediaType: .video).first else {
            throw PipelineError.unsupported("素材没有可转换的视频轨道")
        }
        let naturalSize = try await track.load(.naturalSize)
        let transform = try await track.load(.preferredTransform)
        let oriented = naturalSize.applying(transform)
        var width = abs(oriented.width)
        var height = abs(oriented.height)

        if let maximumSize {
            let landscapeBound = CGSize(
                width: max(maximumSize.width, maximumSize.height),
                height: min(maximumSize.width, maximumSize.height)
            )
            let scale = min(
                1,
                min(
                    landscapeBound.width / max(width, height),
                    landscapeBound.height / min(width, height)
                )
            )
            width *= scale
            height *= scale
        }

        let outputWidth = max(2, Int((width / 2).rounded(.down) * 2))
        let outputHeight = max(2, Int((height / 2).rounded(.down) * 2))
        let frameRate = max(1, Double(try await track.load(.nominalFrameRate)))
        return VideoEncodingProfile(
            width: outputWidth,
            height: outputHeight,
            frameRate: frameRate,
            targetBitrate: VideoBitratePolicy.targetBitrate(
                width: outputWidth,
                height: outputHeight,
                frameRate: frameRate,
                quality: quality
            )
        )
    }

    private func makeExportComposition(
        sourceAsset: AVAsset
    ) async throws -> (asset: AVMutableComposition, videoTrack: AVMutableCompositionTrack) {
        let composition = AVMutableComposition()
        guard let sourceVideo = try await sourceAsset.loadTracks(withMediaType: .video).first,
              let compositionVideo = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw PipelineError.unsupported("素材没有可转换的视频轨道")
        }
        let duration = try await sourceAsset.load(.duration)
        try compositionVideo.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceVideo,
            at: .zero
        )
        compositionVideo.preferredTransform = try await sourceVideo.load(.preferredTransform)

        for sourceAudio in try await sourceAsset.loadTracks(withMediaType: .audio) {
            guard let compositionAudio = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let timeRange = try await sourceAudio.load(.timeRange)
            try compositionAudio.insertTimeRange(timeRange, of: sourceAudio, at: timeRange.start)
        }

        for sourceMetadata in try await sourceAsset.loadTracks(withMediaType: .metadata) {
            guard let compositionMetadata = composition.addMutableTrack(
                withMediaType: .metadata,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { continue }
            let timeRange = try await sourceMetadata.load(.timeRange)
            try compositionMetadata.insertTimeRange(timeRange, of: sourceMetadata, at: timeRange.start)
        }

        PocketLog.debug("已构建导出轨道：1 个主视频、\((try await sourceAsset.loadTracks(withMediaType: .audio)).count) 个音频、\((try await sourceAsset.loadTracks(withMediaType: .metadata)).count) 个元数据轨道")
        return (composition, compositionVideo)
    }

    private func makeVideoComposition(
        asset: AVAsset,
        track: AVAssetTrack,
        maximumSize: CGSize
    ) async throws -> AVVideoComposition? {
        let natural = try await track.load(.naturalSize)
        let preferredTransform = try await track.load(.preferredTransform)
        let transformedRect = CGRect(origin: .zero, size: natural).applying(preferredTransform)
        let oriented = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        let landscapeBound = CGSize(width: max(maximumSize.width, maximumSize.height), height: min(maximumSize.width, maximumSize.height))
        let scale = min(1, min(landscapeBound.width / max(oriented.width, oriented.height), landscapeBound.height / min(oriented.width, oriented.height)))
        guard scale < 0.999 else { return nil }

        let renderSize = CGSize(
            width: max(2, (oriented.width * scale / 2).rounded(.down) * 2),
            height: max(2, (oriented.height * scale / 2).rounded(.down) * 2)
        )
        var finalTransform = preferredTransform.concatenating(
            CGAffineTransform(translationX: -transformedRect.minX, y: -transformedRect.minY)
        )
        finalTransform = finalTransform.concatenating(CGAffineTransform(scaleX: scale, y: scale))

        let rate = max(1, Int32((try await track.load(.nominalFrameRate)).rounded()))
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layerInstruction.setTransform(finalTransform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        instruction.layerInstructions = [layerInstruction]
        let composition = AVMutableVideoComposition()
        composition.renderSize = renderSize
        composition.frameDuration = CMTime(value: 1, timescale: rate)
        composition.instructions = [instruction]
        composition.perFrameHDRDisplayMetadataPolicy = .propagate
        return composition
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    nonisolated private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1_000))
    }
}
