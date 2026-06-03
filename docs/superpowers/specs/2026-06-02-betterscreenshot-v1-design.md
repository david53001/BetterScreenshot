# BetterScreenshot — v1 Design Spec

- **Date:** 2026-06-02
- **Status:** Approved (design); pending implementation plan
- **Scope of this doc:** Phase 1 ("the screenshot tool") only. Later phases are sketched in the roadmap but specced separately.
- **Feature reference:** `CLEANSHOT-X-FEATURE-SPEC.md` (verified CleanShot X feature inventory this clone targets).

## 1. Context & Goal

BetterScreenshot is a free, local macOS clone of CleanShot X's **non-cloud** features. The full feature set decomposes into ~7 independent subsystems (capture, recording, annotation editor, OCR, post-capture overlay, menu-bar/hotkey shell, settings). This spec covers **v1 = the screenshot tool**: capture an image, optionally annotate it, and get it to the clipboard or disk. Cloud features are permanently out of scope.

## 2. Foundational Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Language / UI | Swift, **SwiftUI + AppKit hybrid** | SwiftUI for settings/menus; AppKit (`NSPanel`, custom `NSView`) for overlays and the editor canvas. |
| Min OS | **macOS 14 Sonoma** | Mature ScreenCaptureKit + content picker, solid Vision OCR (for later), modern SwiftUI; covers ~all active Macs. Adjustable later. |
| App type | **Menu-bar agent** (`LSUIElement = true`), **non-sandboxed** | Full system access for hotkeys, capture, save-anywhere, always-on-top overlays. No Dock icon. |
| Distribution | **Personal / local, ad-hoc signed** | No Apple Developer account needed now. Developer ID signing + notarization can be added later without rearchitecting. |
| Editor canvas | **Custom `NSView` + retained model** | Standard way to build a manipulable vector editor; full control over selection/drag/z-order/live-text; export = re-draw the same model into an image context. |

## 3. v1 Scope

**In scope:**
- Capture modes: **area** (drag-to-select), **fullscreen**, **window**.
- Capture overlay aids: **crosshair**, **magnifier/loupe**, **live dimensions readout**, screen **dimming** outside selection, **Esc to cancel**.
- **Quick Access Overlay**: floating thumbnail after capture with actions — copy, save, annotate (open editor), drag-out to other apps, dismiss.
- **Annotation editor** (tools in §5).
- **Output**: copy to clipboard; save to a configurable folder. Formats **PNG** (default) and **JPG**.
- **Settings**: hotkey bindings, after-capture behavior, save location, default format.

**Out of scope for v1 (later phases):** screen recording, webcam, click/keystroke visualization, OCR, pin-to-screen, scrolling capture, background/wallpaper styling, freeze-screen, self-timer, repeat-last-area, capture history/restore, file-naming templates, the `cleanshot://`-style URL automation API, and all cloud features.

## 4. Architecture — Modules

Each is a local Swift package depended on by the app target, kept isolated and unit-testable.

### `CaptureKit`
- **Does:** Wraps ScreenCaptureKit. Enumerates displays and windows; grabs a single frame as a `CGImage`; performs region-crop math across multi-display coordinate spaces. Detects Screen-Recording (TCC) permission state.
- **Interface:** `grab(target:) async throws -> CapturedImage` where `target` is `.area(rect, display)`, `.fullscreen(display)`, or `.window(id)`. `CapturedImage` bundles the `CGImage` + source metadata (display scale, origin).
- **Depends on:** ScreenCaptureKit, CoreGraphics.

### `OverlayKit`
- **Does:** Owns the floating UI. Two panels, both non-activating `NSPanel` at a floating window level: (1) the **capture-selection overlay** (crosshair, magnifier, dimming, dimensions, drag handles); (2) the **Quick Access Overlay** thumbnail with action buttons + drag-out source.
- **Interface:** `presentSelection() async -> SelectionResult` (rect + display, or cancelled); `presentQuickAccess(image:, actions:)`.
- **Depends on:** AppKit only. No capture or file logic.

### `EditorKit`
- **Does:** The annotation editor. Holds a **document model** — an ordered list of annotation objects over a base image. A custom `NSView` renders the model and handles selection handles, dragging, resizing, z-order, and inline text editing. Exports by flattening the model into an image context.
- **Key design:** a single `render(document:, into: CGContext)` path is reused for both on-screen drawing and export, so what you see equals what you save.
- **Interface:** `EditorWindowController(image:)`; emits `export() -> CGImage`.
- **Depends on:** AppKit, CoreGraphics, CoreImage (blur/pixelate filters).

