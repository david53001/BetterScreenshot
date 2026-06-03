# BetterScreenshot v1 — Plan 3: Annotation Editor

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: Plans 1 & 2 complete.** This plan fills the `coordinator.editorPresenter` hook added in Plan 2 so the overlay's "Edit" button opens the editor.

**Goal:** A full annotation editor: open a captured image, draw arrows / lines / rectangles / ellipses / text / blur / pixelate / counters, crop, recolor, reorder, move and delete objects, then export (copy/save) a flattened image.

**Architecture:** A new `EditorKit` package holds a pure, value-typed document model (`EditorDocument` + an `Annotation` protocol with one concrete type per tool) and a single `DocumentRenderer.render(_:)` flatten path reused for both on-screen drawing and export. All rendering goes through a **flipped `NSGraphicsContext`** (top-left origin, 1 unit == 1 base-image pixel) so AppKit drawing (`NSBezierPath`, `NSAttributedString`) — including text — comes out right-side-up. The AppKit `EditorCanvasView` / `EditorWindowController` (also in `EditorKit`) are verified manually; all geometry/model logic is unit-tested with `swift test`.

**Tech Stack:** Swift, macOS 14, AppKit, CoreImage (blur/pixelate), XCTest, XcodeGen.

**Coordinate convention (important):** Annotations live in **base-image pixel space, top-left origin** (matching `CGImage`). The renderer and canvas both set up a flipped context so this maps 1:1.

