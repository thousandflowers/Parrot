import XCTest
@testable import Parrot

final class ToneTuneUpSchedulerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000)

    func test_off_isNeverDue() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .off, lastRun: nil, now: now))
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .off, lastRun: now.addingTimeInterval(-999_999), now: now))
    }
    func test_neverRun_isDue_whenEnabled() {
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: nil, now: now))
    }
    func test_daily_dueAfter24h() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: now.addingTimeInterval(-23*3600), now: now))
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .daily, lastRun: now.addingTimeInterval(-25*3600), now: now))
    }
    func test_weekly_dueAfter7d() {
        XCTAssertFalse(ToneTuneUpScheduler.isDue(cadence: .weekly, lastRun: now.addingTimeInterval(-6*86400), now: now))
        XCTAssertTrue(ToneTuneUpScheduler.isDue(cadence: .weekly, lastRun: now.addingTimeInterval(-8*86400), now: now))
    }
}
