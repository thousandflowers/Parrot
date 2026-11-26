import XCTest
@testable import Parrot

/// Resume/416 handling, free-space guard and exact model-id matching in ModelManager.
final class InfraFixDownloadTests: XCTestCase {

    // MARK: - Content-Range parsing

    func testParsesFullContentRange() {
        let r = ModelManager.parseContentRange("bytes 100-199/1000")
        XCTAssertEqual(r?.start, 100)
        XCTAssertEqual(r?.total, 1000)
    }

    func testParsesUnsatisfiedContentRange() {
        let r = ModelManager.parseContentRange("bytes */1000")
        XCTAssertNil(r?.start)
        XCTAssertEqual(r?.total, 1000)
    }

    func testRejectsGarbageContentRange() {
        XCTAssertNil(ModelManager.parseContentRange("items 1-2/3"))
    }

    // MARK: - Resume decisions

    func testFreshDownloadUses200Length() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 200, existingSize: 0, contentRange: nil, expectedContentLength: 500),
            .fresh(total: 500))
    }

    func testServerIgnoringRangeRestartsFresh() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 200, existingSize: 300, contentRange: nil, expectedContentLength: 500),
            .fresh(total: 500))
    }

    func testMatchingPartialContentAppends() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 206, existingSize: 300,
                                        contentRange: "bytes 300-499/500", expectedContentLength: 200),
            .append(total: 500))
    }

    func testMismatchedContentRangeStartRestarts() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 206, existingSize: 300,
                                        contentRange: "bytes 0-499/500", expectedContentLength: 500),
            .restartWithoutRange)
    }

    func testCompletePartialWith416IsAlreadyComplete() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 416, existingSize: 500,
                                        contentRange: "bytes */500", expectedContentLength: 0),
            .alreadyComplete)
    }

    func test416WithUnknownOrDifferentTotalRestarts() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 416, existingSize: 500, contentRange: nil, expectedContentLength: 0),
            .restartWithoutRange)
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 416, existingSize: 600,
                                        contentRange: "bytes */500", expectedContentLength: 0),
            .restartWithoutRange)
    }

    func testOtherStatusFails() {
        XCTAssertEqual(
            ModelManager.resumeDecision(statusCode: 500, existingSize: 0, contentRange: nil, expectedContentLength: 0),
            .fail)
    }

    // MARK: - Free space

    func testFreeSpaceGuard() {
        XCTAssertTrue(ModelManager.hasEnoughSpace(available: 1_000, needed: 500, margin: 100))
        XCTAssertFalse(ModelManager.hasEnoughSpace(available: 550, needed: 500, margin: 100))
        XCTAssertTrue(ModelManager.hasEnoughSpace(available: nil, needed: 500, margin: 100), "unknown capacity must not block")
        XCTAssertTrue(ModelManager.hasEnoughSpace(available: 10, needed: 0, margin: 100), "unknown length must not block")
    }

    // MARK: - Exact model-id matching / safe deletion

    func testAdoptedPathMatchesOnlyExactID() {
        let path = "/Users/x/.cache/lm-studio/models/qwen2.5-7b-instruct-q4_k_m.gguf"
        XCTAssertTrue(ModelManager.adoptedPath(path, matchesModelID: "qwen2.5-7b-instruct-q4_k_m"))
        XCTAssertTrue(ModelManager.adoptedPath(path, matchesModelID: "Qwen2.5-7B-Instruct-Q4_K_M.gguf"))
        XCTAssertTrue(ModelManager.adoptedPath(path, matchesModelID: path), "discovered models use the full path as id")
        XCTAssertFalse(ModelManager.adoptedPath(path, matchesModelID: "qwen"))
        XCTAssertFalse(ModelManager.adoptedPath(path, matchesModelID: "qwen2.5"))
        XCTAssertFalse(ModelManager.adoptedPath(path, matchesModelID: ""))
    }

    func testIsPathInsideDirectory() {
        XCTAssertTrue(ModelManager.isPath("/a/Parrot/Models/m.gguf", inside: "/a/Parrot/Models"))
        XCTAssertTrue(ModelManager.isPath("/a/Parrot/Models/m.gguf", inside: "/a/Parrot/Models/"))
        XCTAssertFalse(ModelManager.isPath("/a/Parrot/Models-old/m.gguf", inside: "/a/Parrot/Models"))
        XCTAssertFalse(ModelManager.isPath("/b/x/a/Parrot/Models/m.gguf", inside: "/a/Parrot/Models"))
        XCTAssertFalse(ModelManager.isPath("/a/Parrot/Models/../../evil.gguf", inside: "/a/Parrot/Models"))
    }
}
