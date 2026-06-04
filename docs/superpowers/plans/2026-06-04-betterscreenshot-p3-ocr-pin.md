# BetterScreenshot P3 — OCR (Capture Text) + Pin to Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Capture Text (⌘⇧7: drag a region → recognized text or QR payload on the clipboard, with a HUD), Pin to Screen (floating always-on-top image panels from the Quick Access overlay, editor, and clipboard), and a Quick Access stack (up to 3 post-capture thumbnails stacked at the overlay corner instead of replacing each other).

**Architecture:** Recognition logic (pure resolver + Vision wrapper) goes in `CaptureKit` where TestKit tests already live. Pin panels, pin geometry, and the confirmation HUD go in `OverlayKit`, which gains a TestKit executable test target mirroring CaptureKit's. The app target wires the hotkey, menu items, coordinator flows, and settings. Spec: `docs/superpowers/specs/2026-06-04-betterscreenshot-p3-ocr-pin-design.md`.

**Tech Stack:** Swift 5.9 / SwiftPM (CLT-only machine — NO xcodebuild/XCTest), Vision (`VNRecognizeTextRequest`, `VNDetectBarcodesRequest`), AppKit `NSPanel`, TestKit harness.

**Verified feasibility (2026-06-04 probe, this machine):** headless `VNRecognizeTextRequest` read CG-rendered text exactly; `VNDetectBarcodesRequest` decoded a `CIQRCodeGenerator` QR exactly. The recognition tests below use the same technique and need no screen permission.

**Build/test commands:**
- Build everything: `swift build` (from repo root)
- CaptureKit tests: `swift run --package-path Packages/CaptureKit CaptureKitTests`
- OverlayKit tests (new in Task 3): `swift run --package-path Packages/OverlayKit OverlayKitTests`
- App bundle: `./scripts/build-app.sh` → `dist/BetterScreenshot.app`

---

### Task 1: RecognitionResult + RecognitionResolver (pure logic, TDD)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/RecognitionResult.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/RecognitionResolverTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/CaptureKit/Tests/CaptureKitTests/RecognitionResolverTests.swift`:

```swift
import TestKit
@testable import CaptureKit

let recognitionResolverTests: [TestCase] = [
    TestCase("qrBeatsText") { t in
        let r = RecognitionResolver.resolve(qrPayloads: ["https://example.com"],
                                            textLines: ["hello", "world"])
        t.equal(r, RecognitionResult.qr("https://example.com"))
    },
    TestCase("textLinesJoinWithNewlines") { t in
        let r = RecognitionResolver.resolve(qrPayloads: [], textLines: ["hello", "world"])
        t.equal(r, RecognitionResult.text("hello\nworld"))
    },
    TestCase("blankLinesAreDropped") { t in
        let r = RecognitionResolver.resolve(qrPayloads: [], textLines: ["", "hello", ""])
        t.equal(r, RecognitionResult.text("hello"))
    },
    TestCase("nothingIsNone") { t in
        t.equal(RecognitionResolver.resolve(qrPayloads: [], textLines: []),
                RecognitionResult.none)
        t.equal(RecognitionResolver.resolve(qrPayloads: [], textLines: ["", ""]),
                RecognitionResult.none)
    },
    TestCase("clipboardStrings") { t in
        t.equal(RecognitionResult.qr("x").clipboardString, "x")
        t.equal(RecognitionResult.text("y").clipboardString, "y")
        t.isNil(RecognitionResult.none.clipboardString)
    },
    TestCase("hudMessages") { t in
        t.equal(RecognitionResult.qr("x").hudMessage, "QR code copied")
        t.equal(RecognitionResult.text("abcd").hudMessage, "Text copied — 4 characters")
        t.equal(RecognitionResult.none.hudMessage, "No text found")
    },
]
```

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, add `recognitionResolverTests +` to the concatenation (before the closing paren):

```swift
runTests("CaptureKitTests",
    captureKitInfoTests +
    captureGeometryTests +
    imageCropperTests +
    imageEncoderTests +
    fileNamerTests +
    keyCodeTests +
    captureSettingsTests +
    overlayPositionerTests +
    tempImageWriterTests +
    recognitionResolverTests
)
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error — `cannot find 'RecognitionResolver' in scope`

- [ ] **Step 3: Write the implementation**

Create `Packages/CaptureKit/Sources/CaptureKit/RecognitionResult.swift`:

```swift
/// What Capture Text found in the selected region.
public enum RecognitionResult: Equatable {
    case qr(String)
    case text(String)
    case none

    /// The string to put on the clipboard (nil = copy nothing).
    public var clipboardString: String? {
        switch self {
        case .qr(let s): return s
        case .text(let s): return s
        case .none: return nil
        }
    }

    /// Confirmation HUD message.
    public var hudMessage: String {
        switch self {
        case .qr: return "QR code copied"
        case .text(let s): return "Text copied — \(s.count) characters"
        case .none: return "No text found"
        }
    }
}

