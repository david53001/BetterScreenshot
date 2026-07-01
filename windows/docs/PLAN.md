# BetterScreenshot for Windows — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:subagent-driven-development (fresh subagent per
> task) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. Each task ends with a commit; each
> phase ends with a git tag. **Autonomous mode:** do not stop to ask the user; assume the sensible answer, log it,
> proceed (see repo root CLAUDE.md / global CLAUDE.md).

**Goal:** Port the macOS BetterScreenshot app to a native Windows .NET 9 / WPF app that is behaviorally and
visually equivalent, translated from Swift, with all icons hand-authored.

**Architecture:** Layered solution (see `windows/docs/SPEC.md §3`): pure-logic libraries (Core, Capture, Editor,
History, Recording) with headless xUnit tests ported 1:1 from the macOS `TestKit` suites; a Windows platform
library (Win32/WinRT/ffmpeg); and a WPF App (tray agent, overlays, editor, coordinators). Build the testable core
first (TDD), then system integration, then UI, then recording.

**Tech Stack:** .NET 9, WPF, `net9.0-windows10.0.19041.0` (WinRT OCR/Capture), H.NotifyIcon.Wpf, ZXing.Net,
ffmpeg (external), xUnit.

## Global Constraints (apply to every task — copied from SPEC)
- 100% local: **no network calls anywhere** (no HttpClient/WebClient/sockets/update checks). CI check greps for them.
- Tray agent only: no taskbar window, no main window; PerMonitorV2 DPI awareness.
- Free/OSS deps only; recording via already-present ffmpeg.
- **All icons/art hand-authored** as WPF vector geometry (see `port-reference/07-icons.md`) — no screenshots/crops.
- Exact fidelity to constants/behaviors/test-assertions in `windows/docs/port-reference/01..07-*.md`. When a number
  or behavior is needed, read the matching reference doc — it is the authoritative spec and this plan cites it
  rather than restating every value.
- Coordinate origin is **top-left everywhere** (Windows); drop all macOS Cocoa Y-flips.
- Every pure-logic macOS test is ported to xUnit and must pass. Keeping tests green is the loop's first duty.
- Commit after every task with a Conventional Commit message. Never push. Work on branch `windows-port`.

---

## Phase 0 — Solution scaffold  → tag `win-v0.0-scaffold`

### Task 0.1: Create the solution and projects
**Files:** Create `windows/BetterScreenshot.sln`, `windows/Directory.Build.props`, and empty class-lib projects for
Core, Capture, Editor, History, Recording (`net9.0`), Platform + App (`net9.0-windows10.0.19041.0`, App is `WinExe`
`UseWPF`), and `tests/BetterScreenshot.Tests` (`net9.0`, xUnit).
- [ ] Create `Directory.Build.props` with `<Nullable>enable</Nullable>`, `<ImplicitUsings>enable</ImplicitUsings>`,
      `<LangVersion>latest</LangVersion>`, `<TreatWarningsAsErrors>false</TreatWarningsAsErrors>`.
- [ ] `dotnet new sln`; `dotnet new classlib` for each lib; `dotnet new wpf` for App (then fix csproj to the known
      good form from the smoke test: `net9.0-windows10.0.19041.0`, `UseWPF`, no WinForms); `dotnet new xunit` for tests.
- [ ] Add project references: Tests→(Core,Capture,Editor,History,Recording); App→all libs; Platform→Core,Capture,Editor,History,Recording; each lib→Core as needed.
- [ ] Add NuGet: App `H.NotifyIcon.Wpf`; Capture (or Platform) `ZXing.Net`.
- [ ] `dotnet build windows/BetterScreenshot.sln -c Release` → **succeeds**.
- [ ] Update `.gitignore` for `bin/`, `obj/`, `*.user`. Commit `chore(win): scaffold .NET 9 solution`.

