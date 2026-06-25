# v2.4 Recording Controls Implementation Plan — Countdown · Window Target · Pause/Resume

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Source spec:** `docs/superpowers/specs/2026-06-05-betterscreenshot-recording-controls-design.md`
**Read first:** root `CLAUDE.md` (project constraints + stack), then this plan top-to-bottom.

**Goal:** Add three recording-ergonomics controls to BetterScreenshot — an optional pre-record countdown, a "Record Window…" target on the record strip, and pause/resume that produces a gap-free output file — closing the table-stakes gaps vs CleanShot.

**Architecture:** Pure, test-first logic lands in the Swift packages (`RecorderState` pause math + `PauseTimeline` PTS bookkeeping in `RecordingKit`; `WindowPicking` hit-test + coordinate conversion in `CaptureKit`). The AppKit/AV pieces (`ScreenRecorder` retiming, `CountdownOverlayController`, `WindowPickerController`) are wired through the existing `RecordingCoordinator` single recording path. Pause state rides inside the existing `RecorderState` enum (evolved to carry accumulated-pause time) and the existing `onStateChange` menu-bar callback (paused indicator encoded in the elapsed string); a small dedicated callback drives the new Pause/Resume menu item.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit hybrid, ScreenCaptureKit, AVFoundation/CoreMedia, Carbon hotkeys. SwiftPM build; custom **TestKit** executable test runners (NOT XCTest).

---

## Global Constraints

Every task's requirements implicitly include this section.

- **Min deployment target: macOS 14 (Sonoma).** All packages already declare `platforms: [.macOS(.v14)]`.
- **No cloud, ever.** Local features only — no uploads, accounts, share links, sync.
- **Non-sandboxed, menu-bar agent (`LSUIElement`), ad-hoc signed.** Personal/local use.
- **Testing is via the custom TestKit harness, NOT XCTest.** A package's suite runs with `swift run --package-path Packages/<Pkg> <Pkg>Tests`. All suites: `scripts/test.sh`. Each test file declares a top-level `let <name>Tests: [TestCase] = [ … ]` and is concatenated into that package's `Tests/<Pkg>Tests/main.swift` `runTests(...)` call. Assertions: `t.equal`, `t.isTrue`, `t.isFalse`, `t.isNil`, `t.notNil`, `t.unwrap`, `t.approxEqual(_:_:tol:)`, `t.fail`.
- **Build commands:** plain compile `swift build`; signed app bundle `scripts/build-app.sh` → `dist/BetterScreenshot.app`.
- **`HotkeyAction` raw values are persistence keys — never rename existing cases.** New cases append.
- **Coordinate convention:** annotations/regions live in base-image pixel space, top-left origin. `CGWindowListCopyWindowInfo` bounds are **top-left-origin global**; convert to **Cocoa bottom-left global** before hit-testing/highlighting (pure helper, tested).
- **Surgical changes only.** Touch what each task needs; match existing style; don't refactor unrelated code.
- **Ends at git tag `v2.4-recording-controls`; app version `2.4.0`.**

---

## Reconciliations with the spec (verified against live code 2026-06-25)

The spec named several symbols/recipes that differ slightly from the current code. These adaptations are baked into the tasks below — they are intentional, not drift:

1. **`RecorderState` is an enum, not a struct.** Live: `enum RecorderState { case idle, armed, recording(started: Date), finishing }`. We evolve it in place: `recording(started:accumulatedPause:)` + a new `paused(started:accumulatedPause:since:)` case, and new events `.pause(Date)` / `.resume(Date)`. (Spec described a struct with `startedAt`/`pausedAt`/`accumulatedPause`; the enum carries the same information.)
2. **The HUD recipe (`NSVisualEffectView` `.hudWindow` + `.vibrantDark`) lives in `OverlayKit/HUDController.swift`, which `RecordingKit` does not import.** The new `CountdownOverlayController` (in `RecordingKit`) replicates that recipe inline.
3. **Pause menu wiring:** `onStateChange: (Bool, String?)` stays unchanged (paused indicator rides in the elapsed string, e.g. `"Paused · 0:42"`). A new `onPauseStateChange: (Bool, Bool)` callback drives the Pause/Resume **menu item** title + visibility. `RecordingCoordinator.isRecording` is widened to return `true` for `.paused` too (so the status-bar stop icon + timer persist while paused).
4. **`CountdownOverlayController` API** is an async `run(seconds:on:) async` + `cancel()` (cleaner for the `await` inside `begin`) rather than the callback-style `show(...)` the spec sketched. Behavior is identical: per-second tick, click-to-skip, cancellable.
5. **Window target plumbing:** `begin(globalRect:screen:)` is refactored to `begin(target:screen:)` with a private `RecordingTarget` enum (`.display(globalRect:)` / `.window(CGWindowID)`); one path, countdown shared. `cancelStrip()` also cancels the window picker + countdown.
6. **Window-screenshot capture already uses `SCContentFilter(desktopIndependentWindow:)`** (`CaptureKit/CaptureService.swift:40`) and resolves `content.windows.first { $0.windowID == windowID }` — the window-recording path reuses that exact idiom.

---

## File Structure

**Created:**
- `Packages/RecordingKit/Sources/RecordingKit/PauseTimeline.swift` — pure CMTime offset bookkeeping (Task 3).
- `Packages/RecordingKit/Sources/RecordingKit/CountdownOverlayController.swift` — countdown HUD panel (Task 7).
- `Packages/RecordingKit/Tests/RecordingKitTests/PauseTimelineTests.swift` — Task 3.
- `Packages/CaptureKit/Sources/CaptureKit/WindowPicking.swift` — pure window hit-test + frame conversion (Task 10).
- `Packages/CaptureKit/Tests/CaptureKitTests/WindowPickingTests.swift` — Task 10.
- `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyActionTests.swift` — Task 1.
- `Packages/OverlayKit/Sources/OverlayKit/WindowPickerController.swift` — generic window picker overlay (Task 11).

**Modified:**
- `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift` — new case (Task 1).
- `Packages/CaptureKit/Tests/CaptureKitTests/main.swift` — register new suites (Tasks 1, 10).
- `Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift` — pause states/events/elapsed (Task 2).
- `Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift` — updated/added tests (Task 2).
- `Packages/RecordingKit/Tests/RecordingKitTests/main.swift` — register `pauseTimelineTests` (Task 3).
- `Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift` — pause/resume + retiming (Task 4).
- `Packages/RecordingKit/Sources/RecordingKit/RecordingConfig.swift` — `countdownSeconds` (Task 6).
- `Packages/RecordingKit/Tests/RecordingKitTests/RecordingConfigTests.swift` — round-trip test (Task 6).
- `App/Recording/RecordingCoordinator.swift` — pause/resume, `begin(target:)`, countdown, window selection (Tasks 5, 8, 9, 11).
- `App/MenuBar/MenuBarController.swift` — Pause/Resume menu item (Task 5).
- `App/Lifecycle/AppDelegate.swift` — wiring + hotkey handler (Task 5).
- `App/Settings/SettingsView.swift` — countdown picker (Task 6).
- `App/Recording/RecordStripController.swift` — "Record Window…" button (Task 11).
- `CHANGELOG.md`, `README.md`, `App/Info.plist` — release (Task 12).

---

## Task 1: `HotkeyAction.pauseResumeRecording` (CaptureKit, TDD)

Adds the new bindable, default-unbound hotkey action used by the pause/resume control.

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyActionTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

**Interfaces:**
- Produces: `HotkeyAction.pauseResumeRecording` (raw value `"pauseResumeRecording"`), `.title == "Pause/Resume Recording"`, `.defaultCombo == nil`. Consumed by Task 5 (AppDelegate handler + MenuBar) and the Shortcuts tab (auto-renders all `allCases`).

- [ ] **Step 1: Write the failing test**

Create `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyActionTests.swift`:

```swift
import TestKit
@testable import CaptureKit

let hotkeyActionTests: [TestCase] = [
    TestCase("pauseResumeRecordingIsUnboundByDefault") { t in
        t.isTrue(HotkeyAction.allCases.contains(.pauseResumeRecording))
        t.isNil(HotkeyAction.pauseResumeRecording.defaultCombo)   // bindable, no default
        t.isFalse(HotkeyAction.pauseResumeRecording.title.isEmpty)
        t.equal(HotkeyAction.pauseResumeRecording.rawValue, "pauseResumeRecording")
    },
]
```

- [ ] **Step 2: Register the suite**

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, append `+ hotkeyActionTests` to the `runTests(...)` concatenation (e.g. after `textRecognizerTests`).

- [ ] **Step 3: Run test to verify it fails**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error / FAIL — `pauseResumeRecording` is not a member of `HotkeyAction`.

