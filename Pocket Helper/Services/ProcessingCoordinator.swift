import BackgroundTasks
import Combine
import Foundation
import Photos
import PhotosUI
import SwiftData
import SwiftUI

@MainActor
final class ProcessingCoordinator: ObservableObject {
    static let backgroundTaskPattern = "com.jilllees.djihelper.transcode.*"
    nonisolated static let automaticScanCooldown: TimeInterval = 45
    private static let persistedBackgroundIdentifiersKey = "PocketHelper.pendingBackgroundTaskIdentifiers"

    @Published private(set) var authorizationStatus: PHAuthorizationStatus
    @Published private(set) var isScanning = false
    @Published private(set) var isImportingSelection = false
    @Published private(set) var isProcessing = false
    @Published private(set) var isQueuePaused = false
    @Published private(set) var overallProgress = 0.0
    @Published private(set) var currentFilename: String?
    @Published var pendingInitialDescriptors: [MediaAssetDescriptor] = []
    @Published private(set) var pendingScanTitle = "最近添加的素材"
    @Published private(set) var pendingNonDJICount = 0
    @Published var showsInitialPreview = false
    @Published private(set) var deleteConfirmationRequestID: UUID?
    @Published private(set) var experimentalVideoConfirmation: ExperimentalVideoConfirmation?

    let settings: AppSettings
    let messageCenter: MessageCenter

    private let photoLibrary: PhotoLibraryService
    private let transcoder: MediaTranscoder
    private var modelContext: ModelContext?
    private var processingTask: Task<Void, Never>?
    private var backgroundTaskStorage: AnyObject?
    private var pendingLaunchedBackgroundTaskStorage: AnyObject?
    private var submittedBackgroundIdentifier: String?
    private var registeredBackgroundIdentifiers = Set<String>()
    private var currentJobIdentifier: String?
    private var pendingRemovalIdentifier: String?
    private var lastAutomaticScanDate: Date?
    private var experimentalConfirmationContinuation: CheckedContinuation<Bool, Never>?
    private var confirmedExperimentalVideoIdentifiers = Set<String>()

    init(
        settings: AppSettings,
        messageCenter: MessageCenter,
        photoLibrary: PhotoLibraryService,
        transcoder: MediaTranscoder
    ) {
        self.settings = settings
        self.messageCenter = messageCenter
        self.photoLibrary = photoLibrary
        self.transcoder = transcoder
        authorizationStatus = photoLibrary.authorizationStatus
        registerPersistedBackgroundHandlers()
    }

