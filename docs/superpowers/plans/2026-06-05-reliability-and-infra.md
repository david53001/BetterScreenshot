# Reliability Sprint + Infra & Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the silent data-loss paths, the recorder finish race, and the editor canvas re-flatten found by the 2026-06-05 codebase scan (`CODEBASE-SCAN.md`), plus CI, accessibility labels, doc fixes, and overlay-consistency polish.

**Architecture:** All changes are surgical edits to existing files — no new modules. App-target changes (coordinators, PermissionManager) are verified by `swift build` + the manual checklist at the end (project norm: App behavior is manually verified). Pure-logic changes (CounterAnnotation, Redactor tests) are TDD'd with the TestKit harness.

**Tech Stack:** Swift 5.9 / SwiftPM, AppKit, ScreenCaptureKit, AVFoundation, TestKit executable test runners (`swift run --package-path Packages/<Kit> <Kit>Tests`), GitHub Actions (macos-14).

**Branch note:** This project commits directly to `main` (established convention — plans 1–3, P3, v2.0 all did). Working tree must be clean before starting.

**Build/test commands (no Xcode — CLT only):**
- Build: `swift build` (from repo root)
- Tests: `swift run --package-path Packages/CaptureKit CaptureKitTests` (same pattern for OverlayKit, EditorKit, RecordingKit)

---

### Task 1: Surface save & capture failures + ensure save directory (CaptureCoordinator)

The scan's top user-facing bug: `save()` swallows encode/write failures (`try?`), and the save directory is never created/validated — a moved folder or full disk silently loses screenshots. Capture and OCR failures only hit `NSLog`. The HUD toast system already exists (`hud` property) — route errors through it.

**Files:**
- Modify: `App/CaptureCoordinator.swift:71-99` (run/runCaptureText catches) and `:183-190` (save)

- [ ] **Step 1: Replace `save(_:to:)` with a directory-ensuring, error-surfacing version**

In `App/CaptureCoordinator.swift`, replace:

```swift
    private func save(_ image: CGImage, to directory: URL? = nil) {
        let dir = directory ?? settings.saveDirectory
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else { return }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        try? data.write(to: dir.appendingPathComponent(name))
    }
```

with:

```swift
    private func save(_ image: CGImage, to directory: URL? = nil) {
        let dir = directory ?? settings.saveDirectory
        let isPNG = settings.settings.format == .png
        let format: ImageFormat = isPNG ? .png : .jpg(quality: 0.9)
        guard let data = ImageEncoder.encode(image, as: format) else {
            hud.show("Couldn't save — image encoding failed")
            return
        }
        let name = FileNamer.fileName(for: Date(), ext: isPNG ? "png" : "jpg")
        do {
            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name))
        } catch {
            NSLog("Save failed: \(error)")
            hud.show("Couldn't save screenshot")
        }
    }
```

- [ ] **Step 2: Surface capture failures in `run` and `runCaptureText`**

Replace the catch in `run(_:sourceRect:)`:

```swift
        } catch { NSLog("Capture failed: \(error)") }
```

with:

```swift
        } catch {
            NSLog("Capture failed: \(error)")
            hud.show("Capture failed")
        }
```

Replace the catch in `runCaptureText(_:)`:

```swift
        } catch { NSLog("Capture Text failed: \(error)") }
```

with:

```swift
        } catch {
            NSLog("Capture Text failed: \(error)")
            hud.show("Capture Text failed", on: screen(for: result.displayID))
        }
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add App/CaptureCoordinator.swift
git commit -m "fix(capture): surface save/capture failures via HUD; ensure save directory exists

Silent data-loss path from CODEBASE-SCAN.md: try? data.write swallowed
disk-full/missing-folder errors with no user feedback (the user's only
copy in saveOnly mode), and capture/OCR failures only hit NSLog.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Ensure recording save directory + honor mic-permission denial (RecordingCoordinator)

Recordings write straight into `settings.saveDirectory` (MP4) or move into it (GIF/fallbacks) without ensuring it exists. And `begin` discards the mic-permission result, so a denial still adds a mic track to the writer (silent empty track, no signal).

**Files:**
- Modify: `App/RecordingCoordinator.swift:104-139` (begin) and `:175-180` (stop)

- [ ] **Step 1: Honor the mic-permission result in `begin`**

In `begin(globalRect:screen:)`, change line 108:

```swift
        let config = settings.recording
