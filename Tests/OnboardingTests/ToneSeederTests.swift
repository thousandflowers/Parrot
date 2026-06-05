import XCTest
@testable import Parrot

final class ToneSeederTests: XCTestCase {
    func test_phraseCompletions_areJoinedAndLearned() async {
        let store = CompletionLearningStore(loadsFromDisk: false)
        // Three sentence terminators so StyleProfile's `totalSentences >= 3` gate is met
        // and `descriptor` populates — this exercises the recordStyleSample path.
        let result = await ToneSeeder.learn(
            phraseCompletions: [(opener: "Dear team, I am writing to",
                                 continuation: "follow up. Please confirm availability. Thank you for your time.")],
            pastedText: nil,
            store: store
        )
        XCTAssertGreaterThanOrEqual(result.seededCount, 0)
        let d = await store.styleDescriptor()
        XCTAssertFalse(d.isEmpty)  // the joined multi-sentence text updated the profile
    }

    func test_emptyInput_seedsNothing_andRecordsNothing() async {
        let store = CompletionLearningStore(loadsFromDisk: false)
        let result = await ToneSeeder.learn(
            phraseCompletions: [(opener: "Hi", continuation: "   ")],
            pastedText: "   ",
            store: store
        )
        XCTAssertEqual(result.seededCount, 0)
        let d = await store.styleDescriptor()
        XCTAssertTrue(d.isEmpty)
    }

    func test_pastedText_isLearned() async {
        let store = CompletionLearningStore(loadsFromDisk: false)
        let text = """
        ti scrivo per confermare la riunione
        ti scrivo per confermare la disponibilità
        ti scrivo per confermare il preventivo
        """
        let result = await ToneSeeder.learn(phraseCompletions: [], pastedText: text, store: store)
        XCTAssertGreaterThan(result.seededCount, 0)  // repeated "ti scrivo per" key seeds
    }
}
