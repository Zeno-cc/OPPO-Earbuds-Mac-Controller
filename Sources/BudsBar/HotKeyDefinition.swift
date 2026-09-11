import Carbon.HIToolbox
import Foundation

/// A global shortcut, stored as the raw Carbon key code and modifier mask.
///
/// The mask uses Carbon's own bit values because it is handed straight to
/// `RegisterEventHotKey`; the display string is always derived, never persisted, so a
/// keyboard-layout or language change cannot leave stale text behind.
struct HotKeyDefinition: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let command = UInt32(cmdKey)
    static let option = UInt32(optionKey)
    static let control = UInt32(controlKey)
    static let shift = UInt32(shiftKey)

    /// Shift alone is not a usable primary modifier: it would swallow ordinary typing.
    static let primaryModifiers = command | option | control

    var isValid: Bool { modifiers & Self.primaryModifiers != 0 }

    var displayText: String {
        var text = ""
        if modifiers & Self.control != 0 { text += "⌃" }
        if modifiers & Self.option != 0 { text += "⌥" }
        if modifiers & Self.shift != 0 { text += "⇧" }
        if modifiers & Self.command != 0 { text += "⌘" }
        return text + KeyCodeNaming.label(for: keyCode)
    }
}

enum KeyCodeNaming {
    static func label(for keyCode: UInt32) -> String {
        if let special = special[keyCode] { return special }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayout = TISGetInputSourceProperty(
                source, kTISPropertyUnicodeKeyLayoutData) else { return "Key \(keyCode)" }
        // `TISGetInputSourceProperty` hands back the property value itself: for this key that
        // is a `CFData` holding the layout, not the layout bytes, so it has to be unwrapped
        // before `UCKeyTranslate` can read it.
        let layoutData = Unmanaged<CFData>.fromOpaque(rawLayout).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(layoutData) else { return "Key \(keyCode)" }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = UCKeyTranslate(
            layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState, characters.count, &length, &characters)
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    /// Keys whose name is not the character they would type.
    private static let special: [UInt32: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 71: "⌧", 76: "⌤",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        109: "F10", 111: "F12", 115: "↖", 116: "⇞", 117: "⌦", 118: "F4",
        119: "↘", 120: "F2", 121: "⇟", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

struct HotKeyStore {
    private let defaults: UserDefaults
    private let keyCodeKey = "quickNoiseHotKeyCode"
    private let modifiersKey = "quickNoiseHotKeyModifiers"

    init(defaults: UserDefaults) { self.defaults = defaults }

    var definition: HotKeyDefinition? {
        guard defaults.object(forKey: keyCodeKey) != nil,
              let code = defaults.object(forKey: keyCodeKey) as? NSNumber,
              let modifiers = defaults.object(forKey: modifiersKey) as? NSNumber else { return nil }
        let value = HotKeyDefinition(keyCode: code.uint32Value, modifiers: modifiers.uint32Value)
        return value.isValid ? value : nil
    }

    func save(_ definition: HotKeyDefinition?) {
        guard let definition else {
            defaults.removeObject(forKey: keyCodeKey)
            defaults.removeObject(forKey: modifiersKey)
            return
        }
        defaults.set(definition.keyCode, forKey: keyCodeKey)
        defaults.set(definition.modifiers, forKey: modifiersKey)
    }
}
