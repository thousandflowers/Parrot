import XCTest
@testable import Parrot

final class LatencyReportTests: XCTestCase {
    func test_emptyReport_hasNoSamplesMessage() {
        let t = LatencyTracer()
        XCTAssertTrue(t.report().contains("No samples"))
    }

    func test_report_includesRecordedStage_andCount() {
        let t = LatencyTracer()
        t.record(stage: .model, milliseconds: 100)
        t.record(stage: .model, milliseconds: 200)
        XCTAssertEqual(t.count(.model), 2)
        let r = t.report()
        XCTAssertTrue(r.contains("model"))
        XCTAssertTrue(r.contains("| 2 |"))  // sample count column
    }

    func test_reset_clears() {
        let t = LatencyTracer()
        t.record(stage: .total, milliseconds: 50)
        t.reset()
        XCTAssertEqual(t.count(.total), 0)
    }
}
