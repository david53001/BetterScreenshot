# BetterScreenshot P2 — Screen Recording Suite

Date: 2026-06-04 · Status: **shipped 2026-06-04** (tag `v2.0-recording`; see CHANGELOG.md)
Builds on: v1.4-shortcuts (`main`) · Ends at tag: `v2.0-recording`

## Goal

Ship the P2 roadmap item (CleanShot spec §2): **screen recording** with MP4 + GIF
output, microphone + system audio, a webcam bubble, and click/keystroke
visualization — driven by a **smart ⌘⇧5 toggle**: press once to set up and start,
press again to stop. Recording becomes a first-class `HotkeyAction` (default ⌘⇧5,
the slot v1.4 reserved), rebindable like everything else.

## Out of scope (deferred, with reasons)

Pause/resume/restart, countdown/self-timer, auto-Do-Not-Disturb, hide desktop icons
(all P4 polish) · built-in video editor (trim/resize/mute — its own future project) ·
window-tracking recording beyond a static frontmost-window region · camera shape
styles (square/vertical/fullscreen camera) — circle only, S/M sizes · click-viz
style customization (one style: accent-colored filled circle, 0.4 s fade) ·
keystroke-display styles (one dark pill, all keys).

## UX flows

### Start (⌘⇧5 or menu "Record Screen…")
A compact **record strip** (floating panel, bottom-center of the active screen):

```
[ ● Record Full Screen ]  [ ⬚ Record Area… ]   MP4|GIF   🎙  🔊  📷   ✕
```

- **Record Full Screen** — recording starts immediately on that screen.
- **Record Area…** — the existing crosshair selection overlay appears; dragging a
  rect starts recording of that area immediately. Esc returns to the strip.
- **MP4|GIF** segmented toggle, **mic**, **system audio**, **camera** toggles —
  mirror Settings → Recording defaults; flipping them here persists as the new
  defaults. ✕ / Esc cancels.
- Menu bar also gets "Record Screen…" (bound shortcut shown); a second ⌘⇧5 while
  the strip is up cancels it (toggle semantics).

### While recording
- Menu-bar icon swaps to a red `stop.circle`; the status item shows an elapsed
  timer ("0:42", monospaced). Menu's first item becomes **Stop Recording**.
- **⌘⇧5 stops** (the smart toggle). Clicking the status item's Stop item stops too.
- **Camera bubble** (if enabled): circular live preview in a floating panel,
  bottom-right of the recorded region by default, drag to move, S/M size from
  Settings. It is a normal on-screen window, so it is captured *by being on screen*
  — no frame compositing.
- **Click highlights** (if enabled): a transparent, click-through overlay window
  draws a fading accent circle at every mouse-down (global mouse monitor — no
  special permission needed).
- **Keystroke display** (if enabled — permission-gated): a dark pill above the
  bottom edge shows each keypress with modifier glyphs ("⌘⇧4"), fading after ~1 s.
  Requires Accessibility trust (global keyDown monitor); the Settings toggle prompts
  via `AXIsProcessTrustedWithOptions` and stays off until granted. This is the one
  feature that needs the Accessibility prompt; everything else stays prompt-free.

### Stop
- MP4: finalized and saved to the configured save folder
  ("Recording 2026-06-04 at 19.30.12.mp4" via the existing FileNamer pattern),
  HUD: "Recording saved · 0:42".
- GIF mode: records H.264 internally, then converts (10 fps, max width 960 px,
  infinite loop) and deletes the temp MP4. HUD shows "Converting to GIF…" then
  "GIF saved · 0:42". Conversion failure keeps the MP4 and says so.
- Quick Access overlay is **not** used for recordings (it is image-based) — HUD only.