- [ ] **Step 4: Add the enum case**

In `HotkeyAction.swift`, append the case to the declaration (line 5–6):

```swift
    case captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard, record,
         openHistory, restoreRecentlyClosed, pauseResumeRecording
```

Add to the `title` switch (after the `.restoreRecentlyClosed` line):

```swift
        case .pauseResumeRecording:  return "Pause/Resume Recording"
```

Add to the `defaultCombo` switch (after the `.restoreRecentlyClosed` line):

```swift
        case .pauseResumeRecording:  return nil
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: PASS — `✓ pauseResumeRecordingIsUnboundByDefault` and all existing CaptureKit tests still pass.

- [ ] **Step 6: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/HotkeyActionTests.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/main.swift
git commit -m "feat(capture): add pauseResumeRecording hotkey action"
```

---

## Task 2: `RecorderState` pause/resume + accumulated-pause elapsed (RecordingKit, TDD)

Evolves the recording state machine to support pause/resume and excludes paused time from the elapsed timer.

**Files:**
- Modify: `Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift`
- Modify (update existing): `Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift`

**Interfaces:**
- Produces:
  - `RecorderState.recording(started: Date, accumulatedPause: TimeInterval)`
  - `RecorderState.paused(started: Date, accumulatedPause: TimeInterval, since: Date)`
  - Events `.pause(Date)`, `.resume(Date)` (plus existing `.arm`, `.begin(Date)`, `.finish`, `.reset`).
  - `elapsedString(now:)` returns `"m:ss"` while recording (minus accumulated pause), `"Paused · m:ss"` while paused (frozen), `nil` otherwise.
  - Consumed by Task 5 (`RecordingCoordinator` transitions + `isRecording`/`isPaused`).

- [ ] **Step 1: Replace the existing state tests**

Overwrite `Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift` with:

```swift
import TestKit
import Foundation
@testable import RecordingKit

let recorderStateTests: [TestCase] = [
    TestCase("legalTransitions") { t in
        var s = RecorderState.idle
        t.isTrue(s.transition(.arm)); t.equal(s, .armed)
        t.isTrue(s.transition(.begin(Date(timeIntervalSince1970: 100))))
        if case .recording(let started, let acc) = s {
            t.equal(started, Date(timeIntervalSince1970: 100)); t.equal(acc, 0)
        } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)
        t.isTrue(s.transition(.reset)); t.equal(s, .idle)
    },
    TestCase("pauseResumeTransitions") { t in
        var s = RecorderState.armed
        _ = s.transition(.begin(Date(timeIntervalSince1970: 0)))
        t.isTrue(s.transition(.pause(Date(timeIntervalSince1970: 10))))   // recording → paused
        if case .paused(let started, let acc, let since) = s {
            t.equal(started, Date(timeIntervalSince1970: 0)); t.equal(acc, 0)
            t.equal(since, Date(timeIntervalSince1970: 10))
        } else { t.fail("expected .paused") }
        t.isTrue(s.transition(.resume(Date(timeIntervalSince1970: 13))))  // paused → recording, +3s
        if case .recording(_, let acc) = s { t.equal(acc, 3) } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)
    },
    TestCase("pauseThenFinish") { t in
        var s = RecorderState.armed
        _ = s.transition(.begin(Date(timeIntervalSince1970: 0)))
        _ = s.transition(.pause(Date(timeIntervalSince1970: 5)))
        t.isTrue(s.transition(.finish)); t.equal(s, .finishing)           // paused → finishing (⌘⇧5 / quit)
    },
    TestCase("illegalTransitionsRejected") { t in
        var s = RecorderState.idle
        t.isFalse(s.transition(.finish))
        t.isFalse(s.transition(.begin(Date())))
        t.isFalse(s.transition(.pause(Date())))     // can't pause when idle
        t.isFalse(s.transition(.resume(Date())))    // can't resume when idle
        s = .armed
        t.isFalse(s.transition(.pause(Date())))     // can't pause from armed (no engine yet)
        s = .finishing
        t.isFalse(s.transition(.arm))
        t.isFalse(s.transition(.pause(Date())))
        s = .armed
        t.isTrue(s.transition(.reset)); t.equal(s, .idle)
    },
    TestCase("elapsedExcludesPause") { t in
        let start = Date(timeIntervalSince1970: 0)
        // recording with 3 s accumulated pause: at now = +10 → 7 s of real recording
        let rec = RecorderState.recording(started: start, accumulatedPause: 3)
        t.equal(rec.elapsedString(now: start.addingTimeInterval(10)), "0:07")
        t.equal(rec.elapsedString(now: start.addingTimeInterval(725)), "12:02")
        // paused freezes at since - started - acc, independent of now
        let paused = RecorderState.paused(started: start, accumulatedPause: 3,
                                          since: start.addingTimeInterval(20))
        t.equal(paused.elapsedString(now: start.addingTimeInterval(999)), "Paused · 0:17")
        t.isNil(RecorderState.idle.elapsedString(now: Date()))
    },
]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: compile error / FAIL — `.recording` takes one associated value, `.pause`/`.paused` don't exist.

- [ ] **Step 3: Rewrite `RecorderState`**

Overwrite `Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift` with:

```swift
import Foundation

/// Pure recording state machine. `recording`/`paused` carry the start time and
/// the total time spent paused so the elapsed timer can exclude pauses.
public enum RecorderState: Equatable {
    case idle
    case armed                                                   // record strip showing
    case recording(started: Date, accumulatedPause: TimeInterval)
    case paused(started: Date, accumulatedPause: TimeInterval, since: Date)
    case finishing                                              // writer finalizing — new commands rejected

    public enum Event: Equatable {
        case arm                     // show the strip
        case begin(Date)             // capture started
        case pause(Date)             // recording → paused at this time
        case resume(Date)            // paused → recording at this time
        case finish                  // stop requested
        case reset                   // back to idle (finalized or cancelled)
    }

    /// Applies `event` if legal; returns whether the state changed.
    @discardableResult
    public mutating func transition(_ event: Event) -> Bool {
        switch (self, event) {
        case (.idle, .arm):                       self = .armed
        case (.armed, .begin(let date)):          self = .recording(started: date, accumulatedPause: 0)
        case (.armed, .reset):                    self = .idle
        case (.recording(let started, let acc), .pause(let at)):
            self = .paused(started: started, accumulatedPause: acc, since: at)
        case (.paused(let started, let acc, let since), .resume(let at)):
            self = .recording(started: started, accumulatedPause: acc + at.timeIntervalSince(since))
        case (.recording, .finish):               self = .finishing
        case (.paused, .finish):                  self = .finishing
        case (.finishing, .reset):                self = .idle
        default:                                  return false
        }
        return true
    }

