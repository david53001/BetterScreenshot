# P2 Screen Recording Suite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Screen recording with MP4 + GIF output, mic + system audio, webcam bubble, click/keystroke visualization, driven by a smart ⌘⇧5 start/stop toggle.

**Architecture:** New `RecordingKit` package: pure models (`RecorderState`, `RecordingConfig`, `GIFTiming`) with TestKit coverage + AV plumbing (`ScreenRecorder` on SCStream/AVAssetWriter, `MicCapturer`, `GIFExporter`) + visualization panels (camera bubble, click highlighter, keystroke pill). App adds `RecordingCoordinator` + record strip + menu-bar recording state. `HotkeyAction` gains `record` (default ⌘⇧5) with an `"unbound"`-sentinel persistence migration.

**Tech Stack:** Swift 5.9 SwiftPM (CLT-only — **no xcodebuild/XCTest**; TestKit executable runners), ScreenCaptureKit, AVFoundation, Carbon hotkeys. Min macOS 14.

**Spec:** `docs/superpowers/specs/2026-06-04-betterscreenshot-p2-recording-design.md`

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift` | modify | `record` case, default ⌘⇧5 |
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyBindings.swift` | modify | `"unbound"` sentinel persistence |
| `Packages/CaptureKit/Sources/CaptureKit/FileNamer.swift` | modify | `prefix` parameter |
| `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift` | modify | new cases |
| `Packages/CaptureKit/Tests/CaptureKitTests/FileNamerTests.swift` | modify | prefix case |
| `Packages/RecordingKit/*` | create | the whole recording package |
| `App/RecordingCoordinator.swift` | create | orchestration |
| `App/RecordStripController.swift` | create | the record strip panel |
| `App/AppDelegate.swift` | modify | record handler, terminate hook |
| `App/MenuBarController.swift` | modify | record items, icon+timer state |
| `App/SettingsStore.swift` | modify | `recording: RecordingConfig` |
| `App/SettingsView.swift` | modify | Recording tab; drop reserved caption |
| `App/SystemScreenshotShortcuts.swift` | modify | ids 30 + 184 |
| `App/Info.plist` | modify | mic/camera usage strings |

---

### Task 1: CaptureKit groundwork — `record` action, sentinel persistence, FileNamer prefix (TDD)

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift`
- Modify: `Packages/CaptureKit/Sources/CaptureKit/HotkeyBindings.swift`
- Modify: `Packages/CaptureKit/Sources/CaptureKit/FileNamer.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/FileNamerTests.swift` (read it first; append one TestCase to its array)

- [ ] **Step 1: Failing tests.** In `HotkeyTests.swift` append to the END of the `hotkeyBindingsTests` array (inside the `]`):

```swift
    TestCase("recordActionDefaults") { t in
        t.equal(HotkeyAction.record.title, "Start/Stop Recording")
        t.equal(HotkeyAction.record.defaultCombo, HotkeyCombo(keyCode: 23, modifiers: cmdShift)) // ⌘⇧5
        t.equal(HotkeyBindings.defaults.combo(for: .record),
                HotkeyCombo(keyCode: 23, modifiers: cmdShift))
        // record comes last in allCases (menu/settings row order).
        t.equal(HotkeyAction.allCases.last, .record)
    },
    TestCase("unboundSentinelPersistence") { t in
        // Explicit clear persists as "unbound" so it survives upgrades…
        var b = HotkeyBindings.defaults
        b.clear(.captureArea)
        t.equal(b.dictionary["captureArea"], "unbound")
        let restored = HotkeyBindings(dictionary: b.dictionary)
        t.isNil(restored.combo(for: .captureArea))
        t.equal(restored, b)
        // …while a MISSING key means "never customized → use the default".
        // A v1.4 dict (no "record" key) picks up ⌘⇧5 automatically.
        let v14 = HotkeyBindings(dictionary: ["captureArea": "21,768", "captureWindow": "28,768",
                                              "captureFullscreen": "22,768", "captureText": "26,768"])
        t.equal(v14.combo(for: .record), HotkeyCombo(keyCode: 23, modifiers: cmdShift))
        t.equal(v14.combo(for: .captureArea), HotkeyCombo(keyCode: 21, modifiers: 768))
    },
```

In `FileNamerTests.swift` append to its `[TestCase]` array:

```swift
    TestCase("recordingPrefix") { t in
        let date = Date(timeIntervalSince1970: 0)
        let name = FileNamer.fileName(for: date, ext: "mp4", prefix: "Recording",
                                      timeZone: TimeZone(identifier: "UTC")!)
        t.equal(name, "Recording 1970-01-01 at 00.00.00.mp4")
        // Default prefix unchanged.
        t.equal(FileNamer.fileName(for: date, ext: "png",
                                   timeZone: TimeZone(identifier: "UTC")!),
                "Screenshot 1970-01-01 at 00.00.00.png")
    },
```

- [ ] **Step 2: Run to verify failure.** `swift run --package-path Packages/CaptureKit CaptureKitTests` → build error (`record` case missing / `prefix` label missing).

- [ ] **Step 3: Implement.**

`HotkeyAction.swift` — add `record` to the case list (LAST), and extend `title`/`defaultCombo`:

```swift
    case captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard, record
```

```swift
        case .record: return "Start/Stop Recording"
```

```swift
        case .record:            return HotkeyCombo(keyCode: 23, modifiers: cmdShift) // ⌘⇧5
```

Also update the defaults doc comment: replace the "⌘⇧5 (keyCode 23) is intentionally unassigned — reserved…" sentence with "· ⌘⇧5 record."

`HotkeyBindings.swift` — sentinel persistence. The struct must now remember explicit clears. Replace the `map` storage semantics: add a `cleared: Set<HotkeyAction>` alongside `map`, maintained by `clear`/`set`, serialized as `"unbound"`:

```swift
public struct HotkeyBindings: Equatable {
    private var map: [HotkeyAction: HotkeyCombo]
    /// Actions the user explicitly unbound (persisted as "unbound" so the choice
    /// survives upgrades; a key missing entirely means "use the default").
    private var cleared: Set<HotkeyAction>

    public init(_ map: [HotkeyAction: HotkeyCombo] = [:]) {
        self.map = map
        self.cleared = []
    }
```

`set` removes from `cleared`; `clear` removes from `map` and inserts into `cleared`:

```swift
    public mutating func set(_ combo: HotkeyCombo, for action: HotkeyAction) {
        map[action] = combo
        cleared.remove(action)
    }

    public mutating func clear(_ action: HotkeyAction) {
        map[action] = nil
        cleared.insert(action)
    }
```

`dictionary` writes the sentinel; `init(dictionary:)` reads it, and **backfills defaults for actions with no key at all**:

```swift
    public var dictionary: [String: String] {
        var d: [String: String] = [:]
        for (action, combo) in map {
            d[action.rawValue] = "\(combo.keyCode),\(combo.modifiers)"
        }
        for action in cleared { d[action.rawValue] = "unbound" }
        return d
    }

