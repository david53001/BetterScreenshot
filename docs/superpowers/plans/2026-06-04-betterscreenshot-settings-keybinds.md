# Settings Window Fix + Customizable Shortcuts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Settings window (broken on macOS 14 for this LSUIElement app) and make every global hotkey user-customizable from a new Shortcuts tab, freeing ⌘⇧5 for the upcoming recording feature (window capture moves to ⌘⇧8).

**Architecture:** Pure hotkey models (`HotkeyCombo`, `HotkeyAction`, `HotkeyBindings`) live in CaptureKit with TestKit coverage. The app drops the SwiftUI `App` lifecycle (it existed only for the broken `Settings` scene) for plain AppKit + a `SettingsWindowController` that owns the window. `HotKeyManager` learns to apply a whole bindings table and rebind live; a recorder field in the new Shortcuts tab captures combos with a local NSEvent monitor.

**Tech Stack:** Swift 5.9 SwiftPM (CLT only — **no xcodebuild, no XCTest**), TestKit executable test runners (`swift run --package-path Packages/CaptureKit CaptureKitTests`), AppKit + SwiftUI hybrid, Carbon `RegisterEventHotKey`.

**Spec:** `docs/superpowers/specs/2026-06-04-betterscreenshot-settings-keybinds-design.md`

---

## File map

| File | Change | Responsibility |
|---|---|---|
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyCombo.swift` | create | keyCode+modifier model, display string, validity, menu equivalents, persistence |
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift` | create | bindable-action enum, titles, default combos |
| `Packages/CaptureKit/Sources/CaptureKit/HotkeyBindings.swift` | create | action→combo map, conflicts, persistence |
| `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift` | create | tests for all three |
| `Packages/CaptureKit/Tests/CaptureKitTests/main.swift` | modify | aggregate new tests; later drop `keyCodeTests` |
| `Packages/CaptureKit/Sources/CaptureKit/KeyCombo.swift` | delete (Task 4) | superseded by HotkeyCombo |
| `Packages/CaptureKit/Tests/CaptureKitTests/KeyCodeTests.swift` | delete (Task 4) | tests of deleted type |
| `App/main.swift` | create | AppKit entry point |
| `App/AppDelegate.swift` | create | delegate moved out of BetterScreenshotApp.swift; bindings orchestration |
| `App/BetterScreenshotApp.swift` | delete | SwiftUI lifecycle no longer used |
| `App/SettingsWindowController.swift` | create | owns the Settings window (the bug fix) |
| `App/HotKeyManager.swift` | modify | `apply`/`suspend`/`resume`, table-driven registration |
| `App/SettingsStore.swift` | modify | persist `HotkeyBindings`, publish failures |
| `App/MenuBarController.swift` | modify | open our window; show key equivalents |
| `App/SettingsView.swift` | modify | TabView: General + Shortcuts |
| `App/ShortcutRecorderField.swift` | create | click-to-record well (NSViewRepresentable) |

---

### Task 1: `HotkeyCombo` model (CaptureKit, TDD)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/HotkeyCombo.swift`
- Create: `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

Create `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`:

```swift
import TestKit
import Foundation
@testable import CaptureKit

private let cmdShift = HotkeyCombo.commandMask | HotkeyCombo.shiftMask

let hotkeyComboTests: [TestCase] = [
    TestCase("displayStringGlyphOrder") { t in
        // ⌃⌥⇧⌘ is the standard macOS glyph order.
        let all = HotkeyCombo.commandMask | HotkeyCombo.shiftMask
                | HotkeyCombo.optionMask | HotkeyCombo.controlMask
        t.equal(HotkeyCombo(keyCode: 21, modifiers: all).displayString, "⌃⌥⇧⌘4")
        t.equal(HotkeyCombo(keyCode: 21, modifiers: cmdShift).displayString, "⌘⇧4")
    },
    TestCase("displayStringKeyNames") { t in
        t.equal(HotkeyCombo(keyCode: 28, modifiers: cmdShift).displayString, "⌘⇧8")
        t.equal(HotkeyCombo(keyCode: 49, modifiers: cmdShift).displayString, "⌘⇧Space")
        t.equal(HotkeyCombo(keyCode: 122, modifiers: cmdShift).displayString, "⌘⇧F1")
        t.equal(HotkeyCombo(keyCode: 126, modifiers: cmdShift).displayString, "⌘⇧↑")
        t.equal(HotkeyCombo(keyCode: 0, modifiers: cmdShift).displayString, "⌘⇧A")
        // Unknown codes fall back instead of crashing or showing nothing.
        t.equal(HotkeyCombo(keyCode: 999, modifiers: cmdShift).displayString, "⌘⇧(key 999)")
    },
    TestCase("validityRequiresCmdOptOrCtrl") { t in
        t.isTrue(HotkeyCombo(keyCode: 21, modifiers: cmdShift).isValid)
        t.isTrue(HotkeyCombo(keyCode: 21, modifiers: HotkeyCombo.optionMask).isValid)
        t.isTrue(HotkeyCombo(keyCode: 21, modifiers: HotkeyCombo.controlMask).isValid)
        // Shift alone (or nothing) would shadow normal typing.
        t.isFalse(HotkeyCombo(keyCode: 21, modifiers: HotkeyCombo.shiftMask).isValid)
        t.isFalse(HotkeyCombo(keyCode: 21, modifiers: 0).isValid)
    },
    TestCase("cocoaFlagConversionRoundTrip") { t in
        // Cocoa: shift 1<<17, control 1<<18, option 1<<19, command 1<<20.
        let combo = HotkeyCombo(keyCode: 28, cocoaModifierFlagsRaw: (1 << 20) | (1 << 17))
        t.equal(combo.modifiers, cmdShift)
        t.equal(combo.cocoaModifierFlags, UInt((1 << 20) | (1 << 17)))
        // Caps lock (1<<16) and other bits are ignored.
        let noisy = HotkeyCombo(keyCode: 28, cocoaModifierFlagsRaw: (1 << 20) | (1 << 16))
        t.equal(noisy.modifiers, HotkeyCombo.commandMask)
    },
    TestCase("menuKeyEquivalents") { t in
        t.equal(HotkeyCombo(keyCode: 21, modifiers: cmdShift).keyEquivalent, "4")
        t.equal(HotkeyCombo(keyCode: 0, modifiers: cmdShift).keyEquivalent, "a")
        t.equal(HotkeyCombo(keyCode: 49, modifiers: cmdShift).keyEquivalent, " ")
        // Keys with no menu representation produce "" (menu shows nothing).
        t.equal(HotkeyCombo(keyCode: 122, modifiers: cmdShift).keyEquivalent, "")
    },
    TestCase("comboDictionaryRoundTrip") { t in
        let combo = HotkeyCombo(keyCode: 26, modifiers: cmdShift)
        t.equal(HotkeyCombo(dictionary: combo.dictionary), combo)
        t.isNil(HotkeyCombo(dictionary: [:]))
        t.isNil(HotkeyCombo(dictionary: ["keyCode": "x", "modifiers": "768"]))
    },
]
```

- [ ] **Step 2: Add to the aggregate runner and verify the tests fail**

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, add `hotkeyComboTests +` after `keyCodeTests +`:

```swift
    keyCodeTests +
    hotkeyComboTests +
