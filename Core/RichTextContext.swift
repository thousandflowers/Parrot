import Foundation
import AppKit

struct RichTextContext: @unchecked Sendable {
    let plainText: String
    let attributedString: NSAttributedString?
    let formattingMarkers: [FormattingMarker]

    struct FormattingMarker: Sendable {
        let range: NSRange
        let isBold: Bool
        let isItalic: Bool
        let isUnderline: Bool
        let linkURL: URL?
        let fontSize: CGFloat?

        init(range: NSRange, isBold: Bool = false, isItalic: Bool = false,
             isUnderline: Bool = false, linkURL: URL? = nil, fontSize: CGFloat? = nil) {
            self.range = range
            self.isBold = isBold
            self.isItalic = isItalic
            self.isUnderline = isUnderline
            self.linkURL = linkURL
            self.fontSize = fontSize
        }
    }

    init(plainText: String, attributedString: NSAttributedString?) {
        self.plainText = plainText
        self.attributedString = attributedString
        self.formattingMarkers = Self.extractMarkers(from: attributedString, plainText: plainText)
    }

    private static func extractMarkers(from attr: NSAttributedString?, plainText: String) -> [FormattingMarker] {
        guard let attr = attr, attr.length > 0 else { return [] }
        let nsText = plainText as NSString
        var markers: [FormattingMarker] = []
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, attrRange, _ in
            let font = attrs[.font] as? NSFont
            let isBold = (font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
                || font?.fontName.contains("Bold") == true
            let isItalic = (font?.fontDescriptor.symbolicTraits.contains(.italic) == true)
                || font?.fontName.contains("Italic") == true
            let underline = attrs[.underlineStyle] as? Int
            let isUnderline = (underline != nil && underline != 0)
            let link = attrs[.link] as? URL

            let hasFormatting = isBold || isItalic || isUnderline || link != nil
            guard hasFormatting else { return }

            let plainRange: NSRange
            if attrRange.location + attrRange.length <= nsText.length {
                plainRange = attrRange
            } else {
                let safeEnd = min(attrRange.location + attrRange.length, nsText.length)
                guard safeEnd > attrRange.location else { return }
                plainRange = NSRange(location: attrRange.location, length: safeEnd - attrRange.location)
            }

            markers.append(FormattingMarker(
                range: plainRange,
                isBold: isBold,
                isItalic: isItalic,
                isUnderline: isUnderline,
                linkURL: link,
                fontSize: font?.pointSize
            ))
        }
        return markers
    }

    func reapplyFormatting(to correctedText: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: correctedText)
        guard !formattingMarkers.isEmpty else { return result }

        for marker in formattingMarkers {
            let correctedLen = (correctedText as NSString).length
            guard marker.range.location < correctedLen else { continue }
            let clampedLength = min(marker.range.length, correctedLen - marker.range.location)
            let originalRange = NSRange(location: marker.range.location, length: clampedLength)
            guard originalRange.length > 0 else { continue }

            let originalSubstring = (plainText as NSString).substring(with: marker.range)
            let currentSubstring = (correctedText as NSString).substring(with: originalRange)
            if originalSubstring == currentSubstring {
                if marker.isBold {
                    result.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: marker.fontSize ?? NSFont.systemFontSize), range: originalRange)
                }
                if marker.isItalic {
                    let font = NSFont.systemFont(ofSize: marker.fontSize ?? NSFont.systemFontSize)
                    let italicDesc = font.fontDescriptor.withSymbolicTraits(.italic)
                    result.addAttribute(.font, value: NSFont(descriptor: italicDesc, size: marker.fontSize ?? NSFont.systemFontSize) ?? font, range: originalRange)
                }
                if marker.isUnderline {
                    result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: originalRange)
                }
                if let link = marker.linkURL {
                    result.addAttribute(.link, value: link, range: originalRange)
                }
            }
        }
        return result
    }
}
