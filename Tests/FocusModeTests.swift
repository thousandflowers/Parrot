import XCTest
@testable import Parrot

@MainActor
final class FocusWordCountTests: XCTestCase {

    // MARK: - wordCount

    func testWordCount_empty() {
        XCTAssertEqual(FocusWordCounter.wordCount(""), 0)
        XCTAssertEqual(FocusWordCounter.wordCount("   \n  "), 0)
    }

    func testWordCount_singleAndMultiple() {
        XCTAssertEqual(FocusWordCounter.wordCount("hello"), 1)
        XCTAssertEqual(FocusWordCounter.wordCount("hello world"), 2)
        XCTAssertEqual(FocusWordCounter.wordCount("  hello   world  "), 2)
        XCTAssertEqual(FocusWordCounter.wordCount("a\tb\nc"), 3)
    }

    func testWordCount_unicode() {
        XCTAssertEqual(FocusWordCounter.wordCount("caffè è pronto"), 3)
    }

    // MARK: - processReading delta logic

    func testProcessReading_writingAccumulates() {
        let c = FocusWordCounter()
        c.baseline(count: 2)            // field already had 2 words
        c.processReading(count: 5)      // wrote 3 more
        XCTAssertEqual(c.wordsWritten, 3)
        c.processReading(count: 8)      // wrote 3 more
        XCTAssertEqual(c.wordsWritten, 6)
    }

    func testProcessReading_smallBackspaceIgnored() {
        let c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 10)     // +10
        c.processReading(count: 8)      // -2 (backspace), within threshold → ignored
        XCTAssertEqual(c.wordsWritten, 10)
        c.processReading(count: 12)     // +4 from new lastCount(8)
        XCTAssertEqual(c.wordsWritten, 14)
    }

    func testProcessReading_largeDropRebasesWithoutSubtracting() {
        let c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 20)     // +20
        c.processReading(count: 3)      // -17 (> threshold 5) → field switch, rebase
        XCTAssertEqual(c.wordsWritten, 20)
        c.processReading(count: 6)      // +3 from new lastCount(3)
        XCTAssertEqual(c.wordsWritten, 23)
    }

    func testResumeCounting_keepsWordsRebasesLast() {
        let c = FocusWordCounter()
        c.baseline(count: 0)
        c.processReading(count: 10)     // 10 words written
        c.rebaseline(count: 100)        // resumed in a different/longer field
        c.processReading(count: 102)    // +2 only
        XCTAssertEqual(c.wordsWritten, 12)
    }
}

@MainActor
final class FocusTimerMathTests: XCTestCase {
    func testResumeStart_preservesElapsed() {
        // Paused after 40s of a 60s session: 20s remain.
        // Resuming "now" must place startTime 40s in the past so the
        // countdown continues from 20s, not restart at 60s.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = FocusTimer.resumeStartTime(elapsed: 40, now: now)
        let durationSeconds = 60
        let remaining = max(0, durationSeconds - Int(now.timeIntervalSince(start)))
        XCTAssertEqual(remaining, 20)
    }
}

@MainActor
final class FocusStreakTests: XCTestCase {
    private func key(_ daysAgo: Int, from today: Date) -> String {
        let cal = Calendar.current
        let date = cal.date(byAdding: .day, value: -daysAgo, to: cal.startOfDay(for: today))!
        let df = DateFormatter(); df.calendar = cal
        df.locale = Locale(identifier: "en_US_POSIX"); df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    func testStreak_consecutiveDays() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(1, from: today), key(2, from: today)]
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 0), 3)
    }

    func testStreak_gapBreaksWithoutFreeze() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(2, from: today)]  // missing day 1
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 0), 1)
    }

    func testStreak_oneFreezeBridgesOneGap() {
        let today = Date()
        let keys: Set<String> = [key(0, from: today), key(2, from: today), key(3, from: today)]
        // day1 missing, bridged by 1 freeze → 0,(1 freeze),2,3 = streak 3
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: keys, today: today, freezeLimit: 1), 3)
    }

    func testStreak_emptyIsZero() {
        XCTAssertEqual(FocusStatsStore.computeStreak(loggedKeys: [], today: Date(), freezeLimit: 1), 0)
    }
}
