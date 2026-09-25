import Carbon
import Foundation

@MainActor
final class GlobalShortcutManager: ShortcutHandling {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    private var actions: [UInt32: () -> Void] = [:]

    func registerDefaultShortcuts() { }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        actions[id] = action
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), { _, event, data in
                guard let event, let data else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                let manager = Unmanaged<GlobalShortcutManager>.fromOpaque(data).takeUnretainedValue()
                MainActor.assumeIsolated { manager.actions[hotKeyID.id]?() }
                return noErr
            }, 1, &spec, pointer, &handler)
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4E425241), id: id)
        if RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref { refs.append(ref) }
    }

    func unregisterAll() {
        refs.forEach { _ = UnregisterEventHotKey($0) }
        refs.removeAll(); actions.removeAll()
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
}
