# Editor Sticky Defaults + "Stack" Button — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the annotation editor remember the last-used color + size across sessions, and replace its "Pin" button with a "Stack" button that drops the edited screenshot into the bottom-right Quick Access stack.

**Architecture:** `EditorKit` stays decoupled from app settings (mirroring its existing `onCopy`/`onSave` callbacks): `EditorWindowController` takes an injected `defaultStyle` and emits an `onStyleChanged` callback. The App layer (`SettingsStore`) persists the style as JSON in `UserDefaults`, and `CaptureCoordinator` wires it up. For the Stack button, the editor's old `onPin` callback is renamed to `onAddToStack`, which `CaptureCoordinator` routes through the existing post-capture overlay path (`presentOverlay`) so the edited image re-enters the normal Quick Access + history flow.

**Tech Stack:** Swift 5.9+, AppKit, SwiftPM local packages, the local TestKit test harness (`scripts/test.sh`). macOS 14+.

**Reference spec:** `docs/superpowers/specs/2026-06-25-betterscreenshot-editor-defaults-and-stack-button-design.md`

**Build/test commands used in this plan:**
- EditorKit unit tests only: `swift run --package-path Packages/EditorKit EditorKitTests`
- All test suites: `scripts/test.sh`
- Compile the whole app: `swift build`
- Assemble the runnable bundle: `scripts/build-app.sh`

---

## File Structure

- **`Packages/EditorKit/Sources/EditorKit/RGBAColor.swift`** — add `Codable` conformance (color value type).
- **`Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift`** — add `Codable` conformance (the persisted unit).
- **`Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift`** (new) — JSON round-trip test.
- **`Packages/EditorKit/Tests/EditorKitTests/main.swift`** — register the new test array.
- **`Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`** — inject `defaultStyle`, emit `onStyleChanged`, seed the canvas, and replace the Pin button with a Stack button (`onPin`→`onAddToStack`).
- **`App/SettingsStore.swift`** — `import EditorKit`, add `editorStyle`, load it in `init`, add `persistEditorStyle()`.
- **`App/CaptureCoordinator.swift`** — pass `defaultStyle`, wire `onStyleChanged`, replace `onPin` wiring with `onAddToStack`→ new `keepInStack(_:)`.

---

## Task 1: Make `AnnotationStyle` + `RGBAColor` Codable (TDD)

**Files:**
- Create: `Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift`
- Modify: `Packages/EditorKit/Tests/EditorKitTests/main.swift:5-7`
- Modify: `Packages/EditorKit/Sources/EditorKit/RGBAColor.swift:4`
- Modify: `Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift:3`

- [ ] **Step 1: Write the failing test**

Create `Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift`:

```swift
import TestKit
import Foundation
@testable import EditorKit

let annotationStyleCodableTests: [TestCase] = [
    TestCase("annotationStyleRoundTripsThroughJSON") { t in
        let original = AnnotationStyle(
            strokeColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 1.0),
            fillColor: RGBAColor(r: 0.04, g: 0.52, b: 1.0, a: 0.25),
            lineWidth: 7, fontSize: 36)
        do {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(AnnotationStyle.self, from: data)
            t.approxEqual(Double(decoded.strokeColor.r), 0.04, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.g), 0.52, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.b), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.strokeColor.a), 1.0, tol: 1e-6)
            t.approxEqual(Double(decoded.fillColor.a), 0.25, tol: 1e-6)
            t.approxEqual(Double(decoded.lineWidth), 7, tol: 1e-9)
            t.approxEqual(Double(decoded.fontSize), 36, tol: 1e-9)
            t.isTrue(decoded == original, "decoded should equal original")
        } catch {
            t.fail("round-trip threw: \(error)")
        }
    },
]
```

Register the array in `Packages/EditorKit/Tests/EditorKitTests/main.swift` by replacing lines 5–7:

```swift
runTests("EditorKitTests",
    rgbaColorTests + editorDocumentTests + shapeAnnotationTests + arrowGeometryTests + textAnnotationTests + counterAnnotationTests + redactorTests + documentRendererTests + cropTests + annotationStyleCodableTests
)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift run --package-path Packages/EditorKit EditorKitTests`
Expected: **compile failure** — `AnnotationStyle`/`RGBAColor` do not conform to `Encodable`/`Decodable` (e.g. "instance method 'encode' requires that 'AnnotationStyle' conform to 'Encodable'"). This is the TDD red.

- [ ] **Step 3: Add Codable conformance**

In `Packages/EditorKit/Sources/EditorKit/RGBAColor.swift`, change line 4:

```swift
public struct RGBAColor: Equatable, Codable {
```

In `Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift`, change line 3:

```swift
public struct AnnotationStyle: Equatable, Codable {
```