```

to:

```swift
        var config = settings.recording
```

and replace (lines 137-139):

```swift
            if config.microphone {
                _ = await MicCapturer.ensurePermission()
            }
```

with:

```swift
            if config.microphone, await MicCapturer.ensurePermission() == false {
                // Denied: record without a mic track instead of writing an empty one.
                config.microphone = false
                hud.show("Mic access denied — recording without microphone", on: screen)
            }
```

- [ ] **Step 2: Ensure the save directory in `begin` and `stop`**

In `begin`, the MP4 path writes directly into the save folder. Just before the `try await recorder.start(...)` line, add (it's inside the existing `do` block, so a failure lands in the catch that already shows "Couldn't start recording"):

```swift
            // The chosen folder may have been deleted/renamed since it was set.
            try FileManager.default.createDirectory(at: settings.saveDirectory,
                                                    withIntermediateDirectories: true)
```

In `stop()`, after `let config = settings.recording`, add:

```swift
        // GIF exports and MP4 fallbacks land in the save folder — make sure it exists.
        try? FileManager.default.createDirectory(at: settings.saveDirectory,
                                                 withIntermediateDirectories: true)
```

- [ ] **Step 3: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add App/RecordingCoordinator.swift
git commit -m "fix(recording): ensure save directory exists; honor mic-permission denial

A denied mic permission previously still added a mic input to the writer
(silent empty track, no user signal). Recordings into a deleted/renamed
save folder failed silently.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Serialize writer finish with the sample queue (ScreenRecorder)

`stop()` drains the sample queue with `sampleQueue.sync {}` but then calls `markAsFinished()` on the main actor — an append that started during `stopCapture()` can land after finish, and `AVAssetWriterInput.append` after `markAsFinished` traps.

**Files:**
- Modify: `Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift:117-132` (stop)

- [ ] **Step 1: Move `markAsFinished` inside the sample-queue sync block**

Replace:

```swift
        // Let in-flight appends drain before finishing.
        sampleQueue.sync {}
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micInput?.markAsFinished()
```

with:

```swift
        // Finish on the sample queue so an in-flight append can't land after
        // markAsFinished (AVAssetWriterInput.append traps post-finish).
        sampleQueue.sync {
            videoInput?.markAsFinished()
            systemAudioInput?.markAsFinished()
            micInput?.markAsFinished()
        }
```

- [ ] **Step 2: Build + run RecordingKit tests**

Run: `swift build && swift run --package-path Packages/RecordingKit RecordingKitTests`
Expected: `Build complete!` then `PASS — RecordingKitTests: 6/6 test(s) passed` (count per current suite)

- [ ] **Step 3: Commit**

```bash
git add Packages/RecordingKit/Sources/RecordingKit/ScreenRecorder.swift
git commit -m "fix(recording): serialize markAsFinished with the sample queue

Prevents an in-flight sample append racing the writer finish (append
after markAsFinished traps in AVAssetWriter).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Shell-free app relaunch (PermissionManager)

`relaunchApp()` interpolates `Bundle.main.bundlePath` into a `/bin/sh -c` string — a single quote in the install path breaks quoting (silent relaunch failure; crafted path = code exec). Pass the path as `$0` instead so it is never parsed as shell syntax. The detached `sh` (with its 0.5 s sleep so the old instance can quit first) must survive our process exit, so we keep the shell but stop interpolating.

**Files:**
- Modify: `App/PermissionManager.swift:26-32`

- [ ] **Step 1: Replace the interpolated command string**

Replace:

```swift
    static func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open '\(Bundle.main.bundlePath)'"]
        try? task.run()
        NSApp.terminate(nil)
    }
```

