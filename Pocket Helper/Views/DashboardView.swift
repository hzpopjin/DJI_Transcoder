import Photos
import PhotosUI
import SwiftData
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @EnvironmentObject private var messageCenter: MessageCenter
    @Query(sort: \MediaJob.createdAt, order: .reverse) private var jobs: [MediaJob]
    @Query(sort: \AppMessage.createdAt, order: .reverse) private var messages: [AppMessage]
    @State private var pickerItems: [PhotosPickerItem] = []

    private var activeJobs: [MediaJob] {
        jobs.filter { $0.state.isActive || [.paused, .failed].contains($0.state) }
    }

    private var savedBytes: Int64 {
        jobs.reduce(0) { $0 + $1.savedBytes }
    }

    var body: some View {
        NavigationStack {
            Group {
                if coordinator.authorizationStatus == .notDetermined || coordinator.authorizationStatus == .denied || coordinator.authorizationStatus == .restricted {
                    onboarding
                } else {
                    dashboard
                }
            }
            .navigationTitle("Pocket Helper")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        messageCenter.isPresentingMessages = true
                    } label: {
                        Image(systemName: messages.contains(where: { !$0.isRead }) ? "bell.badge.fill" : "bell")
                    }
                    .accessibilityLabel("消息中心")
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            pickerItems = []
            Task { await coordinator.importPickedItems(items) }
        }
    }

    private var onboarding: some View {
        ContentUnavailableView {
            Label("压缩 DJI 素材", systemImage: "camera.filters")
        } description: {
            Text("自动将 DJI 照片转为 HEIF、视频转为 HEVC，并保留 HDR、Live Photo 和关键拍摄信息。")
        } actions: {
            Button("授权访问照片") {
                Task { await coordinator.requestAccessAndScan() }
            }
            .buttonStyle(.borderedProminent)

            if coordinator.authorizationStatus == .denied {
                Button("打开系统设置") { openSettings() }
            }
        }
        .padding()
    }

    private var dashboard: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                statusCard
                actionRow

                if coordinator.authorizationStatus == .limited {
                    Label("当前为有限照片权限，自动扫描已关闭。你仍可手动选择素材。", systemImage: "hand.raised.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 14))
                }

                if activeJobs.isEmpty {
                    ContentUnavailableView(
                        "没有待处理素材",
                        systemImage: "checkmark.circle",
                        description: Text("打开 App 时会自动检查 DJI Album 中今天尚未处理的\(coordinator.settings.autoDetectionScope.title)。")
                    )
                    .frame(minHeight: 250)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("处理队列")
                                .font(.title3.bold())
                            Spacer()
                            Button("重置") { coordinator.resetPendingJobs() }
                                .font(.subheadline)
                                .disabled(coordinator.isProcessing)
                        }
                        ForEach(activeJobs) { job in
                            JobRow(job: job)
                        }
                    }
                }
            }
            .padding()
        }
        .refreshable { await coordinator.scanForNewAssets(force: true) }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(coordinator.isProcessing ? "正在压缩" : "准备就绪")
                        .font(.title2.bold())
                    Text(coordinator.currentFilename ?? "已累计节省 \(AppFormatters.byteString(savedBytes))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: coordinator.isProcessing ? "arrow.trianglehead.2.clockwise.rotate.90" : "sparkles")
                    .font(.title2)
                    .symbolEffect(.rotate, options: .repeat(.continuous), isActive: coordinator.isProcessing)
                    .foregroundStyle(.tint)
            }

            if coordinator.isProcessing {
                ProgressView(value: coordinator.overallProgress)
                    .tint(.accentColor)
                Text(coordinator.overallProgress, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if coordinator.isProcessing {
                Button {
                    coordinator.pauseProcessing()
                } label: {
                    Label("暂停队列", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            } else if !activeJobs.isEmpty {
                Button {
                    coordinator.startQueuedJobs()
                } label: {
                    Label(coordinator.isQueuePaused ? "继续转换" : "开始转换", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }

            if coordinator.readyToDeleteCount > 0 {
                Divider()
                Button(role: .destructive) {
                    coordinator.requestDeleteConfirmation()
                } label: {
                    HStack {
                        Label("删除 \(coordinator.readyToDeleteCount) 个原片", systemImage: "trash")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .accessibilityHint("打开删除原片确认")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: .rect(cornerRadius: 24))
    }

    private var actionRow: some View {
        let isImportingSelection = coordinator.isImportingSelection
        return HStack(spacing: 10) {
            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 50,
                matching: .any(of: [.images, .videos]),
                preferredItemEncoding: .current,
                photoLibrary: PHPhotoLibrary.shared()
            ) {
                Label(isImportingSelection ? "正在读取" : "选择素材", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isImportingSelection)

            Button {
                Task { await coordinator.scanForNewAssets(force: true) }
            } label: {
                Label("扫描", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(coordinator.isScanning || coordinator.authorizationStatus != .authorized)
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct JobRow: View {
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    let job: MediaJob

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            AssetThumbnailView(localIdentifier: job.sourceLocalIdentifier, mediaKind: job.mediaKind)
                .frame(width: 64, height: 64)
                .fixedSize()
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(job.originalFilename)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(job.state.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Menu {
                        if coordinator.isProcessing {
                            Button {
                                coordinator.pauseProcessing()
                            } label: {
                                Label("暂停队列", systemImage: "pause")
                            }
                        }
                        if !job.state.isActive {
                            Button {
                                coordinator.resetJob(jobIdentifier: job.sourceLocalIdentifier)
                            } label: {
                                Label("重置为待处理", systemImage: "arrow.counterclockwise")
                            }
                        }
                        Button(role: .destructive) {
                            coordinator.removeJob(jobIdentifier: job.sourceLocalIdentifier)
                        } label: {
                            Label("移出队列", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: job.progress)
                    .tint(color)
                if let error = job.errorDetails, job.state == .failed {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
    }

    private var color: Color {
        switch job.state {
        case .failed: .red
        case .paused: .orange
        default: .accentColor
        }
    }
}

struct InitialScanPreviewView: View {
    @EnvironmentObject private var coordinator: ProcessingCoordinator

    private var totalBytes: Int64 {
        coordinator.pendingInitialDescriptors.reduce(0) { $0 + $1.estimatedBytes }
    }

    var body: some View {
        NavigationStack {
            List {
                if coordinator.pendingNonDJICount > 0 {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("包含 \(coordinator.pendingNonDJICount) 个非 DJI/Pocket 素材")
                                    .font(.body.weight(.semibold))
                                Text("Pocket Helper 同样可以转换，但请先确认这些是你有意选择的素材。")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    LabeledContent("素材数量", value: "\(coordinator.pendingInitialDescriptors.count)")
                    LabeledContent("原始体积", value: AppFormatters.byteString(totalBytes))
                    LabeledContent("预计输出", value: AppFormatters.byteString(Int64(Double(totalBytes) * 0.48)))
                } footer: {
                    Text("预计体积仅供参考；每个输出都会在保存前重新校验。")
                }

                Section("待转换素材") {
                    ForEach(coordinator.pendingInitialDescriptors) { item in
                        HStack(alignment: .center, spacing: 16) {
                            AssetThumbnailView(localIdentifier: item.id, mediaKind: item.kind, cornerRadius: 10)
                                .frame(width: 64, height: 64)
                                .fixedSize()
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.originalFilename)
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                Text("\(item.pixelWidth) × \(item.pixelHeight) · \(AppFormatters.byteString(item.estimatedBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if item.source == .other {
                                    Text("非 DJI/Pocket 素材")
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
            .navigationTitle(coordinator.pendingScanTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("暂不处理") { coordinator.completeInitialScanWithoutProcessing() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(coordinator.pendingNonDJICount > 0 ? "仍要转换" : "开始转换") {
                        coordinator.confirmInitialBatch()
                    }
                        .fontWeight(.semibold)
                }
            }
        }
    }
}
