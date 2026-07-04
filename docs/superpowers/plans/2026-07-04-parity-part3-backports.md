# Parity Part 3 — Bug & Behavior Backports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Backport the confirmed Windows-side fixes to the macOS BetterScreenshot app: an optional auto-contrasting text-background chip in the annotation editor, clamping annotations to the image bounds while dragging, clamping the area-selection rect to the screen, and the History cap option 200→100. Two spec items are already satisfied on macOS (OCR-failure HUD, drag temp-PNG cleanup) and three are non-defects (per-frame re-raster, text-commit re-entrancy) — recorded here as verified-skips. One item (stretched-resolution capture "black bar") is hardware-gated and needs the owner's display to confirm before any change.

**Architecture:** Pure, unit-testable helpers first (TDD) — Codable back-compat for the new style field, a point/box clamp, a rect clamp — then apply them at the AppKit call sites. `AnnotationStyle` gains one optional, back-compatible field so existing persisted `editorDefaultStyle` blobs still load.

**Tech Stack:** Swift 5.9, AppKit (`NSView` editor canvas, `NSTextField`), CoreGraphics; TestKit executable-runner tests (no XCTest). Build via `scripts/build-app.sh`; tests via `scripts/test.sh` (single suite: `swift run --package-path Packages/<Pkg> <Pkg>Tests`).

**Source spec:** `docs/WINDOWS-TO-MAC-PARITY.md` Part 3 (§3.A port / §3.B verify / §3.C ignore).

**Verified current-state (recon):**
- `Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift:3-13` — `struct AnnotationStyle: Equatable, Codable` with exactly `strokeColor: RGBAColor`, `fillColor: RGBAColor`, `lineWidth: CGFloat`, `fontSize: CGFloat`; **synthesized** Codable (round-trip test in `Tests/EditorKitTests/AnnotationStyleCodableTests.swift`). No text-background field.
- `Packages/EditorKit/Sources/EditorKit/TextAnnotation.swift:11-25` — `draw()` draws only the attributed string (`.font` semibold `style.fontSize`, `.foregroundColor` = `style.strokeColor.nsColor`). No chip. `moved(by:)` adds unconditionally.
- `Packages/EditorKit/Sources/EditorKit/DocumentRenderer.swift:27` — export flatten iterates `for a in doc.annotations { a.draw() }` (no text special-case), so a chip drawn inside `TextAnnotation.draw()` renders identically live and on export.
- Editor canvas `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift`: live draw at `:157-172` draws base image + vectors (NOT a per-frame `DocumentRenderer.render`); Select-tool move at `:268-272` calls `document.move(id:by:)` with **no clamp**; shape rect at `:336-338` uses `min`/`abs` only; resize `resizedFrame` `:104-120` enforces only a 4px min. Inline text field created at `:430` (`backgroundColor = .clear`); commit at `:433-448` uses the `sender: NSTextField` (specific field — no shared-stale bug); new `TextAnnotation` created with `style` at `:447`.
- Sticky style wiring: `App/Settings/SettingsStore.swift` decodes `editorStyle` from `UserDefaults` key `editorDefaultStyle` (`:35-40`), saves via `persistEditorStyle()` (`:50-54`); `App/Capture/CaptureCoordinator.swift:29-42` injects `EditorWindowController(image:defaultStyle: settings.editorStyle)` and `onStyleChanged = { style in settings.editorStyle = style; settings.persistEditorStyle() }`; inspector edits fire `onStyleChanged?(style)` (`EditorWindowController.swift:496/503/510`).
- `App/.../SelectionOverlayController.swift:97-100` — `rectBetween` uses `min`/`abs`, no clamp; each overlay window spans `screen.frame` (`:25`), so the pointer is practically confined per screen (recon: low real-world risk).
- `Packages/CaptureKit/Sources/CaptureKit/CaptureService.swift:49-59` — `SCStreamConfiguration.width/height = Int(display.width * 2)` (logical SCDisplay size ×2), window capture `:41-43` similarly; area crop `:28-35` re-derives `scale = full.width / display.width` from the actual returned image but `CaptureGeometry.pixelRect` (`CaptureGeometry.swift:9-12`) assumes one uniform X=Y scale. **This is the hardware-gated item.**
- OCR failure feedback: `App/Capture/CaptureCoordinator.swift:86-103` already `catch { NSLog(...); hud.show("Capture Text failed", ...) }`, and empty result → `"No text found"` (`RecognitionResult.swift:17-23`). **Already handled.**