with:

```swift
    static func relaunchApp() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // The bundle path is passed as $0 — never interpolated into the command
        // string — so quotes/metacharacters in the install path can't break it.
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add App/PermissionManager.swift
git commit -m "fix(app): pass bundle path as \$0 to the relaunch shell, not interpolated

A single quote in the install path broke the relaunch command (and was
a local command-injection surface).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Editor canvas draws directly — no per-frame flatten (the scan's only 🔴)

`EditorCanvasView.draw` calls `DocumentRenderer.render` on every redraw, and `mouseDragged` redraws per mouse-move: a full base-image-sized RGBA context is allocated, the full-res base re-rasterized, and `makeImage()`d per drag tick (~59 MB/frame on a 5K shot). Fix: draw the base `NSImage` scaled into the view, then draw annotations + the live preview directly under an image→view scale transform. `DocumentRenderer` stays untouched (still used for export — full-res flatten is correct there).

The view is flipped (`isFlipped == true`) and annotations draw in top-left-origin image-pixel coordinates (the project's documented convention), so the only adjustment needed is the scale.

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift:145-150` (draw) + new cached property

- [ ] **Step 1: Add a cached base NSImage keyed on the CGImage's identity**

Below the `// MARK: - Coordinate mapping (view ↔ image)` section in `EditorCanvasView.swift`, add:

```swift
    // MARK: - Base image cache
    /// NSImage wrapper for the base, rebuilt only when the base actually
    /// changes (crop/undo/redo swap in a different CGImage).
    private var cachedBase: (cg: CGImage, ns: NSImage)?
    private var baseNSImage: NSImage {
        if let c = cachedBase, c.cg === document.baseImage { return c.ns }
        let ns = NSImage(cgImage: document.baseImage, size: document.size)
        cachedBase = (document.baseImage, ns)
        return ns
    }
```

- [ ] **Step 2: Replace the flatten-per-draw with direct drawing**

In `draw(_ dirtyRect:)`, replace:

```swift
        // The in-progress shape is drawn on top of the flattened doc so the
        // user sees the annotation live as they drag (e.g. a rectangle growing).
        guard let flat = DocumentRenderer.render(document, preview: inProgress) else { return }
        NSImage(cgImage: flat, size: bounds.size).draw(in: bounds)
```

with:

```swift
        // Draw base + annotations directly at view scale instead of flattening
        // the full-resolution document into a new CGImage on every redraw
        // (which allocated a base-image-sized context per drag tick).
        // DocumentRenderer still does the full-res flatten for export.
        baseNSImage.draw(in: bounds)
        // Annotations (and the live in-progress preview) draw themselves in
        // image-pixel coordinates; scale the context so image px → view points.
        // The view is flipped, matching the renderer's top-left convention.
        NSGraphicsContext.saveGraphicsState()
        let toView = NSAffineTransform()
        toView.scale(by: 1 / scale)
        toView.concat()
        for a in document.annotations { a.draw() }
        inProgress?.draw()
        NSGraphicsContext.restoreGraphicsState()
```

Everything after (regionMarquee, marqueeRect, selection outlines, handles) stays unchanged — those already draw in view coordinates.

- [ ] **Step 3: Build + run the EditorKit suite (renderer/export must be untouched)**

Run: `swift build && swift run --package-path Packages/EditorKit EditorKitTests`
Expected: `Build complete!` then `PASS — EditorKitTests: 25/25 test(s) passed` (count per current suite)

- [ ] **Step 4: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift
git commit -m "perf(editor): draw canvas directly instead of re-flattening per redraw

DocumentRenderer.render allocated a full base-image-sized context and
re-rasterized the base on every drag tick. The canvas now blits the
cached base NSImage and draws annotations under an image->view scale
transform; full-res flattening remains export-only.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

Manual verification (deferred to the Task 13 checklist): drag-create each shape on a large capture, move/resize, blur/pixelate, crop then annotate, undo/redo, export — visuals identical, dragging smooth.

