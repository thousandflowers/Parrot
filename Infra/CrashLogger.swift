import Foundation
import Darwin

enum CrashLogger {
    private static let logDir: URL = {
        guard let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return URL(fileURLWithPath: "/tmp/ParrotLogs")
        }
        return base.appendingPathComponent("Logs/Parrot")
    }()

    private static let crashLogURL = logDir.appendingPathComponent("crash.log")
    private static let debugLogURL = logDir.appendingPathComponent("debug.log")

    /// Must be nonisolated(unsafe) — read by C signal handler where locks are not async-signal-safe.
    /// Written once in install() before signal registration, never mutated after.
    nonisolated(unsafe) static var crashFD: Int32 = -1

    /// Thread-safe via NSLock; only used from Swift contexts (log()).
    private static let debugLock = NSLock()
    private static var debugFD: Int32 = -1

    static func install() {
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        NSSetUncaughtExceptionHandler(_exceptionHandler)

        crashFD = open(crashLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        debugLock.lock()
        debugFD = open(debugLogURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        debugLock.unlock()

        let fatalSignals: [Int32] = [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP]
        for sig in fatalSignals {
            var new = sigaction()
            new.__sigaction_u.__sa_sigaction = _signalHandler
            new.sa_flags = SA_SIGINFO | SA_RESETHAND
            sigaction(sig, &new, nil)
        }
        log("CrashLogger installed")
    }

    static func log(_ message: String, file: StaticString = #file, line: UInt = #line) {
        let entry = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)  (\(file):\(line))\n"
        if let data = entry.data(using: .utf8) {
            debugLock.lock()
            _ = data.withUnsafeBytes { write(debugFD, $0.baseAddress, $0.count) }
            debugLock.unlock()
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
            _ = data.withUnsafeBytes { write(crashFD, $0.baseAddress, $0.count) }
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

    let fd = CrashLogger.crashFD
    var header = "CRASH: signal \(signal)\nStack trace:\n"
    _ = header.withUTF8 { write(fd, $0.baseAddress, $0.count) }

    var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
    let count = backtrace(&frames, 64)
    backtrace_symbols_fd(&frames, count, fd)
    var trailer = "\n"
    _ = trailer.withUTF8 { write(fd, $0.baseAddress, $0.count) }

    raise(signal)
}
