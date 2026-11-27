import XCTest
@testable import Parrot

/// Guards the user's real data: before AppPaths, `swift test` rewrote
/// ~/Library/Application Support/Parrot (custom rules, history, learned completions).
final class AppPathsTests: XCTestCase {
    private let realSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.standardizedFileURL.path

    func testUnderXCTestSupportDirIsNotTheUsersRealOne() throws {
        XCTAssertTrue(AppPaths.isRunningTests)
        let dir = try XCTUnwrap(AppPaths.applicationSupport).standardizedFileURL.path
        XCTAssertFalse(dir.hasPrefix(realSupport), "tests must never resolve to \(realSupport)")
    }

    func testStoresResolveInsideTheTestSandbox() async throws {
        let sandbox = try XCTUnwrap(AppPaths.applicationSupport).standardizedFileURL.path
        let cacheURL = await CorrectionCache.shared.cacheFileURL
        XCTAssertTrue(cacheURL.standardizedFileURL.path.hasPrefix(sandbox))
        XCTAssertFalse(cacheURL.standardizedFileURL.path.hasPrefix(realSupport))
    }
}
