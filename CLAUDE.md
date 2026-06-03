# BetterScreenshot

A **free, local macOS clone of CleanShot X** (screenshot + screen-recording tool). Native Swift app.

## Hard constraints
- **No cloud.** No uploads, share links, accounts, or cloud sync — ever. Local features only.
- **macOS-native, non-sandboxed, menu-bar agent** (`LSUIElement`). Personal/local use; ad-hoc signed (no Apple Developer account required).
- **Min target: macOS 14 (Sonoma).**

## Stack
- Swift 5.9+, **SwiftUI + AppKit hybrid** (SwiftUI for settings/menus; AppKit `NSPanel`/custom `NSView` for overlays + the editor canvas).
- ScreenCaptureKit (capture/recording), Vision (OCR, later), CoreImage (blur/pixelate), Carbon `RegisterEventHotKey` (global hotkeys — avoids the Accessibility prompt).
- **Build:** XcodeGen (`project.yml`) generates the `.xcodeproj`; build/run with `xcodebuild`. Library modules are local Swift packages under `Packages/`, unit-tested with `swift test`.
- **Testing:** TDD on pure logic (geometry, encode, model, renderer) via XCTest; system/UI behavior is manually verified against checklists in the plans.

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

## Roadmap (post-v1, each its own spec → plan)
P2 recording (MP4/GIF, audio, webcam, click/keystroke viz) · P3 OCR + pin-to-screen · P4 backgrounds/styling, scrolling capture, freeze/self-timer/repeat, history · P5 `betterscreenshot://` URL automation.

## Executing the plans
Plans use checkbox steps. Execute task-by-task with the **superpowers:subagent-driven-development** (fresh subagent per task) or **superpowers:executing-plans** skill. Each task ends in a commit; each plan ends in a git tag (`v0.1-capture-core`, `v0.2-quick-access`, `v1.0`). Plan 1 Task 1 runs `git init` and `brew install xcodegen` (prerequisite).

## Working norms (from the user's global CLAUDE.md)
Simplicity first; surgical changes (touch only what the task needs); state assumptions and ask when unclear; define verifiable success criteria and loop until tests pass.
