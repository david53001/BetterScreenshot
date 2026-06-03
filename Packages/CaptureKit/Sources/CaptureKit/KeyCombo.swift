import Foundation

public enum KeyCombo {
    /// Carbon virtual key codes for the small set of keys we bind by default.
    public static func carbonKeyCode(for key: Character) -> UInt32? {
        switch key {
        case "4": return 21
        case "5": return 23
        case "6": return 22
        case "7": return 26
        default: return nil
        }
    }

    /// Carbon modifier flags (cmdKey=0x0100, shiftKey=0x0200, optionKey=0x0800, controlKey=0x1000).
    public static func carbonModifiers(command: Bool, shift: Bool,
                                       option: Bool, control: Bool) -> UInt32 {
        var m: UInt32 = 0
        if command { m |= 0x0100 }
        if shift   { m |= 0x0200 }
        if option  { m |= 0x0800 }
        if control { m |= 0x1000 }
        return m
    }
}
