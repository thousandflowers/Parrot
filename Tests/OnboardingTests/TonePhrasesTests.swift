import XCTest
@testable import Parrot

final class TonePhrasesTests: XCTestCase {
    func test_allRegistersPresent_andNonEmpty() {
        let all = TonePhrases.all
        XCTAssertEqual(Set(all.map(\.register)), Set(TonePhrases.Register.allCases))
        XCTAssertTrue(all.allSatisfy { !$0.opener.isEmpty })
    }

    func test_rotation_isStableForSameSeed_andCoversOverTime() {
        let first = TonePhrases.rotating(count: 3, seed: 0)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first.map(\.opener), TonePhrases.rotating(count: 3, seed: 0).map(\.opener),
                       "same seed → same selection")
        let openers = (0..<TonePhrases.all.count).map { TonePhrases.rotating(count: 1, seed: $0).first!.opener }
        XCTAssertGreaterThan(Set(openers).count, 1, "rotation should cover different phrases")
    }
}
