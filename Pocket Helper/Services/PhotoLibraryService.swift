import CoreLocation
import Foundation
import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PhotoLibraryService: NSObject {
    static let albumName = "Pocket Helper"
    static let sourceAlbumName = "DJI Album"

    private let resourceManager = PHAssetResourceManager.default()
    private var outputAlbum: PHAssetCollection?

    private final class ResourceDataRequestState: @unchecked Sendable {
        private let lock = NSLock()
        private var requestID: PHAssetResourceDataRequestID?
        private var continuation: CheckedContinuation<Void, Error>?
        private var fileHandle: FileHandle?
        private var lifecycle = ResourceRequestLifecycle()

        func configure(
            continuation: CheckedContinuation<Void, Error>,
            fileHandle: FileHandle
        ) {
            lock.lock()
            if !lifecycle.installContinuation() {
                lock.unlock()
                try? fileHandle.close()
                continuation.resume(throwing: CancellationError())
                return
            }
            self.continuation = continuation
            self.fileHandle = fileHandle
            lock.unlock()
        }

        func setRequestID(_ requestID: PHAssetResourceDataRequestID, manager: PHAssetResourceManager) {
            lock.lock()
            if !lifecycle.installRequestID() {
                lock.unlock()
                manager.cancelDataRequest(requestID)
                return
            }
            self.requestID = requestID
            lock.unlock()
        }

        func append(_ data: Data, manager: PHAssetResourceManager) {
            var requestToCancel: PHAssetResourceDataRequestID?
            var continuationToResume: CheckedContinuation<Void, Error>?
            var handleToClose: FileHandle?
            var failure: Error?

            lock.lock()
            guard !lifecycle.isTerminated else {
                lock.unlock()
                return
            }
            do {
                try fileHandle?.write(contentsOf: data)
            } catch {
                lifecycle.terminate()
                requestToCancel = requestID
                requestID = nil
                continuationToResume = continuation
                continuation = nil
                handleToClose = fileHandle
                fileHandle = nil
                failure = PipelineError.downloadFailed(error.localizedDescription)
            }
            lock.unlock()

            if let requestToCancel {
                manager.cancelDataRequest(requestToCancel)
            }
            try? handleToClose?.close()
            if let failure, let continuationToResume {
                continuationToResume.resume(throwing: failure)
            }
        }

        func finish(error: Error?) {
            var continuationToResume: CheckedContinuation<Void, Error>?
            var handleToClose: FileHandle?
            lock.lock()
            guard !lifecycle.isTerminated else {
                lock.unlock()
                return
            }
            lifecycle.terminate()
            requestID = nil
            continuationToResume = continuation
            continuation = nil
            handleToClose = fileHandle
            fileHandle = nil
            lock.unlock()

            var closeError: Error?
            if let handleToClose {
                do {
                    try handleToClose.close()
                } catch {
                    closeError = PipelineError.downloadFailed("临时文件关闭失败")
                }
            }
            guard let continuationToResume else { return }
            if let error {
                continuationToResume.resume(throwing: error)
            } else if let closeError {
                continuationToResume.resume(throwing: closeError)
            } else {
                continuationToResume.resume()
            }
        }

        func cancel(using manager: PHAssetResourceManager) {
            var requestToCancel: PHAssetResourceDataRequestID?
            var continuationToResume: CheckedContinuation<Void, Error>?
            var handleToClose: FileHandle?
            lock.lock()
            guard !lifecycle.isTerminated else {
                lock.unlock()
                return
            }
            lifecycle.terminate()
            requestToCancel = requestID
            requestID = nil
            continuationToResume = continuation
            continuation = nil
            handleToClose = fileHandle
            fileHandle = nil
            lock.unlock()

            if let requestToCancel {
                manager.cancelDataRequest(requestToCancel)
            }
            try? handleToClose?.close()
            continuationToResume?.resume(throwing: CancellationError())
        }
    }

    var authorizationStatus: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    func requestAuthorization() async -> PHAuthorizationStatus {
        PocketLog.info("开始请求照片读写权限")
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                PocketLog.info("照片权限请求完成，状态 rawValue=\(status.rawValue)")
                continuation.resume(returning: status)
            }
        }
    }

    func discoverDJIAssets(
        excluding identifiers: Set<String>,
        window: MediaScanWindow = .today,
        addedAfter: Date? = nil,
        addedThrough: Date? = nil,
        seenIdentifiers: Set<String> = [],
        includePreviouslySeen: Bool = true,
        recordObservedIdentifiers: Bool = true,
        scope: AutoDetectionScope
    ) async -> AssetDiscoveryResult {
        guard let sourceAlbum = fetchSourceAlbum() else {
            PocketLog.warning("未找到 DJI 来源相簿，自动扫描返回空结果")
            return .noSourceAlbum
        }

        let outputIDs = outputAssetIdentifiers()
        let excluded = identifiers.union(outputIDs)
        let result = PHAsset.fetchAssets(in: sourceAlbum, options: nil)
        var descriptors: [MediaAssetDescriptor] = []
        var observedIdentifiers = Set<String>()
        let initialCutoff = addedAfter ?? window.cutoff()
        let hasInitialDateWindow = includePreviouslySeen && addedAfter != nil
        let hasResetDateWindow = addedAfter == nil

        PocketLog.info(
            "扫描 DJI 来源相簿，模式=\(includePreviouslySeen ? "基线/恢复" : "已见标识增量")，范围=\(hasResetDateWindow ? window.title : "导入变化")，候选总数=\(result.count)，排除数量=\(excluded.count)"
        )

        result.enumerateObjects { asset, _, _ in
            guard asset.mediaType == .image || asset.mediaType == .video else { return }
            let kind: MediaKind = asset.mediaSubtypes.contains(.photoLive)
                ? .livePhoto
                : (asset.mediaType == .video ? .video : .photo)
            guard scope.includes(kind) else { return }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let primary = Self.primaryResource(from: resources, for: asset) else { return }

            // The identifier is the import checkpoint. A camera capture's creationDate
            // can predate the import by months, so it is only used for a first baseline
            // and the explicit recent-week recovery action.
            if recordObservedIdentifiers {
                observedIdentifiers.insert(asset.localIdentifier)
            }
            if !includePreviouslySeen, seenIdentifiers.contains(asset.localIdentifier) {
                return
            }
            if hasInitialDateWindow {
                guard let creationDate = asset.creationDate,
                      creationDate > initialCutoff,
                      creationDate <= (addedThrough ?? .now) else { return }
            } else if hasResetDateWindow {
                guard let creationDate = asset.creationDate,
                      creationDate >= initialCutoff,
                      creationDate <= (addedThrough ?? .now) else { return }
            }
            guard !excluded.contains(asset.localIdentifier) else { return }

            let bytes = resources.reduce(Int64(0)) { $0 + Self.resourceSize($1) }
            descriptors.append(MediaAssetDescriptor(asset: asset, resource: primary, estimatedBytes: bytes, source: .dji))
        }
        PocketLog.info("自动扫描完成，发现待处理素材=\(descriptors.count)，已记录当前素材=\(observedIdentifiers.count)")
        return AssetDiscoveryResult(
            descriptors: descriptors,
            observedIdentifiers: observedIdentifiers,
            sourceAlbumFound: true
        )
    }

    func descriptors(for identifiers: [String]) -> [MediaAssetDescriptor] {
        resolveSelection(identifiers).descriptors
    }

    func resolveSelection(_ identifiers: [String]) -> AssetSelectionResolution {
        let result = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        let djiIDs = sourceAssetIdentifiers()
        let outputIDs = outputAssetIdentifiers()
        var descriptors: [MediaAssetDescriptor] = []
        var outputCount = 0
        var resolvedCount = 0
        result.enumerateObjects { asset, _, _ in
            guard !outputIDs.contains(asset.localIdentifier) else {
                outputCount += 1
                return
            }
            let resources = PHAssetResource.assetResources(for: asset)
            guard let primary = Self.primaryResource(from: resources, for: asset) else { return }
            let bytes = resources.reduce(Int64(0)) { $0 + Self.resourceSize($1) }
            let source: MediaSource = djiIDs.contains(asset.localIdentifier) || Self.looksLikeDJI(filename: primary.originalFilename)
                ? .dji
                : .other
            descriptors.append(MediaAssetDescriptor(asset: asset, resource: primary, estimatedBytes: bytes, source: source))
            resolvedCount += 1
        }
        let unsupportedCount = max(0, identifiers.count - resolvedCount - outputCount)
        PocketLog.info(
            "手动素材解析完成：可处理=\(descriptors.count)，非DJI=\(descriptors.filter { $0.source == .other }.count)，输出副本=\(outputCount)，不可读取=\(unsupportedCount)"
        )
        return AssetSelectionResolution(
            descriptors: descriptors,
            unsupportedCount: unsupportedCount,
            outputCount: outputCount
        )
    }

    func resolvePickerItems(_ items: [PhotosPickerItem]) async -> PickerAssetResolution {
        var identifiers: [String] = []
        var unresolvedCount = 0

        for (index, item) in items.enumerated() {
            if let identifier = item.itemIdentifier, !identifier.isEmpty {
                identifiers.append(identifier)
                PocketLog.debug("选择器素材 \(index + 1)/\(items.count) 直接返回 PhotoKit identifier")
                continue
            }

            let contentTypes = item.supportedContentTypes.map(\.identifier).joined(separator: ",")
            PocketLog.warning(
                "选择器素材 \(index + 1)/\(items.count) 未返回 identifier，尝试通过 PHLivePhoto 资源恢复；类型=\(contentTypes)"
            )
            do {
                guard let livePhoto = try await item.loadTransferable(type: PHLivePhoto.self) else {
                    unresolvedCount += 1
                    PocketLog.warning("选择器素材无法加载为 PHLivePhoto")
                    continue
                }
                let resources = PHAssetResource.assetResources(for: livePhoto)
                let resourceTypes = resources.map { String($0.type.rawValue) }.joined(separator: ",")
                guard let identifier = resources
                    .map(\.assetLocalIdentifier)
                    .first(where: { !$0.isEmpty }) else {
                    unresolvedCount += 1
                    PocketLog.warning("PHLivePhoto 已加载，但资源未提供 assetLocalIdentifier；资源类型=\(resourceTypes)")
                    continue
                }
                identifiers.append(identifier)
                PocketLog.info("已通过 PHLivePhoto 配对资源恢复 PhotoKit identifier；资源数量=\(resources.count)，类型=\(resourceTypes)")
            } catch {
                unresolvedCount += 1
                PocketLog.warning("通过 PHLivePhoto 恢复 identifier 失败：\(error.localizedDescription)")
            }
        }

        var seen = Set<String>()
        let uniqueIdentifiers = identifiers.filter { seen.insert($0).inserted }
        PocketLog.info(
            "选择器 identifier 解析完成：选择=\(items.count)，成功=\(uniqueIdentifiers.count)，失败=\(unresolvedCount)"
        )
        return PickerAssetResolution(identifiers: uniqueIdentifiers, unresolvedCount: unresolvedCount)
    }

    func download(_ descriptor: MediaAssetDescriptor, progress: @escaping (Double) -> Void) async throws -> DownloadedMedia {
        PocketLog.info("开始获取原始资源：\(descriptor.originalFilename)，类型=\(descriptor.kind.rawValue)")
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [descriptor.id], options: nil).firstObject else {
            throw PipelineError.resourceMissing(descriptor.originalFilename)
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let primary = Self.primaryResource(from: resources, for: asset) else {
            throw PipelineError.resourceMissing(descriptor.originalFilename)
        }

        let directory = try temporaryDirectory(for: descriptor.id)
        let primaryURL = directory.appendingPathComponent(Self.safeResourceName(primary))
        try await write(primary, to: primaryURL) { value in
            progress(descriptor.kind == .livePhoto ? value * 0.55 : value)
        }

        var pairedURL: URL?
        if descriptor.kind == .livePhoto {
            guard let paired = resources.first(where: { [.pairedVideo, .fullSizePairedVideo].contains($0.type) }) else {
                throw PipelineError.resourceMissing("Live Photo 动态资源")
            }
            let url = directory.appendingPathComponent(Self.safeResourceName(paired))
            try await write(paired, to: url) { value in
                progress(0.55 + value * 0.45)
            }
            pairedURL = url
        }

        let location = asset.location.map {
            SendableLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude, altitude: $0.altitude)
        }
        let downloaded = DownloadedMedia(
            descriptor: descriptor,
            primaryURL: primaryURL,
            pairedVideoURL: pairedURL,
            creationDate: asset.creationDate,
            location: location
        )
        PocketLog.info("原始资源获取完成：\(descriptor.originalFilename)")
        return downloaded
    }

    func ensureOutputAlbum() async throws {
        if let existing = fetchOutputAlbum() {
            outputAlbum = existing
            PocketLog.debug("已找到输出相簿“\(Self.albumName)”")
            return
        }

        PocketLog.info("创建输出相簿“\(Self.albumName)”")
        var placeholder: PHObjectPlaceholder?
        try await performChanges {
            placeholder = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: Self.albumName).placeholderForCreatedAssetCollection
        }
        guard let identifier = placeholder?.localIdentifier,
              let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PipelineError.saveFailed("无法创建专用相簿")
        }
        outputAlbum = created
    }

    func save(
        result: TranscodeResult,
        downloaded: DownloadedMedia,
        filenames: (primary: String, paired: String?)
    ) async throws -> String {
        PocketLog.info("准备保存输出：\(filenames.primary)")
        try await ensureOutputAlbum()
        guard let album = outputAlbum ?? fetchOutputAlbum() else {
            throw PipelineError.saveFailed("找不到专用相簿")
        }
        if downloaded.descriptor.kind == .livePhoto, result.pairedVideoURL == nil {
            throw PipelineError.resourceMissing("Live Photo 动态输出")
        }

        var placeholder: PHObjectPlaceholder?
        try await performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.creationDate = downloaded.creationDate
            if let location = downloaded.location {
                request.location = CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                    altitude: location.altitude,
                    horizontalAccuracy: -1,
                    verticalAccuracy: -1,
                    timestamp: downloaded.creationDate ?? .now
                )
            }

            let primaryOptions = PHAssetResourceCreationOptions()
            primaryOptions.originalFilename = filenames.primary
            primaryOptions.shouldMoveFile = false
            if #available(iOS 26.0, *) {
                primaryOptions.contentType = downloaded.descriptor.kind == .video ? .quickTimeMovie : .heic
            }

            switch downloaded.descriptor.kind {
            case .photo:
                request.addResource(with: .photo, fileURL: result.primaryURL, options: primaryOptions)
            case .video:
                request.addResource(with: .video, fileURL: result.primaryURL, options: primaryOptions)
            case .livePhoto:
                request.addResource(with: .photo, fileURL: result.primaryURL, options: primaryOptions)
                guard let pairedURL = result.pairedVideoURL else { return }
                let pairedOptions = PHAssetResourceCreationOptions()
                pairedOptions.originalFilename = filenames.paired ?? filenames.primary.replacingOccurrences(of: ".HEIC", with: ".mov")
                if #available(iOS 26.0, *) {
                    pairedOptions.contentType = .quickTimeMovie
                }
                pairedOptions.shouldMoveFile = false
                request.addResource(with: .pairedVideo, fileURL: pairedURL, options: pairedOptions)
            }

            placeholder = request.placeholderForCreatedAsset
            if let placeholder {
                PHAssetCollectionChangeRequest(for: album)?.addAssets([placeholder] as NSArray)
            }
        }
        guard let identifier = placeholder?.localIdentifier else {
            throw PipelineError.saveFailed("PhotoKit 未返回输出标识")
        }
        if downloaded.descriptor.kind == .livePhoto {
            do {
                try validateSavedLivePhoto(identifier: identifier)
            } catch {
                let invalidAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                try? await performChanges {
                    PHAssetChangeRequest.deleteAssets(invalidAsset)
                }
                throw error
            }
        }
        PocketLog.info("输出保存成功：\(filenames.primary)，asset=\(identifier)")
        return identifier
    }

    func validateSavedOutput(identifier: String, kind: MediaKind) throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else {
            throw PipelineError.validationFailed("压缩输出已不存在，请重新转换后再删除原片")
        }

        let resources = PHAssetResource.assetResources(for: asset)
        switch kind {
        case .photo:
            guard asset.mediaType == .image,
                  !asset.mediaSubtypes.contains(.photoLive),
                  resources.contains(where: { [.photo, .fullSizePhoto].contains($0.type) }) else {
                throw PipelineError.validationFailed("压缩输出的照片资源无法核验，请重新转换后再删除原片")
            }
        case .video:
            guard asset.mediaType == .video,
                  resources.contains(where: { [.video, .fullSizeVideo].contains($0.type) }) else {
                throw PipelineError.validationFailed("压缩输出的视频资源无法核验，请重新转换后再删除原片")
            }
        case .livePhoto:
            guard asset.mediaType == .image,
                  asset.mediaSubtypes.contains(.photoLive),
                  resources.contains(where: { [.photo, .fullSizePhoto].contains($0.type) }),
                  resources.contains(where: { [.pairedVideo, .fullSizePairedVideo].contains($0.type) }) else {
                throw PipelineError.validationFailed("压缩输出的 Live Photo 配对资源无法核验，请重新转换后再删除原片")
            }
        }
        PocketLog.debug("已重新核验压缩输出资源，类型=\(kind.rawValue)")
    }

    func deleteAssets(with identifiers: [String]) async throws {
        PocketLog.info("请求删除原片数量=\(identifiers.count)")
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
        guard assets.count > 0 else { return }
        try await performChanges {
            PHAssetChangeRequest.deleteAssets(assets)
        }
        PocketLog.info("原片删除完成，数量=\(assets.count)")
    }

    func cleanupTemporaryFiles(for identifier: String) {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PocketHelper", isDirectory: true)
        let directory = base.appendingPathComponent(FilenameGenerator.sanitize(identifier), isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ resource: PHAssetResource, to url: URL, progress: @escaping (Double) -> Void) async throws {
        try? FileManager.default.removeItem(at: url)
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { value in progress(value) }
        let requestState = ResourceDataRequestState()
        let manager = resourceManager
        do {
            try await withTaskCancellationHandler(operation: {
                try Task.checkCancellation()
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                        continuation.resume(throwing: PipelineError.downloadFailed("无法创建临时文件"))
                        return
                    }
                    let fileHandle: FileHandle
                    do {
                        fileHandle = try FileHandle(forWritingTo: url)
                    } catch {
                        continuation.resume(throwing: PipelineError.downloadFailed(error.localizedDescription))
                        return
                    }
                    requestState.configure(continuation: continuation, fileHandle: fileHandle)
                    let requestID = resourceManager.requestData(
                        for: resource,
                        options: options,
                        dataReceivedHandler: { data in
                            requestState.append(data, manager: manager)
                        },
                        completionHandler: { error in
                            if let error {
                                requestState.finish(error: PipelineError.downloadFailed(error.localizedDescription))
                            } else {
                                requestState.finish(error: nil)
                            }
                        }
                    )
                    requestState.setRequestID(requestID, manager: manager)
                }
            }, onCancel: {
                requestState.cancel(using: manager)
            })
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    private func temporaryDirectory(for identifier: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("PocketHelper", isDirectory: true)
        let directory = base.appendingPathComponent(FilenameGenerator.sanitize(identifier), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func fetchOutputAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", Self.albumName)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: options).firstObject
    }

    private func fetchSourceAlbum() -> PHAssetCollection? {
        let collections = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil)
        var match: PHAssetCollection?
        collections.enumerateObjects { collection, _, stop in
            if collection.localizedTitle?.localizedCaseInsensitiveCompare(Self.sourceAlbumName) == .orderedSame {
                match = collection
                stop.pointee = true
            }
        }
        return match
    }

    private func outputAssetIdentifiers() -> Set<String> {
        guard let album = outputAlbum ?? fetchOutputAlbum() else { return [] }
        outputAlbum = album
        let assets = PHAsset.fetchAssets(in: album, options: nil)
        var identifiers = Set<String>()
        assets.enumerateObjects { asset, _, _ in
            identifiers.insert(asset.localIdentifier)
        }
        return identifiers
    }

    private func sourceAssetIdentifiers() -> Set<String> {
        guard let album = fetchSourceAlbum() else { return [] }
        let assets = PHAsset.fetchAssets(in: album, options: nil)
        var identifiers = Set<String>()
        assets.enumerateObjects { asset, _, _ in
            identifiers.insert(asset.localIdentifier)
        }
        return identifiers
    }

    private func performChanges(_ changes: @escaping () -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PipelineError.saveFailed("未知的 PhotoKit 错误"))
                }
            }
        }
    }

    private func validateSavedLivePhoto(identifier: String) throws {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject,
              asset.mediaSubtypes.contains(.photoLive) else {
            throw PipelineError.saveFailed("PhotoKit 未将输出识别为 Live Photo")
        }
        let resources = PHAssetResource.assetResources(for: asset)
        guard resources.contains(where: { [.photo, .fullSizePhoto].contains($0.type) }),
              resources.contains(where: { [.pairedVideo, .fullSizePairedVideo].contains($0.type) }) else {
            throw PipelineError.saveFailed("Live Photo 保存后缺少静态或动态配对资源")
        }
        PocketLog.info("Live Photo 保存校验通过：asset=\(identifier)")
    }

    private static func primaryResource(from resources: [PHAssetResource], for asset: PHAsset) -> PHAssetResource? {
        if asset.mediaSubtypes.contains(.photoLive) {
            return resources.first(where: { [.photo, .fullSizePhoto].contains($0.type) })
        }
        if asset.mediaType == .video {
            return resources.first(where: { [.video, .fullSizeVideo].contains($0.type) })
        }
        return resources.first(where: { [.photo, .fullSizePhoto].contains($0.type) })
    }

    private static func safeResourceName(_ resource: PHAssetResource) -> String {
        let original = FilenameGenerator.sanitize(URL(fileURLWithPath: resource.originalFilename).deletingPathExtension().lastPathComponent)
        let fallback: String
        if #available(iOS 26.0, *) {
            fallback = resource.contentType.preferredFilenameExtension ?? "dat"
        } else {
            fallback = UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "dat"
        }
        let ext = URL(fileURLWithPath: resource.originalFilename).pathExtension.isEmpty
            ? fallback
            : URL(fileURLWithPath: resource.originalFilename).pathExtension
        return "\(original).\(ext)"
    }

    private static func resourceSize(_ resource: PHAssetResource) -> Int64 {
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            return Int64(resource.dataSize ?? 0)
        }
        #endif
        return 0
    }

    private static func looksLikeDJI(filename: String) -> Bool {
        let stem = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent.lowercased()
        return stem.hasPrefix("dji_") || stem.hasPrefix("dji-") || stem.contains("dji_mimo")
    }
}
