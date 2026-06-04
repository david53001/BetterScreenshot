# BetterScreenshot — Settings window fix + customizable shortcuts

Date: 2026-06-04 · Status: **shipped 2026-06-04** (tag `v1.4-shortcuts`; see CHANGELOG.md)
Builds on: v1.3-ocr-pin (`main`) · Ends at tag: `v1.4-shortcuts`

## Goal

1. **Fix the Settings window.** The menu item relies on the private `showSettingsWindow:`
   selector, which macOS 14 broke for `LSUIElement` apps — clicking "Settings…" silently
   does nothing. Replace it with a window we own.
2. **Customizable global hotkeys** for every action, edited in a new Shortcuts tab:
   click a recorder well, type the combo, it applies live (no restart) and persists.
3. **New defaults that free ⌘⇧5 for recording** (the next project):
   ⌘⇧4 area · ⌘⇧6 fullscreen · ⌘⇧7 capture text · **⌘⇧8 window (moved off ⌘⇧5)** ·
   Pin from Clipboard unbound · **⌘⇧5 intentionally unassigned, reserved as the future
   default for Start/Stop Recording.**

## Out of scope

Screen recording itself (next spec) · changes to native symbolic-hotkey suppression
(native ⌘⇧4 stays disabled while the app runs, regardless of bindings) · per-action
enable/disable toggles · chorded or multi-stroke shortcuts.

## UX flows

### Settings window (the fix)
- "Settings…" in the menu bar opens a window we create and own: app activates, window
  centers on first open, comes to the front; later opens reuse the same window.
- The window is a native tabbed settings layout: **General** (the existing form,
  unchanged) and **Shortcuts** (new).

### Shortcuts tab
- One row per action — Capture Area, Capture Window, Capture Fullscreen, Capture Text,
  Pin from Clipboard — each with the action name, a recorder well showing the current
  combo (e.g. "⌘⇧4", or "—" when unbound), and a clear (✕) button.
- **Recording a combo:** click the well → it shows "Type shortcut…" and captures the
  next keypress that includes at least one of ⌘ ⌥ ⌃. Esc cancels. ⌫ clears the binding.
  While a well is active, **all of the app's hotkeys are suspended** so a currently
  bound combo can be re-typed without firing a capture.
- **Conflict inside the app** (combo already bound to another action): refused; a
  transient status line under the list says "Already used by <action>".
- **Rejected by macOS** (`RegisterEventHotKey` fails — another app or the system owns
  it): the previous binding is restored and the status line says "That shortcut is in
  use by another app or macOS."
- **Restore Defaults** button resets every row to the defaults above.
- Rows whose combo failed to register at launch (e.g. another app grabbed it since last
  run) show a "couldn't register" annotation.
- The menu-bar items display the current shortcut next to each action (display only —
  firing remains Carbon hotkeys). They refresh whenever bindings change.

## Architecture

### CaptureKit (pure logic, TestKit-tested)
- `HotkeyCombo.swift` — struct: Carbon `keyCode: UInt32` + Carbon modifier mask.
  Pure helpers: `displayString` ("⌃⌥⇧⌘" glyph order + key-cap name from a static
  keyCode table: letters, digits, F1–F20, arrows, space/return/tab/esc, punctuation;
  unknown codes fall back to "(key N)"); `isValid` (requires ⌘, ⌥, or ⌃);
  `keyEquivalent`/`cocoaModifierFlags` for NSMenuItem display (empty string when the
  key has no menu representation); string-dictionary persistence matching the
  `CaptureSettings` convention.
- `HotkeyAction.swift` — `enum HotkeyAction: String, CaseIterable`: `captureArea,
  captureWindow, captureFullscreen, captureText, pinFromClipboard`. Each has a `title`
  and `defaultCombo` (area ⌘⇧4 · window ⌘⇧8 · fullscreen ⌘⇧6 · text ⌘⇧7 · pin nil).
  Recording (next project) adds a `record` case defaulting to ⌘⇧5.
- `HotkeyBindings.swift` — `[HotkeyAction: HotkeyCombo]` wrapper: `.defaults`,
  `combo(for:)`, `set`/`clear`, `conflictingAction(for:excluding:)`, dictionary
  round-trip.
- Tests: display strings, defaults table, validity rule, conflict detection,
  persistence round-trips, menu key-equivalent mapping.

### App
- `main.swift` **replaces** `BetterScreenshotApp.swift`: plain `NSApplication` +
  existing `AppDelegate` (the SwiftUI `App` lifecycle existed only for the broken
  `Settings` scene).
- `SettingsWindowController.swift` — owns one lazily created `NSWindow` hosting
  `SettingsView` (`NSHostingView`), title "Settings", fixed width, `isReleasedWhenClosed
  = false`. `show()` = activate app + center-on-first-open + `makeKeyAndOrderFront`.
- `HotKeyManager` — gains `unregisterAll()` and
  `apply(_ bindings:, handlers: [HotkeyAction: () -> Void]) -> Set<HotkeyAction>`
  (returns the actions whose registration failed) plus `suspend()`/`resume()` for the
  recorder session (suspend = unregister everything; resume = re-apply current
  bindings).
- `SettingsStore` — `@Published var bindings: HotkeyBindings` persisted under
  `"hotkeyBindings"`; `@Published var failedActions: Set<HotkeyAction>` (not persisted,
  set after each apply).
- `AppDelegate` — replaces the four hard-coded `register` calls with one
  `applyBindings()` building the handler map; re-applies via Combine whenever
  `store.bindings` changes, then refreshes the menu.
- `MenuBarController` — sets `keyEquivalent`/`keyEquivalentModifierMask` from bindings;
  `refresh(bindings:)` rebuilds the menu; opens settings through the injected
  `SettingsWindowController` (no more private selector).
- `SettingsView` — becomes a `TabView` (General | Shortcuts). New `ShortcutsTabView`:
  rows of `ShortcutRecorderField` (a small AppKit `NSView` in `NSViewRepresentable`;
  active state runs a local `NSEvent` monitor) + clear buttons + Restore Defaults +
  one transient status line. Recorder activation/deactivation calls
  `onRecordBegin`/`onRecordEnd` closures (wired by `SettingsWindowController` to
  `HotKeyManager.suspend`/`resume`); deactivation also fires on window close.

### Data flow
Shortcuts tab edit → conflict check (refuse inline) → `store.bindings` updated +
persisted → AppDelegate sink re-applies to `HotKeyManager` (failure → revert binding +
status line) → menu refreshes key equivalents. Launch follows the same apply path with
stored-or-default bindings.

## Edge cases
- Re-typing an action's own current combo → accepted no-op.
- Recorder active when the window closes → session ends, hotkeys resume.
- Launch-time registration failures don't block the app: menu actions still work,
  row shows "couldn't register".
- No migration needed: bindings were never stored before, so every user starts from
  the new defaults (window capture moves ⌘⇧5 → ⌘⇧8).

## Testing
- `swift test` (CaptureKit): all pure logic above.
- Manual GUI checklist (in the plan): Settings opens from the menu (the original bug);
  both tabs render; rebinding each action works live; in-app conflict refused with
  message; macOS-owned combo reverts with message; bindings survive relaunch; menu
  shows equivalents; ⌘⇧8 captures a window; hotkeys are suspended while recording a
  combo; Restore Defaults works; ⌘⇧5 does nothing (reserved).
