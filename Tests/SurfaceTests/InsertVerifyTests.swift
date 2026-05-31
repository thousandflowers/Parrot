import XCTest
@testable import Parrot

final class InsertVerifyTests: XCTestCase {
    func testNeedsRetryWhenTextAbsent() {
        XCTAssertTrue(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: "he"))
    }
    func testNoRetryWhenTextPresent() {
        XCTAssertFalse(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: "hello"))
    }
    func testNoRetryWhenAfterUnreadable() {
        XCTAssertFalse(InsertVerifier.needsKeystrokeFallback(expectedInsert: "llo", before: "he", after: nil))
    }
}