### Task 0.2: Core primitives
**Files:** Create `Core/PxGeometry.cs` (`PxPoint`, `PxSize`, `PxRect` structs with double fields + helpers:
`Integral()`, `Intersection()`, `Contains()`, `Center`, `Union`), `Core/Corner.cs` enum.
**Produces:** `PxRect`, `PxPoint`, `PxSize` used by all pure-logic geometry.
- [ ] Write failing tests for `PxRect.Intersection`, `.Integral`, `.Contains`. Run → fail.
- [ ] Implement. Run → pass. Commit `feat(win-core): pixel geometry primitives`.

Tag `win-v0.0-scaffold`.

---

## Phase 1 — Pure-logic core (TDD, headless)  → tag `win-v0.1-core-green`
Port every macOS `TestKit` pure-logic suite to xUnit. This is the correctness backbone. Reference docs list the
exact assertions: `01-capturekit.md`, `03-editorkit.md`, `04-historykit.md`, `05-recordingkit.md`,
`02-overlaykit.md` (PinGeometry). Work suite-by-suite; each suite = one task (write tests → run red → implement →
green → commit). Adapt coordinates to top-left origin.

### Task 1.1: CaptureGeometry (top-left)
**Files:** `Capture/CaptureGeometry.cs`, `tests/CaptureGeometryTests.cs`.
**Interface — Produces:** `static PxRect PixelRect(PxRect selection, PxRect display, double scale)` →
`x=(sel.X-display.X)*scale; y=(sel.Y-display.Y)*scale; w=sel.W*scale; h=sel.H*scale` (NO Y-flip on Windows).
- [ ] Failing tests: display 1440x900@2, sel(100,100,200,150)→(200,200,400,300); display at (1440,0), sel(1540,80,100,100)→(200,160,200,200). (These are the top-left analogues of the mac tests in 01-capturekit.md.)
- [ ] Implement; green; commit `feat(win-capture): pixel-rect geometry`.

### Task 1.2: ImageCropper geometry
**Files:** `Capture/CropMath.cs` (pure rect-clamp; actual pixel crop lives in Platform), tests.
**Produces:** `static PxRect? ClampCrop(PxRect target, PxSize imageSize)` — integral+intersect, null if <1px. Mirror the 3 mac tests (01-capturekit.md → ImageCropper).
- [ ] tests→red→impl→green→commit.

### Task 1.3: FileNamer
**Files:** `Capture/FileNamer.cs`, tests. `Name(DateTime, ext, prefix="Screenshot")` → `"{prefix} yyyy-MM-dd 'at' HH.mm.ss.{ext}"`, `CultureInfo.InvariantCulture`. Mirror the 2 mac tests.
- [ ] tests→red→impl→green→commit.

### Task 1.4: Hotkey model (Windows)
**Files:** `Capture/HotkeyAction.cs` (enum + title + Windows default combo), `Capture/HotkeyCombo.cs`
(`uint Vk; HotkeyModifiers Mods` [Ctrl/Shift/Alt/Win flags]; `IsValid` requires non-shift modifier;
`DisplayString` "Ctrl+Shift+4"; dictionary round-trip `"vk,mods"`/`"unbound"`), `Capture/HotkeyBindings.cs`
(map + defaults + `Set/Clear/Combo/ConflictingAction/Bound` + dictionary). Tests mirror mac
HotkeyAction/Combo/Bindings suites (01-capturekit.md) adapted to Windows VK/modifiers & default map (06-app-shell.md).
- [ ] tests→red→impl→green→commit `feat(win-capture): hotkey model + defaults`.

### Task 1.5: OverlayPositioner (top-left)
**Files:** `Capture/OverlayPositioner.cs`, tests. Corners + stacking per 02-overlaykit.md (top-left version), spacing 12, stack step by (h+spacing); bottom corners stack upward (subtract), top downward (add).
- [ ] tests→red→impl→green→commit.