/// Pure decision rule for Capture Text: any QR code wins over recognized text;
/// text lines join with newlines (spec: linebreaks are kept); blank lines drop.
public enum RecognitionResolver {
    public static func resolve(qrPayloads: [String], textLines: [String]) -> RecognitionResult {
        if let qr = qrPayloads.first { return .qr(qr) }
        let lines = textLines.filter { !$0.isEmpty }
        return lines.isEmpty ? .none : .text(lines.joined(separator: "\n"))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: every test prints ✓ and the last line starts with `PASS — CaptureKitTests:` (0 failures)

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): RecognitionResult + resolver for Capture Text (QR beats text)"
```

---

### Task 2: TextRecognizer — Vision wrapper (TDD, headless end-to-end)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/TextRecognizer.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/TextRecognizerTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/CaptureKit/Tests/CaptureKitTests/TextRecognizerTests.swift`:

```swift
import TestKit
import AppKit
import CoreImage
@testable import CaptureKit

// Headless renderers — same technique as the verified 2026-06-04 probe.
private func renderTextImage(_ text: String,
                             size: CGSize = CGSize(width: 600, height: 120)) -> CGImage {
    let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                        bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(origin: .zero, size: size))
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    (text as NSString).draw(at: CGPoint(x: 20, y: 40), withAttributes: [
        .font: NSFont.systemFont(ofSize: 36, weight: .medium),
        .foregroundColor: NSColor.black])
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

private func renderQRImage(_ payload: String) -> CGImage {
    let filter = CIFilter(name: "CIQRCodeGenerator")!
    filter.setValue(payload.data(using: .utf8)!, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    let output = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    return CIContext().createCGImage(output, from: output.extent)!
}

private func composite(_ left: CGImage, _ right: CGImage) -> CGImage {
    let w = left.width + right.width, h = max(left.height, right.height)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor.white)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.draw(left, in: CGRect(x: 0, y: 0, width: left.width, height: left.height))
    ctx.draw(right, in: CGRect(x: left.width, y: 0, width: right.width, height: right.height))
    return ctx.makeImage()!
}

let textRecognizerTests: [TestCase] = [
    TestCase("recognizesRenderedText") { t in
        let result = try? TextRecognizer.recognize(
            in: renderTextImage("Hello BetterScreenshot 12345"))
        guard case .text(let s)? = result else {
            t.fail("expected .text, got \(String(describing: result))"); return
        }
        t.isTrue(s.contains("BetterScreenshot"), "recognized: \(s)")
        t.isTrue(s.contains("12345"), "recognized: \(s)")
    },
    TestCase("decodesQRPayload") { t in
        let result = try? TextRecognizer.recognize(
            in: renderQRImage("https://github.com/david53001/BetterScreenshot"))
        t.equal(result, RecognitionResult.qr("https://github.com/david53001/BetterScreenshot"))
    },
    TestCase("qrBeatsTextInMixedImage") { t in
        let mixed = composite(renderTextImage("plain words"), renderQRImage("qr-payload"))
        t.equal(try? TextRecognizer.recognize(in: mixed), RecognitionResult.qr("qr-payload"))
    },
    TestCase("blankImageIsNone") { t in
        t.equal(try? TextRecognizer.recognize(in: renderTextImage("")),
                RecognitionResult.none)
    },
]
```

(Note: if Vision surprises us by reporting stray characters on the blank image, relax `blankImageIsNone` to assert `clipboardString` is nil or very short — but the probe suggests it returns no observations.)

In `main.swift`, append `+ textRecognizerTests` to the same concatenation as Task 1 (after `recognitionResolverTests`).

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error — `cannot find 'TextRecognizer' in scope`

- [ ] **Step 3: Write the implementation**

Create `Packages/CaptureKit/Sources/CaptureKit/TextRecognizer.swift`:

```swift
import Vision
import CoreGraphics

/// Vision wrapper for Capture Text. Synchronous — call it off the main thread
/// (Vision's perform() blocks). Feeds results to RecognitionResolver.
public enum TextRecognizer {
    public static func recognize(in image: CGImage) throws -> RecognitionResult {
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true

        let qrRequest = VNDetectBarcodesRequest()
        qrRequest.symbologies = [.qr]

        try VNImageRequestHandler(cgImage: image).perform([textRequest, qrRequest])

        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let qrs = (qrRequest.results ?? []).compactMap { $0.payloadStringValue }
        return RecognitionResolver.resolve(qrPayloads: qrs, textLines: lines)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: all ✓, last line starts with `PASS — CaptureKitTests:` (0 failures). The Vision tests take a few seconds.

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): TextRecognizer — Vision OCR + QR decode behind RecognitionResolver"
```

---

### Task 3: OverlayKit test target + PinGeometry (TDD)

**Files:**
- Modify: `Packages/OverlayKit/Package.swift`
- Create: `Packages/OverlayKit/Sources/OverlayKit/PinGeometry.swift`
- Create: `Packages/OverlayKit/Tests/OverlayKitTests/main.swift`
- Create: `Packages/OverlayKit/Tests/OverlayKitTests/PinGeometryTests.swift`

- [ ] **Step 1: Add the TestKit executable test target**

Replace `Packages/OverlayKit/Package.swift` with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OverlayKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "OverlayKit", targets: ["OverlayKit"])],
    dependencies: [.package(path: "../TestKit")],
    targets: [
        .target(name: "OverlayKit"),
        // Test suite as an executable runner (XCTest is unavailable under CLT).
        // Run with: swift run --package-path Packages/OverlayKit OverlayKitTests
        .executableTarget(
            name: "OverlayKitTests",
            dependencies: ["OverlayKit", .product(name: "TestKit", package: "TestKit")],
            path: "Tests/OverlayKitTests"
        ),
    ]
)
```

Create `Packages/OverlayKit/Tests/OverlayKitTests/main.swift`:

```swift
import TestKit

// Aggregate every test array in this target here, like CaptureKitTests does.
runTests("OverlayKitTests", pinGeometryTests)
```

- [ ] **Step 2: Write the failing tests**

Create `Packages/OverlayKit/Tests/OverlayKitTests/PinGeometryTests.swift`:

```swift
import TestKit
import CoreGraphics
@testable import OverlayKit

