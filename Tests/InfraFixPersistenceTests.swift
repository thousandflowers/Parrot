import XCTest
@testable import Parrot

/// Store load/backup behaviour: a file that fails to decode must be moved aside, never
/// silently replaced by an empty store on the next save. All I/O happens in a temp dir.
final class InfraFixPersistenceTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraFixPersistence-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func quarantined(prefix: String) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("\(prefix).corrupt-") }
    }

    func testLoadReturnsNilWhenFileMissing() {
        let url = dir.appendingPathComponent("missing.json")
        XCTAssertNil(PersistentJSON.load([String].self, from: url))
    }

    func testLoadDecodesValidFile() throws {
        let url = dir.appendingPathComponent("ok.json")
        try JSONEncoder().encode(["a", "b"]).write(to: url)
        XCTAssertEqual(PersistentJSON.load([String].self, from: url), ["a", "b"])
        XCTAssertTrue(try quarantined(prefix: "ok").isEmpty)
    }

    func testCorruptFileIsMovedAsideWithOriginalBytes() throws {
        let url = dir.appendingPathComponent("rules.json")
        let garbage = Data("{not json".utf8)
        try garbage.write(to: url)

        XCTAssertNil(PersistentJSON.load([String].self, from: url))

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let backups = try quarantined(prefix: "rules")
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.pathExtension, "json")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), garbage)
    }

    func testQuarantineNameKeepsStemAndExtension() {
        let url = dir.appendingPathComponent("contacts.json")
        let name = PersistentJSON.quarantineURL(for: url, at: Date(timeIntervalSince1970: 0)).lastPathComponent
        XCTAssertTrue(name.hasPrefix("contacts.corrupt-"), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)
    }

    func testTwoCorruptionsInSameSecondDoNotOverwriteEachOther() throws {
        let url = dir.appendingPathComponent("kb.json")
        let now = Date()
        try Data("x".utf8).write(to: url)
        _ = PersistentJSON.load([String].self, from: url, now: now)
        try Data("y".utf8).write(to: url)
        _ = PersistentJSON.load([String].self, from: url, now: now)
        XCTAssertEqual(try quarantined(prefix: "kb").count, 2)
    }

    func testContactStoreKeepsCorruptFileAfterSave() async throws {
        let url = dir.appendingPathComponent("contacts.json")
        try Data("[{\"broken\":".utf8).write(to: url)

        let store = ContactStore(fileURL: url)
        let loaded = await store.all
        XCTAssertTrue(loaded.isEmpty)
        await store.upsert(ContactProfile(name: "Rossi"))

        XCTAssertEqual(try quarantined(prefix: "contacts").count, 1, "user data must survive the next save")
        let saved = try JSONDecoder().decode([ContactProfile].self, from: Data(contentsOf: url))
        XCTAssertEqual(saved.map(\.name), ["Rossi"])
    }

    func testContactStoreLoadsExistingFile() async throws {
        let url = dir.appendingPathComponent("contacts.json")
        try JSONEncoder().encode([ContactProfile(name: "Bianchi")]).write(to: url)
        let names = await ContactStore(fileURL: url).all.map(\.name)
        XCTAssertEqual(names, ["Bianchi"])
    }

    func testHistoryStoreKeepsCorruptFileAfterAdd() async throws {
        let url = dir.appendingPathComponent("history.json")
        try Data("garbage".utf8).write(to: url)

        let store = HistoryStore(fileURL: url)
        let before = await store.all()
        XCTAssertTrue(before.isEmpty)
        await store.replaceEntries([])

        XCTAssertEqual(try quarantined(prefix: "history").count, 1)
    }
}

/// Log rotation (llama-server.log, debug.log): bounded size, append not overwrite.
final class InfraFixLogRotationTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("InfraFixLogs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRotatesWhenOverLimit() throws {
        let url = dir.appendingPathComponent("server.log")
        try Data(repeating: 65, count: 2_000).write(to: url)

        XCTAssertTrue(LogRotation.rotateIfNeeded(at: url, maxBytes: 1_000))

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let rotated = url.appendingPathExtension("1")
        XCTAssertEqual(try Data(contentsOf: rotated).count, 2_000)
    }

    func testDoesNotRotateUnderLimit() throws {
        let url = dir.appendingPathComponent("server.log")
        try Data(repeating: 65, count: 500).write(to: url)
        XCTAssertFalse(LogRotation.rotateIfNeeded(at: url, maxBytes: 1_000))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testRotationReplacesPreviousBackup() throws {
        let url = dir.appendingPathComponent("server.log")
        try Data("old".utf8).write(to: url.appendingPathExtension("1"))
        try Data(repeating: 66, count: 2_000).write(to: url)
        XCTAssertTrue(LogRotation.rotateIfNeeded(at: url, maxBytes: 1_000))
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("1")).count, 2_000)
    }

    func testAppendHandleAppendsInsteadOfOverwriting() throws {
        let url = dir.appendingPathComponent("server.log")
        try Data("first\n".utf8).write(to: url)

        let handle = try XCTUnwrap(LogRotation.openAppendHandle(at: url, maxBytes: 1_000_000))
        try handle.write(contentsOf: Data("second\n".utf8))
        try handle.close()

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "first\nsecond\n")
    }
}

/// FeedbackLogger rotation must split whole lines once, never mid-UTF-8 or mid-line.
final class InfraFixFeedbackRotationTests: XCTestCase {
    func testKeepsNewestWholeLinesWithinBudget() {
        let lines = (0..<10).map { "{\"n\":\($0),\"t\":\"città è perché\"}" }
        let data = Data((lines.joined(separator: "\n") + "\n").utf8)
        let lineBytes = lines[0].utf8.count + 1

        let kept = FeedbackLogger.trimmedLog(data, keepingAtMostBytes: lineBytes * 3)
        let keptLines = kept.split(separator: "\n").map(String.init)

        XCTAssertEqual(keptLines, Array(lines.suffix(3)))
        XCTAssertTrue(kept.hasSuffix("\n"))
    }

    func testNoLineIsMangledAcrossOldChunkBoundary() {
        // A long multi-byte line that straddles the old 4096-byte chunk boundary.
        let long = "{\"t\":\"" + String(repeating: "é", count: 3_000) + "\"}"
        let data = Data(("short\n" + long + "\n").utf8)
        let kept = FeedbackLogger.trimmedLog(data, keepingAtMostBytes: 1_000_000)
        XCTAssertEqual(kept.split(separator: "\n").map(String.init), ["short", long])
    }
}
