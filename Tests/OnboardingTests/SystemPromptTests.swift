import XCTest
@testable import Parrot

final class SystemPromptTests: XCTestCase {
    func test_systemPrompt_includesStyleDescriptor_whenPresent() {
        let p = LlamaCompletionClient.systemPrompt(userPrompt: "", styleDescriptor: "User tends to write casual.")
        XCTAssertTrue(p.contains("User tends to write casual."))
    }
    func test_systemPrompt_omitsStyle_whenEmpty() {
        let p = LlamaCompletionClient.systemPrompt(userPrompt: "", styleDescriptor: "")
        XCTAssertFalse(p.contains("User tends"))
    }
}
