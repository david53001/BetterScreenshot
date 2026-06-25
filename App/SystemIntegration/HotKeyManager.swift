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
