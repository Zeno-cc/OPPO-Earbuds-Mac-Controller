import Foundation
import OSLog

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier
        ?? "com.zenocc.OPPO-Earbuds-Mac-Controller"

    static let bluetooth = Logger(subsystem: subsystem, category: "bluetooth")
    static let transport = Logger(subsystem: subsystem, category: "transport")
    static let session = Logger(subsystem: subsystem, category: "session")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