    public init(dictionary: [String: String]) {
        var m: [HotkeyAction: HotkeyCombo] = [:]
        var c: Set<HotkeyAction> = []
        for (key, value) in dictionary {
            guard let action = HotkeyAction(rawValue: key) else { continue }
            if value == "unbound" { c.insert(action); continue }
            let parts = value.split(separator: ",")
            guard parts.count == 2,
                  let kc = UInt32(parts[0]), let mods = UInt32(parts[1]) else { continue }
            m[action] = HotkeyCombo(keyCode: kc, modifiers: mods)
        }
        // Actions absent from the stored dict were never customized → defaults.
        // (This is how pre-record-era bindings pick up ⌘⇧5 on upgrade.)
        for action in HotkeyAction.allCases where m[action] == nil && !c.contains(action) {
            m[action] = action.defaultCombo
        }
        self.map = m
        self.cleared = c
    }
```

NOTE: `.defaults` (built via `init(_:)` from `defaultCombo`) has `cleared = []` — `pinFromClipboard` simply has no map entry and no sentinel, which round-trips correctly because `init(dictionary:)` backfills it with `defaultCombo` (nil → stays absent). Verify the existing `bindingsDictionaryRoundTrip` test still passes: it clears `captureFullscreen` (now sentinel-persisted — round-trips), sets pin, and feeds a messy dict (`"captureArea": "garbage"` → skipped → **backfilled with the default now**, so the old assertion `t.isNil(messy.combo(for: .captureArea))` becomes WRONG). **Update that assertion** in the old test to:

```swift
        t.equal(messy.combo(for: .captureArea), HotkeyCombo(keyCode: 21, modifiers: 768)) // garbage → default
```

**Existing tests that the `record` case breaks — update them in the same step:**

- `defaultsTable`: the "nothing may default to ⌘⇧5" loop is now wrong (record DOES).
  Change the loop line to skip record:

```swift
        for action in HotkeyAction.allCases where action != .record {
```

  and add directly after the loop:

```swift
        t.equal(b.combo(for: .record), HotkeyCombo(keyCode: 23, modifiers: cmdShift))
```

- `setClearAndBoundOrder`: `bound` now ends with record. Change the expected array to:

```swift
        t.equal(b.bound.map(\.action), [.captureWindow, .captureFullscreen, .captureText, .pinFromClipboard, .record])
```

`FileNamer.swift`:

```swift
    public static func fileName(for date: Date, ext: String, prefix: String = "Screenshot",
                                timeZone: TimeZone = .current) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(prefix) \(f.string(from: date)).\(ext)"
    }
```

- [ ] **Step 4: Run tests.** `swift run --package-path Packages/CaptureKit CaptureKitTests` → PASS, 0 failures. Also `swift build` (App must still compile — the Shortcuts tab picks up the new row automatically via `allCases`).

- [ ] **Step 5: Commit.**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): record hotkey action (⌘⇧5) + unbound-sentinel persistence + FileNamer prefix"
```

---

### Task 2: RecordingKit package scaffold + `RecorderState` (TDD)

**Files:**
- Create: `Packages/RecordingKit/Package.swift`
- Create: `Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift`
- Create: `Packages/RecordingKit/Tests/RecordingKitTests/main.swift`
- Create: `Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift`
- Modify: root `Package.swift` (add the package dependency + product)

- [ ] **Step 1: Package manifest.** Create `Packages/RecordingKit/Package.swift` (mirrors CaptureKit's):

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RecordingKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "RecordingKit", targets: ["RecordingKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "RecordingKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/RecordingKit RecordingKitTests
        .executableTarget(
            name: "RecordingKitTests",
            dependencies: ["RecordingKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/RecordingKitTests"
        ),
    ]
)
```

In the root `Package.swift`, add `.package(path: "Packages/RecordingKit"),` to `dependencies` and `.product(name: "RecordingKit", package: "RecordingKit"),` to the executable target's dependencies.

- [ ] **Step 2: Failing tests.** `Packages/RecordingKit/Tests/RecordingKitTests/RecorderStateTests.swift`:

```swift
import TestKit
import Foundation
@testable import RecordingKit

let recorderStateTests: [TestCase] = [
    TestCase("legalTransitions") { t in
        var s = RecorderState.idle
        t.isTrue(s.transition(.arm))          // idle → armed
        t.equal(s, .armed)
        t.isTrue(s.transition(.begin(Date(timeIntervalSince1970: 100))))
        if case .recording(let started) = s {
            t.equal(started, Date(timeIntervalSince1970: 100))
        } else { t.fail("expected .recording") }
        t.isTrue(s.transition(.finish))       // recording → finishing
        t.equal(s, .finishing)
        t.isTrue(s.transition(.reset))        // finishing → idle
        t.equal(s, .idle)
    },
    TestCase("illegalTransitionsRejected") { t in
        var s = RecorderState.idle
        t.isFalse(s.transition(.finish))      // can't finish from idle
        t.equal(s, .idle)
        t.isFalse(s.transition(.begin(Date()))) // can't begin without arming
        s = .finishing
        t.isFalse(s.transition(.arm))         // busy finalizing — ⌘⇧5 ignored
        t.isFalse(s.transition(.begin(Date())))
        s = .armed
        t.isTrue(s.transition(.reset))        // cancel from the strip
        t.equal(s, .idle)
    },
    TestCase("elapsedFormatting") { t in
        let start = Date(timeIntervalSince1970: 0)
        let s = RecorderState.recording(started: start)
        t.equal(s.elapsedString(now: start.addingTimeInterval(0)), "0:00")
        t.equal(s.elapsedString(now: start.addingTimeInterval(42)), "0:42")
        t.equal(s.elapsedString(now: start.addingTimeInterval(725)), "12:05")
        t.isNil(RecorderState.idle.elapsedString(now: Date()))
    },
]
```

`main.swift`:

```swift
import TestKit

runTests("RecordingKitTests",
    recorderStateTests
)
```

Run: `swift run --package-path Packages/RecordingKit RecordingKitTests` → build error (RecorderState undefined).

- [ ] **Step 3: Implement** `Packages/RecordingKit/Sources/RecordingKit/RecorderState.swift`:

```swift
import Foundation

/// Recording lifecycle. Pure state machine: `transition` applies an event only
/// when legal, so callers (the ⌘⇧5 toggle) can't corrupt the lifecycle.
public enum RecorderState: Equatable {
    case idle
    case armed                       // record strip showing
    case recording(started: Date)
    case finishing                   // writer finalizing — new commands rejected

    public enum Event: Equatable {
        case arm                     // show the strip
        case begin(Date)             // capture started
        case finish                  // stop requested
        case reset                   // back to idle (finalized or cancelled)
    }

    /// Applies `event` if legal; returns whether the state changed.
    @discardableResult
    public mutating func transition(_ event: Event) -> Bool {
        switch (self, event) {
        case (.idle, .arm):                self = .armed
        case (.armed, .begin(let date)):   self = .recording(started: date)
        case (.armed, .reset):             self = .idle
        case (.recording, .finish):        self = .finishing
        case (.finishing, .reset):         self = .idle
        default:                           return false
        }
        return true
    }

    /// "m:ss" while recording; nil otherwise.
    public func elapsedString(now: Date) -> String? {
        guard case .recording(let started) = self else { return nil }
        let secs = max(0, Int(now.timeIntervalSince(started)))
        return "\(secs / 60):" + String(format: "%02d", secs % 60)
    }
}
```

- [ ] **Step 4: Run tests.** `swift run --package-path Packages/RecordingKit RecordingKitTests` → PASS 3/3. Also `swift build` at the root (new dependency resolves).

- [ ] **Step 5: Commit.**

```bash
git add Packages/RecordingKit Package.swift
git commit -m "feat(recording): RecordingKit package + RecorderState machine"
```

---

### Task 3: `RecordingConfig` + `GIFTiming` (TDD)

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/RecordingConfig.swift`
- Create: `Packages/RecordingKit/Sources/RecordingKit/GIFTiming.swift`
- Create: `Packages/RecordingKit/Tests/RecordingKitTests/RecordingConfigTests.swift`
- Modify: `Packages/RecordingKit/Tests/RecordingKitTests/main.swift`

- [ ] **Step 1: Failing tests.** `RecordingConfigTests.swift`:

```swift
import TestKit
import Foundation
@testable import RecordingKit

let recordingConfigTests: [TestCase] = [
    TestCase("defaultsAndRoundTrip") { t in
        let d = RecordingConfig.default
        t.equal(d.format, .mp4)
        t.equal(d.fps, 30)
        t.isTrue(d.systemAudio)
        t.isFalse(d.microphone)
        t.isFalse(d.camera)
        t.equal(d.cameraSize, .small)
        t.isTrue(d.clickHighlights)
        t.isFalse(d.keystrokeOverlay)
        var c = d
        c.format = .gif; c.fps = 60; c.microphone = true; c.cameraSize = .medium
        t.equal(RecordingConfig(dictionary: c.dictionary), c)
        // Malformed/missing keys fall back to defaults.
        t.equal(RecordingConfig(dictionary: [:]), .default)
        t.equal(RecordingConfig(dictionary: ["fps": "999"]).fps, 30) // not 30/60 → default
    },
    TestCase("videoSettingsDerivation") { t in
        let s = RecordingConfig.default.videoSettings(width: 1920, height: 1080)
        t.equal(s[AVKey.codec] as? String, "avc1")
        t.equal(s[AVKey.width] as? Int, 1920)
        t.equal(s[AVKey.height] as? Int, 1080)
        let props = s[AVKey.compression] as? [String: Any]
        let bitrate = props?[AVKey.bitRate] as? Int
        // 1920*1080*30*0.12 ≈ 7.46 Mbps — inside the 2–40 Mbps clamp.
        t.equal(bitrate, Int(1920.0 * 1080.0 * 30.0 * 0.12))
        // Tiny recordings clamp up to 2 Mbps.
        let tiny = RecordingConfig.default.videoSettings(width: 100, height: 100)
        let tinyRate = (tiny[AVKey.compression] as? [String: Any])?[AVKey.bitRate] as? Int
        t.equal(tinyRate, 2_000_000)
    },
    TestCase("gifTiming") { t in
        // 2.5 s at 10 fps → 25 frames at 0.0, 0.1, …, 2.4.
        let times = GIFTiming.frameTimes(duration: 2.5, fps: 10)
        t.equal(times.count, 25)
        t.approxEqual(times.first ?? -1, 0.0)
        t.approxEqual(times.last ?? -1, 2.4)
        // Degenerate inputs produce at least one frame.
        t.equal(GIFTiming.frameTimes(duration: 0.01, fps: 10).count, 1)
        // Aspect-preserving downscale, never upscale.
        let down = GIFTiming.outputSize(source: CGSize(width: 1920, height: 1080), maxWidth: 960)
        t.equal(down, CGSize(width: 960, height: 540))
        let keep = GIFTiming.outputSize(source: CGSize(width: 800, height: 600), maxWidth: 960)
        t.equal(keep, CGSize(width: 800, height: 600))
    },
]
```

Add `+ recordingConfigTests` to the runner in `main.swift` (the aggregate becomes `recorderStateTests + recordingConfigTests`).

Run → build error.

- [ ] **Step 2: Implement.** `RecordingConfig.swift`:

```swift
import Foundation

/// AVFoundation settings-dictionary keys, isolated so the pure model (and its
/// tests) don't import AVFoundation. Values match AVVideoSettings.h constants.
public enum AVKey {
    public static let codec = "AVVideoCodecKey"
    public static let width = "AVVideoWidthKey"
    public static let height = "AVVideoHeightKey"
    public static let compression = "AVVideoCompressionPropertiesKey"
    public static let bitRate = "AverageBitRate"
}

public enum RecordingFormat: String, CaseIterable { case mp4, gif }
public enum CameraSize: String, CaseIterable {
    case small, medium
    /// Bubble diameter in points.
    public var diameter: CGFloat { self == .small ? 160 : 240 }
}

/// User-facing recording preferences. Pure; persisted as a string dictionary
/// (same convention as CaptureSettings).
public struct RecordingConfig: Equatable {
    public var format: RecordingFormat
    public var fps: Int                  // 30 or 60
    public var systemAudio: Bool
    public var microphone: Bool
    public var camera: Bool
    public var cameraSize: CameraSize
    public var clickHighlights: Bool
    public var keystrokeOverlay: Bool

    public static let gifFPS = 10
    public static let gifMaxWidth: CGFloat = 960

    public static let `default` = RecordingConfig(
        format: .mp4, fps: 30, systemAudio: true, microphone: false,
        camera: false, cameraSize: .small, clickHighlights: true,
        keystrokeOverlay: false)

    public init(format: RecordingFormat, fps: Int, systemAudio: Bool, microphone: Bool,
                camera: Bool, cameraSize: CameraSize, clickHighlights: Bool,
                keystrokeOverlay: Bool) {
        self.format = format
        self.fps = fps
        self.systemAudio = systemAudio
        self.microphone = microphone
        self.camera = camera
        self.cameraSize = cameraSize
        self.clickHighlights = clickHighlights
        self.keystrokeOverlay = keystrokeOverlay
    }

    /// H.264 AVAssetWriter video settings. Bitrate heuristic w·h·fps·0.12,
    /// clamped to 2–40 Mbps.
    public func videoSettings(width: Int, height: Int) -> [String: Any] {
        let rate = min(max(Int(Double(width) * Double(height) * Double(fps) * 0.12),
                           2_000_000), 40_000_000)
        return [
            AVKey.codec: "avc1",
            AVKey.width: width,
            AVKey.height: height,
            AVKey.compression: [AVKey.bitRate: rate] as [String: Any],
        ]
    }

    // MARK: - Persistence

    public var dictionary: [String: String] {
        ["format": format.rawValue,
         "fps": String(fps),
         "systemAudio": systemAudio ? "true" : "false",
         "microphone": microphone ? "true" : "false",
         "camera": camera ? "true" : "false",
         "cameraSize": cameraSize.rawValue,
         "clickHighlights": clickHighlights ? "true" : "false",
         "keystrokeOverlay": keystrokeOverlay ? "true" : "false"]
    }

    public init(dictionary: [String: String]) {
        let d = RecordingConfig.default
        self.format = RecordingFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        let fps = Int(dictionary["fps"] ?? "")
        self.fps = (fps == 30 || fps == 60) ? fps! : d.fps
        self.systemAudio = (dictionary["systemAudio"] ?? "\(d.systemAudio)") == "true"
        self.microphone = (dictionary["microphone"] ?? "\(d.microphone)") == "true"
        self.camera = (dictionary["camera"] ?? "\(d.camera)") == "true"
        self.cameraSize = CameraSize(rawValue: dictionary["cameraSize"] ?? "") ?? d.cameraSize
        self.clickHighlights = (dictionary["clickHighlights"] ?? "\(d.clickHighlights)") == "true"
        self.keystrokeOverlay = (dictionary["keystrokeOverlay"] ?? "\(d.keystrokeOverlay)") == "true"
    }
}
```

NOTE on `AVKey`: the string values must equal the real AVFoundation constants — `AVVideoCodecKey == "AVVideoCodecKey"`? **No.** The literal runtime values are: `AVVideoCodecKey = "AVVideoCodecKey"` is NOT guaranteed. To avoid a landmine, `ScreenRecorder` (Task 4, which CAN import AVFoundation) must **rebuild** the dictionary with the genuine constants, using `videoSettings` only for the numbers. Therefore simplify: in this file keep `videoSettings` but have the test assert numbers only — see the test: it asserts `codec == "avc1"`, width/height ints, and the bitrate math. The keys here are internal to RecordingKit; Task 4 maps them: `AVVideoCodecKey: AVVideoCodecType.h264` etc. (This keeps the heuristic pure-testable without linking AVFoundation in tests.)

`GIFTiming.swift`:

```swift
import Foundation
import CoreGraphics

public enum GIFTiming {
    /// Sample timestamps (seconds) for converting a clip to GIF at `fps`.
    /// Always at least one frame.
    public static func frameTimes(duration: Double, fps: Int) -> [Double] {
        guard duration > 0, fps > 0 else { return [0] }
        let step = 1.0 / Double(fps)
        let count = max(1, Int(duration * Double(fps)))
        return (0..<count).map { Double($0) * step }
    }

    /// Aspect-preserving downscale to `maxWidth`; never upscales.
    public static func outputSize(source: CGSize, maxWidth: CGFloat) -> CGSize {
        guard source.width > maxWidth, source.width > 0 else { return source }
        let scale = maxWidth / source.width
        return CGSize(width: maxWidth, height: (source.height * scale).rounded())
    }
}
```

- [ ] **Step 3: Run tests.** `swift run --package-path Packages/RecordingKit RecordingKitTests` → PASS (6 cases). 

- [ ] **Step 4: Commit.**

```bash
git add Packages/RecordingKit
git commit -m "feat(recording): RecordingConfig + GIFTiming pure models"
```

---

### Task 4: `ScreenRecorder` engine + `MicCapturer`

No pure logic here — verification is `swift build` (the engine is exercised by the manual checklist; the test runner has no Screen Recording TCC grant).

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift`
- Create: `Packages/RecordingKit/Sources/RecordingKit/MicCapturer.swift`

- [ ] **Step 1:** Create `MicCapturer.swift`:

```swift
import AVFoundation

/// Microphone capture on macOS 14 (SCK mic capture is macOS 15+): a tiny
/// AVCaptureSession forwarding audio sample buffers to the recording writer.
public final class MicCapturer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private var onBuffer: ((CMSampleBuffer) -> Void)?

    /// Requests mic permission if needed; false when denied.
    public static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Starts delivering mic buffers on `queue`. Throws when no mic is available.
    public func start(queue: DispatchQueue,
                      onBuffer: @escaping (CMSampleBuffer) -> Void) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.noMicrophone
        }
        self.onBuffer = onBuffer
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.noMicrophone
        }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
        onBuffer = nil
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        onBuffer?(sampleBuffer)
    }
}
```

- [ ] **Step 2:** Create `ScreenRecorder.swift`:

```swift
import AVFoundation
import ScreenCaptureKit