(No `CodingKeys` or custom methods needed — all stored properties are `CGFloat`/`RGBAColor`, which are `Codable`, so the compiler synthesizes the conformance. `RGBAColor`'s existing custom initializers coexist with the synthesized `init(from:)`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `swift run --package-path Packages/EditorKit EditorKitTests`
Expected: PASS — output includes `✓ annotationStyleRoundTripsThroughJSON` and ends with `PASS — EditorKitTests`.

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/RGBAColor.swift Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift Packages/EditorKit/Tests/EditorKitTests/main.swift
git commit -m "feat(editor): make AnnotationStyle + RGBAColor Codable

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Inject `defaultStyle` + emit `onStyleChanged` in the editor

This is UI wiring (no unit test); verify by compiling. Adding a default-valued init parameter and a new optional callback is backward compatible, so the whole app still builds after this task.

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift` (lines 9–11, 65–91, 486–503)

- [ ] **Step 1: Add the `onStyleChanged` callback property**

In `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`, replace lines 9–11:

```swift
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?
    public var onPin: ((CGImage) -> Void)?
```

with:

```swift
    public var onCopy: ((CGImage) -> Void)?
    public var onSave: ((CGImage) -> Void)?
    public var onPin: ((CGImage) -> Void)?
    /// Fired whenever the active color/stroke-weight/font-size changes, so the
    /// host can persist the style as the next session's default.
    public var onStyleChanged: ((AnnotationStyle) -> Void)?
```

- [ ] **Step 2: Accept `defaultStyle` in the initializer and seed style + canvas**

Replace the initializer signature on line 65:

```swift
    public init(image: CGImage) {
```

with:

```swift
    public init(image: CGImage, defaultStyle: AnnotationStyle = .default) {
```

Then, inside that initializer, insert two lines immediately after `super.init(window: window)` (line 82) — i.e. right before `window.backgroundColor = backdrop`:

```swift
        super.init(window: window)

        self.style = defaultStyle
        canvas.style = defaultStyle
        window.backgroundColor = backdrop
```

(`buildUI()` and `selectTool(.arrow)` run after this, so the inspector's swatch highlight and S/M/L segments — built in `rebuildInspector` — reflect the loaded style, and the canvas draws new annotations with it.)

- [ ] **Step 3: Emit `onStyleChanged` on each style mutation**

Replace `applyStrokeColor(_:)` (lines 486–491):

```swift
    private func applyStrokeColor(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        style.strokeColor = RGBAColor(c)
        style.fillColor = RGBAColor(c.withAlphaComponent(0.25))
        canvas.style = style
        onStyleChanged?(style)
    }
```

Replace `weightChanged(_:)` (lines 493–497):

```swift
    @objc private func weightChanged(_ sender: NSSegmentedControl) {
        let widths: [CGFloat] = [2, 4, 7]
        style.lineWidth = widths[max(0, sender.selectedSegment)]
        canvas.style = style
        onStyleChanged?(style)
    }
```

Replace `sizeChanged(_:)` (lines 499–503):

```swift
    @objc private func sizeChanged(_ sender: NSSegmentedControl) {
        let sizes: [CGFloat] = [18, 24, 36]
        style.fontSize = sizes[max(0, sender.selectedSegment)]
        canvas.style = style
        onStyleChanged?(style)
    }
```

- [ ] **Step 4: Verify it compiles**

Run: `swift build`
Expected: build succeeds (`Compiling`/`Build complete!`), no errors. (Existing `EditorWindowController(image:)` call sites still compile thanks to the defaulted parameter.)

- [ ] **Step 5: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift
git commit -m "feat(editor): inject default style + emit onStyleChanged

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Persist `editorStyle` in `SettingsStore`

UI/persistence wiring; verify by compiling.

**Files:**
- Modify: `App/SettingsStore.swift` (lines 1–3, 5–11, 15–32, add a method)

- [ ] **Step 1: Import EditorKit**

In `App/SettingsStore.swift`, replace lines 1–3:

```swift
import Foundation
import CaptureKit
import RecordingKit
```

with:

```swift
import Foundation
import CaptureKit
import RecordingKit
import EditorKit
```

- [ ] **Step 2: Add the `editorStyle` published property**

Replace the property block (lines 6–11) — add `editorStyle` after `recording`:

```swift
    @Published var settings: CaptureSettings
    @Published var saveDirectory: URL
    @Published var bindings: HotkeyBindings
    /// Actions whose combo macOS refused to register (not persisted).
    @Published var failedActions: Set<HotkeyAction> = []
    @Published var recording: RecordingConfig
    /// The annotation editor's sticky default style (color + sizes).
    @Published var editorStyle: AnnotationStyle
```

- [ ] **Step 3: Load `editorStyle` in `init()`**

At the end of `init()`, immediately after the `recording` assignment (line 31, `self.recording = recDict.isEmpty ? .default : RecordingConfig(dictionary: recDict)`), add:

```swift
        if let data = defaults.data(forKey: "editorDefaultStyle"),
           let decoded = try? JSONDecoder().decode(AnnotationStyle.self, from: data) {
            self.editorStyle = decoded
        } else {
            self.editorStyle = .default
        }
```

- [ ] **Step 4: Add `persistEditorStyle()`**

Immediately after the existing `persist()` method (which ends at line 39 with its closing `}`), add:

```swift
    func persistEditorStyle() {
        if let data = try? JSONEncoder().encode(editorStyle) {
            defaults.set(data, forKey: "editorDefaultStyle")
        }
    }
```

- [ ] **Step 5: Verify it compiles**

Run: `swift build`
Expected: build succeeds, no errors.

- [ ] **Step 6: Commit**

```bash
git add App/SettingsStore.swift
git commit -m "feat(settings): persist editor default style in UserDefaults

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Wire sticky style in `CaptureCoordinator`

**Files:**
- Modify: `App/CaptureCoordinator.swift` (lines 29–38)

- [ ] **Step 1: Pass `defaultStyle` and wire `onStyleChanged`**

In `App/CaptureCoordinator.swift`, replace `presentEditor(_:)` (lines 29–38). Current:

```swift
    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        controller.onPin = { [weak self] img in self?.pin(img) }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

New (changed: `defaultStyle:` argument added; `onStyleChanged` wired; `onPin` line kept for now — Task 5 replaces it):

```swift
    func presentEditor(_ image: CGImage) {
        let controller = EditorWindowController(image: image, defaultStyle: settings.editorStyle)
        controller.onCopy = { [weak self] img in self?.copy(img) }
        controller.onSave = { [weak self] img in self?.save(img) }
        controller.onPin = { [weak self] img in self?.pin(img) }
        controller.onStyleChanged = { [weak self] style in
            self?.settings.editorStyle = style
            self?.settings.persistEditorStyle()
        }
        editorController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: build succeeds, no errors.

- [ ] **Step 3: Verify sticky behavior manually**

Run: `scripts/build-app.sh` then launch `dist/BetterScreenshot.app`. Capture → Edit → pick a blue swatch and set stroke to L → close the editor. Capture again → Edit → confirm the blue swatch is selected and the weight segment shows L. (If a previous BetterScreenshot copy is the active login item, the user must replace it to see the change — this is a manual deploy step, not part of the commit.)

- [ ] **Step 4: Commit**

```bash
git add App/CaptureCoordinator.swift
git commit -m "feat(editor): remember last-used annotation color + size

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Replace the editor "Pin" button with a "Stack" button

This couples an `EditorKit` rename (`onPin`→`onAddToStack`) with the `CaptureCoordinator` rewire, so both files change in one commit to keep the build green.

**Files:**
- Modify: `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift` (line 11, lines 272–278, lines 526–529)
- Modify: `App/CaptureCoordinator.swift` (line 33 area in `presentEditor`, add `keepInStack`)

- [ ] **Step 1: Rename the callback property**

In `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`, change line 11:

```swift
    public var onPin: ((CGImage) -> Void)?
```

to:

```swift
    public var onAddToStack: ((CGImage) -> Void)?
```

- [ ] **Step 2: Swap the Pin button for a Stack button in `buildActionBar()`**

Replace the Pin button block (lines 272–276):

```swift
        let pinBtn = NSButton(title: "Pin", target: self, action: #selector(pinAction))
        pinBtn.bezelStyle = .rounded
        pinBtn.image = NSImage(systemSymbolName: "pin", accessibilityDescription: "Pin")
        pinBtn.imagePosition = .imageLeading
        pinBtn.toolTip = "Pin to screen"
```

with:

```swift
        let stackBtn = NSButton(title: "Stack", target: self, action: #selector(addToStackAction))
        stackBtn.bezelStyle = .rounded
        stackBtn.image = NSImage(systemSymbolName: "square.stack", accessibilityDescription: "Stack")
        stackBtn.imagePosition = .imageLeading
        stackBtn.toolTip = "Keep in the bottom-right stack"
```

Then update the action row on line 278:

```swift
        let actions = NSStackView(views: [doneBtn, pinBtn, saveBtn, copyBtn])
```

to:

```swift
        let actions = NSStackView(views: [doneBtn, stackBtn, saveBtn, copyBtn])
```

- [ ] **Step 3: Rename `pinAction()` and close the window after handing off the image**

Replace `pinAction()` (lines 526–529):

```swift
    @objc private func pinAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onPin?(img)
    }
```

with:

```swift
    @objc private func addToStackAction() {
        guard let img = DocumentRenderer.render(canvas.currentDocument()) else { return }
        onAddToStack?(img)
        window?.close()
    }
```

- [ ] **Step 4: Rewire `CaptureCoordinator.presentEditor` and add `keepInStack`**

In `App/CaptureCoordinator.swift`, inside `presentEditor(_:)` (edited in Task 4), replace the line:

```swift
        controller.onPin = { [weak self] img in self?.pin(img) }
```

with:

```swift
        controller.onAddToStack = { [weak self] img in self?.keepInStack(img) }
```

Then add a new method immediately after `presentEditor(_:)` (before the `init`):

```swift
    /// Drops an edited image into the bottom-right Quick Access stack, treating
    /// it like a fresh capture: it is recorded to history and shown with the
    /// normal Copy/Edit/Pin/Save/drag actions.
    func keepInStack(_ image: CGImage) {
        let historyID = history?.recordScreenshot(image)
        presentOverlay(image, sourceRect: nil, historyID: historyID)
    }
```

(`CaptureCoordinator.pin(_:near:)` is unchanged and is still used by the Quick Access overlay's own Pin action, so Pin-to-Screen remains available app-wide. `presentOverlay` is a private method on the same type, so `keepInStack` can call it.)

- [ ] **Step 5: Verify it compiles**

Run: `swift build`
Expected: build succeeds, no errors. (No remaining references to `onPin` or `pinAction` exist.)

- [ ] **Step 6: Verify the Stack flow manually**

Run: `scripts/build-app.sh` then launch `dist/BetterScreenshot.app`. Capture → Edit → add an arrow → click **Stack**. Confirm: the editor closes; the edited image appears as the newest bottom-right Quick Access card; it is present in the History window; and that card's Copy/Edit/Pin/Save/drag all work. Separately confirm a normal capture's overlay still offers Pin-to-Screen.

- [ ] **Step 7: Commit**

```bash
git add Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift App/CaptureCoordinator.swift
git commit -m "feat(editor): replace Pin button with Stack (add to Quick Access)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Run all automated test suites**

Run: `scripts/test.sh`
Expected: every suite prints `PASS`, and the script ends with `All suites passed.` In particular, `EditorKitTests` includes `✓ annotationStyleRoundTripsThroughJSON`.

- [ ] **Step 2: Compile the whole app**

Run: `swift build`
Expected: `Build complete!` with no warnings about unused `onPin`/`pinAction`.

- [ ] **Step 3: Assemble the bundle**

Run: `scripts/build-app.sh`
Expected: `dist/BetterScreenshot.app` is produced.

- [ ] **Step 4: Manual GUI checklist** (from the spec — run against `dist/BetterScreenshot.app`)

1. **Sticky color:** pick blue, close, reopen editor → blue is selected and new strokes are blue.
2. **Sticky size:** set stroke to L and (Text tool) font to L, close, reopen → both S/M/L segments show L.
3. **First-launch fallback:** with no saved style (e.g. `defaults delete <app bundle id> editorDefaultStyle` or a fresh user), editor opens on red / M / M.
4. **Stack replaces Pin:** bottom bar reads Done · Stack · Save · Copy; no Pin button.
5. **Stack action:** annotate → Stack → editor closes, edited image is the newest bottom-right card and is in History.
6. **Stack card actions:** that card's Copy/Edit/Pin/Save/drag all work.
7. **Pin still available:** a normal capture's overlay card still offers Pin-to-Screen.

Note: deploying the new build (replacing any existing `/Applications/BetterScreenshot.app` login-item copy and relaunching) is the user's call, not part of these commits.

---

## Self-Review

- **Spec coverage:**
  - Feature 1 sticky color+size → Tasks 1–4 (Codable, inject/emit, persist, wire). ✓
  - Feature 2 Stack button replacing Pin → Task 5. ✓
  - Pin-to-Screen retained via overlay → noted in Task 5 Step 4 + checklist item 7. ✓
  - Codable round-trip test → Task 1. ✓
  - Out-of-scope items (no Settings UI, tool not persisted, no shortcut) → respected; no tasks add them. ✓
- **Placeholder scan:** no TBD/TODO/"handle edge cases"; every code step shows full code. ✓
- **Type consistency:** `onStyleChanged: ((AnnotationStyle) -> Void)?`, `onAddToStack: ((CGImage) -> Void)?`, `addToStackAction()`, `keepInStack(_:)`, `persistEditorStyle()`, and the `"editorDefaultStyle"` UserDefaults key are used identically across Tasks 2–6. ✓
- **Build-green ordering:** Tasks 1–4 are each backward compatible (defaulted init param, unused-but-harmless callback). The non-backward-compatible `onPin`→`onAddToStack` rename and its `CaptureCoordinator` rewire are combined in Task 5's single commit. ✓
