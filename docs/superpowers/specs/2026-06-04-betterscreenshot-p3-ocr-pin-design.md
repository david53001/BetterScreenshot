# BetterScreenshot P3 — OCR (Capture Text) + Pin to Screen

Date: 2026-06-04 · Status: **shipped 2026-06-04** (tag `v1.3-ocr-pin`; see CHANGELOG.md)
Builds on: v1.2 (`main`) · Ends at tag: `v1.3-ocr-pin`

## Goal

Ship the two highest value-to-effort CleanShot features still missing (spec §5, §7):

1. **Capture Text (OCR + QR)** — drag a region; recognized text lands on the clipboard. If the region contains a QR code, its payload is copied instead. Confirmation HUD either way.
2. **Pin to Screen (full experience)** — pin any capture as a floating always-on-top panel: drag to move, resize (corner-drag + scroll-zoom), rounded corners + shadow, double-click to copy, hover close button, right-click menu. Entry points: Quick Access overlay, editor toolbar, menu-bar "Pin from Clipboard".
3. **Quick Access stack** (added 2026-06-04) — up to **3** post-capture overlays stack vertically at the configured corner instead of each new capture replacing the previous thumbnail.

**Feasibility verified up front** (probe run 2026-06-04 on this CLT-only machine): headless `VNRecognizeTextRequest` read rendered text exactly, and `VNDetectBarcodesRequest` decoded a `CIQRCodeGenerator` QR exactly. Recognition logic is therefore fully testable in TestKit with real Vision calls — no screen permission needed when feeding `CGImage`s.

## Out of scope

Screen recording (P2) · scrolling capture, backgrounds, history (P4) · `betterscreenshot://` URL scheme (P5) · OCR review-before-copy popup and linebreak settings (deferred; default is **keep** linebreaks) · pin persistence across app restarts · per-pin styling UI (styling comes from Settings at pin creation).

## UX flows

### Capture Text — hotkey ⌘⇧7, menu item "Capture Text"
1. Permission check (same one-button setup flow as other captures).
2. Existing selection overlay (`SelectionOverlayController`) — same crosshair UX as area capture.
3. Region is captured via `CaptureService` (`.area`), then recognized **off the main thread**.
4. Result rule (deterministic): any decoded **QR → copy payload**; else recognized **text → copy** lines joined with `\n`; else nothing copied.
5. HUD confirms: "QR code copied" / "Text copied — N characters" / "No text found". HUD is a small floating panel near the bottom-center of the capture's screen, auto-dismisses after ~1.5 s.

### Pin to Screen
Entry points:
- **Quick Access overlay**: new pin button (`pin` SF symbol). Dismisses the overlay, pins the capture **at its original on-screen location** (the capture rect is threaded through the coordinator); falls back to screen-center when unknown (window/fullscreen captures, clipboard).
- **Editor toolbar**: "Pin" button — flattens the current document and pins it; editor window stays open.
- **Menu bar**: "Pin from Clipboard" — pins the clipboard image (disabled when the clipboard has no image).

Pin panel behavior:
- Borderless, non-activating `NSPanel`, level `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]` — visible on every Space, never steals focus.
- Shown at the image's **point size** (pixels ÷ screen backing scale), clamped to 80% of the screen's visible frame.
- **Move**: drag anywhere. **Resize**: drag the bottom-right 16 pt hotspot or scroll-wheel zoom; both scale proportionally, clamped 0.25×–3× natural size.
- **Double-click**: copy image to clipboard + "Copied" HUD.
- **Hover**: close button (✕) fades in at top-left.
- **Right-click**: Copy Image · Save Image (to the configured save directory) · Close Pin.
- **Styling** (from Settings at creation time): corner radius slider 0–20 pt (default 8) + shadow toggle (default on).
- Multiple simultaneous pins supported; pins live until closed or the app quits.

### Quick Access stack (up to 3)
- New captures no longer replace the existing post-capture thumbnail: up to **3** overlays stack at the configured corner (default bottom-right), 12 pt apart — the newest sits at the corner slot, older ones step away from the screen edge (upward for bottom corners, downward for top corners).
- A **4th capture evicts the oldest** overlay — identical to clicking its ✕ (in show-overlay mode an evicted capture is gone; save it first if you want it).
- Dismissing any overlay (✕, save, drag-out, annotate, pin) **compacts the stack** — the remaining thumbnails slide to fill the gap.
- Each stacked overlay keeps its full, independent action row (copy / edit / pin / save / ✕ / drag).

### Settings additions
- "Pin appearance": corner radius slider + shadow toggle (stored in `CaptureSettings`, round-trips through the existing string-dictionary persistence).

## Architecture

Follows the established package split; alternatives considered and rejected: a new `RecognitionKit`/`PinKit` package (extra scaffolding for ~6 files) and app-target-only code (loses TestKit coverage).

