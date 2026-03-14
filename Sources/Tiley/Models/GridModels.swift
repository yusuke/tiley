import AppKit
import Carbon

struct GridSelection: Equatable, Codable {
    let startColumn: Int
    let startRow: Int
    let endColumn: Int
    let endRow: Int

    var normalized: GridSelection {
        GridSelection(
            startColumn: min(startColumn, endColumn),
            startRow: min(startRow, endRow),
            endColumn: max(startColumn, endColumn),
            endRow: max(startRow, endRow)
        )
    }

    var description: String {
        let n = normalized
        return "c\(n.startColumn + 1)-\(n.endColumn + 1), r\(n.startRow + 1)-\(n.endRow + 1)"
    }

    func scaled(fromRows sourceRows: Int, columns sourceColumns: Int, toRows targetRows: Int, columns targetColumns: Int) -> GridSelection {
        let n = normalized

        func scaledStart(_ value: Int, source: Int, target: Int) -> Int {
            guard source > 0, target > 0 else { return 0 }
            return min(target - 1, max(0, Int(floor((Double(value) / Double(source)) * Double(target)))))
        }

        func scaledEnd(_ value: Int, source: Int, target: Int) -> Int {
            guard source > 0, target > 0 else { return 0 }
            let upper = Int(ceil((Double(value + 1) / Double(source)) * Double(target))) - 1
            return min(target - 1, max(0, upper))
        }

        return GridSelection(
            startColumn: scaledStart(n.startColumn, source: sourceColumns, target: targetColumns),
            startRow: scaledStart(n.startRow, source: sourceRows, target: targetRows),
            endColumn: scaledEnd(n.endColumn, source: sourceColumns, target: targetColumns),
            endRow: scaledEnd(n.endRow, source: sourceRows, target: targetRows)
        ).normalized
    }
}

