import Testing
import Carbon
import AppKit
@testable import Tiley

@Suite("Move to Space")
struct MoveToSpaceTests {

    @Test("settings saved before Move to Space decode with an empty entry")
    func decodesLegacySettings() throws {
        var legacy = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(DisplayShortcutSettings.default)
        ) as! [String: Any]
        legacy.removeValue(forKey: "moveToSpace")
        let data = try JSONSerialization.data(withJSONObject: legacy)

        let decoded = try JSONDecoder().decode(DisplayShortcutSettings.self, from: data)
        #expect(decoded.moveToSpace == .empty)
        #expect(decoded.bringToFront == DisplayShortcutSettings.defaultBringToFront)
    }

    @Test("Move to Space shortcut survives a Codable round-trip")
    func roundTrip() throws {
        var settings = DisplayShortcutSettings.default
        settings.moveToSpace = DisplayShortcutEntry(
            local: HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: 0),
            global: HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: UInt32(controlKey | optionKey)),
            localEnabled: true,
            globalEnabled: true
        )
        let decoded = try JSONDecoder().decode(
            DisplayShortcutSettings.self, from: JSONEncoder().encode(settings)
        )
        #expect(decoded == settings)
    }

    @Test("desktops 1–9 map to their digit, desktop 10 to 0, later desktops to none")
    func keyLabels() {
        func label(_ n: Int) -> String? {
            SpacePickerItem(id: UInt64(n), desktopNumber: n, isWindowSpace: false, appIcons: []).keyLabel
        }
        #expect(label(1) == "1")
        #expect(label(9) == "9")
        #expect(label(10) == "0")
        #expect(label(11) == nil)
    }

    @Test("desktop numbers collapse into ranges")
    func formatRanges() {
        #expect(SpaceMover.formatRanges([]) == "")
        #expect(SpaceMover.formatRanges([4]) == "4")
        #expect(SpaceMover.formatRanges([1, 2, 3, 5, 7, 8]) == "1–3, 5, 7–8")
        #expect(SpaceMover.formatRanges([11, 12, 13, 14, 15, 16, 17, 18]) == "11–18")
    }

    @Test("default Switch to Desktop keys follow macOS: ⌃1–⌃0, then ⌃⌥1–⌃⌥6")
    func defaultDesktopKeys() {
        func label(_ n: Int) -> String? {
            SpaceMover.defaultDesktopShortcut(number: n).map {
                SpaceMover.DesktopShortcutPlan(desktopNumber: n, keyCode: $0.keyCode, modifiers: $0.modifiers).keyLabel
            }
        }
        #expect(label(1) == "⌃1")
        #expect(label(9) == "⌃9")
        #expect(label(10) == "⌃0")
        #expect(label(11) == "⌃⌥1")
        #expect(label(16) == "⌃⌥6")
        #expect(label(17) == nil)
    }
}