public enum RecorderError: Error {
    case writerFailed
    case noMicrophone
    case notRecording
}

/// SCStream → AVAssetWriter MP4 recording engine. Video + optional system-audio
/// track (SCK) + optional microphone track (MicCapturer). All sample appends run
/// on `sampleQueue`; start/stop are called from the main actor.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var micCapturer: MicCapturer?
    private let sampleQueue = DispatchQueue(label: "betterscreenshot.recorder.samples")
    private var sessionStarted = false
    private var outputURL: URL?

    /// Stream died underneath us (display unplugged, etc.). Fired on sampleQueue.
    public var onStreamError: ((Error) -> Void)?

    public override init() { super.init() }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000,
    ]

    /// Begin recording `filter` at `pixelSize` to `outputURL`.
    /// `sourceRect` (display-relative, top-left-origin, points) crops the display.
    public func start(filter: SCContentFilter, pixelSize: CGSize, sourceRect: CGRect?,
                      config: RecordingConfig, outputURL: URL) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let pure = config.videoSettings(width: Int(pixelSize.width), height: Int(pixelSize.height))
        // Map the pure-model dictionary onto the real AVFoundation constants.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pure[AVKey.width] as? Int ?? Int(pixelSize.width),
            AVVideoHeightKey: pure[AVKey.height] as? Int ?? Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:
                    (pure[AVKey.compression] as? [String: Any])?[AVKey.bitRate] as? Int ?? 8_000_000,
            ],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else { throw RecorderError.writerFailed }
        writer.add(vInput)

        var sysInput: AVAssetWriterInput?
        if config.systemAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); sysInput = a }
        }
        var micInput: AVAssetWriterInput?
        if config.microphone {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); micInput = a }
        }

        let sc = SCStreamConfiguration()
        sc.width = Int(pixelSize.width)
        sc.height = Int(pixelSize.height)
        if let sourceRect { sc.sourceRect = sourceRect }
        sc.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        sc.showsCursor = true
        sc.capturesAudio = config.systemAudio
        sc.pixelFormat = kCVPixelFormatType_32BGRA
        sc.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: sc, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if config.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerFailed }

        self.writer = writer
        self.videoInput = vInput
        self.systemAudioInput = sysInput
        self.micInput = micInput
        self.outputURL = outputURL
        self.sessionStarted = false
        self.stream = stream

        if config.microphone, micInput != nil {
            let capturer = MicCapturer()
            self.micCapturer = capturer
            try? capturer.start(queue: sampleQueue) { [weak self] buffer in
                self?.appendMic(buffer)
            }
        }

        try await stream.startCapture()
    }

    /// Stop and finalize; returns the finished file URL.
    public func stop() async throws -> URL {
        guard let writer, let outputURL else { throw RecorderError.notRecording }
        if let stream { try? await stream.stopCapture() }
        micCapturer?.stop()
        // Let in-flight appends drain before finishing.
        sampleQueue.sync {}
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micInput?.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        defer { reset() }
        if writer.status == .failed { throw writer.error ?? RecorderError.writerFailed }
        return outputURL
    }

    private func reset() {
        stream = nil; writer = nil; videoInput = nil
        systemAudioInput = nil; micInput = nil; micCapturer = nil
        outputURL = nil; sessionStarted = false
    }

    // MARK: - SCStreamOutput (called on sampleQueue)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Only complete frames carry image data.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                      sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: statusRaw) == .complete else { return }
            if !sessionStarted {
                writer?.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                sessionStarted = true
            }
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            guard sessionStarted, let systemAudioInput,
                  systemAudioInput.isReadyForMoreMediaData else { return }
            systemAudioInput.append(sampleBuffer)
        default:
            break
        }
    }

    private func appendMic(_ buffer: CMSampleBuffer) {
        guard sessionStarted, let micInput, micInput.isReadyForMoreMediaData else { return }
        micInput.append(buffer)
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamError?(error)
    }
}
```

- [ ] **Step 3: Build.** `swift build` at the repo root (RecordingKit compiles into the app target) AND `swift build --package-path Packages/RecordingKit`. Expected: `Build complete!`. SDK signature drift (e.g. `SCStreamFrameInfo` dictionary casting, `sc.sourceRect` availability) is the risk here — fix mechanically and report each adjustment as a deviation; redesigns require BLOCKED.

- [ ] **Step 4: Commit.**

```bash
git add Packages/RecordingKit
git commit -m "feat(recording): ScreenRecorder engine (SCStream→AVAssetWriter) + MicCapturer"
```

---

### Task 5: `GIFExporter`

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/GIFExporter.swift`

