import Foundation
import SwiftData

@Model
final class MediaJob {
    @Attribute(.unique) var sourceLocalIdentifier: String
    var outputLocalIdentifier: String?
    var originalFilename: String
    var outputFilename: String?
    var mediaKindRaw: String
    var stateRaw: String
    var progress: Double
    var originalBytes: Int64
    var outputBytes: Int64
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?
    var errorDetails: String?
    var retryCount: Int

    init(descriptor: MediaAssetDescriptor, state: ProcessingState) {
        sourceLocalIdentifier = descriptor.id
        originalFilename = descriptor.originalFilename
        mediaKindRaw = descriptor.kind.rawValue
        stateRaw = state.rawValue
        progress = 0
        originalBytes = descriptor.estimatedBytes
        outputBytes = 0
        createdAt = .now
        updatedAt = .now
        retryCount = 0
    }

    var mediaKind: MediaKind {
        get { MediaKind(rawValue: mediaKindRaw) ?? .photo }
        set { mediaKindRaw = newValue.rawValue }
    }

    var state: ProcessingState {
        get { ProcessingState(rawValue: stateRaw) ?? .failed }
        set {
            stateRaw = newValue.rawValue
            updatedAt = .now
        }
    }

    var savedBytes: Int64 { max(0, originalBytes - outputBytes) }
}

@Model
final class AppMessage {
    var id: UUID
    var severityRaw: String
    var jobIdentifier: String?
    var stage: String
    var title: String
    var details: String
    var errorCode: String?
    var isRead: Bool
    var createdAt: Date
    var actionRaw: String

    init(
        severity: MessageSeverity,
        jobIdentifier: String? = nil,
        stage: String,
        title: String,
        details: String,
        errorCode: String? = nil,
        action: MessageAction = .none
    ) {
        id = UUID()
        severityRaw = severity.rawValue
        self.jobIdentifier = jobIdentifier
        self.stage = stage
        self.title = title
        self.details = details
        self.errorCode = errorCode
        isRead = false
        createdAt = .now
        actionRaw = action.rawValue
    }

    var severity: MessageSeverity { MessageSeverity(rawValue: severityRaw) ?? .error }
    var action: MessageAction { MessageAction(rawValue: actionRaw) ?? .none }
}
