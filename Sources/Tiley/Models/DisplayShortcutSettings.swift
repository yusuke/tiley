import AppKit
import Carbon.HIToolbox
import Foundation

/// Persisted settings for display-movement shortcuts and window cycling shortcuts.
struct DisplayShortcutSettings: Codable, Equatable {
    var moveToPrimary: DisplayShortcutEntry
    var moveToNext: DisplayShortcutEntry
    var moveToPrevious: DisplayShortcutEntry
    /// Shows a popup menu to pick the destination display.
    var moveToOther: DisplayShortcutEntry
    /// Shortcuts to move to a specific physical display, identified by hardware fingerprint.
    var moveToDisplay: [PerDisplayShortcut]
    /// Shortcut for selecting the next window in the window list.
    var selectNextWindow: DisplayShortcutEntry
    /// Shortcut for selecting the previous window in the window list.
    var selectPreviousWindow: DisplayShortcutEntry
    /// Shortcut for bringing the selected window to front.
    var bringToFront: DisplayShortcutEntry
    /// Shortcut for closing the selected window or quitting the app.
    var closeOrQuit: DisplayShortcutEntry

    static let defaultCloseOrQuit = DisplayShortcutEntry(
        local: HotKeyShortcut(keyCode: UInt32(kVK_ANSI_Slash), modifiers: 0),
        global: nil,
        localEnabled: true,
        globalEnabled: false
    )
    static let defaultBringToFront = DisplayShortcutEntry(
        local: HotKeyShortcut(keyCode: UInt32(kVK_Return), modifiers: 0),
        global: nil,
        localEnabled: true,
        globalEnabled: false
    )
    static let defaultSelectNextWindow = DisplayShortcutEntry(
        local: HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: 0),
        global: nil,
        localEnabled: true,
        globalEnabled: false
    )
    static let defaultSelectPreviousWindow = DisplayShortcutEntry(
        local: HotKeyShortcut(keyCode: UInt32(kVK_Space), modifiers: UInt32(shiftKey)),
        global: nil,
        localEnabled: true,
        globalEnabled: false
    )

    static let `default` = DisplayShortcutSettings(
        moveToPrimary: .empty,
        moveToNext: .empty,
        moveToPrevious: .empty,
        moveToOther: .empty,
        moveToDisplay: [],
        selectNextWindow: defaultSelectNextWindow,
        selectPreviousWindow: defaultSelectPreviousWindow,
        bringToFront: defaultBringToFront,
        closeOrQuit: defaultCloseOrQuit
    )

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moveToPrimary = try container.decode(DisplayShortcutEntry.self, forKey: .moveToPrimary)
        moveToNext = try container.decode(DisplayShortcutEntry.self, forKey: .moveToNext)
        moveToPrevious = try container.decode(DisplayShortcutEntry.self, forKey: .moveToPrevious)
        moveToOther = try container.decode(DisplayShortcutEntry.self, forKey: .moveToOther)
        moveToDisplay = try container.decode([PerDisplayShortcut].self, forKey: .moveToDisplay)
        selectNextWindow = try container.decodeIfPresent(DisplayShortcutEntry.self, forKey: .selectNextWindow)
            ?? Self.defaultSelectNextWindow
        selectPreviousWindow = try container.decodeIfPresent(DisplayShortcutEntry.self, forKey: .selectPreviousWindow)
            ?? Self.defaultSelectPreviousWindow
        bringToFront = try container.decodeIfPresent(DisplayShortcutEntry.self, forKey: .bringToFront)
            ?? Self.defaultBringToFront
        closeOrQuit = try container.decodeIfPresent(DisplayShortcutEntry.self, forKey: .closeOrQuit)
            ?? Self.defaultCloseOrQuit
    }

    init(
        moveToPrimary: DisplayShortcutEntry,
        moveToNext: DisplayShortcutEntry,
        moveToPrevious: DisplayShortcutEntry,
        moveToOther: DisplayShortcutEntry,
        moveToDisplay: [PerDisplayShortcut],
        selectNextWindow: DisplayShortcutEntry = defaultSelectNextWindow,
        selectPreviousWindow: DisplayShortcutEntry = defaultSelectPreviousWindow,
        bringToFront: DisplayShortcutEntry = defaultBringToFront,
        closeOrQuit: DisplayShortcutEntry = defaultCloseOrQuit
    ) {
        self.moveToPrimary = moveToPrimary
        self.moveToNext = moveToNext
        self.moveToPrevious = moveToPrevious
        self.moveToOther = moveToOther
        self.moveToDisplay = moveToDisplay
        self.selectNextWindow = selectNextWindow
        self.selectPreviousWindow = selectPreviousWindow
        self.bringToFront = bringToFront
        self.closeOrQuit = closeOrQuit
    }

    /// Returns the entry matching a fingerprint and occurrence index, or nil.
    func entry(for fingerprint: DisplayFingerprint, occurrenceIndex: Int = 1) -> PerDisplayShortcut? {
        moveToDisplay.first { $0.fingerprint == fingerprint && $0.occurrenceIndex == occurrenceIndex }
    }

    /// Returns the array index of the entry matching a fingerprint and occurrence index, or nil.
    func entryIndex(for fingerprint: DisplayFingerprint, occurrenceIndex: Int = 1) -> Int? {
        moveToDisplay.firstIndex { $0.fingerprint == fingerprint && $0.occurrenceIndex == occurrenceIndex }
    }

    /// Ensures an entry exists for the given fingerprint + occurrence and returns its array index.
    @discardableResult
    mutating func ensureEntry(for fingerprint: DisplayFingerprint, occurrenceIndex: Int = 1) -> Int {
        if let idx = entryIndex(for: fingerprint, occurrenceIndex: occurrenceIndex) { return idx }
        moveToDisplay.append(PerDisplayShortcut(fingerprint: fingerprint, occurrenceIndex: occurrenceIndex, shortcuts: .empty))
        return moveToDisplay.count - 1
    }
}