```

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: **build error** — `HotkeyCombo` not defined. (Build failure is this stack's "red".)

- [ ] **Step 3: Implement `HotkeyCombo`**

Create `Packages/CaptureKit/Sources/CaptureKit/HotkeyCombo.swift`:

```swift
import Foundation

/// A user-bindable global hotkey: Carbon virtual key code + Carbon modifier mask.
/// Pure model — actual registration lives in the app's HotKeyManager.
public struct HotkeyCombo: Equatable, Hashable {
    public var keyCode: UInt32
    /// Carbon mask: cmd 0x0100 · shift 0x0200 · option 0x0800 · control 0x1000.
    public var modifiers: UInt32

    public static let commandMask: UInt32 = 0x0100
    public static let shiftMask: UInt32   = 0x0200
    public static let optionMask: UInt32  = 0x0800
    public static let controlMask: UInt32 = 0x1000

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Build from an NSEvent's modifierFlags rawValue (Cocoa bits → Carbon mask).
    /// Cocoa: shift 1<<17 · control 1<<18 · option 1<<19 · command 1<<20.
    public init(keyCode: UInt32, cocoaModifierFlagsRaw raw: UInt) {
        var m: UInt32 = 0
        if raw & (1 << 20) != 0 { m |= Self.commandMask }
        if raw & (1 << 17) != 0 { m |= Self.shiftMask }
        if raw & (1 << 19) != 0 { m |= Self.optionMask }
        if raw & (1 << 18) != 0 { m |= Self.controlMask }
        self.init(keyCode: keyCode, modifiers: m)
    }

    /// Cocoa NSEvent.ModifierFlags rawValue for NSMenuItem display.
    public var cocoaModifierFlags: UInt {
        var f: UInt = 0
        if modifiers & Self.commandMask != 0 { f |= 1 << 20 }
        if modifiers & Self.shiftMask   != 0 { f |= 1 << 17 }
        if modifiers & Self.optionMask  != 0 { f |= 1 << 19 }
        if modifiers & Self.controlMask != 0 { f |= 1 << 18 }
        return f
    }

    /// Global hotkeys need ⌘, ⌥, or ⌃ — shift alone would shadow normal typing.
    public var isValid: Bool {
        modifiers & (Self.commandMask | Self.optionMask | Self.controlMask) != 0
    }

    /// "⌃⌥⇧⌘X" — standard macOS modifier glyph order.
    public var displayString: String {
        var s = ""
        if modifiers & Self.controlMask != 0 { s += "⌃" }
        if modifiers & Self.optionMask  != 0 { s += "⌥" }
        if modifiers & Self.shiftMask   != 0 { s += "⇧" }
        if modifiers & Self.commandMask != 0 { s += "⌘" }
        return s + Self.keyName(for: keyCode)
    }

    /// Key-cap name for a Carbon virtual key code; unknown codes fall back to "(key N)".
    public static func keyName(for code: UInt32) -> String {
        keyNames[code] ?? "(key \(code))"
    }

    /// NSMenuItem.keyEquivalent string ("" when the key has no menu representation).
    public var keyEquivalent: String { Self.keyEquivalents[keyCode] ?? "" }

    // MARK: - Persistence (string dictionary, matching CaptureSettings conventions)

    public var dictionary: [String: String] {
        ["keyCode": String(keyCode), "modifiers": String(modifiers)]
    }

    public init?(dictionary: [String: String]) {
        guard let kc = dictionary["keyCode"].flatMap(UInt32.init),
              let m = dictionary["modifiers"].flatMap(UInt32.init) else { return nil }
        self.init(keyCode: kc, modifiers: m)
    }

