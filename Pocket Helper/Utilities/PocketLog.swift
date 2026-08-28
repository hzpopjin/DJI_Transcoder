import Foundation
import OSLog

enum PocketLog {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.jilllees.djihelper",
        category: "PocketHelper"
    )

    nonisolated static func debug(_ message: String) {
        logger.debug("[DEBUG] \(message, privacy: .public)")
    }

    nonisolated static func info(_ message: String) {
        logger.info("[INFO] \(message, privacy: .public)")
    }

    nonisolated static func warning(_ message: String) {
        logger.warning("[WARNING] \(message, privacy: .public)")
    }

    nonisolated static func error(_ message: String) {
        logger.error("[ERROR] \(message, privacy: .public)")
    }
}