---

### Task 6: Center the counter badge on the click (TDD)

`mouseDown` passes the raw click point as the counter's top-left origin, so the badge appears down-and-right of the click. Add a tested `centered(on:)` factory to `CounterAnnotation` and use it in the canvas.

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/CounterAnnotation.swift`
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift:223-227` (mouseDown .counter case)
- Test: `Packages/EditorKit/Tests/EditorKitTests/CounterAnnotationTests.swift`

- [ ] **Step 1: Write the failing test**

In `Packages/EditorKit/Tests/EditorKitTests/CounterAnnotationTests.swift`, append to the existing `counterAnnotationTests` array:

```swift
    TestCase("centeredFactoryCentersBadgeOnPoint") { t in
        let p = CGPoint(x: 100, y: 80)
        let c = CounterAnnotation.centered(on: p, number: 3)
        let bb = c.boundingBox()
        t.approxEqual(Double(bb.midX), 100)
        t.approxEqual(Double(bb.midY), 80)
        t.equal(c.number, 3)
    },
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift run --package-path Packages/EditorKit EditorKitTests`
Expected: BUILD FAILURE — `type 'CounterAnnotation' has no member 'centered'`

- [ ] **Step 3: Implement the factory**

In `Packages/EditorKit/Sources/EditorKit/CounterAnnotation.swift`, after the `init`, add:

```swift
    /// A badge centered on `point` (clicks feel anchored to the cursor).
    public static func centered(on point: CGPoint, number: Int,
                                style: AnnotationStyle = .default) -> CounterAnnotation {
        var c = CounterAnnotation(number: number, origin: point, style: style)
        c.origin = CGPoint(x: point.x - c.diameter / 2, y: point.y - c.diameter / 2)
        return c
    }
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift run --package-path Packages/EditorKit EditorKitTests`
Expected: PASS, including `✓ centeredFactoryCentersBadgeOnPoint`

- [ ] **Step 5: Use it in the canvas**

In `EditorCanvasView.mouseDown`, replace:

```swift
        case .counter:
            snapshot()
            document.add(CounterAnnotation(number: document.nextCounterNumber(),
                                           origin: p, style: style))
            onStateChange?(); needsDisplay = true
```

with:

```swift
        case .counter:
            snapshot()
            document.add(CounterAnnotation.centered(on: p,
                                                    number: document.nextCounterNumber(),
                                                    style: style))
            onStateChange?(); needsDisplay = true
```

- [ ] **Step 6: Build + full EditorKit suite + commit**

Run: `swift build && swift run --package-path Packages/EditorKit EditorKitTests`
Expected: all pass.

```bash
git add Packages/EditorKit/Sources/EditorKit/CounterAnnotation.swift \
        Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift \
        Packages/EditorKit/Tests/EditorKitTests/CounterAnnotationTests.swift
git commit -m "fix(editor): center the counter badge on the click point

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 7: Editor keyboard works without a pre-click (first responder)

Delete/`[`/`]` are handled in the canvas's `keyDown`, which only fires for the first responder — and nothing makes the canvas first responder when the window opens, so those keys are dead until the user clicks the canvas. Also, committing inline text leaves focus on a detached field slot.

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift:82-88` (init)
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift:419-424` (commitText)

- [ ] **Step 1: Set the initial first responder**

In `EditorWindowController.init`, after the `buildUI()` call, add:

```swift
        // Delete / [ / ] are handled in the canvas's keyDown — make it the
        // first responder up front instead of requiring a click first.
        window.initialFirstResponder = canvas
```

- [ ] **Step 2: Return focus to the canvas after committing inline text**

In `EditorCanvasView.commitText(_:)`, replace:

```swift
        let text = sender.stringValue
        sender.removeFromSuperview(); activeField = nil
```

with:

```swift
        let text = sender.stringValue
        sender.removeFromSuperview(); activeField = nil
        window?.makeFirstResponder(self)