    // MARK: - Key tables (ANSI virtual key codes)

    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`",
        51: "⌫", 53: "Esc",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        114: "Help", 115: "Home", 116: "Page Up", 117: "⌦", 118: "F4", 119: "End",
        120: "F2", 121: "Page Down", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Lowercase characters for NSMenuItem.keyEquivalent. Function/arrow/etc. keys are
    /// omitted on purpose — menus simply show no shortcut for those.
    private static let keyEquivalents: [UInt32: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
        11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 49: " ", 50: "`",
    ]
}
```

- [ ] **Step 4: Run tests, verify all pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: `PASS — CaptureKitTests: N/N test(s) passed, 0 failure(s)` including the six new `hotkeyCombo*` cases.

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): HotkeyCombo — pure hotkey model (display, validity, persistence)"
```

---

### Task 2: `HotkeyAction` + `HotkeyBindings` (CaptureKit, TDD)

**Files:**
- Create: `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift`
- Create: `Packages/CaptureKit/Sources/CaptureKit/HotkeyBindings.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Packages/CaptureKit/Tests/CaptureKitTests/HotkeyTests.swift`:

```swift
let hotkeyBindingsTests: [TestCase] = [
    TestCase("defaultsTable") { t in
        let b = HotkeyBindings.defaults
        t.equal(b.combo(for: .captureArea), HotkeyCombo(keyCode: 21, modifiers: cmdShift))       // ⌘⇧4
        t.equal(b.combo(for: .captureWindow), HotkeyCombo(keyCode: 28, modifiers: cmdShift))     // ⌘⇧8
        t.equal(b.combo(for: .captureFullscreen), HotkeyCombo(keyCode: 22, modifiers: cmdShift)) // ⌘⇧6
        t.equal(b.combo(for: .captureText), HotkeyCombo(keyCode: 26, modifiers: cmdShift))       // ⌘⇧7
        t.isNil(b.combo(for: .pinFromClipboard))
        // ⌘⇧5 (keyCode 23) is reserved for recording — nothing may default to it.
        for action in HotkeyAction.allCases {
            t.isTrue(b.combo(for: action) != HotkeyCombo(keyCode: 23, modifiers: cmdShift),
                     "\(action) must not default to ⌘⇧5")
        }
    },
    TestCase("titles") { t in
        t.equal(HotkeyAction.captureArea.title, "Capture Area")
        t.equal(HotkeyAction.captureWindow.title, "Capture Window")
        t.equal(HotkeyAction.captureFullscreen.title, "Capture Fullscreen")
        t.equal(HotkeyAction.captureText.title, "Capture Text")
        t.equal(HotkeyAction.pinFromClipboard.title, "Pin from Clipboard")
    },
    TestCase("setClearAndBoundOrder") { t in
        var b = HotkeyBindings.defaults
        b.clear(.captureArea)
        t.isNil(b.combo(for: .captureArea))
        let combo = HotkeyCombo(keyCode: 35, modifiers: cmdShift) // ⌘⇧P
        b.set(combo, for: .pinFromClipboard)
        t.equal(b.combo(for: .pinFromClipboard), combo)
        // bound lists pairs in HotkeyAction.allCases order.
        t.equal(b.bound.map(\.action), [.captureWindow, .captureFullscreen, .captureText, .pinFromClipboard])
    },
    TestCase("conflictDetection") { t in
        let b = HotkeyBindings.defaults
        let area = HotkeyCombo(keyCode: 21, modifiers: cmdShift)
        // ⌘⇧4 belongs to captureArea → conflict when binding it to another action…
        t.equal(b.conflictingAction(for: area, excluding: .captureText), .captureArea)
        // …but re-typing an action's own combo is not a conflict.
        t.isNil(b.conflictingAction(for: area, excluding: .captureArea))
        t.isNil(b.conflictingAction(for: HotkeyCombo(keyCode: 23, modifiers: cmdShift),
                                    excluding: .captureArea))
    },
    TestCase("bindingsDictionaryRoundTrip") { t in
        var b = HotkeyBindings.defaults
        b.clear(.captureFullscreen)
        b.set(HotkeyCombo(keyCode: 35, modifiers: cmdShift), for: .pinFromClipboard)
        let restored = HotkeyBindings(dictionary: b.dictionary)
        t.equal(restored, b)
        // Unknown action keys and malformed values are skipped, not fatal.
        let messy = HotkeyBindings(dictionary: ["nonsense": "1,2", "captureArea": "garbage",
                                                "captureText": "26,768"])
        t.isNil(messy.combo(for: .captureArea))
        t.equal(messy.combo(for: .captureText), HotkeyCombo(keyCode: 26, modifiers: 768))
    },
]
```

In `main.swift`, add `hotkeyBindingsTests +` after `hotkeyComboTests +`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: build error — `HotkeyAction`/`HotkeyBindings` not defined.

- [ ] **Step 3: Implement both types**

Create `Packages/CaptureKit/Sources/CaptureKit/HotkeyAction.swift`:

```swift
import Foundation

/// Every user-bindable action. Raw values are the persistence keys — don't rename.
public enum HotkeyAction: String, CaseIterable, Hashable {
    case captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard

    public var title: String {
        switch self {
        case .captureArea: return "Capture Area"
        case .captureWindow: return "Capture Window"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureText: return "Capture Text"
        case .pinFromClipboard: return "Pin from Clipboard"
        }
    }

    /// Defaults: ⌘⇧4 area · ⌘⇧6 fullscreen · ⌘⇧7 text · ⌘⇧8 window · pin unbound.
    /// ⌘⇧5 (keyCode 23) is intentionally unassigned — reserved as the future default
    /// for Start/Stop Recording (P2).
    public var defaultCombo: HotkeyCombo? {
        let cmdShift = HotkeyCombo.commandMask | HotkeyCombo.shiftMask
        switch self {
        case .captureArea:       return HotkeyCombo(keyCode: 21, modifiers: cmdShift) // ⌘⇧4
        case .captureWindow:     return HotkeyCombo(keyCode: 28, modifiers: cmdShift) // ⌘⇧8
        case .captureFullscreen: return HotkeyCombo(keyCode: 22, modifiers: cmdShift) // ⌘⇧6
        case .captureText:       return HotkeyCombo(keyCode: 26, modifiers: cmdShift) // ⌘⇧7
        case .pinFromClipboard:  return nil
        }
    }
}
```

Create `Packages/CaptureKit/Sources/CaptureKit/HotkeyBindings.swift`:

```swift
import Foundation

/// The user's action → hotkey map. Pure model; persisted as a string dictionary
/// (action rawValue → "keyCode,modifiers") following CaptureSettings conventions.
/// A missing key means "unbound" — clearing a binding really removes it.
public struct HotkeyBindings: Equatable {
    private var map: [HotkeyAction: HotkeyCombo]

    public init(_ map: [HotkeyAction: HotkeyCombo] = [:]) { self.map = map }

    public static let defaults: HotkeyBindings = {
        var m: [HotkeyAction: HotkeyCombo] = [:]
        for action in HotkeyAction.allCases { m[action] = action.defaultCombo }
        return HotkeyBindings(m)
    }()

    public func combo(for action: HotkeyAction) -> HotkeyCombo? { map[action] }

    public mutating func set(_ combo: HotkeyCombo, for action: HotkeyAction) {
        map[action] = combo
    }

    public mutating func clear(_ action: HotkeyAction) {
        map[action] = nil
    }

    /// The *other* action already bound to `combo`, if any.
    public func conflictingAction(for combo: HotkeyCombo,
                                  excluding action: HotkeyAction) -> HotkeyAction? {
        map.first { $0.key != action && $0.value == combo }?.key
    }

    /// All bound pairs in stable HotkeyAction.allCases order.
    public var bound: [(action: HotkeyAction, combo: HotkeyCombo)] {
        HotkeyAction.allCases.compactMap { a in map[a].map { (a, $0) } }
    }

    // MARK: - Persistence

    public var dictionary: [String: String] {
        var d: [String: String] = [:]
        for (action, combo) in map {
            d[action.rawValue] = "\(combo.keyCode),\(combo.modifiers)"
        }
        return d
    }

    public init(dictionary: [String: String]) {
        var m: [HotkeyAction: HotkeyCombo] = [:]
        for (key, value) in dictionary {
            guard let action = HotkeyAction(rawValue: key) else { continue }
            let parts = value.split(separator: ",")
            guard parts.count == 2,
                  let kc = UInt32(parts[0]), let mods = UInt32(parts[1]) else { continue }
            m[action] = HotkeyCombo(keyCode: kc, modifiers: mods)
        }
        self.map = m
    }
}
```

- [ ] **Step 4: Run tests, verify all pass**

Run: `swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: PASS, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add Packages/CaptureKit
git commit -m "feat(capture): HotkeyAction + HotkeyBindings — defaults, conflicts, persistence"
```

---

### Task 3: AppKit lifecycle + `SettingsWindowController` (the settings fix)

The SwiftUI `App` existed only to provide the `Settings` scene, and the private
`showSettingsWindow:` selector that opens it no-ops on macOS 14 in LSUIElement apps.
Replace both with a window we own. No pure logic here — verification is `swift build`
plus the manual checklist at the end of the plan.

**Files:**
- Create: `App/main.swift`
- Create: `App/AppDelegate.swift`
- Create: `App/SettingsWindowController.swift`
- Delete: `App/BetterScreenshotApp.swift`
- Modify: `App/MenuBarController.swift` (init + `openSettings`)

- [ ] **Step 1: Create the AppKit entry point**

Create `App/main.swift`:

```swift
import AppKit

// Plain AppKit lifecycle. The SwiftUI App existed only for its Settings scene,
// whose opener (private showSettingsWindow: selector) macOS 14 broke for
// LSUIElement apps — SettingsWindowController owns the window instead.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
```

- [ ] **Step 2: Move AppDelegate into its own file**

Create `App/AppDelegate.swift` with the `AppDelegate` class **copied verbatim from
`App/BetterScreenshotApp.swift`** (everything except the `BetterScreenshotApp` struct),
with three changes — the imports, the `settingsWindow` property, and `menuBar` wiring:

```swift
import AppKit
import SwiftUI
import CaptureKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    private var coordinator: CaptureCoordinator!
    private var menuBar: MenuBarController!
    private var onboarding: OnboardingController!
    private var settingsWindow: SettingsWindowController!
    private let hotKeys = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        coordinator = CaptureCoordinator(settings: settings)
        coordinator.editorPresenter = { [weak coordinator] image in
            coordinator?.presentEditor(image)
        }
        settingsWindow = SettingsWindowController(store: settings)
        menuBar = MenuBarController(coordinator: coordinator, settingsWindow: settingsWindow)

        // One-button first-run setup (Screen Recording is the only permission).
        onboarding = OnboardingController()
        coordinator.presentSetup = { [weak self] in self?.onboarding.show(.needsPermission) }
        if !PermissionManager.hasScreenRecordingPermission {
            onboarding.show(.needsPermission)
        } else if OnboardingController.consumeRelaunchFlag() {
            onboarding.show(.allSet)   // just relaunched after the grant
        }
        // Register as a login item once, by default. One-time so we never
        // fight a user who later disables it (Settings or System Settings).
        if !UserDefaults.standard.bool(forKey: "didRegisterLaunchAtLogin") {
            LaunchAtLogin.setEnabled(true)
            UserDefaults.standard.set(true, forKey: "didRegisterLaunchAtLogin")
        }
        // Defaults: ⌘⇧4 area, ⌘⇧5 window, ⌘⇧6 fullscreen, ⌘⇧7 capture text.
        hotKeys.register(key: "4", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureArea() }
        }
        hotKeys.register(key: "5", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFrontWindow() }
        }
        hotKeys.register(key: "6", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureFullscreen() }
        }
        hotKeys.register(key: "7", command: true, shift: true, option: false, control: false) {
            [weak self] in Task { @MainActor in self?.coordinator.captureText() }
        }
        // Stop macOS's native ⌘⇧4 from also firing (double screenshot). Restored on quit.
        SystemScreenshotShortcuts.disableNativeAreaScreenshot()
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemScreenshotShortcuts.restoreNativeAreaScreenshot()
    }
}
```

(The four `hotKeys.register` calls are still the old hard-coded ones here — Task 4
replaces them with the bindings table. This task is only the lifecycle + window fix.)

Delete `App/BetterScreenshotApp.swift`.

- [ ] **Step 3: Create SettingsWindowController**

Create `App/SettingsWindowController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the single Settings window. Replaces the SwiftUI `Settings` scene, whose
/// private `showSettingsWindow:` opener silently broke on macOS 14 for
/// LSUIElement apps.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(store: store))
            let w = NSWindow(contentViewController: hosting)
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: Route the menu item to it**

In `App/MenuBarController.swift`:

Replace the init and the `openSettings` method:

```swift
    private let settingsWindow: SettingsWindowController

    init(coordinator: CaptureCoordinator, settingsWindow: SettingsWindowController) {
        self.coordinator = coordinator
        self.settingsWindow = settingsWindow
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "camera.viewfinder",
                                           accessibilityDescription: "BetterScreenshot")
        buildMenu()
    }
```

```swift
    @objc private func openSettings() { settingsWindow.show() }
```

- [ ] **Step 5: Build and verify**

Run: `swift build`
Expected: `Build complete!` (no errors; warnings about unused `key:` register API are fine and disappear in Task 4).

- [ ] **Step 6: Commit**

```bash
git add -A App
git commit -m "fix(app): own the Settings window — macOS 14 broke showSettingsWindow: for LSUIElement apps"
```

---

### Task 4: Table-driven hotkeys — `HotKeyManager.apply` + store + menu equivalents

**Files:**
- Modify: `App/HotKeyManager.swift` (replace `register(key:...)` with `apply`/`suspend`/`resume`)
- Modify: `App/SettingsStore.swift` (persist bindings, publish failures)
- Modify: `App/AppDelegate.swift` (bindings table replaces hard-coded registrations)
- Modify: `App/MenuBarController.swift` (key equivalents)
- Delete: `Packages/CaptureKit/Sources/CaptureKit/KeyCombo.swift` (orphaned)
- Delete: `Packages/CaptureKit/Tests/CaptureKitTests/KeyCodeTests.swift` (orphaned)
- Modify: `Packages/CaptureKit/Tests/CaptureKitTests/main.swift` (drop `keyCodeTests +`)

- [ ] **Step 1: Rewrite HotKeyManager around bindings**

Replace the whole body of `App/HotKeyManager.swift` with:

```swift
import Carbon
import CaptureKit

final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1
    private var current: (bindings: HotkeyBindings, handlers: [HotkeyAction: () -> Void])?

    init() { installHandler() }

    /// (Re-)register every bound combo. Returns the actions whose registration was
    /// refused by macOS (combo owned by another app or the system).
    @discardableResult
    func apply(_ bindings: HotkeyBindings,
               handlers: [HotkeyAction: () -> Void]) -> Set<HotkeyAction> {
        current = (bindings, handlers)
        unregisterAll()
        var failed: Set<HotkeyAction> = []
        for (action, combo) in bindings.bound {
            guard let handler = handlers[action] else { continue }
            if !register(combo, action: handler) { failed.insert(action) }
        }
        return failed
    }

    /// Release every hotkey so a recorder well can re-type currently-bound combos.
    func suspend() { unregisterAll() }

    /// Re-register whatever `apply` last installed.
    @discardableResult
    func resume() -> Set<HotkeyAction> {
        guard let current else { return [] }
        return apply(current.bindings, handlers: current.handlers)
    }

    private func register(_ combo: HotkeyCombo, action: @escaping () -> Void) -> Bool {
        let id = EventHotKeyID(signature: OSType(0x42535343 /* 'BSSC' */), id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id,
                                         GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return false }
        actions[nextID] = action
        hotKeyRefs.append(ref)
        nextID += 1
        return true
    }

    private func unregisterAll() {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotKeyRefs.removeAll()
        actions.removeAll()
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: OSType(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let mgr = Unmanaged<HotKeyManager>.fromOpaque(userData!).takeUnretainedValue()
            mgr.actions[hkID.id]?()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
    }
}
```

- [ ] **Step 2: Persist bindings in SettingsStore**

In `App/SettingsStore.swift`, add two published properties and persistence. After
`@Published var saveDirectory: URL` add:

```swift
    @Published var bindings: HotkeyBindings
    /// Actions whose combo macOS refused to register (not persisted).
    @Published var failedActions: Set<HotkeyAction> = []