    func configure(context: ModelContext) {
        guard modelContext == nil else { return }
        modelContext = context
        messageCenter.configure(context: context)
        normalizeInterruptedJobs()
        PocketLog.info("处理协调器配置完成，后台 handler 数量=\(registeredBackgroundIdentifiers.count)")
        if #available(iOS 26.0, *), pendingLaunchedBackgroundTask != nil {
            pendingLaunchedBackgroundTask = nil
            startProcessingIfNeeded()
        }
    }

    func requestAccessAndScan() async {
        PocketLog.info("用户触发照片授权与首次扫描")
        authorizationStatus = await photoLibrary.requestAuthorization()
        guard authorizationStatus == .authorized || authorizationStatus == .limited else {
            messageCenter.post(
                severity: .error,
                stage: "权限",
                title: "无法访问照片",
                details: "请在系统设置中允许 \(AppIdentity.displayName) 访问照片。",
                action: .openSettings
            )
            return
        }
        await scanForNewAssets(force: true)
    }

    func scanForNewAssets(force: Bool = false) async {
        guard !isScanning, let context = modelContext else { return }
        authorizationStatus = photoLibrary.authorizationStatus
        guard authorizationStatus == .authorized else { return }
        let now = Date()
        guard force || Self.shouldPerformAutomaticScan(lastScan: lastAutomaticScanDate, now: now) else {
            let remaining = max(0, Self.automaticScanCooldown - now.timeIntervalSince(lastAutomaticScanDate ?? now))
            PocketLog.debug("跳过重复自动扫描，冷却剩余约 \(Int(remaining.rounded(.up))) 秒")
            return
        }
        lastAutomaticScanDate = now
        isScanning = true
        defer { isScanning = false }
        let addedAfter = Self.automaticScanStartDate(
            lastDetection: settings.lastAutomaticDetectionDate,
            now: now
        )
        let checkpoint = settings.automaticScanCheckpoint
        let isInitialBaseline = !checkpoint.baselineEstablished
        PocketLog.info("开始自动扫描 DJI Album 继上次检测之后新增的\(settings.autoDetectionScope.title)")

        let existing = (try? context.fetch(FetchDescriptor<MediaJob>())) ?? []
        let discovery = await photoLibrary.discoverDJIAssets(
            excluding: Set(existing.map(\.sourceLocalIdentifier)),
            addedAfter: addedAfter,
            addedThrough: now,
            seenIdentifiers: checkpoint.seenIdentifiers,
            includePreviouslySeen: isInitialBaseline,
            scope: settings.autoDetectionScope
        )
        var updatedCheckpoint = checkpoint
        // An unavailable or empty source album is still a valid empty baseline.
        // Future assets are then recognized by identifier, regardless of capture date.
        updatedCheckpoint.record(observedIdentifiers: discovery.observedIdentifiers)
        settings.automaticScanCheckpoint = updatedCheckpoint
        settings.lastAutomaticDetectionDate = now
        let descriptors = discovery.descriptors
        guard !descriptors.isEmpty else {
            PocketLog.info("扫描未发现新的待处理素材")
            return
        }
        handleDiscoveredDescriptors(descriptors, title: "最近添加的素材", context: context)
    }

    func resetDetectionAndScanRecentWeek() async {
        guard !isScanning, let context = modelContext else { return }
        authorizationStatus = photoLibrary.authorizationStatus
        guard authorizationStatus == .authorized else {
            messageCenter.post(
                severity: .warning,
                stage: "检测",
                title: "需要完整照片权限",
                details: "重新检测最近 7 天需要完整访问 DJI Album。",
                action: .openSettings
            )
            return
        }

        isScanning = true
        defer { isScanning = false }
        PocketLog.info("用户从设置重置检测，扫描 DJI Album 最近 7 天未处理\(settings.autoDetectionScope.title)")
        let existing = (try? context.fetch(FetchDescriptor<MediaJob>())) ?? []
        let discovery = await photoLibrary.discoverDJIAssets(
            excluding: Set(existing.map(\.sourceLocalIdentifier)),
            window: .recentSevenDays,
            addedThrough: Date(),
            recordObservedIdentifiers: false,
            scope: settings.autoDetectionScope
        )
        let descriptors = discovery.descriptors
        recordPresentedForDetection(descriptors)
        guard !descriptors.isEmpty else {
            PocketLog.info("重置检测完成，最近 7 天没有未处理\(settings.autoDetectionScope.title)")
            messageCenter.post(
                severity: .warning,
                stage: "检测",
                title: "没有发现新素材",
                details: "DJI Album 最近 7 天内没有尚未检测过的\(settings.autoDetectionScope.title)。",
                showsBanner: true
            )
            return
        }

        handleDiscoveredDescriptors(descriptors, title: "最近 7 天的素材", context: context)
    }

    /// A reset scan is an explicit recovery action. Persist only the IDs shown
    /// in its preview, so skipping them is respected without consuming older
    /// assets outside the requested seven-day window.
    private func recordPresentedForDetection(_ descriptors: [MediaAssetDescriptor]) {
        guard !descriptors.isEmpty else { return }
        var checkpoint = settings.automaticScanCheckpoint
        checkpoint.record(observedIdentifiers: Set(descriptors.map(\.id)))
        settings.automaticScanCheckpoint = checkpoint
    }

    func confirmInitialBatch() {
        guard let context = modelContext else { return }
        PocketLog.info("用户确认开始转换，数量=\(pendingInitialDescriptors.count)")
        enqueue(pendingInitialDescriptors, context: context)
        pendingInitialDescriptors = []
        pendingScanTitle = "最近添加的素材"
        pendingNonDJICount = 0
        showsInitialPreview = false
        settings.completedInitialScan = true
        isQueuePaused = false
        startProcessingIfNeeded()
    }

    func completeInitialScanWithoutProcessing() {
        pendingInitialDescriptors = []
        pendingScanTitle = "最近添加的素材"
        pendingNonDJICount = 0
        showsInitialPreview = false
        settings.completedInitialScan = true
    }

    func importPickedIdentifiers(_ identifiers: [String]) {
        guard let context = modelContext else { return }
        PocketLog.info("用户手动选择素材，identifier 数量=\(identifiers.count)")
        let existing = (try? context.fetch(FetchDescriptor<MediaJob>())) ?? []
        let existingIDs = Set(existing.map(\.sourceLocalIdentifier))
        let resolution = photoLibrary.resolveSelection(identifiers)
        let alreadyQueuedCount = resolution.descriptors.filter { existingIDs.contains($0.id) }.count
        let descriptors = resolution.descriptors.filter { !existingIDs.contains($0.id) }

        if resolution.outputCount > 0 || resolution.unsupportedCount > 0 || alreadyQueuedCount > 0 {
            var reasons: [String] = []
            if alreadyQueuedCount > 0 { reasons.append("\(alreadyQueuedCount) 个已在队列或历史记录中") }
            if resolution.outputCount > 0 { reasons.append("\(resolution.outputCount) 个是 \(AppIdentity.displayName) 输出") }
            if resolution.unsupportedCount > 0 { reasons.append("\(resolution.unsupportedCount) 个无法读取") }
            messageCenter.post(
                severity: .warning,
                stage: "选择素材",
                title: "已忽略部分素材",
                details: reasons.joined(separator: "，") + "。",
                showsBanner: true
            )
        }

        guard !descriptors.isEmpty else {
            if resolution.outputCount == 0, resolution.unsupportedCount == 0, alreadyQueuedCount == 0 {
                messageCenter.post(
                    severity: .warning,
                    stage: "选择素材",
                    title: "没有可转换的素材",
                    details: "所选项目无法作为照片、视频或 Live Photo 读取。"
                )
            }
            PocketLog.warning("手动选择没有新增可处理素材")
            return
        }

        let nonDJICount = descriptors.filter { $0.source == .other }.count
        if nonDJICount > 0 {
            PocketLog.info("手动选择包含非 DJI/Pocket 素材，数量=\(nonDJICount)，强制等待确认")
        }
        handleDiscoveredDescriptors(
            descriptors,
            title: "确认所选素材",
            context: context,
            requiresConfirmation: nonDJICount > 0
        )
    }

    func importPickedItems(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty, !isImportingSelection else { return }
        isImportingSelection = true
        defer { isImportingSelection = false }
        PocketLog.info("开始解析 PhotosPicker 素材，数量=\(items.count)")

        let resolution = await photoLibrary.resolvePickerItems(items)
        if resolution.unresolvedCount > 0 {
            messageCenter.post(
                severity: .warning,
                stage: "选择素材",
                title: "部分素材无法读取",
                details: "有 \(resolution.unresolvedCount) 个项目没有可用的照片图库标识。请确认素材已完整下载到系统相册并允许完整照片访问。",
                action: .openSettings
            )
        }
        guard !resolution.identifiers.isEmpty else {
            if resolution.unresolvedCount == 0 {
                messageCenter.post(
                    severity: .warning,
                    stage: "选择素材",
                    title: "没有可转换的素材",
                    details: "系统选择器没有返回可读取的照片、视频或 Live Photo。"
                )
            }
            return
        }
        importPickedIdentifiers(resolution.identifiers)
    }

    func startProcessingIfNeeded() {
        guard processingTask == nil else {
            PocketLog.debug("处理队列已在运行，忽略重复启动")
            return
        }
        guard allJobs().contains(where: { [.queued, .paused].contains($0.state) }) else {
            PocketLog.debug("没有可执行的队列任务")
            return
        }
        isQueuePaused = false
        PocketLog.info("启动串行处理队列")
        processingTask = Task { [weak self] in
            await self?.processQueue()
        }
    }

    func applicationWillResignActive() {
        guard isProcessing else { return }
        if experimentalVideoConfirmation != nil {
            PocketLog.info("App 离开前台，取消等待中的高帧率实验性确认")
            declineExperimentalVideoConversion()
            return
        }
        if #available(iOS 26.0, *) {
            PocketLog.info("App 即将进入后台，自动启用持续后台任务")
            submitContinuedProcessingTask()
        } else {
            PocketLog.info("当前系统不支持持续后台压缩；返回 App 后可继续处理")
        }
    }

    func pauseProcessing() {
        PocketLog.warning("用户请求暂停处理")
        isQueuePaused = true
        if experimentalVideoConfirmation != nil {
            declineExperimentalVideoConversion()
        }
        processingTask?.cancel()
    }

    func startQueuedJobs() {
        PocketLog.info("用户手动开始或继续处理队列")
        isQueuePaused = false
        startProcessingIfNeeded()
    }

    func resetJob(jobIdentifier: String) {
        guard let job = job(with: jobIdentifier), !job.state.isActive else { return }
        PocketLog.info("重置队列素材：\(job.originalFilename)")
        job.state = .queued
        job.progress = 0
        job.errorDetails = nil
        job.completedAt = nil
        try? modelContext?.save()
    }

    var canClearPendingQueue: Bool {
        let pending = allJobs().filter { $0.state.isInProcessingQueue }
        return !isQueuePaused && !pending.isEmpty && pending.allSatisfy { $0.state == .queued }
    }

    func resetPendingJobs() {
        // Cancellation must finish before jobs or their working files can be removed.
        guard processingTask == nil, !isProcessing, !isScanning, !isImportingSelection,
              let context = modelContext else { return }
        let resettable = allJobs().filter { $0.state.isInProcessingQueue }
        guard !resettable.isEmpty,
              resettable.allSatisfy({ [.queued, .paused, .failed].contains($0.state) }) else { return }

        if canClearPendingQueue {
            let identifiers = resettable.map(\.sourceLocalIdentifier)
            for job in resettable { context.delete(job) }
            try? context.save()
            for identifier in identifiers {
                photoLibrary.cleanupTemporaryFiles(for: identifier)
                confirmedExperimentalVideoIdentifiers.remove(identifier)
            }
            PocketLog.info("清空待处理队列，数量=\(identifiers.count)")
            return
        }

        for job in resettable {
            job.state = .queued
            job.progress = 0
            job.errorDetails = nil
            job.completedAt = nil
        }
        isQueuePaused = false
        try? context.save()
        PocketLog.info("重置处理队列，数量=\(resettable.count)")
    }

    func removeJob(jobIdentifier: String) {
        guard let context = modelContext, let job = job(with: jobIdentifier) else { return }
        PocketLog.info("将素材移出队列：\(job.originalFilename)")
        if currentJobIdentifier == jobIdentifier, isProcessing {
            pendingRemovalIdentifier = jobIdentifier
            isQueuePaused = true
            processingTask?.cancel()
            return
        }
        context.delete(job)
        photoLibrary.cleanupTemporaryFiles(for: jobIdentifier)
        try? context.save()
    }

    func clearHistory() {
        guard let context = modelContext else { return }
        let historyJobs = allJobs().filter { $0.state.isHistoryRecord }
        for job in historyJobs {
            context.delete(job)
            photoLibrary.cleanupTemporaryFiles(for: job.sourceLocalIdentifier)
        }
        try? context.save()
        PocketLog.info("清空历史记录，数量=\(historyJobs.count)")
    }

    func retry(jobIdentifier: String) {
        guard let job = job(with: jobIdentifier) else { return }
        PocketLog.info("重新处理素材：\(job.originalFilename)")
        job.errorDetails = nil
        job.state = .queued
        job.progress = 0
        try? modelContext?.save()
        if settings.autoConvert { startProcessingIfNeeded() }
    }

    var readyToDeleteCount: Int {
        jobs(matching: .readyToDelete).count
    }

    func requestDeleteConfirmation() {
        guard readyToDeleteCount > 0 else { return }
        deleteConfirmationRequestID = UUID()
    }

    func keepReadyOriginals() {
        guard let context = modelContext else { return }
        let candidates = jobs(matching: .readyToDelete)
        guard !candidates.isEmpty else { return }
        let previousUpdateDates = candidates.map(\.updatedAt)
        for job in candidates {
            // Retain the record so future scans and imports still recognize the processed source.
            job.state = .completed
        }
        do {
            try context.save()
            deleteConfirmationRequestID = nil
            PocketLog.info("用户选择保留原片，已完成处理数量=\(candidates.count)")
        } catch {
            for (job, updatedAt) in zip(candidates, previousUpdateDates) {
                job.state = .readyToDelete
                job.updatedAt = updatedAt
            }
            messageCenter.post(
                severity: .error,
                stage: "保留原片",
                title: "未能保存保留原片的选择",
                details: error.localizedDescription
            )
        }
    }

    func confirmExperimentalVideoConversion() {
        guard let confirmation = experimentalVideoConfirmation else { return }
        confirmedExperimentalVideoIdentifiers.insert(confirmation.id)
        experimentalVideoConfirmation = nil
        experimentalConfirmationContinuation?.resume(returning: true)
        experimentalConfirmationContinuation = nil
    }

    func declineExperimentalVideoConversion() {
        experimentalVideoConfirmation = nil
        experimentalConfirmationContinuation?.resume(returning: false)
        experimentalConfirmationContinuation = nil
    }

    nonisolated static func shouldPerformAutomaticScan(lastScan: Date?, now: Date) -> Bool {
        guard let lastScan else { return true }
        return now.timeIntervalSince(lastScan) >= automaticScanCooldown
    }

    nonisolated static func automaticScanStartDate(
        lastDetection: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        lastDetection ?? calendar.startOfDay(for: now)
    }

    func deleteReadyOriginals() async {
        let candidates = jobs(matching: .readyToDelete)
        guard !candidates.isEmpty else { return }

        var deletable: [MediaJob] = []
        for job in candidates {
            guard let outputIdentifier = job.outputLocalIdentifier else {
                markOutputValidationFailure(job, details: "压缩输出缺少照片图库标识，请重新转换后再删除原片。")
                continue
            }
            do {
                try photoLibrary.validateSavedOutput(identifier: outputIdentifier, kind: job.mediaKind)
                deletable.append(job)
            } catch {
                markOutputValidationFailure(job, details: error.localizedDescription)
            }
        }
        try? modelContext?.save()
        guard !deletable.isEmpty else { return }

        do {
            try await photoLibrary.deleteAssets(with: deletable.map(\.sourceLocalIdentifier))
            for job in deletable {
                job.state = .completed
                job.completedAt = .now
            }
            try? modelContext?.save()
        } catch {
            messageCenter.post(
                severity: .error,
                stage: "删除",
                title: "无法删除原片",
                details: error.localizedDescription
            )
        }
    }

    private func markOutputValidationFailure(_ job: MediaJob, details: String) {
        job.state = .failed
        job.retryCount += 1
        job.errorDetails = details
        messageCenter.post(
            severity: .error,
            jobIdentifier: job.sourceLocalIdentifier,
            stage: "删除",
            title: "已保留 \(job.originalFilename) 原片",
            details: "删除前未能确认压缩输出仍存在或配对有效。\(details)",
            action: .retry
        )
        PocketLog.warning("删除前输出复核未通过，已保留原片，类型=\(job.mediaKind.rawValue)")
    }

    private func processQueue() async {
        guard let context = modelContext else {
            processingTask = nil
            return
        }
        isProcessing = true
        defer {
            isProcessing = false
            currentFilename = nil
            overallProgress = 0
            processingTask = nil
            currentJobIdentifier = nil
        }

        let candidateIdentifiers = allJobs()
            .filter { [.queued, .paused].contains($0.state) }
            .map(\.sourceLocalIdentifier)
        var wasInterrupted = false
        PocketLog.info("队列开始执行，任务数量=\(candidateIdentifiers.count)")
        setBackgroundProgressTotal(candidateIdentifiers.count)

        for (index, jobIdentifier) in candidateIdentifiers.enumerated() {
            guard let job = job(with: jobIdentifier) else { continue }
            if Task.isCancelled {
                wasInterrupted = true
                if job.state.isActive { job.state = .paused }
                try? context.save()
                break
            }
            currentFilename = job.originalFilename
            currentJobIdentifier = jobIdentifier
            let totalCount = candidateIdentifiers.count
            let coordinator = self
            let jobStartedAt = Date()
            PocketLog.info("开始任务 \(index + 1)/\(totalCount)：\(job.originalFilename)")
            do {
                guard let descriptor = photoLibrary.descriptors(for: [job.sourceLocalIdentifier]).first else {
                    throw PipelineError.resourceMissing(job.originalFilename)
                }
                job.state = .downloading
                PocketLog.debug("任务阶段[下载]：\(job.originalFilename)")
                job.progress = 0
                try? context.save()
                updateBackgroundTitle(total: candidateIdentifiers.count, filename: job.originalFilename, subtitle: "正在从 iCloud 获取原片")

                let downloadStartedAt = Date()
                let downloaded = try await photoLibrary.download(descriptor) { value in
                    coordinator.updateProgress(for: jobIdentifier, value: value * 0.18, index: index, total: totalCount)
                }
                PocketLog.performance("下载", durationMilliseconds: Self.elapsedMilliseconds(since: downloadStartedAt))
                try Task.checkCancellation()

                if let profile = try await transcoder.videoEncodingProfile(
                    for: downloaded,
                    quality: settings.videoQuality
                ), let frameRateMode = profile.experimentalFrameRate,
                   !confirmedExperimentalVideoIdentifiers.contains(jobIdentifier) {
                    let shouldContinue = await requestExperimentalVideoConfirmation(
                        job: job,
                        frameRateMode: frameRateMode,
                        targetBitrate: profile.targetBitrate
                    )
                    guard shouldContinue else {
                        PocketLog.info("用户暂不进行 4K\(frameRateMode) 实验性转换：\(job.originalFilename)")
                        job.state = .paused
                        job.errorDetails = "4K\(frameRateMode) 高帧率转换属于实验性功能，需要再次开始并确认。"
                        try? context.save()
                        photoLibrary.cleanupTemporaryFiles(for: jobIdentifier)
                        isQueuePaused = true
                        wasInterrupted = true
                        break
                    }
                }

                job.state = .transcoding
                PocketLog.debug("任务阶段[转码]：\(job.originalFilename)")
                updateBackgroundTitle(total: candidateIdentifiers.count, filename: job.originalFilename, subtitle: "正在压缩")

                let transcodeStartedAt = Date()
                let result = try await transcoder.transcode(
                    downloaded,
                    videoQuality: settings.videoQuality,
                    photoQuality: settings.photoQuality,
                    liveResolution: settings.liveResolution
                ) { [coordinator] value in
                    Task { @MainActor [coordinator] in
                        coordinator.updateProgress(for: jobIdentifier, value: 0.18 + value * 0.67, index: index, total: totalCount)
                    }
                }
                PocketLog.performance("转码与校验", durationMilliseconds: Self.elapsedMilliseconds(since: transcodeStartedAt))

                try Task.checkCancellation()
                job.state = .validating
                PocketLog.debug("任务阶段[校验]：\(job.originalFilename)")
                job.progress = 0.9
                let filenames = makeFilenames(for: job)
                job.state = .saving
                PocketLog.debug("任务阶段[保存]：\(job.originalFilename)，输出名称=\(filenames.primary)")
                updateBackgroundTitle(total: candidateIdentifiers.count, filename: job.originalFilename, subtitle: "正在保存到相册")
                try Task.checkCancellation()
                let saveStartedAt = Date()
                let outputID = try await photoLibrary.save(result: result, downloaded: downloaded, filenames: filenames)
                PocketLog.performance("PhotoKit保存", durationMilliseconds: Self.elapsedMilliseconds(since: saveStartedAt))

                job.outputLocalIdentifier = outputID
                job.outputFilename = filenames.primary
                job.originalBytes = result.originalBytes
                job.outputBytes = result.outputBytes
                job.progress = 1
                job.completedAt = .now
                job.state = settings.deleteOriginals ? .readyToDelete : .completed
                try context.save()
                photoLibrary.cleanupTemporaryFiles(for: job.sourceLocalIdentifier)
                PocketLog.performance(
                    "任务总耗时",
                    durationMilliseconds: Self.elapsedMilliseconds(since: jobStartedAt),
                    originalBytes: result.originalBytes,
                    outputBytes: result.outputBytes,
                    bytesSaved: result.bytesSaved
                )

                for warning in result.warnings {
                    messageCenter.post(
                        severity: .warning,
                        jobIdentifier: job.sourceLocalIdentifier,
                        stage: "元数据",
                        title: "部分私有元数据未复制",
                        details: warning,
                        showsBanner: false
                    )
                }
                updateProgress(for: job.sourceLocalIdentifier, value: 1, index: index, total: candidateIdentifiers.count)
            } catch is CancellationError {
                wasInterrupted = true
                if pendingRemovalIdentifier == jobIdentifier {
                    PocketLog.info("当前素材取消并移出队列：\(job.originalFilename)")
                    context.delete(job)
                    pendingRemovalIdentifier = nil
                } else {
                    PocketLog.warning("任务取消并暂停：\(job.originalFilename)")
                    job.state = .paused
                    job.errorDetails = PipelineError.cancelled.localizedDescription
                }
                try? context.save()
                photoLibrary.cleanupTemporaryFiles(for: jobIdentifier)
                break
            } catch PipelineError.noSavings {
                PocketLog.info("任务跳过（无空间收益）：\(job.originalFilename)")
                job.state = .skipped
                job.progress = 1
                job.completedAt = .now
                job.errorDetails = PipelineError.noSavings.localizedDescription
                try? context.save()
                photoLibrary.cleanupTemporaryFiles(for: job.sourceLocalIdentifier)
                messageCenter.post(
                    severity: .warning,
                    jobIdentifier: job.sourceLocalIdentifier,
                    stage: "压缩",
                    title: "已跳过 \(job.originalFilename)",
                    details: "输出没有比原片更小，因此没有保存副本。",
                    showsBanner: false
                )
            } catch {
                let failedStage = job.state.title
                PocketLog.error("任务失败：\(job.originalFilename)，阶段=\(failedStage)，错误=\(error.localizedDescription)")
                job.state = .failed
                job.retryCount += 1
                job.errorDetails = error.localizedDescription
                try? context.save()
                photoLibrary.cleanupTemporaryFiles(for: job.sourceLocalIdentifier)
                messageCenter.post(
                    severity: .error,
                    jobIdentifier: job.sourceLocalIdentifier,
                    stage: failedStage,
                    title: "\(job.originalFilename) 处理失败",
                    details: error.localizedDescription,
                    errorCode: String(describing: type(of: error)),
                    action: .retry
                )
            }
        }

        let success = !wasInterrupted && !candidateIdentifiers.contains(where: { job(with: $0)?.state == .failed })
        let completedCount = candidateIdentifiers.filter {
            guard let state = job(with: $0)?.state else { return false }
            return state == .completed || state == .readyToDelete
        }.count
        let failedCount = candidateIdentifiers.filter { job(with: $0)?.state == .failed }.count
        if wasInterrupted { isQueuePaused = true }
        PocketLog.info("队列执行结束，success=\(success)，可删除原片=\(readyToDeleteCount)")
        let finalTitle = wasInterrupted ? "压缩已暂停" : (success ? "压缩完成" : "部分素材处理失败")
        let finalSubtitle = wasInterrupted ? "打开 App 可继续处理" : (success ? "结果已保存到「\(PhotoLibraryService.albumName)」相簿" : "打开 App 查看消息中心")
        await completeBackgroundProcessing(
            title: finalTitle,
            subtitle: finalSubtitle,
            completedCount: completedCount,
            failedCount: failedCount,
            wasInterrupted: wasInterrupted,
            success: success
        )
    }

    private func updateProgress(for identifier: String, value: Double, index: Int, total: Int) {
        job(with: identifier)?.progress = min(max(value, 0), 1)
        overallProgress = total > 0 ? (Double(index) + value) / Double(total) : 0
        setBackgroundProgress(overallProgress, total: total)
    }

    private func handleDiscoveredDescriptors(
        _ descriptors: [MediaAssetDescriptor],
        title: String,
        context: ModelContext,
        requiresConfirmation: Bool = false
    ) {
        let nonDJICount = descriptors.filter { $0.source == .other }.count
        if settings.autoConvert, !requiresConfirmation {
            PocketLog.info("自动转换已开启，素材直接加入队列，数量=\(descriptors.count)")
            enqueue(descriptors, context: context)
            startProcessingIfNeeded()
        } else {
            PocketLog.info("扫描完成，等待用户开始转换，数量=\(descriptors.count)")
            pendingScanTitle = title
            pendingNonDJICount = nonDJICount
            pendingInitialDescriptors = descriptors
            showsInitialPreview = true
        }
    }

    private func requestExperimentalVideoConfirmation(
        job: MediaJob,
        frameRateMode: Int,
        targetBitrate: Double
    ) async -> Bool {
        guard UIApplication.shared.applicationState == .active else { return false }
        experimentalVideoConfirmation = ExperimentalVideoConfirmation(
            id: job.sourceLocalIdentifier,
            filename: job.originalFilename,
            frameRateMode: frameRateMode,
            targetBitrate: targetBitrate
        )
        return await withCheckedContinuation { continuation in
            experimentalConfirmationContinuation = continuation
        }
    }

    private func enqueue(_ descriptors: [MediaAssetDescriptor], context: ModelContext) {
        let existingIDs = Set(allJobs().map(\.sourceLocalIdentifier))
        for descriptor in descriptors where !existingIDs.contains(descriptor.id) {
            context.insert(MediaJob(descriptor: descriptor, state: .queued))
        }
        try? context.save()
    }

    private func makeFilenames(for job: MediaJob) -> (primary: String, paired: String?) {
        let stem = FilenameGenerator.stem(
            originalFilename: job.originalFilename,
            kind: job.mediaKind,
            rule: settings.filenameRule,
            suffix: settings.filenameSuffix,
            template: settings.filenameTemplate,
            counter: settings.automaticCounter,
            date: .now
        )
        settings.automaticCounter += 1
        let used = Set(allJobs().compactMap(\.outputFilename))
        var candidate = stem
        var index = 2
        while used.contains(FilenameGenerator.filenames(stem: candidate, kind: job.mediaKind).primary) {
            candidate = "\(stem)_\(index)"
            index += 1
        }
        return FilenameGenerator.filenames(stem: candidate, kind: job.mediaKind)
    }

    private func normalizeInterruptedJobs() {
        guard let context = modelContext else { return }
        var normalized = false
        for job in allJobs() where job.state.isActive {
            job.state = .paused
            normalized = true
        }
        if normalized { isQueuePaused = true }
        try? context.save()
    }

    private func allJobs() -> [MediaJob] {
        guard let context = modelContext else { return [] }
        var descriptor = FetchDescriptor<MediaJob>(sortBy: [SortDescriptor(\.createdAt)])
        descriptor.includePendingChanges = true
        return (try? context.fetch(descriptor)) ?? []
    }

    private func jobs(matching state: ProcessingState) -> [MediaJob] {
        allJobs().filter { $0.state == state }
    }

    private func job(with identifier: String) -> MediaJob? {
        allJobs().first { $0.sourceLocalIdentifier == identifier }
    }

    private func registerPersistedBackgroundHandlers() {
        guard #available(iOS 26.0, *) else {
            UserDefaults.standard.removeObject(forKey: Self.persistedBackgroundIdentifiersKey)
            return
        }
        let identifiers = UserDefaults.standard.stringArray(forKey: Self.persistedBackgroundIdentifiersKey) ?? []
        if !identifiers.isEmpty {
            PocketLog.info("恢复后台任务 handler，数量=\(identifiers.count)")
        }
        var restored: [String] = []
        for identifier in identifiers {
            if registerBackgroundHandler(for: identifier) {
                restored.append(identifier)
            } else {
                forgetBackgroundIdentifier(identifier)
            }
        }
        if let activeIdentifier = restored.last {
            submittedBackgroundIdentifier = activeIdentifier
            for staleIdentifier in restored.dropLast() {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: staleIdentifier)
                forgetBackgroundIdentifier(staleIdentifier)
                PocketLog.warning("清理重复的后台请求：\(staleIdentifier)")
            }
        }
    }

    @discardableResult
    @available(iOS 26.0, *)
    private func registerBackgroundHandler(for identifier: String) -> Bool {
        if registeredBackgroundIdentifiers.contains(identifier) { return true }
        let didRegister = BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier,
            using: nil
        ) { [weak self] task in
            guard let continued = task as? BGContinuedProcessingTask else {
                PocketLog.error("后台 handler 收到非持续处理任务：\(task.identifier)")
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                guard let self else {
                    continued.setTaskCompleted(success: false)
                    return
                }
                self.handleBackgroundLaunch(continued)
            }
        }
        if didRegister {
            registeredBackgroundIdentifiers.insert(identifier)
            PocketLog.info("已注册持续后台任务 handler：\(identifier)")
        } else {
            PocketLog.error("持续后台任务 handler 注册失败：\(identifier)，请检查 Info.plist 通配标识")
        }
        return didRegister
    }

    @available(iOS 26.0, *)
    private func handleBackgroundLaunch(_ task: BGContinuedProcessingTask) {
        PocketLog.info("系统启动持续后台任务：\(task.identifier)")
        backgroundTask = task
        submittedBackgroundIdentifier = task.identifier
        task.expirationHandler = { [weak self] in
            PocketLog.warning("持续后台任务即将过期：\(task.identifier)")
            Task { @MainActor in
                self?.pauseProcessing()
            }
        }
        guard modelContext != nil else {
            PocketLog.debug("后台任务等待 SwiftData 配置完成：\(task.identifier)")
            pendingLaunchedBackgroundTask = task
            return
        }
        startProcessingIfNeeded()
    }

    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask() {
        let pendingCount = allJobs().filter { $0.state.isActive || $0.state == .paused }.count
        guard pendingCount > 0 else { return }
        guard submittedBackgroundIdentifier == nil, backgroundTask == nil else {
            PocketLog.debug("已有持续后台任务，忽略重复提交")
            return
        }

        let identifier = String(Self.backgroundTaskPattern.dropLast()) + UUID().uuidString
        guard registerBackgroundHandler(for: identifier) else {
            messageCenter.post(
                severity: .warning,
                stage: "后台任务",
                title: "无法注册后台处理",
                details: "后台任务标识未获系统许可，请保持 \(AppIdentity.displayName) 在前台。",
                showsBanner: true
            )
            return
        }
        persistBackgroundIdentifier(identifier)
        submittedBackgroundIdentifier = identifier
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "正在压缩 \(pendingCount) 个项目",
            subtitle: "准备开始"
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            PocketLog.info("持续后台任务提交成功：\(identifier)，任务数量=\(pendingCount)")
        } catch {
            PocketLog.warning("持续后台任务提交失败：\(identifier)，错误=\(error.localizedDescription)")
            submittedBackgroundIdentifier = nil
            forgetBackgroundIdentifier(identifier)
            messageCenter.post(
                severity: .warning,
                stage: "后台任务",
                title: "无法在后台继续",
                details: "请保持 \(AppIdentity.displayName) 在前台。\n\(error.localizedDescription)",
                showsBanner: true
            )
        }
    }

    @available(iOS 26.0, *)
    private func finishBackgroundRequest() {
        guard let identifier = backgroundTask?.identifier ?? submittedBackgroundIdentifier else { return }
        if backgroundTask == nil {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
            PocketLog.debug("前台队列先完成，取消尚未启动的后台请求：\(identifier)")
        }
        forgetBackgroundIdentifier(identifier)
        submittedBackgroundIdentifier = nil
        pendingLaunchedBackgroundTask = nil
    }

    private func persistBackgroundIdentifier(_ identifier: String) {
        var identifiers = Set(UserDefaults.standard.stringArray(forKey: Self.persistedBackgroundIdentifiersKey) ?? [])
        identifiers.insert(identifier)
        UserDefaults.standard.set(identifiers.sorted(), forKey: Self.persistedBackgroundIdentifiersKey)
    }

    private func forgetBackgroundIdentifier(_ identifier: String) {
        var identifiers = Set(UserDefaults.standard.stringArray(forKey: Self.persistedBackgroundIdentifiersKey) ?? [])
        identifiers.remove(identifier)
        UserDefaults.standard.set(identifiers.sorted(), forKey: Self.persistedBackgroundIdentifiersKey)
    }

    private func updateBackgroundTitle(total: Int, filename: String, subtitle: String) {
        if #available(iOS 26.0, *) {
            // Lock-screen task text is visible outside the app; keep user media
            // names out of it while retaining queue progress information.
            backgroundTask?.updateTitle("正在压缩 \(total) 个项目", subtitle: subtitle)
        }
    }

    @available(iOS 26.0, *)
    private var backgroundTask: BGContinuedProcessingTask? {
        get { backgroundTaskStorage as? BGContinuedProcessingTask }
        set { backgroundTaskStorage = newValue }
    }

    @available(iOS 26.0, *)
    private var pendingLaunchedBackgroundTask: BGContinuedProcessingTask? {
        get { pendingLaunchedBackgroundTaskStorage as? BGContinuedProcessingTask }
        set { pendingLaunchedBackgroundTaskStorage = newValue }
    }

    private func setBackgroundProgressTotal(_ total: Int) {
        if #available(iOS 26.0, *) {
            backgroundTask?.progress.totalUnitCount = Int64(max(1, total * 1000))
        }
    }

    private func setBackgroundProgress(_ value: Double, total: Int) {
        if #available(iOS 26.0, *) {
            backgroundTask?.progress.completedUnitCount = Int64(value * Double(max(1, total * 1000)))
        }
    }

    private func completeBackgroundProcessing(
        title: String,
        subtitle: String,
        completedCount: Int,
        failedCount: Int,
        wasInterrupted: Bool,
        success: Bool
    ) async {
        guard #available(iOS 26.0, *) else { return }
        let activeBackgroundTask = backgroundTask
        activeBackgroundTask?.updateTitle(title, subtitle: subtitle)
        if activeBackgroundTask != nil, !wasInterrupted {
            await CompletionActivityManager.shared.showCompletion(
                completedCount: completedCount,
                failedCount: failedCount
            )
        }
        activeBackgroundTask?.setTaskCompleted(success: success)
        finishBackgroundRequest()
        self.backgroundTask = nil
    }

    nonisolated private static func elapsedMilliseconds(since start: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(start) * 1_000))
    }
}
