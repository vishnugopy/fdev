import Carbon.HIToolbox

/// Global hotkeys via Carbon — no Accessibility permission needed for the keys themselves.
/// Supports press and release, so a shortcut can be held (the action wheel uses this).
final class HotKey {
    static let shared = HotKey()
    private var pressHandlers: [UInt32: () -> Void] = [:]
    private var releaseHandlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var installed = false
    /// Last hotkey event received: (id, pressed?, time) — shown live in Settings.
    var onEvent: ((UInt32, Bool) -> Void)?
    func isRegistered(_ id: UInt32) -> Bool { refs[id] != nil }

    /// - Parameters: `key` is a kVK_* code, `modifiers` a Carbon mask (cmdKey | optionKey …).
    @discardableResult
    func register(id: UInt32, key: Int, modifiers: Int,
                  onPress: @escaping () -> Void, onRelease: (() -> Void)? = nil) -> Bool {
        unregister(id: id)
        installIfNeeded()
        pressHandlers[id] = onPress
        releaseHandlers[id] = onRelease
        var ref: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x46444556), id: id) // 'FDEV'
        guard RegisterEventHotKey(UInt32(key), UInt32(modifiers), hkID, GetApplicationEventTarget(), 0, &ref) == noErr,
              let ref else { return false }
        refs[id] = ref
        return true
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
        pressHandlers[id] = nil
        releaseHandlers[id] = nil
    }

    func unregisterAll() {
        for id in Array(refs.keys) { unregister(id: id) }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            HotKey.shared.onEvent?(hk.id, pressed)
            if pressed {
                HotKey.shared.pressHandlers[hk.id]?()
            } else {
                HotKey.shared.releaseHandlers[hk.id]?()
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
