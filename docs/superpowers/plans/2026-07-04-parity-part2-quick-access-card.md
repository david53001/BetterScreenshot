# Parity Part 2 — Quick Access Card (full-bleed + auto-contrast + variable stack) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the macOS post-capture Quick Access overlay to match the Windows port: the captured image fills the rounded card edge-to-edge, action buttons float over the bottom on a tone-matched scrim with glyphs that auto-flip black/white for legibility, cards stack by their actual (aspect-derived) height, and the persisted `overlayAutoDismissSeconds` field finally drives an auto-dismiss timer that pauses on hover.

**Architecture:** Build the pure, unit-testable logic first (TDD): `OverlayDismissScale` (slider↔seconds mapping, shared with Part 1), `QuickAccessContrast` (bottom-strip luminance → light/dark control palette), a card-sizing helper, and a variable-height stacking positioner. Then rework the AppKit `QuickAccessOverlayController` (full-bleed CALayer aspect-fill, rounded-clip container, overlaid chromeless buttons, scrim, auto-dismiss + hover-pause) and `QuickAccessStackController`, and stop the two coordinators hard-coding `CGSize(220,168)`.

**Tech Stack:** Swift 5.9, AppKit (`NSPanel`, `CALayer`, `NSTrackingArea`, `CAGradientLayer`), CoreGraphics; TestKit executable-runner tests (no XCTest). Build via `scripts/build-app.sh`; tests via `scripts/test.sh`.

**Source spec:** `docs/WINDOWS-TO-MAC-PARITY.md` Part 2 (and §2.10 "Key numbers"). All exact constants below are transcribed from it; the spec is on this branch if you need the surrounding rationale.