let pinGeometryTests: [TestCase] = [
    TestCase("retinaImageGetsPointSize") { t in
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 400, height: 200), backingScale: 2,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), sourceRect: nil)
        t.equal(f.size, CGSize(width: 200, height: 100))
    },
    TestCase("centersOnVisibleFrameWithoutSource") { t in
        let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let f = PinGeometry.initialFrame(imagePixelSize: CGSize(width: 400, height: 200),
                                         backingScale: 2, visibleFrame: vf, sourceRect: nil)
        t.approxEqual(f.midX, vf.midX)
        t.approxEqual(f.midY, vf.midY)
    },
    TestCase("centersOnSourceRect") { t in
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 200, height: 100), backingScale: 2,
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            sourceRect: CGRect(x: 300, y: 300, width: 100, height: 50))
        t.approxEqual(f.midX, 350)
        t.approxEqual(f.midY, 325)
    },
    TestCase("clampsTo80PercentOfScreen") { t in
        let vf = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let f = PinGeometry.initialFrame(imagePixelSize: CGSize(width: 4000, height: 2000),
                                         backingScale: 1, visibleFrame: vf, sourceRect: nil)
        t.approxEqual(f.width, 800)    // 80% of 1000 wide
        t.approxEqual(f.height, 400)   // aspect preserved
    },
    TestCase("staysInsideVisibleFrame") { t in
        let vf = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let f = PinGeometry.initialFrame(
            imagePixelSize: CGSize(width: 400, height: 200), backingScale: 2,
            visibleFrame: vf,
            sourceRect: CGRect(x: 1400, y: 850, width: 100, height: 50))
        t.isTrue(vf.contains(f), "frame \(f) escapes \(vf)")
    },
    TestCase("zoomScalesAroundCenter") { t in
        let current = CGRect(x: 100, y: 100, width: 200, height: 100)
        let f = PinGeometry.zoomedFrame(current: current,
                                        naturalSize: CGSize(width: 200, height: 100),
                                        factor: 2)
        t.equal(f.size, CGSize(width: 400, height: 200))
        t.approxEqual(f.midX, current.midX)
        t.approxEqual(f.midY, current.midY)
    },
    TestCase("zoomClampsToMinAndMax") { t in
        let natural = CGSize(width: 200, height: 100)
        let current = CGRect(x: 0, y: 0, width: 200, height: 100)
        let big = PinGeometry.zoomedFrame(current: current, naturalSize: natural, factor: 100)
        t.equal(big.size, CGSize(width: 600, height: 300))      // 3× cap
        let small = PinGeometry.zoomedFrame(current: current, naturalSize: natural, factor: 0.001)
        t.equal(small.size, CGSize(width: 50, height: 25))      // 0.25× floor
    },
]
```

- [ ] **Step 3: Run tests to verify they fail to compile**

Run: `swift run --package-path Packages/OverlayKit OverlayKitTests`
Expected: compile error — `cannot find 'PinGeometry' in scope`

- [ ] **Step 4: Write the implementation**

Create `Packages/OverlayKit/Sources/OverlayKit/PinGeometry.swift`:

```swift
import CoreGraphics

/// Pure geometry for pinned screenshots (all rects in Cocoa global points).
public enum PinGeometry {
    /// Initial pin frame: the image's point size (pixels ÷ backingScale),
    /// shrunk if needed so it fits within maxFraction of the visible frame
    /// (aspect preserved), centered on sourceRect when known (else on the
    /// visible frame), then nudged fully on-screen.
    public static func initialFrame(imagePixelSize: CGSize, backingScale: CGFloat,
                                    visibleFrame: CGRect, sourceRect: CGRect?,
                                    maxFraction: CGFloat = 0.8) -> CGRect {
        var size = CGSize(width: imagePixelSize.width / backingScale,
                          height: imagePixelSize.height / backingScale)
        let scale = min(1, (visibleFrame.width * maxFraction) / size.width,
                        (visibleFrame.height * maxFraction) / size.height)
        size = CGSize(width: size.width * scale, height: size.height * scale)

        let center = sourceRect.map { CGPoint(x: $0.midX, y: $0.midY) }
            ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        var frame = CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                           width: size.width, height: size.height)
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        return frame
    }

    /// Rescales `current` around its center by `factor`, clamped so the result
    /// stays between minScale× and maxScale× of `naturalSize` (aspect preserved).
    public static func zoomedFrame(current: CGRect, naturalSize: CGSize, factor: CGFloat,
                                   minScale: CGFloat = 0.25, maxScale: CGFloat = 3.0) -> CGRect {
        guard naturalSize.width > 0, naturalSize.height > 0, factor > 0 else { return current }
        let newScale = min(maxScale, max(minScale, (current.width / naturalSize.width) * factor))
        let newSize = CGSize(width: naturalSize.width * newScale,
                             height: naturalSize.height * newScale)
        return CGRect(x: current.midX - newSize.width / 2,
                      y: current.midY - newSize.height / 2,
                      width: newSize.width, height: newSize.height)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift run --package-path Packages/OverlayKit OverlayKitTests`
Expected: 7 ✓, last line `PASS — OverlayKitTests: 7/7 test(s) passed, 0 failure(s)`

Also run: `swift build` (root) — Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): PinGeometry + OverlayKit TestKit suite"
```

---

### Task 4: HUDController (confirmation toast)

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/HUDController.swift`

No unit tests — panel UI is covered by the manual checklist in Task 11.

- [ ] **Step 1: Write the implementation**

Create `Packages/OverlayKit/Sources/OverlayKit/HUDController.swift`:

```swift
import AppKit

/// A small transient confirmation toast ("Text copied — 132 characters").
/// Bottom-center of the given screen; disappears after ~1.5 s. Showing a new
/// message replaces the current one.
@MainActor
public final class HUDController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    public init() {}

    public func show(_ message: String, on screen: NSScreen? = NSScreen.main) {
        dismissTask?.cancel()
        panel?.orderOut(nil); panel = nil
        guard let screen else { return }

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let pad = NSSize(width: 18, height: 10)
        let size = NSSize(width: label.frame.width + pad.width * 2,
                          height: label.frame.height + pad.height * 2)
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + 80)

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false

        let container = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        container.appearance = NSAppearance(named: .vibrantDark)
        container.material = .hudWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = size.height / 2
        container.layer?.masksToBounds = true
        label.frame.origin = NSPoint(x: pad.width, y: pad.height)
        container.addSubview(label)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel = nil
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): HUDController confirmation toast"
```

---

### Task 5: PinPanelController + PinView

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/PinPanelController.swift`
- Create: `Packages/OverlayKit/Sources/OverlayKit/PinView.swift`

