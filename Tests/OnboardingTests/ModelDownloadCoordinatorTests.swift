import XCTest
@testable import Parrot

@MainActor
final class ModelDownloadCoordinatorTests: XCTestCase {
    func test_progressStream_movesToComplete() async {
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            AsyncThrowingStream { c in
                c.yield(.downloading(0.5)); c.yield(.verifying(0.9)); c.yield(.complete); c.finish()
            }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        XCTAssertEqual(coord.phase, .complete)
        XCTAssertEqual(coord.progress, 1.0, accuracy: 0.001)
    }

    func test_error_setsErrorPhase() async {
        struct Boom: Error {}
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            AsyncThrowingStream { c in c.finish(throwing: Boom()) }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        if case .failed = coord.phase {} else { XCTFail("expected .failed, got \(coord.phase)") }
    }

    func test_startWhenAlreadyComplete_isNoop() async {
        var calls = 0
        let coord = ModelDownloadCoordinator(streamProvider: { _, _ in
            calls += 1
            return AsyncThrowingStream { c in c.yield(.complete); c.finish() }
        }, onComplete: { _ in })
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        await coord.start(modelID: "m", url: URL(string: "https://x/m.gguf")!, sha: nil)
        XCTAssertEqual(calls, 1, "second start after complete must not re-download")
    }
}
