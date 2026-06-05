import XCTest
@testable import Parrot

final class StyleSampleTests: XCTestCase {
    func test_recordStyleSample_populatesDescriptor() async {
        let store = CompletionLearningStore(loadsFromDisk: false)
        await store.recordStyleSample(from: "I don't think so. It's fine. We're good.")
        let d = await store.styleDescriptor()
        XCTAssertFalse(d.isEmpty, "descriptor should be non-empty after >=3 sentences")
    }

    func test_recordStyleSample_emptyText_isNoop() async {
        let store = CompletionLearningStore(loadsFromDisk: false)
        await store.recordStyleSample(from: "   ")
        let d = await store.styleDescriptor()
        XCTAssertTrue(d.isEmpty)
    }
}