    /// "m:ss" while recording (paused time excluded); "Paused · m:ss" (frozen)
    /// while paused; nil otherwise.
    public func elapsedString(now: Date) -> String? {
        switch self {
        case .recording(let started, let acc):
            let secs = max(0, Int(now.timeIntervalSince(started) - acc))
            return "\(secs / 60):" + String(format: "%02d", secs % 60)
        case .paused(let started, let acc, let since):
            let secs = max(0, Int(since.timeIntervalSince(started) - acc))
            return "Paused · \(secs / 60):" + String(format: "%02d", secs % 60)
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: PASS — all five `recorderStateTests` plus existing `recordingConfigTests` pass.

> NOTE: `App/Recording/RecordingCoordinator.swift` references `.recording` via `if case .recording = state` (still valid — binds nothing) and `state.transition(.begin(Date()))` (still valid). It does **not** construct `.recording` directly, so the app still compiles. Pause wiring lands in Task 5; do not touch the coordinator here.

- [ ] **Step 5: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift \
        Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift
git commit -m "feat(recording): RecorderState pause/resume with accumulated-pause elapsed"
```

---

## Task 3: `PauseTimeline` PTS-offset bookkeeping (RecordingKit, TDD)

Pure CoreMedia helper the recorder uses to retime post-resume sample buffers into a gap-free, monotonic timeline.

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/PauseTimeline.swift`
- Create: `Packages/RecordingKit/Tests/RecordingKitTests/PauseTimelineTests.swift`
- Modify: `Packages/RecordingKit/Tests/RecordingKitTests/main.swift`

**Interfaces:**
- Produces:
  - `struct PauseTimeline` with `init()`, `var currentOffset: CMTime { get }`, `mutating func resume(lastPTSBeforePause: CMTime, firstPTSAfterResume: CMTime, frameDuration: CMTime)`, `func adjusted(_ pts: CMTime) -> CMTime`.
  - Consumed by Task 4 (`ScreenRecorder`).

- [ ] **Step 1: Write the failing test**

Create `Packages/RecordingKit/Tests/RecordingKitTests/PauseTimelineTests.swift`:

```swift
import TestKit
import CoreMedia
@testable import RecordingKit

let pauseTimelineTests: [TestCase] = [
    TestCase("zeroOffsetByDefault") { t in
        let tl = PauseTimeline()
        let p = CMTime(value: 10, timescale: 60)
        t.isTrue(tl.adjusted(p) == p)
        t.isTrue(tl.currentOffset == .zero)
    },
    TestCase("contiguousAndMonotonicAcrossOnePause") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        let lastBefore = CMTime(value: 120, timescale: 60)   // 2.0 s
        let firstAfter = CMTime(value: 360, timescale: 60)   // 6.0 s (≈4 s paused)
        tl.resume(lastPTSBeforePause: lastBefore, firstPTSAfterResume: firstAfter, frameDuration: fd)
        // No gap at the seam: adjusted(firstAfter) == adjusted(lastBefore) + frameDuration.
        t.approxEqual(CMTimeGetSeconds(tl.adjusted(firstAfter)),
                      CMTimeGetSeconds(tl.adjusted(lastBefore) + fd))
        // Monotonic across the seam.
        t.isTrue(CMTimeGetSeconds(tl.adjusted(firstAfter)) > CMTimeGetSeconds(tl.adjusted(lastBefore)))
    },
    TestCase("accumulatesMultiplePauses") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        tl.resume(lastPTSBeforePause: CMTime(value: 60, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 180, timescale: 60), frameDuration: fd)
        let afterFirst = tl.currentOffset
        tl.resume(lastPTSBeforePause: CMTime(value: 240, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 360, timescale: 60), frameDuration: fd)
        t.isTrue(CMTimeGetSeconds(tl.currentOffset) > CMTimeGetSeconds(afterFirst))
    },
    TestCase("ignoresZeroOrNegativeGap") { t in
        var tl = PauseTimeline()
        let fd = CMTime(value: 1, timescale: 60)
        // First frame after resume is exactly one frame later → gap == 0 → no offset change.
        tl.resume(lastPTSBeforePause: CMTime(value: 60, timescale: 60),
                  firstPTSAfterResume: CMTime(value: 61, timescale: 60), frameDuration: fd)
        t.isTrue(tl.currentOffset == .zero)
    },
]
```

- [ ] **Step 2: Register the suite**

In `Packages/RecordingKit/Tests/RecordingKitTests/main.swift`, change the call to:

```swift
runTests("RecordingKitTests",
    recorderStateTests + recordingConfigTests + pauseTimelineTests
)
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: compile error / FAIL — `PauseTimeline` is undefined.

- [ ] **Step 4: Implement `PauseTimeline`**

Create `Packages/RecordingKit/Sources/RecordingKit/PauseTimeline.swift`:

```swift
import CoreMedia

/// Accumulates the time skipped across pause/resume boundaries so the writer can
/// retime post-resume sample buffers into a gap-free, monotonic timeline.
public struct PauseTimeline: Equatable {
    private var offset: CMTime

    public init() { offset = .zero }

    /// Total accumulated offset to subtract from raw sample PTS.
    public var currentOffset: CMTime { offset }

    /// Extend the offset by the silent gap between the last frame appended before
    /// pausing and the first frame after resuming. A zero/negative gap is ignored.
    public mutating func resume(lastPTSBeforePause: CMTime,
                                firstPTSAfterResume: CMTime,
                                frameDuration: CMTime) {
        let gap = firstPTSAfterResume - lastPTSBeforePause - frameDuration
        if gap > .zero { offset = offset + gap }
    }

    /// Raw PTS mapped into the gap-free timeline.
    public func adjusted(_ pts: CMTime) -> CMTime { pts - offset }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: PASS — `pauseTimelineTests` all green.

- [ ] **Step 6: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/PauseTimeline.swift \
        Packages/RecordingKit/Tests/RecordingKitTests/PauseTimelineTests.swift \
        Packages/RecordingKit/Tests/RecordingKitTests/main.swift
git commit -m "feat(recording): add PauseTimeline PTS-offset bookkeeping"
```

---

## Task 4: `ScreenRecorder` pause/resume + gap-free retiming (RecordingKit) + manual probe

> **This is the riskiest piece (per the spec).** A manual probe is the final step. If it fails, the documented fallback is segment-per-pause files stitched with `AVMutableComposition` at stop — switch only if the probe fails.

Adds `pause()` / `resume()` to the engine. While paused, all samples are dropped. On the first video frame after resume, the silent gap is folded into a `PauseTimeline`, and every subsequent sample (video, system audio, mic) is retimed by subtracting the accumulated offset before append — so the output file has no gap.

**Files:**
- Modify: `Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift`

**Interfaces:**
- Consumes: `PauseTimeline` (Task 3).
- Produces: `ScreenRecorder.pause()`, `ScreenRecorder.resume()` (both flip a flag on `sampleQueue`). Consumed by Task 5 (`RecordingCoordinator`).

There is no automated test for `ScreenRecorder` (AV/SCK live capture) — verification is `swift build` + the manual probe.

- [ ] **Step 1: Add pause/resume state fields**

In `ScreenRecorder.swift`, after the existing `private var outputURL: URL?` (line 23), add:

```swift
    // Pause/resume: flags are flipped on `sampleQueue` so they serialize with
    // appends. While `paused`, all samples are dropped. `pendingResume` means a
    // resume was requested but the first post-resume video frame hasn't set the
    // new offset yet (audio is held back until it does — a ≤1-buffer seam nick).
    private var paused = false
    private var pendingResume = false
    private var lastVideoPTS: CMTime?
    private var frameDuration = CMTime(value: 1, timescale: 60)
    private var timeline = PauseTimeline()
```

- [ ] **Step 2: Initialize timing fields in `start(...)`**

In `start(...)`, immediately after `self.sessionStarted = false` (line 94), add:

```swift
        self.frameDuration = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        self.paused = false
        self.pendingResume = false
        self.lastVideoPTS = nil
        self.timeline = PauseTimeline()
```

- [ ] **Step 3: Add `pause()` / `resume()`**

After the `stop()` method (after line 134, before `private func reset()`), add:

```swift
    /// Pause: drop all samples until `resume()`. Serialized on the sample queue.
    public func pause() {
        sampleQueue.sync { paused = true }
    }

    /// Resume: the next video frame re-establishes the gap-free offset; samples
    /// flow again retimed by the accumulated pause offset.
    public func resume() {
        sampleQueue.sync { paused = false; pendingResume = true }
    }
```

- [ ] **Step 4: Reset pause state in `reset()`**

Replace the body of `reset()` (lines 136–140) with:

```swift
    private func reset() {
        stream = nil; writer = nil; videoInput = nil
        systemAudioInput = nil; micInput = nil; micCapturer = nil
        outputURL = nil; sessionStarted = false; sessionStartPTS = nil
        paused = false; pendingResume = false; lastVideoPTS = nil
        timeline = PauseTimeline()
    }
```

- [ ] **Step 5: Add the retiming helper**

After `reset()`, add:

```swift
    /// Append `sampleBuffer` retimed by the current pause offset. Subtracts the
    /// offset from every timing entry (handles multi-sample audio buffers). Fast
    /// path: with a zero offset (no pause yet) the original buffer is appended.
    private func appendRetimed(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput) {
        let offset = timeline.currentOffset
        if offset == .zero { input.append(sampleBuffer); return }
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0,
                                               arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { input.append(sampleBuffer); return }
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: count,
                                               arrayToFill: &timings, entriesNeededOut: &count)
        for i in 0..<count {
            if timings[i].presentationTimeStamp.isValid {
                timings[i].presentationTimeStamp = timings[i].presentationTimeStamp - offset
            }
            if timings[i].decodeTimeStamp.isValid {
                timings[i].decodeTimeStamp = timings[i].decodeTimeStamp - offset
            }
        }
        var out: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count, sampleTimingArray: &timings, sampleBufferOut: &out)
        if status == noErr, let out { input.append(out) } else { input.append(sampleBuffer) }
    }
```

- [ ] **Step 6: Rewrite the sample handler to respect pause + retiming**

Replace the `.screen` and `.audio` arms of `stream(_:didOutputSampleBuffer:of:)` (lines 148–166) with:

```swift
        case .screen:
            // Only complete frames carry image data.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                      sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: statusRaw) == .complete else { return }
            let pts = sampleBuffer.presentationTimeStamp
            if !sessionStarted {
                writer?.startSession(atSourceTime: pts)
                sessionStartPTS = pts
                sessionStarted = true
                lastVideoPTS = pts
            }
            if paused { return }
            if pendingResume {
                if let last = lastVideoPTS {
                    timeline.resume(lastPTSBeforePause: last, firstPTSAfterResume: pts,
                                    frameDuration: frameDuration)
                }
                pendingResume = false
            }
            if let videoInput, videoInput.isReadyForMoreMediaData {
                appendRetimed(sampleBuffer, to: videoInput)
            }
            lastVideoPTS = pts
        case .audio:
            guard sessionStarted, !paused, !pendingResume,
                  let systemAudioInput, systemAudioInput.isReadyForMoreMediaData else { return }
            appendRetimed(sampleBuffer, to: systemAudioInput)
```

- [ ] **Step 7: Apply the same pause/retiming to the mic path**

Replace `appendMic(_:)` (lines 172–177) with:

```swift
    private func appendMic(_ buffer: CMSampleBuffer) {
        guard sessionStarted, !paused, !pendingResume, let sessionStartPTS,
              buffer.presentationTimeStamp >= sessionStartPTS,
              let micInput, micInput.isReadyForMoreMediaData else { return }
        appendRetimed(buffer, to: micInput)
    }
```

- [ ] **Step 8: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds (also run `scripts/test.sh` to confirm all package suites still pass).

- [ ] **Step 9: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift
git commit -m "feat(recording): ScreenRecorder pause/resume with gap-free retiming"
```

- [ ] **Step 10: Manual probe (do before building further on this)**

After Task 5 wires pause/resume to a control, perform the spec's probe:
1. `scripts/build-app.sh`, copy `dist/BetterScreenshot.app` over `/Applications/BetterScreenshot.app`, relaunch.
2. Record full screen with **system audio on**, pause ~3 s mid-recording, resume, stop.
3. Open the file: `AVAsset.duration` ≈ recorded time (NOT wall-clock incl. the pause), and playback A/V stays in sync with no freeze/jump at the seam.

If the probe fails (duration wrong, desync, or `CMSampleBufferCreateCopyWithNewTiming` misbehaves with SCK buffers): fall back to recording a segment file per pause and stitching with `AVMutableComposition` at stop (same UX). Record the outcome in the Task 12 checklist either way.

---

## Task 5: Pause/Resume controls — coordinator + menu + hotkey (App)

Wires `pause()`/`resume()` into the recording lifecycle: a Pause/Resume menu item (visible only while recording/paused), the `pauseResumeRecording` hotkey, and the paused indicator in the menu-bar timer.

**Files:**
- Modify: `App/Recording/RecordingCoordinator.swift`
- Modify: `App/MenuBar/MenuBarController.swift`
- Modify: `App/Lifecycle/AppDelegate.swift`

**Interfaces:**
- Consumes: `RecorderState` pause events (Task 2), `ScreenRecorder.pause()/resume()` (Task 4), `HotkeyAction.pauseResumeRecording` (Task 1).
- Produces:
  - `RecordingCoordinator.pauseResume()`, `RecordingCoordinator.isPaused: Bool`, widened `isRecording`, `onPauseStateChange: ((_ active: Bool, _ paused: Bool) -> Void)?`.
  - `MenuBarController.onPauseResume: (() -> Void)?`, `MenuBarController.setPauseItem(active:paused:)`.

- [ ] **Step 1: Widen `isRecording` + add `isPaused` in the coordinator**

In `RecordingCoordinator.swift`, replace `isRecording` (line 46) with:

```swift
    /// True while a capture session exists (recording OR paused) — keeps the
    /// menu-bar stop icon + timer visible through a pause.
    var isRecording: Bool {
        switch state { case .recording, .paused: return true; default: return false }
    }
    var isPaused: Bool { if case .paused = state { return true }; return false }
```

- [ ] **Step 2: Add the pause callback property**

After `var onStateChange: ((Bool, String?) -> Void)?` (line 30), add:

```swift
    /// Drives the Pause/Resume menu item: (session active?, currently paused?).
    var onPauseStateChange: ((_ active: Bool, _ paused: Bool) -> Void)?
```

- [ ] **Step 3: Stop from `.paused` too**

In `toggle()` (lines 49–56), change the `.recording` arm to:

```swift
        case .recording, .paused: Task { await stop() }
```

- [ ] **Step 4: Implement `pauseResume()`**

Add after `toggle()` (after line 56):

```swift
    /// Pause/resume the running recording. No-op outside `.recording`/`.paused`.
    func pauseResume() {
        switch state {
        case .recording:
            guard state.transition(.pause(Date())) else { return }
            recorder.pause()
            notify()
        case .paused:
            guard state.transition(.resume(Date())) else { return }
            recorder.resume()
            notify()
        default:
            break
        }
    }
```

- [ ] **Step 5: Fire the pause callback from `notify()`**

Replace `notify()` (lines 267–269) with:

```swift
    private func notify() {
        onStateChange?(isRecording, state.elapsedString(now: Date()))
        onPauseStateChange?(isRecording, isPaused)
    }
```

- [ ] **Step 6: Add the Pause/Resume menu item**

In `MenuBarController.swift`, after `private var recordItem: NSMenuItem?` (line 20), add:

```swift
    private var pauseItem: NSMenuItem?
```

In `buildMenu()`, after the `recordItem` block (after line 36, `if let recordItem { actionItems[.record] = recordItem }`), add:

```swift
        let pause = menu.addItem(withTitle: "Pause Recording",
                                 action: #selector(togglePauseResume), keyEquivalent: "")
        pause.target = self
        pause.isHidden = true
        pauseItem = pause
        if let pauseItem { actionItems[.pauseResumeRecording] = pauseItem }
```

> `actionItems[.pauseResumeRecording] = pauseItem` lets `refreshKeyEquivalents` display the user's bound shortcut on the menu item automatically — no extra code needed.

- [ ] **Step 7: Add the menu callback + updater**

In `MenuBarController.swift`, after `var onRestoreRecentlyClosed: (() -> Void)?` (line 69), add:

```swift
    var onPauseResume: (() -> Void)?
```

After `@objc private func restoreClosed() { onRestoreRecentlyClosed?() }` (line 75), add:

```swift
    @objc private func togglePauseResume() { onPauseResume?() }

    /// Pause/Resume item: shown only while recording/paused; title flips on state.
    func setPauseItem(active: Bool, paused: Bool) {
        pauseItem?.isHidden = !active
        pauseItem?.title = paused ? "Resume Recording" : "Pause Recording"
    }
```

- [ ] **Step 8: Wire it in AppDelegate**

In `AppDelegate.swift`, after the `recordingCoordinator.onStateChange = { … }` block (lines 33–35), add:

```swift
        recordingCoordinator.onPauseStateChange = { [weak self] active, paused in
            self?.menuBar.setPauseItem(active: active, paused: paused)
        }
```

After `menuBar.onRestoreRecentlyClosed = { … }` (line 54), add:

```swift
        menuBar.onPauseResume = { [weak self] in self?.recordingCoordinator.pauseResume() }
```

In the `handlers` dictionary in `applyBindings()` (lines 80–89), add after the `.restoreRecentlyClosed` entry:

```swift
            .pauseResumeRecording:  { [weak self] in Task { @MainActor in self?.recordingCoordinator.pauseResume() } },
```

- [ ] **Step 9: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 10: Manual smoke + run the Task 4 probe**

`scripts/build-app.sh` → deploy to `/Applications` → relaunch. Start a recording: the menu shows "Pause Recording"; clicking it freezes the timer to "Paused · m:ss" and the item becomes "Resume Recording"; resume continues; ⌘⇧5 while paused stops. Now run the Task 4 Step 10 probe and confirm the output has no gap.

- [ ] **Step 11: Commit**

```bash
git add App/Recording/RecordingCoordinator.swift App/MenuBar/MenuBarController.swift App/Lifecycle/AppDelegate.swift
git commit -m "feat(recording): pause/resume controls (menu item + hotkey)"
```

---

## Task 6: Countdown setting — `RecordingConfig.countdownSeconds` + Settings picker (RecordingKit TDD + App)

Adds the persisted countdown preference (Off/3/5/10 s) and its Settings UI. No countdown behavior yet (Task 9 consumes it).

**Files:**
- Modify: `Packages/RecordingKit/Sources/RecordingKit/RecordingConfig.swift`
- Modify: `Packages/RecordingKit/Tests/RecordingKitTests/RecordingConfigTests.swift`
- Modify: `App/Settings/SettingsView.swift`

**Interfaces:**
- Produces: `RecordingConfig.countdownSeconds: Int` (0 = off; persisted, validated to `{0,3,5,10}`). Consumed by Task 9 (`begin`) and the Settings picker.

- [ ] **Step 1: Extend the round-trip test**

In `RecordingConfigTests.swift`, in the `"defaultsAndRoundTrip"` test, after `t.isFalse(d.keystrokeOverlay)` (line 15), add:

```swift
        t.equal(d.countdownSeconds, 0)   // off by default
```

And after the existing round-trip mutation line (line 17, `c.format = .gif; …`), add `c.countdownSeconds = 5` so the round-trip covers it:

```swift
        c.format = .gif; c.fps = 60; c.microphone = true; c.cameraSize = .medium; c.countdownSeconds = 5
```

After the malformed-fps assertion (line 21), add:

```swift
        // Countdown: unknown value falls back to 0 (off); valid values round-trip.
        t.equal(RecordingConfig(dictionary: ["countdownSeconds": "7"]).countdownSeconds, 0)
        t.equal(RecordingConfig(dictionary: ["countdownSeconds": "10"]).countdownSeconds, 10)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: compile error / FAIL — `countdownSeconds` is not a member of `RecordingConfig`.

- [ ] **Step 3: Add the field to `RecordingConfig`**

In `RecordingConfig.swift`:

(a) After `public var keystrokeOverlay: Bool` (line 30), add:

```swift
    public var countdownSeconds: Int     // 0 = off; otherwise 3 / 5 / 10
```

(b) Update `.default` (lines 35–38) to pass `countdownSeconds: 0`:

```swift
    public static let `default` = RecordingConfig(
        format: .mp4, fps: 30, systemAudio: true, microphone: false,
        camera: false, cameraSize: .small, clickHighlights: true,
        keystrokeOverlay: false, countdownSeconds: 0)
```

(c) Update the memberwise `init` (lines 40–51) to accept and assign it:

```swift
    public init(format: RecordingFormat, fps: Int, systemAudio: Bool, microphone: Bool,
                camera: Bool, cameraSize: CameraSize, clickHighlights: Bool,
                keystrokeOverlay: Bool, countdownSeconds: Int) {
        self.format = format
        self.fps = fps
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.camera = camera
        self.cameraSize = cameraSize
        self.clickHighlights = clickHighlights
        self.keystrokeOverlay = keystrokeOverlay
        self.countdownSeconds = countdownSeconds
    }
```

(d) In `dictionary` (lines 68–77), add the entry (after `keystrokeOverlay`):

```swift
         "keystrokeOverlay": keystrokeOverlay ? "true" : "false",
         "countdownSeconds": String(countdownSeconds)]
```

(e) In `init(dictionary:)` (lines 79–90), after the `keystrokeOverlay` line, add:

```swift
        let cd = Int(dictionary["countdownSeconds"] ?? "")
        self.countdownSeconds = (cd == 3 || cd == 5 || cd == 10) ? cd! : 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: PASS.

> The only memberwise `RecordingConfig(...)` call site is `.default` (verified via grep); `init(dictionary:)` doesn't use it. No other source needs changing for the type to compile.

- [ ] **Step 5: Add the Settings picker**

In `App/Settings/SettingsView.swift`, inside `RecordingTab`'s `Form` (after the "Show keystrokes" toggle + its caption `Text(...)`, around line 218), add:

```swift
              Picker("Countdown before recording", selection: bind(\.countdownSeconds)) {
                  Text("Off").tag(0)
                  Text("3 seconds").tag(3)
                  Text("5 seconds").tag(5)
                  Text("10 seconds").tag(10)
              }
```

> The existing `bind<V>(_ keyPath: WritableKeyPath<RecordingConfig, V>)` helper persists on change via `store.persist()`; `countdownSeconds: Int` works with `Int`-tagged picker rows.

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/RecordingConfig.swift \
        Packages/RecordingKit/Tests/RecordingKitTests/RecordingConfigTests.swift \
        App/Settings/SettingsView.swift
git commit -m "feat(recording): countdown setting (RecordingConfig + Settings)"
```

---

## Task 7: `CountdownOverlayController` (RecordingKit)

A centered HUD panel showing a large monospaced digit counting down once per second. Click to skip; cancellable. Replicates the `HUDController` dark-pill recipe (`NSVisualEffectView` `.hudWindow` + `.vibrantDark`) inline (RecordingKit can't import OverlayKit).

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/CountdownOverlayController.swift`

**Interfaces:**
- Produces: `@MainActor final class CountdownOverlayController` with `init()`, `func run(seconds: Int, on screen: NSScreen) async`, `func cancel()`. Consumed by Task 9 (`RecordingCoordinator`).

No automated test (AppKit panel) — verification is `swift build` + the Task 9 manual check.

- [ ] **Step 1: Implement the controller**

Create `Packages/RecordingKit/Sources/RecordingKit/CountdownOverlayController.swift`:

```swift
import AppKit

/// A centered countdown HUD shown before recording starts. Counts down once per
/// second; click to skip (start now); `cancel()` aborts. Uses the same dark-pill
/// recipe as OverlayKit's HUDController (replicated here — RecordingKit doesn't
/// depend on OverlayKit).
@MainActor
public final class CountdownOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var timer: Timer?
    private var remaining = 0
    private var continuation: CheckedContinuation<Void, Never>?

    public init() {}

    /// Shows the countdown centered on `screen`; returns when it finishes, is
    /// clicked (skip), or is cancelled. Always tears the overlay down first.
    public func run(seconds: Int, on screen: NSScreen) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            self.present(seconds: seconds, on: screen)
        }
    }

    /// Aborts an in-flight countdown (no-op otherwise), resolving `run()`.
    public func cancel() { finish() }

    private func present(seconds: Int, on screen: NSScreen) {
        let side: CGFloat = 200
        let origin = NSPoint(x: screen.frame.midX - side / 2, y: screen.frame.midY - side / 2)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: NSSize(width: side, height: side)),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = ClickView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        container.onClick = { [weak self] in self?.finish() }   // click to skip
        container.appearance = NSAppearance(named: .vibrantDark)
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 24
        container.layer?.masksToBounds = true

        let label = NSTextField(labelWithString: "\(seconds)")
        label.font = .monospacedDigitSystemFont(ofSize: 120, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = container.bounds
        label.autoresizingMask = [.width, .height]
        // Vertically center the baseline-ish: nudge using a cell that centers.
        label.cell?.lineBreakMode = .byClipping
        container.addSubview(label)

        panel.contentView = container
        panel.orderFrontRegardless()

        self.panel = panel
        self.label = label
        self.remaining = seconds
        self.timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 { finish(); return }
        label?.stringValue = "\(remaining)"
    }

    private func finish() {
        timer?.invalidate(); timer = nil
        panel?.orderOut(nil); panel = nil
        label = nil
        let cont = continuation; continuation = nil
        cont?.resume()
    }
}

/// A vibrancy view that reports clicks (skip the countdown).
private final class ClickView: NSVisualEffectView {
    var onClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) { onClick?() }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/CountdownOverlayController.swift
git commit -m "feat(recording): countdown overlay controller"
```

---

## Task 8: Route recording through `RecordingTarget` (App refactor, no behavior change)

Refactors `begin(globalRect:screen:)` into `begin(target:screen:)` with a private `RecordingTarget` enum covering display and window. The window arm is implemented but unused until Task 11. Full-screen and area recording behave exactly as before.

**Files:**
- Modify: `App/Recording/RecordingCoordinator.swift`

**Interfaces:**
- Produces: `private enum RecordingTarget { case display(globalRect: CGRect?); case window(CGWindowID) }` and `private func begin(target: RecordingTarget, screen: NSScreen) async`. Consumed by Task 9 (countdown hook) and Task 11 (window path).

- [ ] **Step 1: Add the `RecordingTarget` enum**

In `RecordingCoordinator.swift`, immediately above `private func begin(...)` (line 105), add:

```swift
    private enum RecordingTarget {
        case display(globalRect: CGRect?)   // nil = full screen
        case window(CGWindowID)
    }
```

- [ ] **Step 2: Replace `begin(globalRect:screen:)` with `begin(target:screen:)`**

Replace the entire `begin(globalRect:screen:)` method (lines 105–180) with:

```swift
    /// Start the engine for `target` on `screen`. Single path for full-screen,
    /// area, and window recording.
    private func begin(target: RecordingTarget, screen: NSScreen) async {
        // A ⌘⇧5 cancel can land while the selection overlay or permission prompts
        // were up — only proceed if we're still armed.
        guard case .armed = state else { return }
        var config = settings.recording
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            let scale = screen.backingScaleFactor
            let filter: SCContentFilter
            var sourceRect: CGRect?
            var pixelSize: CGSize
            let cameraAnchor: CGRect
            switch target {
            case .display(let globalRect):
                guard let displayID = screen.deviceDescription[
                        NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                      let display = content.displays.first(where: { $0.displayID == displayID })
                else { throw RecorderError.writerFailed }
                pixelSize = CGSize(width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
                if let globalRect {
                    // sourceRect: display-relative, top-left origin, points.
                    let local = CaptureGeometry.pixelRect(forGlobalRect: globalRect,
                                                          inDisplayFrame: screen.frame, scale: 1)
                    sourceRect = local
                    pixelSize = CGSize(width: local.width * scale, height: local.height * scale)
                }
                filter = SCContentFilter(display: display, excludingWindows: [])
                cameraAnchor = globalRect ?? screen.frame
            case .window(let windowID):
                guard let window = content.windows.first(where: { $0.windowID == windowID })
                else { throw RecorderError.writerFailed }
                pixelSize = CGSize(width: window.frame.width * scale,
                                   height: window.frame.height * scale)
                filter = SCContentFilter(desktopIndependentWindow: window)
                cameraAnchor = screen.frame   // camera bubble is screen-level (v1)
            }

            // Even pixel dimensions keep H.264 encoders happy.
            pixelSize.width = (pixelSize.width / 2).rounded(.down) * 2
            pixelSize.height = (pixelSize.height / 2).rounded(.down) * 2

            if config.microphone, await MicCapturer.ensurePermission() == false {
                config.microphone = false
                hud.show("Mic access denied — recording without microphone", on: screen)
            }
            if config.camera, await CameraBubbleController.ensurePermission() {
                bubble.show(near: cameraAnchor, on: screen, diameter: config.cameraSize.diameter)
            }
            if config.clickHighlights { clicks.start(on: screen) }
            if config.keystrokeOverlay { keystrokes.start(on: screen) }

            // (Task 9 inserts the countdown step here.)

            let ext = "mp4"   // GIF converts after the fact
            let name = FileNamer.fileName(for: Date(), ext: ext, prefix: "Recording")
            let url = config.format == .gif
                ? FileManager.default.temporaryDirectory.appendingPathComponent(name)
                : settings.saveDirectory.appendingPathComponent(name)
            tempOutputURL = config.format == .gif ? url : nil

            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: settings.saveDirectory,
                                                    withIntermediateDirectories: true)
            try await recorder.start(filter: filter, pixelSize: pixelSize,
                                     sourceRect: sourceRect, config: config, outputURL: url)
            guard state.transition(.begin(Date())) else {
                // Cancelled (⌘⇧5) during engine startup: stop and discard.
                _ = try? await recorder.stop()
                try? FileManager.default.removeItem(at: url)
                tearDownPanels()
                notify()
                return
            }
            startTimer()
            notify()
        } catch {
            tearDownPanels()
            state.transition(.reset)
            hud.show("Couldn't start recording", on: screen)
            notify()
        }
    }
```

> Behavior note: the only change for existing paths is that an (effectively impossible) missing-`displayID` now flows through the same `catch` → "Couldn't start recording" HUD as display-not-found, instead of a silent reset. Acceptable per the "no error handling for impossible scenarios" guideline.

- [ ] **Step 3: Update the two call sites**

In `beginFullScreen()` (lines 77–81), change the `Task` line to:

```swift
        Task { await begin(target: .display(globalRect: nil), screen: screen) }
```

In `beginAreaSelection()`'s completion (line 96), change:

```swift
                await self.begin(target: .display(globalRect: result.globalRect), screen: screen)
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Manual smoke (no behavior change)**

`scripts/build-app.sh` → deploy → relaunch. Confirm full-screen and area recording still start, record, stop, and save exactly as before.

- [ ] **Step 6: Commit**

```bash
git add App/Recording/RecordingCoordinator.swift
git commit -m "refactor(recording): route begin through RecordingTarget"
```

---

## Task 9: Countdown before recording (App)

Hooks the countdown overlay into `begin`, between panel setup and engine start, for all targets. Cancellable via ⌘⇧5 (which routes through `cancelStrip()` while `.armed`).

**Files:**
- Modify: `App/Recording/RecordingCoordinator.swift`

**Interfaces:**
- Consumes: `CountdownOverlayController` (Task 7), `RecordingConfig.countdownSeconds` (Task 6), `begin(target:)` (Task 8).

- [ ] **Step 1: Add the countdown controller property**

In `RecordingCoordinator.swift`, after `private let keystrokes = KeystrokeOverlayController()` (line 17), add:

```swift
    private let countdown = CountdownOverlayController()
```

- [ ] **Step 2: Cancel the countdown on strip-cancel**

In `cancelStrip()` (lines 70–75), add `countdown.cancel()` after `selection.cancel()`:

```swift
    private func cancelStrip() {
        // ⌘⇧5 while the area-selection overlay / countdown is up: tear it down too.
        selection.cancel()
        countdown.cancel()
        strip.hide()
        state.transition(.reset)
    }
```

- [ ] **Step 3: Insert the countdown step in `begin`**

In `begin(target:screen:)`, replace the placeholder comment line `// (Task 9 inserts the countdown step here.)` with:

```swift
            if config.countdownSeconds > 0 {
                await countdown.run(seconds: config.countdownSeconds, on: screen)
                // ⌘⇧5 during the countdown cancels (cancelStrip → reset). If we're
                // no longer armed, tear the panels back down and bail.
                guard case .armed = state else { tearDownPanels(); notify(); return }
            }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds.

- [ ] **Step 5: Manual check**

`scripts/build-app.sh` → deploy → relaunch. In Settings → Recording set Countdown = 3 s. Then: full-screen record shows a centered 3→2→1 countdown before capture; click the countdown to skip (starts immediately); ⌘⇧5 during the countdown cancels with no recording and no leftover camera/keystroke panels. Repeat with an area selection and confirm the countdown appears on the selected screen.

- [ ] **Step 6: Commit**

```bash
git add App/Recording/RecordingCoordinator.swift
git commit -m "feat(recording): countdown before recording"
```

---

## Task 10: `WindowPicking` hit-test + frame conversion (CaptureKit, TDD)

Pure logic for picking the front-most normal window under a point and converting `CGWindowList` top-left-origin bounds to Cocoa bottom-left coordinates.

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/WindowPicking.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/WindowPickingTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

**Interfaces:**
- Produces:
  - `struct PickableWindow: Equatable { let id: UInt32; let frame: CGRect; let title: String?; let layer: Int; let ownerPID: pid_t; init(...) }`
  - `enum WindowPicking { static func topmost(at: CGPoint, windows: [PickableWindow], excludingPID: pid_t) -> PickableWindow?; static func cocoaFrame(fromTopLeft: CGRect, primaryHeight: CGFloat) -> CGRect }`
  - Consumed by Task 11 (`RecordingCoordinator.beginWindowSelection`).

- [ ] **Step 1: Write the failing tests**

Create `Packages/CaptureKit/Tests/CaptureKitTests/WindowPickingTests.swift`:

```swift
import TestKit
import CoreGraphics
@testable import CaptureKit

private func win(_ id: UInt32, _ frame: CGRect, layer: Int = 0, pid: pid_t = 10,
                 title: String? = nil) -> PickableWindow {
    PickableWindow(id: id, frame: frame, title: title, layer: layer, ownerPID: pid)
}

let windowPickingTests: [TestCase] = [
    TestCase("topmostReturnsFrontOnOverlap") { t in
        // Front-to-back ordered: smaller front window wins over the larger one behind.
        let front = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 10)
        let back  = win(2, CGRect(x: 0, y: 0, width: 200, height: 200), pid: 11)
        t.equal(WindowPicking.topmost(at: CGPoint(x: 50, y: 50),
                                      windows: [front, back], excludingPID: 99)?.id, 1)
    },
    TestCase("skipsNonNormalLayer") { t in
        let menu = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), layer: 25)   // e.g. menu/dock
        let app  = win(2, CGRect(x: 0, y: 0, width: 100, height: 100), layer: 0, pid: 11, title: "W")
        t.equal(WindowPicking.topmost(at: CGPoint(x: 10, y: 10),
                                      windows: [menu, app], excludingPID: 99)?.id, 2)
    },
    TestCase("excludesOwnPID") { t in
        let own   = win(1, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 42, title: "self")
        let other = win(2, CGRect(x: 0, y: 0, width: 100, height: 100), pid: 7, title: "other")
        t.equal(WindowPicking.topmost(at: CGPoint(x: 10, y: 10),
                                      windows: [own, other], excludingPID: 42)?.id, 2)
    },
    TestCase("missReturnsNil") { t in
        let w = win(1, CGRect(x: 0, y: 0, width: 10, height: 10))
        t.isNil(WindowPicking.topmost(at: CGPoint(x: 500, y: 500),
                                      windows: [w], excludingPID: 99))
    },
    TestCase("cocoaFrameConversion") { t in
        // Primary display 900 tall; window top-left at y=100, height 200 → cocoa y = 900-100-200 = 600.
        let cocoa = WindowPicking.cocoaFrame(
            fromTopLeft: CGRect(x: 50, y: 100, width: 300, height: 200), primaryHeight: 900)
        t.equal(cocoa, CGRect(x: 50, y: 600, width: 300, height: 200))
    },
]
```

- [ ] **Step 2: Register the suite**

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, append `+ windowPickingTests` to the `runTests(...)` concatenation.

- [ ] **Step 3: Run test to verify it fails**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error / FAIL — `WindowPicking` / `PickableWindow` undefined.

- [ ] **Step 4: Implement `WindowPicking`**

Create `Packages/CaptureKit/Sources/CaptureKit/WindowPicking.swift`:

```swift
import Foundation
import CoreGraphics

