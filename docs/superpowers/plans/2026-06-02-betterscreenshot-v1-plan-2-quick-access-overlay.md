# BetterScreenshot v1 — Plan 2: Quick Access Overlay

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **PREREQUISITE: Plan 1 (Foundation & Capture Core) must be complete** — this plan depends on `CaptureKit`, `OverlayKit`, `CaptureCoordinator`, `SettingsStore`, and `CaptureSettings`/`AfterCaptureBehavior` from Plan 1.

**Goal:** After a capture, instead of silently copying/saving, show a floating thumbnail in a screen corner (the "Quick Access Overlay") with Copy / Save / Annotate / Close actions and drag-out-to-other-apps support, auto-dismissing after a configurable delay.

**Architecture:** Add a `QuickAccessOverlayController` (a non-activating floating `NSPanel`) to `OverlayKit`, plus two pure helpers in `CaptureKit` (`OverlayPositioner` for corner placement math, `TempImageWriter` for drag-out temp files). `CaptureCoordinator` gains a `.showOverlay` branch that presents the overlay and routes button actions back to its existing copy/save logic. The Annotate button calls a `coordinator.annotate(image:)` hook that is a stub in this plan and is filled in by Plan 3.

**Tech Stack:** Same as Plan 1 (Swift, macOS 14, AppKit, ScreenCaptureKit, XCTest, XcodeGen).

**Reference:** `docs/superpowers/specs/2026-06-02-betterscreenshot-v1-design.md` §6 (Quick Access Overlay).

**Out of scope (later):** capture history / restore-recently-closed (Plan 4), editor itself (Plan 3).

---

## File Structure (added/modified by this plan)

```
Packages/CaptureKit/Sources/CaptureKit/
  OverlayPositioner.swift     (new, PURE)
  TempImageWriter.swift       (new, PURE)
  CaptureSettings.swift       (modified — add .showOverlay + overlay prefs)
Packages/CaptureKit/Tests/CaptureKitTests/
  OverlayPositionerTests.swift (new)
  TempImageWriterTests.swift   (new)
  CaptureSettingsTests.swift   (modified)
Packages/OverlayKit/Sources/OverlayKit/
  QuickAccessOverlayController.swift (new, manual-tested)
  DraggableImageView.swift           (new, manual-tested)
App/
  CaptureCoordinator.swift    (modified — .showOverlay branch + annotate stub)
  SettingsView.swift          (modified — overlay options)
```

---

## Task 1: Extend settings with overlay behavior + preferences

**Files:**
- Modify: `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/CaptureSettingsTests.swift`

- [ ] **Step 1: Update the failing test**

Replace the contents of `CaptureSettingsTests.swift`:
```swift
import XCTest
@testable import CaptureKit

final class CaptureSettingsTests: XCTestCase {
    func testDefaultsToShowOverlay() {
        let s = CaptureSettings.default
        XCTAssertEqual(s.afterCapture, .showOverlay)
        XCTAssertEqual(s.format, .png)
        XCTAssertEqual(s.overlayCorner, .bottomRight)
        XCTAssertEqual(s.overlayAutoDismissSeconds, 6)
    }

    func testRoundTripsAllFields() {
        var s = CaptureSettings.default
        s.afterCapture = .saveOnly
        s.format = .jpg
        s.overlayCorner = .topLeft
        s.overlayAutoDismissSeconds = 10
        let restored = CaptureSettings(dictionary: s.dictionary)
        XCTAssertEqual(restored, s)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureSettingsTests`
Expected: FAIL — `.showOverlay` / `overlayCorner` not members.

- [ ] **Step 3: Update CaptureSettings**