**v1 editor scope note:** create / select / move / delete / reorder + inline text editing + crop are fully implemented. **Bounding-box resize handles** are implemented as the final *stretch* task (Task 14) for rect-defined shapes only; if skipped, users delete-and-redraw. Hit-testing uses a lenient bounding-box test (clicking anywhere in an object's box selects it) — a deliberate v1 simplification.

---

## File Structure

```
Packages/EditorKit/
  Package.swift
  Sources/EditorKit/
    RGBAColor.swift            (PURE + AppKit color bridge)
    AnnotationStyle.swift      (PURE)
    EditorTool.swift           (PURE enum)
    Annotation.swift           (protocol + hitTest default)
    EditorDocument.swift       (model)
    ShapeAnnotations.swift     (Rectangle, FilledRectangle, Ellipse, Line)
    ArrowGeometry.swift        (PURE arrowhead math)
    ArrowAnnotation.swift
    TextAnnotation.swift
    CounterAnnotation.swift
    Redactor.swift             (CoreImage blur/pixelate)
    RedactionAnnotations.swift (Blur, Pixelate — hold a precomputed patch)
    DocumentRenderer.swift     (flatten → CGImage)
    EditorCanvasView.swift     (NSView, manual)
    EditorWindowController.swift (manual)
  Tests/EditorKitTests/
    RGBAColorTests.swift
    EditorDocumentTests.swift
    ShapeAnnotationTests.swift
    ArrowGeometryTests.swift
    TextAnnotationTests.swift
    CounterAnnotationTests.swift
    RedactorTests.swift
    DocumentRendererTests.swift
    CropTests.swift
App/
  CaptureCoordinator.swift     (modified — set editorPresenter)
  BetterScreenshotApp.swift    (modified — wire presenter)
project.yml                    (modified — add EditorKit dependency)
```

---

## Task 1: EditorKit scaffold + RGBAColor + AnnotationStyle

**Files:**
- Create: `Packages/EditorKit/Package.swift`, `Sources/EditorKit/RGBAColor.swift`, `Sources/EditorKit/AnnotationStyle.swift`, `Sources/EditorKit/EditorTool.swift`
- Test: `Tests/EditorKitTests/RGBAColorTests.swift`

- [ ] **Step 1: Package manifest**

`Packages/EditorKit/Package.swift`:
```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EditorKit", targets: ["EditorKit"])],
    targets: [
        .target(name: "EditorKit"),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
    ]
)
```

- [ ] **Step 2: Write the failing test**

`Tests/EditorKitTests/RGBAColorTests.swift`:
```swift
import XCTest
@testable import EditorKit

final class RGBAColorTests: XCTestCase {
    func testCGColorComponentsMatch() {
        let c = RGBAColor(r: 1, g: 0.5, b: 0, a: 0.8)
        let cg = c.cgColor
        XCTAssertEqual(cg.components?[0] ?? -1, 1, accuracy: 0.001)
        XCTAssertEqual(cg.components?[1] ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(cg.components?[3] ?? -1, 0.8, accuracy: 0.001)
    }

    func testDefaultStyleIsRed() {
        XCTAssertEqual(AnnotationStyle.default.lineWidth, 4)
        XCTAssertEqual(AnnotationStyle.default.strokeColor.r, 1, accuracy: 0.001)
    }
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter RGBAColorTests`
Expected: FAIL — `cannot find 'RGBAColor'`.

- [ ] **Step 4: Implement**

`Sources/EditorKit/RGBAColor.swift`:
```swift
import CoreGraphics
import AppKit

public struct RGBAColor: Equatable {
    public var r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat
    public init(r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    public var nsColor: NSColor {
        NSColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
    public init(_ ns: NSColor) {
        let c = ns.usingColorSpace(.sRGB) ?? ns
        self.init(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent)
    }
}
```

`Sources/EditorKit/AnnotationStyle.swift`:
```swift
import CoreGraphics

public struct AnnotationStyle: Equatable {
    public var strokeColor: RGBAColor
    public var fillColor: RGBAColor
    public var lineWidth: CGFloat
    public var fontSize: CGFloat

    public init(strokeColor: RGBAColor, fillColor: RGBAColor,
                lineWidth: CGFloat, fontSize: CGFloat) {
        self.strokeColor = strokeColor; self.fillColor = fillColor
        self.lineWidth = lineWidth; self.fontSize = fontSize
    }

    public static let `default` = AnnotationStyle(
        strokeColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 1),
        fillColor: RGBAColor(r: 1, g: 0.23, b: 0.19, a: 0.25),
        lineWidth: 4, fontSize: 24)
}
```

`Sources/EditorKit/EditorTool.swift`:
```swift
public enum EditorTool: String, CaseIterable {
    case select, arrow, line, rectangle, filledRectangle, ellipse
    case text, counter, blur, pixelate, crop
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter RGBAColorTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): EditorKit scaffold + RGBAColor + AnnotationStyle"
```

---

## Task 2: Annotation protocol + EditorDocument

**Files:**
- Create: `Sources/EditorKit/Annotation.swift`, `Sources/EditorKit/EditorDocument.swift`
- Test: `Tests/EditorKitTests/EditorDocumentTests.swift`

Note: the test uses a tiny `StubAnnotation` so the document can be tested before any real tool exists.

- [ ] **Step 1: Write the failing test**

`Tests/EditorKitTests/EditorDocumentTests.swift`:
```swift
import XCTest
import CoreGraphics
@testable import EditorKit

private struct StubAnnotation: Annotation {
    let id = UUID()
    var style = AnnotationStyle.default
    var box: CGRect
    func boundingBox() -> CGRect { box }
    func draw() {}
    func moved(by d: CGVector) -> any Annotation {
        var c = self; c.box = box.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    var isCounter = false
}

final class EditorDocumentTests: XCTestCase {
    private func makeBase() -> CGImage {
        let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    func testAddAndCount() {
        var doc = EditorDocument(baseImage: makeBase())
        doc.add(StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4)))
        XCTAssertEqual(doc.annotations.count, 1)
    }

    func testTopmostHitReturnsLastAdded() {
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 8, height: 8))
        let b = StubAnnotation(box: CGRect(x: 0, y: 0, width: 8, height: 8))
        doc.add(a); doc.add(b)
        XCTAssertEqual(doc.topmostHit(at: CGPoint(x: 4, y: 4)), b.id) // b drawn last = on top
    }

    func testMoveById() {
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: CGRect(x: 0, y: 0, width: 4, height: 4))
        doc.add(a)
        doc.move(id: a.id, by: CGVector(dx: 5, dy: 3))
        XCTAssertEqual(doc.annotations[0].boundingBox(), CGRect(x: 5, y: 3, width: 4, height: 4))
    }

    func testRemoveAndReorder() {
        var doc = EditorDocument(baseImage: makeBase())
        let a = StubAnnotation(box: .zero), b = StubAnnotation(box: .zero)
        doc.add(a); doc.add(b)
        doc.bringToFront(id: a.id)
        XCTAssertEqual(doc.annotations.last?.id, a.id)
        doc.remove(id: b.id)
        XCTAssertEqual(doc.annotations.count, 1)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter EditorDocumentTests`
Expected: FAIL — `cannot find 'Annotation'` / `EditorDocument`.

- [ ] **Step 3: Implement the protocol**

`Sources/EditorKit/Annotation.swift`:
```swift
import CoreGraphics

public protocol Annotation {
    var id: UUID { get }
    var style: AnnotationStyle { get set }
    func boundingBox() -> CGRect
    /// Draws into the CURRENT NSGraphicsContext (flipped, top-left origin, image-pixel units).
    func draw()
    func moved(by delta: CGVector) -> any Annotation
}

public extension Annotation {
    /// Lenient v1 hit-test: a few px of slop around the bounding box.
    func hitTest(_ point: CGPoint) -> Bool {
        boundingBox().insetBy(dx: -6, dy: -6).contains(point)
    }
}
```

- [ ] **Step 4: Implement the document**

`Sources/EditorKit/EditorDocument.swift`:
```swift
import CoreGraphics

public struct EditorDocument {
    public let baseImage: CGImage
    public private(set) var annotations: [any Annotation] = []

    public var size: CGSize { CGSize(width: baseImage.width, height: baseImage.height) }

    public init(baseImage: CGImage) { self.baseImage = baseImage }

    public mutating func add(_ a: any Annotation) { annotations.append(a) }

    public mutating func remove(id: UUID) { annotations.removeAll { $0.id == id } }

    public func index(of id: UUID) -> Int? { annotations.firstIndex { $0.id == id } }

    public mutating func move(id: UUID, by delta: CGVector) {
        guard let i = index(of: id) else { return }
        annotations[i] = annotations[i].moved(by: delta)
    }

    public mutating func replace(id: UUID, with a: any Annotation) {
        guard let i = index(of: id) else { return }
        annotations[i] = a
    }

    public mutating func bringToFront(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.append(a)
    }

    public mutating func sendToBack(id: UUID) {
        guard let i = index(of: id) else { return }
        let a = annotations.remove(at: i); annotations.insert(a, at: 0)
    }

    /// Topmost (last-drawn) annotation under the point.
    public func topmostHit(at point: CGPoint) -> UUID? {
        for a in annotations.reversed() where a.hitTest(point) { return a.id }
        return nil
    }

    public func nextCounterNumber() -> Int {
        annotations.filter { $0 is CounterAnnotation }.count + 1
    }
}
```
Note: `nextCounterNumber()` references `CounterAnnotation`, defined in Task 6 — it compiles only once Task 6 lands. To keep this task green, temporarily stub the body as `return annotations.count + 1` and restore the counter-aware version in Task 6. (Marked again there.)

- [ ] **Step 5: Apply the temporary stub for `nextCounterNumber()`**

For now, replace the `nextCounterNumber()` body with:
```swift
    public func nextCounterNumber() -> Int { 1 } // refined in Task 6
```

- [ ] **Step 6: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter EditorDocumentTests`
Expected: PASS (4 tests).

- [ ] **Step 7: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): Annotation protocol + EditorDocument model"
```

---

## Task 3: Shape annotations (Rectangle, FilledRectangle, Ellipse, Line)

**Files:**
- Create: `Sources/EditorKit/ShapeAnnotations.swift`
- Test: `Tests/EditorKitTests/ShapeAnnotationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class ShapeAnnotationTests: XCTestCase {
    func testRectangleBoundingBoxAndMove() {
        let r = RectangleAnnotation(frame: CGRect(x: 10, y: 20, width: 30, height: 40), filled: false)
        XCTAssertEqual(r.boundingBox(), CGRect(x: 10, y: 20, width: 30, height: 40))
        let moved = r.moved(by: CGVector(dx: 5, dy: -5))
        XCTAssertEqual(moved.boundingBox(), CGRect(x: 15, y: 15, width: 30, height: 40))
    }

    func testEllipseHitTestUsesBoundingBox() {
        let e = EllipseAnnotation(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        XCTAssertTrue(e.hitTest(CGPoint(x: 10, y: 10)))
        XCTAssertFalse(e.hitTest(CGPoint(x: 200, y: 200)))
    }

    func testLineBoundingBoxSpansEndpoints() {
        let l = LineAnnotation(start: CGPoint(x: 5, y: 30), end: CGPoint(x: 25, y: 10))
        let bb = l.boundingBox()
        XCTAssertEqual(bb.minX, 5, accuracy: 0.001)
        XCTAssertEqual(bb.minY, 10, accuracy: 0.001)
        XCTAssertEqual(bb.maxX, 25, accuracy: 0.001)
        XCTAssertEqual(bb.maxY, 30, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter ShapeAnnotationTests`
Expected: FAIL — types not found.

- [ ] **Step 3: Implement**

`Sources/EditorKit/ShapeAnnotations.swift`:
```swift
import AppKit

public struct RectangleAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public var filled: Bool
    public init(frame: CGRect, filled: Bool, style: AnnotationStyle = .default) {
        self.frame = frame; self.filled = filled; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        let path = NSBezierPath(rect: frame)
        if filled { style.fillColor.nsColor.setFill(); path.fill() }
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}

public struct FilledRectangleAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public init(frame: CGRect, style: AnnotationStyle = .default) {
        self.frame = frame; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        style.strokeColor.nsColor.setFill()
        NSBezierPath(rect: frame).fill()
    }
}

public struct EllipseAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public init(frame: CGRect, style: AnnotationStyle = .default) {
        self.frame = frame; self.style = style
    }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        let path = NSBezierPath(ovalIn: frame)
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}

public struct LineAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint, style: AnnotationStyle = .default) {
        self.start = start; self.end = end; self.style = style
    }
    public func boundingBox() -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self
        c.start = CGPoint(x: start.x + d.dx, y: start.y + d.dy)
        c.end = CGPoint(x: end.x + d.dx, y: end.y + d.dy)
        return c
    }
    public func draw() {
        let path = NSBezierPath()
        path.move(to: start); path.line(to: end)
        style.strokeColor.nsColor.setStroke(); path.lineWidth = style.lineWidth; path.stroke()
    }
}
```
(`FilledRectangleAnnotation` is a distinct type from `RectangleAnnotation(filled:true)` for clarity; the toolbar uses one or the other. Both are fine — keep both.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter ShapeAnnotationTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): rectangle/filled/ellipse/line annotations"
```

---

## Task 4: ArrowGeometry (PURE) + ArrowAnnotation

**Files:**
- Create: `Sources/EditorKit/ArrowGeometry.swift`, `Sources/EditorKit/ArrowAnnotation.swift`
- Test: `Tests/EditorKitTests/ArrowGeometryTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class ArrowGeometryTests: XCTestCase {
    func testHorizontalArrowheadWings() {
        // Arrow pointing right: start (0,0) → end (100,0), head length 10, half-angle 30°.
        let (left, right) = ArrowGeometry.headWings(
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0),
            length: 10, halfAngleDegrees: 30)
        // Wings sit behind the tip (x < 100) and symmetric about y=0.
        XCTAssertLessThan(left.x, 100)
        XCTAssertLessThan(right.x, 100)
        XCTAssertEqual(left.y, -right.y, accuracy: 0.001)
        XCTAssertEqual(abs(left.y), 10 * sin(30 * .pi / 180), accuracy: 0.01)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter ArrowGeometryTests`
Expected: FAIL — `cannot find 'ArrowGeometry'`.

- [ ] **Step 3: Implement geometry**

`Sources/EditorKit/ArrowGeometry.swift`:
```swift
import CoreGraphics

public enum ArrowGeometry {
    /// The two arrowhead wing points for an arrow from `start` to `end`.
    public static func headWings(start: CGPoint, end: CGPoint,
                                 length: CGFloat, halfAngleDegrees: CGFloat)
        -> (left: CGPoint, right: CGPoint) {
        let dx = end.x - start.x, dy = end.y - start.y
        let angle = atan2(dy, dx)
        let half = halfAngleDegrees * .pi / 180
        let a1 = angle + .pi - half
        let a2 = angle + .pi + half
        let left = CGPoint(x: end.x + length * cos(a1), y: end.y + length * sin(a1))
        let right = CGPoint(x: end.x + length * cos(a2), y: end.y + length * sin(a2))
        return (left, right)
    }
}
```

- [ ] **Step 4: Implement the arrow annotation**

`Sources/EditorKit/ArrowAnnotation.swift`:
```swift
import AppKit

public struct ArrowAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var start: CGPoint
    public var end: CGPoint
    public init(start: CGPoint, end: CGPoint, style: AnnotationStyle = .default) {
        self.start = start; self.end = end; self.style = style
    }
    public func boundingBox() -> CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(start.x - end.x), height: abs(start.y - end.y))
            .insetBy(dx: -style.lineWidth * 3, dy: -style.lineWidth * 3)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self
        c.start = CGPoint(x: start.x + d.dx, y: start.y + d.dy)
        c.end = CGPoint(x: end.x + d.dx, y: end.y + d.dy)
        return c
    }
    public func draw() {
        let headLen = max(12, style.lineWidth * 3)
        let (left, right) = ArrowGeometry.headWings(start: start, end: end,
                                                    length: headLen, halfAngleDegrees: 28)
        let shaft = NSBezierPath()
        shaft.move(to: start); shaft.line(to: end)
        style.strokeColor.nsColor.setStroke()
        shaft.lineWidth = style.lineWidth; shaft.lineCapStyle = .round; shaft.stroke()

        let head = NSBezierPath()
        head.move(to: end); head.line(to: left); head.line(to: right); head.close()
        style.strokeColor.nsColor.setFill(); head.fill()
    }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter ArrowGeometryTests`
Expected: PASS (1 test).

- [ ] **Step 6: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): arrow annotation + arrowhead geometry"
```

