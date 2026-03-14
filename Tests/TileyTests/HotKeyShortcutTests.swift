import Testing
import Carbon
import AppKit
@testable import Tiley

@Suite("HotKeyShortcut")
struct HotKeyShortcutTests {

    @Test("default shortcut has expected values")
    func defaultValues() {
        let shortcut = HotKeyShortcut.default
        #expect(shortcut.keyCode == UInt32(kVK_Space))
        #expect(shortcut.modifiers == UInt32(cmdKey | shiftKey))
    }

    @Test("equality for matching keyCode and modifiers")
    func equality() {
        let a = HotKeyShortcut(keyCode: 0, modifiers: UInt32(cmdKey))
        let b = HotKeyShortcut(keyCode: 0, modifiers: UInt32(cmdKey))
        #expect(a == b)
    }

    @Test("inequality for different modifiers")
    func inequality() {
        let a = HotKeyShortcut(keyCode: 0, modifiers: UInt32(cmdKey))
        let b = HotKeyShortcut(keyCode: 0, modifiers: UInt32(optionKey))
        #expect(a != b)
    }

    @Test("Codable round-trip preserves values")
    func codableRoundTrip() throws {
        let original = HotKeyShortcut(keyCode: 49, modifiers: UInt32(cmdKey | optionKey))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - carbonModifiers

    @Test("carbonModifiers maps command flag")
    func carbonModifiersCommand() {
        let result = HotKeyShortcut.carbonModifiers(from: .command)
        #expect(result == UInt32(cmdKey))
    }

    @Test("carbonModifiers maps option flag")
    func carbonModifiersOption() {
        let result = HotKeyShortcut.carbonModifiers(from: .option)
        #expect(result == UInt32(optionKey))
    }

    @Test("carbonModifiers maps control flag")
    func carbonModifiersControl() {
        let result = HotKeyShortcut.carbonModifiers(from: .control)
        #expect(result == UInt32(controlKey))
    }

    @Test("carbonModifiers maps shift flag")
    func carbonModifiersShift() {
        let result = HotKeyShortcut.carbonModifiers(from: .shift)
        #expect(result == UInt32(shiftKey))
    }

    @Test("carbonModifiers maps combined flags")
    func carbonModifiersCombined() {
        let flags: NSEvent.ModifierFlags = [.command, .option, .shift]
        let result = HotKeyShortcut.carbonModifiers(from: flags)
        let expected = UInt32(cmdKey) | UInt32(optionKey) | UInt32(shiftKey)
        #expect(result == expected)
    }

    @Test("carbonModifiers returns 0 for empty flags")
    func carbonModifiersEmpty() {
        let result = HotKeyShortcut.carbonModifiers(from: [])
        #expect(result == 0)
    }

    // MARK: - isModifierOnlyKeyCode

    @Test("modifier-only key codes return true",
          arguments: [kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift,
                      kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl,
                      kVK_CapsLock, kVK_Function])
    func modifierOnlyReturnsTrue(keyCode: Int) {
        #expect(HotKeyShortcut.isModifierOnlyKeyCode(UInt16(keyCode)))
    }

    @Test("non-modifier key codes return false",
          arguments: [kVK_Space, kVK_Return, kVK_ANSI_A, kVK_F1])
    func nonModifierReturnsFalse(keyCode: Int) {
        #expect(!HotKeyShortcut.isModifierOnlyKeyCode(UInt16(keyCode)))
    }

    // MARK: - eventHotKeyModifiers

    @Test("eventHotKeyModifiers passes through carbon modifiers")
    func eventHotKeyModifiersPassthrough() {
        let mods = UInt32(cmdKey | controlKey)
        let shortcut = HotKeyShortcut(keyCode: 0, modifiers: mods)
        #expect(shortcut.eventHotKeyModifiers == mods)
    }

    @Test("eventHotKeyModifiers returns 0 when no modifiers")
    func eventHotKeyModifiersZero() {
        let shortcut = HotKeyShortcut(keyCode: 49, modifiers: 0)
        #expect(shortcut.eventHotKeyModifiers == 0)
    }
}
