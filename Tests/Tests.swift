import XCTest
@testable import RefineClone

final class PromptEngineTests: XCTestCase {
    func testBuildGrammarPrompt_containsUserText() {
        let engine = PromptEngine(language: "en", style: "formal")
        let prompt = engine.buildGrammarPrompt(for: "This is a test")
        XCTAssertTrue(prompt.contains("This is a test"))
        XCTAssertTrue(prompt.contains("<|TEXT_START|>"))
        XCTAssertTrue(prompt.contains("<|TEXT_END|>"))
    }
}

final class CorrectionResultTests: XCTestCase {
    func testHasChanges_differentText_returnsTrue() {
        let result = CorrectionResult(original: "abc", corrected: "def", modelID: "test")
        XCTAssertTrue(result.hasChanges)
    }

    func testHasChanges_sameText_returnsFalse() {
        let result = CorrectionResult(original: "abc", corrected: "abc", modelID: "test")
        XCTAssertFalse(result.hasChanges)
    }

    func testComputeDiff_differentWords_returnsOps() {
        let ops = CorrectionResult.computeDiff(original: "hello", corrected: "hi")
        XCTAssertNotNil(ops)
    }

    func testComputeDiff_sameText_returnsEmpty() {
        let ops = CorrectionResult.computeDiff(original: "hello", corrected: "hello")
        XCTAssertNotNil(ops)
        XCTAssertTrue(ops?.isEmpty ?? false)
    }
}

final class ResultCacheTests: XCTestCase {
    func testGet_afterSet_returnsResult() async {
        let cache = ResultCache.shared
        await cache.invalidateAll()
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, for: "a", modelID: "x")
        let retrieved = await cache.get(for: "a", modelID: "x")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.correctedText, "b")
    }

    func testGet_differentModel_returnsNil() async {
        let cache = ResultCache.shared
        await cache.invalidateAll()
        let result = CorrectionResult(original: "a", corrected: "b", modelID: "x")
        await cache.set(result, for: "a", modelID: "x")
        let retrieved = await cache.get(for: "a", modelID: "y")
        XCTAssertNil(retrieved)
    }
}