```

In `init()`, after the `saveDirectory` assignment block, add:

```swift
        if let dict = defaults.dictionary(forKey: "hotkeyBindings") as? [String: String] {
            self.bindings = HotkeyBindings(dictionary: dict)
        } else {
            self.bindings = .defaults
        }
```

(Note: Swift requires all stored properties initialized before `self` is used —
place the `bindings` assignment **before** the existing
`self.saveDirectory = SettingsStore.systemScreenshotLocation()` if-else, or after it;
either is fine as long as it precedes any method call.)

In `persist()` add:

```swift
        defaults.set(bindings.dictionary, forKey: "hotkeyBindings")
```

- [ ] **Step 3: Drive registration from the store in AppDelegate**

In `App/AppDelegate.swift`, replace the four `hotKeys.register(...)` calls (and the
"Defaults: ⌘⇧4 area…" comment above them) with:

```swift
        applyBindings()
```

Add these methods to `AppDelegate`:

```swift
    /// Register every bound hotkey; record failures and refresh menu shortcuts.
    @discardableResult
    private func applyBindings() -> Set<HotkeyAction> {
        let handlers: [HotkeyAction: () -> Void] = [
            .captureArea:      { [weak self] in Task { @MainActor in self?.coordinator.captureArea() } },
            .captureWindow:    { [weak self] in Task { @MainActor in self?.coordinator.captureFrontWindow() } },
            .captureFullscreen:{ [weak self] in Task { @MainActor in self?.coordinator.captureFullscreen() } },
            .captureText:      { [weak self] in Task { @MainActor in self?.coordinator.captureText() } },
            .pinFromClipboard: { [weak self] in Task { @MainActor in self?.coordinator.pinFromClipboard() } },
        ]
        let failed = hotKeys.apply(settings.bindings, handlers: handlers)
        settings.failedActions = failed
        menuBar.refreshKeyEquivalents(settings.bindings)
        return failed
    }

    /// Rebind transaction for the Shortcuts tab: validate, apply, revert on failure.
    /// Returns a user-facing error message, or nil on success.
    func updateBinding(_ combo: HotkeyCombo?, for action: HotkeyAction) -> String? {
        var candidate = settings.bindings
        if let combo {
            if let other = candidate.conflictingAction(for: combo, excluding: action) {
                return "Already used by \(other.title)"
            }
            candidate.set(combo, for: action)
        } else {
            candidate.clear(action)
        }
        let previous = settings.bindings
        settings.bindings = candidate
        let failed = applyBindings()
        if let _ = combo, failed.contains(action) {
            settings.bindings = previous
            applyBindings()
            return "That shortcut is in use by another app or macOS."
        }
        settings.persist()
        return nil
    }

    func restoreDefaultBindings() {
        settings.bindings = .defaults
        applyBindings()
        settings.persist()
    }