---

## Task 5: TextAnnotation

**Files:**
- Create: `Sources/EditorKit/TextAnnotation.swift`
- Test: `Tests/EditorKitTests/TextAnnotationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class TextAnnotationTests: XCTestCase {
    func testLongerStringHasWiderBox() {
        let short = TextAnnotation(text: "Hi", origin: CGPoint(x: 0, y: 0))
        let long = TextAnnotation(text: "Hello world, this is longer", origin: CGPoint(x: 0, y: 0))
        XCTAssertGreaterThan(long.boundingBox().width, short.boundingBox().width)
    }

    func testMoveOffsetsOrigin() {
        let t = TextAnnotation(text: "Hi", origin: CGPoint(x: 10, y: 10))
        let m = t.moved(by: CGVector(dx: 5, dy: 7))
        XCTAssertEqual(m.boundingBox().minX, 15, accuracy: 0.5)
        XCTAssertEqual(m.boundingBox().minY, 17, accuracy: 0.5)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter TextAnnotationTests`
Expected: FAIL — `cannot find 'TextAnnotation'`.

- [ ] **Step 3: Implement**

`Sources/EditorKit/TextAnnotation.swift`:
```swift
import AppKit

public struct TextAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var text: String
    public var origin: CGPoint   // top-left
    public init(text: String, origin: CGPoint, style: AnnotationStyle = .default) {
        self.text = text; self.origin = origin; self.style = style
    }
    private var attributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: style.fontSize, weight: .semibold),
         .foregroundColor: style.strokeColor.nsColor]
    }
    public func boundingBox() -> CGRect {
        let size = NSAttributedString(string: text.isEmpty ? " " : text,
                                      attributes: attributes).size()
        return CGRect(origin: origin, size: size)
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() {
        NSAttributedString(string: text, attributes: attributes).draw(at: origin)
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter TextAnnotationTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): text annotation"
```

