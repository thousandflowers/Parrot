import XCTest
@testable import Parrot

final class LatencyTracerTests: XCTestCase {
    func testRecordsPercentiles() {
        let tracer = LatencyTracer()
        for ms in [10.0, 20.0, 30.0, 40.0, 100.0] {
            tracer.record(stage: .total, milliseconds: ms)
        }
        XCTAssertEqual(tracer.percentile(.total, p: 50), 30.0, accuracy: 0.001)
        XCTAssertEqual(tracer.percentile(.total, p: 95), 100.0, accuracy: 0.001)
    }

    func testEmptyStageReturnsZero() {
        let tracer = LatencyTracer()
        XCTAssertEqual(tracer.percentile(.model, p: 95), 0.0)
    }

    func testRingBufferCaps() {
        let tracer = LatencyTracer(capacity: 3)
        for ms in [1.0, 2.0, 3.0, 4.0] { tracer.record(stage: .total, milliseconds: ms) }
        // oldest (1.0) evicted; p50 of [2,3,4] is 3
        XCTAssertEqual(tracer.percentile(.total, p: 50), 3.0, accuracy: 0.001)
    }
}
