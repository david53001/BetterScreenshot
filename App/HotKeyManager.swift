import Carbon
import CaptureKit

final class HotKeyManager {
    private var handlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var nextID: UInt32 = 1

    init() { installHandler() }

    /// Register a combo; returns false if registration fails (e.g. already taken).
    @discardableResult
    func register(key: Character, command: Bool, shift: Bool,
                  option: Bool, control: Bool, action: @escaping () -> Void) -> Bool {
        guard let code = KeyCombo.carbonKeyCode(for: key) else { return false }
        let mods = KeyCombo.carbonModifiers(command: command, shift: shift,
                                            option: option, control: control)
        let id = EventHotKeyID(signature: OSType(0x42535343 /* 'BSSC' */), id: nextID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, mods, id, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return false }
        actions[nextID] = action
        hotKeyRefs.append(ref)
        nextID += 1
        return true
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