### Task 1.6: RecognitionResolver + RecognitionResult
**Files:** `Capture/RecognitionResolver.cs`, `Capture/RecognitionResult.cs`, tests. Rules + hudMessage/clipboard strings verbatim (01-capturekit.md). 6 tests.
- [ ] tests→red→impl→green→commit.

### Task 1.7: CaptureSettings
**Files:** `Capture/CaptureSettings.cs`, tests. Enums + defaults + dictionary round-trip (01-capturekit.md). 6 tests.
- [ ] tests→red→impl→green→commit.

### Task 1.8: WindowPicking (pure hit-test)
**Files:** `Capture/WindowPicking.cs` (`PickableWindow` record; `Topmost(point, windows, excludePid)`), tests. Front-to-back, layer==0, exclude pid (01-capturekit.md, 4 tests; drop the Cocoa-frame test — Windows is top-left).
- [ ] tests→red→impl→green→commit.

### Task 1.9: RGBAColor + AnnotationStyle
**Files:** `Editor/RGBAColor.cs`, `Editor/AnnotationStyle.cs`, tests. 0–1 sRGB, JSON round-trip, default red(1,.23,.19) lw4 fs24 (03-editorkit.md).
- [ ] tests→red→impl→green→commit.

### Task 1.10: Annotation model + document
**Files:** `Editor/IAnnotation.cs`, `Editor/Annotations/*.cs` (Arrow, Line, Rectangle, FilledRectangle, Ellipse,
Text, Counter, Pixelate, Blur), `Editor/EditorDocument.cs`, tests (EditorDocument, Shape, Text, Counter suites).
Bounding boxes, MovedBy, hit-slop 6, z-order, IdsIntersecting, NextCounterNumber, Cropped offsets by -origin,
counter diameter max(28,fs*1.6) (03-editorkit.md).
- [ ] tests→red→impl→green→commit `feat(win-editor): annotation model + document`.

### Task 1.11: ArrowGeometry
**Files:** `Editor/ArrowGeometry.cs`, tests. `HeadWings(start,end,length,halfAngleDeg=28)`, `ShaftEnd(...)` clamped ≥ start (03-editorkit.md, 3 tests).
- [ ] tests→red→impl→green→commit.

### Task 1.12: HistoryEntry + HistoryIndex
**Files:** `History/HistoryEntry.cs`, `History/HistoryIndex.cs`, tests. Newest-first, cap, 30-day prune (`>=` boundary), removing, prunedOfMissingFiles, JSON round-trip (ISO-8601, sorted keys), corrupt throws (04-historykit.md, 10 tests).
- [ ] tests→red→impl→green→commit.

### Task 1.13: RestoreStack
**Files:** `History/RestoreStack.cs`, tests. depth 5, LIFO, repush-to-top, depth cap (04-historykit.md, 4 tests).
- [ ] tests→red→impl→green→commit.

### Task 1.14: RecordingConfig
**Files:** `Recording/RecordingConfig.cs` (+ `RecordingFormat`, `CameraSize`), tests. 9 fields, dictionary round-trip,
fps∈{30,60}, countdown∈{0,3,5,10}, `VideoBitrate(w,h)=clamp(w*h*fps*0.12,2e6,40e6)`, gifFPS10 gifMaxW960 (05-recordingkit.md).
- [ ] tests→red→impl→green→commit.

### Task 1.15: RecorderState
**Files:** `Recording/RecorderState.cs`, tests. State machine + events + elapsedString (excludes pause) (05-recordingkit.md).
- [ ] tests→red→impl→green→commit.

### Task 1.16: PauseTimeline + GIFTiming
**Files:** `Recording/PauseTimeline.cs`, `Recording/GIFTiming.cs`, tests. Offset accumulation, adjusted PTS,
`FrameTimes(duration,fps)`, `OutputSize(source,maxWidth)` no-upscale (05-recordingkit.md).
- [ ] tests→red→impl→green→commit.

