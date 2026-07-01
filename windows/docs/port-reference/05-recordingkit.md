# Port Reference — RecordingKit (ground truth for the C#/.NET port)

Source = Swift `Packages/RecordingKit`. Target namespace `BetterScreenshot.Recording`.
Highest-complexity module. **Windows engine = ffmpeg (installed: 8.1.1)** driving DXGI Desktop Duplication
(`ddagrab`) or `gdigrab` for video, WASAPI loopback for system audio, `dshow` for mic; plus WPF overlay windows
for camera/click/keystroke/countdown. Pure-logic pieces (config, state machine, pause timeline, GIF timing) port 1:1 and are unit-tested.

## RecordingConfig (PURE, dictionary-persisted)
```
format:           mp4 | gif                (default mp4)
fps:              30 | 60                   (default 30; invalid → 30)
systemAudio:      bool                      (default true)
microphone:       bool                      (default false)
camera:           bool                      (default false)
cameraSize:       small(160) | medium(240)  (default small)  -- diameter in px
clickHighlights:  bool                      (default true)
keystrokeOverlay: bool                      (default false)
countdownSeconds: 0 | 3 | 5 | 10           (default 0; invalid → 0)
```
Constants: `gifFPS=10`, `gifMaxWidth=960`.
`videoSettings(w,h)`: H.264, bitrate = `clamp(w*h*fps*0.12, 2_000_000, 40_000_000)` bps.
(For ffmpeg: `-b:v` from same formula, or `-crf` fallback.) Round pixel dims to **even** (H.264).

## RecorderState (PURE state machine)
States: `idle → armed → recording(started,accumulatedPause) / paused(started,accumulatedPause,since) → finishing → idle`.
Events: arm, begin(date), pause(date), resume(date), finish, reset. `transition(event)→bool` (rejects illegal).
`elapsedString(now)`: recording → `"m:ss"` = now-started-accumulatedPause; paused → `"Paused · m:ss"` frozen; else null.
Legal: idle→armed→recording→finishing→idle; recording↔paused; paused→finishing. Illegal transitions rejected.

## PauseTimeline (PURE — gapless pause)
- Accumulates pause gaps as a time offset. `resume(lastPTSBeforePause, firstPTSAfterResume, frameDuration)`:
  gap = firstAfter - lastBefore - frameDuration; if gap>0 add to offset (ignore ≤0). `adjusted(pts) = pts - offset`.
- Guarantees output timeline is contiguous & monotonic across pause boundaries.
- **Windows/ffmpeg strategy:** record contiguous while paused = drop frames; simplest faithful approach = write
  segments per active span and concat, OR feed ffmpeg via pipe and retime PTS with `setpts`/`asetpts`. Probe early
  (probe: record 30s, pause 5s, resume, stop → expect ~25s, A/V in sync). Keep PauseTimeline as the model of truth.

## GIFTiming (PURE) + GIFExporter
- `frameTimes(duration, fps)` → [0, 1/fps, 2/fps, …] (e.g. 2.5s@10 → 25 frames 0.0..2.4).
- `outputSize(source, maxWidth=960)` → aspect-preserving downscale, **never upscale** (1920x1080→960x540; 800x600→800x600).
- Export MP4→GIF: **Windows = ffmpeg** `fps=10,scale=min(960,iw):-1:flags=lanczos` + palettegen/paletteuse, loop forever. Delete temp MP4 on success. Must be fast (seconds).

## ScreenRecorder engine (the imperative part — reimplement on ffmpeg)
- Video: capture region/window/full at fps, pixelFormat BGRA, cursor shown.
- System audio (if enabled): WASAPI loopback → AAC track. Mic (if enabled): dshow default mic → AAC track. **Separate tracks**, 48kHz/2ch/128kbps each (don't pre-mix). If both, mux both.
- Pause = stop feeding samples; Resume sets pendingResume; **first sample after resume (video OR audio) clears pendingResume** and computes the gap (critical: on a static screen only audio arrives, so audio must also clear it — this was a real bug fix). All post-resume samples retimed by offset.
- Window target: capture full display then crop to window rect (DXGI can't crop to a window natively); track window rect. Or use Graphics.Capture item per-HWND if feasible.
- Area target: crop to `sourceRect`. Full: whole monitor.
- Finalize: stop stream+mic, mark inputs finished, finish writing, return output path.
- On app quit: best-effort finalize with timeout (~3s), partial file better than frozen.

## Overlay controllers (WPF topmost click-through windows; captured because they're on-screen)
- **CountdownOverlayController.run(seconds, screen)**: 200×200 centered dark pill (radius 24), **120pt** mono semibold digit, per-second tick, click-to-skip, cancellable via `cancel()`. If cancelled mid-countdown, abort recording.
- **CameraBubbleController.show(near rect, screen, diameter)**: circular webcam preview (diameter 160/240, radius=Ø/2), bottom-right of region + 24 margin, draggable, aspect-fill. Windows: `Windows.Media.Capture` / `MediaCapture` or ffmpeg dshow preview → render into WPF. Included in capture because it's an on-screen window.
- **ClickHighlighter.start(screen)**: full-screen transparent click-through window; global mouse-down hook (`WH_MOUSE_LL`); draws **Ø36** accent@0.45 circle at click, **0.4s** opacity fade then remove.
- **KeystrokeOverlayController.start(screen)**: **280×44** dark pill (black@0.75, radius 10) top-center 100px from top, **20pt** mono semibold white; global keyDown hook (`WH_KEYBOARD_LL`, no special perm on Windows); shows modifier glyphs + char, **1.0s** fade. glyphs: Ctrl/Alt/Shift/Win + ↩ ⇥ Space ⌫ Esc ← ↑ → ↓ + uppercased char.

## App-level (RecordingCoordinator) — belongs in App layer but summarized here
- Targets: display(globalRect? — nil=full, else area) | window(hwnd). Route to capture region.
- Flow: toggle() → arm (show record strip) → pick target → (countdown if>0) → begin → recording → stop → (GIF convert if gif) → thumbnail → history → Quick Access card.
- `onStateChange(isRecording, elapsedString)` drives tray icon/timer (isRecording true while recording OR paused).
- `onPauseStateChange(active, paused)` drives Pause/Resume menu item.

## Constants table
mp4/30fps/sysAudio on/mic off/cam off/small 160(med 240)/clicks on/keystroke off/countdown 0 ·
gifFPS 10 gifMaxW 960 · bitrate w*h*fps*0.12 clamp[2,40]Mbps · audio 48k AAC 2ch 128k · queueDepth 6 ·
click Ø36 accent@0.45 fade 0.4s · keystroke 280×44 20pt fade 1.0s radius10 · countdown 200×200 120pt radius24.

## Tests to re-create (xUnit)
RecorderState: legal/illegal transitions; elapsed excludes pause (start0,pause10,resume13,@20 → 7s).
RecordingConfig: all 9 fields round-trip; fps∈{30,60} else 30; countdown∈{0,3,5,10} else 0; videoSettings 1920x1080@30≈7.46Mbps; 100x100@30 clamps to 2Mbps; GIF size 1920x1080→960x540, 800x600→800x600; GIF timing 2.5s@10→25 frames.
PauseTimeline: zero offset default; single pause contiguous; multiple pauses accumulate; ≤0 gap ignored; output PTS strictly increasing across pause.

## Icons used (author natively — see icons.md)
mic, speaker.wave.2, video, xmark.circle.fill, stop.circle.fill, record.circle.
