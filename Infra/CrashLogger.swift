import Foundation

enum CrashLogger {
    private static let logDir: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Logs/Parrot")
    }()

    private static let crashLogURL = logDir.appendingPathComponent("crash.log")
    private static let debugLogURL = logDir.appendingPathComponent("debug.log")

    static func install() {
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler(_exceptionHandler)
        let fatalSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in fatalSignals {
            var new = sigaction()
            new.__sigaction_u.__sa_sigaction = _signalHandler
            new.sa_flags = SA_SIGINFO
            sigaction(sig, &new, nil)
        }
        log("CrashLogger installed")
    }

    static func log(_ message: String, file: StaticString = #file, line: UInt = #line) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(message)  (\(file):\(line))\n"
        if let data = entry.data(using: .utf8) {
            try? data.append(to: debugLogURL)
        }
        NSLog("[Parrot] \(message)")
    }

    static func writeCrash(title: String, detail: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let preamble = """
        ===== CRASH: \(title) =====
        Date: \(timestamp)
        App: \(Bundle.main.bundleIdentifier ?? "?")
        Version: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")
        Build: \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")
        """
        let entry = "\(preamble)\n\n\(detail)\n\n"
        if let data = entry.data(using: .utf8) {
            try? data.append(to: crashLogURL)
        }
    }
}

private let _exceptionHandler: @convention(c) (NSException) -> Void = { exception in
    let stack = exception.callStackSymbols.joined(separator: "\n")
    CrashLogger.writeCrash(
        title: "Uncaught NSException",
        detail: """
        Name: \(exception.name.rawValue)
        Reason: \(exception.reason ?? "nil")
        Stack:
        \(stack)
        """
    )
}

private let _signalHandler: @convention(c) (Int32, UnsafeMutablePointer<__siginfo>?, UnsafeMutableRawPointer?) -> Void = { signal, _, _ in
    var restore = sigaction()
    restore.__sigaction_u.__sa_handler = SIG_DFL
    sigaction(signal, &restore, nil)
    CrashLogger.writeCrash(
        title: "Fatal signal \(signalDescription(signal))",
        detail: "Signal \(signal) (\(String(cString: strsignal(signal))))"
    )
    raise(signal)
}

private func signalDescription(_ signal: Int32) -> String {
    switch signal {
    case SIGABRT: return "SIGABRT (abort)"
    case SIGSEGV: return "SIGSEGV (segmentation fault)"
    case SIGBUS:  return "SIGBUS (bus error)"
    case SIGILL:  return "SIGILL (illegal instruction)"
    case SIGFPE:  return "SIGFPE (floating point exception)"
    case SIGTRAP: return "SIGTRAP (trace trap)"
    default:      return "signal \(signal)"
    }
}

private extension Data {
    func append(to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: self)
            try handle.close()
        } else {
            try write(to: url, options: .atomic)
        }
    }
}
