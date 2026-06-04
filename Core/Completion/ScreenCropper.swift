import CoreGraphics

/// Pure geometry for screen-context capture: the pixel rect of a window image that lies strictly
/// ABOVE the caret. OCR'ing only this region captures the conversation/email being replied to while
/// never including the user's input field — which is what makes screen context safe from the
/// model-reads-its-own-output feedback loop.
///
/// All inputs are top-left origin (y down): `windowBounds` and `caretRectTopLeft` in screen points,
/// `imageSize` in pixels. The caller converts the AX caret (Cocoa bottom-left) to top-left first.
enum ScreenCropper {
    /// Minimum captured height (px) worth OCR'ing — below this there is nothing useful above.
    static let minHeightPx: CGFloat = 16

    static func cropAboveCaret(windowBounds: CGRect, caretRectTopLeft: CGRect, imageSize: CGSize) -> CGRect? {
        guard windowBounds.width > 0, windowBounds.height > 0,
              imageSize.width > 0, imageSize.height > 0 else { return nil }

        let caretTopFromWindow = caretRectTopLeft.minY - windowBounds.minY
        guard caretTopFromWindow > 0 else { return nil }

        let scaleY = imageSize.height / windowBounds.height
        let cropH = min(imageSize.height, caretTopFromWindow * scaleY)
        guard cropH >= minHeightPx else { return nil }

        return CGRect(x: 0, y: 0, width: imageSize.width, height: cropH)
    }
}