No unit tests — geometry was tested in Task 3; panel behavior is in the Task 11 manual checklist.

- [ ] **Step 1: Write PinPanelController**

Create `Packages/OverlayKit/Sources/OverlayKit/PinPanelController.swift`:

```swift
import AppKit

/// Visual styling for a pin, decided at creation time (from app Settings).
public struct PinStyle {
    public let cornerRadius: CGFloat
    public let shadow: Bool
    public init(cornerRadius: CGFloat, shadow: Bool) {
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }
}

/// App-supplied actions; OverlayKit stays free of clipboard/file knowledge.
public struct PinActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void) {
        self.onCopy = onCopy
        self.onSave = onSave
    }
}

/// Owns every live pin. Pins float above everything, appear on all Spaces,
/// and never steal focus. They live until closed or the app quits.
@MainActor
public final class PinPanelController {
    private var panels: [NSPanel] = []

    public init() {}

    public func pin(image: NSImage, pixelSize: CGSize, sourceRect: CGRect?,
                    on screen: NSScreen, style: PinStyle, actions: PinActions) {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return }
        let scale = screen.backingScaleFactor
        let frame = PinGeometry.initialFrame(
            imagePixelSize: pixelSize, backingScale: scale,
            visibleFrame: screen.visibleFrame, sourceRect: sourceRect)
        let naturalSize = CGSize(width: pixelSize.width / scale,
                                 height: pixelSize.height / scale)

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = style.shadow
        panel.hidesOnDeactivate = false

        let view = PinView(image: image, naturalSize: naturalSize, actions: actions,
                           onClose: { [weak self, weak panel] in
            guard let self, let panel else { return }
            panel.orderOut(nil)
            self.panels.removeAll { $0 === panel }
        })
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.layer?.cornerRadius = style.cornerRadius
        panel.contentView = view
        panel.orderFrontRegardless()
        panels.append(panel)
    }
}
```

- [ ] **Step 2: Write PinView**

Create `Packages/OverlayKit/Sources/OverlayKit/PinView.swift`:

```swift
import AppKit

/// The pinned screenshot's content view: drag anywhere to move, drag the
/// bottom-right hotspot or scroll to resize (aspect-locked, 0.25×–3×),
/// double-click to copy, hover for the ✕ close button, right-click for
/// Copy/Save/Close. NSView is an NSObject, so it safely owns its tracking area.
final class PinView: NSView {
    private let image: NSImage
    private let naturalSize: CGSize          // 1× point size; zoom-clamp baseline
    private let actions: PinActions
    private let onClose: () -> Void

    private let closeButton = NSButton()
    private enum DragMode { case none, move, resize }
    private var dragMode: DragMode = .none
    private var dragStartMouse = CGPoint.zero    // screen coords
    private var dragStartFrame = CGRect.zero
    private static let resizeHotspot: CGFloat = 16

    init(image: NSImage, naturalSize: CGSize, actions: PinActions,
         onClose: @escaping () -> Void) {
        self.image = image
        self.naturalSize = naturalSize
        self.actions = actions
        self.onClose = onClose
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true

        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "Close pin")
        closeButton.isBordered = false
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .white
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        closeButton.isHidden = true
        addSubview(closeButton)
    }

    required init?(coder: NSCoder) { fatalError("unsupported") }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1,
                   respectFlipped: true,
                   hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    override func layout() {
        super.layout()
        closeButton.frame = NSRect(x: 6, y: bounds.height - 26, width: 20, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { closeButton.isHidden = false }
    override func mouseExited(with event: NSEvent) { closeButton.isHidden = true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { actions.onCopy(); return }
        guard let window else { return }
        dragStartMouse = NSEvent.mouseLocation
        dragStartFrame = window.frame
        let local = convert(event.locationInWindow, from: nil)
        let inHotspot = local.x > bounds.width - Self.resizeHotspot
            && local.y < Self.resizeHotspot
        dragMode = inHotspot ? .resize : .move
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let dx = mouse.x - dragStartMouse.x
        let dy = mouse.y - dragStartMouse.y
        switch dragMode {
        case .move:
            window.setFrameOrigin(NSPoint(x: dragStartFrame.origin.x + dx,
                                          y: dragStartFrame.origin.y + dy))
        case .resize:
            // Bottom-right drag: aspect follows the horizontal axis.
            let targetW = max(40, dragStartFrame.width + dx)
            let f = PinGeometry.zoomedFrame(current: dragStartFrame,
                                            naturalSize: naturalSize,
                                            factor: targetW / dragStartFrame.width)
            // Anchor the top-left corner while resizing from bottom-right.
            window.setFrame(NSRect(x: dragStartFrame.minX,
                                   y: dragStartFrame.maxY - f.height,
                                   width: f.width, height: f.height), display: true)
            needsDisplay = true
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) { dragMode = .none }

    override func scrollWheel(with event: NSEvent) {
        guard let window else { return }
        let factor = 1 + event.scrollingDeltaY * 0.005
        guard factor > 0.05 else { return }
        let f = PinGeometry.zoomedFrame(current: window.frame,
                                        naturalSize: naturalSize, factor: factor)
        window.setFrame(f, display: true)
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Copy Image", action: #selector(copyTapped),
                     keyEquivalent: "").target = self
        menu.addItem(withTitle: "Save Image", action: #selector(saveTapped),
                     keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Close Pin", action: #selector(closeTapped),
                     keyEquivalent: "").target = self
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func copyTapped() { actions.onCopy() }
    @objc private func saveTapped() { actions.onSave() }
    @objc private func closeTapped() { onClose() }
}
```

- [ ] **Step 3: Verify build + existing tests still pass**

Run: `swift build && swift run --package-path Packages/OverlayKit OverlayKitTests`
Expected: `Build complete!`, then `PASS — OverlayKitTests: 7/7 test(s) passed, 0 failure(s)`

- [ ] **Step 4: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): PinPanelController + PinView — floating always-on-top pins"
```

---

### Task 6: CaptureSettings pin fields (TDD)

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`

