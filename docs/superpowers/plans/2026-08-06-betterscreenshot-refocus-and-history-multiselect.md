# Refocus-After-Capture + History Drag & Multi-Select — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended)
> or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`)
> syntax for tracking.

**Goal:** After a screenshot, BetterScreenshot hands keyboard focus back to the app you were using; and
the History window lets you drag captures out to Finder/chat/terminal and select several at once with
⇧-click and ⌘-click.

**Architecture:** Two independent features in one plan.

*Feature A (Tasks 1–2, refocus).* BetterScreenshot is an `LSUIElement` menu-bar agent. Today
`SelectionOverlayController.present()` calls `NSApp.activate(ignoringOtherApps: true)`
(`Packages/OverlayKit/Sources/OverlayKit/SelectionOverlayController.swift:39`) so the borderless
selection overlay can receive the Escape key — and nothing ever hands focus back, so after every
⌘⇧4 the user has to click their old window to resume typing. The Quick Access card and the HUD are
already `.nonactivatingPanel` and are **not** the problem. Fix: `CaptureCoordinator` remembers
`NSWorkspace.shared.frontmostApplication` when a capture starts and reactivates it once the capture
has finished. Restoring *after* the pixels are grabbed is deliberate — reactivating first could
re-order windows and change what gets captured.

*Feature B (Tasks 3–6, History).* The History window
(`App/History/HistoryWindowController.swift`) is a SwiftUI `LazyVGrid` with single-`UUID?` selection
and no drag support. Selection becomes a `Set<UUID>` plus a shift-anchor, with the selection
arithmetic living as a pure, unit-tested function in `Packages/HistoryKit`. Drag needs a real
multi-item `NSDraggingSession`, which SwiftUI's single-item `.onDrag` cannot express, so each cell
gets a thin transparent `NSViewRepresentable` layer that owns mouse-down/drag and forwards
modifier-aware clicks back to SwiftUI. Dragged files are the **persistent** history-owned PNGs and
saved recording files — never `$TMPDIR` copies — so the "Keep cached files for" retention window
can't delete a file out from under a drop target.

**Tech Stack:** Swift 5.9, SwiftUI + AppKit hybrid, SwiftPM local packages, TestKit executable test
runners (XCTest is unavailable under Command Line Tools only).

## Global Constraints

- **Min target: macOS 14 (Sonoma).** No API newer than macOS 14.
- **No cloud.** No uploads, share links, accounts, or sync. Local features only.
- **No XCTest.** Tests are `[TestCase]` arrays using `Packages/TestKit`, aggregated in each package's
  `Tests/<Pkg>Tests/main.swift`. Run everything with `scripts/test.sh`.
- **Pure logic lives in `Packages/*` and is unit-tested; AppKit/SwiftUI glue lives in `App/` and is
  verified by hand.** Follow this split — do not put AppKit imports in HistoryKit.
- **`App/` is a single SwiftPM target.** Every `.swift` under `App/` compiles into the same module;
  the subfolders are organization only and need no `import` between them.
- **Surgical changes only.** Every changed line must trace to this plan. Do not reformat, rename, or
  "improve" adjacent code.
- **Commit after every task**, using the exact message given in the task's final step.
- **History has no time expiry.** Do not add age-based pruning to HistoryKit — the count cap is the
  only prune (see `HistoryIndex.pruned(cap:)`).

## File Structure

| File | Status | Responsibility |
|---|---|---|
| `Packages/CaptureKit/Sources/CaptureKit/FocusRestore.swift` | create | Pure predicate: should we reactivate the remembered app? |
| `Packages/CaptureKit/Tests/CaptureKitTests/FocusRestoreTests.swift` | create | Tests for the above |
| `Packages/CaptureKit/Tests/CaptureKitTests/main.swift` | modify | Register the new test array |
| `App/Capture/CaptureCoordinator.swift` | modify | Remember + restore the frontmost app around a capture |
| `Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift` | create | Pure ⇧/⌘ click → selection arithmetic |
| `Packages/HistoryKit/Tests/HistoryKitTests/HistorySelectionTests.swift` | create | Tests for the above |
| `Packages/HistoryKit/Tests/HistoryKitTests/main.swift` | modify | Register the new test array |
| `App/History/HistoryItemInteraction.swift` | create | AppKit mouse/drag layer bridged into SwiftUI |
| `App/History/HistoryService.swift` | modify | Drag URLs + batch copy/delete/reveal |
| `App/History/HistoryWindowController.swift` | modify | Set-based selection, drag overlay, batch action bar |
| `App/History/CLAUDE.md` | modify | Note the new interaction layer |
| `CHANGELOG.md` | modify | Release notes |
| `CLAUDE.md` | modify | Roadmap entry |

---

### Task 1: `FocusRestore` — the pure "should we hand focus back?" rule

Isolates the one decision worth testing in Feature A: never reactivate ourselves, and never try to
reactivate nothing.

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/FocusRestore.swift`
- Test: `Packages/CaptureKit/Tests/CaptureKitTests/FocusRestoreTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `FocusRestore.shouldRestore(previousBundleID: String?, ownBundleID: String?) -> Bool`,
  used by Task 2.

- [ ] **Step 1: Write the failing test**

Create `Packages/CaptureKit/Tests/CaptureKitTests/FocusRestoreTests.swift`:

```swift
import TestKit
@testable import CaptureKit

let focusRestoreTests: [TestCase] = [
    TestCase("restoresADifferentApp") { t in
        t.isTrue(FocusRestore.shouldRestore(previousBundleID: "com.apple.Safari",
                                            ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("neverRestoresOurselves") { t in
        t.isFalse(FocusRestore.shouldRestore(previousBundleID: "com.betterscreenshot.app",
                                             ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("noPreviousAppMeansNothingToRestore") { t in
        t.isFalse(FocusRestore.shouldRestore(previousBundleID: nil,
                                             ownBundleID: "com.betterscreenshot.app"))
    },
    TestCase("unknownOwnBundleStillRestores") { t in
        // Defensive: if we can't identify ourselves, handing focus back to a
        // named app is still better than stranding the user on the agent.
        t.isTrue(FocusRestore.shouldRestore(previousBundleID: "com.apple.Terminal",
                                            ownBundleID: nil))
    },
]
```

- [ ] **Step 2: Register the array in the runner**

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, add `focusRestoreTests` to the
concatenation. Change the last line of the `runTests` call from:

```swift
    selectionClampTests
)
```

to:

```swift
    selectionClampTests +
    focusRestoreTests
)
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: FAIL to compile — `cannot find 'FocusRestore' in scope`.

- [ ] **Step 4: Write the minimal implementation**

Create `Packages/CaptureKit/Sources/CaptureKit/FocusRestore.swift`:

```swift
import Foundation

/// Decides whether a finished capture should hand keyboard focus back to the
/// app that was frontmost when the capture started.
///
/// BetterScreenshot is a menu-bar agent that has to activate itself so the
/// borderless selection overlay can receive Escape. That leaves the user's real
/// app unfocused, so we reactivate it afterwards — unless we *were* the app
/// they were using, or there is nothing to go back to.
public enum FocusRestore {
    public static func shouldRestore(previousBundleID: String?, ownBundleID: String?) -> Bool {
        guard let previousBundleID else { return false }
        return previousBundleID != ownBundleID
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: PASS, with `focusRestoreTests`' four cases listed and the suite total up by 4.

- [ ] **Step 6: Commit**

```bash
git add Packages/CaptureKit/Sources/CaptureKit/FocusRestore.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/FocusRestoreTests.swift \
        Packages/CaptureKit/Tests/CaptureKitTests/main.swift
git commit -m "feat(capture): pure rule for handing focus back after a capture"
```

---

### Task 2: Hand focus back to the previous app after a screenshot

Wires Task 1 into the capture flow. All four screenshot entry points are covered, including Capture
Text (⌘⇧7) — that one matters most, since OCR exists so you can paste the text straight back into
whatever you were doing.

**Files:**
- Modify: `App/Capture/CaptureCoordinator.swift`

**Interfaces:**
- Consumes: `FocusRestore.shouldRestore(previousBundleID:ownBundleID:)` from Task 1.
- Produces: nothing consumed by later tasks.

**Background the implementer needs:**
- `CaptureCoordinator` is `@MainActor` and already imports `AppKit` and `CaptureKit`.
- `run(_:sourceRect:)` is the shared tail for area/fullscreen/window captures and ends in
  `handle(_:sourceRect:)`. `runCaptureText(_:)` is the separate OCR tail.
- `overlay.present { result in … }` fires its closure with `nil` when the user presses Escape.
- On macOS 14, use `NSRunningApplication.activate()` — **not** the deprecated
  `activate(options: .activateIgnoringOtherApps)`.

- [ ] **Step 1: Add the stored property and the two helpers**

In `App/Capture/CaptureCoordinator.swift`, immediately after the `private var editorController:
EditorWindowController?` line (currently line 27), add:

```swift
    /// The app that was frontmost when the current capture began, so focus can
    /// be handed back once we're done stealing it for the selection overlay.
    private var previousApp: NSRunningApplication?
```

Then add these two methods just above the closing brace's `private func frontmostWindowID()`:

```swift
    /// Remembers who had focus before the selection overlay activates us.
    private func rememberFrontmostApp() {
        previousApp = NSWorkspace.shared.frontmostApplication
    }

    /// Hands focus back to that app. Safe to call more than once per capture —
    /// the remembered app is cleared on the first call.
    private func restoreFrontmostApp() {
        guard let app = previousApp else { return }
        previousApp = nil
        guard FocusRestore.shouldRestore(previousBundleID: app.bundleIdentifier,
                                         ownBundleID: Bundle.main.bundleIdentifier) else { return }
        app.activate()
    }
```

- [ ] **Step 2: Remember the frontmost app at every screenshot entry point**

Still in `App/Capture/CaptureCoordinator.swift`, add `rememberFrontmostApp()` as the first line of
each of the four capture entry points, *before* the permission check. The four methods become:

```swift
    func captureArea() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self else { return }
            guard let result else { self.restoreFrontmostApp(); return }
            Task { await self.run(.area(rect: result.globalRect, displayID: result.displayID),
                                  sourceRect: result.globalRect) }
        }
    }

    func captureFullscreen() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        Task { await run(.fullscreen(displayID: CGMainDisplayID())) }
    }

    func captureFrontWindow() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        Task { if let id = await frontmostWindowID() { await run(.window(windowID: id)) } }
    }

    func captureText() {
        rememberFrontmostApp()
        guard ensurePermission() else { return }
        overlay.present { [weak self] result in
            guard let self else { return }
            guard let result else { self.restoreFrontmostApp(); return }
            Task { await self.runCaptureText(result) }
        }
    }
```

Note the reshaped `guard` in `captureArea` and `captureText`: the old single
`guard let self, let result else { return }` swallowed the Escape case, and Escape must now restore
focus too. Keep `captureText`'s existing doc comment above it.

- [ ] **Step 3: Restore focus once the capture has finished**

Restoration happens **after** the image is captured and the after-capture action has run, so the
reactivated app can't re-order windows into the shot.

In `run(_:sourceRect:)`, restore on the failure path as well — a failed capture shouldn't strand the
user on the agent:

```swift
    private func run(_ target: CaptureTarget, sourceRect: CGRect? = nil) async {
        do {
            let image = try await service.capture(target)
            handle(image, sourceRect: sourceRect)
        } catch {
            NSLog("Capture failed: \(error)")
            hud.show("Capture failed")
            restoreFrontmostApp()
        }
    }
```

In `handle(_:sourceRect:)`, add the restore as the final line:

```swift
    private func handle(_ image: CGImage, sourceRect: CGRect?) {
        // Silent bookkeeping first, so even copy-only captures are recoverable.
        let historyID = history?.recordScreenshot(image)
        if settings.settings.playSound { CaptureSound.play() }
        switch settings.settings.afterCapture {
        case .copyOnly:    copy(image)
        case .saveOnly:    save(image)
        case .copyAndSave: copy(image); save(image)
        case .showOverlay: presentOverlay(image, sourceRect: sourceRect, historyID: historyID)
        }
        // The Quick Access card is a .nonactivatingPanel, so handing focus back
        // here leaves it on screen and clickable.
        restoreFrontmostApp()
    }
```

In `runCaptureText(_:)`, add the restore as the final line of the method, after the `do/catch` block,
so it runs on both the success and the failure path. The whole method becomes:

```swift
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
        } catch {
            NSLog("Capture Text failed: \(error)")
            hud.show("Capture Text failed", on: screen(for: result.displayID))
        }
        // Focus goes back last, so the recognized text can be pasted straight
        // into the app the user was already in.
        restoreFrontmostApp()
    }
```

- [ ] **Step 4: Verify it compiles and the suites still pass**

Run: `swift build && scripts/test.sh`
Expected: build succeeds; `All suites passed.`

- [ ] **Step 5: Verify by hand in the built app**

Run: `scripts/build-app.sh && open -n dist/BetterScreenshot.app`

Then check each case (the running `/Applications` copy is a *different* process — quit it first via
its menu-bar icon so hotkeys don't go to the old build):

1. Focus TextEdit and place the cursor in a document. Press ⌘⇧4, drag a region. → After the Quick
   Access card appears, type. **Expected:** the characters land in TextEdit; the card stays visible.
2. Same, but press Escape instead of dragging. **Expected:** focus returns to TextEdit.
3. Press ⌘⇧7 (Capture Text) over some text, then press ⌘V in TextEdit. **Expected:** the recognized
   text pastes without clicking TextEdit first.
4. Open Settings → set After capture to "Copy to clipboard", take a ⌘⇧4. **Expected:** focus returns.
5. Trigger "Capture Area" from the menu-bar menu instead of the hotkey. **Expected:** no crash, and
   focus goes to whatever app was frontmost before you opened the menu.

- [ ] **Step 6: Commit**

```bash
git add App/Capture/CaptureCoordinator.swift
git commit -m "feat(capture): return focus to the previous app after a screenshot"
```

---

### Task 3: `HistorySelection` — pure ⇧/⌘ click arithmetic

Standard macOS list-selection semantics as a pure function, so the History window's click handling has
no untested branching. Plain click replaces the selection; ⌘-click toggles one item; ⇧-click selects
the contiguous run between the anchor and the clicked item.

**Files:**
- Create: `Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift`
- Test: `Packages/HistoryKit/Tests/HistoryKitTests/HistorySelectionTests.swift`
- Modify: `Packages/HistoryKit/Tests/HistoryKitTests/main.swift`

**Interfaces:**
- Consumes: nothing.
- Produces, all used by Tasks 4 and 6:
  - `enum HistoryClickModifier { case none, command, shift }`
  - `struct HistorySelectionState: Equatable { var selected: Set<UUID>; var anchor: UUID?;
    init(selected: Set<UUID> = [], anchor: UUID? = nil) }`
  - `HistorySelection.click(on: UUID, modifier: HistoryClickModifier, order: [UUID],
    state: HistorySelectionState) -> HistorySelectionState`
  - `HistorySelection.dragStart(on: UUID, order: [UUID], state: HistorySelectionState)
    -> HistorySelectionState`

- [ ] **Step 1: Write the failing tests**

Create `Packages/HistoryKit/Tests/HistoryKitTests/HistorySelectionTests.swift`:

```swift
import TestKit
import Foundation
@testable import HistoryKit

// A fixed newest-first order, mirroring HistoryIndex.entries.
private let a = UUID(), b = UUID(), c = UUID(), d = UUID()
private let order = [a, b, c, d]

private func state(_ selected: Set<UUID>, anchor: UUID?) -> HistorySelectionState {
    HistorySelectionState(selected: selected, anchor: anchor)
}

let historySelectionTests: [TestCase] = [
    TestCase("plainClickSelectsOnlyThatItem") { t in
        let s = HistorySelection.click(on: c, modifier: .none, order: order,
                                       state: state([a, b], anchor: a))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("commandClickAddsToSelection") { t in
        let s = HistorySelection.click(on: c, modifier: .command, order: order,
                                       state: state([a], anchor: a))
        t.equal(s.selected, [a, c])
        t.equal(s.anchor, c)
    },
    TestCase("commandClickTogglesOffWhenAlreadySelected") { t in
        let s = HistorySelection.click(on: a, modifier: .command, order: order,
                                       state: state([a, c], anchor: c))
        t.equal(s.selected, [c])
        t.equal(s.anchor, a)
    },
    TestCase("shiftClickSelectsRangeForwardFromAnchor") { t in
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([a], anchor: a))
        t.equal(s.selected, [a, b, c])
        t.equal(s.anchor, a, "the anchor stays put so the range can be re-dragged")
    },
    TestCase("shiftClickSelectsRangeBackwardFromAnchor") { t in
        let s = HistorySelection.click(on: a, modifier: .shift, order: order,
                                       state: state([c], anchor: c))
        t.equal(s.selected, [a, b, c])
        t.equal(s.anchor, c)
    },
    TestCase("shiftClickReplacesThePreviousRange") { t in
        // Anchor at a, previously ranged out to d; shift-clicking b shrinks it.
        let s = HistorySelection.click(on: b, modifier: .shift, order: order,
                                       state: state([a, b, c, d], anchor: a))
        t.equal(s.selected, [a, b])
        t.equal(s.anchor, a)
    },
    TestCase("shiftClickWithoutAnchorActsAsAPlainClick") { t in
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([], anchor: nil))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("shiftClickWithAStaleAnchorActsAsAPlainClick") { t in
        // The anchored entry was deleted since it was clicked.
        let s = HistorySelection.click(on: c, modifier: .shift, order: order,
                                       state: state([], anchor: UUID()))
        t.equal(s.selected, [c])
        t.equal(s.anchor, c)
    },
    TestCase("clickOnAnUnknownIDLeavesTheStateUnchanged") { t in
        let before = state([a], anchor: a)
        let s = HistorySelection.click(on: UUID(), modifier: .none, order: order, state: before)
        t.equal(s, before)
    },
    TestCase("dragOnAnUnselectedItemSelectsItAlone") { t in
        let s = HistorySelection.dragStart(on: d, order: order, state: state([a, b], anchor: a))
        t.equal(s.selected, [d])
        t.equal(s.anchor, d)
    },
    TestCase("dragOnASelectedItemKeepsTheWholeSelection") { t in
        let before = state([a, b], anchor: a)
        let s = HistorySelection.dragStart(on: b, order: order, state: before)
        t.equal(s, before)
    },
]
```

- [ ] **Step 2: Register the array in the runner**

In `Packages/HistoryKit/Tests/HistoryKitTests/main.swift`, change the last line of the `runTests`
call from:

```swift
    historyStoreTests
)
```

to:

```swift
    historyStoreTests +
    historySelectionTests
)
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: FAIL to compile — `cannot find 'HistorySelection' in scope`.

- [ ] **Step 4: Write the minimal implementation**

Create `Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift`:

```swift
import Foundation

/// Which modifier the user was holding when they clicked a history item.
public enum HistoryClickModifier {
    case none, command, shift
}

/// The History window's selection: the chosen entries plus the anchor a
/// ⇧-click ranges from.
public struct HistorySelectionState: Equatable {
    public var selected: Set<UUID>
    public var anchor: UUID?

    public init(selected: Set<UUID> = [], anchor: UUID? = nil) {
        self.selected = selected
        self.anchor = anchor
    }
}

/// Standard macOS list-selection arithmetic, kept pure so the History window
/// itself has nothing to branch on. `order` is the displayed order — for the
/// History window that is `HistoryIndex.entries` (newest first).
public enum HistorySelection {

    public static func click(on id: UUID,
                             modifier: HistoryClickModifier,
                             order: [UUID],
                             state: HistorySelectionState) -> HistorySelectionState {
        guard let clicked = order.firstIndex(of: id) else { return state }

        switch modifier {
        case .none:
            return HistorySelectionState(selected: [id], anchor: id)

        case .command:
            var selected = state.selected
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
            return HistorySelectionState(selected: selected, anchor: id)

        case .shift:
            // No usable anchor (first click, or the anchored entry was deleted)
            // degrades to a plain click, which is what Finder does.
            guard let anchor = state.anchor, let start = order.firstIndex(of: anchor) else {
                return HistorySelectionState(selected: [id], anchor: id)
            }
            let range = start <= clicked ? start...clicked : clicked...start
            return HistorySelectionState(selected: Set(order[range]), anchor: anchor)
        }
    }

    /// A drag that starts on an unselected item selects just that item first;
    /// starting on an already-selected item drags the whole selection.
    public static func dragStart(on id: UUID,
                                 order: [UUID],
                                 state: HistorySelectionState) -> HistorySelectionState {
        if state.selected.contains(id) { return state }
        return click(on: id, modifier: .none, order: order, state: state)
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift run --package-path Packages/HistoryKit HistoryKitTests`
Expected: PASS — 38/38 tests (27 existing + 11 new).

- [ ] **Step 6: Commit**

```bash
git add Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift \
        Packages/HistoryKit/Tests/HistoryKitTests/HistorySelectionTests.swift \
        Packages/HistoryKit/Tests/HistoryKitTests/main.swift
git commit -m "feat(history): pure shift/command click selection arithmetic"
```

---

### Task 4: `HistoryItemInteraction` — the AppKit mouse & drag layer

SwiftUI can't express a multi-item drag (`.onDrag` returns exactly one `NSItemProvider`) and gives no
access to the modifier flags of a tap. This transparent `NSView`, overlaid on each grid cell, owns
mouse-down and mouse-drag and reports both back to SwiftUI.

**Files:**
- Create: `App/History/HistoryItemInteraction.swift`

**Interfaces:**
- Consumes: `HistoryClickModifier` from Task 3.
- Produces, used by Task 6:
  - `struct HistoryDragItem { let url: URL; let image: NSImage?; init(url: URL, image: NSImage?) }`
  - `struct HistoryItemInteraction: NSViewRepresentable` with initialiser
    `init(onClick: @escaping (HistoryClickModifier, Int) -> Void,
    dragItems: @escaping () -> [HistoryDragItem])`

**Background the implementer needs:**
- `Packages/OverlayKit/Sources/OverlayKit/DraggableImageView.swift` is the existing precedent for the
  4-point drag threshold and the `NSDraggingSource` conformance — read it first and match its shape.
- Do **not** override `rightMouseDown` and do **not** assign `view.menu`. `NSView`'s default
  `rightMouseDown` asks `menu(for:)` (nil here) and then forwards up the responder chain to the
  SwiftUI hosting view, which is what keeps the existing `.contextMenu` working. Step 4 verifies this
  by hand and gives the fallback if it doesn't hold.
- `App/` is one module — this file needs `import HistoryKit` for `HistoryClickModifier`, but no
  import for other `App/` files.

- [ ] **Step 1: Write the interaction layer**

Create `App/History/HistoryItemInteraction.swift`:

```swift
import AppKit
import SwiftUI
import HistoryKit

/// One file to drag out of History, with the thumbnail to drag under the cursor.
struct HistoryDragItem {
    let url: URL
    let image: NSImage?

    init(url: URL, image: NSImage?) {
        self.url = url
        self.image = image
    }
}

/// A transparent AppKit layer over a History grid cell. It exists for two things
/// SwiftUI can't do on macOS 14: read the modifier keys held during a click, and
/// start a dragging session carrying more than one file.
struct HistoryItemInteraction: NSViewRepresentable {
    /// (modifier, clickCount) — clickCount 2 is the open/annotate gesture.
    let onClick: (HistoryClickModifier, Int) -> Void
    /// Evaluated at drag time, so it sees the selection the click just made.
    let dragItems: () -> [HistoryDragItem]

    func makeNSView(context: Context) -> HistoryItemView {
        let view = HistoryItemView()
        view.onClick = onClick
        view.dragItems = dragItems
        return view
    }

    func updateNSView(_ view: HistoryItemView, context: Context) {
        view.onClick = onClick
        view.dragItems = dragItems
    }
}

final class HistoryItemView: NSView, NSDraggingSource {
    var onClick: ((HistoryClickModifier, Int) -> Void)?
    var dragItems: (() -> [HistoryDragItem])?

    private var mouseDownPoint: NSPoint?

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext)
        -> NSDragOperation { .copy }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        onClick?(Self.modifier(for: event), event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        // Only start a drag once the pointer actually moves, so a plain click
        // never fires a zero-length drag. Same 4pt threshold as DraggableImageView.
        guard let down = mouseDownPoint else { return }
        let p = event.locationInWindow
        guard hypot(p.x - down.x, p.y - down.y) >= 4 else { return }
        mouseDownPoint = nil

        let items = dragItems?() ?? []
        guard !items.isEmpty else { return }

        let dragging: [NSDraggingItem] = items.enumerated().map { index, item in
            let di = NSDraggingItem(pasteboardWriter: item.url as NSURL)
            // Fan the thumbnails out slightly so a multi-file drag reads as a stack.
            let offset = CGFloat(index) * 8
            di.setDraggingFrame(bounds.offsetBy(dx: offset, dy: -offset), contents: item.image)
            return di
        }
        beginDraggingSession(with: dragging, event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    private static func modifier(for event: NSEvent) -> HistoryClickModifier {
        // Shift wins over Command when both are held, matching Finder.
        if event.modifierFlags.contains(.shift) { return .shift }
        if event.modifierFlags.contains(.command) { return .command }
        return .none
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `swift build`
Expected: build succeeds. Nothing constructs `HistoryItemInteraction` yet — Task 6 does — so this
step only proves the type compiles.

- [ ] **Step 3: Commit**

```bash
git add App/History/HistoryItemInteraction.swift
git commit -m "feat(history): AppKit mouse and multi-file drag layer for history cells"
```

- [ ] **Step 4: (Deferred verification note — no action now)**

The right-click passthrough is verified in Task 6 Step 5, once cells actually use this view. If the
existing context menu stops appearing there, the fix is to give this view its own menu instead of
relying on the responder chain — Task 6 Step 5 spells that out.

---

### Task 5: `HistoryService` — drag URLs and batch actions

The window needs a file URL per entry to drag, and needs Copy / Delete / Show in Finder to act on a
whole selection. Keeping this in the service means the view stays declarative.

**Files:**
- Modify: `App/History/HistoryService.swift`

**Interfaces:**
- Consumes: existing `HistoryStore` API — `imageURL(for:) -> URL?`, `savedFileURL(for:) -> URL?`,
  `remove(id:)`, `index.entries`.
- Produces, used by Task 6:
  - `func dragURL(for entry: HistoryEntry) -> URL?`
  - `func copyToClipboard(_ entries: [HistoryEntry])`
  - `func delete(_ entries: [HistoryEntry])`
  - `func revealInFinder(_ entries: [HistoryEntry])`

**Background the implementer needs:**
- The existing single-entry `copyToClipboard(_:)`, `delete(_:)` and `revealInFinder(_:)` stay exactly
  as they are — the new array overloads are additions, and Swift resolves them by argument type.
- A screenshot's draggable file is the history-owned PNG (`store.imageURL(for:)`), which lives in
  `~/Library/Application Support/BetterScreenshot/History/` and is **not** swept by the
  "Keep cached files for" temp retention. Never hand a `$TMPDIR` path to a drag.
- Recordings are referenced, never copied — their file may have been deleted in Finder, so
  `dragURL(for:)` must return nil when the file is gone.

- [ ] **Step 1: Add `dragURL(for:)`**

In `App/History/HistoryService.swift`, add immediately after the existing
`func savedFileExists(_ entry: HistoryEntry) -> Bool { store.savedFileExists(entry) }` line:

```swift
    /// The file to put on the pasteboard when this entry is dragged out:
    /// the history-owned PNG for screenshots, the user's saved file for
    /// recordings. Nil when the file is missing, so it is simply skipped.
    func dragURL(for entry: HistoryEntry) -> URL? {
        var url: URL?
        switch entry.kind {
        case .screenshot: url = store.imageURL(for: entry)
        case .recording:  url = store.savedFileURL(for: entry)
        }
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
```

- [ ] **Step 2: Add the batch copy overload**

Add directly below the existing single-entry `copyToClipboard(_ entry: HistoryEntry)` method:

```swift
    /// Multi-selection copy. One entry keeps the rich single-item behaviour
    /// (image data + file URL); several write file URLs, which is what Finder,
    /// Mail and chat apps accept for a multi-file paste.
    func copyToClipboard(_ entries: [HistoryEntry]) {
        guard entries.count != 1 else { copyToClipboard(entries[0]); return }
        let urls = entries.compactMap { dragURL(for: $0) }
        guard !urls.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        hud.show("\(urls.count) files copied")
    }
```

- [ ] **Step 3: Add the batch delete and reveal overloads**

Add directly below the existing `func delete(_ entry: HistoryEntry)`:

```swift
    func delete(_ entries: [HistoryEntry]) {
        for entry in entries { store.remove(id: entry.id) }
        self.entries = store.index.entries
    }
```

And directly below the existing `func revealInFinder(_ entry: HistoryEntry)`:

```swift
    /// Reveals every selected file in one Finder window.
    func revealInFinder(_ entries: [HistoryEntry]) {
        let urls = entries.compactMap { revealURL(for: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
```

Note `delete(_ entries:)` writes `self.entries` — the parameter shadows the `@Published entries`
property, so the explicit `self.` is required and is not optional style.

- [ ] **Step 4: Verify it compiles and the suites still pass**

Run: `swift build && scripts/test.sh`
Expected: build succeeds; `All suites passed.`

- [ ] **Step 5: Commit**

```bash
git add App/History/HistoryService.swift
git commit -m "feat(history): drag URLs and batch copy/delete/reveal"
```

---

### Task 6: Rewire the History window for multi-select and dragging

Replaces the single-`UUID?` selection with `HistorySelectionState`, hangs the Task 4 interaction layer
on every cell, and makes the action bar and context menu operate on the selection.

**Files:**
- Modify: `App/History/HistoryWindowController.swift`

**Interfaces:**
- Consumes: `HistorySelectionState`, `HistoryClickModifier`, `HistorySelection.click(on:modifier:order:state:)`,
  `HistorySelection.dragStart(on:order:state:)` (Task 3); `HistoryItemInteraction`, `HistoryDragItem`
  (Task 4); `dragURL(for:)`, `copyToClipboard(_:[HistoryEntry])`, `delete(_:[HistoryEntry])`,
  `revealInFinder(_:[HistoryEntry])` (Task 5).
- Produces: nothing.

**Background the implementer needs:**
- `HistoryWindowController.swift` already imports `AppKit`, `SwiftUI` and `HistoryKit`. The
  `HistoryWindowController` class (lines 1–39) and the `HistoryWindowActions` struct do **not**
  change — only `HistoryView` and `HistoryCell` do.
- The interaction view must be an `.overlay(...)`, not a `.background(...)`: AppKit hit-testing sends
  the mouse to the topmost view, and the layer needs to be on top to receive it.
- `history.entries` is newest-first and is the `order` array the selection arithmetic needs.

- [ ] **Step 1: Swap the selection state and the grid's per-cell interaction**

In `App/History/HistoryView`, replace `@State private var selection: UUID?` with:

```swift
    @State private var selection = HistorySelectionState()
```

Replace the `ForEach` body (currently lines 59–65) with:

```swift
                        ForEach(history.entries) { entry in
                            HistoryCell(entry: entry, history: history,
                                        isSelected: selection.selected.contains(entry.id))
                                .overlay(HistoryItemInteraction(
                                    onClick: { modifier, clicks in
                                        handleClick(entry, modifier: modifier, clicks: clicks)
                                    },
                                    dragItems: { dragItems(startingAt: entry) }))
                                .contextMenu { contextItems(for: entry) }
                        }
```

The old `.gesture(TapGesture(count: 2))` and `.onTapGesture` are deleted — the AppKit layer now owns
clicks, and leaving the SwiftUI gestures in place would double-handle them.

- [ ] **Step 2: Add the click and drag handlers, and swap `selected` for a selection list**

Replace the single `private var selected: HistoryEntry?` computed property (currently line 75) with:

```swift
    /// The selected entries, in displayed order.
    private var selectedEntries: [HistoryEntry] {
        history.entries.filter { selection.selected.contains($0.id) }
    }

    /// The single selected entry, when the selection is exactly one.
    private var soleSelection: HistoryEntry? {
        selectedEntries.count == 1 ? selectedEntries[0] : nil
    }

    /// Context-menu and drag target: the whole selection when the clicked entry
    /// is part of it, otherwise just that entry — the Finder convention.
    private func targets(for entry: HistoryEntry) -> [HistoryEntry] {
        selection.selected.contains(entry.id) ? selectedEntries : [entry]
    }

    private func handleClick(_ entry: HistoryEntry, modifier: HistoryClickModifier, clicks: Int) {
        if clicks >= 2 {
            open(entry)
            return
        }
        selection = HistorySelection.click(on: entry.id, modifier: modifier,
                                           order: history.entries.map(\.id), state: selection)
    }

    /// Evaluated when a drag actually starts: an unselected cell becomes the
    /// selection first, then every selected entry with a file on disk is dragged.
    private func dragItems(startingAt entry: HistoryEntry) -> [HistoryDragItem] {
        selection = HistorySelection.dragStart(on: entry.id,
                                               order: history.entries.map(\.id), state: selection)
        return selectedEntries.compactMap { candidate in
            guard let url = history.dragURL(for: candidate) else { return nil }
            return HistoryDragItem(url: url, image: history.thumbnail(for: candidate))
        }
    }
```

- [ ] **Step 3: Make the action bar operate on the selection**

Replace the whole `actionBar` computed property (currently lines 77–106) with:

```swift
    private var actionBar: some View {
        HStack(spacing: 8) {
            Text(countLabel)
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear All…") { confirmingClear = true }
                .disabled(history.entries.isEmpty)
            Spacer()
            Button("Copy") { history.copyToClipboard(selectedEntries) }
                .disabled(selectedEntries.isEmpty)
            Button("Annotate") { if let e = soleSelection { annotate(e) } }
                .disabled(soleSelection?.kind != .screenshot)
            Button("Pin") { if let e = soleSelection { pin(e) } }
                .disabled(soleSelection?.kind != .screenshot)
            Button("Show in Finder") { history.revealInFinder(selectedEntries) }
                .disabled(!selectedEntries.contains { history.canReveal($0) })
            Button("Delete") { delete(selectedEntries) }
                .disabled(selectedEntries.isEmpty)
        }
        .padding(10)
        .background(.bar)
        .confirmationDialog("Clear all capture history?",
                            isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear All", role: .destructive) {
                selection = HistorySelectionState()
                history.clearAll()
            }
        } message: {
            Text("Removes every remembered capture and its stored copies. Saved recording files on disk are not deleted.")
        }
    }

    /// "12 items" normally; "3 of 12 selected" once more than one is picked.
    private var countLabel: String {
        let total = history.entries.count
        let picked = selection.selected.count
        if picked > 1 { return "\(picked) of \(total) selected" }
        return "\(total) item\(total == 1 ? "" : "s")"
    }
```

Annotate and Pin stay deliberately single-selection — opening five editor windows or five pins from
one click is not useful.

- [ ] **Step 4: Make the context menu and delete work on multiple entries**

Replace `contextItems(for:)` and `delete(_:)` (currently lines 108–120 and 143–146) with:

```swift
    @ViewBuilder
    private func contextItems(for entry: HistoryEntry) -> some View {
        let group = targets(for: entry)
        Button(group.count > 1 ? "Copy \(group.count) Items" : "Copy") {
            history.copyToClipboard(group)
        }
        if entry.kind == .screenshot {
            Button("Annotate") { annotate(entry) }
            Button("Pin") { pin(entry) }
        }
        if group.contains(where: { history.canReveal($0) }) {
            Button("Show in Finder") { history.revealInFinder(group) }
        }
        Divider()
        Button(group.count > 1 ? "Delete \(group.count) Items" : "Delete", role: .destructive) {
            delete(group)
        }
    }

    private func delete(_ entries: [HistoryEntry]) {
        let ids = Set(entries.map(\.id))
        selection.selected.subtract(ids)
        if let anchor = selection.anchor, ids.contains(anchor) { selection.anchor = nil }
        history.delete(entries)
    }
```

Annotate and Pin stay per-entry inside the context menu for the same reason as the action bar.

- [ ] **Step 5: Verify it builds, tests pass, and check the window by hand**

Run: `swift build && scripts/test.sh`
Expected: build succeeds; `All suites passed.`

Run: `scripts/build-app.sh && open -n dist/BetterScreenshot.app`
(Quit the `/Applications` copy from its menu-bar icon first.)

Take three or four screenshots so History has content, open **History** from the menu-bar menu, then
check:

1. **Single drag** — drag one thumbnail onto the Desktop. **Expected:** the PNG lands there, and the
   thumbnail follows the cursor during the drag.
2. **⌘-click** — click one cell, then ⌘-click two others. **Expected:** three cells highlighted; the
   bar reads "3 of N selected".
3. **⇧-click** — click the first cell, then ⇧-click the fourth. **Expected:** all four highlighted.
   ⇧-click the second. **Expected:** the range shrinks to the first two.
4. **Multi drag** — with three selected, drag from one of them onto the Desktop. **Expected:** three
   files land, and the drag image shows a fanned stack.
5. **Drag an unselected cell** while others are selected. **Expected:** the selection jumps to that
   one cell and only its file drags.
6. **Double-click** a screenshot. **Expected:** the annotation editor opens (unchanged behaviour).
7. **Right-click** a cell. **Expected:** the context menu appears with Copy / Annotate / Pin / Show in
   Finder / Delete. Right-click one of several selected cells. **Expected:** the menu reads
   "Copy 3 Items" / "Delete 3 Items".
8. **Batch delete** — select two, press Delete in the bar. **Expected:** both vanish, count updates.
9. **Show in Finder** with two selected. **Expected:** one Finder window with both files selected.
10. **Scrolling** — with enough captures to overflow the window, two-finger scroll with the pointer
    resting *over a thumbnail*. **Expected:** the grid scrolls normally. (`HistoryItemView` doesn't
    override `scrollWheel`, so the event forwards up the responder chain to the `ScrollView`. If
    scrolling is dead over cells, that assumption broke — add
    `override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }`
    to `HistoryItemView`.)

**If step 7 fails and no context menu appears**, the responder-chain passthrough described in Task 4
doesn't hold on this macOS version. Fix it by owning the menu in AppKit: add
`var menuProvider: (() -> NSMenu?)?` to `HistoryItemView`, override
`override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }`, pass a builder down through
`HistoryItemInteraction`, and construct the same five items as `NSMenuItem`s with closures. Remove
the SwiftUI `.contextMenu` in that case. Do not leave both in place.

- [ ] **Step 6: Commit**

```bash
git add App/History/HistoryWindowController.swift
git commit -m "feat(history): multi-select with shift/command click and drag-out"
```

---

### Task 7: Docs, deploy, and push

**Files:**
- Modify: `App/History/CLAUDE.md`, `CHANGELOG.md`, `CLAUDE.md`

- [ ] **Step 1: Update the History area brief**

In `App/History/CLAUDE.md`, add to the bullet list, after the `HistoryWindowController.swift` line:

```markdown
- `HistoryItemInteraction.swift` — transparent AppKit layer over each grid cell. Exists because
  SwiftUI on macOS 14 can neither read a click's modifier keys nor start a dragging session with more
  than one file. Selection arithmetic itself is pure and lives in `HistoryKit/HistorySelection.swift`.
```

And append this paragraph at the end of the file:

```markdown
Dragged files are always the **persistent** ones — the history-owned PNG under
`~/Library/Application Support/BetterScreenshot/History/` for screenshots, the user's saved file for
recordings — never a `$TMPDIR` copy, so the "Keep cached files for" sweep can't delete a file out
from under a drop target.
```

- [ ] **Step 2: Add the CHANGELOG entry**

In `CHANGELOG.md`, insert a new section immediately **after** the intro line that begins "All notable
changes to BetterScreenshot…" and **before** the existing `## v2.7.0 — 2026-08-01 · Temp-file
retention…` heading. Match that heading's `## <tag> — <date> · <short title>` shape:

```markdown
## v2.8.0 — 2026-08-06 · Focus hand-back + History drag & multi-select

### Added
- **Focus returns to your app after a capture.** Taking a screenshot (⌘⇧4 area, fullscreen, window)
  or running Capture Text (⌘⇧7) now hands keyboard focus back to whatever app was frontmost when you
  started — including when you cancel the selection with Escape. Previously BetterScreenshot kept
  focus and you had to click your window again before typing.
- **Drag captures out of History.** Drag any thumbnail in the History window straight into Finder, a
  chat, or a terminal. The dragged file is the stored copy, so it never expires.
- **Multi-select in History.** ⇧-click selects a contiguous range, ⌘-click toggles individual items.
  Copy, Delete and Show in Finder act on the whole selection, and dragging a multi-selection drags
  every file at once. Annotate and Pin remain single-selection.
```

- [ ] **Step 3: Update the roadmap in `CLAUDE.md`**

In the root `CLAUDE.md`, append this paragraph immediately after the **Temp-file retention** paragraph
in the Roadmap section:

```markdown
**Refocus after capture + History drag/multi-select** (shipped 2026-08-06, tag `v2.8.0`, plan:
`docs/superpowers/plans/2026-08-06-betterscreenshot-refocus-and-history-multiselect.md`): every
screenshot entry point in `CaptureCoordinator` now records `NSWorkspace.shared.frontmostApplication`
up front and reactivates it once the capture finishes — after the pixels are grabbed, so the restored
window ordering can't leak into the shot. The predicate is
`FocusRestore.shouldRestore(previousBundleID:ownBundleID:)` in CaptureKit. The focus theft itself
comes from `SelectionOverlayController.present()`'s `NSApp.activate(ignoringOtherApps:)`, which the
borderless overlay needs to receive Escape; the Quick Access card and HUD are `.nonactivatingPanel`
and never stole focus. In the History window, selection is now `HistorySelectionState`
(`Packages/HistoryKit/Sources/HistoryKit/HistorySelection.swift`, pure + unit-tested) driven by
`App/History/HistoryItemInteraction.swift`, a transparent AppKit view per cell — SwiftUI on macOS 14
can express neither modifier-aware clicks nor a multi-file `NSDraggingSession`.
```

- [ ] **Step 4: Full verification**

Run: `scripts/test.sh`
Expected: `All suites passed.` — CaptureKit up 4 tests, HistoryKit up 11 (38/38).

Run: `scripts/build-app.sh`
Expected: `==> Built dist/BetterScreenshot.app (signed with stable identity — permissions persist)`.

Do not proceed past this step if either command fails.

- [ ] **Step 5: Commit the docs**

```bash
git add App/History/CLAUDE.md CHANGELOG.md CLAUDE.md
git commit -m "docs: CHANGELOG v2.8.0 + briefs for refocus and history multi-select"
```

- [ ] **Step 6: Deploy to /Applications**

The owner runs the `/Applications` copy as a login item — a build in `dist/` alone changes nothing
they can see. Quit the running app from its menu-bar icon first, then:

```bash
rm -rf /Applications/BetterScreenshot.app
cp -R dist/BetterScreenshot.app /Applications/
open /Applications/BetterScreenshot.app
```

Confirm the menu-bar icon reappears, then re-run the Task 2 Step 5 and Task 6 Step 5 checks against
the installed copy.

- [ ] **Step 7: Push**

```bash
git push origin main
```

- [ ] **Step 8: Tag**

```bash
git tag v2.8.0
git push origin v2.8.0
```

---

## Pre-flight for whoever picks this up

- The working tree had 62 deleted files under `windows/src/BetterScreenshot.App/` on 2026-08-06;
  they were restored with `git restore` before this plan was written. Run `git status --short` first
  and confirm the tree is clean apart from the untracked `CODEBASE-SCAN.md`. Do not commit
  `CODEBASE-SCAN.md` — it is deliberately untracked.
- Baseline before starting: `scripts/test.sh` passes, HistoryKit at 27/27.
- This plan does not touch the Windows port under `windows/`. If parity is wanted later, it is a
  separate piece of work on the `windows-port` branch.