- [ ] **Step 1: Implement:**

```swift
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

public enum GIFExportError: Error {
    case noVideoTrack
    case destinationFailed
}

/// Post-conversion of a recorded MP4 into a looping GIF (10 fps, ≤960 px wide).
public enum GIFExporter {
    public static func export(mp4 url: URL, to gifURL: URL,
                              fps: Int = RecordingConfig.gifFPS,
                              maxWidth: CGFloat = RecordingConfig.gifMaxWidth) async throws {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw GIFExportError.noVideoTrack
        }
        let duration = try await asset.load(.duration).seconds
        let natural = try await track.load(.naturalSize)
        let size = GIFTiming.outputSize(source: natural, maxWidth: maxWidth)
        let times = GIFTiming.frameTimes(duration: duration, fps: fps)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = size
        let tolerance = CMTime(seconds: 0.5 / Double(fps), preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        guard let dest = CGImageDestinationCreateWithURL(
                gifURL as CFURL, UTType.gif.identifier as CFString, times.count, nil) else {
            throw GIFExportError.destinationFailed
        }
        let gifProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(dest, gifProps as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary:
                            [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]]
        for t in times {
            let cm = CMTime(seconds: t, preferredTimescale: 600)
            let image = try await generator.image(at: cm).image
            CGImageDestinationAddImage(dest, image, frameProps as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw GIFExportError.destinationFailed }
    }
}
```