- [ ] **Step 1: Write the failing tests**

In `CaptureSettingsTests.swift`, append two cases to the `captureSettingsTests` array:

```swift
    TestCase("pinDefaults") { t in
        let s = CaptureSettings.default
        t.equal(s.pinCornerRadius, 8)
        t.isTrue(s.pinShadow)
    },
    TestCase("roundTripsPinFields") { t in
        var s = CaptureSettings.default
        s.pinCornerRadius = 0
        s.pinShadow = false
        let restored = CaptureSettings(dictionary: s.dictionary)
        t.equal(restored, s)
    },
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error — `value of type 'CaptureSettings' has no member 'pinCornerRadius'`

- [ ] **Step 3: Implement**

In `CaptureSettings.swift`, add the two properties and persistence (new memberwise parameters get defaults so existing call sites keep compiling):

```swift
public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat
    public var overlayCorner: OverlayCorner
    public var overlayAutoDismissSeconds: Int
    public var pinCornerRadius: Int
    public var pinShadow: Bool

    public static let `default` = CaptureSettings(
        afterCapture: .showOverlay, format: .png,
        overlayCorner: .bottomRight, overlayAutoDismissSeconds: 6)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue,
         "format": format.rawValue,
         "overlayCorner": overlayCorner.rawValue,
         "overlayAutoDismissSeconds": String(overlayAutoDismissSeconds),
         "pinCornerRadius": String(pinCornerRadius),
         "pinShadow": pinShadow ? "true" : "false"]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat,
                overlayCorner: OverlayCorner, overlayAutoDismissSeconds: Int,
                pinCornerRadius: Int = 8, pinShadow: Bool = true) {
        self.afterCapture = afterCapture
        self.format = format
        self.overlayCorner = overlayCorner
        self.overlayAutoDismissSeconds = overlayAutoDismissSeconds
        self.pinCornerRadius = pinCornerRadius
        self.pinShadow = pinShadow
    }

    public init(dictionary: [String: String]) {
        let d = CaptureSettings.default
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "") ?? d.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        self.overlayCorner = OverlayCorner(rawValue: dictionary["overlayCorner"] ?? "") ?? d.overlayCorner
        self.overlayAutoDismissSeconds = Int(dictionary["overlayAutoDismissSeconds"] ?? "") ?? d.overlayAutoDismissSeconds
        self.pinCornerRadius = Int(dictionary["pinCornerRadius"] ?? "") ?? d.pinCornerRadius
        self.pinShadow = dictionary["pinShadow"].map { $0 == "true" } ?? d.pinShadow
    }
}
```

(Keep the existing `AfterCaptureBehavior`/`SettingsImageFormat`/`OverlayCorner` enums above the struct untouched.)

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests && swift build`
Expected: `PASS — CaptureKitTests:` (0 failures), then `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): pin appearance settings (corner radius + shadow)"
```

---

### Task 7: Capture Text app wiring (⌘⇧7, coordinator flow, menu item)

**Files:**
- Modify: `App/CaptureCoordinator.swift`
- Modify: `App/BetterScreenshotApp.swift`
- Modify: `App/MenuBarController.swift`

`KeyCombo.carbonKeyCode` already maps `"7"` → 26, so the hotkey works without CaptureKit changes.

- [ ] **Step 1: Add the Capture Text flow to CaptureCoordinator**

In `App/CaptureCoordinator.swift`, add two stored properties next to the existing `quickAccess` property:

```swift
    private let hud = HUDController()
```

Add these methods after `captureFrontWindow()`:

```swift
    /// Capture Text (OCR + QR): drag a region; the recognized text — or a QR
    /// code's payload, which wins — lands on the clipboard. HUD confirms.
    func captureText() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.runCaptureText(result) }
        }
    }

    private func runCaptureText(_ result: SelectionResult) async {
        do {
            let image = try await service.capture(
                .area(rect: result.globalRect, displayID: result.displayID))
            // Vision's perform() blocks — keep it off the main actor.
            let recognition = try await Task.detached {
                try TextRecognizer.recognize(in: image)
            }.value
            if let payload = recognition.clipboardString {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(payload, forType: .string)
            }
            hud.show(recognition.hudMessage, on: screen(for: result.displayID))
        } catch { NSLog("Capture Text failed: \(error)") }
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == displayID
        } ?? NSScreen.main
    }
```

- [ ] **Step 2: Register ⌘⇧7**

In `App/BetterScreenshotApp.swift`, update the defaults comment and add the registration after the ⌘⇧6 block:

```swift
        // Defaults: ⌘⇧4 area, ⌘⇧5 window, ⌘⇧6 fullscreen, ⌘⇧7 capture text.
```

```swift
        hotKeys.register(key: "7", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureText() }
        }
```

- [ ] **Step 3: Add the menu item**

In `App/MenuBarController.swift` `buildMenu()`, after the "Capture Fullscreen" item:

```swift
        menu.addItem(withTitle: "Capture Text", action: #selector(captureText), keyEquivalent: "")
            .target = self
```

And next to the other `@objc` handlers:

```swift
    @objc private func captureText() { coordinator.captureText() }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add App
git commit -m "feat(app): Capture Text — ⌘⇧7 + menu item; OCR/QR result to clipboard with HUD"
```

---

