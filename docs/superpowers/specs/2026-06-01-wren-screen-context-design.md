# Wren Screen Context — Design

**Date:** 2026-06-01
**Status:** Approved

## Goal

Let Wren read the conversation / email / thread *above* the input field via on-device OCR, so
completions fit the surrounding context — without the model re-reading its own output (the feedback
loop that caused screen context to be disabled originally).

## Key idea: crop above the caret (anti-loop by construction)

`ScreenContextProvider` already does on-device OCR (Apple Vision) of the focused app's front window.
The loop came from OCR'ing the *whole* window, which includes the user's input field (the model's
own ghost text / accepted output). Fix: **crop the window image to the region strictly above the
caret** before OCR. We already have `caretRect` (screen coords) in `requestSuggestion`. The region
above the caret is the conversation/email being replied to; the input field is below it and never
captured. No fragile text-stripping.

Defense in depth: also drop any OCR line equal to the current suggestion text.

## Components

- `ScreenCropper` (new, pure): given the window bounds (screen coords), the caret rect (screen
  coords), and the captured image's pixel size, returns the pixel crop rect covering the area above
  the caret. Unit-tested. Handles the y-flip (Cocoa bottom-left screen → top-left image).
- `ScreenContextProvider` (extend): `currentContext(pid:caretRect:)` crops via `ScreenCropper`
  before OCR. Falls back to the whole window when no caret is available. Existing throttle/TTL,
  off-main-actor OCR, and Screen Recording permission handling are reused.
- `CompletionController.requestSuggestion` (wire): when screen context is enabled and permission is
  granted and the app is not a code editor/terminal, fetch the cached screen context and prepend it
  to the model prompt: `screenContext + "\n" + preContext`. The base (pretrained) model continues
  naturally; no instruction framing (the model does not follow instructions). The screen text is
  capped to `completionScreenContextMaxChars` (suffix = nearest the caret = most relevant).
- `PreferencesStore` (setting): `completionScreenContextEnabled` (Bool). Default true when Screen
  Recording permission is granted; the feature no-ops without permission.

## Data flow

```
requestSuggestion → caretRect (screen) →
  if screenContextEnabled && hasPermission && !isCodeEditor:
     ScreenContextProvider.currentContext(pid:, caretRect:)   // throttled, cropped above caret, OCR
        → ScreenCropper.cropRect(window, caret, imageSize) → crop → OCR → cleaned text
  prompt preContext = screenText + "\n" + ax.preContext   (only for the model call; learned/typo/cache paths unchanged)
  → CompletionEngine.suggest → helper
```

Screen context feeds ONLY the model path. Typo-fix, emoji, learned-store, and cache keys keep using
the raw typed `preContext` (screen text must not pollute the personalized/cache keys).

## Loop / correctness safeguards

1. Crop strictly above the caret → input field never OCR'd.
2. Drop OCR lines equal to the live suggestion (defense in depth).
3. Cap length; OCR `.fast`, no language correction (context not transcription).
4. Throttled (TTL) and cached so typing never waits on OCR; a stale cached context is acceptable.

## Permission & privacy

Screen Recording is optional. Requested once when the user enables the feature. Without it, Wren
degrades to text-field-only context (current behaviour). The OCR text stays on device; nothing is
sent anywhere (same as the rest of Wren).

## Testing

- `ScreenCropper.cropRect`: caret in middle of window → crop is the upper half; caret at top → tiny
  / empty crop; y-flip correct; clamps to image bounds. Pure unit tests.
- Prompt merge: `screenText + "\n" + preContext` assembled correctly; empty screenText → unchanged.
- OCR + capture: manual integration (needs a real screen + permission).

## Out of scope

Reading other windows/apps, whole-display OCR, AX-based message extraction (possible future
backends behind the same `currentContext` interface).
