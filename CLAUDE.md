# BetterScreenshot

A **free, local macOS clone of CleanShot X** (screenshot + screen-recording tool). Native Swift app.

## Hard constraints
- **No cloud.** No uploads, share links, accounts, or cloud sync — ever. Local features only.
- **macOS-native, non-sandboxed, menu-bar agent** (`LSUIElement`). Personal/local use; ad-hoc signed (no Apple Developer account required).
- **Min target: macOS 14 (Sonoma).**

## Stack
- Swift 5.9+, **SwiftUI + AppKit hybrid** (SwiftUI for settings/menus; AppKit `NSPanel`/custom `NSView` for overlays + the editor canvas).
- ScreenCaptureKit (capture/recording), Vision (OCR, later), CoreImage (blur/pixelate), Carbon `RegisterEventHotKey` (global hotkeys — avoids the Accessibility prompt).
- **Build:** SwiftPM — `swift build`, with `scripts/build-app.sh` assembling `dist/BetterScreenshot.app` (CLT-only, no Xcode; see `docs/BUILD-NOTES.md`). Library modules are local Swift packages under `Packages/`, tested via TestKit executable runners — run all suites with `scripts/test.sh`.
- **Testing:** TDD on pure logic (geometry, encode, model, renderer) via the local TestKit harness; system/UI behavior is manually verified against checklists in the plans.

## Architecture (v1)
Local Swift packages + a menu-bar app target:
- `CaptureKit` — ScreenCaptureKit wrapper + pure geometry/crop/encode/filename logic.
- `OverlayKit` — area-selection overlay + Quick Access thumbnail (`NSPanel`).
- `EditorKit` — annotation document model + custom `NSView` canvas + tools + flatten-to-image renderer.
- `App/` (target) — hotkeys, menu bar, settings, and capture→overlay→editor→output orchestration.

**Coordinate convention:** annotations live in base-image pixel space, top-left origin; rendering uses a flipped `NSGraphicsContext` so AppKit drawing (incl. text) is right-side-up.

## Source of truth — read these before working
- `CLEANSHOT-X-FEATURE-SPEC.md` — verified target feature inventory (what we're cloning).
- `docs/superpowers/specs/2026-06-02-betterscreenshot-v1-design.md` — the v1 design.
- `docs/superpowers/plans/` — bite-sized, TDD, self-contained implementation plans:
  - `…-plan-1-foundation-capture.md` — scaffold, hotkeys, permission, capture, save/copy.
  - `…-plan-2-quick-access-overlay.md` — post-capture floating thumbnail.
  - `…-plan-3-annotation-editor.md` — the editor (model, canvas, tools, export).
- P3 (shipped v1.3): `docs/superpowers/specs/2026-06-04-betterscreenshot-p3-ocr-pin-design.md` + `docs/superpowers/plans/2026-06-04-betterscreenshot-p3-ocr-pin.md` — Capture Text (OCR/QR, ⌘⇧7), Pin to Screen, Quick Access stack.
- Next features (designed 2026-06-05, awaiting plans — see Roadmap below for order):
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-capture-history-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-recording-controls-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`
- `CHANGELOG.md` — per-release history.

## Roadmap (post-v1, each its own spec → plan)
~~P2 recording~~ (shipped v2.0/2.1) · ~~P3 OCR + pin-to-screen~~ (shipped v1.3) · ~~reliability + infra sprint~~ (shipped v2.2, 2026-06-05 — fixes from the scan, CI added).

**Next up — specs ready, implement in this order** (for each: `superpowers:writing-plans` from the spec, then execute with `superpowers:subagent-driven-development`; each spec lists its own probes/risks — run probe tasks first, and verify named symbols against live code before planning):
1. **v2.3 Capture History** — `docs/superpowers/specs/2026-06-05-betterscreenshot-capture-history-design.md`
2. **v2.4 Recording Controls** (countdown · window target · pause/resume) — `docs/superpowers/specs/2026-06-05-betterscreenshot-recording-controls-design.md`
3. **v2.5 Trim Editor** — `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`

**Background/wallpaper styling: dropped by owner decision (2026-06-05) — do not build or re-propose.**

Later (no spec yet): scrolling capture · freeze/self-timer/repeat-area · small quick wins (Repeat Previous Area, editor ⌘D/⌘⇧S bindings, capture sound, JPG-quality + filename settings; details in the local `CODEBASE-SCAN.md` if present) · P5 `betterscreenshot://` URL automation.

## Executing the plans
Plans use checkbox steps. Execute task-by-task with the **superpowers:subagent-driven-development** (fresh subagent per task) or **superpowers:executing-plans** skill. Each task ends in a commit; each plan ends in a git tag (`v0.1-capture-core`, `v0.2-quick-access`, `v1.0`). Plan 1 Task 1 runs `git init` and `brew install xcodegen` (prerequisite).

## Working norms (from the user's global CLAUDE.md)
Simplicity first; surgical changes (touch only what the task needs); state assumptions and ask when unclear; define verifiable success criteria and loop until tests pass.