```

`applyBindings()` must run **after** `menuBar` is created (it already is — the
`applyBindings()` call replaces the registers, which sat after menu creation).

- [ ] **Step 4: Show shortcuts in the menu**

In `App/MenuBarController.swift`, keep references to the action items. Replace
`buildMenu()` with:

```swift
    private var actionItems: [HotkeyAction: NSMenuItem] = [:]

    private func buildMenu() {
        let menu = NSMenu()
        func add(_ title: String, _ sel: Selector, _ action: HotkeyAction?) {
            let item = menu.addItem(withTitle: title, action: sel, keyEquivalent: "")
            item.target = self
            if let action { actionItems[action] = item }
        }
        add("Capture Area", #selector(area), .captureArea)
        add("Capture Window", #selector(window), .captureWindow)
        add("Capture Fullscreen", #selector(full), .captureFullscreen)
        add("Capture Text", #selector(captureText), .captureText)
        menu.addItem(.separator())
        add("Pin from Clipboard", #selector(pinClipboard), .pinFromClipboard)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    /// Display-only: firing stays Carbon. Menus just show the current combos.
    func refreshKeyEquivalents(_ bindings: HotkeyBindings) {
        for (action, item) in actionItems {
            if let combo = bindings.combo(for: action) {
                item.keyEquivalent = combo.keyEquivalent
                item.keyEquivalentModifierMask = NSEvent.ModifierFlags(rawValue: combo.cocoaModifierFlags)
            } else {
                item.keyEquivalent = ""
                item.keyEquivalentModifierMask = []
            }
        }
    }
```

Add `import CaptureKit` at the top of the file (for `HotkeyAction`/`HotkeyBindings`).

- [ ] **Step 5: Delete the superseded KeyCombo**

```bash
git rm Packages/CaptureKit/Sources/CaptureKit/KeyCombo.swift \
       Packages/CaptureKit/Tests/CaptureKitTests/KeyCodeTests.swift
```

In `Packages/CaptureKit/Tests/CaptureKitTests/main.swift`, remove the `keyCodeTests +` line.

- [ ] **Step 6: Build + test**

Run: `swift build && swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: `Build complete!`, then PASS with 0 failures (and no `keyCodeTests` in the list).

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat(app): table-driven hotkeys — live apply/rebind, persisted bindings, menu shortcuts (window capture ⌘⇧5→⌘⇧8, ⌘⇧5 reserved for recording)"
```

---

### Task 5: Shortcuts tab — recorder field + wiring

**Files:**
- Create: `App/ShortcutRecorderField.swift`
- Modify: `App/SettingsView.swift` (TabView: General | Shortcuts)
- Modify: `App/SettingsWindowController.swift` (inject shortcut closures)
- Modify: `App/AppDelegate.swift` (build `ShortcutActions`)

- [ ] **Step 1: Create the recorder field**

Create `App/ShortcutRecorderField.swift`:

```swift
import AppKit
import SwiftUI
import CaptureKit

/// Click-to-record shortcut well. Active state captures the next keypress with a
/// local NSEvent monitor: a combo containing ⌘/⌥/⌃ is reported, Esc cancels,
/// ⌫ clears the binding. Events are swallowed while recording.
struct ShortcutRecorderField: NSViewRepresentable {
    var combo: HotkeyCombo?
    @Binding var isRecording: Bool
    /// nil = clear the binding (⌫ pressed while recording).
    var onCombo: (HotkeyCombo?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> RecorderWell {
        let well = RecorderWell()
        well.onClick = { context.coordinator.toggle() }
        return well
    }

    func updateNSView(_ well: RecorderWell, context: Context) {
        context.coordinator.parent = self
        well.label = isRecording ? "Type shortcut…" : (combo?.displayString ?? "—")
        well.active = isRecording
        context.coordinator.setMonitoring(isRecording, window: well.window)
    }

    @MainActor
    final class Coordinator {
        var parent: ShortcutRecorderField
        private var monitor: Any?
        private var closeObserver: NSObjectProtocol?

        init(_ parent: ShortcutRecorderField) { self.parent = parent }

        func toggle() { parent.isRecording.toggle() }

        func setMonitoring(_ on: Bool, window: NSWindow?) {
            if on, monitor == nil {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    self?.handle(event)
                    return nil   // swallow every keypress while recording
                }
                if let window {
                    closeObserver = NotificationCenter.default.addObserver(
                        forName: NSWindow.willCloseNotification, object: window, queue: .main
                    ) { [weak self] _ in
                        Task { @MainActor in self?.parent.isRecording = false }
                    }
                }
            } else if !on, monitor != nil {
                stopMonitoring()
            }
        }

        private func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
            closeObserver = nil
        }

        private func handle(_ event: NSEvent) {
            let plain = event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty
            if event.keyCode == 53, plain {            // Esc — cancel
                parent.isRecording = false
                return
            }
            if event.keyCode == 51, plain {            // ⌫ — clear binding
                parent.isRecording = false
                parent.onCombo(nil)
                return
            }
            let combo = HotkeyCombo(keyCode: UInt32(event.keyCode),
                                    cocoaModifierFlagsRaw: UInt(event.modifierFlags.rawValue))
            guard combo.isValid else { return }        // keep waiting for ⌘/⌥/⌃
            // Ignore bare modifier presses (keyDown only fires for real keys, so
            // nothing needed) and report the combo.
            parent.isRecording = false
            parent.onCombo(combo)
        }
    }
}

/// The visual well: rounded rect + centered label; click reports to the field.
final class RecorderWell: NSView {
    var onClick: (() -> Void)?
    var label: String = "—" { didSet { needsDisplay = true } }
    var active: Bool = false { didSet { needsDisplay = true } }

    override var intrinsicContentSize: NSSize { NSSize(width: 130, height: 22) }

    override func mouseDown(with event: NSEvent) { onClick?() }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5),
                             xRadius: 5, yRadius: 5)
        (active ? NSColor.controlAccentColor.withAlphaComponent(0.15)
                : NSColor.controlBackgroundColor).setFill()
        r.fill()
        (active ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        r.stroke()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
            .foregroundColor: active ? NSColor.controlAccentColor : NSColor.labelColor,
        ]
        let size = label.size(withAttributes: attrs)
        label.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
                               y: (bounds.height - size.height) / 2), withAttributes: attrs)
    }
}
```

- [ ] **Step 2: Restructure SettingsView into tabs**

Replace `App/SettingsView.swift` entirely with:

```swift
import SwiftUI
import CaptureKit

/// Closures the Shortcuts tab needs from the app layer (AppDelegate owns the
/// rebind transaction because it touches HotKeyManager + menu + persistence).
struct ShortcutActions {
    /// Bind combo (nil = clear) to action. Returns an error message, or nil on success.
    var update: (HotkeyCombo?, HotkeyAction) -> String?
    var restoreDefaults: () -> Void
    /// true while a recorder well is active → suspend all hotkeys.
    var recordingChanged: (Bool) -> Void
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    let shortcuts: ShortcutActions

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(store: store, actions: shortcuts)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 480)
        .padding(20)
    }
}

private struct GeneralTab: View {
    @ObservedObject var store: SettingsStore
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    guard newValue != LaunchAtLogin.isEnabled else { return }
                    LaunchAtLogin.setEnabled(newValue)
                    launchAtLogin = LaunchAtLogin.isEnabled  // revert if it failed
                }
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
            HStack {
                Text("Save to: \(store.saveDirectory.path)")
                    .truncationMode(.middle).lineLimit(1)
                Spacer()
                Button("Change…") { chooseFolder() }
            }
        }
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
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

