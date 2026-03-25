import AppKit
import Foundation

/// Persisted settings for display-movement shortcuts.
struct DisplayShortcutSettings: Codable, Equatable {
    var moveToPrimary: DisplayShortcutEntry
    var moveToNext: DisplayShortcutEntry
    var moveToPrevious: DisplayShortcutEntry
    /// Shows a popup menu to pick the destination display.
    var moveToOther: DisplayShortcutEntry
    /// Shortcuts to move to a specific physical display, identified by hardware fingerprint.
    var moveToDisplay: [PerDisplayShortcut]

    static let `default` = DisplayShortcutSettings(
        moveToPrimary: .empty,
        moveToNext: .empty,
        moveToPrevious: .empty,
        moveToOther: .empty,
        moveToDisplay: []
    )

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
        displays = result.sorted { $0.displayID < $1.displayID }
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