```

- [ ] **Step 3: Build + commit**

Run: `swift build`
Expected: `Build complete!`

```bash
git add Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift \
        Packages/EditorKit/Sources/EditorKit/EditorCanvasView.swift
git commit -m "fix(editor): canvas is first responder on open and after text commit

Delete and [ / ] z-order keys were dead until the user first clicked
the canvas.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 8: Redactor tests assert content is actually obscured

Current tests only check patch dimensions — a regression returning the region unmodified (a privacy failure for a screenshot tool) would pass. Add characterization tests on a high-contrast striped base: redaction must destroy hard edges. These should pass immediately against current behavior; if one fails, stop and investigate the Redactor (do not weaken the test).

**Files:**
- Test: `Packages/EditorKit/Tests/EditorKitTests/RedactorTests.swift`

- [ ] **Step 1: Add the striped base, pixel helpers, and the two tests**

Append to `Packages/EditorKit/Tests/EditorKitTests/RedactorTests.swift` (file-private helpers above the array extension; new cases appended to `redactorTests`). Replace the whole file with:

```swift
import TestKit
import CoreGraphics
@testable import EditorKit

private func makeBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    return ctx.makeImage()!
}

/// White base with 2px black vertical stripes every 4px — maximal hard edges,
/// so any working redaction must measurably destroy detail.
private func makeStripedBase() -> CGImage {
    let ctx = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
    var x = 0
    while x < 100 { ctx.fill(CGRect(x: x, y: 0, width: 2, height: 100)); x += 4 }
    return ctx.makeImage()!
}

/// RGBA8 readback of an image (premultiplied-last, device RGB).
private func pixels(_ image: CGImage) -> [UInt8] {
    let w = image.width, h = image.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
        bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buf
}

/// Number of horizontally adjacent pixel pairs whose red channels differ by
/// more than 128 — a proxy for "readable hard edges" in the region.
private func highContrastPairCount(_ image: CGImage) -> Int {
    let w = image.width, h = image.height
    let buf = pixels(image)
    var count = 0
    for y in 0..<h {
        for x in 0..<(w - 1) {
            let a = Int(buf[(y * w + x) * 4])
            let b = Int(buf[(y * w + x + 1) * 4])
            if abs(a - b) > 128 { count += 1 }
        }
    }
    return count
}

let redactorTests: [TestCase] = [
    TestCase("pixelatePatchHasRegionSize") { t in
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        let patch = Redactor.pixelate(makeBase(), region: region, blockSize: 10)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 40)
        t.equal(p.height, 30)
    },
    TestCase("blurPatchHasRegionSize") { t in
        let region = CGRect(x: 0, y: 0, width: 20, height: 20)
        let patch = Redactor.blur(makeBase(), region: region, radius: 8)
        guard let p = t.unwrap(patch) else { return }
        t.equal(p.width, 20)
        t.equal(p.height, 20)
    },
    TestCase("pixelateDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.pixelate(base, region: region, blockSize: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "pixelation left \(after) of \(before) hard edges")
    },
    TestCase("blurDestroysDetail") { t in
        let base = makeStripedBase()
        let region = CGRect(x: 10, y: 10, width: 40, height: 30)
        guard let patch = t.unwrap(Redactor.blur(base, region: region, radius: 12)),
              let original = t.unwrap(base.cropping(to: region)) else { return }
        let before = highContrastPairCount(original)
        let after = highContrastPairCount(patch)
        t.isTrue(before > 100, "striped source must start with strong edges (got \(before))")
        t.isTrue(after < before / 10, "blur left \(after) of \(before) hard edges")
    },
]
```

- [ ] **Step 2: Run the suite — the new tests characterize current (correct) behavior**

Run: `swift run --package-path Packages/EditorKit EditorKitTests`
Expected: PASS including `✓ pixelateDestroysDetail` and `✓ blurDestroysDetail`. If either fails, STOP — that's a real Redactor bug; investigate before proceeding (do not loosen thresholds without understanding why).

- [ ] **Step 3: Commit**

