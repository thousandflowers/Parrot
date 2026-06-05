import Foundation

/// How often Wren resurfaces the optional tone practice. Raw values persist in UserDefaults.
enum ToneTuneUpCadence: String, CaseIterable, Sendable {
    case off, daily, weekly
    var interval: TimeInterval? {
        switch self {
        case .off: return nil
        case .daily: return 24 * 3600
        case .weekly: return 7 * 24 * 3600
        }
    }
}

/// Pure decision: is a tone tune-up due? Injectable `now` for tests.
enum ToneTuneUpScheduler {
    static func isDue(cadence: ToneTuneUpCadence, lastRun: Date?, now: Date = Date()) -> Bool {
        guard let interval = cadence.interval else { return false }   // .off
        guard let last = lastRun else { return true }                 // never run
        return now.timeIntervalSince(last) >= interval
    }
}
