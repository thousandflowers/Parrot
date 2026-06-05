import XCTest
@testable import Parrot

@MainActor
final class CadencePrefTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.toneTuneUpCadence)
    }
    func test_default_isOff() {
        XCTAssertEqual(PreferencesStore.shared.toneTuneUpCadence, .off)
    }
    func test_roundTrips() {
        PreferencesStore.shared.toneTuneUpCadence = .weekly
        XCTAssertEqual(PreferencesStore.shared.toneTuneUpCadence, .weekly)
    }
}
