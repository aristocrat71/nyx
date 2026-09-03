import AppKit
import Carbon.HIToolbox

final class HotkeyManager {
    var onHotkey: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func register(_ spec: HotkeySpec) {
        unregister()
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { manager.onHotkey?() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &eventHandlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E59_5831), id: 1)
        let status = RegisterEventHotKey(
            spec.keyCode, spec.carbonModifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef
        )
        if status == noErr {
            Log.ui.debug("hotkey registered")
        } else {
            Log.ui.error("hotkey registration failed (\(status, privacy: .public))")
        }
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        hotKeyRef = nil
        eventHandlerRef = nil
    }
}
