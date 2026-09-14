import Foundation
import OSLog

enum PocketLog {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jilllees.djihelper",
        category: "PocketHelper"
    )

    nonisolated static func debug(_ message: String) {
        logger.debug("[DEBUG] \(message, privacy: .private(mask: .hash))")
    }

    nonisolated static func info(_ message: String) {
        logger.info("[INFO] \(message, privacy: .private(mask: .hash))")
    }

    nonisolated static func warning(_ message: String) {
        logger.warning("[WARNING] \(message, privacy: .private(mask: .hash))")
    }

    nonisolated static func error(_ message: String) {
        logger.error("[ERROR] \(message, privacy: .private(mask: .hash))")
    }

    nonisolated static func performance(
        _ stage: String,
        durationMilliseconds: Int? = nil,
        originalBytes: Int64? = nil,
        outputBytes: Int64? = nil,
        bytesSaved: Int64? = nil,
        width: Int? = nil,
        height: Int? = nil,
        frameRate: Double? = nil,
        targetBitrate: Int64? = nil,
        actualBitrate: Int64? = nil
    ) {
        var details = "[PERF] stage=\(stage)"
        if let durationMilliseconds {
            details += " durationMs=\(durationMilliseconds)"
        }
        if let originalBytes {
            details += " originalBytes=\(originalBytes)"
        }
        if let outputBytes {
            details += " outputBytes=\(outputBytes)"
        }
        if let bytesSaved {
            details += " bytesSaved=\(bytesSaved)"
        }
        if let width, let height {
            details += " width=\(width) height=\(height)"
        }
        if let frameRate {
            details += " frameRate=\(String(format: "%.3f", frameRate))"
        }
        if let targetBitrate {
            details += " targetBitrate=\(targetBitrate)"
        }
        if let actualBitrate {
            details += " actualBitrate=\(actualBitrate)"
        }
        logger.info("\(details, privacy: .public)")
    }
}