**TestKit pattern:** each `Tests/EditorKitTests/<Name>Tests.swift` exports `let <name>Tests: [TestCase]`; append `+ <name>Tests` to `runTests(...)` in `Packages/EditorKit/Tests/EditorKitTests/main.swift`. Template for rect/point math: `Tests/EditorKitTests/CropTests.swift` and `Packages/CaptureKit/Tests/CaptureKitTests/CaptureGeometryTests.swift`.

---

### Task 1: `AnnotationStyle.textBackground` — new optional field, back-compatible Codable

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift`
- Test: `Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift` (append cases)

Add `textBackground: Bool` defaulting `false`. Because existing persisted `editorDefaultStyle` JSON lacks this key, add a custom `init(from:)` that uses `decodeIfPresent(...) ?? false` so old blobs still load (synthesized decode would otherwise require the key). Keep synthesized `encode` (or write both). Off by default; sticky via the existing `editorStyle` persistence.

- [ ] **Step 1: Add failing tests**

```swift
    TestCase("defaultTextBackgroundIsFalse") { t in
        let s = AnnotationStyle(strokeColor: .init(r:1,g:0,b:0,a:1), fillColor: .init(r:0,g:0,b:0,a:0), lineWidth: 3, fontSize: 24)
        t.isFalse(s.textBackground)
    },
    TestCase("decodesLegacyJSONWithoutTextBackground") { t in
        // JSON shaped like a pre-parity persisted style (no textBackground key)
        let legacy = """
        {"strokeColor":{"r":1,"g":0,"b":0,"a":1},"fillColor":{"r":0,"g":0,"b":0,"a":0},"lineWidth":3,"fontSize":24}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: legacy)
        t.isFalse(decoded.textBackground)
        t.approxEqual(Double(decoded.fontSize), 24, tol: 0.001)
    },
    TestCase("textBackgroundRoundTrips") { t in
        var s = AnnotationStyle(strokeColor: .init(r:1,g:1,b:1,a:1), fillColor: .init(r:0,g:0,b:0,a:0), lineWidth: 3, fontSize: 24)
        s.textBackground = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AnnotationStyle.self, from: data)
        t.isTrue(back.textBackground)
    },
```
(Match the real `AnnotationStyle`/`RGBAColor` initializers — confirm field names before writing; adjust the literal initializers if `RGBAColor` uses different labels.)

- [ ] **Step 2: Register (already registered suite) + run → FAIL** (`textBackground` undefined). `swift run --package-path Packages/EditorKit EditorKitTests`.

- [ ] **Step 3: Implement** — add the property + custom decoder:

```swift
public struct AnnotationStyle: Equatable, Codable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat
    public var textBackground: Bool

    public init(strokeColor: RGBAColor, fillColor: RGBAColor, lineWidth: CGFloat, fontSize: CGFloat, textBackground: Bool = false) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.lineWidth = lineWidth
        self.fontSize = fontSize
        self.textBackground = textBackground
    }

    private enum CodingKeys: String, CodingKey { case strokeColor, fillColor, lineWidth, fontSize, textBackground }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        strokeColor = try c.decode(RGBAColor.self, forKey: .strokeColor)
        fillColor   = try c.decode(RGBAColor.self, forKey: .fillColor)
        lineWidth   = try c.decode(CGFloat.self, forKey: .lineWidth)
        fontSize    = try c.decode(CGFloat.self, forKey: .fontSize)
        textBackground = try c.decodeIfPresent(Bool.self, forKey: .textBackground) ?? false
    }
}
```
(Encoding stays synthesized. If the existing struct had a memberwise-only init used elsewhere, keep the explicit init above so all call sites still compile — search the repo for `AnnotationStyle(` and confirm.)

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift \
        Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift
git commit -m "feat(editor): add back-compat textBackground style field (parity P3)"
```

---

### Task 2: Text chip rendering (auto-contrast) + editor inspector toggle

**Files:**
- Create: `Packages/EditorKit/Sources/EditorKit/TextChip.swift` (pure chip-color decision + constants)
- Test: `Packages/EditorKit/Tests/EditorKitTests/TextChipTests.swift` + register in `main.swift`
- Modify: `Packages/EditorKit/Sources/EditorKit/TextAnnotation.swift` (draw the chip when enabled)
- Modify: `App/Editor/EditorWindowController.swift` (inspector toggle → `onStyleChanged`)

Chip color auto-contrasts to the **text color** (spec §3.A #1: dark chip behind light text, light behind dark). Decide with a pure luminance test on `style.strokeColor`.

- [ ] **Step 1: Add failing test**

```swift
import TestKit
@testable import EditorKit

let textChipTests: [TestCase] = [
    TestCase("darkChipBehindLightText") { t in
        t.isTrue(TextChip.chipIsDark(forTextLuminance: 0.9))   // light text -> dark chip
    },
    TestCase("lightChipBehindDarkText") { t in
        t.isFalse(TextChip.chipIsDark(forTextLuminance: 0.1))  // dark text -> light chip
    },
]
```

- [ ] **Step 2: Register + run → FAIL.**

- [ ] **Step 3: Implement `TextChip.swift`**

```swift
import CoreGraphics

public enum TextChip {
    public static let cornerRadius: CGFloat = 4
    public static let horizontalPadding: CGFloat = 6
    public static let verticalPadding: CGFloat = 3

    /// Light text (luminance > 0.5) gets a dark chip; dark text gets a light chip.
    public static func chipIsDark(forTextLuminance lum: Double) -> Bool { lum > 0.5 }
}
```

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Draw the chip in `TextAnnotation.draw()`** — when `style.textBackground` is true, compute the string's bounding size, inset by the padding, fill a rounded rect (`TextChip.cornerRadius`) with the chip color (near-black `#18181A` if `chipIsDark`, else near-white `#F4F4F6`), then draw the text on top. Compute text luminance from `style.strokeColor` (`0.2126r+0.7152g+0.0722b`). Guard: only when `textBackground` is set, so default output is byte-identical to today.

- [ ] **Step 6: Add the inspector toggle** in the editor. In `App/Editor/EditorWindowController.swift`, add a "Text background" checkbox to the inspector (near the color/size controls); on change set `style.textBackground` and call `onStyleChanged?(style)` (mirrors `applyStrokeColor`/`sizeChanged` at `:496/:510`). New text annotations already pick up `style` (`EditorCanvasView.swift:447`), and the chip renders live because the canvas also calls `a.draw()`.

- [ ] **Step 7: Build + verify.** `scripts/build-app.sh`. Manually: annotate text with a light color over a dark image → chip appears dark; toggle off → no chip; the choice persists across editor sessions (sticky). Copy/Save/Stack export shows the same chip (DocumentRenderer path).

- [ ] **Step 8: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/TextChip.swift \
        Packages/EditorKit/Tests/EditorKitTests/TextChipTests.swift \
        Packages/EditorKit/Tests/EditorKitTests/main.swift \
        Packages/EditorKit/Sources/EditorKit/TextAnnotation.swift \
        App/Editor/EditorWindowController.swift
git commit -m "feat(editor): optional auto-contrast text background chip (parity P3)"
```

---

### Task 3: Clamp annotation drags to the image bounds

**Files:**
- Create: `Packages/EditorKit/Sources/EditorKit/EditorBoundsClamp.swift`
- Test: `Packages/EditorKit/Tests/EditorKitTests/EditorBoundsClampTests.swift` + register
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift` (drag/move path)

Spec §3.B #8: clamp the drag pointer to `[0,imgW]×[0,imgH]` and keep a moved selection's bounding box inside the image.

- [ ] **Step 1: Add failing tests**

```swift
import TestKit
import CoreGraphics
@testable import EditorKit

let editorBoundsClampTests: [TestCase] = [
    TestCase("pointClampInside") { t in
        t.equal(EditorBoundsClamp.point(CGPoint(x: 50, y: 60), into: CGSize(width: 100, height: 100)), CGPoint(x: 50, y: 60))
    },
    TestCase("pointClampOutside") { t in
        t.equal(EditorBoundsClamp.point(CGPoint(x: -5, y: 130), into: CGSize(width: 100, height: 100)), CGPoint(x: 0, y: 100))
    },
    TestCase("boxTranslatedToStayInside") { t in
        // box hanging off the right/top is pushed back in, size preserved
        let b = EditorBoundsClamp.box(CGRect(x: 90, y: 90, width: 30, height: 30), into: CGSize(width: 100, height: 100))
        t.equal(b, CGRect(x: 70, y: 70, width: 30, height: 30))
    },
    TestCase("boxLargerThanImagePinsToOrigin") { t in
        let b = EditorBoundsClamp.box(CGRect(x: -50, y: -50, width: 200, height: 200), into: CGSize(width: 100, height: 100))
        t.equal(b, CGRect(x: 0, y: 0, width: 200, height: 200))
    },
]
```

- [ ] **Step 2: Register + run → FAIL.**

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

public enum EditorBoundsClamp {
    public static func point(_ p: CGPoint, into size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), size.width), y: min(max(p.y, 0), size.height))
    }

    /// Translate (not shrink) a box so it stays within [0,w]x[0,h]; if larger than the image, pin origin to 0.
    public static func box(_ r: CGRect, into size: CGSize) -> CGRect {
        var x = r.origin.x, y = r.origin.y
        if r.width <= size.width { x = min(max(x, 0), size.width - r.width) } else { x = 0 }
        if r.height <= size.height { y = min(max(y, 0), size.height - r.height) } else { y = 0 }
        return CGRect(x: x, y: y, width: r.width, height: r.height)
    }
}
```

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Apply in `EditorCanvasView`.** At the start of `mouseDragged` clamp the current image-space point `p` via `EditorBoundsClamp.point(p, into: imageSize)` before it feeds shape rects. For the Select-tool move branch (`:268-272`): compute the selection's combined bounding box, clamp it with `EditorBoundsClamp.box(...)`, and derive the effective delta from the clamped box so the whole selection stays on-canvas. Use the image pixel size the canvas already knows (from `baseNSImage`/document). Keep the 4px min-size resize behavior unchanged.

- [ ] **Step 6: Build + verify.** `scripts/build-app.sh`. Manually: drag a shape/text hard against each edge → it stops at the image boundary and is not clipped on flatten.

- [ ] **Step 7: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/EditorBoundsClamp.swift \
        Packages/EditorKit/Tests/EditorKitTests/EditorBoundsClampTests.swift \
        Packages/EditorKit/Tests/EditorKitTests/main.swift \
        Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift
git commit -m "fix(editor): clamp annotation drags to image bounds (parity P3)"
```

---

### Task 4: Clamp the area-selection rect to the screen (defensive)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/SelectionClamp.swift` (pure)
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/SelectionClampTests.swift` + register
- Modify: `App/.../SelectionOverlayController.swift` (after building the global selection rect)

Spec §3.B #11. Low real-world risk (overlay confines the pointer per screen) but cheap and defensive.

- [ ] **Step 1: Add failing test**

```swift
import TestKit
import CoreGraphics
@testable import CaptureKit

let selectionClampTests: [TestCase] = [
    TestCase("insideUnchanged") { t in
        let r = CGRect(x: 10, y: 10, width: 50, height: 50)
        t.equal(SelectionClamp.clamp(r, to: CGRect(x: 0, y: 0, width: 100, height: 100)), r)
    },
    TestCase("overflowClipped") { t in
        let r = CGRect(x: 80, y: 80, width: 50, height: 50)
        t.equal(SelectionClamp.clamp(r, to: CGRect(x: 0, y: 0, width: 100, height: 100)),
                CGRect(x: 80, y: 80, width: 20, height: 20))
    },
]
```

- [ ] **Step 2: Register + run → FAIL.** `swift run --package-path Packages/CaptureKit CaptureKitTests`.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

public enum SelectionClamp {
    public static func clamp(_ r: CGRect, to bounds: CGRect) -> CGRect { r.intersection(bounds) }
}
```

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Apply** in `SelectionOverlayController` where the final global selection rect is produced (after `rectBetween` + global conversion, ~`:88-90`): `let clamped = SelectionClamp.clamp(globalRect, to: screen.frame)` and use `clamped` for the capture. Do not alter the live drawing rect (only the committed capture rect) unless trivial.

- [ ] **Step 6: Build + verify.** `scripts/build-app.sh`. Fast-drag toward a screen edge → capture never exceeds the screen.

- [ ] **Step 7: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/SelectionClamp.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/SelectionClampTests.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/main.swift \
        App/*/SelectionOverlayController.swift
git commit -m "fix(capture): clamp area-selection rect to screen bounds (parity P3)"
```

---

### Task 5: History cap option 200 → 100

**Files:**
- Modify: `App/Settings/SettingsView.swift:84-89` (the "Keep last" `Picker`)

Spec §3.A #5. The model (`CaptureSettings.historyCap`) has no validation, so this is purely the UI option value. **If Part 1 (Settings JVoice revamp) is executed first, it already rebuilds this control with 10/50/100 — then this task is a no-op; verify and skip.** Otherwise change the `Text("200 items").tag(200)` entry to `Text("100 items").tag(100)`.

- [ ] **Step 1:** Change the third `Picker` option from `200` to `100` (both label and `.tag`).
- [ ] **Step 2: Build + verify.** `scripts/build-app.sh`; open Settings → the option reads 10/50/100; selecting 100 persists (reopen shows it stuck).
- [ ] **Step 3: Commit**

```bash
git add App/Settings/SettingsView.swift
git commit -m "chore(settings): history cap option 200 -> 100 (parity P3)"
```

---

### Task 6: Stretched-resolution capture "black bar" — investigate, OWNER-GATED

**Files:** investigation only in this plan — **do not change core capture geometry without owner confirmation on the stretched display.**

Spec §3.B #10. Recon: `CaptureService.swift:49-59` requests `SCStreamConfiguration` dims from the **logical** `SCDisplay.width/height × 2`; area crop re-derives a single uniform `scale` from the actual returned image (`:28-35`) but `CaptureGeometry.pixelRect` (`CaptureGeometry.swift:9-12`) can't represent different X vs Y scales. On a stretched/non-native scanout the returned pixel buffer's aspect can differ from the requested logical frame → potential letterbox/black-bar. **This is core capture; a wrong change breaks all capture. It must be verified on the owner's stretched-resolution rig first.**

- [ ] **Step 1: Reproduce (owner hardware).** On the stretched-resolution display, capture full-screen and an area; inspect the saved PNG dimensions vs. the actual framebuffer. Confirm whether a black bar / letterbox actually appears and whether `SCScreenshotManager` returns a buffer whose aspect ≠ `display.width:display.height`.
- [ ] **Step 2: If reproduced,** design the minimal fix: derive output dims and per-axis scale from the **actual returned `CGImage`** (`full.width`/`full.height`) rather than `SCDisplay.width/height`, and extend `pixelRect` to take independent `scaleX`/`scaleY` (add a new pure helper + tests alongside `CaptureGeometryTests`, leaving the existing uniform path intact). Keep it behind the confirmed repro so non-stretched setups are byte-identical.
- [ ] **Step 3: If NOT reproduced,** record "macOS immune (ScreenCaptureKit returns the true buffer)" in the plan and skip — no change.

**Do not commit a speculative capture-geometry change.** Bring the repro result back to the owner before merging anything here.

---

### Verified skips (no task — recorded for completeness)
- **§3.B #9 per-frame re-raster:** macOS draws vectors live (`EditorCanvasView.swift:157-172`), flattens only on export. Not a defect. Skip.
- **§3.B #12 text-commit re-entrancy:** commit uses the specific `sender: NSTextField` (`:433-448`), not a shared/stale field. Not present. Skip.
- **§3.A #4 drag temp-PNG leak:** macOS writes the temp PNG lazily on drag and `DraggableImageView` deletes it +300s; no leak when dismissed without a drag. Already handled (see Part 2 Task 8). Skip.
- **§3.A #7 Capture Text failure feedback:** macOS already shows a "Capture Text failed" HUD and "No text found" for empty results. Already handled. Skip.
- **§3.C:** Windows-only (WPF/Win32/ClearType/DPI/ffmpeg/dev-tooling) — intentionally not ported.

## Verification checklist (Part 3)
- [ ] `scripts/test.sh` green incl. new `AnnotationStyleCodable` (legacy-JSON) , `TextChip`, `EditorBoundsClamp`, `SelectionClamp` tests.
- [ ] `scripts/build-app.sh` clean.
- [ ] Text chip toggles on/off, auto-contrasts, is sticky, and appears on export.
- [ ] Annotations can't be dragged off-canvas; area selection can't exceed the screen.
- [ ] History cap option reads 10/50/100.
- [ ] Black-bar item: repro result reported to owner (no speculative commit).
