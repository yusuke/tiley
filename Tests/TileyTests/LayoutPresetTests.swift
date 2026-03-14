import Testing
import Carbon
@testable import Tiley

@Suite("LayoutPreset")
struct LayoutPresetTests {

    // MARK: - defaultPresets

    @Test("defaultPresets returns 5 presets")
    func defaultPresetsCount() {
        let presets = LayoutPreset.defaultPresets(rows: 6, columns: 6)
        #expect(presets.count == 5)
    }

    @Test("default presets all have local shortcuts")
    func defaultPresetsLocalShortcuts() {
        let presets = LayoutPreset.defaultPresets(rows: 6, columns: 6)
        for preset in presets {
            #expect(preset.shortcut != nil)
            #expect(preset.isGlobalShortcut == false)
            #expect(preset.shortcut?.modifiers == 0)
        }
    }

    @Test("default presets store base grid dimensions")
    func defaultPresetsBaseDimensions() {
        let presets = LayoutPreset.defaultPresets(rows: 8, columns: 10)
        for preset in presets {
            #expect(preset.baseRows == 8)
            #expect(preset.baseColumns == 10)
        }
    }

    // MARK: - Codable

    @Test("Codable round-trip preserves all fields")
    func codableRoundTrip() throws {
        let original = LayoutPreset(
            id: UUID(),
            name: "Test",
            selection: GridSelection(startColumn: 0, startRow: 0, endColumn: 2, endRow: 3),
            baseRows: 6,
            baseColumns: 6,
            shortcut: HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: UInt32(cmdKey)),
            isGlobalShortcut: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: data)
        #expect(decoded == original)
    }

    @Test("Codable round-trip with nil shortcut")
    func codableNilShortcut() throws {
        let original = LayoutPreset(
            id: UUID(),
            name: "No Shortcut",
            selection: GridSelection(startColumn: 0, startRow: 0, endColumn: 1, endRow: 1),
            baseRows: 4,
            baseColumns: 4,
            shortcut: nil,
            isGlobalShortcut: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: data)
        #expect(decoded == original)
    }

    @Test("decoding legacy globalShortcut key migrates correctly")
    func codableLegacyGlobalShortcut() throws {
        let id = UUID()
        let json = """
        {
            "id": "\(id.uuidString)",
            "name": "Legacy",
            "selection": {"startColumn": 0, "startRow": 0, "endColumn": 5, "endRow": 5},
            "baseRows": 6,
            "baseColumns": 6,
            "globalShortcut": {"keyCode": 49, "modifiers": 256}
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(LayoutPreset.self, from: data)
        #expect(decoded.shortcut != nil)
        #expect(decoded.shortcut?.keyCode == 49)
        #expect(decoded.shortcut?.modifiers == 256)
        #expect(decoded.isGlobalShortcut == true)
    }

    // MARK: - scaledSelection

    @Test("scaledSelection delegates to GridSelection.scaled")
    func scaledSelectionDelegates() {
        let preset = LayoutPreset(
            id: UUID(),
            name: "Full",
            selection: GridSelection(startColumn: 0, startRow: 0, endColumn: 5, endRow: 5),
            baseRows: 6,
            baseColumns: 6,
            shortcut: nil,
            isGlobalShortcut: false
        )
        let scaled = preset.scaledSelection(toRows: 4, columns: 4)
        #expect(scaled == GridSelection(startColumn: 0, startRow: 0, endColumn: 3, endRow: 3))
    }

    @Test("scaledSelection with same dimensions returns original")
    func scaledSelectionIdentity() {
        let selection = GridSelection(startColumn: 1, startRow: 1, endColumn: 3, endRow: 4)
        let preset = LayoutPreset(
            id: UUID(),
            name: "Partial",
            selection: selection,
            baseRows: 6,
            baseColumns: 6,
            shortcut: nil,
            isGlobalShortcut: false
        )
        let scaled = preset.scaledSelection(toRows: 6, columns: 6)
        #expect(scaled == selection.normalized)
    }
}
