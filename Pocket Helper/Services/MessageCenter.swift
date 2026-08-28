import Combine
import Foundation
import SwiftData
import SwiftUI

struct BannerMessage: Identifiable, Equatable {
    let id = UUID()
    let severity: MessageSeverity
    let title: String
    let details: String
}

@MainActor
final class MessageCenter: ObservableObject {
    @Published var banner: BannerMessage?
    @Published var isPresentingMessages = false

    private var context: ModelContext?
    private var dismissTask: Task<Void, Never>?

    func configure(context: ModelContext) {
        self.context = context
    }

    func post(
        severity: MessageSeverity,
        jobIdentifier: String? = nil,
        stage: String,
        title: String,
        details: String,
        errorCode: String? = nil,
        action: MessageAction = .none,
        showsBanner: Bool = true
    ) {
        if let context {
            context.insert(AppMessage(
                severity: severity,
                jobIdentifier: jobIdentifier,
                stage: stage,
                title: title,
                details: details,
                errorCode: errorCode,
                action: action
            ))
            try? context.save()
        }

        guard showsBanner else { return }
        dismissTask?.cancel()
        withAnimation(.smooth(duration: 0.3)) {
            banner = BannerMessage(severity: severity, title: title, details: details)
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.smooth(duration: 0.25)) {
                    self?.banner = nil
                }
            }
        }
    }

    func dismissBanner() {
        dismissTask?.cancel()
        withAnimation(.smooth(duration: 0.25)) { banner = nil }
    }
}
