# BetterScreenshot

A **free, local macOS clone of CleanShot X** (screenshot + screen-recording tool). Native Swift app.

> **Windows port:** a native **.NET 9 + WPF (C#)** port lives under [`windows/`](windows/) on the
> **`windows-port`** branch. This file and everything below it describe the **macOS** app (the behavioral
> source of truth). For the port, the guide + ledger are [`windows/README-win.md`](windows/README-win.md),
> [`windows/docs/PROGRESS.md`](windows/docs/PROGRESS.md), and [`windows/LOOP-PROMPT.md`](windows/LOOP-PROMPT.md).
> It's built/deployed with `pwsh windows/scripts/publish-app.ps1` (republish + relaunch after runtime-visible
> changes — a plain build doesn't update the `dist/` tray agent the owner runs).

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
- `HistoryKit` — capture history index/store + restore stack (pure logic + file IO).
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
- Editor sticky defaults + Stack button (shipped 2026-06-25, on `main`, not tagged): `docs/superpowers/specs/2026-06-25-betterscreenshot-editor-defaults-and-stack-button-design.md` + `docs/superpowers/plans/2026-06-25-betterscreenshot-editor-defaults-and-stack-button.md` — the annotation editor remembers the last-used stroke/text color + size across sessions (persisted in `UserDefaults` key `editorDefaultStyle` via `SettingsStore.editorStyle`, injected into `EditorWindowController` as `defaultStyle`, saved on the `onStyleChanged` callback); and the editor's bottom-bar **Pin** button was replaced by a **Stack** button (`EditorWindowController.onAddToStack` → `CaptureCoordinator.keepInStack`) that adds the flattened edit to the bottom-right Quick Access stack + History. Pin-to-Screen is retained via the Quick Access overlay's own Pin action (`QuickAccessActions.onPin`). This change is a good worked example of the brainstorm → spec → plan → subagent-driven-development → merge flow for a small two-feature change.
- Windows→macOS parity backport (shipped 2026-07-04, on `main`, not tagged): design in `docs/WINDOWS-TO-MAC-PARITY.md` (grabbed from the `windows-port` branch, which holds a full C#/.NET WPF port of the app under `windows/`); plans in `docs/superpowers/plans/2026-07-04-parity-part{1,2,3}-*.md`. Brings the mac app to parity with the Windows port in three areas: **Part 1** — Settings rebuilt as a pure-black 960px three-column "JVoice" card masonry replacing the SwiftUI `TabView` (new custom controls under `App/Settings/Components/` + `SettingsTheme.swift`/`SettingsHelp.swift`; forced-dark window; instant-apply preserved); **Part 2** — the Quick Access post-capture card is now full-bleed with auto-contrasting overlaid buttons (`QuickAccessContrast`), a tone-matched scrim, variable-height stacking (`OverlayPositioner.stackedOrigins`), and a wired auto-dismiss timer + hover-pause (`OverlayDismissScale`; `overlayAutoDismissSeconds` default **0 = Never**); **Part 3** — optional auto-contrast editor text-background chip (`AnnotationStyle.textBackground`), clamp annotation drags to image bounds (`EditorBoundsClamp`), clamp area-selection to screen (`SelectionClamp`), history cap 200→100, plus a new `playSound` capture setting. **Not yet done: the stretched-resolution capture "black bar" item** (Part 3 §3.B #10) — needs the owner's stretched display to reproduce; no speculative capture-geometry change was made. A second good worked example of the brainstorm → spec → plan → subagent-driven-development → merge flow.
- Next features (designed 2026-06-05, awaiting plans — see Roadmap below for order):
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-capture-history-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-recording-controls-design.md`
  - `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`
- `CHANGELOG.md` — per-release history.

## Roadmap (post-v1, each its own spec → plan)
~~P2 recording~~ (shipped v2.0/2.1) · ~~P3 OCR + pin-to-screen~~ (shipped v1.3) · ~~reliability + infra sprint~~ (shipped v2.2, 2026-06-05 — fixes from the scan, CI added) · ~~v2.3 capture history~~ (shipped 2026-06-05) · ~~editor sticky defaults + Stack-to-Quick-Access button~~ (shipped 2026-06-25, on `main`, not tagged — see Source of truth above) · ~~Windows→macOS parity backport~~ (shipped 2026-07-04, on `main`, not tagged — JVoice settings reskin + full-bleed Quick Access card + editor/capture backports; see Source of truth above. Outstanding: stretched-resolution "black bar" capture item, needs owner hardware) · ~~Quick Access hold duration~~ (shipped v2.5.0, 2026-08-01 — see below).

**Quick Access hold duration** (shipped 2026-08-01, tag `v2.5.0`, built directly without a spec at the owner's request): the Settings → Quick Access Overlay → "Auto-dismiss after" slider now runs over an ordered stop table in `OverlayDismissScale` (`Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift`) — **30s · 1m · 2m · 5m · 10m · 15m · 30m · Never** — where the slider position is the stop *index*, not a second count. `CaptureSettings.init(dictionary:)` snaps any persisted value that isn't a stop to the nearest one (same precedent as `historyCap` in `48e9c3a`). Default is still `0` = Never. The C# port mirrors the identical table in `windows/src/BetterScreenshot.Capture/OverlayDismissScale.cs` on the `windows-port` branch.

**Cache retention** (shipped 2026-08-01, tag `v2.6.0`, built directly without a spec at the owner's request): Settings → History → "Keep in cache for" controls how long a captured screenshot stays in `~/Library/Application Support/BetterScreenshot/History/` before its cached copy + thumbnail are deleted. Stops live in `HistoryRetentionScale` (`Packages/CaptureKit/Sources/CaptureKit/HistoryRetentionScale.swift`) — **10s · 30s · 5m · 10m · 30m · 1h · Never** — persisted as `CaptureSettings.historyRetentionSeconds` (default **1800**; `0` = Never). `HistoryIndex`'s old hard-coded 30-day `maxAge` is now a `TimeInterval?` parameter threaded through `HistoryIndex.pruned(cap:maxAge:now:)` / `adding` / `HistoryStore.init` / `addScreenshot` / `addRecording`, where `nil` means Never. Because the shortest stop is 10s, `HistoryService` drives a **5-second sweep timer** calling the new `HistoryStore.pruneExpired(cap:maxAge:now:)`, which only republishes `entries` on a real eviction. **Only history-owned files are deleted** — a recording's saved video is never touched (covered by `pruneExpiredNeverTouchesARecordingsSavedFile`). Note this is a *different* setting from the Quick Access card's on-screen "Auto-dismiss after" (`OverlayDismissScale`); the two are independent, and `HistoryRetentionScale` deliberately duplicates the small stop-table shape rather than refactoring the shipped overlay scale. **Both scales render their "never expire" stop as `∞`** (tag `v2.6.1`) via a `neverLabel` constant on each scale — the persisted value for that stop is still `0`, and the internal `neverSeconds` / `neverPosition` names are unchanged, so only the displayed glyph differs. The C# port mirrors this in `OverlayDismissScale.NeverLabel`.

**Next up — spec ready** (`superpowers:writing-plans` from the spec, then execute with `superpowers:subagent-driven-development`; the spec lists its own probes/risks — run probe tasks first, and verify named symbols against live code before planning):
1. **Trim Editor** — `docs/superpowers/specs/2026-06-05-betterscreenshot-trim-editor-design.md`

(Recording Controls — countdown · window target · pause/resume — shipped as `v2.4.0` on 2026-06-25.)

**Background/wallpaper styling: dropped by owner decision (2026-06-05) — do not build or re-propose.**

Later (no spec yet): scrolling capture · freeze/self-timer/repeat-area · small quick wins (Repeat Previous Area, editor ⌘D/⌘⇧S bindings, capture sound, JPG-quality + filename settings; details in the local `CODEBASE-SCAN.md` if present) · P5 `betterscreenshot://` URL automation.

## Executing the plans
Plans use checkbox steps. Execute task-by-task with the **superpowers:subagent-driven-development** (fresh subagent per task) or **superpowers:executing-plans** skill. Each task ends in a commit; each plan ends in a git tag (`v0.1-capture-core`, `v0.2-quick-access`, `v1.0`). Plan 1 Task 1 runs `git init` and `brew install xcodegen` (prerequisite).

## Working norms (from the user's global CLAUDE.md)
Simplicity first; surgical changes (touch only what the task needs); state assumptions and ask when unclear; define verifiable success criteria and loop until tests pass.
