import Foundation

/// Reconstructs the recently typed text of the focused field from keystrokes alone — no AX,
/// no clipboard. Used by UniversalSurface when AX exposes nothing. Per-focus; the buffer is
/// invalidated whenever the cursor may have moved in a way we cannot track (arrows, click,
/// paste, undo) so we never suggest on a wrong context.
final class TypedInputBuffer {
    private var chars: [Character] = []
    private let maxLength: Int

    init(maxLength: Int = 2048) { self.maxLength = max(1, maxLength) }

    var preContext: String { String(chars) }

    func type(character: Character) {
        chars.append(character)
        if chars.count > maxLength { chars.removeFirst(chars.count - maxLength) }
    }

    func deleteBackward() {
        if !chars.isEmpty { chars.removeLast() }
    }

    /// Cursor may have moved unpredictably (arrow/click/paste/undo). Drop everything.
    func invalidate() { chars.removeAll() }

    /// Focus moved to a different field. Drop everything.
    func focusChanged() { chars.removeAll() }
}