- [ ] **Step 2: Build + tests still green.**

```bash
swift build --package-path Packages/RecordingKit && swift build && \
swift run --package-path Packages/RecordingKit RecordingKitTests
```

- [ ] **Step 3: Commit.**

```bash
git add Packages/RecordingKit
git commit -m "feat(recording): GIFExporter — MP4 → looping GIF via AVAssetImageGenerator"
```

---

### Task 6: Visualization panels — camera bubble, click highlighter, keystroke pill

**Files:**
- Create: `Packages/RecordingKit/Sources/RecordingKit/CameraBubbleController.swift`
- Create: `Packages/RecordingKit/Sources/RecordingKit/ClickHighlighter.swift`
- Create: `Packages/RecordingKit/Sources/RecordingKit/KeystrokeOverlayController.swift`

- [ ] **Step 1:** `CameraBubbleController.swift`:

```swift
import AppKit
import AVFoundation

/// Circular live-camera preview in a floating panel. It is captured by simply
/// being on screen — no frame compositing. Drag to move.
@MainActor
public final class CameraBubbleController {
    private var panel: NSPanel?
    private var session: AVCaptureSession?

    public init() {}

    public static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    /// Shows the bubble near the bottom-right of `rect` (screen coords, points).
    public func show(near rect: CGRect, on screen: NSScreen, diameter: CGFloat) {
        guard panel == nil else { return }
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        let session = AVCaptureSession()
        session.sessionPreset = .medium
        guard session.canAddInput(input) else { return }
        session.addInput(input)

        let margin: CGFloat = 24
        let origin = CGPoint(
            x: min(rect.maxX, screen.visibleFrame.maxX) - diameter - margin,
            y: max(rect.minY, screen.visibleFrame.minY) + margin)
        let frame = CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        content.layer?.cornerRadius = diameter / 2
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.black.cgColor
        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = content.bounds
        preview.videoGravity = .resizeAspectFill
        content.layer?.addSublayer(preview)
        p.contentView = content

        self.session = session
        self.panel = p
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
        p.orderFrontRegardless()
    }

    public func hide() {
        session?.stopRunning()
        session = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
```

- [ ] **Step 2:** `ClickHighlighter.swift`:

```swift
import AppKit

/// Fading accent circles at every mouse-down, drawn in a transparent
/// click-through panel covering the recorded screen. Global+local monitors —
/// mouse monitors need no special permission.
@MainActor
public final class ClickHighlighter {
    private var panel: NSPanel?
    private var monitors: [Any] = []

    public init() {}

    public func start(on screen: NSScreen) {
        guard panel == nil else { return }
        let p = NSPanel(contentRect: screen.frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView?.wantsLayer = true
        p.orderFrontRegardless()
        panel = p

        let down: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.flash(at: NSEvent.mouseLocation) }
        }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: down) {
            monitors.append(global)
        }
        // Global monitors don't see this app's own events — add a local one too.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { event in
            down(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    public func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        panel?.orderOut(nil)
        panel = nil
    }

    private func flash(at globalPoint: CGPoint) {
        guard let panel, let layer = panel.contentView?.layer,
              panel.frame.contains(globalPoint) else { return }
        let local = CGPoint(x: globalPoint.x - panel.frame.minX,
                            y: globalPoint.y - panel.frame.minY)
        let d: CGFloat = 36
        let circle = CAShapeLayer()
        circle.path = CGPath(ellipseIn: CGRect(x: local.x - d / 2, y: local.y - d / 2,
                                               width: d, height: d), transform: nil)
        circle.fillColor = NSColor.controlAccentColor.withAlphaComponent(0.45).cgColor
        layer.addSublayer(circle)
        CATransaction.begin()
        CATransaction.setCompletionBlock { circle.removeFromSuperlayer() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = 0.4
        fade.isRemovedOnCompletion = false
        fade.fillMode = .forwards
        circle.add(fade, forKey: "fade")
        CATransaction.commit()
    }
}
```

- [ ] **Step 3:** `KeystrokeOverlayController.swift`:

```swift
import AppKit
import ApplicationServices

/// Dark pill showing each keypress ("⌘⇧4") near the bottom of the recorded
/// screen. Global keyDown monitoring requires Accessibility trust — the only
/// permission-gated feature in the app.
@MainActor
public final class KeystrokeOverlayController {
    private var panel: NSPanel?
    private var label: NSTextField?
    private var monitors: [Any] = []
    private var fadeTimer: Timer?

    public init() {}

    public static var hasPermission: Bool { AXIsProcessTrusted() }

    /// Prompts the user (opens System Settings) when not yet trusted.
    public static func requestPermission() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(opts)
    }

    public func start(on screen: NSScreen) {
        guard panel == nil, Self.hasPermission else { return }
        let size = CGSize(width: 280, height: 44)
        let frame = CGRect(x: screen.frame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 100,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSView(frame: CGRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        content.layer?.cornerRadius = 10
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedSystemFont(ofSize: 20, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.frame = content.bounds.insetBy(dx: 8, dy: 8)
        label.autoresizingMask = [.width, .height]
        content.addSubview(label)
        p.contentView = content
        p.alphaValue = 0
        p.orderFrontRegardless()

        self.panel = p
        self.label = label

        let handler: (NSEvent) -> Void = { [weak self] event in
            let text = Self.glyphString(for: event)
            Task { @MainActor in self?.show(text) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    public func stop() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        fadeTimer?.invalidate()
        fadeTimer = nil
        panel?.orderOut(nil)
        panel = nil
        label = nil
    }

    private func show(_ text: String) {
        guard let panel, let label else { return }
        label.stringValue = text
        panel.alphaValue = 1
        fadeTimer?.invalidate()
        fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
            Task { @MainActor [weak self] in
                self?.panel?.animator().alphaValue = 0
            }
        }
    }

    /// "⌃⌥⇧⌘X" — modifier glyphs + the typed character (uppercased) or key name.
    static func glyphString(for event: NSEvent) -> String {
        var s = ""
        let f = event.modifierFlags
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        switch event.keyCode {
        case 36: return s + "↩"
        case 48: return s + "⇥"
        case 49: return s + "Space"
        case 51: return s + "⌫"
        case 53: return s + "Esc"
        case 123: return s + "←"
        case 124: return s + "→"
        case 125: return s + "↓"
        case 126: return s + "↑"
        default:
            let chars = event.charactersIgnoringModifiers ?? ""
            return s + chars.uppercased()
        }
    }
}
```

- [ ] **Step 4: Build.** `swift build --package-path Packages/RecordingKit && swift build` → `Build complete!` (fix mechanical issues, report deviations).

- [ ] **Step 5: Commit.**

```bash
git add Packages/RecordingKit
git commit -m "feat(recording): camera bubble, click highlighter, keystroke pill panels"
```

---

### Task 7: System shortcut suppression (id 184) + Info.plist usage strings