Replace `Packages/CaptureKit/Sources/CaptureKit/CaptureSettings.swift`:
```swift
import Foundation

public enum AfterCaptureBehavior: String, Equatable, CaseIterable {
    case copyOnly, saveOnly, copyAndSave, showOverlay
}

public enum SettingsImageFormat: String, Equatable, CaseIterable {
    case png, jpg
}

public enum OverlayCorner: String, Equatable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

public struct CaptureSettings: Equatable {
    public var afterCapture: AfterCaptureBehavior
    public var format: SettingsImageFormat
    public var overlayCorner: OverlayCorner
    public var overlayAutoDismissSeconds: Int

    public static let `default` = CaptureSettings(
        afterCapture: .showOverlay, format: .png,
        overlayCorner: .bottomRight, overlayAutoDismissSeconds: 6)

    public var dictionary: [String: String] {
        ["afterCapture": afterCapture.rawValue,
         "format": format.rawValue,
         "overlayCorner": overlayCorner.rawValue,
         "overlayAutoDismissSeconds": String(overlayAutoDismissSeconds)]
    }

    public init(afterCapture: AfterCaptureBehavior, format: SettingsImageFormat,
                overlayCorner: OverlayCorner, overlayAutoDismissSeconds: Int) {
        self.afterCapture = afterCapture
        self.format = format
        self.overlayCorner = overlayCorner
        self.overlayAutoDismissSeconds = overlayAutoDismissSeconds
    }

    public init(dictionary: [String: String]) {
        let d = CaptureSettings.default
        self.afterCapture = AfterCaptureBehavior(rawValue: dictionary["afterCapture"] ?? "") ?? d.afterCapture
        self.format = SettingsImageFormat(rawValue: dictionary["format"] ?? "") ?? d.format
        self.overlayCorner = OverlayCorner(rawValue: dictionary["overlayCorner"] ?? "") ?? d.overlayCorner
        self.overlayAutoDismissSeconds = Int(dictionary["overlayAutoDismissSeconds"] ?? "") ?? d.overlayAutoDismissSeconds
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter CaptureSettingsTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(settings): add showOverlay behavior + overlay corner/auto-dismiss prefs"
```

---

## Task 2: OverlayPositioner (PURE — corner placement math)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/OverlayPositioner.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/OverlayPositionerTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import CaptureKit

final class OverlayPositionerTests: XCTestCase {
    // Screen 1440x900 at origin (0,0); overlay 200x140; margin 16.
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let size = CGSize(width: 200, height: 140)

    func testBottomRight() {
        let o = OverlayPositioner.origin(corner: .bottomRight, overlaySize: size,
                                         screenFrame: screen, margin: 16)
        // Cocoa bottom-left origin: x = 1440-200-16 = 1224; y = 16
        XCTAssertEqual(o, CGPoint(x: 1224, y: 16))
    }

    func testTopLeft() {
        let o = OverlayPositioner.origin(corner: .topLeft, overlaySize: size,
                                         screenFrame: screen, margin: 16)
        // x = 16; y = 900 - 140 - 16 = 744
        XCTAssertEqual(o, CGPoint(x: 16, y: 744))
    }

