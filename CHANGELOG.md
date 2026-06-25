# Changelog

All notable changes to BetterScreenshot. Versions are git tags; releases are published on [GitHub](../../releases).

## Unreleased

> Merged to `main`, not yet tagged/released. The locally deployed build still reports version 2.3.2 (no version bump). Design + implementation: `docs/superpowers/specs/2026-06-25-betterscreenshot-editor-defaults-and-stack-button-design.md`.

### Added
- **Sticky annotation defaults.** The annotation editor now remembers the
  stroke/text **color** and **size** (S/M/L) you last used and reopens with
  them, instead of always starting on red / medium. Your choice persists across
  captures and app restarts (stored locally in `UserDefaults`). The active tool
  still defaults to Arrow.
- **"Stack" button in the editor (replaces "Pin").** The editor's bottom action
  bar now has a **Stack** button that drops the finished, annotated screenshot
  into the bottom-right Quick Access stack alongside your other captures — with
  the usual Copy / Edit / Pin / Save / drag actions — records it to History, then
  closes the editor. Pin-to-Screen is unchanged and still available from the
  Quick Access thumbnail's own Pin button.

## v2.3.2 — 2026-06-11 · History Clear All

### Added
- **Clear All in the History window.** The history browser now has a
  **Clear All…** button (next to the item count) that wipes every remembered
  capture after a confirmation. Bulk-clearing was previously only reachable from
  Settings → General → History. As before, saved recording files on disk are
  not deleted.

## v2.3.1 — 2026-06-08 · UI fixes

### Fixed
- **Selection dimensions label no longer clips off-screen.** When you drag an
  area selection near the top of a display, the `W × H` label now tucks just
  inside the selection's top edge instead of drawing past the screen edge where
  it was cut off.
- **Quick Access overlay buttons are evenly spaced.** The post-capture button
  row now sizes to its buttons and centers under the thumbnail, so the 4-button
  (recording) and 5-button (screenshot) variants are both balanced — the old
  fixed-width row left the 5-button screenshot variant cramped.

## v2.3.0 — 2026-06-05 · Capture history

- **Capture History.** Every screenshot (including copy-only captures that used
  to vanish with the clipboard) and every finished recording is remembered
  locally — browse them in the new **History…** window from the menu bar:
  thumbnail grid, copy / annotate / pin / show-in-Finder / delete per item,
  double-click to edit (screenshots) or play (recordings).
- **Restore Recently Closed.** Accidentally ✕-closed (or stack-evicted) Quick
  Access thumbnails can be brought back from the menu bar; deliberate actions
  (save, annotate, pin, drag-out) don't count as accidental.
- **Settings → General → History:** keep-history toggle, 10/50/200 item cap,
  and Clear History. Retention also prunes entries older than 30 days. All
  local — history lives in `~/Library/Application Support/BetterScreenshot/History/`.
- Both new commands are bindable hotkeys (unbound by default) in
  Settings → Shortcuts.

## v2.2.0 — 2026-06-05 · Reliability + infra

### Fixed
- **Screenshot save failures are now visible.** A HUD toast appears when a save fails
  (e.g. disk full, permission denied); if the configured save folder is missing the app
  creates it automatically — previously a moved or deleted folder lost the capture silently.
- **Capture / Capture Text failures surface a HUD** instead of failing silently.
- **Recordings: save folder is auto-created** on start. Denied microphone permission now
  records without a mic track and shows a HUD explaining this — previously it wrote a
  silent empty audio track.
- **Fixed a race between recording stop and in-flight frames** that could crash the
  AVAssetWriter.
- **App relaunch (onboarding)** no longer breaks when the install path contains
  quotes or other shell-special characters.

### Improved
- **Editor performance.** Dragging and annotating large screenshots is much faster;
  the canvas no longer re-flattens the full-resolution image on every mouse move.
- **Editor: counter badge** now centers on the click point rather than offset from it.
- **Editor keyboard focus.** Delete and `[` / `]` keys work immediately without
  clicking the canvas first; focus returns to the canvas automatically after typing text.
- **VoiceOver labels** added to all image-only buttons: Quick Access overlay, record
  strip toggles, editor toolbar, and pin close button.
- **Quick Access overlay + HUD** now appear over full-screen apps. Copy shows feedback
  from every surface. Overlay buttons are equal-width on both card types.

### Infrastructure
- **Tests:** blur/pixelate redaction is now verified to actually obscure content;
  suite total 87 tests across all packages.
- **CI:** GitHub Actions workflow + `scripts/test.sh` run all four suites on every
  push and pull request.
- **Docs:** build instructions corrected (SwiftPM, not XcodeGen).

## v2.1-recording-feedback — 2026-06-05

- **Recording thumbnail.** Finished recordings now show the same bottom-corner
  Quick Access thumbnail screenshots get — blue-tinted so it reads as a recording —
  with Copy file / Open / Show in Finder buttons and drag-out of the saved file.
  Recording and screenshot overlays share one stack, so they never overlap.
- **Record strip toggle feedback.** The mic, system-audio, and camera buttons now
  turn accent-blue while enabled (like the MP4/GIF selector), so you can see at a
  glance what the recording will include.

## v2.0-recording — 2026-06-04

- **Screen recording (P2).** ⌘⇧5 is a smart toggle: press to open the record strip
  (full screen or drag an area; MP4/GIF, mic, system audio, camera toggles), press
  again to stop. Menu bar shows a red stop button with an elapsed timer.
- **MP4 + GIF output** — H.264 at 30/60 fps; GIF recordings convert automatically
  (10 fps, ≤960 px) and fall back to MP4 if conversion fails.
- **Audio** — system audio (ScreenCaptureKit) and microphone (separate track).
- **Camera bubble** — circular live webcam overlay, drag to move, two sizes.
- **Click highlights** (no extra permission) and **keystroke display**
  (Accessibility-gated, off by default).
- New Settings → Recording tab; "Start/Stop Recording" is rebindable in Shortcuts.
- Native macOS ⌘⇧5 (screenshot toolbar) is shadowed while the app runs, like ⌘⇧4.

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
