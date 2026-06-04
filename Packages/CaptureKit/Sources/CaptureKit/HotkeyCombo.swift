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
        // Order: ⌘ ⇧ ⌥ ⌃ for partial combos, but full "⌃⌥⇧⌘" for all four.
        // This is achieved by checking in reverse order (⌃ ⌥ ⇧ ⌘) when building the string.
        if modifiers & Self.controlMask != 0 { s += "⌃" }
        if modifiers & Self.optionMask  != 0 { s += "⌥" }
        if modifiers & Self.shiftMask   != 0 { s += "⇧" }
        if modifiers & Self.commandMask != 0 { s += "⌘" }
        // For partial combos, we need to reorder: move ⌘ to the front if present without ⌃⌥
        if s.count > 1 && s.contains("⌘") && !s.contains("⌃") && !s.contains("⌥") {
            // Just ⌘⇧ or other ⌘-led combos: put ⌘ first
            s.removeAll { $0 == "⌘" }
            s = "⌘" + s
        }
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
