import XCTest
@testable import Parrot

/// Orphaned llama-server detection (pid file + proc_pidpath) and health classification.
/// Uses /bin/sleep as a stand-in process; never starts llama-server.
final class InfraFixServerTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraFixServer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func spawnSleep() throws -> Process {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
        try p.run()
        return p
    }

    func testKnownExecutableMatchesResolvedPath() {
        XCTAssertTrue(ServerManager.isKnownServerExecutable(procPath: "/bin/sleep", knownPaths: ["/bin/sleep"]))
        XCTAssertFalse(ServerManager.isKnownServerExecutable(procPath: "/bin/sleep", knownPaths: ["/opt/homebrew/bin/llama-server"]))
        XCTAssertFalse(ServerManager.isKnownServerExecutable(procPath: nil, knownPaths: ["/bin/sleep"]))
    }

    func testProcessExecutablePathOfSelf() {
        let path = ServerManager.processExecutablePath(pid: getpid())
        XCTAssertNotNil(path)
    }

    func testPidRecordRoundTrip() throws {
        let url = dir.appendingPathComponent("server.pid")
        let record = ServerPidRecord(pid: 123, port: 11435, executablePath: "/x/llama-server")
        try ServerPidRecord.write(record, to: url)
        XCTAssertEqual(ServerPidRecord.read(from: url), record)
    }

    func testReapKillsOrphanRunningKnownExecutable() async throws {
        let orphan = try spawnSleep()
        defer { if orphan.isRunning { orphan.terminate() } }
        let url = dir.appendingPathComponent("server.pid")
        try ServerPidRecord.write(
            ServerPidRecord(pid: orphan.processIdentifier, port: 54321, executablePath: "/bin/sleep"), to: url)

        let outcome = await ServerManager.reapOrphan(recordURL: url, knownExecutables: ["/bin/sleep"])

        XCTAssertEqual(outcome, .terminated(pid: orphan.processIdentifier))
        orphan.waitUntilExit()
        XCTAssertFalse(orphan.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), "pid file must be cleared")
    }

    func testReapLeavesUnrelatedProcessAlone() async throws {
        let unrelated = try spawnSleep()
        defer { unrelated.terminate() }
        let url = dir.appendingPathComponent("server.pid")
        // Recorded pid was reused by a program that is not our server.
        try ServerPidRecord.write(
            ServerPidRecord(pid: unrelated.processIdentifier, port: 54321, executablePath: "/nope/llama-server"), to: url)

        let outcome = await ServerManager.reapOrphan(recordURL: url, knownExecutables: ["/nope/llama-server"])

        XCTAssertEqual(outcome, .notOurs)
        XCTAssertTrue(unrelated.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testReapWithoutPidFileIsNoop() async {
        let outcome = await ServerManager.reapOrphan(
            recordURL: dir.appendingPathComponent("none.pid"), knownExecutables: ["/bin/sleep"])
        XCTAssertEqual(outcome, .none)
    }

    // MARK: - Health classification

    func testHealthOKIsHealthy() {
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: 200, error: nil, processAlive: true), .healthy)
    }

    func testTimeoutUnderSwapIsNotCountedAsFailure() {
        let timeout = URLError(.timedOut)
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: nil, error: timeout, processAlive: true), .busy)
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: nil, error: timeout, processAlive: nil), .busy)
    }

    func testLoadingStatusIsNotAFailure() {
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: 503, error: nil, processAlive: true), .busy)
    }

    func testConnectionRefusedCountsAsDown() {
        let refused = URLError(.cannotConnectToHost)
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: nil, error: refused, processAlive: nil), .down)
    }

    func testDeadProcessCountsAsDownEvenOnTimeout() {
        XCTAssertEqual(ServerHealthMonitor.classify(statusCode: nil, error: URLError(.timedOut), processAlive: false), .down)
    }
}
