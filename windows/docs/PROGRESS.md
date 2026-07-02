# BetterScreenshot-Windows — Progress Ledger

> ▶️ **LOOP RESUMED (2026-07-02).** Restarted from `windows/docs/HANDOFF-2026-07-02.md`; the self-perpetuating
> firing loop is active again (ScheduleWakeup). Phases 1–6 complete; **Phase 7 (Screen recording) IN PROGRESS —
> Task 7.1 (ffmpeg arg builder + engine) + 7.2-core (RecordingCoordinator start/stop + audio-device discovery)
> DONE, 212 tests green.** Ctrl+Shift+5 now records the full screen → MP4 in Videos + Quick Access card + history.
> Remaining 7.2: the record-strip picker UI (format/toggles/area+window targets). Next firing continues there.

The loop (`windows/LOOP-PROMPT.md`) reads this first every firing to avoid redoing work. Keep it current: check off
finished tasks, move the pointer, log assumptions/known-issues. One firing = one durable increment.

## Current pointer
- **Branch:** `windows-port`
- **Phase:** Phases 1–6 COMPLETE ✅. **Phase 7 (Screen recording) IN PROGRESS** — Task 7.1 + 7.2-core done.
- **Build:** `dotnet build windows/BetterScreenshot.sln -c Release` → **clean (0/0)**.
- **Tests:** `dotnet test windows/tests/BetterScreenshot.Tests` → **212 passed** (197 + 7 FfmpegArgs + 8
  DshowDeviceList; incl. hardware-gated tests, 0 skipped on this machine).
