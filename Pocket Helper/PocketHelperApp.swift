import SwiftData
import SwiftUI

@main
@MainActor
struct PocketHelperApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var messageCenter: MessageCenter
    @StateObject private var coordinator: ProcessingCoordinator
    private let modelContainer: ModelContainer

    init() {
        PocketLog.info("Pocket Helper 启动，准备初始化服务")
        let settings = AppSettings()
        let messages = MessageCenter()
        _settings = StateObject(wrappedValue: settings)
        _messageCenter = StateObject(wrappedValue: messages)
        _coordinator = StateObject(wrappedValue: ProcessingCoordinator(
            settings: settings,
            messageCenter: messages,
            photoLibrary: PhotoLibraryService(),
            transcoder: MediaTranscoder()
        ))
        do {
            let applicationSupportDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            try FileManager.default.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true
            )
            modelContainer = try ModelContainer(for: MediaJob.self, AppMessage.self)
            PocketLog.info("SwiftData 数据库初始化完成，目录已就绪")
        } catch {
            PocketLog.error("SwiftData 数据库初始化失败：\(error.localizedDescription)")
            fatalError("无法创建本地数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(messageCenter)
                .environmentObject(coordinator)
        }
        .modelContainer(modelContainer)
    }
}
