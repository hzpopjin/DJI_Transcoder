import Combine
import Foundation
import SwiftData
import SwiftUI

@MainActor
final class ModelContainerController: ObservableObject {
    typealias ContainerFactory = () throws -> ModelContainer

    @Published private(set) var container: ModelContainer?
    @Published private(set) var errorMessage: String?

    private let factory: ContainerFactory

    init(factory: @escaping ContainerFactory = {
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
        return try ModelContainer(for: MediaJob.self, AppMessage.self)
    }) {
        self.factory = factory
        retry()
    }

    func retry() {
        do {
            let container = try factory()
            self.container = container
            errorMessage = nil
            PocketLog.info("SwiftData 数据库初始化完成，目录已就绪")
        } catch {
            container = nil
            errorMessage = Self.userFacingErrorMessage
            PocketLog.error("SwiftData 数据库初始化失败")
        }
    }

    nonisolated static let userFacingErrorMessage = "本机记录暂时无法打开。请检查设备存储空间后重试；已有记录不会被自动删除。"
}

struct DatabaseRecoveryView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("无法打开本机记录", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }
}
