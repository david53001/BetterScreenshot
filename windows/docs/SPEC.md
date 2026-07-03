# BetterScreenshot for Windows — Port Design Spec

**Status:** authored 2026-07-01 (autonomous port session). Source of truth for the Windows port.
**Goal:** a faithful, native Windows re-implementation of the macOS BetterScreenshot app (a free, 100%-local
CleanShot-X-style screenshot / screen-recording / annotation tool that lives in the system tray) — behaviorally
and visually equivalent, translated from Swift to C#, with **all icons and art authored from scratch** (no
screenshots or cropped images of the original).

The macOS app is the reference implementation. Its behavior, constants, and test assertions are captured in
`windows/docs/port-reference/01..07-*.md`. Those docs + the Swift source under `App/` and `Packages/` are the spec
for exact fidelity. This document records the *decisions* that adapt that behavior to Windows.

---

## 1. Non-negotiable product constraints (inherited from macOS app)
- **100% local.** No network calls of any kind — no uploads, share links, accounts, telemetry, update checks.
- **Tray agent.** No taskbar button, no main window; lives in the system tray (macOS: menu-bar `LSUIElement`).
- **Free / no paid dependencies.** Only OSS + already-installed tools (ffmpeg).
- Feature parity with the shipped macOS v2.4 feature set (README): area/window/fullscreen capture; Capture Text
  (OCR+QR); screen recording (MP4/GIF, system audio, mic, camera bubble, click highlights, keystroke overlay,
  countdown, gapless pause/resume); Quick Access overlay + 3-item stack; Capture History (cap + 30-day prune,
  restore-recently-closed); Pin-to-screen; full annotation editor (arrow/line/rect/ellipse/text/counter/blur/
  pixelate/crop, undo-redo, multi-select, resize, z-order, sticky style, Stack button); configurable hotkeys;
  save PNG/JPG to a chosen folder; copy to clipboard.

