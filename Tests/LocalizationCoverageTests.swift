import XCTest

/// Every `String(localized: "some.key")` must exist in every shipped .lproj table. A key missing
/// from the user's language is shown raw ("realtime.errors" appeared in the realtime indicator);
/// Localizable.xcstrings is not compiled into the app, only Resources/*.lproj ships.
final class LocalizationCoverageTests: XCTestCase {
    private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    func testEveryLocalizedKeyExistsInEveryLanguage() throws {
        let used = try usedKeys()
        XCTAssertFalse(used.isEmpty, "found no localized keys: scan is broken")
        let tables = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Resources"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "lproj" }
        XCTAssertFalse(tables.isEmpty)
        for lproj in tables {
            let strings = lproj.appendingPathComponent("Localizable.strings")
            let defined = try XCTUnwrap(NSDictionary(contentsOf: strings) as? [String: String],
                                        "\(strings.path) does not parse")
            let missing = used.subtracting(defined.keys).sorted()
            XCTAssertTrue(missing.isEmpty, "\(lproj.lastPathComponent) is missing: \(missing)")
        }
    }

    /// Dotted keys passed to String(localized:) in app sources (literal sentences are skipped:
    /// they are their own English fallback).
    private func usedKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(pattern: #"String\(localized:\s*"([a-z0-9_]+(?:\.[A-Za-z0-9_]+)+)""#)
        var keys = Set<String>()
        for dir in ["App", "Core", "Infra", "UI", "Accessibility", "Shortcuts"] {
            guard let walker = FileManager.default.enumerator(at: root.appendingPathComponent(dir),
                                                              includingPropertiesForKeys: nil) else { continue }
            for case let file as URL in walker where file.pathExtension == "swift" {
                let source = try String(contentsOf: file, encoding: .utf8)
                let range = NSRange(source.startIndex..., in: source)
                for match in pattern.matches(in: source, range: range) {
                    if let r = Range(match.range(at: 1), in: source) { keys.insert(String(source[r])) }
                }
            }
        }
        return keys
    }
}
