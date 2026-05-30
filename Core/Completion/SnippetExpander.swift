import Foundation
import AppKit

/// Expands dynamic placeholders inside a snippet (espanso-style), so snippets aren't just static
/// text. Supported: {{date}}, {{time}}, {{datetime}}, {{clipboard}}, {{year}}.
enum SnippetExpander {
    static func expand(_ template: String) -> String {
        guard template.contains("{{") else { return template }
        var out = template
        let now = Date()
        let df = DateFormatter()

        df.dateStyle = .medium; df.timeStyle = .none
        out = out.replacingOccurrences(of: "{{date}}", with: df.string(from: now))
        df.dateStyle = .none; df.timeStyle = .short
        out = out.replacingOccurrences(of: "{{time}}", with: df.string(from: now))
        df.dateStyle = .medium; df.timeStyle = .short
        out = out.replacingOccurrences(of: "{{datetime}}", with: df.string(from: now))

        let year = Calendar.current.component(.year, from: now)
        out = out.replacingOccurrences(of: "{{year}}", with: String(year))

        if out.contains("{{clipboard}}") {
            let clip = NSPasteboard.general.string(forType: .string) ?? ""
            out = out.replacingOccurrences(of: "{{clipboard}}", with: clip)
        }
        return out
    }
}