## 2. Tech stack (decided)
- **.NET 9 + WPF (C#)**, single solution under `windows/`. Verified building on this machine (SDK 9.0.304).
- **TargetFramework `net9.0-windows10.0.19041.0`** for the app + system-integration libs (unlocks WinRT:
  `Windows.Media.Ocr`, `Windows.Graphics.Capture`, `Windows.Media.Capture`). Pure-logic libs target plain `net9.0`
  so their tests run fast and headless.
- **Tray:** `H.NotifyIcon.Wpf` (avoids pulling WinForms `Application` into WPF; validated the WPF+WinForms name
  clash in the smoke test).
- **Recording:** bundled/installed **ffmpeg** (8.1.1 present) for capture+encode (DXGI `ddagrab`/`gdigrab` video,
  WASAPI loopback system audio, `dshow` mic, MP4 H.264, MP4→GIF). Pure timing/config logic stays in C#.
- **OCR:** `Windows.Media.Ocr.OcrEngine`. **QR:** `ZXing.Net` (OSS).
- **Image ops (blur/pixelate/encode/thumbnail):** WPF imaging (`WriteableBitmap`, `RenderTargetBitmap`,
  `PngBitmapEncoder`/`JpegBitmapEncoder`, `BitmapEncoder` for thumbnails). No `System.Drawing.Common` dependency
  where avoidable (keeps it modern), but it's available if needed.
- **Hotkeys:** Win32 `RegisterHotKey` via P/Invoke on a hidden message window.
- **Tests:** **xUnit**. Pure-logic suites (the bulk) run headless in CI-less `dotnet test`. Capture/OCR/recording
  suites are hardware-gated with `[Trait("category","hardware")]` and skipped when unavailable.

## 3. Solution layout
```
windows/
  BetterScreenshot.sln
  Directory.Build.props                 # shared TFM/nullable/langversion
  src/
    BetterScreenshot.Core/              # net9.0 — shared primitives (geometry, color, RGBA, small helpers)
    BetterScreenshot.Capture/           # net9.0(-windows for capture impl split) — geometry/crop/encode/name/hotkey model/OCR-resolver/settings/windowpick
    BetterScreenshot.Editor/            # net9.0 — annotation model, ArrowGeometry, Redactor logic, DocumentRenderer
    BetterScreenshot.History/           # net9.0 — HistoryEntry/Index/Store/RestoreStack/ThumbnailRenderer
    BetterScreenshot.Recording/         # net9.0 — RecordingConfig/RecorderState/PauseTimeline/GIFTiming (pure)
    BetterScreenshot.Platform/          # net9.0-windows10.0.19041.0 — Win32/WinRT: screen enum, BitBlt/Graphics.Capture, RegisterHotKey, clipboard, OCR engine, ffmpeg runner, global hooks
    BetterScreenshot.App/               # net9.0-windows10.0.19041.0 — WPF: tray, windows, overlays, editor UI, coordinators, icons
  tests/
    BetterScreenshot.Tests/             # net9.0 — xUnit; ports every pure-logic test suite 1:1
  docs/  (SPEC.md, PLAN.md, port-reference/*)
```
Pure-logic libraries have **no WPF/Win32 dependency** so their tests are deterministic and fast. Geometry types:
use `System.Windows.Rect`/`Point`/`Size` only in WPF-facing code; in pure libs use lightweight `Core` structs
(`PxRect`, `PxPoint`, `PxSize` — doubles) to stay UI-free and headless-testable.

## 4. macOS → Windows adaptations (decisions)
- **Coordinate origin:** macOS mixes Cocoa bottom-left (points) with top-left image pixels and flips constantly.
  Windows is **top-left everywhere**. We drop all Y-flips: the selection overlay emits top-left pixel rects; the
  editor renderer draws top-left with no context flip. Geometry unit tests are rewritten for top-left (same
  numbers, no `maxY - y`).
- **DPI:** per-monitor DPI. WPF logical units = px/ (dpi/96). We capture at physical pixels and map selection
  logical→physical using each monitor's DPI. `PinGeometry`/`OverlayPositioner` use logical units; capture/crop use
  physical pixels. Set `<application manifest>` to PerMonitorV2 DPI awareness.
- **Hotkeys:** Cmd→Ctrl. Defaults become Ctrl+Shift+4/5/6/7/8 (see 06-app-shell.md). `RegisterHotKey` with
  `MOD_CONTROL|MOD_SHIFT|MOD_NOREPEAT`. Validity requires a non-Shift modifier. Display strings use `Ctrl/Alt/Win`.
- **Permissions:** Windows needs **no screen-capture permission** — the mac TCC/onboarding permission loop is
  dropped. Onboarding becomes a one-time friendly welcome (icon, feature blurb, hotkey cheat sheet). Camera/mic
  consent is handled by the OS on first `MediaCapture`/dshow use.
- **Native-shortcut suppression dropped:** mac disabled ⌘⇧4/⌘⇧5 via `com.apple.symbolichotkeys`. Windows has no
  such global registry and Ctrl+Shift+n don't collide with OS defaults, so we simply register ours.
- **Storage:** `%APPDATA%\BetterScreenshot\` — `settings.json` (replaces UserDefaults, keys 1:1) and
  `History\history.json` + owned files. Save destinations default to `Pictures\Screenshots` and `Videos\`.
- **Reveal in Finder → Explorer:** `explorer.exe /select,"<path>"`.
- **Recording:** replace ScreenCaptureKit/AVFoundation with ffmpeg. Keep the pure `RecorderState`/`PauseTimeline`/
  `RecordingConfig`/`GIFTiming` models identical (with their tests). Gapless pause/resume: probe segment+concat vs
  PTS retiming early. Overlays (camera/click/keystroke/countdown) are on-screen WPF windows, captured naturally.
- **Global hooks:** click + keystroke overlays use `SetWindowsHookEx(WH_MOUSE_LL/WH_KEYBOARD_LL)` (no special
  permission on Windows, unlike mac Accessibility).
- **Icons/app icon:** hand-authored WPF vector geometries (see 07-icons.md); app icon built to multi-size `.ico`.

## 5. Fidelity / acceptance criteria
1. Every **pure-logic test** from the macOS `TestKit` suites is ported to xUnit and **passes** (Capture geometry/
   crop/encode/name/hotkeys/positioner/recognition/settings; Editor document/renderer/arrow/counter/redactor/text/
   shape/style/color/crop; History index/store/restore/thumbnail; Recording state/config/pausetimeline/gif). This
   is the objective correctness bar and the first thing the loop must keep green.
2. The app **builds** (`dotnet build -c Release`) and **launches** to a tray icon with the full menu.
3. Each shipped feature is reachable and behaves per the reference docs (manual/automated checklist in PLAN §V).
4. Constants (sizes, colors, timings, defaults, hotkeys) match the reference tables exactly.
5. No network access anywhere (grep the source for http/socket/WebClient/HttpClient — must be absent).
6. All visual glyphs are our own vector art — no bitmap screenshots of the original.

## 6. Build / run / verify
- Build: `dotnet build windows/BetterScreenshot.sln -c Release`
- Test: `dotnet test windows/tests/BetterScreenshot.Tests -c Release` (headless; hardware traits excluded by default)
- Run: `dotnet run --project windows/src/BetterScreenshot.App` (or launch the built exe) → tray icon appears.
- ffmpeg is invoked from PATH (present) or a bundled `tools/ffmpeg.exe`; the app checks availability at startup and
  disables recording gracefully if missing.

## 7. Out of scope (matches macOS app)
Cloud anything; scrolling capture; self-timer/freeze; background/wallpaper styling (dropped by owner); the
`cleanshot://` URL automation; trim editor (designed but never shipped on mac — optional stretch, not required for
parity).
