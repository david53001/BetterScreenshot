# BetterScreenshot-Windows — Progress Ledger

The loop (`windows/LOOP-PROMPT.md`) reads this first every firing to avoid redoing work. Keep it current: check off
finished tasks, move the pointer, log assumptions/known-issues. One firing = one durable increment.

## Current pointer
- **Branch:** `windows-port`
- **Phase:** Phases 1 & 2 COMPLETE ✅. Now entering **Phase 3 (App shell + capture flow)** — makes the app runnable.
- **Build:** `dotnet build windows/BetterScreenshot.sln -c Release` → **clean (0/0)**.
- **Tests:** `dotnet test windows/tests/BetterScreenshot.Tests` → **120 passed** (incl. 8 hardware-gated tests).
- **Next task:** Phase 3 Task **3.1 (Settings store)** in `BetterScreenshot.App` — `SettingsStore`: JSON at
  `%APPDATA%\BetterScreenshot\settings.json`, keys 1:1 with the macOS app (see `port-reference/06-app-shell.md`),
  typed accessors for CaptureSettings, saveDirectory (default `Pictures\Screenshots`), hotkeyBindings,
  recordingConfig, editorDefaultStyle, flags. Round-trip test (headless).

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
**Phase 2 COMPLETE — 120 tests green.** Next: Phase 3 (App shell). Phases 3–8 pending — see PLAN.md.

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
