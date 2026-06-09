import XCTest
@testable import Parrot

final class MLXServiceTests: XCTestCase {
    private var savedModelID: String?

    override func setUp() {
        super.setUp()
        savedModelID = UserDefaults.standard.string(forKey: Constants.UserDefaultsKey.selectedMLXModelID)
    }

    override func tearDown() {
        if let savedModelID {
            UserDefaults.standard.set(savedModelID, forKey: Constants.UserDefaultsKey.selectedMLXModelID)
        } else {
            UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.selectedMLXModelID)
        }
        super.tearDown()
    }

    func testServiceTypeMLX_rawValueRoundTrip() throws {
        XCTAssertEqual(ServiceType(rawValue: "mlx"), .mlx)
        XCTAssertEqual(ServiceType.mlx.rawValue, "mlx")
        XCTAssertTrue(ServiceType.allCases.contains(.mlx))

        let encoded = try JSONEncoder().encode(ServiceType.mlx)
        let decoded = try JSONDecoder().decode(ServiceType.self, from: encoded)
        XCTAssertEqual(decoded, .mlx)
    }

    func testFactory_mlx_returnsMLXService() {
        XCTAssertTrue(LLMServiceFactory.make(with: .mlx) is MLXLLMService)
    }

    func testResolveModelID_defaultsWhenUnset() {
        UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKey.selectedMLXModelID)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .mlx), MLXLLMService.defaultModelID)
    }

    func testResolveModelID_usesStoredSelection() {
        UserDefaults.standard.set("mlx-community/Llama-3.2-1B-Instruct-4bit",
                                  forKey: Constants.UserDefaultsKey.selectedMLXModelID)
        XCTAssertEqual(LLMServiceFactory.resolveModelID(for: .mlx),
                       "mlx-community/Llama-3.2-1B-Instruct-4bit")
    }

    func testSelectedModelID_emptyStringFallsBackToDefault() {
        UserDefaults.standard.set("", forKey: Constants.UserDefaultsKey.selectedMLXModelID)
        XCTAssertEqual(MLXLLMService.shared.selectedModelID, MLXLLMService.defaultModelID)
    }

    func testCatalog_nonEmptyWithUniqueIDs() {
        XCTAssertFalse(MLXLLMService.catalog.isEmpty)
        let ids = MLXLLMService.catalog.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "catalog ids must be unique")
        XCTAssertTrue(ids.contains(MLXLLMService.defaultModelID),
                      "default model must be offered in the catalog")
        for entry in MLXLLMService.catalog {
            XCTAssertTrue(entry.id.contains("/"), "\(entry.id) is not a HF repo id")
            XCTAssertGreaterThan(entry.ramRequired, 0)
        }
    }

    /// Real end-to-end inference — downloads the smallest catalog model (~300 MB) on first
    /// run. Opt-in: MLX_INTEGRATION=1 swift test --filter MLXServiceTests/testRealCorrection
    func testRealCorrection_grammarFix() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MLX_INTEGRATION"] == "1",
                          "set MLX_INTEGRATION=1 to run the real-inference test")
        UserDefaults.standard.set("mlx-community/Qwen2.5-0.5B-Instruct-4bit",
                                  forKey: Constants.UserDefaultsKey.selectedMLXModelID)

        let result = try await MLXLLMService.shared.correct(
            text: "She go to school yesterday.", promptType: .grammar, language: "en")

        XCTAssertFalse(result.correctedText.isEmpty)
        XCTAssertEqual(result.modelID, "mlx-community/Qwen2.5-0.5B-Instruct-4bit")
    }
}