### Task 1.17: PinGeometry
**Files:** `Editor/PinGeometry.cs` (or `Overlay` pure lib), tests. initialFrame (÷dpi, ≤80%, center on source/visible,
stay inside), zoomedFrame (scale about center, clamp 0.25–3.0) (02-overlaykit.md, 9 tests).
- [ ] tests→red→impl→green→commit.

### Task 1.18: Redactor detail-destruction (logic)
**Files:** `Editor/Redactor.cs` (operates on a simple `ArgbImage` buffer in Core to stay headless), tests
(pixelatePatchHasRegionSize, blurPatchHasRegionSize, pixelateDestroysDetail, blurDestroysDetail). Pixelate averages
blockSize(12) blocks; blur box/Gaussian radius(12); return null if <2×2 (03-editorkit.md). Keep buffer-based so it's testable without WPF; WPF wrapper in Platform/App converts BitmapSource↔ArgbImage.
- [ ] tests→red→impl→green→commit.

- [ ] **Phase gate:** `dotnet test` → **all pure-logic suites green**. Tag `win-v0.1-core-green`.

---

## Phase 2 — Windows platform integration  → tag `win-v0.2-capture`
Library `BetterScreenshot.Platform` (net9.0-windows10.0.19041.0). System code; verified manually + light integration
tests where possible.

### Task 2.1: Screen enumeration + DPI
**Files:** `Platform/Screens.cs`. Enumerate monitors (`EnumDisplayMonitors`/`GetDpiForMonitor`) → list of
`{ deviceName, PxRect bounds(physical), double dpiScale }`. Primary detection. Commit.

### Task 2.2: Still capture
**Files:** `Platform/ScreenCapture.cs`. `CaptureRegion(PxRect physical)` and `CaptureDisplay(device)` via GDI
`BitBlt` (`CreateCompatibleBitmap`+`BitBlt`+`SW`?) → `BitmapSource`. `CaptureWindow(hwnd)` via PrintWindow or crop.
Cursor excluded (stills). Commit. (Manual verify: save a PNG of a region.)

### Task 2.3: Window picking (Win32)
**Files:** `Platform/WindowEnum.cs`. Enumerate top-level windows in Z-order (`GetTopWindow`+`GetWindow`), rects
(`GetWindowRect`, DWM extended frame), titles, skip own pid/cloaked/invisible → `List<PickableWindow>`; feed the
pure `WindowPicking.Topmost`. Commit.

### Task 2.4: Clipboard + temp writer + encode
**Files:** `Platform/ClipboardService.cs` (set image + file-drop of a temp PNG that self-deletes after 5 min),
`Platform/ImageIo.cs` (`EncodePng`, `EncodeJpg(quality)`, `SavePng/Jpg`, `WriteTempPng`). Commit.

### Task 2.5: OCR + QR
**Files:** `Platform/TextRecognizerService.cs`. `Windows.Media.Ocr.OcrEngine.TryCreateFromUserProfileLanguages`
→ lines; `ZXing` QR decode; feed pure `RecognitionResolver`. Hardware-gated integration test. Commit.

### Task 2.6: Global hotkey host
**Files:** `Platform/HotkeyHost.cs`. Hidden `HwndSource` message window; `RegisterHotKey`/`UnregisterHotKey`;
map `HotkeyCombo`→(MOD flags, vk); raise `HotkeyPressed(HotkeyAction)`; report registration failures; suspend/resume. Commit.

### Task 2.7: ffmpeg runner + availability
**Files:** `Platform/FfmpegRunner.cs`. Locate ffmpeg (PATH or `tools/ffmpeg.exe`); `IsAvailable`; start/stop a
recording process (args built by Recording layer); run MP4→GIF; capture stderr for diagnostics. Commit.

