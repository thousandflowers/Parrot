import Cocoa

protocol AXBridgeProtocol: Actor, Sendable {
    func fetchSelectedText() async throws -> String
    func replaceSelectedText(with text: String) async throws
    var lastSelectionBounds: CGRect { get async }
}

actor MockAXBridge: AXBridgeProtocol {
    private(set) var lastSelectionBounds: CGRect = .zero
    var mockText: String = ""
    var shouldThrow: Error?

    func fetchSelectedText() async throws -> String {
        if let error = shouldThrow { throw error }
        return mockText
    }

    func replaceSelectedText(with text: String) async throws {
        if let error = shouldThrow { throw error }
        lastSelectionBounds = .zero
    }
}
