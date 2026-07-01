# BetterScreenshot-Windows — Progress Ledger

The loop (`windows/LOOP-PROMPT.md`) reads this first every firing to avoid redoing work. Keep it current: check off
finished tasks, move the pointer, log assumptions/known-issues. One firing = one durable increment.

## Current pointer
- **Branch:** `windows-port`
- **Phase:** Phases 1–4 COMPLETE ✅. Now entering **Phase 5 (Annotation editor)** — the biggest UI subsystem.
- **Build:** `dotnet build windows/BetterScreenshot.sln -c Release` → **clean (0/0)**.
- **Tests:** `dotnet test windows/tests/BetterScreenshot.Tests` → **152 passed** (incl. 10 hardware-gated tests).
- **App TAKES SCREENSHOTS:** Ctrl+Shift+6 (fullscreen) & Ctrl+Shift+8 (front window) capture → save/copy; end-to-end
  capture→save PNG verified by test. captureArea falls back to fullscreen (overlay = Phase 4); captureText OCRs
  the primary display → clipboard.
- **Next task:** Phase 5 Task **5.3 (Toolbar/inspector + undo/redo + sticky style + Stack button)** in
  `BetterScreenshot.App` — polish the editor: styled tool toolbar (hand-drawn glyphs, selected state) + inspector
  (8 preset color swatches + custom color, weight S/M/L=2/4/7, size S/M/L=18/24/36 by tool); undo/redo via document
  snapshots (max 50) with Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y; sticky style (load defaultStyle, on change persist via
  `StyleChanged`); Stack button already present (wire `OnAddToStack`). See `port-reference/03-editorkit.md`.
  DEFERRED from 5.2 (do in 5.3 or hardening): 8-handle resize for a single selection (currently move/delete/z-order
  only); marquee multi-select. NEEDS MANUAL VERIFY: editor tools once reachable (Edit wires in 5.4).
  INTERIM caveats still open: captureText→region select; Quick Access Edit button (5.4).

## Phase 5 task status (Annotation editor — BetterScreenshot.App)
- [x] 5.1 Editor window + canvas render (DocumentRenderer, WPF) — done, 4 renderer tests (pixel read-back)
- [x] 5.2 Tools + interaction (draw/select/move/redact/crop; AnnotationFactory tested) — done; 8-handle resize + marquee-select deferred to 5.3
- [ ] 5.3 Toolbar + inspector + action bar + undo/redo + sticky style + Stack button
- [ ] 5.4 Wire editor into CaptureCoordinator (Quick Access Edit, annotate from history)

## Phase 4 task status (Overlays — BetterScreenshot.App)
- [x] 4.1 SelectionOverlay (area selection) — done (physical-pixel positioning, SelectionMath tested); needs manual drag verify
- [x] 4.2 QuickAccess card + stack (220×168, ≤3, actions, drag-export) — done; Copy/Save work, Edit/Pin stubs (4.3/5)
- [x] 4.3 Pin panels (PinGeometry-based, drag/zoom/multi-pin) — done (Pin from Clipboard + Quick Access Pin button)
- [x] 4.4 HUD + WindowPicker overlay — done (Capture-Text HUD; interactive window picker → CaptureWindow)
**Phase 4 COMPLETE — 141 tests green.** Overlays all built (selection, Quick Access, pin, HUD, window picker).
Next: Phase 5 (annotation editor).

## Phase 1 task status (pure-logic core)
- [x] 1.1 CaptureGeometry (top-left)              — done, tested
- [x] 1.2 CropMath                                 — done, tested
- [x] 1.3 FileNamer                                — done, tested
- [x] 1.4 Hotkey model (HotkeyAction/Combo/Bindings, Windows VK) — done, tested
- [x] 1.5 OverlayPositioner (top-left)             — done, tested
- [x] 1.6 RecognitionResult/Resolver              — done, tested
- [x] 1.7 CaptureSettings                          — done, tested
- [x] 1.8 WindowPicking (pure hit-test)            — done, tested
- [x] 1.9 RGBAColor + AnnotationStyle              — done, tested
- [x] 1.10 Annotation model + EditorDocument       — done, tested
- [x] 1.11 ArrowGeometry                            — done, tested
- [x] 1.12 HistoryEntry + HistoryIndex             — done, tested
- [x] 1.13 RestoreStack                             — done, tested
- [x] 1.14 RecordingConfig                          — done, tested
- [x] 1.15 RecorderState                            — done, tested
- [x] 1.16 PauseTimeline + GIFTiming                — done, tested
- [x] 1.17 PinGeometry                              — done, tested
- [x] 1.18 Redactor (buffer-based detail destruction) — done, tested
**Phase 1 COMPLETE — 104 tests green.** Phase 0 (scaffold) complete. Phases 3–8 (App shell, Overlays,
Editor UI, History UI, Recording, Icons) pending — see PLAN.md.

