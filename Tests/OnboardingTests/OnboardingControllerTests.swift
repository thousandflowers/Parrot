import XCTest
@testable import Parrot

final class OnboardingControllerTests: XCTestCase {
    func test_completionKey_isPerMode() {
        XCTAssertNotEqual(
            OnboardingController.completionKey(for: .parrot),
            OnboardingController.completionKey(for: .wren)
        )
        XCTAssertEqual(OnboardingController.completionKey(for: .wren),
                       "hasCompletedOnboarding_wren_v1")
    }
}