**Files:**
- Modify: `App/SystemScreenshotShortcuts.swift`
- Modify: `App/AppDelegate.swift` (two call sites)
- Modify: `App/Info.plist`

- [ ] **Step 1:** Read `App/SystemScreenshotShortcuts.swift`. Generalize: replace the single-id implementation with a list. Keep the Preferences I/O section unchanged. Replace the id constant + both public methods with:

```swift
    /// Native shortcuts we shadow: id 30 = "Save picture of selected area as a
    /// file" (⌘⇧4), id 184 = "Screenshot and recording options" (⌘⇧5).
    /// parameters = [ASCII code, virtual key code, modifier mask].
    private static let shadowed: [(id: String, parameters: [Int])] = [
        ("30",  [52, 21, 1_179_648]),  // '4', keycode 21, ⌘⇧
        ("184", [53, 23, 1_179_648]),  // '5', keycode 23, ⌘⇧
    ]

    /// Disable the native shortcuts by writing standard bindings with `enabled = 0`.
    static func disableNativeShortcuts() {
        var hotKeys = currentHotKeys()
        for entry in shadowed {
            hotKeys[entry.id] = [
                "enabled": 0,
                "value": ["parameters": entry.parameters, "type": "standard"],
            ]
        }
        write(hotKeys)
        reload()
    }

    /// Restore by removing our entries, reverting to macOS defaults (enabled).
    /// Safe across crashes: a run killed before this simply re-disables next launch.
    static func restoreNativeShortcuts() {
        var hotKeys = currentHotKeys()
        let present = shadowed.filter { hotKeys[$0.id] != nil }
        guard !present.isEmpty else { return }
        for entry in present { hotKeys.removeValue(forKey: entry.id) }
        write(hotKeys)
        reload()
    }
```

Update the file's top doc comment to mention both ids. In `App/AppDelegate.swift`, rename the two call sites: `disableNativeAreaScreenshot()` → `disableNativeShortcuts()` and `restoreNativeAreaScreenshot()` → `restoreNativeShortcuts()` (update the adjacent comments' wording from "native ⌘⇧4" to "native ⌘⇧4/⌘⇧5").

- [ ] **Step 2:** In `App/Info.plist`, add inside the top-level `<dict>`:

```xml
	<key>NSMicrophoneUsageDescription</key>
	<string>BetterScreenshot records microphone audio in screen recordings when you enable the mic.</string>
	<key>NSCameraUsageDescription</key>
	<string>BetterScreenshot shows your camera as an overlay bubble in screen recordings when you enable it.</string>
```

- [ ] **Step 3: Build + commit.**

```bash
swift build && git add App && \
git commit -m "feat(app): shadow native ⌘⇧5 (id 184) alongside ⌘⇧4 + mic/camera usage strings"
```

---

### Task 8: SettingsStore `recording` + Recording settings tab

**Files:**
- Modify: `App/SettingsStore.swift`
- Modify: `App/SettingsView.swift`

- [ ] **Step 1:** `App/SettingsStore.swift` — add `import RecordingKit`; add after `failedActions`:

```swift
    @Published var recording: RecordingConfig
```

In `init()` add:

```swift
        let recDict = defaults.dictionary(forKey: "recordingConfig") as? [String: String] ?? [:]
        self.recording = recDict.isEmpty ? .default : RecordingConfig(dictionary: recDict)
```

In `persist()` add:

```swift
        defaults.set(recording.dictionary, forKey: "recordingConfig")
```

- [ ] **Step 2:** `App/SettingsView.swift` — add `import RecordingKit`. In `SettingsView.body`'s `TabView`, add after the Shortcuts tab:

```swift
            RecordingTab(store: store)
                .tabItem { Label("Recording", systemImage: "record.circle") }
```

In `ShortcutsTab`, DELETE the line:

```swift
            Text("⇧⌘5 is reserved for Start/Stop Recording (coming soon).")
                .font(.caption).foregroundStyle(.secondary)
```

(and its preceding `Divider().padding(.vertical, 4)` if that leaves a double divider — keep exactly one divider above the Restore Defaults row).

Add at the bottom of the file:

```swift
private struct RecordingTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("Format", selection: bind(\.format)) {
                Text("MP4 video").tag(RecordingFormat.mp4)
                Text("GIF").tag(RecordingFormat.gif)
            }
            Picker("Frame rate", selection: bind(\.fps)) {
                Text("30 fps").tag(30)
                Text("60 fps").tag(60)
            }
            Toggle("Record system audio", isOn: bind(\.systemAudio))
            Toggle("Record microphone", isOn: bind(\.microphone))
            Toggle("Show camera bubble", isOn: bind(\.camera))
            Picker("Camera size", selection: bind(\.cameraSize)) {
                Text("Small").tag(CameraSize.small)
                Text("Medium").tag(CameraSize.medium)
            }
            .disabled(!store.recording.camera)
            Toggle("Highlight mouse clicks", isOn: bind(\.clickHighlights))
            Toggle("Show keystrokes", isOn: Binding(
                get: { store.recording.keystrokeOverlay },
                set: { newValue in
                    if newValue && !KeystrokeOverlayController.hasPermission {
                        KeystrokeOverlayController.requestPermission()
                        // Stays off until Accessibility is actually granted.
                        store.recording.keystrokeOverlay = KeystrokeOverlayController.hasPermission
                    } else {
                        store.recording.keystrokeOverlay = newValue
                    }
                    store.persist()
                }))
            Text("Showing keystrokes needs the Accessibility permission.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func bind<V>(_ keyPath: WritableKeyPath<RecordingConfig, V>) -> Binding<V> {
        Binding(get: { store.recording[keyPath: keyPath] },
                set: { store.recording[keyPath: keyPath] = $0; store.persist() })
    }
}
```

- [ ] **Step 3: Build + commit.**

```bash
swift build && git add App && \
git commit -m "feat(app): Recording settings tab + persisted RecordingConfig"
```

---

### Task 9: RecordingCoordinator + record strip + menu-bar state + ⌘⇧5 wiring

**Files:**
- Create: `App/RecordStripController.swift`
- Create: `App/RecordingCoordinator.swift`
- Modify: `App/MenuBarController.swift`
- Modify: `App/AppDelegate.swift`

- [ ] **Step 1:** Create `App/RecordStripController.swift`:

```swift
import AppKit
import RecordingKit

/// The pre-record control strip: target buttons + per-recording toggles.
/// Lives in App because it bridges RecordingConfig ↔ SettingsStore.
@MainActor
final class RecordStripController {
    private var panel: NSPanel?
    private let store: SettingsStore

    var onFullScreen: (() -> Void)?
    var onArea: (() -> Void)?
    var onCancel: (() -> Void)?

    init(store: SettingsStore) { self.store = store }

    var isVisible: Bool { panel != nil }

    func show(on screen: NSScreen) {
        guard panel == nil else { return }
        let strip = NSStackView()
        strip.orientation = .horizontal
        strip.spacing = 10
        strip.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)

        let full = NSButton(title: "Record Full Screen", target: self,
                            action: #selector(fullScreen))
        full.bezelStyle = .rounded
        let area = NSButton(title: "Record Area…", target: self, action: #selector(areaSelect))
        area.bezelStyle = .rounded

        let format = NSSegmentedControl(labels: ["MP4", "GIF"], trackingMode: .selectOne,
                                        target: self, action: #selector(formatChanged(_:)))
        format.selectedSegment = store.recording.format == .mp4 ? 0 : 1

        func toggle(_ symbol: String, _ tip: String, _ state: Bool,
                    _ action: Selector) -> NSButton {
            let b = NSButton(image: NSImage(systemSymbolName: symbol,
                                            accessibilityDescription: tip)!,
                             target: self, action: action)
            b.setButtonType(.toggle)
            b.bezelStyle = .rounded
            b.state = state ? .on : .off
            b.toolTip = tip
            return b
        }
        let mic = toggle("mic", "Record microphone", store.recording.microphone,
                         #selector(micChanged(_:)))
        let sys = toggle("speaker.wave.2", "Record system audio", store.recording.systemAudio,
                         #selector(sysChanged(_:)))
        let cam = toggle("video", "Show camera bubble", store.recording.camera,
                         #selector(camChanged(_:)))

        let cancel = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill",
                                             accessibilityDescription: "Cancel")!,
                              target: self, action: #selector(cancelTapped))
        cancel.isBordered = false

        for v in [full, area, format, mic, sys, cam, cancel] { strip.addArrangedSubview(v) }

        let size = strip.fittingSize
        let frame = CGRect(x: screen.visibleFrame.midX - size.width / 2,
                           y: screen.visibleFrame.minY + 60,
                           width: size.width, height: size.height)
        let p = NSPanel(contentRect: frame,
                        styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        strip.frame = CGRect(origin: .zero, size: size)
        p.contentView = strip
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    @objc private func fullScreen() { onFullScreen?() }
    @objc private func areaSelect() { onArea?() }
    @objc private func cancelTapped() { onCancel?() }
    @objc private func formatChanged(_ sender: NSSegmentedControl) {
        store.recording.format = sender.selectedSegment == 0 ? .mp4 : .gif
        store.persist()
    }
    @objc private func micChanged(_ sender: NSButton) {
        store.recording.microphone = sender.state == .on; store.persist()
    }
    @objc private func sysChanged(_ sender: NSButton) {
        store.recording.systemAudio = sender.state == .on; store.persist()
    }
    @objc private func camChanged(_ sender: NSButton) {
        store.recording.camera = sender.state == .on; store.persist()
    }
}
```

- [ ] **Step 2:** Create `App/RecordingCoordinator.swift`:

```swift
import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit
import RecordingKit

/// Orchestrates the recording lifecycle: strip → engine + panels → save/convert.
@MainActor
final class RecordingCoordinator {
    private let settings: SettingsStore
    private let recorder = ScreenRecorder()
    private let strip: RecordStripController
    private let selection = SelectionOverlayController()
    private let bubble = CameraBubbleController()
    private let clicks = ClickHighlighter()
    private let keystrokes = KeystrokeOverlayController()
    private let hud = HUDController()
    private var state = RecorderState.idle
    private var timer: Timer?

    /// Set by the app delegate; presents the one-button permission setup window.
    var presentSetup: (() -> Void)?
    /// Menu-bar state: (recording?, elapsed string). Called on every change/tick.
    var onStateChange: ((Bool, String?) -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
        self.strip = RecordStripController(store: settings)
        strip.onFullScreen = { [weak self] in self?.beginFullScreen() }
        strip.onArea = { [weak self] in self?.beginAreaSelection() }
        strip.onCancel = { [weak self] in self?.cancelStrip() }
        recorder.onStreamError = { [weak self] _ in
            Task { @MainActor in self?.streamFailed() }
        }
    }

    var isRecording: Bool { if case .recording = state { return true }; return false }

    /// The smart ⌘⇧5 entry point: idle → strip · armed → cancel · recording → stop.
    func toggle() {
        switch state {
        case .idle: arm()
        case .armed: cancelStrip()
        case .recording: Task { await stop() }
        case .finishing: break   // busy — ignore
        }
    }

    private func arm() {
        guard PermissionManager.hasScreenRecordingPermission else {
            presentSetup?()
            return
        }
        guard state.transition(.arm) else { return }
        let screen = NSScreen.screens.first {
            $0.frame.contains(NSEvent.mouseLocation)
        } ?? NSScreen.main
        if let screen { strip.show(on: screen) }
    }

    private func cancelStrip() {
        strip.hide()
        state.transition(.reset)
    }

    private func beginFullScreen() {
        guard let screen = stripScreen() else { return }
        strip.hide()
        Task { await begin(globalRect: nil, screen: screen) }
    }

    private func beginAreaSelection() {
        strip.hide()
        selection.present { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard let result,
                      let screen = NSScreen.screens.first(where: {
                          $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                              as? CGDirectDisplayID == result.displayID
                      }) else {
                    self.state.transition(.reset)
                    return
                }
                await self.begin(globalRect: result.globalRect, screen: screen)
            }
        }
    }

    private func stripScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
    }

    /// Start the engine for `globalRect` (nil = full screen) on `screen`.
    private func begin(globalRect: CGRect?, screen: NSScreen) async {
        let config = settings.recording
        guard let displayID = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            state.transition(.reset)
            return
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID })
            else { throw RecorderError.writerFailed }

            let scale = screen.backingScaleFactor
            // sourceRect: display-relative, top-left origin, points.
            var sourceRect: CGRect?
            var pixelSize = CGSize(width: CGFloat(display.width) * scale,
                                   height: CGFloat(display.height) * scale)
            if let globalRect {
                let local = CaptureGeometry.pixelRect(forGlobalRect: globalRect,
                                                      inDisplayFrame: screen.frame,
                                                      scale: 1)   // points, top-left
                sourceRect = local
                pixelSize = CGSize(width: local.width * scale, height: local.height * scale)
            }

            // Even pixel dimensions keep H.264 encoders happy.
            pixelSize.width = (pixelSize.width / 2).rounded(.down) * 2
            pixelSize.height = (pixelSize.height / 2).rounded(.down) * 2

            if config.microphone {
                _ = await MicCapturer.ensurePermission()
            }
            if config.camera, await CameraBubbleController.ensurePermission() {
                bubble.show(near: globalRect ?? screen.frame, on: screen,
                            diameter: config.cameraSize.diameter)
            }
            if config.clickHighlights { clicks.start(on: screen) }
            if config.keystrokeOverlay { keystrokes.start(on: screen) }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let ext = "mp4"   // GIF converts after the fact
            let name = FileNamer.fileName(for: Date(), ext: ext, prefix: "Recording")
            let url = config.format == .gif
                ? FileManager.default.temporaryDirectory.appendingPathComponent(name)
                : settings.saveDirectory.appendingPathComponent(name)

            try await recorder.start(filter: filter, pixelSize: pixelSize,
                                     sourceRect: sourceRect, config: config, outputURL: url)
            state.transition(.begin(Date()))
            startTimer()
            notify()
        } catch {
            tearDownPanels()
            state.transition(.reset)
            hud.show("Couldn't start recording", on: screen)
            notify()
        }
    }

    private func stop() async {
        guard state.transition(.finish) else { return }
        stopTimer()
        notify()
        let config = settings.recording
        do {
            let mp4 = try await recorder.stop()
            tearDownPanels()
            if config.format == .gif {
                hud.show("Converting to GIF…")
                let gifName = FileNamer.fileName(for: Date(), ext: "gif", prefix: "Recording")
                let gifURL = settings.saveDirectory.appendingPathComponent(gifName)
                do {
                    try await GIFExporter.export(mp4: mp4, to: gifURL)
                    try? FileManager.default.removeItem(at: mp4)
                    hud.show("GIF saved")
                } catch {
                    // Keep the MP4 so the recording isn't lost.
                    let mp4Name = FileNamer.fileName(for: Date(), ext: "mp4", prefix: "Recording")
                    let dest = settings.saveDirectory.appendingPathComponent(mp4Name)
                    try? FileManager.default.moveItem(at: mp4, to: dest)
                    hud.show("Saved as MP4 (GIF conversion failed)")
                }
            } else {
                hud.show("Recording saved")
            }
        } catch {
            tearDownPanels()
            hud.show("Recording failed")
        }
        state.transition(.reset)
        notify()
    }

    /// Best-effort stop for app termination. Spins the main run loop (instead of
    /// blocking on a semaphore, which would deadlock the MainActor task) so the
    /// async finalize can complete before the process exits.
    func stopForTermination() {
        guard isRecording else { return }
        var done = false
        Task { @MainActor in
            await self.stop()
            done = true
        }
        let deadline = Date().addingTimeInterval(3)
        while !done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private func streamFailed() {
        guard isRecording else { return }
        Task { await stop() }
    }

    private func tearDownPanels() {
        bubble.hide()
        clicks.stop()
        keystrokes.stop()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor [weak self] in self?.notify() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func notify() {
        onStateChange?(isRecording, state.elapsedString(now: Date()))
    }
}
```