    func testTopRightWithDisplayOffset() {
        let s2 = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        let o = OverlayPositioner.origin(corner: .topRight, overlaySize: size,
                                         screenFrame: s2, margin: 20)
        // x = 1440 + 1920 - 200 - 20 = 3140; y = 1080 - 140 - 20 = 920
        XCTAssertEqual(o, CGPoint(x: 3140, y: 920))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter OverlayPositionerTests`
Expected: FAIL — `cannot find 'OverlayPositioner'`.

- [ ] **Step 3: Implement**

```swift
import CoreGraphics

public enum OverlayPositioner {
    /// Returns the Cocoa (bottom-left origin) origin for an overlay window in a screen corner.
    public static func origin(corner: OverlayCorner, overlaySize: CGSize,
                              screenFrame: CGRect, margin: CGFloat) -> CGPoint {
        let leftX = screenFrame.minX + margin
        let rightX = screenFrame.maxX - overlaySize.width - margin
        let bottomY = screenFrame.minY + margin
        let topY = screenFrame.maxY - overlaySize.height - margin
        switch corner {
        case .topLeft:     return CGPoint(x: leftX,  y: topY)
        case .topRight:    return CGPoint(x: rightX, y: topY)
        case .bottomLeft:  return CGPoint(x: leftX,  y: bottomY)
        case .bottomRight: return CGPoint(x: rightX, y: bottomY)
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter OverlayPositionerTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(overlay): OverlayPositioner corner placement math"
```

---

## Task 3: TempImageWriter (PURE — temp file for drag-out)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/TempImageWriter.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/TempImageWriterTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
import CoreGraphics
@testable import CaptureKit

final class TempImageWriterTests: XCTestCase {
    private func makeImage() -> CGImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                            bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return ctx.makeImage()!
    }

    func testWritesPNGToTempAndFileExists() throws {
        let url = try XCTUnwrap(TempImageWriter.writePNG(makeImage(), fileName: "DragTest.png"))
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "png")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path Packages/CaptureKit --filter TempImageWriterTests`
Expected: FAIL — `cannot find 'TempImageWriter'`.

- [ ] **Step 3: Implement**

```swift
import Foundation
import CoreGraphics

public enum TempImageWriter {
    /// Writes a PNG into a unique temp subdirectory and returns its URL (nil on failure).
    public static func writePNG(_ image: CGImage, fileName: String) -> URL? {
        guard let data = ImageEncoder.encode(image, as: .png) else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BetterScreenshot-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(fileName)
            try data.write(to: url)
            return url
        } catch { return nil }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --package-path Packages/CaptureKit --filter TempImageWriterTests`
Expected: PASS (1 test).

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(overlay): TempImageWriter for drag-out files"
```

---

## Task 4: DraggableImageView + QuickAccessOverlayController (OverlayKit — MANUAL verify)

**Files:**
- Create: `Packages/OverlayKit/Sources/OverlayKit/DraggableImageView.swift`
- Create: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift`

Context: a non-activating `NSPanel` showing a thumbnail and four buttons. The thumbnail is draggable (writes a temp file URL to the drag pasteboard). The panel auto-dismisses after N seconds unless the mouse is hovering it. Interactive — verified manually in Task 5.

- [ ] **Step 1: Implement the draggable thumbnail view**

`DraggableImageView.swift`:
```swift
import AppKit

/// An image view that starts a file drag (of a temp file URL) when dragged.
public final class DraggableImageView: NSImageView, NSDraggingSource {
    public var fileURLProvider: (() -> URL?)?

    public func draggingSession(_ session: NSDraggingSession,
                                sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    public override func mouseDown(with event: NSEvent) {
        guard let url = fileURLProvider?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        if let img = image {
            item.setDraggingFrame(bounds, contents: img)
        }
        beginDraggingSession(with: [item], event: event, source: self)
    }
}
```

- [ ] **Step 2: Implement the overlay controller**

`QuickAccessOverlayController.swift`:
```swift
import AppKit

public struct QuickAccessActions {
    public let onCopy: () -> Void
    public let onSave: () -> Void
    public let onAnnotate: () -> Void
    public let fileURLForDrag: () -> URL?
    public init(onCopy: @escaping () -> Void, onSave: @escaping () -> Void,
                onAnnotate: @escaping () -> Void, fileURLForDrag: @escaping () -> URL?) {
        self.onCopy = onCopy; self.onSave = onSave
        self.onAnnotate = onAnnotate; self.fileURLForDrag = fileURLForDrag
    }
}

public final class QuickAccessOverlayController {
    private var panel: NSPanel?
    private var dismissTimer: Timer?
    private var actions: QuickAccessActions?

    public init() {}

    /// Presents the overlay at the given screen origin (Cocoa bottom-left coords).
    public func present(image: NSImage, at origin: CGPoint,
                        autoDismissSeconds: Int, actions: QuickAccessActions) {
        dismiss()
        self.actions = actions

        let size = NSSize(width: 220, height: 168)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 12

        let thumb = DraggableImageView(frame: NSRect(x: 10, y: 46, width: 200, height: 112))
        thumb.image = image
        thumb.imageScaling = .scaleProportionallyUpOrDown
        thumb.wantsLayer = true
        thumb.layer?.cornerRadius = 6
        thumb.layer?.masksToBounds = true
        thumb.fileURLProvider = actions.fileURLForDrag
        container.addSubview(thumb)

        let stack = NSStackView(frame: NSRect(x: 10, y: 8, width: 200, height: 30))
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.spacing = 6
        stack.addArrangedSubview(button("Copy", #selector(copyAction)))
        stack.addArrangedSubview(button("Save", #selector(saveAction)))
        stack.addArrangedSubview(button("Edit", #selector(annotateAction)))
        stack.addArrangedSubview(button("✕", #selector(closeAction)))
        container.addSubview(stack)

        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        // Auto-dismiss unless hovered.
        let tracking = NSTrackingArea(rect: container.bounds,
            options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        container.addTrackingArea(tracking)
        scheduleDismiss(after: autoDismissSeconds)
    }

    public func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        panel?.orderOut(nil); panel = nil; actions = nil
    }

    private func scheduleDismiss(after seconds: Int) {
        dismissTimer?.invalidate()
        guard seconds > 0 else { return }
        dismissTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(seconds),
                                            repeats: false) { [weak self] _ in self?.dismiss() }
    }

    public func mouseEntered(with event: NSEvent) { dismissTimer?.invalidate() }
    public func mouseExited(with event: NSEvent) { scheduleDismiss(after: 3) }

    private func button(_ title: String, _ sel: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: sel)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 11)
        return b
    }

    @objc private func copyAction() { actions?.onCopy(); dismiss() }
    @objc private func saveAction() { actions?.onSave(); dismiss() }
    @objc private func annotateAction() { actions?.onAnnotate(); dismiss() }
    @objc private func closeAction() { dismiss() }
}

extension QuickAccessOverlayController {
    // NSTrackingArea calls require the owner to respond; route via the panel's content view owner.
    // (mouseEntered/mouseExited above are invoked because this controller is the tracking owner.)
}
```
Note: `QuickAccessOverlayController` is the tracking-area owner, so its `mouseEntered/mouseExited` fire. If hover behavior misbehaves during manual test, move the tracking area onto a small `NSView` subclass that forwards to the controller — but start with this simpler form.

- [ ] **Step 3: Verify it compiles**

Run: `swift build --package-path Packages/OverlayKit`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add Packages/OverlayKit
git commit -m "feat(overlay): Quick Access Overlay panel with drag-out + auto-dismiss"
```

---

## Task 5: Route captures through the overlay (CaptureCoordinator — MANUAL verify)

**Files:**
- Modify: `App/CaptureCoordinator.swift`

- [ ] **Step 1: Refactor output + add the overlay branch and annotate stub**

Replace the `output(_:)` method in `App/CaptureCoordinator.swift` and add new members. The full updated file:
```swift
import AppKit
import ScreenCaptureKit
import CaptureKit
import OverlayKit

@MainActor
final class CaptureCoordinator {
    private let service = CaptureService()
    private let settings: SettingsStore
    private let overlay = SelectionOverlayController()
    private let quickAccess = QuickAccessOverlayController()

    /// Filled in by Plan 3 to present the annotation editor. Nil = stub.
    var editorPresenter: ((CGImage) -> Void)?

    init(settings: SettingsStore) { self.settings = settings }

    func captureArea() {
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self, let result else { return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID)) }
        }
    }

    func captureFullscreen() {
        guard ensurePermission() else { return }
        Task { await run(.fullscreen(displayID: CGMainDisplayID())) }
    }

    func captureFrontWindow() {
        guard ensurePermission() else { return }
        Task { if let id = await frontmostWindowID() { await run(.window(windowID: id)) } }
    }

    private func run(_ target: CaptureTarget) async {
        do {
            let image = try await service.capture(target)
            handle(image)
        } catch { NSLog("Capture failed: \(error)") }
    }

    private func handle(_ image: CGImage) {
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image)
        }
    }

