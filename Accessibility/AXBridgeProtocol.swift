import Cocoa

protocol AXBridgeProtocol: Sendable {
    func fetchSelectedText() async throws -> String
    func replaceSelectedText(with text: String) async throws
    var lastSelectionBounds: CGRect { get async }
}

actor MockAXBridge: AXBridgeProtocol {
    private(set) var lastSelectionBounds: CGRect = .zero
    private var mockText: String = ""
    private var mockShouldThrow: Error?

    func setMockText(_ text: String) { mockText = text }
    func setShouldThrow(_ error: Error?) { mockShouldThrow = error }

    func fetchSelectedText() async throws -> String {
        if let error = mockShouldThrow { throw error }
        return mockText
    }

    func replaceSelectedText(with text: String) async throws {
        if let error = mockShouldThrow { throw error }
        mockText = text
    }
}