- [ ] **Step 3:** `App/MenuBarController.swift` — recording state. Add a stored property and two methods; add a "Record Screen…"/"Stop Recording" item. In `buildMenu()`, insert after the `add("Capture Text", …)` line and before the first separator:

```swift
        recordItem = menu.addItem(withTitle: "Record Screen…",
                                  action: #selector(toggleRecording), keyEquivalent: "")
        recordItem?.target = self
        if let recordItem { actionItems[.record] = recordItem }
```

Add the property next to `actionItems`:

```swift
    private var recordItem: NSMenuItem?
```

Add an `onToggleRecording` callback property + action + state API (near `openSettings`):

```swift
    var onToggleRecording: (() -> Void)?

    @objc private func toggleRecording() { onToggleRecording?() }

    /// Red stop icon + elapsed timer while recording; normal icon otherwise.
    func setRecording(_ recording: Bool, elapsed: String?) {
        if recording {
            statusItem.button?.image = NSImage(systemSymbolName: "stop.circle.fill",
                                               accessibilityDescription: "Stop Recording")
            statusItem.button?.contentTintColor = .systemRed
            statusItem.button?.title = elapsed.map { " \($0)" } ?? ""
            statusItem.button?.imagePosition = .imageLeading
            statusItem.button?.font = .monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
            recordItem?.title = "Stop Recording"
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                               accessibilityDescription: "BetterScreenshot")
            statusItem.button?.contentTintColor = nil
            statusItem.button?.title = ""
            recordItem?.title = "Record Screen…"
        }
    }
```

- [ ] **Step 4:** `App/AppDelegate.swift`:
- Add property `private var recordingCoordinator: RecordingCoordinator!` and `import RecordingKit` is NOT needed (only the coordinator file imports it).
- In `applicationDidFinishLaunching`, right after `coordinator.editorPresenter…` block:

```swift
        recordingCoordinator = RecordingCoordinator(settings: settings)
        recordingCoordinator.onStateChange = { [weak self] recording, elapsed in
            self?.menuBar.setRecording(recording, elapsed: elapsed)
        }
```

- After `menuBar = MenuBarController(…)`:

```swift
        menuBar.onToggleRecording = { [weak self] in self?.recordingCoordinator.toggle() }
```

- In the same method, after the onboarding lines, point the recording coordinator at the setup window too:

```swift
        recordingCoordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
```

- In `applyBindings()`, add the record handler to the dictionary:

```swift
            .record:            { [weak self] in Task { @MainActor in self?.recordingCoordinator.toggle() } },
```

- In `applicationWillTerminate`, FIRST line:

```swift
        recordingCoordinator?.stopForTermination()
```

- [ ] **Step 5: Build + all tests.**

```bash
swift build && \
swift run --package-path Packages/CaptureKit CaptureKitTests && \
swift run --package-path Packages/RecordingKit RecordingKitTests
```

Expected: green across the board. (`PermissionManager`, `CaptureGeometry`, `FileNamer`, `HUDController`, `SelectionOverlayController` all already exist — only new wiring here.)

- [ ] **Step 6: Commit.**

```bash
git add -A App
git commit -m "feat(app): RecordingCoordinator + record strip + menu-bar recording state — smart ⌘⇧5 toggle"
```

---

### Task 10: Full verification, CHANGELOG, tag

- [ ] **Step 1:** All gates:

```bash
swift run --package-path Packages/CaptureKit CaptureKitTests
swift run --package-path Packages/OverlayKit OverlayKitTests
swift run --package-path Packages/EditorKit EditorKitTests
swift run --package-path Packages/RecordingKit RecordingKitTests
scripts/build-app.sh
```

All PASS + `==> Built dist/BetterScreenshot.app …`.

- [ ] **Step 2:** CHANGELOG entry at top (match existing style):

```markdown
## v2.0-recording — 2026-06-04

- **Screen recording (P2).** ⌘⇧5 is a smart toggle: press to open the record strip
  (full screen or drag an area; MP4/GIF, mic, system audio, camera toggles), press
  again to stop. Menu bar shows a red stop button with an elapsed timer.
- **MP4 + GIF output** — H.264 at 30/60 fps; GIF recordings convert automatically
  (10 fps, ≤960 px) and fall back to MP4 if conversion fails.
- **Audio** — system audio (ScreenCaptureKit) and microphone (separate track).
- **Camera bubble** — circular live webcam overlay, drag to move, two sizes.
- **Click highlights** (no extra permission) and **keystroke display**
  (Accessibility-gated, off by default).
- New Settings → Recording tab; "Start/Stop Recording" is rebindable in Shortcuts.
- Native macOS ⌘⇧5 (screenshot toolbar) is shadowed while the app runs, like ⌘⇧4.
```

- [ ] **Step 3:** Spec status line → `Status: **shipped 2026-06-04** (tag \`v2.0-recording\`; see CHANGELOG.md)`. Also update `CLAUDE.md`'s roadmap line: change `P2 recording (MP4/GIF, audio, webcam, click/keystroke viz)` to `~~P2 recording~~ (shipped v2.0)`.

- [ ] **Step 4:** Commit + tag:

```bash
git add CHANGELOG.md CLAUDE.md docs/superpowers/specs/2026-06-04-betterscreenshot-p2-recording-design.md
git commit -m "docs: CHANGELOG + shipped status for v2.0-recording"
git tag v2.0-recording
```

- [ ] **Step 5: Manual GUI checklist** (launch `dist/BetterScreenshot.app`):

1. ⌘⇧5 → strip appears bottom-center; ⌘⇧5 again cancels it; Esc-equivalent ✕ works.
2. Record Full Screen → menu-bar icon turns into red stop + ticking timer; ⌘⇧5 stops; MP4 lands in the save folder and plays (video + system audio).
3. Record Area… → drag a region → only that region is recorded.
4. GIF mode → "Converting to GIF…" HUD → looping GIF in save folder; temp MP4 gone.
5. Mic toggle on → first run prompts for mic; resulting MP4 has the mic track.
6. Camera on → bubble appears, draggable, visible IN the recording; first run prompts for camera.
7. Click highlights → clicks flash circles, visible in the recording.
8. Keystroke display toggle prompts for Accessibility; once granted, typing shows the pill (in recordings too).
9. Settings → Recording tab persists choices; strip toggles mirror + persist them.
10. Shortcuts tab shows "Start/Stop Recording ⇧⌘5"; rebinding it works; v1.4-era custom bindings survive the upgrade and record picks up ⌘⇧5.
11. Quit while recording → file is finalized (best-effort) and playable.
12. Native ⌘⇧5 screenshot toolbar does NOT appear while the app runs; it returns after quit.
```