### `AppCore` (app target)
- **Does:** Global hotkeys via Carbon `RegisterEventHotKey` (**no Accessibility permission required**); the menu-bar menu; settings store (`UserDefaults`); file output (PNG/JPG encode, save, clipboard); and the orchestration wiring capture → overlay → editor → output.
- **Depends on:** all three packages above.

## 5. Editor Tools (v1)

Each tool is a model object supporting select / move / resize / delete / reorder:

- **Arrow** (straight), **Line**, **Rectangle** (outline + filled), **Ellipse**
- **Text** (font size + color)
- **Blur** and **Pixelate** (redaction; CoreImage filters over a region)
- **Crop** (with edge snapping)
- **Counter** (numbered step badges, auto-incrementing)
- **Color picker** (stroke/fill color, with a few saved swatches)

*Stretch if cheap:* highlighter, pencil (freehand). *Deferred:* curved arrows, spotlight, emoji, backgrounds.

## 6. Data Flow

```
hotkey (AppCore)
  → CaptureKit.grab(target) → CapturedImage
  → AppCore routes by "after capture" setting:
       • direct copy  → clipboard
       • direct save  → save folder
       • show overlay → OverlayKit Quick Access thumbnail
  → user clicks "Annotate"
  → EditorKit opens on the image; edits mutate the model (live redraw)
  → export() flattens model → PNG/JPG
  → clipboard or save folder
```

## 7. Output & Settings

- **Formats:** PNG (default), JPG. (WebP deferred — unconfirmed in CleanShot and not needed for v1.)
- **Filename:** timestamp default (e.g. `Screenshot 2026-06-02 at 14.32.10.png`). Full naming templates deferred.
- **Save location:** user-configurable folder (default `~/Desktop`).
- **Settings pane (SwiftUI):** hotkey bindings; after-capture behavior (overlay / direct-copy / direct-save); save location; default format.

## 8. Permissions & Error Handling

- **Screen Recording (TCC):** required by ScreenCaptureKit. On first run or denial, detect state and present a guided panel that deep-links to System Settings → Privacy & Security → Screen Recording. App must degrade gracefully (no crash, clear messaging) until granted.
- **Global hotkeys:** Carbon `RegisterEventHotKey` avoids the Accessibility/Input-Monitoring prompt. Handle registration failure (hotkey already claimed by another app) with a clear settings-pane error.
- **Explicit handled cases:** empty/zero-size selection, Esc-cancel, capture spanning multiple displays (coordinate normalization), and the editor opening on a nil/failed image.

## 9. Testing Strategy

- **TDD on pure logic** (write tests first):
  - EditorKit model: add/move/resize/delete/z-order, hit-testing.
  - Export render correctness via golden-image comparison (render model → compare to fixture).
  - Region/crop math across display scales and origins.
  - Filename generation.
- **Manual verification** (scripted checklist) for permission flows, hotkey registration, and overlay interaction — these are system-UI heavy and not meaningfully unit-testable.

## 10. Phase Roadmap (post-v1)

Each phase gets its own spec → plan → build cycle.

- **P2 — Recording:** MP4/GIF, mic + system audio, webcam overlay, mouse-click & keystroke visualization, countdown, pause/resume, trim editor.
- **P3 — OCR & Pin:** on-device Vision "Capture Text" → clipboard; pin-to-screen floating overlays.
- **P4 — Capture polish & styling:** background/wallpaper styling (padding, rounded corners, shadow), scrolling capture, freeze-screen, self-timer, repeat-last-area, capture history + restore.
- **P5 — Automation:** `betterscreenshot://` URL-scheme command surface (mirroring CleanShot's documented API, minus cloud).

## 11. Open Questions / Future Decisions

- Whether to widen the OS floor below macOS 14 (only if a real user needs it).
- Self-timer delay configurability and window-capture transparent-background behavior — flagged as unverified in the feature spec; resolve against the live app when P4 is specced.
- Developer ID signing + notarization pipeline — defer until distributing to others.

## 12. References

- `CLEANSHOT-X-FEATURE-SPEC.md` — verified target feature inventory.
- ScreenCaptureKit, Vision, CoreImage, AppKit (`NSPanel`), Carbon `RegisterEventHotKey`.