```bash
git add Packages/EditorKit/Tests/EditorKitTests/RedactorTests.swift
git commit -m "test(editor): assert blur/pixelate actually obscure content, not just size

A redaction regression returning the region unmodified (privacy failure)
previously passed the suite.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 9: VoiceOver labels for image-only buttons

Image-only `NSButton`s carry only `toolTip` — VoiceOver reads them as unlabeled (the SF Symbol `accessibilityDescription` labels the image, not the control).

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift:127-135` (iconButton)
- Modify: `App/RecordStripController.swift:36-58` (toggle helper + cancel button)
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorChrome.swift:16-38` (IconToolButton init)

- [ ] **Step 1: Quick Access overlay buttons**

In `QuickAccessOverlayController.iconButton(_:tip:_:)`, after `b.toolTip = tip`, add:

```swift
        b.setAccessibilityLabel(tip)
```

- [ ] **Step 2: Record-strip toggles + cancel**

In `RecordStripController.show(on:)`, in the local `toggle(...)` helper after `b.toolTip = tip`, add:

```swift
            b.setAccessibilityLabel(tip)
```

and after the `cancel.isBordered = false` line, add:

```swift
        cancel.setAccessibilityLabel("Cancel")
```

- [ ] **Step 3: Editor tool-pill buttons**

In `IconToolButton.init` (`EditorChrome.swift`), after `toolTip = tip`, add:

```swift
        setAccessibilityLabel(tip)