/// One on-screen window for hit-testing. `frame` is in Cocoa bottom-left global
/// coordinates (convert from CGWindowList bounds via `WindowPicking.cocoaFrame`).
public struct PickableWindow: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let title: String?
    public let layer: Int
    public let ownerPID: pid_t

    public init(id: UInt32, frame: CGRect, title: String?, layer: Int, ownerPID: pid_t) {
        self.id = id
        self.frame = frame
        self.title = title
        self.layer = layer
        self.ownerPID = ownerPID
    }
}

public enum WindowPicking {
    /// `windows` must be **front-to-back ordered** (caller's contract, e.g. from
    /// `CGWindowListCopyWindowInfo(.optionOnScreenOnly, ...)`). Returns the
    /// front-most normal window (layer 0), not owned by `excludingPID`, whose
    /// frame contains `point`. nil on a miss.
    public static func topmost(at point: CGPoint, windows: [PickableWindow],
                               excludingPID: pid_t) -> PickableWindow? {
        for w in windows where w.layer == 0 && w.ownerPID != excludingPID {
            if w.frame.contains(point) { return w }
        }
        return nil
    }

    /// Convert a top-left-origin global rect (CGWindowList bounds) to Cocoa
    /// bottom-left global coordinates, given the primary display's height.
    public static func cocoaFrame(fromTopLeft frame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryHeight - frame.minY - frame.height,
               width: frame.width, height: frame.height)
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: PASS — `windowPickingTests` all green.

- [ ] **Step 6: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/WindowPicking.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/WindowPickingTests.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/main.swift
git commit -m "feat(capture): WindowPicking hit-test + frame conversion"
```

---

## Task 11: Record a single window (OverlayKit picker + strip button + App path)

Adds the hover-to-pick window overlay, the "Record Window…" strip button, and the `beginWindowSelection()` path that builds the window list, presents the picker, resolves the pick, and records via `begin(target: .window(id))`.

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/WindowPickerController.swift`
- Modify: `App/Recording/RecordStripController.swift`
- Modify: `App/Recording/RecordingCoordinator.swift`

**Interfaces:**
- Consumes: `WindowPicking` + `PickableWindow` (Task 10), `begin(target:)` (Task 8), the `KeyableOverlayWindow` type (internal to OverlayKit, in `SelectionOverlayController.swift`).
- Produces:
  - `WindowPickerController` with `init()`, `present(hitTest:onPicked:)`, `cancel()`:
    - `hitTest: (CGPoint) -> (id: UInt32, frame: CGRect, title: String?)?` (global Cocoa point in → hovered window id + global Cocoa frame + title out).
    - `onPicked: (UInt32?) -> Void` (nil = cancelled).
  - `RecordStripController.onWindow: (() -> Void)?`.

- [ ] **Step 1: Implement `WindowPickerController`**

Create `Packages/OverlayKit/Sources/OverlayKit/WindowPickerController.swift`:

```swift
import AppKit

/// A full-screen overlay (per display) that highlights the window under the
/// cursor and confirms a pick on click. Generic: it knows nothing about
/// CaptureKit — the caller injects a hit-test closure (global Cocoa point in →
/// hovered window id + global Cocoa frame + title out) and a pick handler.
/// Mirrors SelectionOverlayController's per-screen overlay + Esc handling and
/// QuickAccessStackController's injected-closure pattern.
public final class WindowPickerController {
    public typealias HitTest = (CGPoint) -> (id: UInt32, frame: CGRect, title: String?)?

    private var windows: [NSWindow] = []
    private var hitTest: HitTest?
    private var onPicked: ((UInt32?) -> Void)?

    public init() {}

    /// Present the picker on all screens. `onPicked(nil)` means cancelled (Esc /
    /// click on no window).
    public func present(hitTest: @escaping HitTest, onPicked: @escaping (UInt32?) -> Void) {
        if self.onPicked != nil { tearDown(); self.onPicked = nil; self.hitTest = nil } // re-entry guard
        self.hitTest = hitTest
        self.onPicked = onPicked
        for screen in NSScreen.screens {
            let view = WindowPickerView(frame: screen.frame, screenOrigin: screen.frame.origin)
            view.hitTest = hitTest
            view.onPick = { [weak self] id in self?.finish(id: id) }
            view.onCancel = { [weak self] in self?.finish(id: nil) }
            let window = KeyableOverlayWindow(contentRect: screen.frame, styleMask: .borderless,
                                              backing: .buffered, defer: false, screen: screen)
            window.level = .screenSaver
            window.backgroundColor = .clear
            window.isOpaque = false
            window.ignoresMouseEvents = false
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)   // borderless: needed to receive Escape
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Dismiss an in-flight picker without firing `onPicked` (the caller's cancel
    /// path already handles state). No-op when nothing is presented.
    public func cancel() {
        guard onPicked != nil else { return }
        onPicked = nil
        hitTest = nil
        tearDown()
    }

    private func finish(id: UInt32?) {
        guard let cb = onPicked else { return }
        onPicked = nil
        hitTest = nil
        tearDown()
        cb(id)
    }

    private func tearDown() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

/// Draws the dim + hovered-window highlight for one screen.
private final class WindowPickerView: NSView {
    var hitTest: WindowPickerController.HitTest?
    var onPick: ((UInt32?) -> Void)?
    var onCancel: (() -> Void)?

    private let screenOrigin: CGPoint
    private var current: (id: UInt32, frame: CGRect, title: String?)?

    init(frame: NSRect, screenOrigin: CGPoint) {
        self.screenOrigin = screenOrigin
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited],
            owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        let hovered = hitTest?(NSEvent.mouseLocation) ?? nil
        if hovered?.id != current?.id { current = hovered; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        if current != nil { current = nil; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) { onPick?(current?.id) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }   // Escape
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.15).setFill()
        bounds.fill()
        guard let current else { return }
        // Global Cocoa frame → this screen's view-local coordinates.
        let local = CGRect(x: current.frame.minX - screenOrigin.x,
                           y: current.frame.minY - screenOrigin.y,
                           width: current.frame.width, height: current.frame.height)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        local.fill()
        NSColor.controlAccentColor.setStroke()
        let stroke = NSBezierPath(rect: local); stroke.lineWidth = 3; stroke.stroke()

        guard let title = current.title, !title.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)]
        let size = (title as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        let cap = CGRect(x: local.midX - size.width / 2 - pad,
                         y: local.midY - size.height / 2 - pad,
                         width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: cap, xRadius: 6, yRadius: 6).fill()
        (title as NSString).draw(at: CGPoint(x: local.midX - size.width / 2,
                                             y: local.midY - size.height / 2), withAttributes: attrs)
    }
}
```

- [ ] **Step 2: Build OverlayKit to verify it compiles**

Run: `swift build` (or `swift run --package-path Packages/OverlayKit OverlayKitTests` to also re-run its suite)
Expected: build succeeds.

- [ ] **Step 3: Add the "Record Window…" strip button**

In `App/Recording/RecordStripController.swift`:

(a) After `var onArea: (() -> Void)?` (line 12), add:

```swift
    var onWindow: (() -> Void)?
```

(b) After the `area` button setup (line 30), add:

```swift
        let windowBtn = NSButton(title: "Record Window…", target: self,
                                 action: #selector(windowSelect))
        windowBtn.bezelStyle = .rounded
```

(c) In the arranged-subviews array (line 62), insert `windowBtn` between `full` and `area`:

```swift
        for v in [full, windowBtn, area, format, mic, sys, cam, cancel] { strip.addArrangedSubview(v) }
```

(d) After `@objc private func areaSelect() { onArea?() }` (line 88), add:

```swift
    @objc private func windowSelect() { onWindow?() }
```

- [ ] **Step 4: Add the picker controller + wiring in the coordinator**

In `App/Recording/RecordingCoordinator.swift`:

(a) After `private let countdown = CountdownOverlayController()` (added in Task 9), add:

```swift
    private let windowPicker = WindowPickerController()
```

(b) In `init`, after `strip.onArea = { [weak self] in self?.beginAreaSelection() }` (line 39), add:

```swift
        strip.onWindow = { [weak self] in self?.beginWindowSelection() }
```

(c) In `cancelStrip()`, after `countdown.cancel()`, add:

```swift
        windowPicker.cancel()
```

- [ ] **Step 5: Implement `beginWindowSelection()`**

In `RecordingCoordinator.swift`, add after `beginAreaSelection()` (after line 99):

```swift
    private func beginWindowSelection() {
        strip.hide()
        // CGWindowList bounds are top-left global; convert with the primary
        // display height (the screen whose origin is (0,0)).
        let primaryHeight = (NSScreen.screens.first { $0.frame.origin == .zero }
                             ?? NSScreen.main)?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let windows: [PickableWindow] = info.compactMap { dict in
            guard let id = dict[kCGWindowNumber as String] as? UInt32,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  let pidInt = dict[kCGWindowOwnerPID as String] as? Int,
                  let boundsValue = dict[kCGWindowBounds as String],
                  let bounds = CGRect(dictionaryRepresentation: boundsValue as! CFDictionary)
            else { return nil }
            let title = dict[kCGWindowName as String] as? String
            return PickableWindow(id: id,
                                  frame: WindowPicking.cocoaFrame(fromTopLeft: bounds,
                                                                  primaryHeight: primaryHeight),
                                  title: title, layer: layer, ownerPID: pid_t(pidInt))
        }
        windowPicker.present(hitTest: { point in
            guard let w = WindowPicking.topmost(at: point, windows: windows,
                                                excludingPID: ownPID) else { return nil }
            return (id: w.id, frame: w.frame, title: w.title)
        }, onPicked: { [weak self] id in
            guard let self else { return }
            guard let id, let picked = windows.first(where: { $0.id == id }) else {
                self.state.transition(.reset); self.notify(); return
            }
            let center = CGPoint(x: picked.frame.midX, y: picked.frame.midY)
            let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
            guard let screen else { self.state.transition(.reset); self.notify(); return }
            Task { await self.begin(target: .window(id), screen: screen) }
        })
    }
```

- [ ] **Step 6: Build to verify it compiles**

Run: `swift build`
Expected: build succeeds. Then run all suites: `scripts/test.sh` (expected: all pass).

- [ ] **Step 7: Manual check**

`scripts/build-app.sh` → deploy → relaunch. Press ⌘⇧5 → click "Record Window…": moving the mouse highlights the window under the cursor (accent outline + title). Confirm BetterScreenshot's own strip/overlays are never highlightable. Click a window (e.g. Safari) → it records at the window's size; move the window mid-recording (capture follows it); close it mid-recording (the partial file is finalized and saved). Esc and ⌘⇧5 during picking cancel cleanly.

- [ ] **Step 8: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/WindowPickerController.swift \
        App/Recording/RecordStripController.swift App/Recording/RecordingCoordinator.swift
git commit -m "feat(recording): record a single window"
```

---

## Task 12: Release — manual checklist, docs, version bump, tag (owner-gated)

Final verification + release prep. **The actual tag and any GitHub release are outward-facing — confirm with the owner before pushing/tagging.** Also confirm whether v2.4.0 folds in the already-merged-but-untagged "Sticky annotation defaults + Stack button" work currently sitting under CHANGELOG "Unreleased".

**Files:**
- Modify: `CHANGELOG.md`, `README.md`, `App/Info.plist`

- [ ] **Step 1: Run the full automated suite**

Run: `scripts/test.sh`
Expected: "All suites passed."

- [ ] **Step 2: Build the app bundle**

Run: `scripts/build-app.sh`
Expected: `dist/BetterScreenshot.app` is assembled and signed without error.

- [ ] **Step 3: Work the manual GUI checklist** (from the spec's Testing section)

Deploy `dist/BetterScreenshot.app` to `/Applications`, relaunch, and verify:
- Countdown 3 s on each target (full / area / window); click-to-skip; ⌘⇧5 cancels during countdown.
- Window record of Safari, including moving the window mid-recording (capture follows) and closing it (partial file saved).
- Pause ~5 s mid-recording → output has **no gap** and A/V stays in sync (mic + system audio); timer freezes and shows "Paused".
- Pause hotkey works after binding `Pause/Resume Recording` in Settings → Shortcuts.
- GIF recording with a pause.
- Quit while paused → recording finalizes.
- Record the Task 4 PTS-retiming probe outcome (pass, or fell back to AVMutableComposition stitching).

- [ ] **Step 4: Update `CHANGELOG.md`**

Add the recording-controls entries under the appropriate version heading. **Decision for the owner:** either fold these into the existing "Unreleased" block alongside the editor-defaults work and release both as 2.4.0, or split the editor-defaults release out first. Draft entry:

```markdown
### Added
- **Countdown before recording.** Optional 3 / 5 / 10-second on-screen
  countdown before a recording starts (Settings → Recording). Click the
  countdown to start immediately; ⌘⇧5 cancels.
- **Record Window.** A new "Record Window…" button on the record strip:
  hover to highlight any window, click to record just that window.
- **Pause / Resume.** Pause a running recording and resume with no gap in the
  saved file. Available from the menu bar and as a bindable shortcut
  (Settings → Shortcuts → "Pause/Resume Recording"); the menu-bar timer
  freezes and shows "Paused" while paused.
```

- [ ] **Step 5: Update `README.md`**

Add countdown / window-record / pause-resume to the recording feature list (match the existing README's recording bullet style).

- [ ] **Step 6: Bump the version**

In `App/Info.plist`, set `CFBundleShortVersionString` to `2.4.0` (and bump `CFBundleVersion` per the existing convention). Rebuild with `scripts/build-app.sh` and confirm the About/version reflects 2.4.0.

- [ ] **Step 7: Commit**

```bash
git add CHANGELOG.md README.md App/Info.plist
git commit -m "chore(release): v2.4 recording controls"
```

- [ ] **Step 8: Tag (owner-gated)**

After the owner confirms the release scope, tag:

```bash
git tag v2.4-recording-controls
```

Do not push the tag or publish a GitHub release without explicit owner approval (outward-facing).

---

## Self-Review

**Spec coverage:**
- Countdown (setting, overlay, click-skip, ⌘⇧5 cancel, all targets) → Tasks 6, 7, 9. ✅
- Record Window (strip button, hover-highlight picker, own-window exclusion, `desktopIndependentWindow` filter, window pixel size, mid-recording move/close) → Tasks 8, 10, 11. ✅
- Pause/Resume (state, gap-free retiming, menu item + hotkey, frozen "Paused" timer, ⌘⇧5/quit while paused) → Tasks 1, 2, 3, 4, 5. ✅
- CaptureKit pure: `HotkeyAction` case, `WindowPicking.topmost`, top-left↔Cocoa conversion → Tasks 1, 10. ✅
- RecordingKit pure: `RecorderState` pause math, `PauseTimeline`, `RecordingConfig.countdownSeconds` → Tasks 2, 3, 6. ✅
- OverlayKit: generic `WindowPickerController` with injected hit-test closure → Task 11. ✅
- Build order matches the spec (state → timeline → recorder → wiring → countdown → window). ✅
- Error handling (window vanished → "Couldn't start recording"; wrong-state pause/resume no-ops; countdown cancel; window-closes-mid-recording via existing `streamFailed`) → Tasks 5, 8, 9. ✅
- Risks/probe (PTS retiming probed early with documented fallback; own-window exclusion; `desktopIndependentWindow` occlusion) → Tasks 4, 11. ✅

**Type consistency:** `RecorderState.recording(started:accumulatedPause:)` / `.paused(started:accumulatedPause:since:)` and events `.pause(Date)`/`.resume(Date)` are used identically across Tasks 2 and 5. `PauseTimeline.resume(lastPTSBeforePause:firstPTSAfterResume:frameDuration:)` / `adjusted(_:)` / `currentOffset` match across Tasks 3 and 4. `WindowPicking.topmost(at:windows:excludingPID:)` / `cocoaFrame(fromTopLeft:primaryHeight:)` and `PickableWindow(id:frame:title:layer:ownerPID:)` match across Tasks 10 and 11. `begin(target:screen:)` + `RecordingTarget` match across Tasks 8, 9, 11. `RecordingConfig.countdownSeconds` matches across Tasks 6 and 9. `onPauseStateChange: (Bool, Bool)` / `setPauseItem(active:paused:)` match across Task 5. ✅

**Placeholders:** none — every code step shows complete code; every run step gives a command + expected result.
