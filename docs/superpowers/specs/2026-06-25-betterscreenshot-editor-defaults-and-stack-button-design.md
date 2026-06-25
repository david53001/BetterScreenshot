# BetterScreenshot — Editor Sticky Defaults + "Stack" Button

**Date:** 2026-06-25
**Status:** Approved (design), pending implementation plan
**Scope:** Two small, independent changes to the annotation editor and its app-side wiring.

BetterScreenshot is a free, local macOS clone of CleanShot X (a screenshot + screen-recording
tool), built as a native Swift menu-bar app. After a capture, a floating "Quick Access"
thumbnail appears in a screen corner (default bottom-right); clicking its Edit button opens the
annotation editor (an AppKit `NSWindowController` titled "Annotate"). This spec covers two
user-requested behavior changes to that editor.

---

## Feature 1 — Sticky annotation defaults (remember color + size)

### Problem
Every time the annotation editor opens, its toolbar starts from a fixed hardcoded style:
red stroke, 4 pt line width, 24 pt font (`AnnotationStyle.default` in
`Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift`). A user who always wants, say,
a large blue stroke must re-select it on every screenshot. The editor should instead
**remember the last-used color and size** and reopen with them.

### Decisions (locked during brainstorming)
- **Mechanism:** automatic ("sticky") — the editor remembers the last-used values. **No button**
  and **no new Settings-window UI.**
- **What is remembered:** the **color** (stroke + derived fill) and the **size** (stroke line
  width *and* text font size). The **selected tool is NOT remembered** — the editor always opens
  on the Arrow tool, as it does today.
- **Persistence ownership:** the App layer owns persistence (see Architecture). `EditorKit`
  stays decoupled from `UserDefaults`.

### Current behavior (for reference)
- `EditorWindowController` (`Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`)
  holds `private var style = AnnotationStyle.default` (line 8). `init(image:)` builds the UI and
  calls `selectTool(.arrow)` (line 90), which calls `rebuildInspector(for:)`.
- The inspector reads `style` when it builds its controls:
  - `makeColorRow()` highlights the swatch matching `style.strokeColor` and seeds the custom
    color well from it (lines 393–414).
  - `makeWeightSegment()` selects S/M/L from `style.lineWidth` using widths `[2, 4, 7]`
    (lines 416–423).
  - `makeSizeSegment()` selects S/M/L from `style.fontSize` using sizes `[18, 24, 36]`
    (lines 425–432).
- User edits mutate `style` and push it to the canvas:
  - `applyStrokeColor(_:)` (lines 486–491) — called by both `swatchClicked(_:)` and
    `customColorChanged(_:)`; sets `style.strokeColor` and `style.fillColor` (stroke at 0.25 alpha).
  - `weightChanged(_:)` (lines 493–497) — sets `style.lineWidth`.
  - `sizeChanged(_:)` (lines 499–503) — sets `style.fontSize`.
- There is **no persistence**: `style` resets to `AnnotationStyle.default` every time.

### Target behavior
- On launch the editor loads the **persisted style** (or `AnnotationStyle.default` if none saved
  yet) and reflects it in the toolbar: the matching color swatch is highlighted (or the custom
  color well shows the saved color), and the S/M/L weight and size segments show the saved
  selection.
- New annotations drawn in that session use the loaded style immediately (the canvas is seeded
  with it).
- Whenever the user changes color, stroke weight, or font size, the new style is persisted, so
  the next editor session reopens with it.
- The persisted unit is the whole `AnnotationStyle` (`strokeColor`, `fillColor`, `lineWidth`,
  `fontSize`). The active tool is not part of `AnnotationStyle` and is not persisted.

### Architecture
`EditorKit` is a standalone Swift package (model + canvas + flatten-to-image renderer) with no
knowledge of app settings, mirroring how the existing `onCopy` / `onSave` callbacks keep it
decoupled from the App layer. We keep that boundary:

1. **`EditorWindowController` gains an injected default + a change callback.**
   - New initializer parameter: `init(image: CGImage, defaultStyle: AnnotationStyle = .default)`.
     The body assigns `self.style = defaultStyle` and `canvas.style = defaultStyle`
     **before** `selectTool(.arrow)` runs, so the inspector and canvas both reflect the loaded
     style. (The default-valued parameter keeps existing call sites compiling, though the only
     caller, `CaptureCoordinator.presentEditor`, will pass an explicit style.)
   - New property: `var onStyleChanged: ((AnnotationStyle) -> Void)?`. It is invoked at the end of
     `applyStrokeColor(_:)`, `weightChanged(_:)`, and `sizeChanged(_:)`, passing the current
     `style`. (`applyStrokeColor` covers both the swatch and custom-color-well paths, so one call
     site there is enough.)