### Audio
- **System audio** via ScreenCaptureKit's audio output (`capturesAudio`).
- **Microphone** via a parallel `AVCaptureSession` (macOS 14 cannot use SCK's mic
  capture — that's macOS 15+). Mic and system audio are **two separate AAC tracks**
  in the MP4 (no live mixing; players play both).
- First mic/camera use triggers the standard permission prompts;
  `NSMicrophoneUsageDescription` + `NSCameraUsageDescription` added to Info.plist.

### Settings → new "Recording" tab
Format default (MP4/GIF) · FPS (30/60) · system audio on/off · microphone on/off ·
camera on/off + size (Small/Medium) · click highlights on/off · keystroke display
on/off (permission-gated). Persisted as a string dictionary under `"recordingConfig"`
(same convention as `captureSettings`).

### Shortcuts integration
- `HotkeyAction` gains `case record`, title "Start/Stop Recording", default ⌘⇧5
  (keyCode 23). The Shortcuts tab row appears automatically; the
  "⇧⌘5 is reserved…" caption is removed.
- **Persistence migration:** explicit unbinding now persists as the sentinel value
  `"unbound"` (a missing key means "never customized → use the default"). This lets
  v1.4 stored bindings (which lack a `record` key) pick up ⌘⇧5 automatically while
  still honoring deliberate clears across upgrades. `HotkeyBindings` change + tests.
- Native ⌘⇧5 (macOS screenshot toolbar, symbolic-hotkey **id 184**) is disabled at
  launch and restored at quit, exactly like native ⌘⇧4 (id 30) today —
  `SystemScreenshotShortcuts` generalizes to a list of ids.

## Architecture

### New package: `RecordingKit` (depends on TestKit for tests; AppKit/AVFoundation/SCK at runtime)
- `RecorderState.swift` — **pure** state machine: `idle → armed(strip) →
  recording(started: Date) → finishing → idle`; legal-transition table +
  `elapsedString(now:)` ("0:42", "12:05"). TestKit-tested.
- `RecordingConfig.swift` — **pure**: `format` (.mp4/.gif), `fps` (30/60),
  `systemAudio`, `microphone`, `camera`, `cameraSize` (.small/.medium),
  `clickHighlights`, `keystrokeOverlay`; string-dictionary round-trip;
  `videoSettings(width:height:)` → H.264 `AVAssetWriter` settings dict (bitrate
  heuristic `w*h*fps*0.12`, clamped 2–40 Mbps); GIF constants (10 fps, 960 px).
  TestKit-tested.
- `GIFTiming.swift` — **pure**: `frameTimes(duration:fps:)` → sample timestamps;
  `outputSize(source:maxWidth:)` aspect-preserving. TestKit-tested.
- `ScreenRecorder.swift` — the engine: builds `SCContentFilter` +
  `SCStreamConfiguration` (BGRA, `showsCursor`, `minimumFrameInterval` from fps,
  `capturesAudio`), owns `AVAssetWriter` (.mp4; video input + system-audio input +
  optional mic input), starts the writer session at the first video PTS,
  `start(filter:size:config:outputURL:) async throws` / `stop() async throws -> URL`.
  Stream errors finalize what's written and surface the error.
- `MicCapturer.swift` — `AVCaptureSession` + `AVCaptureAudioDataOutput` wrapper
  feeding CMSampleBuffers to a writer input; permission request helper.
- `CameraBubbleController.swift` — floating circular `NSPanel` with
  `AVCaptureVideoPreviewLayer`, drag-move, S/M diameter (160/240 pt), shown only
  while armed/recording.
- `ClickHighlighter.swift` — full-screen transparent, click-through panel per
  recorded screen + global `NSEvent` mouse-down monitor; fading circles
  (CAShapeLayer, 0.4 s fade). No permission required.
- `KeystrokeOverlayController.swift` — dark pill panel + global keyDown monitor
  (requires `AXIsProcessTrusted()`); renders `HotkeyCombo`-style glyph strings;
  auto-fades after 1 s. Exposes `static var hasPermission` /
  `requestPermission()` for the Settings toggle.

### CaptureKit
- `HotkeyAction` + `record` case (title, default ⌘⇧5 keyCode 23).
- `HotkeyBindings` — `"unbound"` sentinel persistence (clear keeps the key;
  missing key = use default). Tests updated/added.
- `FileNamer` — parameterized prefix/extension if not already ("Recording …", .mp4/.gif).

### App
- `RecordingCoordinator.swift` — orchestration: owns `ScreenRecorder`, strip,
  bubble, highlighters, state; `toggle()` (the ⌘⇧5 entry: idle→show strip,
  armed→cancel, recording→stop); wires HUD + saving + GIF conversion; reports state
  changes to `MenuBarController` (icon/timer/Stop item) via a callback.
- `RecordStripController.swift` — the strip panel (AppKit buttons; lives in App
  because it binds RecordingConfig to RecordingKit components and SettingsStore).
- `AppDelegate` — handler map gains `.record → recordingCoordinator.toggle()`;
  `applicationWillTerminate` best-effort stops an active recording.
- `MenuBarController` — "Record Screen…"/"Stop Recording" first menu item,
  red stop icon + elapsed-timer status text while recording.
- `SettingsStore` — `@Published recording: RecordingConfig` persisted under
  `"recordingConfig"`.
- `SettingsView` — third tab "Recording".
- `SystemScreenshotShortcuts` — generalized over ids [30 ("⌘⇧4" area), 184
  ("⌘⇧5" toolbar)].
- `Info.plist` — `NSMicrophoneUsageDescription`, `NSCameraUsageDescription`.

### Data flow
⌘⇧5 → `RecordingCoordinator.toggle()` → strip → (optional area select) →
`ScreenRecorder.start` (+ bubble/highlighter/keystroke panels) → menu-bar timer ticks
(1 s `Timer` reading `RecorderState.elapsedString`) → ⌘⇧5/Stop →
`ScreenRecorder.stop()` → (GIF convert) → save folder + HUD → state idle, panels
torn down, menu restored.

## Edge cases
- ⌘⇧5 while finishing → ignored (state machine rejects).
- Capture-command hotkeys (⌘⇧4 etc.) during recording → allowed (screenshots during
  a recording are legitimate); the selection overlay will appear in the recording —
  acceptable.
- Stream error / display disconnect mid-recording → finalize written frames, HUD
  "Recording stopped (display error)"; file kept if non-empty.
- Quit while recording → `applicationWillTerminate` awaits a short best-effort stop.
- Mic permission denied → recording proceeds without mic; HUD notes "mic unavailable".
- GIF conversion failure → MP4 kept, HUD says "Saved as MP4 (GIF conversion failed)".
- Strip shown on the screen with the mouse pointer (`NSScreen` of `NSEvent.mouseLocation`).

## Testing
- TestKit (`swift run --package-path Packages/RecordingKit RecordingKitTests`):
  `RecorderState` transition table + elapsed formatting; `RecordingConfig`
  round-trip/defaults/video-settings derivation; `GIFTiming` frame times + sizing.
- CaptureKit tests: `record` defaults, sentinel persistence migration cases.
- Engine/panels/permissions: manual GUI checklist in the plan (recording requires
  the granted Screen Recording TCC of the launched .app — not reachable from the
  test runner).