### Task 2.8: Global input hooks
**Files:** `Platform/GlobalHooks.cs`. `WH_MOUSE_LL` (mouse-down points) + `WH_KEYBOARD_LL` (key events → glyph
string) low-level hooks with events; safe install/remove. Commit.

Tag `win-v0.2-capture`.

---

## Phase 3 — App shell + capture flow  → tag `win-v0.3-shell`
Now the app becomes runnable and can capture.

### Task 3.1: Settings store
**Files:** `App/Settings/SettingsStore.cs`. JSON at `%APPDATA%\BetterScreenshot\settings.json`; keys 1:1 with mac
(06-app-shell.md); typed accessors for CaptureSettings, saveDirectory (default `Pictures\Screenshots`),
hotkeyBindings, recordingConfig, editorDefaultStyle, flags. Round-trip test. Commit.

### Task 3.2: Tray + menu
**Files:** `App/App.xaml(.cs)` (no StartupUri, PerMonitorV2 manifest), `App/Tray/TrayIcon.cs`. H.NotifyIcon tray
with the exact menu (06-app-shell.md); wire commands to coordinator stubs; hotkey text on items; recording
state → icon+tooltip. Runs to a tray icon. Commit.

### Task 3.3: Hotkey wiring
**Files:** `App/HotkeyController.cs`. Load bindings, register via `HotkeyHost`, dispatch to actions; re-register on
change; surface failures. Commit.

### Task 3.4: CaptureCoordinator (area/fullscreen/window/text → route)
**Files:** `App/Capture/CaptureCoordinator.cs`. captureArea (selection overlay → CaptureGeometry → crop),
captureFullscreen (main display), captureWindow (picker → CaptureWindow), captureText (selection → OCR → clipboard
+ HUD). `Handle(image, sourceRect)` routes by afterCapture (copy/save/both/overlay). save/copy via Platform. Commit.

### Task 3.5: Onboarding (welcome)
**Files:** `App/Onboarding/WelcomeWindow.xaml(.cs)`. One-time welcome (icon, blurb, Ctrl+Shift cheat sheet, Start button); first-run flag. Commit.

### Task 3.6: Settings window
**Files:** `App/Settings/SettingsWindow.xaml(.cs)` — General/Shortcuts/Recording tabs (06-app-shell.md). Shortcut
recorder control (KeyDown capture, Esc cancel, Backspace clear, validity + conflict). Commit.

Tag `win-v0.3-shell`.

---

## Phase 4 — Overlays (selection, quick access, pin, HUD, window picker)  → tag `win-v0.4-overlays`
All per 02-overlaykit.md constants. WPF borderless topmost windows.

### Task 4.1: SelectionOverlay
**Files:** `App/Overlays/SelectionOverlayWindow.xaml(.cs)`, `App/Overlays/SelectionOverlayController.cs`. Per-monitor
dimmed (0.35) full-screen, crosshair, white 1px rect, live "W×H" label, Esc cancel, min 1px, first-wins, DPI→physical
rect. Commit.

### Task 4.2: QuickAccess card + stack
**Files:** `App/Overlays/QuickAccessWindow.xaml(.cs)`, `App/Overlays/QuickAccessStackController.cs`. 220×168 card,
thumbnail 200×112, button rows (screenshot/recording variants) with hand-authored icons, drag-to-export, stack ≤3
bottom-right margin 24, evict oldest, DismissReason. Wire into CaptureCoordinator showOverlay. Commit.

### Task 4.3: Pin panels
**Files:** `App/Overlays/PinWindow.xaml(.cs)`, `App/Overlays/PinPanelController.cs`. Topmost image window using
PinGeometry initial/zoom; drag move, corner/scroll resize, double-click copy, right-click menu, multi-pin, style
(radius/shadow). pinFromClipboard. Commit.

### Task 4.4: HUD + WindowPicker overlay
**Files:** `App/Overlays/HudWindow.xaml(.cs)`, `App/Overlays/WindowPickerWindow.xaml(.cs)`. HUD pill 1.5s; picker
per-monitor highlight (accent fill/stroke) + title caption, click picks, Esc cancels. Commit.