### CaptureKit (has TestKit tests)
- `RecognitionResult.swift` — `enum RecognitionResult: Equatable { case qr(String), text(String), none }` + pure `RecognitionResolver.resolve(qrPayloads:[String], textLines:[String]) -> RecognitionResult` (QR wins; lines joined with `\n`; empty → `.none`) and `RecognitionResult.hudMessage`.
- `OverlayPositioner.stackedOrigin(corner:overlaySize:screenFrame:margin:index:spacing:)` — pure: the existing corner origin offset by `index × (height + spacing)` away from the screen edge.
- `TextRecognizer.swift` — thin Vision wrapper: `recognize(in: CGImage) async throws -> RecognitionResult`. `VNRecognizeTextRequest` (`.accurate`, `usesLanguageCorrection`, `automaticallyDetectsLanguage`) + `VNDetectBarcodesRequest` (`.qr`), feeding `RecognitionResolver`.
- Tests: pure resolver unit tests + end-to-end probe-style tests (render text / generate QR headlessly → recognize → assert).

### OverlayKit (gains a TestKit test target, mirroring CaptureKit's manifest)
- `PinGeometry.swift` — pure: initial frame (point size from pixel size + backing scale, clamp to 80% visible frame, center-on-rect or center-on-screen) and `scaledFrame(natural:current:scale:)` with 0.25×–3× clamping around the panel center.
- `PinPanelController.swift` — manages the set of live pins; `pin(image: NSImage, near: CGRect?, on: NSScreen, style: PinStyle, actions: PinActions)`. `PinStyle` = corner radius + shadow flag. `PinActions` = `onCopy`/`onSave` callbacks (App supplies them, OverlayKit stays generic).
- `PinView.swift` — content view: drag-move, corner-drag/scroll resize, hover close button (tracking area owned by the view itself — an `NSObject`, avoiding the v1.0 tracking-area crash), double-click copy, context menu.
- `HUDController.swift` — `show(_ message: String, on screen: NSScreen)`; small rounded panel, auto-dismisses ~1.5 s. Used by OCR results and pin copy.
- `QuickAccessOverlayController` — `QuickAccessActions` gains `onPin: () -> Void`; pin button added to the button row. Also gains `onDismissed: (() -> Void)?` (fired once per visible-overlay teardown) and `move(to:)` so a stack manager can compact it.
- `QuickAccessStackController.swift` — owns up to 3 `QuickAccessOverlayController`s (index 0 = newest at the corner slot), evicts the oldest beyond 3, restacks on any dismissal. Positioning is injected as an `originForIndex: (Int) -> CGPoint` closure supplied by the App (so OverlayKit stays free of CaptureKit).
- Tests: `PinGeometry` unit tests.

### EditorKit
- `EditorWindowController` — `onPin: ((CGImage) -> Void)?` + toolbar "Pin" button that flattens via the existing `DocumentRenderer` path.

### App
- `CaptureCoordinator` — new `captureText()` (overlay → capture → recognize → clipboard + HUD); capture rect threaded through `run`/`handle` as `sourceRect: CGRect?` so pins land where captured; `pin(_ image: CGImage, near: CGRect?)` helper wiring `PinPanelController` with style from settings and copy/save actions reusing the existing `copy`/`save` paths; `pinFromClipboard()`; swaps the single `QuickAccessOverlayController` for `QuickAccessStackController`, supplying `OverlayPositioner.stackedOrigin` as the slot-position closure.
- `BetterScreenshotApp` — register ⌘⇧7 → `captureText()` (no native macOS conflict).
- `MenuBarController` — add "Capture Text" and "Pin from Clipboard" items (+ separator), clipboard item validated via `NSMenuItemValidation`.
- `SettingsView` — pin appearance section.

## Error handling

- Recognition failure (Vision throws) → log + "No text found" HUD; never crash the capture flow.
- Pin with zero-size/invalid image → ignore (log).
- Clipboard pin with no image → menu item disabled, action also guards.
- OCR runs in a `Task` off the main actor; UI work (clipboard, HUD) hops back to `@MainActor`.

## Testing

- **TestKit (automated)**: resolver rules (QR precedence, line joining, empty), end-to-end Vision recognition on rendered images (proven feasible by probe), `PinGeometry` placement/clamping, `OverlayPositioner.stackedOrigin` slots/directions, `CaptureSettings` round-trip with new keys.
- **Manual checklist (GUI)**: ⌘⇧7 flow incl. multi-display; QR vs text precedence on a real screen; pin from all three entry points; move/resize/zoom/double-click/hover-close/context-menu; pins across Spaces; settings styling applied; no focus stealing; 3-deep overlay stack, 4th-capture eviction, compaction on dismissal.

## Build order (one plan)

1. `RecognitionResolver` + `RecognitionResult` (TDD, pure) → 2. `TextRecognizer` Vision wrapper (TDD, headless end-to-end) → 3. `PinGeometry` + OverlayKit test target (TDD) → 4. `HUDController` + `PinPanelController`/`PinView` → 5. App wiring: `captureText`, ⌘⇧7, menu items → 6. Pin entry points (overlay button, editor button, clipboard) + settings UI → 7. Quick Access stack (`stackedOrigin` TDD + stack controller + coordinator swap) → 8. Manual checklist, README update, tag `v1.3-ocr-pin`.