---

## Task 6: CounterAnnotation (+ restore document counter logic)

**Files:**
- Create: `Sources/EditorKit/CounterAnnotation.swift`
- Modify: `Sources/EditorKit/EditorDocument.swift` (restore `nextCounterNumber()`)
- Test: `Tests/EditorKitTests/CounterAnnotationTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class CounterAnnotationTests: XCTestCase {
    func testBoundingBoxIsSquareAtOrigin() {
        let c = CounterAnnotation(number: 3, origin: CGPoint(x: 50, y: 60))
        let bb = c.boundingBox()
        XCTAssertEqual(bb.minX, 50, accuracy: 0.001)
        XCTAssertEqual(bb.minY, 60, accuracy: 0.001)
        XCTAssertEqual(bb.width, bb.height, accuracy: 0.001)
    }

    func testNextCounterNumberCountsCountersOnly() {
        let base = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        var doc = EditorDocument(baseImage: base)
        doc.add(RectangleAnnotation(frame: .zero, filled: false))
        doc.add(CounterAnnotation(number: 1, origin: .zero))
        XCTAssertEqual(doc.nextCounterNumber(), 2)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter CounterAnnotationTests`
Expected: FAIL — `cannot find 'CounterAnnotation'`.

- [ ] **Step 3: Implement the counter**

`Sources/EditorKit/CounterAnnotation.swift`:
```swift
import AppKit

public struct CounterAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var number: Int
    public var origin: CGPoint   // top-left of the badge
    public init(number: Int, origin: CGPoint, style: AnnotationStyle = .default) {
        self.number = number; self.origin = origin; self.style = style
    }
    public var diameter: CGFloat { max(28, style.fontSize * 1.6) }
    public func boundingBox() -> CGRect {
        CGRect(origin: origin, size: CGSize(width: diameter, height: diameter))
    }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.origin = CGPoint(x: origin.x + d.dx, y: origin.y + d.dy); return c
    }
    public func draw() {
        let rect = boundingBox()
        style.strokeColor.nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let s = "\(number)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: diameter * 0.55, weight: .bold),
            .foregroundColor: NSColor.white]
        let size = NSAttributedString(string: s, attributes: attrs).size()
        let p = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        NSAttributedString(string: s, attributes: attrs).draw(at: p)
    }
}
```

- [ ] **Step 4: Restore the counter-aware document logic**

In `Sources/EditorKit/EditorDocument.swift`, replace:
```swift
    public func nextCounterNumber() -> Int { 1 } // refined in Task 6
```
with:
```swift
    public func nextCounterNumber() -> Int {
        annotations.filter { $0 is CounterAnnotation }.count + 1
    }
```

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter CounterAnnotationTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): counter annotation + counter-aware numbering"
```

---

## Task 7: Redactor + Blur/Pixelate annotations

**Files:**
- Create: `Sources/EditorKit/Redactor.swift`, `Sources/EditorKit/RedactionAnnotations.swift`
- Test: `Tests/EditorKitTests/RedactorTests.swift`

Design: redaction annotations hold a **precomputed patch** (`CGImage`) of their region, so `draw()` just blits it. The patch is produced by `Redactor` at creation time (the canvas has the base image). This keeps `draw()` uniform and side-effect-free.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class RedactorTests: XCTestCase {
    private func makeBase() -> CGImage {
        let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        return ctx.makeImage()!
    }

    func testPixelatePatchHasRegionSize() {
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        let patch = Redactor.pixelate(makeBase(), region: region, blockSize: 10)
        XCTAssertEqual(patch?.width, 40)
        XCTAssertEqual(patch?.height, 30)
    }

    func testBlurPatchHasRegionSize() {
        let region = CGRect(x: 0, y: 0, width: 20, height: 20)
        let patch = Redactor.blur(makeBase(), region: region, radius: 8)
        XCTAssertEqual(patch?.width, 20)
        XCTAssertEqual(patch?.height, 20)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter RedactorTests`
