import Foundation

/// The one place that decides where the app keeps its files.
///
/// Every store resolves its location from `applicationSupport`, so a test run gets a private
/// throw-away directory instead of the user's real `~/Library/Application Support`. Before this,
/// `swift test` rewrote the user's custom rules, history and learned completions with fixtures.
enum AppPaths {
    /// `~/Library/Application Support` in the app; a per-process temp dir under XCTest.
    /// Optional to mirror `FileManager.urls(for:in:).first`, which callers already handle.
    static let applicationSupport: URL? = isRunningTests
        ? testSandbox
        : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private static let testSandbox: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ParrotTests-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            // Never fall back to the real directory: a failing test beats rewritten user data.
            fatalError("AppPaths: cannot create test sandbox at \(dir.path): \(error)")
        }
        return dir
    }()
}
