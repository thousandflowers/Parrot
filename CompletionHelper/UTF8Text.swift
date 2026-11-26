/// Pure UTF-8 helpers for the generation loop. A token piece is raw bytes that may end (or begin)
/// in the middle of a multi-byte character — emoji, accented letters and CJK are often split across
/// two or more tokens. Decoding each piece on its own turns every split character into U+FFFD, so
/// the loop accumulates bytes and decodes once at the end with this helper.
enum UTF8Text {
    private static let maxSequenceLength = 4

    /// Decodes `bytes`, first dropping an INCOMPLETE trailing multi-byte sequence (the generation
    /// budget can stop mid-character). Invalid bytes elsewhere still decode to U+FFFD.
    static func decodeDroppingIncompleteTail(_ bytes: [UInt8]) -> String {
        String(decoding: bytes.prefix(completePrefixLength(bytes)), as: UTF8.self)
    }

    /// Length of `bytes` without a trailing lead byte whose continuation bytes have not arrived yet.
    static func completePrefixLength(_ bytes: [UInt8]) -> Int {
        // Walk back over at most (maxSequenceLength - 1) continuation bytes to the lead byte.
        var i = bytes.count - 1
        let floor = max(0, bytes.count - maxSequenceLength)
        while i >= floor, isContinuation(bytes[i]) { i -= 1 }
        guard i >= floor else { return bytes.count }          // no lead byte in reach → leave as is
        let expected = sequenceLength(lead: bytes[i])
        let available = bytes.count - i
        return expected > 1 && available < expected ? i : bytes.count
    }

    private static func isContinuation(_ b: UInt8) -> Bool { b & 0b1100_0000 == 0b1000_0000 }

    private static func sequenceLength(lead b: UInt8) -> Int {
        switch b {
        case 0b1100_0000...0b1101_1111: return 2
        case 0b1110_0000...0b1110_1111: return 3
        case 0b1111_0000...0b1111_0111: return 4
        default: return 1                                     // ASCII or invalid lead
        }
    }
}