    private func presentOverlay(_ image: CGImage) {
        let nsImage = NSImage(cgImage: image, size: .zero)
        guard let screen = NSScreen.main else { copy(image); save(image); return }
        let origin = OverlayPositioner.origin(
            corner: settings.settings.overlayCorner,
            overlaySize: CGSize(width: 220, height: 168),
            screenFrame: screen.frame, margin: 16)
        let actions = QuickAccessActions(
            onCopy: { [weak self] in self?.copy(image) },
            onSave: { [weak self] in self?.save(image) },
            onAnnotate: { [weak self] in self?.annotate(image) },
            fileURLForDrag: { TempImageWriter.writePNG(image, fileName: FileNamer.fileName(for: Date(), ext: "png")) })
        quickAccess.present(image: nsImage, at: origin,
                            autoDismissSeconds: settings.settings.overlayAutoDismissSeconds,
                            actions: actions)
    }

    /// Plan 3 replaces the stub body via `editorPresenter`.
    func annotate(_ image: CGImage) {
        if let present = editorPresenter { present(image) }
        else { NSLog("Annotate requested — editor arrives in Plan 3") }
    }

    private func copy(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let nsImage = NSImage(); nsImage.addRepresentation(rep)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([nsImage])
    }

    private func save(_ image: CGImage) {
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else { return }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        try? data.write(to: settings.saveDirectory.appendingPathComponent(name))
    }

    private func ensurePermission() -> Bool {
        if PermissionManager.hasScreenRecordingPermission { return true }
        PermissionManager.requestScreenRecordingPermission()
        if !PermissionManager.hasScreenRecordingPermission {
            PermissionManager.presentDeniedAlert(); return false
        }
        return true
    }