### Task 8: Pin plumbing — Quick Access button, sourceRect threading, clipboard pin

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`
- Modify: `App/CaptureCoordinator.swift`
- Modify: `App/MenuBarController.swift`

These land together because changing `QuickAccessActions`' initializer breaks the App call site until it's updated.

- [ ] **Step 1: Add onPin to QuickAccessActions and a pin button**

In `QuickAccessOverlayController.swift`, replace the `QuickAccessActions` struct with:

```swift
public struct QuickAccessActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public let onAnnotate: () -> Void
    public let onPin: () -> Void
    public let fileURLForDrag: () -> URL?
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void,
                onAnnotate: @escaping () -> Void, onPin: @escaping () -> Void,
                fileURLForDrag: @escaping () -> URL?) {
        self.onCopy = onCopy; self.onSave = onSave
        self.onAnnotate = onAnnotate; self.onPin = onPin
        self.fileURLForDrag = fileURLForDrag
    }
}
```

In `present(image:at:actions:)`, add a pin button to the stack between Edit and Save:

```swift
        stack.addArrangedSubview(iconButton("pin", tip: "Pin to screen", #selector(pinAction)))
```

(The full row order becomes: Copy, Edit, Pin, Save, Close.) And with the other `@objc` handlers:

```swift
    // Pinning replaces the overlay with a floating pin.
    @objc private func pinAction() {
        let a = actions
        dismiss()
        a?.onPin()
    }
```

- [ ] **Step 2: Thread sourceRect through the coordinator and add pin helpers**

In `App/CaptureCoordinator.swift`:

Add the controller next to `hud`:

```swift
    private let pins = PinPanelController()
```

Change `captureArea()` to pass the selection rect along:

```swift
    func captureArea() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID),
                                  sourceRect: result.globalRect) }
        }
    }
```

Change `run` and `handle` signatures (existing `run(...)` call sites in
`captureFullscreen`/`captureFrontWindow` keep compiling via the default):

```swift
    private func run(_ target: CaptureTarget, sourceRect: CGRect? = nil) async {
        do {
            let image = try await service.capture(target)
            handle(image, sourceRect: sourceRect)
        } catch { NSLog("Capture failed: \(error)") }
    }

    private func handle(_ image: CGImage, sourceRect: CGRect?) {
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image, sourceRect: sourceRect)
        }
    }
```

Change `presentOverlay` to accept the rect and supply `onPin` (the rest of the body is unchanged):

```swift
    private func presentOverlay(_ image: CGImage, sourceRect: CGRect?) {
```

```swift
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image) },
            // The overlay's download button always lands in the macOS screenshot folder.
            onSave: { [weak self] in self?.save(image, to: SettingsStore.systemScreenshotLocation()) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            onPin: { [weak self] in self?.pin(image, near: sourceRect) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
```

Add the pin helpers after `annotate(_:)`:

```swift
    /// Pins the image as a floating panel — at its original on-screen location
    /// when known, else centered on the main screen.
    func pin(_ image: CGImage, near sourceRect: CGRect? = nil) {
        guard image.width > 0, image.height > 0 else { return }
        let screen = sourceRect.flatMap { r in NSScreen.screens.first { $0.frame.intersects(r) } }
            ?? NSScreen.main
        guard let screen else { return }
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: image.width, height: image.height))
        let style = PinStyle(cornerRadius: CGFloat(settings.settings.pinCornerRadius),
                             shadow: settings.settings.pinShadow)
        let actions = PinActions(
            onCopy: { [weak self] in
                self?.copy(image)
                self?.hud.show("Copied", on: screen)
            },
            onSave: { [weak self] in self?.save(image) })
        pins.pin(image: nsImage,
                 pixelSize: CGSize(width: image.width, height: image.height),
                 sourceRect: sourceRect, on: screen, style: style, actions: actions)
    }

    func pinFromClipboard() {
        guard let ns = NSPasteboard.general.readObjects(forClasses: [NSImage.self],
                                                        options: nil)?.first as? NSImage,
              let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hud.show("No image on clipboard", on: NSScreen.main)
            return
        }
        pin(cg)
    }

    var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }
```

- [ ] **Step 3: Menu item + validation**

In `App/MenuBarController.swift`, make the class an `NSObject` subclass so it can adopt `NSMenuItemValidation` (call `super.init()` before touching `statusItem`):

```swift
@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: CaptureCoordinator

    init(coordinator: CaptureCoordinator) {
        self.coordinator = coordinator
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }
```

In `buildMenu()`, after the "Capture Text" item:

```swift
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pin from Clipboard", action: #selector(pinClipboard), keyEquivalent: "")
            .target = self
```

With the other handlers:

```swift
    @objc private func pinClipboard() { coordinator.pinFromClipboard() }
```

At the bottom of the file:

```swift
extension MenuBarController: NSMenuItemValidation {
    nonisolated func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        MainActor.assumeIsolated {
            if menuItem.action == #selector(pinClipboard) { return coordinator.clipboardHasImage }
            return true
        }
    }
}
```

(If the actor checker rejects this conformance under the current Swift mode, drop the extension entirely — `pinFromClipboard()` already guards with a "No image on clipboard" HUD.)

- [ ] **Step 4: Build + run package tests**

Run: `swift build && swift run --package-path Packages/OverlayKit OverlayKitTests`
Expected: `Build complete!`, `PASS — OverlayKitTests:` (0 failures)

- [ ] **Step 5: Commit**

```bash
git add App Packages/OverlayKit
git commit -m "feat(app): Pin to Screen — Quick Access pin button, source-rect placement, clipboard pin"
```

---

### Task 9: Editor Pin button

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`
- Modify: `App/CaptureCoordinator.swift`

- [ ] **Step 1: Add onPin + the action-bar button to the editor**

In `EditorWindowController.swift`, add the callback below `onSave` (line ~10):

```swift
    public var onPin: ((CGImage) -> Void)?
```

In `buildActionBar()`, add a Pin button after the `doneBtn` block and include it in the stack:

```swift
        let pinBtn = NSButton(title: "Pin", target: self, action: #selector(pinAction))
        pinBtn.bezelStyle = .rounded
        pinBtn.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        pinBtn.imagePosition = .imageLeading
```

```swift
        let actions = NSStackView(views: [doneBtn, pinBtn, saveBtn, copyBtn])
```

Next to `copyAction`/`saveAction` (line ~503):

```swift
    @objc private func pinAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onPin?(img)
    }
```

- [ ] **Step 2: Wire it in the app**

In `App/CaptureCoordinator.swift` `presentEditor(_:)`, after the `onSave` assignment:

```swift
        controller.onPin = { [weak self] img in self?.pin(img) }
```

(The editor window stays open after pinning — per spec.)

- [ ] **Step 3: Build + run EditorKit tests**

Run: `swift build && swift run --package-path Packages/EditorKit EditorKitTests`
Expected: `Build complete!`, `PASS — EditorKitTests:` (0 failures)

- [ ] **Step 4: Commit**

```bash
git add App Packages/EditorKit
git commit -m "feat(editor): Pin button — flatten document to a floating pin"
```

---

### Task 10: Settings UI for pin appearance

**Files:**
- Modify: `App/SettingsView.swift`

- [ ] **Step 1: Add the two rows**

In the `Form`, after the existing pickers and before the save-folder row, add:

```swift
            Toggle("Pin shadow", isOn: bind(\.pinShadow))
            HStack {
                Text("Pin corner radius")
                Slider(value: Binding(
                    get: { Double(store.settings.pinCornerRadius) },
                    set: { store.settings.pinCornerRadius = Int($0); store.persist() }),
                    in: 0...20, step: 1)
                Text("\(store.settings.pinCornerRadius) pt")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
```

(`bind(\.pinShadow)` works as-is — it takes any `WritableKeyPath<CaptureSettings, V>` and persists on set. The slider needs the explicit `Binding` because `pinCornerRadius` is `Int` and `Slider` wants a floating-point value.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add App/SettingsView.swift
git commit -m "feat(app): pin appearance settings UI (shadow toggle + corner radius)"
```

---

### Task 11: Quick Access stack — up to 3 overlays at the corner

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift`
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`
- Create: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift`
- Modify: `App/CaptureCoordinator.swift`

New captures stack at the configured corner (newest at the corner slot, index 0), 12 pt apart; a 4th capture evicts the oldest; dismissing any overlay compacts the stack.

- [ ] **Step 1: Write the failing tests for the slot math**

In `Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift`, append three cases to the existing `overlayPositionerTests` array:

```swift
    TestCase("stackedOriginIndexZeroMatchesOrigin") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let base = OverlayPositioner.origin(corner: .bottomRight, overlaySize: size,
                                            screenFrame: frame, margin: 24)
        let stacked = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                      screenFrame: frame, margin: 24, index: 0)
        t.equal(stacked, base)
    },
    TestCase("bottomCornersStackUpward") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let s0 = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 0)
        let s1 = OverlayPositioner.stackedOrigin(corner: .bottomRight, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 1)
        t.approxEqual(s1.x, s0.x)
        t.approxEqual(s1.y, s0.y + 168 + 12)   // one slot above, 12 pt gap
    },
    TestCase("topCornersStackDownward") { t in
        let size = CGSize(width: 220, height: 168)
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 875)
        let s0 = OverlayPositioner.stackedOrigin(corner: .topLeft, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 0)
        let s1 = OverlayPositioner.stackedOrigin(corner: .topLeft, overlaySize: size,
                                                 screenFrame: frame, margin: 24, index: 1)
        t.approxEqual(s1.y, s0.y - (168 + 12))
    },
```

- [ ] **Step 2: Run tests to verify they fail to compile**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: compile error — `type 'OverlayPositioner' has no member 'stackedOrigin'`

- [ ] **Step 3: Implement stackedOrigin**

In `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift`, add inside the enum:

```swift
    /// Origin for the overlay at stack position `index` (0 = at the corner;
    /// higher indexes step away from the screen edge so overlays pile up
    /// one over the other with `spacing` between them).
    public static func stackedOrigin(corner: OverlayCorner, overlaySize: CGSize,
                                     screenFrame: CGRect, margin: CGFloat,
                                     index: Int, spacing: CGFloat = 12) -> CGPoint {
        var o = origin(corner: corner, overlaySize: overlaySize,
                       screenFrame: screenFrame, margin: margin)
        let offset = CGFloat(index) * (overlaySize.height + spacing)
        switch corner {
        case .bottomLeft, .bottomRight: o.y += offset   // stack upward
        case .topLeft, .topRight:       o.y -= offset   // stack downward
        }
        return o
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: all ✓, `PASS — CaptureKitTests:` (0 failures)

- [ ] **Step 5: Give QuickAccessOverlayController a dismissal hook and a move**

In `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`, add below the `actions` property:

```swift
    /// Fired exactly once whenever a visible overlay goes away (✕, save,
    /// drag-out, annotate, pin, or eviction) so a stack manager can compact.
    public var onDismissed: (() -> Void)?
```

Replace `dismiss()` with (the `guard` keeps `present()`'s defensive first-line `dismiss()` from firing the hook when nothing was showing):

```swift
    public func dismiss() {
        guard panel != nil else { return }
        panel?.orderOut(nil); panel = nil; actions = nil
        onDismissed?()
    }
```

And add:

```swift
    /// Slides the overlay to a new stack slot.
    public func move(to origin: CGPoint) {
        panel?.setFrameOrigin(origin)
    }
```

- [ ] **Step 6: Create the stack controller**

Create `Packages/OverlayKit/Sources/OverlayKit/QuickAccessStackController.swift`:

```swift
import AppKit

/// Manages up to `maxCount` post-capture overlays stacked at a screen corner.
/// Index 0 is the newest capture and sits at the corner slot; older overlays
/// step away from the screen edge. A capture beyond the limit evicts the
/// oldest; dismissing any overlay compacts the stack. Slot positions are
/// injected via `originForIndex` so OverlayKit needs no positioning logic.
@MainActor
public final class QuickAccessStackController {
    public let maxCount = 3
    private var entries: [QuickAccessOverlayController] = []   // index 0 = newest
    private var originForIndex: ((Int) -> CGPoint)?

    public init() {}

    public func present(image: NSImage, actions: QuickAccessActions,
                        originForIndex: @escaping (Int) -> CGPoint) {
        self.originForIndex = originForIndex
        if entries.count == maxCount, let oldest = entries.last {
            entries.removeLast()
            oldest.dismiss()   // its onDismissed no-ops: already removed
        }
        let controller = QuickAccessOverlayController()
        controller.onDismissed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.entries.removeAll { $0 === controller }
            self.restack()
        }
        entries.insert(controller, at: 0)
        controller.present(image: image, at: originForIndex(0), actions: actions)
        restack()
    }

    private func restack() {
        guard let originForIndex else { return }
        for (i, c) in entries.enumerated() { c.move(to: originForIndex(i)) }
    }
}
```

- [ ] **Step 7: Swap the coordinator over to the stack**

In `App/CaptureCoordinator.swift`, replace the `quickAccess` property:

```swift
    private let quickAccess = QuickAccessStackController()
