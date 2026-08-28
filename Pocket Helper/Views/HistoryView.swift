import SwiftData
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @Query(sort: \MediaJob.updatedAt, order: .reverse) private var jobs: [MediaJob]
    @State private var showsClearHistoryConfirmation = false

    private var historyJobs: [MediaJob] {
        jobs.filter { $0.state.isHistoryRecord }
    }

    var body: some View {
        NavigationStack {
            List {
                if historyJobs.isEmpty {
                    ContentUnavailableView("还没有历史记录", systemImage: "clock")
                } else {
                    ForEach(historyJobs) { job in
                        HStack(alignment: .center, spacing: 16) {
                            AssetThumbnailView(
                                localIdentifier: job.outputLocalIdentifier ?? job.sourceLocalIdentifier,
                                mediaKind: job.mediaKind,
                                cornerRadius: 10
                            )
                            .frame(width: 64, height: 64)
                            .fixedSize()

                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.outputFilename ?? job.originalFilename)
                                    .font(.body.weight(.medium))
                                    .lineLimit(2)
                                    .truncationMode(.middle)
                                HStack(spacing: 8) {
                                    Label(job.state.title, systemImage: job.mediaKind.symbol)
                                    if job.savedBytes > 0 {
                                        Text("节省 \(AppFormatters.byteString(job.savedBytes))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .layoutPriority(1)

                            if job.state == .completed || job.state == .readyToDelete {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .fixedSize()
                            }
                        }
                        .padding(.vertical, 7)
                        .contentShape(.rect)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if [.failed, .paused, .skipped].contains(job.state) {
                                Button("重置") {
                                    coordinator.resetJob(jobIdentifier: job.sourceLocalIdentifier)
                                }
                                .tint(.orange)
                                Button("移除", role: .destructive) {
                                    coordinator.removeJob(jobIdentifier: job.sourceLocalIdentifier)
                                }
                            }
                        }
                    }
                }
            }
            .contentMargins(.top, 12, for: .scrollContent)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 72)
            }
            .navigationTitle("历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showsClearHistoryConfirmation = true
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .disabled(historyJobs.isEmpty)
                }
            }
            .alert("清空历史记录？", isPresented: $showsClearHistoryConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) {
                    coordinator.clearHistory()
                }
            } message: {
                Text("只清除 App 内的历史记录，不会删除系统相册中的照片或视频。")
            }
        }
    }

    private func tint(for state: ProcessingState) -> Color {
        switch state {
        case .failed: .red
        case .skipped, .paused: .orange
        case .completed, .readyToDelete: .green
        default: .accentColor
        }
    }
}
