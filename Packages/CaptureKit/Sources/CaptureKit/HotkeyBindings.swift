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