Expected: FAIL — `cannot find 'Redactor'`.

- [ ] **Step 3: Implement Redactor**

`Sources/EditorKit/Redactor.swift`:
```swift
import CoreImage
import CoreGraphics

public enum Redactor {
    private static let context = CIContext(options: nil)

    private static func patch(_ base: CGImage, region: CGRect,
                              _ transform: (CIImage) -> CIImage) -> CGImage? {
        let r = region.integral
        guard r.width >= 1, r.height >= 1 else { return nil }
        let full = CIImage(cgImage: base)
        // CIImage origin is bottom-left; convert top-left region → bottom-left.
        let blOrigin = CGRect(x: r.minX,
                              y: CGFloat(base.height) - r.maxY,
                              width: r.width, height: r.height)
        let cropped = full.cropped(to: blOrigin)
        let filtered = transform(cropped).cropped(to: blOrigin)
        return context.createCGImage(filtered, from: blOrigin)
    }

    public static func pixelate(_ base: CGImage, region: CGRect, blockSize: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            img.applyingFilter("CIPixellate", parameters: [
                kCIInputScaleKey: blockSize,
                kCIInputCenterKey: CIVector(x: region.midX, y: CGFloat(base.height) - region.midY)])
        }
    }

    public static func blur(_ base: CGImage, region: CGRect, radius: CGFloat) -> CGImage? {
        patch(base, region: region) { img in
            img.clampedToExtent().applyingFilter("CIGaussianBlur",
                parameters: [kCIInputRadiusKey: radius])
        }
    }
}
```

- [ ] **Step 4: Implement the redaction annotations**

`Sources/EditorKit/RedactionAnnotations.swift`:
```swift
import AppKit

public struct PixelateAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public let patch: CGImage
    public init(frame: CGRect, patch: CGImage) { self.frame = frame; self.patch = patch }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        NSImage(cgImage: patch, size: frame.size).draw(in: frame)
    }
}

public struct BlurAnnotation: Annotation {
    public let id = UUID()
    public var style = AnnotationStyle.default
    public var frame: CGRect
    public let patch: CGImage
    public init(frame: CGRect, patch: CGImage) { self.frame = frame; self.patch = patch }
    public func boundingBox() -> CGRect { frame }
    public func moved(by d: CGVector) -> any Annotation {
        var c = self; c.frame = frame.offsetBy(dx: d.dx, dy: d.dy); return c
    }
    public func draw() {
        NSImage(cgImage: patch, size: frame.size).draw(in: frame)
    }
}
```
Note: moving a redaction annotation shows the *original* patch over a new location (it does not re-sample). That's acceptable for v1; re-sampling on move is a later refinement.

- [ ] **Step 5: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter RedactorTests`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): blur/pixelate via CoreImage patches"
```

---

## Task 8: DocumentRenderer (flatten → CGImage) with golden test

**Files:**
- Create: `Sources/EditorKit/DocumentRenderer.swift`
- Test: `Tests/EditorKitTests/DocumentRendererTests.swift`

