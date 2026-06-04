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
        t.equal(HotkeyCombo(keyCode: 21, modifiers: cmdShift).displayString, "⇧⌘4")
    },
    TestCase("displayStringKeyNames") { t in
        t.equal(HotkeyCombo(keyCode: 28, modifiers: cmdShift).displayString, "⇧⌘8")
        t.equal(HotkeyCombo(keyCode: 49, modifiers: cmdShift).displayString, "⇧⌘Space")
        t.equal(HotkeyCombo(keyCode: 122, modifiers: cmdShift).displayString, "⇧⌘F1")
        t.equal(HotkeyCombo(keyCode: 126, modifiers: cmdShift).displayString, "⇧⌘↑")
        t.equal(HotkeyCombo(keyCode: 0, modifiers: cmdShift).displayString, "⇧⌘A")
        // Unknown codes fall back instead of crashing or showing nothing.
        t.equal(HotkeyCombo(keyCode: 999, modifiers: cmdShift).displayString, "⇧⌘(key 999)")
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
