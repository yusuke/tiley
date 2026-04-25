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

    func overlaps(_ other: GridSelection) -> Bool {
        let a = self.normalized, b = other.normalized
        return a.startColumn <= b.endColumn && a.endColumn >= b.startColumn
            && a.startRow <= b.endRow && a.endRow >= b.startRow
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

/// A pair of indices into `LayoutPreset.allSelections` marking two regions
/// that should be grouped together automatically when the preset is applied.
/// Indices are stored normalized (`indexA < indexB`) so `==` / `Hashable`
/// treat `(a,b)` and `(b,a)` as identical.
struct PresetGroupPair: Hashable, Codable {
    let indexA: Int
    let indexB: Int

    init(_ a: Int, _ b: Int) {
        self.indexA = min(a, b)
        self.indexB = max(a, b)
    }
}

struct LayoutPreset: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var selection: GridSelection
    var secondarySelections: [GridSelection]
    var baseRows: Int
    var baseColumns: Int
    var shortcuts: [HotKeyShortcut]
    /// Pairs of selection indices (0 = primary, 1+ = secondary[i-1]) that
    /// should be grouped together automatically when the preset is applied.
    var groupedPairs: [PresetGroupPair]
    /// Parallel to `allSelections`. Each entry is the assigned app's bundle
    /// identifier, or `nil` for an unassigned slot. Helpers pad/truncate on
    /// access so the effective length always equals `allSelections.count`.
    var rectangleApps: [String?]

    /// A sentinel selection used when all selections have been deleted in the editor.
    static let emptySelection = GridSelection(startColumn: -1, startRow: -1, endColumn: -1, endRow: -1)

    var allSelections: [GridSelection] {
        if selection == Self.emptySelection {
            return []
        }
        return [selection] + secondarySelections
    }

    func allScaledSelections(toRows rows: Int, columns: Int) -> [GridSelection] {
        allSelections.map {
            $0.scaled(fromRows: baseRows, columns: baseColumns, toRows: rows, columns: columns)
        }
    }

    /// Returns a copy of `rectangleApps` padded/truncated to match `allSelections.count`.
    var normalizedRectangleApps: [String?] {
        let target = allSelections.count
        if rectangleApps.count == target { return rectangleApps }
        var result = rectangleApps
        if result.count > target {
            result = Array(result.prefix(target))
        } else {
            result.append(contentsOf: Array(repeating: nil, count: target - result.count))
        }
        return result
    }

    /// Bundle identifier assigned to the selection at `idx`, or `nil` if unassigned or out of range.
    func appAssignment(atSelectionIndex idx: Int) -> String? {
        let apps = normalizedRectangleApps
        guard idx >= 0, idx < apps.count else { return nil }
        return apps[idx]
    }

    func isAssigned(atSelectionIndex idx: Int) -> Bool {
        appAssignment(atSelectionIndex: idx) != nil
    }

    /// 1-based index shown in the editor for unassigned slots. `nil` for
    /// assigned slots (they show an app icon instead). Unassigned slots are
    /// numbered in the order they appear in `allSelections` — since
    /// `unassignApp` moves a freshly-unassigned slot to the end, its display
    /// index becomes the largest unassigned number.
    func displayIndex(forSelectionIndex idx: Int) -> Int? {
        let apps = normalizedRectangleApps
        guard idx >= 0, idx < apps.count else { return nil }
        guard apps[idx] == nil else { return nil }
        var position = 0
        for i in 0...idx {
            if apps[i] == nil {
                position += 1
            }
        }
        return position
    }

    var assignedSelectionIndices: [Int] {
        normalizedRectangleApps.enumerated().compactMap { $0.element == nil ? nil : $0.offset }
    }

    var unassignedSelectionIndices: [Int] {
        normalizedRectangleApps.enumerated().compactMap { $0.element == nil ? $0.offset : nil }
    }

    var hasAnyGlobalShortcut: Bool { shortcuts.contains { $0.isGlobal } }
    var globalShortcuts: [HotKeyShortcut] { shortcuts.filter { $0.isGlobal } }
    var localShortcuts: [HotKeyShortcut] { shortcuts.filter { !$0.isGlobal } }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case selection
        case secondarySelections
        case baseRows
        case baseColumns
        case shortcut
        case shortcuts
        case isGlobalShortcut
        case localShortcut
        case globalShortcut
        case groupedPairs
        case rectangleApps
    }

    init(
        id: UUID,
        name: String,
        selection: GridSelection,
        secondarySelections: [GridSelection] = [],
        baseRows: Int,
        baseColumns: Int,
        shortcuts: [HotKeyShortcut],
        groupedPairs: [PresetGroupPair] = [],
        rectangleApps: [String?] = []
    ) {
        self.id = id
        self.name = name
        self.selection = selection
        self.secondarySelections = secondarySelections
        self.baseRows = baseRows
        self.baseColumns = baseColumns
        self.shortcuts = shortcuts
        self.groupedPairs = groupedPairs
        self.rectangleApps = rectangleApps
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        selection = try container.decode(GridSelection.self, forKey: .selection)
        secondarySelections = try container.decodeIfPresent([GridSelection].self, forKey: .secondarySelections) ?? []
        baseRows = try container.decode(Int.self, forKey: .baseRows)
        baseColumns = try container.decode(Int.self, forKey: .baseColumns)
        groupedPairs = try container.decodeIfPresent([PresetGroupPair].self, forKey: .groupedPairs) ?? []
        rectangleApps = try container.decodeIfPresent([String?].self, forKey: .rectangleApps) ?? []

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
        if !secondarySelections.isEmpty {
            try container.encode(secondarySelections, forKey: .secondarySelections)
        }
        if !groupedPairs.isEmpty {
            try container.encode(groupedPairs, forKey: .groupedPairs)
        }
        let normalizedApps = normalizedRectangleApps
        if normalizedApps.contains(where: { $0 != nil }) {
            try container.encode(normalizedApps, forKey: .rectangleApps)
        }
    }

    func scaledSelection(toRows rows: Int, columns: Int) -> GridSelection {
        selection.scaled(fromRows: baseRows, columns: baseColumns, toRows: rows, columns: columns)
    }

    func scaledSecondarySelections(toRows rows: Int, columns: Int) -> [GridSelection] {
        secondarySelections.map {
            $0.scaled(fromRows: baseRows, columns: baseColumns, toRows: rows, columns: columns)
        }
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
                secondarySelections: [
                    GridSelection(startColumn: rightStart, startRow: 0, endColumn: maxColumn, endRow: maxRow)
                ],
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
                secondarySelections: [
                    GridSelection(startColumn: 0, startRow: 0, endColumn: leftEnd, endRow: maxRow)
                ],
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
                secondarySelections: [
                    GridSelection(startColumn: 0, startRow: bottomStart, endColumn: maxColumn, endRow: maxRow)
                ],
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
                secondarySelections: [
                    GridSelection(startColumn: 0, startRow: 0, endColumn: maxColumn, endRow: topEnd)
                ],
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

/// Relative window position within the visible frame (all values 0.0–1.0).
struct WindowFrameRelative: Equatable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat
    /// Menu bar height as a fraction of the visible frame height.
    let menuBarHeightFraction: CGFloat
    /// The title of the window (e.g. document name).
    let windowTitle: String?
    /// The name of the owning application.
    let appName: String?
    /// The icon of the owning application.
    let appIcon: NSImage?

    static func == (lhs: WindowFrameRelative, rhs: WindowFrameRelative) -> Bool {
        lhs.x == rhs.x && lhs.y == rhs.y && lhs.width == rhs.width && lhs.height == rhs.height
            && lhs.menuBarHeightFraction == rhs.menuBarHeightFraction
            && lhs.windowTitle == rhs.windowTitle && lhs.appName == rhs.appName
            && lhs.appIcon === rhs.appIcon
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

// MARK: - Selection Adjacency (for preset editor grouping badges)

/// Edge-adjacency between two `GridSelection`s within a preset's grid.
/// Two selections are adjacent when their bounding boxes share a full grid
/// edge (one cell offset between them on one axis) and their ranges on the
/// other axis overlap by at least one cell.
struct SelectionAdjacency: Hashable {
    enum Edge: Hashable {
        case left, right, top, bottom
    }

    /// Index of selection A into the `selections` array passed to `detect`.
    let indexA: Int
    /// Index of selection B into the same array.
    let indexB: Int
    /// Which edge of A is in contact with B.
    let edgeOfA: Edge
    /// Shared overlap interval in cell coordinates on the axis orthogonal to
    /// `edgeOfA` (row range for left/right, column range for top/bottom).
    let overlapStart: Int
    let overlapEnd: Int
}

enum SelectionAdjacencyDetector {
    /// Enumerates all edge-adjacent pairs among the given selections.
    /// Each pair is returned once with `indexA < indexB`.
    static func detect(selections: [GridSelection]) -> [SelectionAdjacency] {
        var result: [SelectionAdjacency] = []
        guard selections.count >= 2 else { return result }
        for i in 0..<selections.count {
            for j in (i + 1)..<selections.count {
                let a = selections[i].normalized
                let b = selections[j].normalized

                // Right of A meets left of B (columns adjacent, rows overlap).
                if a.endColumn + 1 == b.startColumn {
                    let overlapStart = max(a.startRow, b.startRow)
                    let overlapEnd = min(a.endRow, b.endRow)
                    if overlapStart <= overlapEnd {
                        result.append(SelectionAdjacency(indexA: i, indexB: j, edgeOfA: .right, overlapStart: overlapStart, overlapEnd: overlapEnd))
                        continue
                    }
                }
                // Left of A meets right of B.
                if b.endColumn + 1 == a.startColumn {
                    let overlapStart = max(a.startRow, b.startRow)
                    let overlapEnd = min(a.endRow, b.endRow)
                    if overlapStart <= overlapEnd {
                        result.append(SelectionAdjacency(indexA: i, indexB: j, edgeOfA: .left, overlapStart: overlapStart, overlapEnd: overlapEnd))
                        continue
                    }
                }
                // Bottom of A meets top of B (row-wise, AppKit-style top-origin grid).
                if a.endRow + 1 == b.startRow {
                    let overlapStart = max(a.startColumn, b.startColumn)
                    let overlapEnd = min(a.endColumn, b.endColumn)
                    if overlapStart <= overlapEnd {
                        result.append(SelectionAdjacency(indexA: i, indexB: j, edgeOfA: .bottom, overlapStart: overlapStart, overlapEnd: overlapEnd))
                        continue
                    }
                }
                // Top of A meets bottom of B.
                if b.endRow + 1 == a.startRow {
                    let overlapStart = max(a.startColumn, b.startColumn)
                    let overlapEnd = min(a.endColumn, b.endColumn)
                    if overlapStart <= overlapEnd {
                        result.append(SelectionAdjacency(indexA: i, indexB: j, edgeOfA: .top, overlapStart: overlapStart, overlapEnd: overlapEnd))
                        continue
                    }
                }
            }
        }
        return result
    }
}

// MARK: - Window Resize Presets

struct WindowResizePreset {
    let width: Int
    let height: Int
    let ratioLabel: String

    var label: String { "\(width) x \(height) (\(ratioLabel))" }
    var size: CGSize { CGSize(width: CGFloat(width), height: CGFloat(height)) }

    static let all: [(ratio: String, presets: [WindowResizePreset])] = [
        ("16:9", [
            WindowResizePreset(width: 15360, height: 8640, ratioLabel: "16:9"),
            WindowResizePreset(width: 7680, height: 4320, ratioLabel: "16:9"),
            WindowResizePreset(width: 5120, height: 2880, ratioLabel: "16:9"),
            WindowResizePreset(width: 3840, height: 2160, ratioLabel: "16:9"),
            WindowResizePreset(width: 3200, height: 1800, ratioLabel: "16:9"),
            WindowResizePreset(width: 2560, height: 1440, ratioLabel: "16:9"),
            WindowResizePreset(width: 1920, height: 1080, ratioLabel: "16:9"),
            WindowResizePreset(width: 1600, height: 900, ratioLabel: "16:9"),
            WindowResizePreset(width: 1280, height: 720, ratioLabel: "16:9"),
            WindowResizePreset(width: 854, height: 480, ratioLabel: "16:9"),
            WindowResizePreset(width: 640, height: 360, ratioLabel: "16:9"),
            WindowResizePreset(width: 426, height: 240, ratioLabel: "16:9"),
        ]),
        ("16:10", [
            WindowResizePreset(width: 15360, height: 9600, ratioLabel: "16:10"),
            WindowResizePreset(width: 7680, height: 4800, ratioLabel: "16:10"),
            WindowResizePreset(width: 5120, height: 3200, ratioLabel: "16:10"),
            WindowResizePreset(width: 3840, height: 2400, ratioLabel: "16:10"),
            WindowResizePreset(width: 3200, height: 2000, ratioLabel: "16:10"),
            WindowResizePreset(width: 2560, height: 1600, ratioLabel: "16:10"),
            WindowResizePreset(width: 1920, height: 1200, ratioLabel: "16:10"),
            WindowResizePreset(width: 1600, height: 1000, ratioLabel: "16:10"),
            WindowResizePreset(width: 1280, height: 800, ratioLabel: "16:10"),
            WindowResizePreset(width: 1200, height: 760, ratioLabel: "16:10"),
            WindowResizePreset(width: 1024, height: 665, ratioLabel: "16:10"),
        ]),
        ("4:3", [
            WindowResizePreset(width: 15360, height: 11520, ratioLabel: "4:3"),
            WindowResizePreset(width: 7680, height: 5760, ratioLabel: "4:3"),
            WindowResizePreset(width: 5120, height: 3840, ratioLabel: "4:3"),
            WindowResizePreset(width: 3840, height: 2880, ratioLabel: "4:3"),
            WindowResizePreset(width: 3200, height: 2400, ratioLabel: "4:3"),
            WindowResizePreset(width: 2560, height: 1920, ratioLabel: "4:3"),
            WindowResizePreset(width: 1920, height: 1440, ratioLabel: "4:3"),
            WindowResizePreset(width: 1600, height: 1200, ratioLabel: "4:3"),
            WindowResizePreset(width: 1280, height: 960, ratioLabel: "4:3"),
            WindowResizePreset(width: 854, height: 640, ratioLabel: "4:3"),
            WindowResizePreset(width: 640, height: 480, ratioLabel: "4:3"),
            WindowResizePreset(width: 426, height: 320, ratioLabel: "4:3"),
        ]),
        ("9:16", [
            WindowResizePreset(width: 8640, height: 15360, ratioLabel: "9:16"),
            WindowResizePreset(width: 4320, height: 7680, ratioLabel: "9:16"),
            WindowResizePreset(width: 2880, height: 5120, ratioLabel: "9:16"),
            WindowResizePreset(width: 2160, height: 3840, ratioLabel: "9:16"),
            WindowResizePreset(width: 1800, height: 3200, ratioLabel: "9:16"),
            WindowResizePreset(width: 1440, height: 2560, ratioLabel: "9:16"),
            WindowResizePreset(width: 1080, height: 1920, ratioLabel: "9:16"),
            WindowResizePreset(width: 900, height: 1600, ratioLabel: "9:16"),
            WindowResizePreset(width: 720, height: 1280, ratioLabel: "9:16"),
            WindowResizePreset(width: 480, height: 854, ratioLabel: "9:16"),
            WindowResizePreset(width: 360, height: 640, ratioLabel: "9:16"),
        ]),
    ]

    /// Returns presets that fit within the given screen's visible frame, grouped by aspect ratio.
    static func presetsAvailable(on screen: NSScreen) -> [(ratio: String, presets: [WindowResizePreset])] {
        let visible = screen.visibleFrame
        return all.compactMap { group in
            let filtered = group.presets.filter { CGFloat($0.width) <= visible.width && CGFloat($0.height) <= visible.height }
            return filtered.isEmpty ? nil : (ratio: group.ratio, presets: filtered)
        }
    }
}

// MARK: - Subsequence Search

extension String {
    /// Returns `true` if all characters in `query` appear in `self` in order (subsequence match).
    func isSubsequence(of query: String) -> Bool {
        var searchIndex = self.startIndex
        for ch in query {
            guard let found = self[searchIndex...].firstIndex(of: ch) else { return false }
            searchIndex = self.index(after: found)
        }
        return true
    }
}