- [ ] **Step 1: Write the failing golden test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class DocumentRendererTests: XCTestCase {
    /// Read an (r,g,b,a) byte tuple at a top-left pixel coordinate.
    private func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return [buf[i], buf[i+1], buf[i+2], buf[i+3]]
    }

    private func whiteBase(_ n: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        return ctx.makeImage()!
    }

    func testRendersFilledRectAtTopLeftCoordsInRed() throws {
        var doc = EditorDocument(baseImage: whiteBase(100))
        var style = AnnotationStyle.default
        style.strokeColor = RGBAColor(r: 1, g: 0, b: 0, a: 1)
        // Top-left rect covering x:20..60, y:20..60.
        doc.add(FilledRectangleAnnotation(frame: CGRect(x: 20, y: 20, width: 40, height: 40), style: style))

        let out = try XCTUnwrap(DocumentRenderer.render(doc))
        XCTAssertEqual(out.width, 100)
        XCTAssertEqual(out.height, 100)

        let inside = pixel(out, 40, 40)   // center of the rect → red
        XCTAssertGreaterThan(inside[0], 200); XCTAssertLessThan(inside[1], 60)

        let corner = pixel(out, 5, 5)     // top-left empty → white
        XCTAssertGreaterThan(corner[0], 200)
        XCTAssertGreaterThan(corner[1], 200)
        XCTAssertGreaterThan(corner[2], 200)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter DocumentRendererTests`
Expected: FAIL — `cannot find 'DocumentRenderer'`.

- [ ] **Step 3: Implement**

`Sources/EditorKit/DocumentRenderer.swift`:
```swift
import AppKit
import CoreGraphics

public enum DocumentRenderer {
    /// Flattens the document into a CGImage. Used for both export and the canvas.
    public static func render(_ doc: EditorDocument) -> CGImage? {
        let w = doc.baseImage.width, h = doc.baseImage.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Flipped NSGraphicsContext → AppKit drawing uses top-left origin (incl. text, images).
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns

        NSImage(cgImage: doc.baseImage, size: NSSize(width: w, height: h))
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        for a in doc.annotations { a.draw() }

        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter DocumentRendererTests`
Expected: PASS (1 test). If the rect renders at the bottom instead of the top, the flip is wrong — recheck `flipped: true`.

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): DocumentRenderer flatten path + golden test"
```

---

## Task 9: Crop operation on the document

**Files:**
- Modify: `Sources/EditorKit/EditorDocument.swift` (add `cropped(to:)`)
- Test: `Tests/EditorKitTests/CropTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import EditorKit

final class CropTests: XCTestCase {
    private func base(_ n: Int) -> CGImage {
        CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    func testCropResizesBaseAndOffsetsAnnotations() throws {
        var doc = EditorDocument(baseImage: base(100))
        doc.add(RectangleAnnotation(frame: CGRect(x: 40, y: 40, width: 10, height: 10), filled: false))
        let cropped = try XCTUnwrap(doc.cropped(to: CGRect(x: 30, y: 30, width: 40, height: 40)))
        XCTAssertEqual(cropped.baseImage.width, 40)
        XCTAssertEqual(cropped.baseImage.height, 40)
        // Annotation shifts by (-30,-30): 40→10.
        XCTAssertEqual(cropped.annotations[0].boundingBox(), CGRect(x: 10, y: 10, width: 10, height: 10))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/EditorKit --filter CropTests`
Expected: FAIL — `value of type 'EditorDocument' has no member 'cropped'`.

- [ ] **Step 3: Implement**

Add to `EditorDocument` (in `EditorDocument.swift`):
```swift
    /// Returns a new document cropped to `rect` (top-left image coords), annotations offset to match.
    public func cropped(to rect: CGRect) -> EditorDocument? {
        let r = rect.integral
        let bounds = CGRect(x: 0, y: 0, width: baseImage.width, height: baseImage.height)
        let clamped = r.intersection(bounds)
        guard clamped.width >= 1, clamped.height >= 1,
              let newBase = baseImage.cropping(to: clamped) else { return nil }
        var d = EditorDocument(baseImage: newBase)
        let delta = CGVector(dx: -clamped.minX, dy: -clamped.minY)
        for a in annotations { d.add(a.moved(by: delta)) }
        return d
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/EditorKit --filter CropTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): document crop with annotation offset"
```

---

## Task 10: EditorCanvasView — create / select / move / delete / reorder (MANUAL verify)

**Files:**
- Create: `Sources/EditorKit/EditorCanvasView.swift`

Context: a flipped `NSView` (top-left coords). It renders the current `EditorDocument` via `DocumentRenderer`, maps view points to image points by a scale factor, and implements tool interactions. Interactive — verified in Task 13.

- [ ] **Step 1: Implement the canvas**

`Sources/EditorKit/EditorCanvasView.swift`:
```swift
import AppKit

public final class EditorCanvasView: NSView {
    public private(set) var document: EditorDocument
    public var tool: EditorTool = .select
    public var style = AnnotationStyle.default { didSet { needsDisplay = true } }
    public var onTextRequested: ((CGPoint) -> Void)?   // Task 11 wires inline editing

    private var selectedID: UUID?
    private var dragStartImagePoint: CGPoint?
    private var inProgress: (any Annotation)?

    public init(document: EditorDocument) {
        self.document = document
        super.init(frame: NSRect(origin: .zero, size: document.size))
    }
    required init?(coder: NSCoder) { fatalError() }

    public override var isFlipped: Bool { true }

    // MARK: - Coordinate mapping (view ↔ image)
    private var scale: CGFloat { document.size.width / max(bounds.width, 1) }
    private func imagePoint(_ viewPoint: NSPoint) -> CGPoint {
        CGPoint(x: viewPoint.x * scale, y: viewPoint.y * scale)
    }

    // MARK: - Rendering
    public override func draw(_ dirtyRect: NSRect) {
        guard let flat = DocumentRenderer.render(document) else { return }
        NSImage(cgImage: flat, size: bounds.size).draw(in: bounds)
        // Selection outline.
        if let id = selectedID, let i = document.index(of: id) {
            let bb = document.annotations[i].boundingBox()
            let viewRect = NSRect(x: bb.minX / scale, y: bb.minY / scale,
                                  width: bb.width / scale, height: bb.height / scale)
            NSColor.systemBlue.setStroke()
            let p = NSBezierPath(rect: viewRect.insetBy(dx: -2, dy: -2))
            p.lineWidth = 1; p.setLineDash([4, 3], count: 2, phase: 0); p.stroke()
        }
    }

    // MARK: - Mouse
    public override func mouseDown(with event: NSEvent) {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        dragStartImagePoint = p
        switch tool {
        case .select:
            selectedID = document.topmostHit(at: p); needsDisplay = true
        case .text:
            onTextRequested?(p)
        case .counter:
            document.add(CounterAnnotation(number: document.nextCounterNumber(),
                                           origin: p, style: style)); needsDisplay = true
        default:
            inProgress = nil // shape creation happens on drag
        }
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let start = dragStartImagePoint else { return }
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        switch tool {
        case .select:
            if let id = selectedID {
                document.move(id: id, by: CGVector(dx: (p.x - start.x), dy: (p.y - start.y)))
                dragStartImagePoint = p
            }
        case .arrow:
            inProgress = ArrowAnnotation(start: start, end: p, style: style)
        case .line:
            inProgress = LineAnnotation(start: start, end: p, style: style)
        case .rectangle:
            inProgress = RectangleAnnotation(frame: rect(start, p), filled: false, style: style)
        case .filledRectangle:
            inProgress = FilledRectangleAnnotation(frame: rect(start, p), style: style)
        case .ellipse:
            inProgress = EllipseAnnotation(frame: rect(start, p), style: style)
        default: break
        }
        needsDisplay = true
    }

    public override func mouseUp(with event: NSEvent) {
        if let a = inProgress { document.add(a); selectedID = a.id; inProgress = nil }
        dragStartImagePoint = nil; needsDisplay = true
    }

    // Live preview of the in-progress shape on top of the flattened doc.
    public override func updateLayer() {}
    private func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    // MARK: - Keyboard (delete, z-order)
    public override var acceptsFirstResponder: Bool { true }
    public override func keyDown(with event: NSEvent) {
        guard let id = selectedID else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 51, 117: document.remove(id: id); selectedID = nil   // Delete / Fwd-Delete
        default:
            if event.charactersIgnoringModifiers == "]" { document.bringToFront(id: id) }
            else if event.charactersIgnoringModifiers == "[" { document.sendToBack(id: id) }
            else { super.keyDown(with: event); return }
        }
        needsDisplay = true
    }

    // MARK: - Mutation entry points for the window controller / inline editor
    public func insert(_ annotation: any Annotation) {
        document.add(annotation); selectedID = annotation.id; needsDisplay = true
    }
    public func applyCrop(to imageRect: CGRect) {
        if let cropped = document.cropped(to: imageRect) {
            document = cropped
            frame = NSRect(origin: .zero, size: document.size)
            selectedID = nil; needsDisplay = true
        }
    }
    public func currentDocument() -> EditorDocument { document }
}
```
Note on in-progress preview: this minimal version commits the shape on `mouseUp`; the dragged shape isn't drawn until release because `draw(_:)` renders only `document`. If you want a live preview, also draw `inProgress?.draw()` after rendering the doc inside `draw(_:)` (wrap in `NSGraphicsContext` setup the same way `DocumentRenderer` does, scaled). Start without preview; add if the manual test feels off.

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/EditorKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): canvas view (create/select/move/delete/reorder)"
```

---

## Task 11: Inline text editing (MANUAL verify)

**Files:**
- Modify: `Sources/EditorKit/EditorCanvasView.swift` (handle `onTextRequested` via a floating NSTextField)

- [ ] **Step 1: Add an inline text-field editor**

Append to `EditorCanvasView` (inside the class) and wire it in `init`:
```swift
    private var activeField: NSTextField?

    private func beginTextEditing(atImagePoint p: CGPoint) {
        let viewPoint = NSPoint(x: p.x / scale, y: p.y / scale)
        let field = NSTextField(frame: NSRect(x: viewPoint.x, y: viewPoint.y, width: 200, height: 28))
        field.font = .systemFont(ofSize: style.fontSize / scale, weight: .semibold)
        field.textColor = style.strokeColor.nsColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.target = self
        field.action = #selector(commitText(_:))
        addSubview(field)
        window?.makeFirstResponder(field)
        activeField = field
        textImageOrigin = p
    }
    private var textImageOrigin: CGPoint = .zero

    @objc private func commitText(_ sender: NSTextField) {
        let text = sender.stringValue
        sender.removeFromSuperview(); activeField = nil
        guard !text.isEmpty else { needsDisplay = true; return }
        insert(TextAnnotation(text: text, origin: textImageOrigin, style: style))
    }
```
And in `init`, set the request hook:
```swift
        self.onTextRequested = { [weak self] p in self?.beginTextEditing(atImagePoint: p) }
```
(Place that line after `super.init(...)` in `init(document:)`.)

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/EditorKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): inline text editing"
```

---

## Task 12: EditorWindowController — toolbar, color, crop, export (MANUAL verify)

**Files:**
- Create: `Sources/EditorKit/EditorWindowController.swift`

Context: an `NSWindowController` hosting a tool palette (one button per `EditorTool`), an `NSColorWell`, the canvas (in an `NSScrollView`), and Copy / Save / Done buttons. Crop and redaction tools need access to the base image; the controller mediates.

- [ ] **Step 1: Implement**

`Sources/EditorKit/EditorWindowController.swift`:
```swift
import AppKit

public final class EditorWindowController: NSWindowController {
    private let canvas: EditorCanvasView
    private var style = AnnotationStyle.default
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?

    public init(image: CGImage) {
        let doc = EditorDocument(baseImage: image)
        self.canvas = EditorCanvasView(document: doc)

        let displayW = min(CGFloat(image.width), 1200)
        let displayH = displayW * CGFloat(image.height) / CGFloat(image.width)
        canvas.frame = NSRect(x: 0, y: 0, width: displayW, height: displayH)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: displayW + 24, height: displayH + 96),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Annotate"
        super.init(window: window)
        buildUI(canvasSize: NSSize(width: displayW, height: displayH))
    }
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(canvasSize: NSSize) {
        guard let content = window?.contentView else { return }

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.spacing = 4
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        for tool in EditorTool.allCases {
            let b = NSButton(title: label(for: tool), target: self, action: #selector(selectTool(_:)))
            b.bezelStyle = .texturedRounded
            b.tag = EditorTool.allCases.firstIndex(of: tool)!
            toolbar.addArrangedSubview(b)
        }
        let colorWell = NSColorWell()
        colorWell.color = style.strokeColor.nsColor
        colorWell.target = self; colorWell.action = #selector(colorChanged(_:))
        toolbar.addArrangedSubview(colorWell)

        let scroll = NSScrollView()
        scroll.documentView = canvas
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let actions = NSStackView()
        actions.orientation = .horizontal; actions.spacing = 8
        actions.translatesAutoresizingMaskIntoConstraints = false
        let copyBtn = NSButton(title: "Copy", target: self, action: #selector(copyAction))
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveAction))
        let doneBtn = NSButton(title: "Done", target: self, action: #selector(doneAction))
        [copyBtn, saveBtn, doneBtn].forEach { actions.addArrangedSubview($0) }

        content.addSubview(toolbar); content.addSubview(scroll); content.addSubview(actions)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            actions.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 8),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -8),
        ])
    }

    private func label(for tool: EditorTool) -> String {
        switch tool {
        case .select: return "Select"; case .arrow: return "Arrow"; case .line: return "Line"
        case .rectangle: return "Rect"; case .filledRectangle: return "Fill"; case .ellipse: return "Oval"
        case .text: return "Text"; case .counter: return "1•"; case .blur: return "Blur"
        case .pixelate: return "Pixel"; case .crop: return "Crop"
        }
    }

    @objc private func selectTool(_ sender: NSButton) {
        canvas.tool = EditorTool.allCases[sender.tag]
    }
    @objc private func colorChanged(_ sender: NSColorWell) {
        style.strokeColor = RGBAColor(sender.color)
        style.fillColor = RGBAColor(sender.color.withAlphaComponent(0.25))
        canvas.style = style
    }
    @objc private func copyAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onCopy?(img)
    }
    @objc private func saveAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onSave?(img)
    }
    @objc private func doneAction() { window?.close() }
}
```
Note: blur/pixelate/crop tools need region selection inside the canvas. For v1, wire them as follows in the canvas `mouseUp` (extend Task 10's `default` create path): when `tool == .blur`/`.pixelate`, build the patch with `Redactor` from `document.baseImage` for the dragged rect and `insert(...)` the redaction annotation; when `tool == .crop`, call `applyCrop(to:)` with the dragged rect. Add these cases to `EditorCanvasView.mouseUp` now:
```swift
    // Add inside mouseUp, before the final needsDisplay, replacing the simple commit:
    // (full mouseUp shown for clarity)
    public override func mouseUp(with event: NSEvent) {
        let p = imagePoint(convert(event.locationInWindow, from: nil))
        let start = dragStartImagePoint ?? p
        let r = rect(start, p)
        switch tool {
        case .blur:
            if r.width >= 2, r.height >= 2,
               let patch = Redactor.blur(document.baseImage, region: r, radius: 12) {
                insert(BlurAnnotation(frame: r, patch: patch))
            }
        case .pixelate:
            if r.width >= 2, r.height >= 2,
               let patch = Redactor.pixelate(document.baseImage, region: r, blockSize: 12) {
                insert(PixelateAnnotation(frame: r, patch: patch))
            }
        case .crop:
            if r.width >= 4, r.height >= 4 { applyCrop(to: r) }
        default:
            if let a = inProgress { document.add(a); selectedID = a.id; inProgress = nil }
        }
        dragStartImagePoint = nil; needsDisplay = true
    }
```
(Delete the original simpler `mouseUp` from Task 10 and use this one.)

- [ ] **Step 2: Verify it compiles**

Run: `swift build --package-path Packages/EditorKit`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Packages/EditorKit
git commit -m "feat(editor): editor window (toolbar/color/crop/redaction/export)"
```

---

## Task 13: Wire the editor into the app (MANUAL verify)

**Files:**
- Modify: `project.yml` (add EditorKit dependency)
- Modify: `App/CaptureCoordinator.swift` (present the editor; reuse copy/save)
- Modify: `App/BetterScreenshotApp.swift` (set `editorPresenter`)

- [ ] **Step 1: Add the package dependency**

In `project.yml`, under `packages:` add:
```yaml
  EditorKit:
    path: Packages/EditorKit
```
and under `targets: BetterScreenshot: dependencies:` add:
```yaml
      - package: EditorKit
```

- [ ] **Step 2: Present the editor from the coordinator**

In `App/CaptureCoordinator.swift`, add `import EditorKit` at the top, add a stored property to retain the controller, and add a method:
```swift
    private var editorController: EditorWindowController?

    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```
(`copy(_:)` and `save(_:)` already exist from Plan 2.)

- [ ] **Step 3: Wire the presenter at launch**

In `App/BetterScreenshotApp.swift`, inside `applicationDidFinishLaunching`, after `coordinator` is created, add:
```swift
        coordinator.editorPresenter = { [weak coordinator] image in
            coordinator?.presentEditor(image)
        }
```

- [ ] **Step 4: Build**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Manual end-to-end verification**

Open the app, capture an area, click **Edit** on the overlay:
- [ ] Editor window opens showing the screenshot.
- [ ] Arrow / Line / Rect / Fill / Oval: drag to draw; color well changes new objects' color.
- [ ] Text: click, type, Return commits text at that point.
- [ ] Counter: click places auto-incrementing numbered badges (1, 2, 3…).
- [ ] Blur / Pixelate: drag a region → that region is obscured.
- [ ] Crop: drag a region → image crops to it; existing annotations stay aligned.
- [ ] Select tool: click an object (blue dashed outline), drag to move, Delete removes it, `[`/`]` change z-order.
- [ ] Copy puts the flattened annotated image on the clipboard; Save writes it to the save folder; Done closes.

- [ ] **Step 6: Commit**

```bash
git add project.yml App/CaptureCoordinator.swift App/BetterScreenshotApp.swift
git commit -m "feat(app): open annotation editor from Quick Access Overlay"
```

---

## Task 14 (STRETCH): Resize handles for rect-defined shapes (MANUAL verify)

Optional. Adds 8 corner/edge handles to the selection of rect-based annotations (`RectangleAnnotation`, `FilledRectangleAnnotation`, `EllipseAnnotation`, `BlurAnnotation`, `PixelateAnnotation`) so a selected object can be resized by dragging a handle. Line/arrow/text/counter are not resizable in v1 (delete & redraw, or change font size for text).

- [ ] **Step 1:** In `EditorCanvasView.draw`, when a rect-based annotation is selected, draw 8 small filled squares at its bounding-box corners/edges (in view coords).
- [ ] **Step 2:** In `mouseDown`, hit-test the handles first; if one is hit, record which handle + the original frame.
- [ ] **Step 3:** In `mouseDragged`, when a handle is active, compute the new frame from the drag and `document.replace(id:with:)` a copy of the annotation with the updated `frame` (each rect-based type already exposes a mutable `frame`).
- [ ] **Step 4:** Manual test: select a rectangle, drag a corner → it resizes; the same for ellipse/fill/blur/pixelate.
- [ ] **Step 5:** Commit: `git commit -m "feat(editor): resize handles for rect-based shapes"`

---

## Task 15: Regression + milestone

- [ ] **Step 1: Run the full unit suite for both packages**

Run:
```bash
swift test --package-path Packages/CaptureKit
swift test --package-path Packages/EditorKit
```
Expected: ALL PASS.

- [ ] **Step 2: Clean build the app**

Run:
```bash
rm -rf build && xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Re-run the Task 13 manual checklist end-to-end.**

- [ ] **Step 4: Tag the milestone (v1 complete)**

```bash
git commit -m "chore: Plan 3 (Annotation Editor) complete — v1 done" --allow-empty
git tag v1.0
```

---

## Definition of Done (Plan 3 / v1)

- `EditorKit` model + renderer + crop are unit-tested green (`swift test`).
- The overlay's "Edit" button opens the editor on the capture.
- All v1 tools work: arrow, line, rectangle, filled rectangle, ellipse, text, counter, blur, pixelate, crop, color picker, select/move/delete/reorder.
- Copy and Save export the flattened annotated image (clipboard / save folder).
- The full capture → overlay → annotate → export flow works end-to-end.

**v1 is complete.** Subsequent milestones (recording, OCR, pin, scrolling/backgrounds/freeze, URL automation) are Plans 4+ per the design's phase roadmap.
```