/// Hardware fingerprint for a physical display, stable across reconnections.
/// Uses vendor number, model number, and serial number from CoreGraphics.
struct DisplayFingerprint: Codable, Equatable, Hashable {
    let vendorNumber: UInt32
    let modelNumber: UInt32
    let serialNumber: UInt32

    /// Creates a fingerprint from a `CGDirectDisplayID`.
    init(displayID: CGDirectDisplayID) {
        vendorNumber = CGDisplayVendorNumber(displayID)
        modelNumber = CGDisplayModelNumber(displayID)
        serialNumber = CGDisplaySerialNumber(displayID)
    }

    init(vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32) {
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
    }
}

/// Shortcut entry for a specific physical display, identified by hardware fingerprint.
struct PerDisplayShortcut: Codable, Equatable {
    var fingerprint: DisplayFingerprint
    /// 1-based occurrence index among displays sharing the same fingerprint.
    var occurrenceIndex: Int
    var shortcuts: DisplayShortcutEntry

    init(fingerprint: DisplayFingerprint, occurrenceIndex: Int = 1, shortcuts: DisplayShortcutEntry) {
        self.fingerprint = fingerprint
        self.occurrenceIndex = occurrenceIndex
        self.shortcuts = shortcuts
    }
}

/// A pair of shortcuts (local + global) for a single display-movement action.
struct DisplayShortcutEntry: Codable, Equatable {
    var local: HotKeyShortcut?
    var global: HotKeyShortcut?
    var localEnabled: Bool
    var globalEnabled: Bool

    static let empty = DisplayShortcutEntry(local: nil, global: nil, localEnabled: false, globalEnabled: false)

    init(local: HotKeyShortcut? = nil, global: HotKeyShortcut? = nil, localEnabled: Bool = false, globalEnabled: Bool = false) {
        self.local = local
        self.global = global
        self.localEnabled = localEnabled
        self.globalEnabled = globalEnabled
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        local = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .local)
        global = try container.decodeIfPresent(HotKeyShortcut.self, forKey: .global)
        localEnabled = try container.decodeIfPresent(Bool.self, forKey: .localEnabled) ?? (local != nil)
        globalEnabled = try container.decodeIfPresent(Bool.self, forKey: .globalEnabled) ?? (global != nil)
    }
}

/// Identifies a display-movement action for Carbon hotkey dispatch.
enum DisplayHotKeyAction {
    case moveToPrimary
    case moveToNext
    case moveToPrevious
    case moveToOther
    case moveToDisplay(displayID: CGDirectDisplayID)
}

// MARK: - Display fingerprint resolution

/// Resolves hardware fingerprints to currently connected `CGDirectDisplayID`s.
/// When multiple displays share the same fingerprint (identical model with serial 0),
/// they are disambiguated by assigning occurrence indices (1-based) sorted by `CGDirectDisplayID`.
struct DisplayFingerprintResolver {

    /// A resolved mapping from fingerprint to connected display info.
    struct ResolvedDisplay {
        let fingerprint: DisplayFingerprint
        let displayID: CGDirectDisplayID
        let screen: NSScreen
        /// 1-based occurrence index among displays sharing the same fingerprint.
        /// 1 for unique displays, 2/3/... for duplicates.
        let occurrenceIndex: Int
        /// Total number of connected displays sharing this fingerprint.
        let occurrenceCount: Int
    }