2. **`AnnotationStyle` and `RGBAColor` become `Codable`** so the App can serialize the style.
   Both are simple value types over `CGFloat` (which is `Codable`), so synthesized conformance is
   sufficient — add `Codable` to each type's conformance list. No custom coding keys needed.
   - `RGBAColor` (`Packages/EditorKit/Sources/EditorKit/RGBAColor.swift`): `public struct RGBAColor: Equatable, Codable`.
   - `AnnotationStyle` (`Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift`): `public struct AnnotationStyle: Equatable, Codable`.

3. **`SettingsStore` owns persistence.** `SettingsStore`
   (`App/SettingsStore.swift`) already centralizes app preferences in `UserDefaults`. Add:
   - `import EditorKit` (it currently imports `CaptureKit` and `RecordingKit`).
   - `@Published var editorStyle: AnnotationStyle`, loaded in `init()` from a new `UserDefaults`
     key `"editorDefaultStyle"` (JSON-encoded `Data`), falling back to `AnnotationStyle.default`
     when absent or undecodable.
   - `func persistEditorStyle()` that JSON-encodes `editorStyle` to that key. (Kept separate from
     the existing `persist()`, which writes the dictionary-encoded capture/hotkey/recording
     settings driven by the Settings window; the editor style is driven by the editor callback,
     not the Settings UI.)

4. **`CaptureCoordinator` wires them together.** In `presentEditor(_:)`
   (`App/CaptureCoordinator.swift`, lines 29–38):
   - Construct with `EditorWindowController(image: image, defaultStyle: settings.editorStyle)`.
   - Set `controller.onStyleChanged = { [weak self] style in self?.settings.editorStyle = style; self?.settings.persistEditorStyle() }`.

### Data flow
```
editor opens
  → CaptureCoordinator.presentEditor passes settings.editorStyle
  → EditorWindowController seeds style + canvas, inspector reflects it
user changes color / weight / size
  → controller mutates style, calls onStyleChanged(style)
  → CaptureCoordinator updates settings.editorStyle, calls persistEditorStyle()
  → SettingsStore JSON-encodes to UserDefaults["editorDefaultStyle"]
next editor open → loads the saved style
```

---

## Feature 2 — Replace the editor "Pin" button with a "Stack" button

### Problem
The editor's bottom action bar has **Done · Pin · Save · Copy**. "Pin" floats the edited image on
screen as an always-on-top panel. The user instead wants a button that **keeps the edited
screenshot (with all annotations) in the bottom-right Quick Access stack alongside their other
captures** — i.e. treats the finished edit like a fresh capture.

### Decisions (locked during brainstorming)
- The **Pin button is removed from the editor** and replaced by the new button. Pin-to-Screen is
  **not lost from the app** — the Quick Access overlay card still has its own Pin button
  (`QuickAccessActions.onPin`), so any capture can still be pinned from the bottom-right thumbnail.
- Pressing the new button **adds the edited image to the Quick Access stack, records it to
  history (like any capture), and closes the editor.**

### Current behavior (for reference)
- The action bar is built in `EditorWindowController.buildActionBar()`
  (`Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift`, lines 229–297). The Pin
  button (lines 272–276) is added to the row `[doneBtn, pinBtn, saveBtn, copyBtn]` (line 278).
- `pinAction()` (lines 526–529) renders the document via `DocumentRenderer.render(...)` and calls
  `onPin?(img)`.
- `onPin` is wired in `CaptureCoordinator.presentEditor` (line 33) to `self?.pin(img)`, which
  creates a floating `PinPanelController` panel.
- A fresh capture's overlay path is `CaptureCoordinator.handle(_:sourceRect:)` (lines 110–119):
  it calls `history?.recordScreenshot(image)` then, for the default `.showOverlay` behavior,
  `presentOverlay(image, sourceRect:historyID:)` (lines 121–146), which adds a card to
  `QuickAccessStackController` with the standard Copy / Edit / Pin / Save / drag actions.

### Target behavior
- The editor's bottom bar reads **Done · Stack · Save · Copy** (Stack replaces Pin in the same
  slot).
- **Button presentation:** title "Stack", SF Symbol `square.stack`, `imagePosition = .imageLeading`,
  `bezelStyle = .rounded`, tooltip "Keep in the bottom-right stack". (Matches the existing
  Save/Copy button styling; no keyboard shortcut, consistent with the old Pin button.)
- Pressing Stack: render the document, hand the image to the App, then **close the editor
  window** (same as Done).
- The App treats that image exactly like a fresh capture's overlay route: record it to history
  and present it in the Quick Access stack with the normal actions.