```

In `presentOverlay(_:sourceRect:)`, delete the `let origin = OverlayPositioner.origin(...)` statement and replace the final `quickAccess.present(image: nsImage, at: origin, actions: actions)` call with:

```swift
        let corner = settings.settings.overlayCorner
        let frame = screen.visibleFrame
        quickAccess.present(image: nsImage, actions: actions) { index in
            OverlayPositioner.stackedOrigin(corner: corner,
                                            overlaySize: CGSize(width: 220, height: 168),
                                            screenFrame: frame, margin: 24, index: index)
        }
```

(Everything else in the method — the `QuickAccessActions` with `onPin` etc. from Task 8 — stays as is.)

- [ ] **Step 8: Build + run all package tests**

Run: `swift build && swift run --package-path Packages/CaptureKit CaptureKitTests && swift run --package-path Packages/OverlayKit OverlayKitTests`
Expected: `Build complete!` and two `PASS` lines, 0 failures

- [ ] **Step 9: Commit**

```bash
git add App Packages/CaptureKit Packages/OverlayKit
git commit -m "feat(overlay): Quick Access stack — up to 3 captures pile at the corner"
```

---

### Task 12: Full verification, docs, tag

**Files:**
- Modify: `README.md` (feature list)
- Modify: `CLAUDE.md` (roadmap line)

- [ ] **Step 1: Run every automated suite**

```bash
swift build
swift run --package-path Packages/CaptureKit CaptureKitTests
swift run --package-path Packages/OverlayKit OverlayKitTests
swift run --package-path Packages/EditorKit EditorKitTests
```

Expected: `Build complete!` and three `PASS` lines with 0 failures.

- [ ] **Step 2: Build and deploy the app bundle for manual verification**

```bash
./scripts/build-app.sh
osascript -e 'tell application "BetterScreenshot" to quit' 2>/dev/null; pkill -x BetterScreenshot 2>/dev/null
rm -rf /Applications/BetterScreenshot.app && ditto dist/BetterScreenshot.app /Applications/BetterScreenshot.app
open /Applications/BetterScreenshot.app
```

(The stable signing identity keeps the Screen Recording grant across the swap.)

- [ ] **Step 3: Manual checklist (GUI session required — ask the user to verify)**

- [ ] ⌘⇧7 → drag over text → "Text copied — N characters" HUD → paste matches
- [ ] ⌘⇧7 over a QR code (even with surrounding text) → "QR code copied" → paste is the payload
- [ ] ⌘⇧7 over blank wallpaper → "No text found", clipboard untouched
- [ ] Menu bar → Capture Text works like the hotkey
- [ ] Area capture → Quick Access overlay → Pin → pin appears at the captured location
- [ ] Editor → Pin → flattened image pins; editor stays open
- [ ] Menu bar → Pin from Clipboard (with and without an image on the clipboard)
- [ ] Pin: drag moves; bottom-right drag and scroll resize (clamped); double-click copies (+ HUD); hover shows ✕; right-click menu Copy/Save/Close works
- [ ] Pin floats over other apps and survives Space switches; no focus stealing
- [ ] Settings: corner radius + shadow apply to newly created pins
- [ ] Multiple pins at once; closing one leaves the others
- [ ] Three quick captures stack on the right, newest at the corner, 12 pt gaps
- [ ] A 4th capture evicts the oldest (farthest-from-corner) overlay
- [ ] Closing/saving/dragging-out a middle overlay slides the rest to fill the gap
- [ ] Stack follows the overlay-corner setting (top corners stack downward)

- [ ] **Step 4: Update docs**

- README.md: add "Capture Text (OCR + QR → clipboard)" and "Pin to screen (floating always-on-top captures)" to the feature list.
- CLAUDE.md roadmap line: mark P3 done, e.g. `P2 recording (…) · ~~P3 OCR + pin-to-screen~~ (shipped v1.3) · P4 …`.

- [ ] **Step 5: Commit + tag**

```bash
git add README.md CLAUDE.md
git commit -m "docs: P3 shipped — Capture Text (OCR/QR) + Pin to Screen"
git tag v1.3-ocr-pin
```

---

## Self-review notes (already applied)

- Spec coverage: OCR core+QR (Tasks 1–2, 7), HUD (4), pin geometry/panel/full UX (3, 5, 8), three entry points (8, 9), settings styling (6, 10), Quick Access stack (11), manual checklist + tag (12). The spec's "menu item disabled when clipboard empty" is Task 8 Step 3 with a documented fallback.
- Type consistency: `RecognitionResult`/`RecognitionResolver`/`TextRecognizer` (Tasks 1→2→7); `PinGeometry.initialFrame/zoomedFrame` (3→5); `PinStyle`/`PinActions` (5→8); `QuickAccessActions.onPin` (8); `CaptureSettings.pinCornerRadius/pinShadow` (6→8→10); `OverlayPositioner.stackedOrigin`/`QuickAccessStackController`/`onDismissed`/`move(to:)` (11) — names match across tasks.
- Task-11 note: it edits the same `presentOverlay` and `QuickAccessOverlayController` that Task 8 touches, so it must run after Task 8 (the plan order already guarantees this).
- All test code, commands, and expected outputs are concrete; no placeholders.