```

- [ ] **Step 4: Sweep for any remaining unlabeled image-only buttons**

Run: `grep -rn "imagePosition = .imageOnly" App Packages --include="*.swift"`
For every hit whose surrounding code does NOT already call `setAccessibilityLabel`, add `setAccessibilityLabel(<the button's tooltip string>)` immediately after its `toolTip` assignment, following the same pattern as Steps 1–3. (Known additional candidates: undo/redo buttons in `EditorWindowController.buildTitlebarHistory` — label them `"Undo"` / `"Redo"`.)

- [ ] **Step 5: Build + commit**

Run: `swift build`
Expected: `Build complete!`

```bash
git add -A
git commit -m "fix(a11y): accessibility labels for all image-only buttons

VoiceOver read the Quick Access, record-strip, and editor toolbar
buttons as unlabeled (tooltips don't provide the control's a11y name).

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 10: Overlay behavior consistency (Spaces, copy feedback, button widths)

Three scan findings: (a) the HUD toast and Quick Access overlay don't set `collectionBehavior`, so they never appear over full-screen apps while pins/strip/bubble do; (b) Copy shows a "Copied" HUD from a pin but is silent from the overlay; (c) overlay buttons are wider on recording cards (4 buttons) than screenshot cards (5 buttons) because the fixed 200px stack uses `.fillEqually`.

**Files:**
- Modify: `Packages/OverlayKit/Sources/OverlayKit/HUDController.swift:31-39`
- Modify: `Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift:55-63,92-95,127-135`
- Modify: `App/CaptureCoordinator.swift:114-115` (presentOverlay onCopy)
- Modify: `App/RecordingCoordinator.swift:267-271` (presentQuickAccess onCopy)

- [ ] **Step 1: Join all Spaces like the other panels**

In `HUDController.show`, after `panel.hidesOnDeactivate = false`, add:

```swift
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

In `QuickAccessOverlayController.present`, after `panel.hidesOnDeactivate = false`, add:

```swift
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
```

- [ ] **Step 2: Consistent copy feedback**

In `CaptureCoordinator.presentOverlay`, replace:

```swift
            onCopy: { [weak self] in self?.copy(image) },
```

with:

```swift
            onCopy: { [weak self] in self?.copy(image); self?.hud.show("Copied") },
```

In `RecordingCoordinator.presentQuickAccess`, replace:

```swift
            onCopy: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            },
```

with:

```swift
            onCopy: { [weak self] in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
                self?.hud.show("File copied")
            },
```

- [ ] **Step 3: Equal-size buttons on both card kinds**

In `QuickAccessOverlayController.present`, replace:

```swift
        stack.distribution = .fillEqually
```

with:

```swift
        stack.distribution = .equalCentering
```

and in `iconButton(_:tip:_:)`, after `b.toolTip = tip` (and the `setAccessibilityLabel` from Task 9), add:

```swift
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
```

- [ ] **Step 4: Build + commit**

Run: `swift build`
Expected: `Build complete!`

```bash
git add Packages/OverlayKit/Sources/OverlayKit/HUDController.swift \
        Packages/OverlayKit/Sources/OverlayKit/QuickAccessOverlayController.swift \
        App/CaptureCoordinator.swift App/RecordingCoordinator.swift
git commit -m "fix(overlay): consistent Spaces behavior, copy feedback, and button sizing

HUD + Quick Access now join all Spaces like pins/strip do; Copy shows a
HUD from every surface; overlay buttons are equal-width on screenshot
and recording cards.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

Manual verification (Task 13 checklist): capture over a full-screen app → overlay appears; Copy from overlay shows "Copied"; both card kinds have same-size buttons.

---

### Task 11: One-command test runner + GitHub Actions CI

84 tests exist with proper exit codes, but nothing runs them automatically, and the README documents only 3 of the 4 suites.

**Files:**
- Create: `scripts/test.sh`
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create `scripts/test.sh`**

```bash
#!/bin/bash
# Runs every package's TestKit suite. Each runner exits non-zero on failure,
# and set -e makes the first failure fail the whole script.
set -euo pipefail
cd "$(dirname "$0")/.."
for pkg in CaptureKit OverlayKit EditorKit RecordingKit; do
    echo "== ${pkg}Tests"
    swift run --package-path "Packages/$pkg" "${pkg}Tests"
done
echo "All suites passed."
```

Run: `chmod +x scripts/test.sh`

- [ ] **Step 2: Run it locally — all four suites must pass**

Run: `./scripts/test.sh`
Expected: four `PASS — <Suite>: …` lines then `All suites passed.` (exit 0)

- [ ] **Step 3: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  build-and-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Build app
        run: swift build
      - name: Run all test suites
        run: ./scripts/test.sh
```

- [ ] **Step 4: Commit**

```bash
git add scripts/test.sh .github/workflows/ci.yml
git commit -m "ci: GitHub Actions workflow + scripts/test.sh running all four suites

84 existing tests now gate every push/PR instead of running only by hand.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

(CI run itself is verified after the final push — see Task 13.)

---

### Task 12: Fix stale build docs (CLAUDE.md, README, project.yml)

CLAUDE.md still describes the abandoned XcodeGen/xcodebuild toolchain (the file agents read first); the README's test block omits `RecordingKitTests`; `project.yml` is an empty vestige.

**Files:**
- Modify: `CLAUDE.md:13`
- Modify: `README.md:42-48`
- Delete: `project.yml` (verify it's empty first)

- [ ] **Step 1: Fix the CLAUDE.md Stack bullet**

Replace line 13:

```markdown
- **Build:** XcodeGen (`project.yml`) generates the `.xcodeproj`; build/run with `xcodebuild`. Library modules are local Swift packages under `Packages/`, unit-tested with `swift test`.
```

with:

```markdown
- **Build:** SwiftPM — `swift build`, with `scripts/build-app.sh` assembling `dist/BetterScreenshot.app` (CLT-only, no Xcode; see `docs/BUILD-NOTES.md`). Library modules are local Swift packages under `Packages/`, tested via TestKit executable runners — run all suites with `scripts/test.sh`.
```

- [ ] **Step 2: Fix the README test block**

Replace:

```sh
swift run --package-path Packages/CaptureKit CaptureKitTests
swift run --package-path Packages/OverlayKit OverlayKitTests
swift run --package-path Packages/EditorKit EditorKitTests
```

with:

```sh
./scripts/test.sh    # all four suites: CaptureKit, OverlayKit, EditorKit, RecordingKit
```

- [ ] **Step 3: Remove the empty project.yml**

Run: `wc -c project.yml`
Expected: `0 project.yml` (if non-zero, STOP and inspect — do not delete a non-empty file).
Then: `git rm project.yml`

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md README.md
git commit -m "docs: build instructions match reality (SwiftPM, not XcodeGen); all 4 test suites

CLAUDE.md described the abandoned XcodeGen/xcodebuild flow; the README
omitted RecordingKitTests; project.yml was an empty vestige.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 13: Changelog, version bump, full verification

**Files:**
- Modify: `CHANGELOG.md` (new 2.2.0 section at top, matching existing entry style)
- Modify: `App/Info.plist` (CFBundleShortVersionString 2.1.0 → 2.2.0)

- [ ] **Step 1: Add the CHANGELOG entry**

At the top of `CHANGELOG.md` (above the 2.1.0 section), add a `## 2.2.0 — 2026-06-05` section summarizing: save/capture failures surfaced via HUD + save-folder auto-creation; mic-denial handling; recorder finish race fix; shell-free relaunch; editor canvas perf (no per-frame flatten); counter centered on click; editor keyboard works without pre-click; VoiceOver labels; overlay consistency (Spaces/copy feedback/button widths); blur/pixelate obscuring tests; CI + test.sh; build-doc corrections. Follow the existing entry format in the file.

- [ ] **Step 2: Bump the version**

In `App/Info.plist`, change the `CFBundleShortVersionString` value from `2.1.0` to `2.2.0`.

- [ ] **Step 3: Full build + all tests + app bundle**

Run: `swift build && ./scripts/test.sh && ./scripts/build-app.sh`
Expected: build OK, four PASS lines, `dist/BetterScreenshot.app` produced.

- [ ] **Step 4: Commit**

```bash
git add CHANGELOG.md App/Info.plist
git commit -m "chore: bump app version to 2.2.0 for the reliability + infra release

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Manual GUI checklist (user-run, post-deploy)**

After copying `dist/BetterScreenshot.app` to `/Applications` and relaunching:
1. Point the save folder at a directory, delete the directory in Finder, take a screenshot in save-only mode → folder is recreated and the file saved (no silent loss).
2. ⌘⇧4 capture → editor: drag shapes on a large (Retina fullscreen) capture → dragging is smooth; blur/pixelate/crop/undo/redo/export visuals unchanged.
3. Editor opens → press Delete on a selected object WITHOUT clicking the canvas first → it deletes.
4. Counter tool click → badge centered on the cursor.
5. Record with mic toggled on but permission denied (System Settings → Privacy → Microphone off) → HUD "Mic access denied…", recording completes without a mic track.
6. Capture while a full-screen app is frontmost → Quick Access overlay and HUD appear on that Space.
7. Copy from the Quick Access overlay → "Copied" HUD; recording card buttons same size as screenshot card buttons.
8. VoiceOver (⌘F5): overlay/strip/editor toolbar buttons announce their names.
9. Push to GitHub → Actions run goes green.

---

## Self-Review Notes

- **Coverage vs. chosen scan scope (Tracks A + D):** silent save loss ✓ (T1), save-dir ensure ✓ (T1/T2), capture/OCR feedback ✓ (T1), recorder race ✓ (T3), mic denial ✓ (T2), editor 🔴 perf ✓ (T5), relaunch quoting ✓ (T4), CI ✓ (T11), stale docs ✓ (T12), VoiceOver ✓ (T9), Redactor tests ✓ (T8), first-responder ✓ (T7), counter offset ✓ (T6), overlay consistency ✓ (T10). Deliberately deferred (larger, separate efforts per scan's long-term bucket): shared design-system layer, `stopForTermination` async-terminate rework, Swift 6 tools-version migration, `EditorWindowController` decomposition.
- **Types:** `hud` is an existing `HUDController` property on both coordinators; `screen(for:)` exists in CaptureCoordinator; `config` becomes `var` in T2 before mutation; `CounterAnnotation.centered(on:number:style:)` defined in T6 Step 3 and used in T6 Step 5 with matching signature.
