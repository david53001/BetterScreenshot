# BetterScreenshot v2.4 — Recording Controls: Countdown · Window Target · Pause/Resume

Date: 2026-06-05 · Status: **designed — awaiting plan**
Builds on: v2.2 (`main`, commit 28403d2+; v2.3-history recommended first but not required)
Ends at tag: `v2.4-recording-controls`

> **For a fresh session:** read `CLAUDE.md` first. Then turn this spec into a plan with the
> `superpowers:writing-plans` skill and execute it with `superpowers:subagent-driven-development`.
> Verify integration-point symbols against the live code before writing the plan.

## Goal

Close the three table-stakes recording-ergonomics gaps vs CleanShot (spec §2):

1. **Countdown** — optional 3/5/10 s on-screen countdown before recording starts.
2. **Record Window** — third target on the record strip: hover-highlight any window, click to
   record just that window.
3. **Pause/Resume** — pause a running recording and resume without a gap in the output file;
   menu-bar control + bindable hotkey.

## Out of scope

Restart-recording command (cheap follow-up once pause lands — noted, not built) · resolution/
quality pickers · camera shape options / fullscreen camera · Auto-DND · hide-desktop-icons ·
hover-to-pick for *screenshot* window capture (the picker built here is deliberately reusable
for that later, but wiring ⌘⇧-window-capture to it is its own change) · trim editor (separate
spec).

## UX flows

### Countdown
- Setting: Recording tab picker "Countdown before recording": **Off (default)** / 3 s / 5 s / 10 s.
- Flow: strip target chosen (full screen, area selection completed, or window picked) → strip
  hides → countdown overlay appears on the target screen → counts down once per second → engine
  starts.
- Overlay: centered on the target screen; large monospaced digit (≈120 pt) in the established
  dark-pill recipe (`NSVisualEffectView` `.hudWindow` + `.vibrantDark`, like `HUDController`);
  non-activating, `[.canJoinAllSpaces, .fullScreenAuxiliary]`.
- **Click the countdown → skip it and start now.** **⌘⇧5 → cancel** (state is still `.armed`
  during the countdown, so the existing `toggle()` → `cancelStrip()` path already cancels; the
  countdown task must check `state` before calling `begin` — the existing
  `guard case .armed = state` in `begin` is the second line of defense).
- Countdown applies to all three targets and both formats.

### Record Window
- Strip gains "Record Window…" button between "Record Full Screen" and "Record Area…".
- Flow: strip hides → window picker overlay covers the screen(s): moving the mouse highlights
  the window under the cursor (accent-color stroke + light fill over its frame, window title in
  a small caption); click confirms; Esc or ⌘⇧5 cancels (same key handling pattern as
  `SelectionOverlayController`).
- Own windows (strip, overlays, pins) and non-normal windows (menus, docks — window layer ≠ 0)
  are never offered.
- Recording uses `SCContentFilter(desktopIndependentWindow:)`; output is the window's pixel
  size (frame × `backingScaleFactor`, floored to even). If the window closes mid-recording the
  stream errors and the existing `streamFailed()` → `stop()` path finalizes what was captured.
- Camera bubble / click highlights / keystroke overlay behave exactly as in full-screen mode
  (they are screen-level, not window-level — acceptable v1 simplification, noted in checklist).