Tag `win-v0.4-overlays`.

---

## Phase 5 — Annotation editor UI  → tag `win-v0.5-editor`

### Task 5.1: Editor window + canvas render
**Files:** `App/Editor/EditorWindow.xaml(.cs)`, `App/Editor/EditorCanvas.cs`, `App/Editor/DocumentRenderer.cs`
(WPF `RenderTargetBitmap`, top-left, HighQuality, FormattedText; draws base + annotations + preview). Renders a
document to screen and to an export bitmap. Commit.

### Task 5.2: Tools + interaction
**Files:** extend `EditorCanvas`. Shape drag-create+preview; text inline TextBox; counter click; blur/pixelate/crop
marquee (min sizes); select/move/marquee/8 resize handles/z-order/delete. Redactor via Platform WPF wrapper. Commit.

### Task 5.3: Toolbar + inspector + action bar + undo/redo
**Files:** `App/Editor/EditorChrome.xaml`. 11 tool buttons (5 groups), adaptive inspector (color swatches + weight/
size segments), action bar (Done/Stack/Save/Copy), titlebar Undo/Redo. Undo/redo stacks (max 50), Ctrl+Z/Ctrl+Shift+Z/
Ctrl+Y. Sticky style (load defaultStyle, onStyleChanged→persist). Stack button→keepInStack. All icons hand-authored. Commit.

### Task 5.4: Wire editor into CaptureCoordinator
**Files:** `App/Capture/CaptureCoordinator.cs`. presentEditor with callbacks (onCopy/onSave/onAddToStack/onStyleChanged); annotate from overlay/history. Commit.

Tag `win-v0.5-editor`.

---

## Phase 6 — Capture history UI + service  → tag `win-v0.6-history`

### Task 6.1: HistoryStore + ThumbnailRenderer (Platform-backed)
**Files:** `History/HistoryStore.cs` (file IO, load-prune, add screenshot/recording, remove, clearAll — 04-historykit.md,
10 tests), `Platform/ThumbnailRenderer.cs` (≤400 JPEG q0.8; 4 tests). Store tests use temp dirs. Commit.

### Task 6.2: HistoryService facade
**Files:** `App/History/HistoryService.cs`. recordScreenshot/recordRecording, restore-recently-closed LIFO,
delete/clearAll, copyToClipboard, revealInExplorer, getters. Wire into coordinators. Commit.

### Task 6.3: History window
**Files:** `App/History/HistoryWindow.xaml(.cs)`. Thumbnail grid, kind badge, relative date, action bar (copy/annotate/
pin/reveal/delete/clear-all), double-click annotate/open. Commit.

Tag `win-v0.6-history`.

---

## Phase 7 — Screen recording  → tag `win-v0.7-recording`

### Task 7.1: ffmpeg arg builder + engine
**Files:** `Recording/FfmpegArgs.cs` (pure: build args from RecordingConfig+target+region — video ddagrab/gdigrab,
WASAPI loopback, dshow mic, H.264 bitrate, output path; unit-test the arg strings), `App/Recording/RecordingEngine.cs`
(drives FfmpegRunner). Probe: 30s record → valid MP4. Commit.

### Task 7.2: RecordingCoordinator + record strip
**Files:** `App/Recording/RecordingCoordinator.cs` (state machine via RecorderState; targets full/area/window;
onStateChange→tray; onPauseStateChange→menu), `App/Recording/RecordStripWindow.xaml(.cs)` (format, toggles, target
buttons, cancel — hand-authored icons). Commit.

### Task 7.3: Countdown + gapless pause/resume
**Files:** `App/Recording/CountdownOverlayWindow.xaml(.cs)` (200×200, 120pt, click-skip, cancel), pause/resume
wiring. Probe gapless: record 30s, pause 5s, resume, stop → ~25s in sync (segment+concat or setpts; PauseTimeline is the model). Commit.

