import OSLog

extension Logger {
    static let cache    = Logger(subsystem: Constants.bundleID, category: "cache")
    static let core     = Logger(subsystem: Constants.bundleID, category: "core")
    static let infra    = Logger(subsystem: Constants.bundleID, category: "infra")
    static let ui       = Logger(subsystem: Constants.bundleID, category: "ui")
    static let ax       = Logger(subsystem: Constants.bundleID, category: "accessibility")
    static let server   = Logger(subsystem: Constants.bundleID, category: "server")
    static let feedback = Logger(subsystem: Constants.bundleID, category: "feedback")
}
