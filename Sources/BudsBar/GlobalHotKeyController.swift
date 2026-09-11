import Carbon.HIToolbox
import Foundation

final class GlobalHotKeyController {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var definition: HotKeyDefinition?
    var onPress: (() -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.onPress?()
            return noErr
        }, 1, &spec, userData, &handler)
    }

    deinit {
        clear()
        if let handler { RemoveEventHandler(handler) }
    }

    @discardableResult
    func replace(with definition: HotKeyDefinition?) -> Bool {
        if let definition, !definition.isValid { return false }
        let previous = self.definition
        clear()
        guard let definition else { self.definition = nil; return true }
        var registered: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x5142484B, id: 1)
        let status = RegisterEventHotKey(
            definition.keyCode, definition.modifiers, id,
            GetApplicationEventTarget(), 0, &registered)
        guard status == noErr, let registered else {
            if let previous { _ = register(previous) }
            return false
        }
        hotKey = registered
        self.definition = definition
        return true
    }

    private func register(_ definition: HotKeyDefinition) -> Bool {
        var registered: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x5142484B, id: 1)
        guard RegisterEventHotKey(definition.keyCode, definition.modifiers, id,
                                  GetApplicationEventTarget(), 0, &registered) == noErr,
              let registered else { return false }
        hotKey = registered
        self.definition = definition
        return true
    }

    private func clear() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
        definition = nil
    }
}
