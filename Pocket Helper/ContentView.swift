import Foundation
import Photos
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var coordinator: ProcessingCoordinator
    @EnvironmentObject private var messageCenter: MessageCenter
    @Query(sort: \AppMessage.createdAt, order: .reverse) private var messages: [AppMessage]
    @State private var hasEnteredBackground = false
    @State private var showsDeleteConfirmation = false

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
                DashboardView()
                    .tabItem { Label("转换", systemImage: "arrow.trianglehead.2.clockwise.rotate.90") }
                HistoryView()
                    .tabItem { Label("历史", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape") }
            }

            if let banner = messageCenter.banner {
                BannerView(message: banner)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .task {
            await CompletionActivityManager.shared.dismissAll()
            coordinator.configure(context: modelContext)
            if coordinator.authorizationStatus == .authorized {
                await coordinator.scanForNewAssets()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await CompletionActivityManager.shared.dismissAll() }
                guard hasEnteredBackground else { break }
                hasEnteredBackground = false
                Task { await coordinator.scanForNewAssets() }
            case .inactive:
                coordinator.applicationWillResignActive()
            case .background:
                hasEnteredBackground = true
            @unknown default:
                break
            }
        }
        .onChange(of: coordinator.deleteConfirmationRequestID) { _, requestID in
            guard requestID != nil else { return }
            Task { @MainActor in
                await Task.yield()
                showsDeleteConfirmation = true
            }
        }
        .sheet(isPresented: $messageCenter.isPresentingMessages) {
            MessageCenterView()
        }
        .sheet(isPresented: $coordinator.showsInitialPreview) {
            InitialScanPreviewView()
                .interactiveDismissDisabled()
        }
        .alert(
            "删除 \(coordinator.readyToDeleteCount) 个原片？",
            isPresented: $showsDeleteConfirmation
        ) {
            Button("删除原片", role: .destructive) {
                Task { await coordinator.deleteReadyOriginals() }
            }
            Button("保留原片", role: .cancel) {
                coordinator.keepReadyOriginals()
            }
        } message: {
            Text("压缩结果已经保存并通过校验。PhotoKit 还会显示一次系统确认。")
        }
        .alert(
            coordinator.experimentalVideoConfirmation.map {
                "4K\($0.frameRateMode) 实验性转换"
            } ?? "高帧率实验性转换",
            isPresented: Binding(
                get: { coordinator.experimentalVideoConfirmation != nil },
                set: { if !$0 { coordinator.declineExperimentalVideoConversion() } }
            )
        ) {
            Button("继续实验性转换") {
                coordinator.confirmExperimentalVideoConversion()
            }
            Button("暂不转换", role: .cancel) {
                coordinator.declineExperimentalVideoConversion()
            }
        } message: {
            if let confirmation = coordinator.experimentalVideoConfirmation {
                Text("\(confirmation.filename) 将保留约 \(confirmation.frameRateMode) fps，并以约 \(String(format: "%.0f", confirmation.targetBitrate / 1_000_000)) Mbps 转换。4K 高帧率输出取决于设备的 HEVC 编码能力，可能失败或耗时较长。")
            }
        }
        .overlay(alignment: .topTrailing) {
            if messages.contains(where: { !$0.isRead }) {
                Color.clear.frame(width: 1, height: 1).accessibilityLabel("有未读消息")
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [MediaJob.self, AppMessage.self], inMemory: true)
        .environmentObject(AppSettings())
        .environmentObject(MessageCenter())
        .environmentObject(ProcessingCoordinator(
            settings: AppSettings(),
            messageCenter: MessageCenter(),
            photoLibrary: PhotoLibraryService(),
            transcoder: MediaTranscoder()
        ))
}