**Verified current-state (recon):**
- `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift` — `public final class QuickAccessOverlayController: NSObject`; fixed `NSSize(220,168)` at line 63; letterboxed `DraggableImageView` at `(10,46,200×112)`, `.scaleProportionallyUpOrDown`; button row is a centered `NSStackView` (`iconButton(...)` width-36 `.rounded` NSButtons) at `y=8`; `present(image:at:kind:actions:)` (line 58); `dismiss(reason:)`; `move(to:)`; `onDismissed`. No contrast/scrim/timer. Old tracking-area crash noted at lines 42-45.
- `QuickAccessActions` struct: `onCopy,onSave,onAnnotate,onPin,onOpen,onReveal: () -> Void`, `fileURLForDrag: () -> URL?`. No `onClose` (Close is internal → `dismiss(reason: .closed)`).
- `DismissReason: Equatable { case closed, evicted, actionTaken }`.
- `QuickAccessStackController` — `maxCount = 3`; `present(image:kind:actions:onDismissed:originForIndex:)`; injects `originForIndex: (Int) -> CGPoint`; evicts oldest via `.evicted`; `restack()` calls `move(to: originForIndex(i))`. No per-card size knowledge.
- `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift` — `public enum OverlayPositioner`; `stackedOrigin(corner:overlaySize:screenFrame:margin:index:spacing:=12)` offsets each index by `overlaySize.height + spacing`. Tests in `Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift` (array `overlayPositionerTests`, registered in that dir's `main.swift`).
- `App/Capture/CaptureCoordinator.swift:133-158` `presentOverlay(_:sourceRect:historyID:)` — closure hard-codes `overlaySize: CGSize(width:220,height:168)`, `margin: 24`, `corner = settings.settings.overlayCorner`, `frame = screen.visibleFrame`; drag URL via `TempImageWriter.writePNG(image, fileName:)`.
- `App/Recording/RecordingCoordinator.swift:376-401` `presentCard(for:image:historyID:)` — identical hard-coded `CGSize(220,168)` at lines 396-400; `kind: .recording`; `fileURLForDrag: { url }` (real saved file).
- `DraggableImageView` (`Packages/OverlayKit/Sources/OverlayKit/DraggableImageView.swift`): `fileURLProvider: (() -> URL?)?`, `onDragEnded: ((Bool) -> Void)?`, `deletesFileAfterDrag` (deletes temp dir +300s), 4pt drag threshold.

**TestKit pattern:** each `Tests/<Pkg>Tests/<Name>Tests.swift` exports `let <name>Tests: [TestCase] = [ TestCase("...") { t in t.equal(...) } ]`; append `+ <name>Tests` to the `runTests(...)` call in that dir's `main.swift`. Run one suite: `swift run --package-path Packages/<Pkg> <Pkg>Tests`.

---

### Task 1: `OverlayDismissScale` — slider position ↔ seconds (pure, shared with Part 1)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/OverlayDismissScaleTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift` (register suite)

Mapping (spec §2.6/§2.9): `MinSeconds=2`, `MaxSeconds=30`, `NeverSeconds=0`, `NeverPosition=31`. Slider positions 2…30 = that many seconds; position ≥31 = "Never" (persists as 0). `label(0)="Never"`, else `"{n}s"`.

- [ ] **Step 1: Write the failing test**

```swift
import TestKit
@testable import CaptureKit

let overlayDismissScaleTests: [TestCase] = [
    TestCase("positionToSecondsInRange") { t in
        t.equal(OverlayDismissScale.positionToSeconds(2), 2)
        t.equal(OverlayDismissScale.positionToSeconds(6), 6)
        t.equal(OverlayDismissScale.positionToSeconds(30), 30)
    },
    TestCase("positionAtOrAboveNeverIsZero") { t in
        t.equal(OverlayDismissScale.positionToSeconds(31), 0)
        t.equal(OverlayDismissScale.positionToSeconds(99), 0)
    },
    TestCase("secondsToPositionRoundTrips") { t in
        t.equal(OverlayDismissScale.secondsToPosition(2), 2)
        t.equal(OverlayDismissScale.secondsToPosition(30), 30)
        t.equal(OverlayDismissScale.secondsToPosition(0), 31)   // Never
    },
    TestCase("secondsToPositionClampsOutOfRange") { t in
        t.equal(OverlayDismissScale.secondsToPosition(1), 2)    // below min clamps up
        t.equal(OverlayDismissScale.secondsToPosition(45), 30)  // above max clamps down (still a real duration)
    },
    TestCase("labels") { t in
        t.equal(OverlayDismissScale.label(0), "Never")
        t.equal(OverlayDismissScale.label(-3), "Never")
        t.equal(OverlayDismissScale.label(6), "6s")
        t.equal(OverlayDismissScale.label(30), "30s")
    },
]
```

- [ ] **Step 2: Register + run to verify it fails**

Edit `main.swift` to add `+ overlayDismissScaleTests` inside `runTests("CaptureKitTests", ...)`.
Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: FAIL — `OverlayDismissScale` undefined.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Maps a monochrome auto-dismiss slider position to a persisted seconds value.
/// Positions 2...30 are that many seconds; position >= NeverPosition means "Never" (persisted as 0).
public enum OverlayDismissScale {
    public static let minSeconds = 2
    public static let maxSeconds = 30
    public static let neverSeconds = 0
    public static let neverPosition = 31

    public static func positionToSeconds(_ position: Int) -> Int {
        if position >= neverPosition { return neverSeconds }
        return min(max(position, minSeconds), maxSeconds)
    }

    public static func secondsToPosition(_ seconds: Int) -> Int {
        if seconds <= 0 { return neverPosition }
        return min(max(seconds, minSeconds), maxSeconds)
    }

    public static func label(_ seconds: Int) -> String {
        seconds <= 0 ? "Never" : "\(seconds)s"
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests` → all green.

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/OverlayDismissScale.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/OverlayDismissScaleTests.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/main.swift
git commit -m "feat(overlay): add OverlayDismissScale slider<->seconds mapping (parity P2)"
```

---

### Task 2: `QuickAccessContrast` — bottom-strip luminance → light/dark control palette (pure)

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessContrast.swift`
- Test: `Packages/OverlayKit/Tests/OverlayKitTests/QuickAccessContrastTests.swift`
- Modify: `Packages/OverlayKit/Tests/OverlayKitTests/main.swift`

Split per spec §2.5: a **pure** luminance/threshold + palette selector (this task), and the pixel-sampling/color-construction (Task 5, in the AppKit controller). Threshold `> 0.58` = light bg → dark controls. Rec.709 luminance `0.2126R+0.7152G+0.0722B`. Palette (ARGB, spec §2.5 table):

| | Light bg → DARK controls | Dark bg → LIGHT controls |
|---|---|---|
| Glyph | `#FF18181A` | `#FFF4F4F6` |
| Hover pill | `#24000000` | `#2BFFFFFF` |
| Pressed pill | `#3D000000` | `#45FFFFFF` |
| Scrim tone | white | black |

Model the pure output as an `enum ContrastTone { case dark, light }` plus a struct of the four ARGB `UInt32` values so AppKit can build `NSColor`/`CGColor` from them without the pure module importing AppKit.

- [ ] **Step 1: Write the failing test**

```swift
import TestKit
@testable import OverlayKit

let quickAccessContrastTests: [TestCase] = [
    TestCase("averageLuminanceWhiteAndBlack") { t in
        // RGBA bytes, 2 opaque white pixels
        let white: [UInt8] = [255,255,255,255, 255,255,255,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: white, pixelCount: 2), 1.0, tol: 0.001)
        let black: [UInt8] = [0,0,0,255, 0,0,0,255]
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: black, pixelCount: 2), 0.0, tol: 0.001)
    },
    TestCase("emptyBufferIsZero") { t in
        t.approxEqual(QuickAccessContrast.averageLuminance(rgba: [], pixelCount: 0), 0.0, tol: 0.001)
    },
    TestCase("toneThresholdBoundary") { t in
        t.equal(QuickAccessContrast.tone(forLuminance: 0.57), .light)  // dark bg -> light controls
        t.equal(QuickAccessContrast.tone(forLuminance: 0.58), .light)  // strictly > 0.58 required
        t.equal(QuickAccessContrast.tone(forLuminance: 0.59), .dark)   // light bg -> dark controls
    },
    TestCase("paletteForTone") { t in
        let d = QuickAccessContrast.palette(for: .dark)
        t.equal(d.glyphARGB, 0xFF18181A)
        t.equal(d.hoverARGB, 0x24000000)
        t.equal(d.pressedARGB, 0x3D000000)
        t.isTrue(d.scrimIsWhite)
        let l = QuickAccessContrast.palette(for: .light)
        t.equal(l.glyphARGB, 0xFFF4F4F6)
        t.equal(l.hoverARGB, 0x2BFFFFFF)
        t.equal(l.pressedARGB, 0x45FFFFFF)
        t.isFalse(l.scrimIsWhite)
    },
]
```

- [ ] **Step 2: Register + run to verify it fails**

Add `quickAccessContrastTests` to `runTests(...)` in `Packages/OverlayKit/Tests/OverlayKitTests/main.swift` (currently `runTests("OverlayKitTests", pinGeometryTests)` → `... pinGeometryTests + quickAccessContrastTests`).
Run: `swift run --package-path Packages/OverlayKit OverlayKitTests` → FAIL (undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

public enum ContrastTone: Equatable { case dark, light }

public struct ContrastPalette: Equatable {
    public let glyphARGB: UInt32
    public let hoverARGB: UInt32
    public let pressedARGB: UInt32
    public let scrimIsWhite: Bool
}

public enum QuickAccessContrast {
    public static let lightThreshold = 0.58

    /// Mean Rec.709 relative luminance (0...1) of an RGBA byte buffer; alpha ignored. 0 if empty.
    public static func averageLuminance(rgba: [UInt8], pixelCount: Int) -> Double {
        guard pixelCount > 0, rgba.count >= pixelCount * 4 else { return 0 }
        var sum = 0.0
        for i in 0..<pixelCount {
            let r = Double(rgba[i*4 + 0]) / 255.0
            let g = Double(rgba[i*4 + 1]) / 255.0
            let b = Double(rgba[i*4 + 2]) / 255.0
            sum += 0.2126*r + 0.7152*g + 0.0722*b
        }
        return sum / Double(pixelCount)
    }

    /// A light strip (> 0.58) wants DARK controls; otherwise LIGHT controls.
    public static func tone(forLuminance avg: Double) -> ContrastTone {
        avg > lightThreshold ? .dark : .light
    }

    public static func palette(for tone: ContrastTone) -> ContrastPalette {
        switch tone {
        case .dark:  return ContrastPalette(glyphARGB: 0xFF18181A, hoverARGB: 0x24000000, pressedARGB: 0x3D000000, scrimIsWhite: true)
        case .light: return ContrastPalette(glyphARGB: 0xFFF4F4F6, hoverARGB: 0x2BFFFFFF, pressedARGB: 0x45FFFFFF, scrimIsWhite: false)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** → `swift run --package-path Packages/OverlayKit OverlayKitTests` green.

- [ ] **Step 5: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/QuickAccessContrast.swift \
        Packages/OverlayKit/Tests/OverlayKitTests/QuickAccessContrastTests.swift \
        Packages/OverlayKit/Tests/OverlayKitTests/main.swift
git commit -m "feat(overlay): add QuickAccessContrast luminance+palette (parity P2)"
```

---

### Task 3: Card sizing helper — aspect-derived full-bleed height (pure)

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessContrast.swift` (add sizing fn to keep the pure overlay-math together) — OR create `Packages/OverlayKit/Sources/OverlayKit/QuickAccessCardSize.swift`
- Test: `Packages/OverlayKit/Tests/OverlayKitTests/QuickAccessContrastTests.swift` (append cases)

Spec §2.3: width fixed **210**; `contentHeight = clamp(210/aspect, 150, 280)`; aspect `= w/h` (fallback `16/9` if `h<=0`).

- [ ] **Step 1: Add failing tests**

```swift
    TestCase("cardSizeSquareImage") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 1000, imagePixelHeight: 1000)
        t.approxEqual(Double(s.width), 210, tol: 0.001)
        t.approxEqual(Double(s.height), 210, tol: 0.001)  // 210/1.0, within [150,280]
    },
    TestCase("cardSizeWideClampsToFloor") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 2000, imagePixelHeight: 500) // aspect 4 -> 52.5
        t.approxEqual(Double(s.height), 150, tol: 0.001)
    },
    TestCase("cardSizeTallClampsToCeiling") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 500, imagePixelHeight: 2000) // aspect .25 -> 840
        t.approxEqual(Double(s.height), 280, tol: 0.001)
    },
    TestCase("cardSizeZeroHeightFallback") { t in
        let s = QuickAccessCardSize.contentSize(imagePixelWidth: 1600, imagePixelHeight: 0) // -> 16/9 aspect
        t.approxEqual(Double(s.height), min(max(210.0/(16.0/9.0),150),280), tol: 0.001)
    },
]
```
(Insert before the closing `]` of `quickAccessContrastTests`.)

- [ ] **Step 2: Run → FAIL** (`QuickAccessCardSize` undefined).

- [ ] **Step 3: Implement** (new file `QuickAccessCardSize.swift`)

```swift
import CoreGraphics

public enum QuickAccessCardSize {
    public static let width: CGFloat = 210
    public static let minHeight: CGFloat = 150
    public static let maxHeight: CGFloat = 280

    public static func contentSize(imagePixelWidth w: Int, imagePixelHeight h: Int) -> CGSize {
        let aspect: CGFloat = h > 0 ? CGFloat(w) / CGFloat(h) : 16.0/9.0
        let raw = width / (aspect == 0 ? 16.0/9.0 : aspect)
        let clamped = min(max(raw, minHeight), maxHeight)
        return CGSize(width: width, height: clamped)
    }
}
```

- [ ] **Step 4: Run → PASS.**

- [ ] **Step 5: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/QuickAccessCardSize.swift \
        Packages/OverlayKit/Tests/OverlayKitTests/QuickAccessContrastTests.swift
git commit -m "feat(overlay): aspect-derived full-bleed card sizing (parity P2)"
```

---

### Task 4: Variable-height stacking positioner (pure, additive — keep the fixed-step one)

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift` (add a NEW function; do not change `stackedOrigin` or its tests)
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift` (append cases)

Spec §2.8 option (b): add `stackedOrigins(corner:heights:screenFrame:margin:spacing:)` returning one origin per card, where the cursor advances by each card's own height. Newest = index 0, nearest the corner; bottom corners advance upward, top corners downward. Width per card also varies, but width is fixed (210) in practice; accept per-card `sizes` to be safe.

- [ ] **Step 1: Add failing tests**

```swift
    TestCase("variableStackBottomRightPacksByActualHeight") { t in
        let f = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sizes = [CGSize(width: 210, height: 150), CGSize(width: 210, height: 280), CGSize(width: 210, height: 200)]
        let os = OverlayPositioner.stackedOrigins(corner: .bottomRight, sizes: sizes, screenFrame: f, margin: 24, spacing: 12)
        t.equal(os.count, 3)
        // index 0 newest, at the corner: x = right - w - margin; y = bottom + margin
        t.approxEqual(Double(os[0].x), Double(1000 - 210 - 24), tol: 0.001)
        t.approxEqual(Double(os[0].y), 24, tol: 0.001)
        // index1 sits above index0 by index0.height + spacing
        t.approxEqual(Double(os[1].y), Double(24 + 150 + 12), tol: 0.001)
        // index2 sits above index1 by index1.height + spacing
        t.approxEqual(Double(os[2].y), Double(24 + 150 + 12 + 280 + 12), tol: 0.001)
    },
    TestCase("variableStackTopLeftStacksDownward") { t in
        let f = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let sizes = [CGSize(width: 210, height: 150), CGSize(width: 210, height: 200)]
        let os = OverlayPositioner.stackedOrigins(corner: .topLeft, sizes: sizes, screenFrame: f, margin: 24, spacing: 12)
        t.approxEqual(Double(os[0].x), 24, tol: 0.001)
        // top corner: index0 top-most; origin.y is the card's bottom-left in Cocoa space = top - height
        t.approxEqual(Double(os[0].y), Double(800 - 24 - 150), tol: 0.001)
        t.approxEqual(Double(os[1].y), Double(800 - 24 - 150 - 12 - 200), tol: 0.001)
    },
]
```
(Insert before the closing `]` of `overlayPositionerTests`.)

- [ ] **Step 2: Run → FAIL** (`stackedOrigins` undefined). `swift run --package-path Packages/CaptureKit CaptureKitTests`.

- [ ] **Step 3: Implement** (append to `OverlayPositioner`)

```swift
    /// Variable-height cumulative stacking. sizes[0] is the newest card (nearest the corner).
    /// Bottom corners stack upward; top corners stack downward. Cocoa bottom-left origins.
    public static func stackedOrigins(corner: OverlayCorner, sizes: [CGSize],
                                      screenFrame: CGRect, margin: CGFloat,
                                      spacing: CGFloat = 12) -> [CGPoint] {
        let isRight = (corner == .topRight || corner == .bottomRight)
        let isBottom = (corner == .bottomLeft || corner == .bottomRight)
        var origins: [CGPoint] = []
        var advance: CGFloat = 0   // cumulative height + spacing consumed toward center
        for size in sizes {
            let x = isRight ? screenFrame.maxX - size.width - margin
                            : screenFrame.minX + margin
            let y: CGFloat
            if isBottom {
                y = screenFrame.minY + margin + advance
            } else {
                y = screenFrame.maxY - margin - size.height - advance
            }
            origins.append(CGPoint(x: x, y: y))
            advance += size.height + spacing
        }
        return origins
    }
```

- [ ] **Step 4: Run → PASS.** Confirm the pre-existing `overlayPositionerTests` fixed-step cases still pass.

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift
git commit -m "feat(overlay): variable-height stacking positioner (parity P2)"
```

---

### Task 5: Full-bleed card + overlaid auto-contrast buttons + scrim (AppKit rework)

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`

This is a view rebuild; no unit test — verify by build + by-eye (spec §2.10 checklist). Keep the existing public API surface (`present(image:at:kind:actions:)`, `dismiss`, `move`, `onDismissed`, `QuickAccessActions`, `QuickAccessKind`, `DismissReason`) so the stack controller/coordinators keep compiling; ADD a `contentSize`/aspect parameter (see below).

- [ ] **Step 1: Change panel sizing to aspect-derived.** Replace the fixed `NSSize(220,168)` (line ~63) with a size computed from the image's pixel size via `QuickAccessCardSize.contentSize(imagePixelWidth:imagePixelHeight:)`. Derive pixels from the `NSImage`'s CGImage (`image.cgImage(forProposedRect:context:hints:)`), fallback to `image.size`. Store `contentSize` on the controller so the stack controller can read it back (add `public private(set) var contentSize: CGSize`).

- [ ] **Step 2: Rebuild the container as a rounded-clipped, layer-backed view.** One `container` view, `wantsLayer = true`, `layer.cornerRadius = 14`, `layer.masksToBounds = true` (spec §2.3 — clipping the container is what clips the overlaid children). Panel keeps `hasShadow = true`. Optional 1px top hairline `#26FFFFFF`.

- [ ] **Step 3: Full-bleed image via aspect-fill CALayer.** Replace the letterboxed `DraggableImageView(frame:(10,46,200×112))` + `.scaleProportionallyUpOrDown` with the image hosted to fill the whole container: set the `DraggableImageView` frame to the container bounds and back it with a layer using `contentsGravity = .resizeAspectFill` + `masksToBounds = true` (or draw aspect-fill). Keep it a `DraggableImageView` so drag-to-export still works (Task 8/spec §2.7). Remove the recording blue tint / rounded-6 thumbnail insets.

- [ ] **Step 4: Sample luminance + pick tone.** Add a private `sampleBottomLuminance(_ cg: CGImage) -> Double` implementing spec §2.5: crop bottom 30% strip (`stripH = max(1, Int(h*0.30))`), downscale so longest side ≤ 48px, read RGBA bytes into `[UInt8]` (respect `bytesPerRow` stride padding — copy row-by-row into a tight `pixelCount*4` buffer), call `QuickAccessContrast.averageLuminance(rgba:pixelCount:)`; any failure → return 0.0. Then `let tone = QuickAccessContrast.tone(forLuminance:)` and `let palette = QuickAccessContrast.palette(for: tone)`. Build `NSColor`s from the ARGB `UInt32`s via a small helper `NSColor(argb:)`.

- [ ] **Step 5: Overlaid chromeless button row.** Keep SF Symbols + order by kind (screenshot: Copy→Edit→Pin→Save→Close; recording: Copy→Open→Reveal→Close). Render each as a template image tinted with `palette.glyph`. Replace the `.rounded` NSButtons with a chromeless layer-backed button (`box 32×30`, glyph `17×17`, gap `4`, pill radius `7`): transparent resting, hover fill = `palette.hover`, pressed = `palette.pressed`. Anchor the row centered, `9pt` up from the bottom. Dismiss semantics unchanged (Copy stays; Edit/Pin/Save/Open/Reveal → `.actionTaken`; Close → `.closed`).

- [ ] **Step 6: Scrim.** Insert a `CAGradientLayer` bottom-anchored, over image, under buttons, `hitTest` ignored. Height `= min(64, contentHeight * 0.42)`. Tone per `palette.scrimIsWhite`. Vertical alpha stops (transparent top → opaque bottom in Cocoa bottom-left space): `0.0→0x00`, `0.5→0x2E`, `1.0→0x8C`.

- [ ] **Step 7: Build.**

Run: `scripts/build-app.sh`
Expected: builds clean; `dist/BetterScreenshot.app` assembled.

- [ ] **Step 8: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift
git commit -m "feat(overlay): full-bleed card, auto-contrast overlaid buttons, scrim (parity P2)"
```

---

### Task 6: Auto-dismiss timer + hover-pause (fix the old tracking-area crash)

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`

Spec §2.9. The controller is already an `NSObject`, so it can own an `NSTrackingArea`. Implement carefully — this is the exact path that crashed before (`doesNotRecognizeSelector: mouseEntered:`).

- [ ] **Step 1:** Add `present(...)` parameter `autoDismissSeconds: Int` (default so callers not yet updated still compile — but Task 7 updates the stack controller; keep the controller default at `0` = persistent). Store it.

- [ ] **Step 2:** After presenting: if `seconds <= 0` → no timer (persistent). Else start a one-shot `Timer.scheduledTimer(withTimeInterval: Double(seconds), repeats: false)` → `self.dismiss(reason: .closed)`. Store the timer; invalidate it in `dismiss` and before restarting.

- [ ] **Step 3: Hover-pause via a tracking-area-owning NSView subclass** (safer than owner: self across the panel). Add a small `private final class HoverView: NSView` with `onEnter`/`onExit` closures that overrides `mouseEntered(with:)`/`mouseExited(with:)` and, in `updateTrackingAreas()`, installs a single `NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)`. Add a full-size `HoverView` on top of the container (below buttons is fine — enter/exit still fire for the panel). On enter → invalidate timer; on exit → restart the full countdown (`interval = seconds`). This guarantees the owner responds to `mouseEntered:`/`mouseExited:`.

- [ ] **Step 4: Build + smoke-verify.**

Run: `scripts/build-app.sh`. Then manually: take a screenshot, confirm the card auto-dismisses after the configured delay and the countdown **pauses while hovering** and **restarts on exit** — and does NOT crash (this is the regression-prone path). Auto-dismiss uses `.closed` so "Restore Recently Closed" still works.

- [ ] **Step 5: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift
git commit -m "feat(overlay): auto-dismiss timer with hover-pause (parity P2)"
```

---

### Task 7: Variable-height stacking in the controller + wire coordinators

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift`
- Modify: `App/Capture/CaptureCoordinator.swift:133-158`
- Modify: `App/Recording/RecordingCoordinator.swift:376-401`

Spec §2.8. Move positioning into the stack controller so it can read each live card's actual `contentSize` (preferred option a), OR keep the closure but feed it real heights. This plan uses option (a)-lite: the stack controller computes origins from its entries' `contentSize` using `OverlayPositioner.stackedOrigins`, driven by an injected `corner` + `screenFrame` + `margin` (no more per-index closure that assumes uniform size).

- [ ] **Step 1:** Change `QuickAccessStackController.present(...)` signature from `originForIndex: (Int) -> CGPoint` to explicit layout inputs:
```swift
public func present(image: NSImage, kind: QuickAccessKind = .screenshot,
                    actions: QuickAccessActions, autoDismissSeconds: Int,
                    corner: OverlayCorner, screenFrame: CGRect, margin: CGFloat = 24,
                    onDismissed: ((DismissReason) -> Void)? = nil)
```
Store `corner/screenFrame/margin`. In `restack()`, build `sizes = entries.map { $0.contentSize }` and `origins = OverlayPositioner.stackedOrigins(corner:sizes:screenFrame:margin:spacing:12)`, then `entries[i].move(to: origins[i])`. Present the new card first (present its controller which now knows its own `contentSize`), then `restack()`. Pass `autoDismissSeconds` through to `controller.present(...)`.
- Add `import CaptureKit` to the stack controller for `OverlayPositioner`/`OverlayCorner` if not already imported.

- [ ] **Step 2:** In `CaptureCoordinator.presentOverlay` (lines 153-157), delete the `originForIndex` closure and the hard-coded `CGSize(220,168)`; call the new `present(...)` passing `autoDismissSeconds: settings.settings.overlayAutoDismissSeconds`, `corner: settings.settings.overlayCorner`, `screenFrame: screen.visibleFrame`, `margin: 24`.

- [ ] **Step 3:** In `RecordingCoordinator.presentCard` (lines 396-400), same change: remove the `CGSize(220,168)` closure, pass `autoDismissSeconds: <settings>.overlayAutoDismissSeconds` (thread the `SettingsStore`/config through if not already available here), `corner`, `screenFrame: screen.visibleFrame`, `margin: 24`, `kind: .recording`.

- [ ] **Step 4: Build.** `scripts/build-app.sh` clean.

- [ ] **Step 5: Verify by eye.** Take 3 screenshots of different aspect ratios → cards pack tightly by actual height, newest at the corner, bottom corners stacking upward. Recording card still appears + drags the real file.

- [ ] **Step 6: Commit**

```bash
git add Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift \
        App/Capture/CaptureCoordinator.swift App/Recording/RecordingCoordinator.swift
git commit -m "feat(overlay): variable-height stacking + wire auto-dismiss seconds (parity P2)"
```

---

### Task 8: Drag temp-PNG safety net (verify already-handled)

**Files:** none expected — verification task.

Recon found `DraggableImageView` already deletes the temp dir +300s after a drag, and the temp PNG is only written lazily when a drag starts (`fileURLForDrag` provider). So a card dismissed **without** a drag writes no temp file → no leak. Spec fix #4 is effectively satisfied on macOS.

- [ ] **Step 1:** Confirm in code that `fileURLForDrag`/`TempImageWriter.writePNG` is invoked only from the drag path (not eagerly at `present`). If (and only if) a temp PNG is ever written before/without a drag, add a `+300s` cleanup on `dismiss` for `.screenshot` only (never `.recording`). Otherwise record "already handled" in the plan and skip.

- [ ] **Step 2: Commit** (only if a change was needed).

---

## Verification checklist (Part 2)
- [ ] `scripts/test.sh` green including new `OverlayDismissScale`, `QuickAccessContrast`, card-size, and variable-stack tests (white→dark glyphs, black→light glyphs, threshold boundary 0.58, empty buffer, stride padding covered in Task 5 sampling).
- [ ] `scripts/build-app.sh` clean.
- [ ] By eye (spec §2 checklist): bright window → dark glyphs; dark window → light glyphs; full-bleed rounded image (no letterbox, no separate strip); buttons overlay bottom on a faint tone-matched scrim; 3 different-aspect captures pack tightly; auto-dismiss fires + pauses on hover (no crash); drag to Finder exports + dismisses; temp file doesn't linger.

## Assumptions logged
- `QuickAccessContrast` + `QuickAccessCardSize` live in **OverlayKit** (consumed by the AppKit controller); `OverlayDismissScale` + `stackedOrigins` live in **CaptureKit** (alongside `OverlayPositioner`, and reused by Part 1's slider).
- Stacking reworked via option (a): the stack controller positions from live `contentSize`s; the fixed-step `stackedOrigin` and its tests are left intact for any other caller.
- Card width fixed at **210** and height clamp **[150,280]** per the *actual Windows code* values (spec §2.3 note), not the stale design-doc 236/[132,280].