    /// All resolved displays, sorted by `CGDirectDisplayID`.
    let displays: [ResolvedDisplay]

    init() {
        let screens = NSScreen.screens
        // Group screens by fingerprint, sorted by displayID within each group.
        var groups: [DisplayFingerprint: [(CGDirectDisplayID, NSScreen)]] = [:]
        for screen in screens {
            let did = screen.displayID
            let fp = DisplayFingerprint(displayID: did)
            groups[fp, default: []].append((did, screen))
        }
        // Sort each group by displayID for stable occurrence assignment.
        for key in groups.keys {
            groups[key]?.sort { $0.0 < $1.0 }
        }
        // Build resolved list.
        var result: [ResolvedDisplay] = []
        for (fp, members) in groups {
            for (i, (did, screen)) in members.enumerated() {
                result.append(ResolvedDisplay(
                    fingerprint: fp,
                    displayID: did,
                    screen: screen,
                    occurrenceIndex: i + 1,
                    occurrenceCount: members.count
                ))
            }
        }
        // Sort by physical arrangement: top-to-bottom rows, left-to-right within each row.
        // Displays whose vertical extents overlap by ≥80% are treated as the same row.
        displays = Self.sortByPhysicalArrangement(result)
    }

    /// Sorts displays by physical position: higher displays first, then left to right.
    /// Displays whose vertical ranges overlap by ≥80% are considered on the same row.
    private static func sortByPhysicalArrangement(_ list: [ResolvedDisplay]) -> [ResolvedDisplay] {
        guard list.count > 1 else { return list }

        // Use CGDisplayBounds (Quartz coordinates: origin top-left of primary, y↓).
        struct DisplayRect {
            let resolved: ResolvedDisplay
            let bounds: CGRect  // Quartz coords
        }
        let rects = list.map { DisplayRect(resolved: $0, bounds: CGDisplayBounds($0.displayID)) }

        // Assign rows: group displays whose vertical extents overlap ≥80%.
        var rows: [[DisplayRect]] = []
        let sortedByTop = rects.sorted { $0.bounds.minY < $1.bounds.minY }

        for dr in sortedByTop {
            var placed = false
            for i in rows.indices {
                // Check overlap with the first element in the row (representative).
                let rep = rows[i][0]
                if verticalOverlapFraction(dr.bounds, rep.bounds) >= 0.8 {
                    rows[i].append(dr)
                    placed = true
                    break
                }
            }
            if !placed {
                rows.append([dr])
            }
        }

        // Sort rows top-to-bottom (smallest minY first in Quartz coords).
        rows.sort { rowA, rowB in
            let topA = rowA.map(\.bounds.minY).min() ?? 0
            let topB = rowB.map(\.bounds.minY).min() ?? 0
            return topA < topB
        }

        // Within each row, sort left-to-right.
        var result: [ResolvedDisplay] = []
        for row in rows {
            let sorted = row.sorted { $0.bounds.minX < $1.bounds.minX }
            result.append(contentsOf: sorted.map(\.resolved))
        }
        return result
    }

    /// Returns the fraction of vertical overlap between two rects relative to the shorter one.
    private static func verticalOverlapFraction(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlapTop = max(a.minY, b.minY)
        let overlapBottom = min(a.maxY, b.maxY)
        let overlap = max(0, overlapBottom - overlapTop)
        let shorter = min(a.height, b.height)
        guard shorter > 0 else { return 0 }
        return overlap / shorter
    }

    /// Finds the resolved display for a fingerprint with a given occurrence index.
    func resolve(_ fingerprint: DisplayFingerprint, occurrenceIndex: Int = 1) -> ResolvedDisplay? {
        let matching = displays.filter { $0.fingerprint == fingerprint }
        guard occurrenceIndex >= 1, occurrenceIndex <= matching.count else { return nil }
        return matching[occurrenceIndex - 1]
    }

    /// Returns all resolved displays matching a fingerprint.
    func resolveAll(_ fingerprint: DisplayFingerprint) -> [ResolvedDisplay] {
        displays.filter { $0.fingerprint == fingerprint }
    }

    /// Finds the resolved display for a given `CGDirectDisplayID`.
    func resolve(displayID: CGDirectDisplayID) -> ResolvedDisplay? {
        displays.first { $0.displayID == displayID }
    }

    /// Display name with occurrence suffix if needed: "Display Name" or "Display Name (2)".
    func displayName(for resolved: ResolvedDisplay) -> String {
        let name = resolved.screen.localizedName
        if resolved.occurrenceCount > 1 {
            return resolved.occurrenceIndex == 1 ? name : "\(name) (\(resolved.occurrenceIndex))"
        }
        return name
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