- **App TAKES SCREENSHOTS + HISTORY + RECORDS (full screen):** Ctrl+Shift+6 (fullscreen) & Ctrl+Shift+8 (front
  window) capture → save/copy; captureArea → selection overlay; captureText OCRs primary display → clipboard+HUD.
  Captures are recorded in **persistent history**; the **History window** (tray → History…) browses thumbnails.
  **Recording now works end-to-end for the full screen:** Ctrl+Shift+5 (or tray → Record Screen…) toggles a
  ffmpeg recording of the primary display → on stop, saves an MP4 to `Videos\`, records it in history, and shows a
  Quick Access recording card (Copy file / Open / Show in folder); the tray icon turns red with a live m:ss timer
  while recording. **Not yet:** the record-strip picker (format/audio/mic/camera toggles + area/window targets) and
  gapless pause/resume (`PauseResumeRecording` is still a no-op — Task 7.3).
- **Next task:** finish Phase 7 Task **7.2 — the record-strip window** `App/Recording/RecordStripWindow.xaml(.cs)`
  (format dropdown, systemAudio/mic/camera toggles, target buttons full/area/window, cancel — hand-authored icons),
  and route `ToggleRecording` through it (arm → show strip → pick target/region → begin) instead of going straight
  to full-screen. Extend `RecordingCoordinator` to accept a target (full display / area rect / window hwnd) →
  region. See `port-reference/05-recordingkit.md` §"App-level (RecordingCoordinator)". Then 7.3 countdown + gapless
  pause/resume, 7.4 camera/click/keystroke overlays, 7.5 GIF export + finalize.
  DEFERRED (hardening): editor 8-handle resize + marquee multi-select; icon-glyph toolbar (Phase 8);
  captureText→region select.

## Phase 7 task status (Screen recording — BetterScreenshot.Recording/App)
- [x] 7.1 ffmpeg arg builder + engine — done, +7 tests. `Recording/FfmpegArgs.cs` (PURE) builds the recording
      command line: video via **gdigrab** over a desktop-relative pixel region (all three targets — display/area/
      window — reduce to one region), cursor drawn, H.264/`libx264`/yuv420p at the pure `VideoBitrate` formula,
      output MP4. System audio + mic are separate `dshow` AAC tracks (48kHz/2ch/128k), included only when the
      config asks AND an `AudioInputs` device name is supplied; explicit `-map` when audio present, else default
      map. Even-floors capture dims for H.264. `App/Recording/RecordingEngine.cs` drives Platform's `FfmpegRunner`
      (start/stop, drains stderr/stdout so ffmpeg can't block, returns the finished path). **Probe passed:** a real
      3s gdigrab→libx264 capture of the live desktop → ffprobe reports valid h264/640×480/mp4/3.0s. Not yet wired
      into `ToggleRecording` (that's 7.2).
- [~] 7.2 RecordingCoordinator + record strip — **core done, strip UI remaining.** +8 tests (DshowDeviceList).
      DONE: `Recording/DshowDeviceList.cs` (PURE — parse ffmpeg `-list_devices` stderr → audio/video names;
      `PickSystemLoopback` [conservative loopback-name heuristic] + `PickMicrophone`), `Platform/DshowAudioDevices.cs`
      (runs ffmpeg -list_devices, caches, `ResolveAsync(config)`→`AudioInputs`), `App/Recording/RecordingCoordinator.cs`
      (RecorderState machine + `RecordingEngine`; full-display target; 1s DispatcherTimer → tray red icon + m:ss;
      on stop saves MP4 to `Videos\` + thumbnail-at-stop → history `RecordRecording` + Quick Access recording card).
      Wired: `CaptureCoordinator.ToggleRecording`→coordinator, `App` sets `OnRecordingStateChanged`→`tray.SetRecordingState`.
      Verified: 212 tests green; real ffmpeg -list_devices output matches the parser; engine→valid MP4 (7.1 probe);
      app launches to tray with the wiring (no startup crash). REMAINING: record-strip picker window + area/window
      targets; route Toggle through arm→strip→begin. `PauseResumeRecording` still a no-op (→ 7.3).
- [ ] 7.3 Countdown + gapless pause/resume
- [ ] 7.4 Overlays — camera bubble, click highlighter, keystroke
- [ ] 7.5 GIF export + finalize + recording Quick Access/history card

## Phase 6 task status (Capture history — BetterScreenshot.History/Platform/App)
- [x] 6.1 HistoryStore (file IO, load-prune, add/remove/clearAll) + ThumbnailRenderer — done, 14 tests (10 store + 4 thumb)
- [x] 6.2 HistoryService facade (record/restore/copy/reveal/delete) + wire into coordinators — done, +10 tests
      (RestoreStack.PopRestorable ×2, HistoryService ×8). Wired: record on save/overlay, ✕-close/evict→RestoreStack,
      KeepInStack records, RestoreRecentlyClosed re-shows newest closed card. ClipboardService.SetFile added.
- [x] 6.3 History window (thumbnail grid, actions) — done, +16 tests (HistoryDateFormat.Relative). Dark grid over
      HistoryService.Entries, hand-authored camera/film badges, relative date, action bar (copy/annotate/pin/reveal/
      delete/clear-all), double-click open, OpenHistory() shows single reused window. App-launch verified.
**Phase 6 COMPLETE — 197 tests green.** Capture history persists + is browsable end-to-end. Next: Phase 7 (recording).

## Phase 5 task status (Annotation editor — BetterScreenshot.App)
- [x] 5.1 Editor window + canvas render (DocumentRenderer, WPF) — done, 4 renderer tests (pixel read-back)
- [x] 5.2 Tools + interaction (draw/select/move/redact/crop; AnnotationFactory tested) — done; 8-handle resize + marquee-select deferred to 5.3
- [x] 5.3 Toolbar + inspector + action bar + undo/redo + sticky style + Stack button — done (UndoHistory tested; inspector colors/weights/sizes)
- [x] 5.4 Wire editor into CaptureCoordinator (Quick Access Edit, sticky-style persist) — done; app runs
**Phase 5 COMPLETE — 157 tests green.** Editor reachable end-to-end. Next: Phase 6 (history).
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
- History records a capture only when it is **saved or shown as an overlay** (not for copy-only captures, which are
  transient) — matches the PROGRESS pointer's "record on save/overlay". Copy-only stays ephemeral. (Task 6.2)
- HistoryService reads cap + enabled **live** from settings each call (via `ForSettings`), so toggling history in
  Settings takes effect immediately without reconstructing the service. (Task 6.2)
- **(7.1) Video backend = `gdigrab`, not `ddagrab`.** The reference allows either; gdigrab supports arbitrary
  region capture via `-offset_x/-offset_y/-video_size`, so display/area/window all reduce to one desktop-relative
  pixel region (matches the mac recorder's "capture full display then crop to window"). ddagrab captures a whole
  output and can't crop to an arbitrary rect as cleanly. Verified gdigrab produces a valid MP4 on this machine.
- **(7.1) "WASAPI loopback" is realized as a `dshow` audio input.** Mainline ffmpeg 8.1 has no WASAPI demuxer, so
  system-audio loopback must come from a loopback-capable dshow device (e.g. "Stereo Mix" or a virtual cable). The
  pure `FfmpegArgs` only formats a supplied device name; **discovering the actual device names is deferred to the
  engine/coordinator (Task 7.2)** via dshow enumeration. If no device is found the track is dropped gracefully
  (video-only), matching "disable recording features gracefully if unavailable".
- **(7.1) Recording always encodes H.264/MP4; a GIF request is a separate post-conversion pass (Task 7.5).**
  `FfmpegArgs.BuildRecording` ignores `config.Format` (always libx264). This mirrors the mac flow
  (record → stop → convert-to-GIF-if-gif).
- **(7.1) Capture dims are even-floored** for H.264 yuv420p (drops ≤1px per axis), per "round pixel dims to even".
- **(7.2) System-audio loopback picker is deliberately conservative.** `PickSystemLoopback` only matches genuine
  loopback names (stereo mix / what u hear / wave out mix / loopback / cable output / voicemeeter out). Generic
  "virtual audio" devices are NOT auto-selected (some are mics — e.g. this machine's "Voicemod Virtual Audio").
  Consequence: on a machine with no Stereo-Mix-class device (like this one), system audio is silently dropped and
  recordings are video-only until the user picks a device (a future record-strip/settings affordance). Honest
  default over guessing wrong.
- **(7.2) Recording target defaults to the full primary display** for now (no strip yet). Toggle records the whole
  primary monitor; area/window targets + the picker come with the record-strip UI (remaining 7.2).
- **(7.2) Recording thumbnail = a still GDI grab of the primary display at stop** (≈ the final frame) — avoids a
  second ffmpeg frame-extract pass; falls back to a 2×2 blank if the grab fails.
- **(7.2) dshow device list is cached** after first enumeration (`DshowAudioDevices`, `InvalidateCache()` to reset)
  — enumeration spawns ffmpeg and devices change rarely; keeps recording start snappy.
- **(7.2) Recordings save to `SettingsStore.RecordingsDirectory`** (default `Videos\`), named `Recording {date}.mp4`
  via `FileNamer` (prefix "Recording"). Dir is created on demand.

## Known issues / TODO discovered during build (append as you find them)
- Git warns LF→CRLF on the C# files (autocrlf). Harmless; could add a `.gitattributes` to normalize.