### Task 7.4: Overlays — camera bubble, click highlighter, keystroke
**Files:** `App/Recording/CameraBubbleWindow.xaml(.cs)` (MediaCapture preview, circular, draggable, 160/240),
`App/Recording/ClickHighlighter.cs` (WH_MOUSE_LL, Ø36 accent@0.45 0.4s fade), `App/Recording/KeystrokeOverlayWindow.xaml(.cs)`
(WH_KEYBOARD_LL, 280×44, 20pt, 1.0s fade, glyphs). Captured naturally as on-screen windows. Commit.

### Task 7.5: GIF export + finalize + history card
**Files:** extend RecordingEngine. MP4→GIF via ffmpeg (fps10, ≤960, palette, loop); thumbnail; history record;
Quick Access recording card. Quit-time best-effort finalize (~3s). Commit.

Tag `win-v0.7-recording`.

---

## Phase 8 — Icons, app icon, polish, end-to-end  → tag `win-v1.0`

### Task 8.1: Icon resource dictionary
**Files:** `App/Resources/Icons.xaml` (all ~38 glyphs as `Geometry` per 07-icons.md), `App/Controls/IconPresenter.cs`.
Replace any placeholder glyphs used earlier. Commit.

### Task 8.2: App icon (.ico) + tray icon
**Files:** author vector app icon (charcoal squircle #1C1C1C + white camera), render multi-size `.ico`
(`App/Resources/AppIcon.ico`), monochrome tray variant. Wire into App + tray. Commit.

### Task 8.3: End-to-end verification pass (see §V) + fixes.
### Task 8.4: README-win.md (install/build/run, differences from mac, ffmpeg note). Commit.

Tag `win-v1.0`.

---

## V. Verification checklist (run each; the loop keeps these green)
- **Build:** `dotnet build windows/BetterScreenshot.sln -c Release` → 0 errors.
- **Tests:** `dotnet test windows/tests/BetterScreenshot.Tests -c Release` → all green (hardware traits skipped).
- **No-network audit:** grep source for `HttpClient|WebClient|Socket|WebRequest|http://|https://` (allow only
  localhost-free; there should be none) → none in product code.
- **Launch:** app starts to tray; menu items present with correct hotkey text.
- **Capture:** Ctrl+Shift+4 area → selection overlay → Quick Access card → copy/save/edit/pin/close all work;
  Ctrl+Shift+6 fullscreen; Ctrl+Shift+8 window; Ctrl+Shift+7 OCR→clipboard+HUD.
- **Editor:** every tool draws; undo/redo; multi-select/resize/z-order; blur/pixelate destroy detail; crop; Stack;
  sticky style persists across sessions; Save/Copy output correct.
- **History:** captures recorded, browse/copy/annotate/pin/delete/clear-all/restore-recently-closed; 30-day prune + cap.
- **Recording:** Ctrl+Shift+5 → strip → MP4 and GIF; system audio + mic; camera bubble; click highlights; keystroke
  overlay; countdown; pause/resume gapless (~no gap); timer in tray/tooltip.
- **Fidelity:** spot-check constants against reference tables; all icons are our vector art.
- **DPI:** verify on 100%/150%/200% scaling and a secondary monitor.

## VI. Self-review notes (author)
- Spec coverage: every README feature maps to a phase (capture→3/4, text→3, editor→5, history→6, recording→7,
  pin→4, settings/hotkeys→3, tray→3, icons→8). ✔
- Pure-logic parity: all mac TestKit suites have a Phase-1 task. ✔
- Type consistency: pure libs use `PxRect/PxPoint/PxSize`; WPF layers convert at the boundary. ✔
- Known assumptions logged in SPEC §4 (permissions dropped, native-suppression dropped, ffmpeg engine, history cap 50).