## Phase 2 task status (Windows platform integration — BetterScreenshot.Platform)
- [x] 2.1 Screen enumeration + DPI (Screens: EnumDisplayMonitors + GetDpiForMonitor) — done, hardware test
- [x] 2.2 Still capture (GDI BitBlt region/display + PrintWindow) — done, hardware test
- [x] 2.3 Window picking (Win32 enum in Z-order → feed pure WindowPicking) — done, hardware test
- [x] 2.4 Clipboard + temp writer + encode (PNG/JPG) — done (ImageIo tested headless; ClipboardService build-only)
- [x] 2.5 OCR + QR (Windows.Media.Ocr + ZXing) — done, QR round-trip test (hardware)
- [x] 2.6 Global hotkey host (RegisterHotKey on hidden HwndSource) — done, STA registration test (hardware)
- [x] 2.7 ffmpeg runner + availability — done, availability+run test (hardware)
- [x] 2.8 Global input hooks (WH_MOUSE_LL / WH_KEYBOARD_LL) — done, glyph tests + hook-install tests
**Phase 2 COMPLETE — 120 tests green.** Phases 3–8 pending — see PLAN.md.

## Phase 3 task status (App shell + capture flow — BetterScreenshot.App)
- [x] 3.1 Settings store (JSON, keys 1:1 with mac) — done, round-trip/missing/corrupt tests
      NOTE: placed in `BetterScreenshot.Platform` (not App) so the Tests project can cover it without referencing
      the WinExe. Namespace `BetterScreenshot.Platform.SettingsStore`.
- [x] 3.2 Tray + menu (WinForms NotifyIcon, full menu) — done, app launches to tray (verified via Start-Process)
- [x] 3.3 Hotkey wiring (load bindings → HotkeyHost → dispatch to actions) — done, dispatch tests; app runs w/ hotkeys
- [x] 3.4 CaptureCoordinator (area/fullscreen/window/text → route by afterCapture; save/copy) — done, e2e capture→save test
- [x] 3.5 Onboarding (welcome window) — done, renders on first run (verified via Start-Process)
- [x] 3.6 Settings window (General/Shortcuts/Recording tabs + shortcut recorder) — done, recorder tested; app runs
**Phase 3 COMPLETE — 138 tests green.** App = functional tray screenshot tool (capture/save/copy, OCR, settings,
live hotkey rebind, first-run welcome). Next: Phase 4 (Overlays).

## Completed (append as you go)
- 2026-07-01 (seed): Reconnaissance of macOS app → SPEC.md, PLAN.md, LOOP-PROMPT.md, seven port-reference docs.
- 2026-07-01 (seed): Scaffolded .NET 9 solution (8 projects), WPF tray shell (windowless, PerMonitorV2 manifest,
  WinForms NotifyIcon interop — dropped H.NotifyIcon due to NU1701). Full build clean.
- 2026-07-01 (seed): Implemented + tested Core (PxRect/PxPoint/PxSize, Corner, ArgbImage) and pure-logic for
  Capture (Geometry/Crop/FileNamer/OverlayPositioner/Recognition/Settings), History (Entry/Index/RestoreStack),
  Recording (Config/State/PauseTimeline/GIFTiming). **57 xUnit tests green.**

## Assumptions log (decisions made without asking; David can review)
- Windows hotkeys map Cmd→Ctrl: Ctrl+Shift+4/5/6/7/8 (SPEC §4).
- macOS screen-recording permission flow + native-shortcut suppression are **dropped** (no Windows equivalent needed).
- Recording engine = ffmpeg (DXGI/gdigrab + WASAPI loopback + dshow), not a custom encoder.
- History cap default = 50 (CaptureKit default; the mac App note said 200 — using 50 per the tested default).
- Save destinations default to `Pictures\Screenshots` (images) and `Videos\` (recordings).
- Tray = built-in WinForms `NotifyIcon` (not H.NotifyIcon.Wpf, which resolved via a .NET Framework fallback).
- RecorderState elapsed formula = wall − accumulatedPause (the "7s" figure in 05-recordingkit.md is a doc typo;
  the real value for start0/pause10/resume13/now20 is 0:17). Verified by test.

## Known issues / TODO discovered during build (append as you find them)
- Git warns LF→CRLF on the C# files (autocrlf). Harmless; could add a `.gitattributes` to normalize.
