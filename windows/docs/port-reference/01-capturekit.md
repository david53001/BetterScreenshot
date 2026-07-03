# Port Reference — CaptureKit (ground truth for the C#/.NET port)

Source of truth = the Swift `Packages/CaptureKit`. This file captures the exact behavior,
constants, and test assertions to re-implement in `BetterScreenshot.Capture`.

## Files & responsibilities (Swift → C# target namespace `BetterScreenshot.Capture`)
- `CaptureTarget` — enum: `Area(Rect, displayId)`, `Fullscreen(displayId)`, `Window(windowId)`.
- `CaptureService` — screen-capture wrapper (SCK → Windows.Graphics.Capture / GDI BitBlt). `capture(target) -> image`.
- `CaptureSettings` — settings struct + dictionary round-trip (see keys below).
- `CaptureGeometry` — PURE: global rect → top-left pixel rect. **Port-critical.**
- `ImageCropper` — PURE: crop image to pixel rect; clamp; nil if zero-area.
- `ImageEncoder` — PURE: image → PNG / JPG(quality) bytes.
- `FileNamer` — PURE: timestamped filename.
- `HotkeyAction` / `HotkeyCombo` / `HotkeyBindings` — hotkey model + persistence + conflict detection.
- `OverlayPositioner` — PURE: overlay window origin per corner + stacking.
- `TextRecognizer` / `RecognitionResult` / `RecognitionResolver` — OCR + QR (Vision → Windows.Media.Ocr + ZXing).
- `TempImageWriter` — write PNG to unique temp subdir.
- `WindowPicking` / `PickableWindow` — hit-test frontmost normal window at point, exclude own PID.

## CaptureGeometry (PURE — must match tests exactly)
macOS formula (Cocoa bottom-left points → top-left pixels):
```
xLocal    = (rect.minX - display.minX) * scale
yTopLocal = (display.maxY - rect.maxY) * scale     // Y-FLIP
width     = rect.width  * scale
height    = rect.height * scale
```
**Windows note:** GDI/Graphics.Capture are already top-left origin, so the Windows selection
overlay should emit top-left rects and the transform becomes:
`xLocal=(rect.x-display.x)*scale; yLocal=(rect.y-display.y)*scale; w=rect.w*scale; h=rect.h*scale`.
Keep a pure function + unit tests mirroring the mac tests (adjusted for no Y-flip).
Tests to mirror: display 1440x900 @scale2, sel (100,100,200,150) → (200,1300,400,300) [mac];
display at (1440,0) 1920x1080, sel (1540,80,100,100) → (100,900,100,100) [mac offset].

## ImageCropper (PURE)
- Round rect to integral, intersect with `[0,0,W,H]`, return null if resulting w<1 or h<1.
- Tests: 200x100 crop (10,20,50,30)→50x30; 100x100 crop (90,90,50,50)→10x10 (clamped); crop (0,0,0,0)→null.

## ImageEncoder (PURE)
- PNG (lossless) and JPG(quality in [0,1]).
- Tests: PNG starts `89 50 4E 47`; JPEG starts `FF D8`.

## FileNamer (PURE)
- Format: `"{prefix} yyyy-MM-dd 'at' HH.mm.ss.{ext}"`, culture invariant (en_US_POSIX), default prefix `Screenshot`.
- Example: `Screenshot 2026-06-02 at 14.32.10.png`. Recording prefix `Recording` → `Recording 1970-01-01 at 00.00.00.mp4`.
- NOTE: **dots** as time separators (Windows-safe already; `:` is illegal on Windows anyway).

## CaptureSettings — defaults & persistence (dictionary of string→string)
```
afterCapture:            showOverlay        (enum: copyOnly|saveOnly|copyAndSave|showOverlay)
format:                  png                (enum: png|jpg)
overlayCorner:           bottomRight        (enum: topLeft|topRight|bottomLeft|bottomRight)
overlayAutoDismissSeconds: 6                (Int)
pinCornerRadius:         8                  (Int)
pinShadow:               true               (Bool)
historyEnabled:          true               (Bool)
historyCap:              50                 (Int)
```
All fields round-trip through the dictionary; unit-test round-trip of every field.

## Hotkeys — default map (THE default bindings to replicate)
Actions (9): `captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard,
record, openHistory, restoreRecentlyClosed, pauseResumeRecording`.

Defaults (mac glyphs → Windows uses Ctrl+Shift+<n> as the equivalent, see App reference):
| Action | mac default | Windows default (this port) |
|---|---|---|
| captureArea | ⌘⇧4 | Ctrl+Shift+4 |
| captureWindow | ⌘⇧8 | Ctrl+Shift+8 |
| captureFullscreen | ⌘⇧6 | Ctrl+Shift+6 |
| captureText | ⌘⇧7 | Ctrl+Shift+7 |
| record | ⌘⇧5 | Ctrl+Shift+5 |
| pinFromClipboard | (unbound) | (unbound) |
| openHistory | (unbound) | (unbound) |
| restoreRecentlyClosed | (unbound) | (unbound) |
| pauseResumeRecording | (unbound) | (unbound) |

`HotkeyCombo` persists as `"keyCode,modifiers"` or sentinel `"unbound"`; missing key ⇒ use default (migration path).
Validity: must include a non-shift modifier (Ctrl/Alt/Win) — reject shift-only. Conflict detection across actions.
On Windows use Win32 `RegisterHotKey` (MOD_CONTROL|MOD_SHIFT, VK '4'..'8'). Display strings show `Ctrl+Shift+4` etc.

## OverlayPositioner (PURE) — corners + stacking
Windows top-left screen coords version (adapt from mac bottom-left):
```
topLeft:     (x + margin,               y + margin)
topRight:    (x + W - w - margin,       y + margin)
bottomLeft:  (x + margin,               y + H - h - margin)
bottomRight: (x + W - w - margin,       y + H - h - margin)
```
Stacking: index 0 = at corner; each step offsets by `(h + spacing)` where spacing default **12**.
Bottom corners stack upward (subtract), top corners stack downward (add). Mirror mac tests with the
sign convention appropriate to top-left origin.

## OCR / QR (TextRecognizer + RecognitionResolver)
- Resolve rule (PURE, must match tests): **first QR payload wins**; else drop blank text lines, join with `\n`;
  else `.none`.
- `clipboardString`: qr→payload, text→text, none→null.
- `hudMessage`: qr→`"QR code copied"`, text→`"Text copied — {N} characters"`, none→`"No text found"`.
- Windows: `Windows.Media.Ocr.OcrEngine` (accurate, language auto) + `ZXing.Net` for QR. Match `hudMessage` strings verbatim.

## WindowPicking
- `topmost(point, windows, excludingPID)`: front-to-back order, return first window with `layer==0`
  containing the point and `ownerPID != excludingPID`.
- On Windows: enumerate top-level windows in Z-order (`GetTopWindow`/`GetWindow(GW_HWNDNEXT)`),
  `GetWindowRect`, skip own process (`GetCurrentProcessId`), skip cloaked/invisible.

## Complete test list to re-create (xUnit)
CaptureGeometry(2), ImageCropper(3), ImageEncoder(2), FileNamer(2), HotkeyAction(1),
HotkeyCombo(6), HotkeyBindings(8), OverlayPositioner(6), RecognitionResolver(6),
TempImageWriter(1), WindowPicking(5), TextRecognizer(4, hardware-gated), CaptureSettings(6).
Pure-logic suites must pass in CI; capture/OCR/window suites are hardware-gated (skippable).
