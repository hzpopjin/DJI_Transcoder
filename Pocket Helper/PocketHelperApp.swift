import SwiftData
import SwiftUI

@main
@MainActor
struct PocketHelperApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var messageCenter: MessageCenter
    @StateObject private var coordinator: ProcessingCoordinator
    @StateObject private var databaseController: ModelContainerController

    init() {
        PocketLog.info("Pocket Helper 启动，准备初始化服务")
        let settings = AppSettings()
        let messages = MessageCenter()
        let databaseController = ModelContainerController()
        _settings = StateObject(wrappedValue: settings)
        _messageCenter = StateObject(wrappedValue: messages)
        _databaseController = StateObject(wrappedValue: databaseController)
        _coordinator = StateObject(wrappedValue: ProcessingCoordinator(
            settings: settings,
            messageCenter: messages,
            photoLibrary: PhotoLibraryService(),
            transcoder: MediaTranscoder()
        ))
    }

    var body: some Scene {
        WindowGroup {
            if let modelContainer = databaseController.container {
                AppEntryView()
                    .environmentObject(settings)
                    .environmentObject(messageCenter)
                    .environmentObject(coordinator)
                    .modelContainer(modelContainer)
            } else {
                DatabaseRecoveryView(
                    message: databaseController.errorMessage ?? "本机数据暂时无法打开，请重试。",
                    retry: databaseController.retry
                )
            }
        }
    }
}