### Architecture / wiring
1. **`EditorWindowController`:**
   - Rename the `onPin` property to `onAddToStack` (`var onAddToStack: ((CGImage) -> Void)?`).
     It is the only such callback; `onCopy` and `onSave` are unchanged.
   - Replace the Pin button with the Stack button in `buildActionBar()` (title/symbol/tooltip
     above), keeping its position in the `[doneBtn, stackBtn, saveBtn, copyBtn]` row.
   - Rename `pinAction()` to `addToStackAction()`. Body: render the document; if non-nil, call
     `onAddToStack?(img)`; then `window?.close()`.

2. **`CaptureCoordinator`:**
   - In `presentEditor(_:)`, replace the `controller.onPin = …` line with
     `controller.onAddToStack = { [weak self] img in self?.keepInStack(img) }`.
   - Add `func keepInStack(_ image: CGImage)`:
     ```swift
     func keepInStack(_ image: CGImage) {
         let historyID = history?.recordScreenshot(image)
         presentOverlay(image, sourceRect: nil, historyID: historyID)
     }
     ```
     This reuses the existing private `presentOverlay(_:sourceRect:historyID:)`, so the edited
     image re-enters the normal post-capture flow: it lands in the bottom-right stack (subject to
     the existing 3-card cap and eviction) with Copy / Edit / Pin / Save / drag, and is recorded
     to history. `sourceRect: nil` is correct — the edited image has no meaningful original
     on-screen rectangle; the overlay positions at the corner regardless.
   - `CaptureCoordinator.pin(_:near:)` stays unchanged and is still used by the overlay's own Pin
     action, so Pin-to-Screen remains available app-wide.

### Notes / accepted trade-offs
- Keeping the edited image records a **new** history entry separate from the original capture's
  entry (every capture already calls `recordScreenshot`). This is intended: the edited version is
  the one the user chose to keep, and history is the durable store (the Quick Access stack itself
  is ephemeral — max 3 cards). Duplicate-looking history entries (original + edited) are
  acceptable.

---

## Testing

### Automated (TestKit, run via `scripts/test.sh`)
EditorKit's test suite uses the local TestKit harness: `TestCase("name") { t in … }` arrays
aggregated in `Packages/EditorKit/Tests/EditorKitTests/main.swift`.

- Add a test array (e.g. `annotationStyleCodableTests` in a new
  `Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift`) and concatenate it
  into the `runTests("EditorKitTests", …)` call in `main.swift`.
- **Round-trip test:** JSON-encode a non-default `AnnotationStyle` (e.g. blue stroke, `lineWidth`
  7, `fontSize` 36), decode it, and assert equality of all fields (`strokeColor`, `fillColor`,
  `lineWidth`, `fontSize`) within tolerance. This is the only pure logic the features add; it
  guards the persistence format.

The UI wiring (inspector reflecting the loaded style, persistence on change, the Stack button
flow) is verified manually below, consistent with the project's norm of TDD on pure logic and
manual checklists for system/UI behavior.

### Manual GUI checklist
1. **Sticky color:** Open editor, pick blue, close. Capture again, open editor → blue swatch is
   selected and new strokes are blue.
2. **Sticky size:** Set stroke to L and (with the Text tool) font to L, close. Reopen → both S/M/L
   segments show L; a new stroke/text is large.
3. **First-launch fallback:** With no saved style (fresh `UserDefaults`), the editor opens on red
   / M / M as before.
4. **Stack button replaces Pin:** Editor bottom bar shows Done · Stack · Save · Copy; no Pin
   button.
5. **Stack action:** Annotate, click Stack → editor closes, the edited image appears as the newest
   bottom-right Quick Access card, and it is present in History.
6. **Stack card actions:** That card's Copy / Edit / Pin / Save / drag all work; its Pin pins the
   edited image to screen.
7. **Pin still available:** A normal capture's overlay card still offers Pin-to-Screen.

---

## Out of scope
- No "Save as default" button and no Settings-window pickers for the editor style (sticky is
  automatic).
- Selected tool is not persisted.
- No keyboard shortcut for the Stack button.
- No change to the Quick Access stack cap, eviction, positioning, or the floating pin panel.

## Files touched
- `Packages/EditorKit/Sources/EditorKit/RGBAColor.swift` — add `Codable`.
- `Packages/EditorKit/Sources/EditorKit/AnnotationStyle.swift` — add `Codable`.
- `Packages/EditorKit/Sources/EditorKit/EditorWindowController.swift` — `defaultStyle` init param,
  `onStyleChanged` callback, seed canvas, Pin→Stack button + `onAddToStack`/`addToStackAction`.
- `Packages/EditorKit/Tests/EditorKitTests/AnnotationStyleCodableTests.swift` (new) +
  `main.swift` (register the array).
- `App/SettingsStore.swift` — `import EditorKit`, `editorStyle` property, load in `init`,
  `persistEditorStyle()`.
- `App/CaptureCoordinator.swift` — pass `defaultStyle`, wire `onStyleChanged`, replace `onPin`
  wiring with `onAddToStack` → new `keepInStack(_:)`.