### Pause / Resume
- While recording, the menu-bar dropdown shows **"Pause Recording"** (then **"Resume
  Recording"**); new bindable hotkey action `pauseResumeRecording` (default unbound).
- Menu-bar timer shows the **recorded** time (pauses excluded) and a paused indicator —
  `onStateChange` elapsed string becomes e.g. `"Paused · 0:42"` while paused.
- The output file contains **no gap**: frames captured while paused are dropped and
  post-resume timestamps are shifted back so playback is seamless.
- ⌘⇧5 while paused stops the recording (same as while recording). Quit while paused finalizes
  normally via `stopForTermination`.
- Pause is available only in `.recording` (not during countdown/arming).

## Architecture

### CaptureKit (pure, TDD)
- `HotkeyAction` — new case `pauseResumeRecording`, `defaultCombo == nil`.
- `WindowPicking.swift` — **pure** window hit-testing:
  `struct PickableWindow { id: UInt32, frame: CGRect, title: String?, layer: Int, ownerPID: pid_t }`
  and `WindowPicking.topmost(at: CGPoint, windows: [PickableWindow], excludingPID: pid_t) -> PickableWindow?`
  — input array is **front-to-back ordered** (caller's contract); filters `layer == 0`,
  excludes own PID, returns the first whose frame contains the point. TDD with synthetic lists
  (overlap, layering, own-window exclusion, miss).
  - The App builds the ordered list from `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)`
    (which **is** documented front-to-back, unlike `SCShareableContent.windows`) and maps the
    picked `id` to the matching `SCWindow` for the filter.

### RecordingKit
- `RecorderState.swift` (pure, TDD) — new case `.paused`; the state must now track
  `startedAt: Date`, `pausedAt: Date?`, and `accumulatedPause: TimeInterval`. Transitions:
  `.recording → .paused` (`.pause(Date)`), `.paused → .recording` (`.resume(Date)` adds to
  `accumulatedPause`), `.paused → .finishing` (`.finish`). All illegal transitions rejected.
  `elapsedString(now:)` excludes paused time (frozen while paused).
- `PauseTimeline.swift` (pure, TDD) — CMTime bookkeeping for the writer:
  accumulates pause gaps and answers `offset(for samplePTS: CMTime) -> CMTime`; built from
  pause/resume boundary PTS pairs. Property: output PTS sequence is contiguous and monotonic
  across a pause.
- `ScreenRecorder` — `pause()` / `resume()`: a flag flipped **on `sampleQueue`** (sync) so it
  serializes with appends. While paused every video/audio/mic sample is dropped. On the first
  video sample after resume, the gap (`samplePTS − lastAppendedVideoPTS − one frame duration`)
  is added to a running `ptsOffset`; **all** subsequent samples (video, system audio, mic) are
  retimed via `CMSampleBufferCreateCopyWithNewTiming(sampleBuffer, pts − ptsOffset)` before
  append. Audio buffers arriving with PTS inside a dropped span are discarded.
- `CountdownOverlayController.swift` — the countdown panel described above;
  `show(seconds:on:onTick:onFinished:onSkip:)`, `cancel()`. Lives in RecordingKit beside the
  other recording panels (camera bubble, keystroke overlay).
- `RecordingConfig` — new `countdownSeconds: Int` (0 = off) with string-dictionary round-trip
  (TDD).

### OverlayKit
- `WindowPickerController.swift` — generic picker panel that knows nothing about windows or
  CaptureKit. The App injects a hit-test closure
  `(CGPoint) -> (id: UInt32, frame: CGRect, title: String?)?` (global mouse location in, the
  hovered window's id + **Cocoa-coords** frame + title out — the App implements it with
  `WindowPicking.topmost`); the controller tracks mouseMoved, calls the closure, and draws the
  highlight + title caption from the returned frame. Same dependency-inversion pattern as
  `QuickAccessStackController`'s `originForIndex`. Esc/⌘⇧5 cancel; click confirms via
  `onPicked: (UInt32?) -> Void` (nil = cancelled). Coordinate note:
  `CGWindowListCopyWindowInfo` bounds are **top-left-origin global** — the App converts to
  Cocoa bottom-left before hit-testing/highlighting (conversion helper is pure, test it).

### App
- `RecordingCoordinator` —
  - `begin` gains the countdown step: after panels/permissions are resolved but **before**
    `recorder.start`, if `config.countdownSeconds > 0` await the countdown (cancellable;
    re-check `.armed` after).
  - `beginWindowSelection()`: fetch `CGWindowListCopyWindowInfo` + `SCShareableContent`,
    build `PickableWindow` list, present `WindowPickerController`; on pick, resolve the
    `SCWindow`, compute pixel size, `begin` with a window filter. Plumb a
    `target: RecordingTarget` (display-filter vs window-filter) through `begin` rather than
    a second begin path.
  - `pauseResume()`: guards state, calls `recorder.pause()/resume()`, transitions
    `RecorderState`, `notify()`.
  - `onStateChange` signature unchanged (`(Bool, String?)`) — paused state is encoded in the
    elapsed string ("Paused · 0:42"); menu item title flips off `state`.
- `RecordStripController` — third button "Record Window…" → `onWindow` callback.
- `MenuBarController` — "Pause Recording"/"Resume Recording" item, visible only while
  recording/paused.
- `SettingsView` — Recording tab countdown picker; Shortcuts tab row for
  `pauseResumeRecording` (existing unbound-row support).

## Error handling

- Window picked but its `SCWindow` vanished before `recorder.start` → existing catch shows
  "Couldn't start recording".
- Pause/resume calls in wrong states are no-ops (state machine rejects; coordinator guards).
- Countdown cancelled (⌘⇧5) → strip/panels torn down exactly like today's armed-cancel.
- Window closes mid-recording → `streamFailed` finalizes the partial file (existing behavior).

## Testing

- **TestKit (automated)**: `RecorderState` pause/resume/finish transitions + frozen/excluded
  elapsed math; `PauseTimeline` offset properties (single + multiple pauses, contiguity,
  monotonicity); `WindowPicking.topmost` synthetic cases; top-left↔Cocoa frame conversion;
  `RecordingConfig.countdownSeconds` round-trip; `HotkeyAction` table.
- **Manual checklist (GUI)**: countdown 3 s on each target; click-to-skip; ⌘⇧5 cancel during
  countdown; window record of Safari incl. moving the window mid-recording (capture follows the
  window) and closing it (partial file saved); pause 5 s mid-recording → output has no gap and
  A/V stays in sync (mic + system audio); timer freezes while paused and shows "Paused"; pause
  hotkey after binding it; GIF recording with pause; quit while paused.

## Build order (one plan)

1. `RecorderState` pause transitions + elapsed (TDD) → 2. `PauseTimeline` (TDD) →
3. `ScreenRecorder.pause/resume` + retiming → 4. coordinator/menu/hotkey wiring for pause →
5. `RecordingConfig.countdownSeconds` (TDD) + `CountdownOverlayController` + begin-flow hook →
6. `WindowPicking` + frame conversion (TDD) → 7. `WindowPickerController` + strip button +
window begin path → 8. Manual checklist, CHANGELOG, README, bump 2.4.0, tag
`v2.4-recording-controls`.

## Risks / probes for the implementing session

- **PTS retiming is the riskiest piece** — probe early (build-order step 3): record → pause 3 s
  → resume → stop; inspect duration (`AVAsset.duration` ≈ recorded time, not wall time) and
  play back for A/V sync. If `CMSampleBufferCreateCopyWithNewTiming` misbehaves with SCK
  buffers, fallback: segment files per pause + `AVMutableComposition` stitch at stop (more code,
  same UX — switch only if the probe fails).
- System-audio PTS during the pause boundary: buffers spanning the boundary are dropped whole —
  a ≤1 buffer (~21 ms) audio nick at the seam is acceptable.
- `SCContentFilter(desktopIndependentWindow:)` records the window even when occluded/moved —
  verify on macOS 14 (documented behavior, but confirm in the window-record manual check).
- The picker excludes windows by PID — overlays created by BetterScreenshot itself must never
  be pickable (test with the strip visible).
