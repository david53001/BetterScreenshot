# Changelog

All notable changes to BetterScreenshot. Versions are git tags; releases are published on [GitHub](../../releases).

## v1.4-shortcuts — 2026-06-04

- **Fixed: the Settings window now opens.** macOS 14 silently broke the private
  selector the menu item relied on; the app now owns its settings window directly.
- **Customizable shortcuts.** New Settings → Shortcuts tab: click a shortcut well,
  type a new combo, it applies immediately and persists. Conflicts inside the app
  and combos owned by other apps/macOS are refused with an explanation.
- **New defaults:** Capture Window moved ⌘⇧5 → **⌘⇧8**; **⌘⇧5 is now reserved for
  Start/Stop Recording** (next release). Pin from Clipboard can be given a shortcut
  (unbound by default). Menu-bar items now display their current shortcuts.

## v1.3 — 2026-06-04 · OCR, Pin to Screen, Quick Access stack

The P3 release ([spec](docs/superpowers/specs/2026-06-04-betterscreenshot-p3-ocr-pin-design.md) · [plan](docs/superpowers/plans/2026-06-04-betterscreenshot-p3-ocr-pin.md)).

### Added
- **Capture Text (⌘⇧7)** — drag a region and the recognized text lands on the clipboard, entirely on-device (Vision OCR, automatic language detection). If the region contains a **QR code**, its payload is copied instead (QR wins over text). A toast confirms: "Text copied — N characters" / "QR code copied" / "No text found". Also available from the menu bar.
- **Pin to Screen** — float any capture as an always-on-top panel that follows you across Spaces and never steals focus. Drag to move; resize from the bottom-right corner or by scrolling (aspect-locked, 0.25×–3×); double-click to copy; hover for the ✕ close button; right-click for Copy / Save / Close. Entry points: the Quick Access overlay's new pin button, a **Pin** button in the annotation editor (the editor stays open), and menu bar → **Pin from Clipboard**.
- **Quick Access stack** — new captures no longer replace the post-capture thumbnail: up to **3** overlays stack at the configured corner, newest at the corner slot. A 4th capture evicts the oldest; dismissing any overlay slides the rest together.
- **Pin appearance settings** — corner radius (0–20 pt) and shadow toggle for newly created pins.
- **Launch at login** — registered once by default via `SMAppService`; toggle in Settings (stays in sync with System Settings → Login Items).
- New OverlayKit test suite (TestKit); recognition logic is covered by real headless Vision OCR/QR end-to-end tests. 66 automated tests across the three packages.

### Fixed
- Pressing a second capture hotkey (e.g. ⌘⇧7 while a ⌘⇧4 selection is open) now cancels the open selection instead of stacking orphaned overlays.
- Pin double-click registers on mouse-up, so a 1-pixel drift between clicks no longer micro-drags the pin.
- The "Copied" toast for a pin re-resolves its screen at click time, surviving display disconnects.

## v1.2 — 2026-06-04 · Public release polish

- One-button first-run setup for the Screen Recording permission (welcome window drives the whole grant flow and relaunches the app).
- Editor chrome redesign: floating tool pill, adaptive inspector, quiet bottom action bar, title-bar undo/redo; arrow rendering fix; undo/redo keys; marquee multi-select.
- Native macOS ⌘⇧4 is disabled while the app runs (restored on quit) so captures don't double-fire.
- README, MIT license, and repo hygiene for the public GitHub release.

## v1.1 — 2026-06-03 · Stability

- Fixed a crash when the cursor entered the Quick Access overlay; the overlay is now persistent (no auto-dismiss).
- Overlay download button saves to the macOS screenshot folder (`com.apple.screencapture` location); drag-out uses a self-deleting temp file.
- Stable self-signed identity (`scripts/setup-signing.sh`) so the Screen Recording grant persists across rebuilds.
- Guarded the selection overlay against double completion; sized the Quick Access thumbnail correctly.

## v1.0 — 2026-06-03 · Initial release

- **v0.1 capture core**: menu-bar app, global hotkeys (⌘⇧4/5/6), area/window/fullscreen capture via ScreenCaptureKit, save (PNG/JPG) / copy, settings.
- **v0.2 Quick Access overlay**: post-capture floating thumbnail with copy / save / annotate / drag-out.
- **v1.0 annotation editor**: arrows, lines, shapes, text, numbered counters, blur/pixelate redaction, crop, inline text editing, resize handles, object reordering, flatten-to-image export — all TDD'd against a golden-image renderer.
