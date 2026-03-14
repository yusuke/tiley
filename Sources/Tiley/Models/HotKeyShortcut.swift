import AppKit
import Carbon

struct HotKeyShortcut: Equatable, Codable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = HotKeyShortcut(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    var displayString: String {
        let parts = modifierDisplayParts + [keyDisplayString]
        return parts.joined(separator: " + ")
    }

    var eventHotKeyModifiers: UInt32 {
        var carbonModifiers: UInt32 = 0
        if modifiers & UInt32(cmdKey) != 0 {
            carbonModifiers |= UInt32(cmdKey)
        }
        if modifiers & UInt32(optionKey) != 0 {
            carbonModifiers |= UInt32(optionKey)
        }
        if modifiers & UInt32(controlKey) != 0 {
            carbonModifiers |= UInt32(controlKey)
        }
        if modifiers & UInt32(shiftKey) != 0 {
            carbonModifiers |= UInt32(shiftKey)
        }
        return carbonModifiers
    }

    static func from(event: NSEvent, requireModifiers: Bool = true) -> HotKeyShortcut? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard !isModifierOnlyKeyCode(event.keyCode) else {
            return nil
        }
        guard !requireModifiers || modifiers != 0 else {
            return nil
        }
        return HotKeyShortcut(
            keyCode: UInt32(event.keyCode),
            modifiers: modifiers
        )
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let deviceIndependentFlags = flags.intersection(.deviceIndependentFlagsMask)
        var carbonModifiers: UInt32 = 0
        if deviceIndependentFlags.contains(.command) {
            carbonModifiers |= UInt32(cmdKey)
        }
        if deviceIndependentFlags.contains(.option) {
            carbonModifiers |= UInt32(optionKey)
        }
        if deviceIndependentFlags.contains(.control) {
            carbonModifiers |= UInt32(controlKey)
        }
        if deviceIndependentFlags.contains(.shift) {
            carbonModifiers |= UInt32(shiftKey)
        }
        return carbonModifiers
    }

    static func isModifierOnlyKeyCode(_ keyCode: UInt16) -> Bool {
        switch Int(keyCode) {
        case kVK_Command, kVK_RightCommand,
             kVK_Shift, kVK_RightShift,
             kVK_Option, kVK_RightOption,
             kVK_Control, kVK_RightControl,
             kVK_CapsLock, kVK_Function:
            return true
        default:
            return false
        }
    }

    private var modifierDisplayParts: [String] {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }
        return parts
    }

    private var keyDisplayString: String {
        if let specialKey = Self.specialKeyNames[Int(keyCode)] {
            return specialKey
        }

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawLayoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "Key \(keyCode)"
        }

        let layoutData = unsafeBitCast(rawLayoutData, to: CFData.self) as Data
        return layoutData.withUnsafeBytes { bytes in
            guard let keyboardLayout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return "Key \(keyCode)"
            }

            var deadKeyState: UInt32 = 0
            let maxLength: Int = 4
            var actualLength = 0
            var unicodeScalars = [UniChar](repeating: 0, count: maxLength)

            let status = UCKeyTranslate(
                keyboardLayout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDown),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                maxLength,
                &actualLength,
                &unicodeScalars
            )

            guard status == noErr, actualLength > 0 else {
                return "Key \(keyCode)"
            }

            return String(utf16CodeUnits: unicodeScalars, count: actualLength)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        }
    }

    private static let specialKeyNames: [Int: String] = [
        kVK_Space: "Space",
        kVK_Return: "Return",
        kVK_Tab: "Tab",
        kVK_Delete: "Delete",
        kVK_ForwardDelete: "Forward Delete",
        kVK_Escape: "Escape",
        kVK_Home: "Home",
        kVK_End: "End",
        kVK_PageUp: "Page Up",
        kVK_PageDown: "Page Down",
        kVK_LeftArrow: "Left Arrow",
        kVK_RightArrow: "Right Arrow",
        kVK_UpArrow: "Up Arrow",
        kVK_DownArrow: "Down Arrow",
        kVK_F1: "F1",
        kVK_F2: "F2",
        kVK_F3: "F3",
        kVK_F4: "F4",
        kVK_F5: "F5",
        kVK_F6: "F6",
        kVK_F7: "F7",
        kVK_F8: "F8",
        kVK_F9: "F9",
        kVK_F10: "F10",
        kVK_F11: "F11",
        kVK_F12: "F12",
        kVK_F13: "F13",
        kVK_F14: "F14",
        kVK_F15: "F15",
        kVK_F16: "F16",
        kVK_F17: "F17",
        kVK_F18: "F18",
        kVK_F19: "F19",
        kVK_F20: "F20"
    ]
}
