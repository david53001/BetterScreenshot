import Foundation

/// Every user-bindable action. Raw values are the persistence keys — don't rename.
public enum HotkeyAction: String, CaseIterable, Hashable {
    case captureArea, captureWindow, captureFullscreen, captureText, pinFromClipboard, record

    public var title: String {
        switch self {
        case .captureArea:       return "Capture Area"
        case .captureWindow:     return "Capture Window"
        case .captureFullscreen: return "Capture Fullscreen"
        case .captureText:       return "Capture Text"
        case .pinFromClipboard:  return "Pin from Clipboard"
        case .record:            return "Start/Stop Recording"
        }
    }

    /// Defaults: ⌘⇧4 area · ⌘⇧6 fullscreen · ⌘⇧7 text · ⌘⇧8 window · pin unbound · ⌘⇧5 record.
    public var defaultCombo: HotkeyCombo? {
        let cmdShift = HotkeyCombo.commandMask | HotkeyCombo.shiftMask
        switch self {
        case .captureArea:       return HotkeyCombo(keyCode: 21, modifiers: cmdShift) // ⌘⇧4
        case .captureWindow:     return HotkeyCombo(keyCode: 28, modifiers: cmdShift) // ⌘⇧8
        case .captureFullscreen: return HotkeyCombo(keyCode: 22, modifiers: cmdShift) // ⌘⇧6
        case .captureText:       return HotkeyCombo(keyCode: 26, modifiers: cmdShift) // ⌘⇧7
        case .pinFromClipboard:  return nil
        case .record:            return HotkeyCombo(keyCode: 23, modifiers: cmdShift) // ⌘⇧5
        }
    }
}
