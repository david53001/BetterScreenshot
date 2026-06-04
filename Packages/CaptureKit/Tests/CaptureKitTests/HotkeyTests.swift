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