private struct ShortcutsTab: View {
    @ObservedObject var store: SettingsStore
    let actions: ShortcutActions
    @State private var status = ""
    @State private var recordingAction: HotkeyAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(HotkeyAction.allCases, id: \.self) { action in
                HStack {
                    Text(action.title)
                    if store.failedActions.contains(action) {
                        Text("couldn't register")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Spacer()
                    ShortcutRecorderField(
                        combo: store.bindings.combo(for: action),
                        isRecording: Binding(
                            get: { recordingAction == action },
                            set: { setRecording($0 ? action : nil) }),
                        onCombo: { combo in
                            status = actions.update(combo, action) ?? ""
                        })
                        .frame(width: 130, height: 22)
                    Button {
                        status = actions.update(nil, action) ?? ""
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .disabled(store.bindings.combo(for: action) == nil)
                        .help("Remove shortcut")
                }
            }
            Divider().padding(.vertical, 4)
            Text("⌘⇧5 is reserved for Start/Stop Recording (coming soon).")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Restore Defaults") {
                    actions.restoreDefaults()
                    status = ""
                }
                Spacer()
                Text(status).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { setRecording(nil) }
    }

    /// Tracks which row is recording; suspends/resumes hotkeys on transitions.
    private func setRecording(_ action: HotkeyAction?) {
        let wasRecording = recordingAction != nil
        recordingAction = action
        let isRecording = action != nil
        if wasRecording != isRecording { actions.recordingChanged(isRecording) }
    }
}
```

- [ ] **Step 3: Thread ShortcutActions through SettingsWindowController**

Replace the `store` property/init/`show()` body in `App/SettingsWindowController.swift`:

```swift
    private var window: NSWindow?
    private let store: SettingsStore
    private let shortcuts: ShortcutActions

    init(store: SettingsStore, shortcuts: ShortcutActions) {
        self.store = store
        self.shortcuts = shortcuts
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if window == nil {
            let view = SettingsView(store: store, shortcuts: shortcuts)
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.title = "Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
    }
```

- [ ] **Step 4: Build ShortcutActions in AppDelegate**

In `App/AppDelegate.swift`, replace the `settingsWindow = SettingsWindowController(store: settings)` line with:

```swift
        let shortcuts = ShortcutActions(
            update: { [weak self] combo, action in self?.updateBinding(combo, for: action) },
            restoreDefaults: { [weak self] in self?.restoreDefaultBindings() },
            recordingChanged: { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.hotKeys.suspend()
                } else {
                    self.settings.failedActions = self.hotKeys.resume()
                }
            })
        settingsWindow = SettingsWindowController(store: settings, shortcuts: shortcuts)
```

- [ ] **Step 5: Build + test**

Run: `swift build && swift run --package-path Packages/CaptureKit CaptureKitTests`
Expected: `Build complete!`, PASS with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add -A App
git commit -m "feat(app): Shortcuts settings tab — click-to-record wells, conflict refusal, live rebinding"
```

---

### Task 6: Full verification, CHANGELOG, tag

- [ ] **Step 1: Run every test suite + build the app bundle**

```bash
swift run --package-path Packages/CaptureKit CaptureKitTests
swift run --package-path Packages/OverlayKit OverlayKitTests
swift run --package-path Packages/EditorKit EditorKitTests
scripts/build-app.sh
```

Expected: three `PASS` lines, then `==> Built dist/BetterScreenshot.app …`.

- [ ] **Step 2: CHANGELOG entry**

Add at the top of `CHANGELOG.md` (below any title line, matching the existing entry style):

```markdown
## v1.4-shortcuts — 2026-06-04

- **Fixed: the Settings window now opens.** macOS 14 silently broke the private
  selector the menu item relied on; the app now owns its settings window directly.
- **Customizable shortcuts.** New Settings → Shortcuts tab: click a shortcut well,
  type a new combo, it applies immediately and persists. Conflicts inside the app
  and combos owned by other apps/macOS are refused with an explanation.
- **New defaults:** Capture Window moved ⌘⇧5 → **⌘⇧8**; **⌘⇧5 is now reserved for
  Start/Stop Recording** (next release). Pin from Clipboard can be given a shortcut
  (unbound by default). Menu-bar items now display their current shortcuts.
```

- [ ] **Step 3: Update the spec status line**

In `docs/superpowers/specs/2026-06-04-betterscreenshot-settings-keybinds-design.md`,
change `Status: draft` to `Status: **shipped 2026-06-04** (tag \`v1.4-shortcuts\`)`.

- [ ] **Step 4: Commit + tag**

```bash
git add CHANGELOG.md docs/superpowers/specs/2026-06-04-betterscreenshot-settings-keybinds-design.md
git commit -m "docs: CHANGELOG + shipped status for v1.4-shortcuts"
git tag v1.4-shortcuts
```

- [ ] **Step 5: Manual GUI checklist (human or post-ship verification)**

Launch `dist/BetterScreenshot.app` and verify:

1. Menu bar → Settings… **opens the window** (the original bug).
2. General and Shortcuts tabs both render; General controls all still work.
3. ⌘⇧8 captures a window; ⌘⇧5 does nothing.
4. Rebind Capture Area to ⌘⇧9 via the recorder well → fires immediately, menu shows ⌘⇧9.
5. While a well is active ("Type shortcut…"), pressing ⌘⇧4 types into the well instead of capturing.
6. Esc cancels recording; ⌫ in an active well clears the binding; ✕ clears too.
7. Binding a combo already used in-app shows "Already used by …" and keeps the old binding.
8. Quit + relaunch → custom bindings survive; Restore Defaults brings back the table above.
```