    private func frontmostWindowID() async -> CGWindowID? {
        let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        return content?.windows.first(where: { $0.isOnScreen && $0.title?.isEmpty == false })?.windowID
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification**

Open the app, capture an area (default behavior is now `.showOverlay`):
- [ ] A thumbnail panel appears in the bottom-right corner.
- [ ] **Copy** puts the image on the clipboard and dismisses.
- [ ] **Save** writes a PNG to the save folder and dismisses.
- [ ] **Edit** logs "editor arrives in Plan 3" (stub) and dismisses.
- [ ] Dragging the thumbnail into Finder/Notes drops a PNG file.
- [ ] The panel auto-dismisses after ~6s; hovering it pauses the timer.
- [ ] ✕ closes immediately.

- [ ] **Step 4: Commit**

```bash
git add App/CaptureCoordinator.swift
git commit -m "feat(capture): route captures through Quick Access Overlay"
```

---

## Task 6: Settings UI for overlay options

**Files:**
- Modify: `App/SettingsView.swift`

- [ ] **Step 1: Add overlay controls**

Replace `App/SettingsView.swift`:
```swift
import SwiftUI
import CaptureKit

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        Form {
            Picker("After capture", selection: bind(\.afterCapture)) {
                Text("Show overlay").tag(AfterCaptureBehavior.showOverlay)
                Text("Copy to clipboard").tag(AfterCaptureBehavior.copyOnly)
                Text("Save to folder").tag(AfterCaptureBehavior.saveOnly)
                Text("Copy and save").tag(AfterCaptureBehavior.copyAndSave)
            }
            Picker("Format", selection: bind(\.format)) {
                Text("PNG").tag(SettingsImageFormat.png)
                Text("JPG").tag(SettingsImageFormat.jpg)
            }
            Picker("Overlay corner", selection: bind(\.overlayCorner)) {
                Text("Bottom-right").tag(OverlayCorner.bottomRight)
                Text("Bottom-left").tag(OverlayCorner.bottomLeft)
                Text("Top-right").tag(OverlayCorner.topRight)
                Text("Top-left").tag(OverlayCorner.topLeft)
            }
            Stepper("Auto-dismiss after \(store.settings.overlayAutoDismissSeconds)s",
                    value: Binding(
                        get: { store.settings.overlayAutoDismissSeconds },
                        set: { store.settings.overlayAutoDismissSeconds = $0; store.persist() }),
                    in: 0...30)
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func bind<V>(_ keyPath: WritableKeyPath<CaptureSettings, V>) -> Binding<V> {
        Binding(get: { store.settings[keyPath: keyPath] },
                set: { store.settings[keyPath: keyPath] = $0; store.persist() })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            store.saveDirectory = url; store.persist()
        }
    }
}
```

- [ ] **Step 2: Build**

Run:
```bash
xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Manual verification**
- [ ] All controls render; changing "Overlay corner" moves the next capture's overlay.
- [ ] Auto-dismiss stepper changes the timer (set to 0 → overlay stays until ✕/action).
- [ ] Settings persist across relaunch.

- [ ] **Step 4: Commit**

```bash
git add App/SettingsView.swift
git commit -m "feat(settings): overlay corner + auto-dismiss controls"
```

---

## Task 7: Regression + milestone

- [ ] **Step 1: Run full unit suite**

Run: `swift test --package-path Packages/CaptureKit`
Expected: ALL PASS (now includes OverlayPositioner, TempImageWriter, updated CaptureSettings).

- [ ] **Step 2: Clean build**

Run:
```bash
rm -rf build && xcodegen generate
xcodebuild -project BetterScreenshot.xcodeproj -scheme BetterScreenshot -configuration Debug -derivedDataPath build build
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 3: Re-run Task 5 + Task 6 manual checklists.**

- [ ] **Step 4: Tag**

```bash
git commit -m "chore: Plan 2 (Quick Access Overlay) complete" --allow-empty
git tag v0.2-quick-access
```

---

## Definition of Done (Plan 2)

- Default capture flow shows a corner thumbnail with Copy / Save / Edit / Close.
- Drag-out drops a real PNG file into other apps.
- Auto-dismiss works and pauses on hover; corner + delay configurable in Settings.
- The Annotate path calls `coordinator.annotate(_:)` (stub) — ready for Plan 3 to fill via `editorPresenter`.
- All `swift test` pure-logic tests pass.

**Next:** Plan 3 builds `EditorKit` and sets `coordinator.editorPresenter` so "Edit" opens the annotation editor.
```