struct LayoutPreset: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var selection: GridSelection
    var baseRows: Int
    var baseColumns: Int
    var shortcuts: [HotKeyShortcut]

    var hasAnyGlobalShortcut: Bool { shortcuts.contains { $0.isGlobal } }
    var globalShortcuts: [HotKeyShortcut] { shortcuts.filter { $0.isGlobal } }
    var localShortcuts: [HotKeyShortcut] { shortcuts.filter { !$0.isGlobal } }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case selection
        case baseRows
        case baseColumns
        case shortcut
        case shortcuts
        case isGlobalShortcut
        case localShortcut
        case globalShortcut
    }

    init(
        id: UUID,
        name: String,
        selection: GridSelection,
        baseRows: Int,
        baseColumns: Int,
        shortcuts: [HotKeyShortcut]
    ) {
        self.id = id
        self.name = name
        self.selection = selection
        self.baseRows = baseRows
        self.baseColumns = baseColumns
        self.shortcuts = shortcuts
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        selection = try container.decode(GridSelection.self, forKey: .selection)
        baseRows = try container.decode(Int.self, forKey: .baseRows)
        baseColumns = try container.decode(Int.self, forKey: .baseColumns)

        // Decode new array format first, fall back to legacy formats
        if let shortcuts = try container.decodeIfPresent([HotKeyShortcut].self, forKey: .shortcuts) {
            // Migrate legacy preset-level isGlobalShortcut flag to per-shortcut isGlobal
            let legacyGlobal = try container.decodeIfPresent(Bool.self, forKey: .isGlobalShortcut) ?? false
            if legacyGlobal, !shortcuts.contains(where: { $0.isGlobal }) {
                self.shortcuts = shortcuts.map { var s = $0; s.isGlobal = true; return s }
            } else {
                self.shortcuts = shortcuts
            }
        } else if let shortcut = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .shortcut) {
            let legacyGlobal = try container.decodeIfPresent(Bool.self, forKey: .isGlobalShortcut) ?? false
            var s = shortcut
            if legacyGlobal { s.isGlobal = true }
            self.shortcuts = [s]
        } else if let globalShortcut = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .globalShortcut) {
            var s = globalShortcut
            s.isGlobal = true
            shortcuts = [s]
        } else {
            shortcuts = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(selection, forKey: .selection)
        try container.encode(baseRows, forKey: .baseRows)
        try container.encode(baseColumns, forKey: .baseColumns)
        try container.encode(shortcuts, forKey: .shortcuts)
    }

    func scaledSelection(toRows rows: Int, columns: Int) -> GridSelection {
        selection.scaled(fromRows: baseRows, columns: baseColumns, toRows: rows, columns: columns)
    }

    static func defaultPresets(rows: Int, columns: Int) -> [LayoutPreset] {
        let maxColumn = max(0, columns - 1)
        let maxRow = max(0, rows - 1)
        let leftEnd = max(0, (columns / 2) - 1)
        let rightStart = min(maxColumn, columns / 2)
        let topEnd = max(0, (rows / 2) - 1)
        let bottomStart = min(maxRow, rows / 2)

        return [
            LayoutPreset(
                id: UUID(),
                name: NSLocalizedString("Maximize", comment: "Default layout preset name"),
                selection: GridSelection(startColumn: 0, startRow: 0, endColumn: maxColumn, endRow: maxRow),
                baseRows: rows,
                baseColumns: columns,
                shortcuts: [
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: 0)
                ]
            ),
            LayoutPreset(
                id: UUID(),
                name: NSLocalizedString("Left Half", comment: "Default layout preset name"),
                selection: GridSelection(startColumn: 0, startRow: 0, endColumn: leftEnd, endRow: maxRow),
                baseRows: rows,
                baseColumns: columns,
                shortcuts: [
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_A), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_H), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_LeftArrow), modifiers: 0)
                ]
            ),
            LayoutPreset(
                id: UUID(),
                name: NSLocalizedString("Right Half", comment: "Default layout preset name"),
                selection: GridSelection(startColumn: rightStart, startRow: 0, endColumn: maxColumn, endRow: maxRow),
                baseRows: rows,
                baseColumns: columns,
                shortcuts: [
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_D), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_L), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_RightArrow), modifiers: 0)
                ]
            ),
            LayoutPreset(
                id: UUID(),
                name: NSLocalizedString("Top Half", comment: "Default layout preset name"),
                selection: GridSelection(startColumn: 0, startRow: 0, endColumn: maxColumn, endRow: topEnd),
                baseRows: rows,
                baseColumns: columns,
                shortcuts: [
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_K), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_UpArrow), modifiers: 0)
                ]
            ),
            LayoutPreset(
                id: UUID(),
                name: NSLocalizedString("Bottom Half", comment: "Default layout preset name"),
                selection: GridSelection(startColumn: 0, startRow: bottomStart, endColumn: maxColumn, endRow: maxRow),
                baseRows: rows,
                baseColumns: columns,
                shortcuts: [
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_S), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: 0),
                    HotKeyShortcut(keyCode: UInt32(kVK_DownArrow), modifiers: 0)
                ]
            )
        ]
    }
}

enum GridCalculator {
    static func frame(for selection: GridSelection, in visibleFrame: CGRect, rows: Int, columns: Int, gap: CGFloat) -> CGRect {
        let n = selection.normalized
        let totalHorizontalGap = gap * CGFloat(max(0, columns - 1))
        let totalVerticalGap = gap * CGFloat(max(0, rows - 1))
        let cellWidth = max(40, (visibleFrame.width - totalHorizontalGap) / CGFloat(columns))
        let cellHeight = max(40, (visibleFrame.height - totalVerticalGap) / CGFloat(rows))

        let width = cellWidth * CGFloat(n.endColumn - n.startColumn + 1) + gap * CGFloat(n.endColumn - n.startColumn)
        let height = cellHeight * CGFloat(n.endRow - n.startRow + 1) + gap * CGFloat(n.endRow - n.startRow)

        let x = visibleFrame.minX + CGFloat(n.startColumn) * (cellWidth + gap)
        let yTop = visibleFrame.maxY - CGFloat(n.startRow) * (cellHeight + gap)
        let y = yTop - height

        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }
}
