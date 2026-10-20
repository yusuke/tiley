import AppKit
import ApplicationServices
import CoreGraphics

// MARK: - Space mover
//
// Moves another app's window to a different Mission Control space.
//
// The direct SkyLight calls (SLSMoveWindowsToManagedSpace, and the
// SLSSpaceSetCompatID + SLSSetWindowListWorkspace workaround) only work on
// windows owned by the caller's own connection since macOS 14.5, so they
// can't move other apps' windows without disabling SIP. Instead this uses the
// "drag trick": hold the window by its title bar with a synthesized mouse-down
// and press the system "Move left/right a space" shortcut. The window server
// carries a dragged window along to the new space, exactly as when the user
// drags a window and presses ⌃→ themselves.

/// The spaces on one display, in Mission Control order.
struct DisplaySpaces {
    let displayUUID: String
    /// All spaces on the display, including full-screen spaces, in order.
    let spaces: [SpaceInfo]
    let currentSpaceID: UInt64?

    /// Normal (non-full-screen) desktops — the valid move destinations.
    var desktops: [SpaceInfo] { spaces.filter { !$0.isFullScreen } }
}

/// A keyboard shortcut read from the system's symbolic hotkeys.
struct SpaceSwitchShortcut: Equatable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    /// The modifiers that decide whether a key press is this shortcut. Arrow
    /// keys also carry the function and numeric-pad flags, which are ignored.
    static let significantFlags: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]

    /// True when a key-down with this key code and these flags triggers the shortcut.
    func matches(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        keyCode == self.keyCode
            && flags.intersection(Self.significantFlags) == self.flags.intersection(Self.significantFlags)
    }
}

/// What a system space-switch shortcut does.
enum SpaceSwitchKind: Equatable {
    /// "Move left/right a space".
    case step(right: Bool)
    /// "Switch to Desktop N" (numbered across all displays).
    case desktop(Int)
}

enum SpaceMoveError: Error {
    case spacesUnavailable
    case shortcutDisabled
    case windowNotFound
    case windowNotOnCurrentSpace
    case spaceSwitchTimedOut
    case windowDidNotMove
    /// No point on the window's top edge started a window drag.
    case noDraggableArea
}

enum SpaceMover {

    // MARK: - Space lookup

    /// Mission Control's identifier for a display ("Display Identifier" in
    /// CGSCopyManagedDisplaySpaces output).
    static func displayUUID(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Returns the spaces on the given display. When "Displays have separate
    /// Spaces" is off there is a single "Main" entry shared by all displays.
    static func spaces(forDisplayID displayID: CGDirectDisplayID) -> DisplaySpaces? {
        let map = AccessibilityService.buildSpaceMap()
        guard map.isAvailable, !map.spaceList.isEmpty else { return nil }

        let uuids = Set(map.spaceList.map(\.displayUUID))
        let uuid: String
        if let own = displayUUID(for: displayID), uuids.contains(where: { $0.caseInsensitiveCompare(own) == .orderedSame }) {
            uuid = uuids.first { $0.caseInsensitiveCompare(own) == .orderedSame }!
        } else if uuids.count == 1, let only = uuids.first {
            uuid = only
        } else {
            return nil
        }

        let spaces = map.spaceList.filter { $0.displayUUID == uuid }
        return DisplaySpaces(
            displayUUID: uuid,
            spaces: spaces,
            currentSpaceID: spaces.first(where: \.isCurrent)?.id
        )
    }

    /// The space the given window lives on, or nil when unknown.
    static func spaceID(ofWindow windowID: CGWindowID) -> UInt64? {
        AccessibilityService.buildWindowSpaceMap(windowIDs: [windowID])[windowID]
    }

    /// App icons per space for the given spaces, front-most window first,
    /// one entry per app.
    static func appsBySpace(spaceIDs: Set<UInt64>) -> [UInt64: [NSRunningApplication]] {
        let options = CGWindowListOption([.optionAll, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [:] }
        let myPID = getpid()

        var windowPIDs: [(CGWindowID, pid_t)] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != myPID,
                  let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
                  (bounds["Width"] ?? 0) > 100, (bounds["Height"] ?? 0) > 100 else { continue }
            windowPIDs.append((wid, pid))
        }

        let spaceMap = AccessibilityService.buildWindowSpaceMap(windowIDs: windowPIDs.map(\.0))
        var result: [UInt64: [NSRunningApplication]] = [:]
        var seen: [UInt64: Set<pid_t>] = [:]
        for (wid, pid) in windowPIDs {
            guard let space = spaceMap[wid], spaceIDs.contains(space),
                  !seen[space, default: []].contains(pid),
                  let app = NSRunningApplication(processIdentifier: pid),
                  app.activationPolicy == .regular else { continue }
            seen[space, default: []].insert(pid)
            result[space, default: []].append(app)
        }
        return result
    }

    // MARK: - System shortcuts

    /// Symbolic hotkey IDs for Mission Control's "Move left/right a space".
    private static let moveLeftHotKeyID = "79"
    private static let moveRightHotKeyID = "81"

    /// Symbolic hotkey ID for "Switch to Desktop 1"; Desktop N is 117 + N.
    private static let firstDesktopHotKeyID = 118
    /// Mission Control offers "Switch to Desktop N" shortcuts for 1–16.
    private static let maxDesktopHotKeys = 16

    /// State of one entry in com.apple.symbolichotkeys.
    private enum SymbolicHotKey {
        /// No entry — the user never changed it from the system default.
        case absent
        case disabled
        case enabled(SpaceSwitchShortcut)
        /// Enabled, but without a key assigned.
        case unassigned
    }

    private static func symbolicHotKey(id: Int) -> SymbolicHotKey {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                  "com.apple.symbolichotkeys" as CFString) as? [String: Any],
              let entry = all[String(id)] as? [String: Any] else {
            return .absent
        }
        if let enabled = entry["enabled"] as? Bool, !enabled { return .disabled }
        guard let value = entry["value"] as? [String: Any],
              let params = value["parameters"] as? [NSNumber], params.count >= 3,
              params[1].intValue != 65535 else {
            return .unassigned
        }
        return .enabled(SpaceSwitchShortcut(
            keyCode: CGKeyCode(params[1].uint16Value),
            flags: CGEventFlags(rawValue: params[2].uint64Value)
        ))
    }

    /// Reads the user's "Move left/right a space" shortcut. Returns nil when the
    /// user has turned it off in System Settings › Keyboard › Keyboard Shortcuts.
    static func spaceSwitchShortcut(right: Bool) -> SpaceSwitchShortcut? {
        // ⌃← / ⌃→ (arrow keys carry the function and numeric-pad flags).
        let defaultShortcut = SpaceSwitchShortcut(
            keyCode: right ? 124 : 123,
            flags: [.maskControl, .maskSecondaryFn]
        )
        switch symbolicHotKey(id: Int(right ? moveRightHotKeyID : moveLeftHotKeyID)!) {
        case .absent, .unassigned: return defaultShortcut // the system default is on
        case .disabled: return nil
        case .enabled(let shortcut): return shortcut
        }
    }

    /// The user's "Switch to Desktop N" shortcut, or nil when it is off or
    /// was never set up (those are off by default).
    static func desktopShortcut(number: Int) -> SpaceSwitchShortcut? {
        guard (1...maxDesktopHotKeys).contains(number) else { return nil }
        if case .enabled(let shortcut) = symbolicHotKey(id: firstDesktopHotKeyID + number - 1) {
            return shortcut
        }
        return nil
    }

    /// Every space-switch shortcut that is currently on.
    static func activeSwitchShortcuts() -> [(shortcut: SpaceSwitchShortcut, kind: SpaceSwitchKind)] {
        var result: [(SpaceSwitchShortcut, SpaceSwitchKind)] = []
        for right in [false, true] {
            if let s = spaceSwitchShortcut(right: right) { result.append((s, .step(right: right))) }
        }
        for n in 1...maxDesktopHotKeys {
            if let s = desktopShortcut(number: n) { result.append((s, .desktop(n))) }
        }
        return result
    }

    /// The N in "Switch to Desktop N" for a space. Mission Control numbers
    /// desktops across all displays in order, skipping full-screen spaces.
    static func desktopShortcutNumber(of spaceID: UInt64) -> Int? {
        let desktops = AccessibilityService.buildSpaceMap().spaceList.filter { !$0.isFullScreen }
        return desktops.firstIndex(where: { $0.id == spaceID }).map { $0 + 1 }
    }

    /// How one display's desktops map onto the system "Switch to Desktop N"
    /// shortcuts.
    struct DesktopShortcutCoverage: Equatable {
        let displayName: String
        /// System Settings numbers of this display's desktops ("Desktop 11–15").
        let desktopNumbers: [Int]
        /// Numbers with no usable shortcut (off, no key, or above 16).
        let missing: [Int]
    }

    /// Per-display shortcut coverage, in Mission Control order. Empty when
    /// space information is unavailable.
    static func desktopShortcutCoverage() -> [DesktopShortcutCoverage] {
        let map = AccessibilityService.buildSpaceMap()
        guard map.isAvailable else { return [] }

        var displayOrder: [String] = []
        for space in map.spaceList where !displayOrder.contains(space.displayUUID) {
            displayOrder.append(space.displayUUID)
        }
        var number = 0
        return displayOrder.map { uuid in
            let numbers = map.spaceList
                .filter { $0.displayUUID == uuid && !$0.isFullScreen }
                .map { _ -> Int in number += 1; return number }
            let screen = NSScreen.screens.first {
                displayUUID(for: $0.displayID)?.caseInsensitiveCompare(uuid) == .orderedSame
            }
            return DesktopShortcutCoverage(
                displayName: screen?.localizedName
                    ?? NSLocalizedString("All Displays", comment: "Spaces shared by all displays"),
                desktopNumbers: numbers,
                missing: numbers.filter { desktopShortcut(number: $0) == nil }
            )
        }
    }

    /// Formats sorted numbers as ranges: [1, 2, 3, 5, 7, 8] → "1–3, 5, 7–8".
    static func formatRanges(_ numbers: [Int]) -> String {
        var parts: [String] = []
        var index = 0
        while index < numbers.count {
            var end = index
            while end + 1 < numbers.count, numbers[end + 1] == numbers[end] + 1 { end += 1 }
            parts.append(end == index ? "\(numbers[index])" : "\(numbers[index])–\(numbers[end])")
            index = end + 1
        }
        return parts.joined(separator: ", ")
    }

    /// Highest desktop number macOS offers a "Switch to Desktop N" shortcut for.
    static var maxDesktopShortcutNumber: Int { maxDesktopHotKeys }

    // MARK: - Turning on desktop shortcuts

    /// Number-row key codes for the digits 1–9, then 0.
    private static let digitKeyCodes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
    private static let controlModifier: UInt32 = 0x40000
    private static let optionModifier: UInt32 = 0x80000

    /// A "Switch to Desktop N" shortcut Tiley can turn on.
    struct DesktopShortcutPlan: Equatable {
        let desktopNumber: Int
        let keyCode: UInt16
        let modifiers: UInt32

        /// "⌃3", "⌃⌥2".
        var keyLabel: String {
            var label = ""
            if modifiers & controlModifier != 0 { label += "⌃" }
            if modifiers & optionModifier != 0 { label += "⌥" }
            if modifiers & 0x20000 != 0 { label += "⇧" }
            if modifiers & 0x100000 != 0 { label += "⌘" }
            if let digit = digitKeyCodes.firstIndex(of: keyCode) {
                label += digit == 9 ? "0" : String(digit + 1)
            } else {
                label += "#\(keyCode)"
            }
            return label
        }
    }

    /// macOS's default key for "Switch to Desktop N": ⌃1–⌃9, ⌃0 for 10,
    /// then ⌃⌥1–⌃⌥6 for 11–16.
    static func defaultDesktopShortcut(number: Int) -> (keyCode: UInt16, modifiers: UInt32)? {
        switch number {
        case 1...10: return (digitKeyCodes[number - 1], controlModifier)
        case 11...maxDesktopHotKeys: return (digitKeyCodes[number - 11], controlModifier | optionModifier)
        default: return nil
        }
    }

    /// Plans shortcuts for the given desktop numbers, keeping any key the user
    /// already assigned. Desktops above 16, and desktops whose key is already
    /// used by another enabled system shortcut, are returned in `skipped`.
    static func planDesktopShortcuts(for numbers: [Int]) -> (plans: [DesktopShortcutPlan], skipped: [Int]) {
        let all = symbolicHotKeyEntries()
        var plans: [DesktopShortcutPlan] = []
        var skipped: [Int] = []
        // Keys taken by other enabled shortcuts: "keyCode-modifiers".
        var taken = Set(all.compactMap { id, entry -> String? in
            guard entry.enabled, let key = entry.keyCode, let mods = entry.modifiers else { return nil }
            return "\(id):\(key)-\(mods)"
        })
        for number in numbers {
            let id = firstDesktopHotKeyID + number - 1
            guard number <= maxDesktopHotKeys else { skipped.append(number); continue }
            let existing = all[id]
            let key: UInt16
            let mods: UInt32
            if let k = existing?.keyCode, let m = existing?.modifiers {
                (key, mods) = (k, m)
            } else if let d = defaultDesktopShortcut(number: number) {
                (key, mods) = (d.keyCode, d.modifiers)
            } else {
                skipped.append(number); continue
            }
            let conflict = taken.contains { $0.hasSuffix(":\(key)-\(mods)") && !$0.hasPrefix("\(id):") }
            guard !conflict else { skipped.append(number); continue }
            taken.insert("\(id):\(key)-\(mods)")
            plans.append(DesktopShortcutPlan(desktopNumber: number, keyCode: key, modifiers: mods))
        }
        return (plans, skipped)
    }

    /// Turns on the planned shortcuts: saves them to the system preference
    /// (so System Settings shows them and they survive a logout) and applies
    /// them to the running session.
    static func enableDesktopShortcuts(_ plans: [DesktopShortcutPlan]) {
        guard !plans.isEmpty else { return }
        let domain = "com.apple.symbolichotkeys" as CFString
        let key = "AppleSymbolicHotKeys" as CFString
        CFPreferencesAppSynchronize(domain)
        var all = (CFPreferencesCopyAppValue(key, domain) as? [String: Any]) ?? [:]
        for plan in plans {
            let id = firstDesktopHotKeyID + plan.desktopNumber - 1
            all[String(id)] = [
                "enabled": true,
                "value": [
                    "parameters": [65535, Int(plan.keyCode), Int(plan.modifiers)],
                    "type": "standard",
                ] as [String: Any],
            ] as [String: Any]
            CGSPrivate.setSymbolicHotKey(Int32(id), keyCode: plan.keyCode, modifiers: plan.modifiers, enabled: true)
        }
        CFPreferencesSetValue(key, all as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize(domain)
        debugLog("enableDesktopShortcuts: \(plans.map { "\($0.desktopNumber)=\($0.keyLabel)" })")
    }

    private struct SymbolicHotKeyEntry {
        let enabled: Bool
        let keyCode: UInt16?
        let modifiers: UInt32?
    }

    private static func symbolicHotKeyEntries() -> [Int: SymbolicHotKeyEntry] {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        guard let all = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                  "com.apple.symbolichotkeys" as CFString) as? [String: Any] else { return [:] }
        var result: [Int: SymbolicHotKeyEntry] = [:]
        for (idString, raw) in all {
            guard let id = Int(idString), let entry = raw as? [String: Any] else { continue }
            let params = (entry["value"] as? [String: Any])?["parameters"] as? [NSNumber]
            let assigned = (params?.count ?? 0) >= 3 && params![1].intValue != 65535
            result[id] = SymbolicHotKeyEntry(
                enabled: entry["enabled"] as? Bool ?? false,
                keyCode: assigned ? params![1].uint16Value : nil,
                modifiers: assigned ? params![2].uint32Value : nil
            )
        }
        return result
    }

    /// Opens System Settings at Keyboard › Keyboard Shortcuts, where the
    /// Mission Control space shortcuts live.
    static func openMissionControlShortcutSettings() {
        let shortcuts = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")!
        let keyboard = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!
        if !NSWorkspace.shared.open(shortcuts) {
            NSWorkspace.shared.open(keyboard)
        }
    }

    /// True when both directions can be driven by Tiley.
    static var canSwitchSpaces: Bool {
        spaceSwitchShortcut(right: false) != nil && spaceSwitchShortcut(right: true) != nil
    }

    // MARK: - Move

    /// Delay between space switches once the current space has changed, so
    /// the next key press doesn't land mid-animation.
    private static let switchSettleDelay: UInt64 = 350_000_000
    private static let switchTimeout: TimeInterval = 2.0

    /// Moves the window to `targetSpaceID` on `displayID`. The user ends up on
    /// the destination space, as when dragging a window there by hand.
    @MainActor
    static func moveWindow(
        windowID: CGWindowID,
        pid: pid_t,
        windowElement: AXUIElement?,
        toSpace targetSpaceID: UInt64,
        displayID: CGDirectDisplayID
    ) async -> Result<Void, SpaceMoveError> {
        guard windowID != 0 else { return .failure(.windowNotFound) }
        guard let initial = spaces(forDisplayID: displayID) else { return .failure(.spacesUnavailable) }
        guard spaceID(ofWindow: windowID) != targetSpaceID else { return .success(()) }

        // Bring the window forward so the synthesized click lands on it. For a
        // window on another space this also switches to that space.
        NSRunningApplication(processIdentifier: pid)?.activate()
        try? await Task.sleep(nanoseconds: 50_000_000)
        if let windowElement {
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        }
        let windowSpace = spaceID(ofWindow: windowID)
        if windowSpace != initial.currentSpaceID {
            let reached = await waitUntil(timeout: switchTimeout) {
                spaces(forDisplayID: displayID)?.currentSpaceID == windowSpace
            }
            guard reached else { return .failure(.windowNotOnCurrentSpace) }
            try? await Task.sleep(nanoseconds: switchSettleDelay)
        }

        guard let display = spaces(forDisplayID: displayID),
              let currentIndex = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }),
              let targetIndex = display.spaces.firstIndex(where: { $0.id == targetSpaceID }) else {
            return .failure(.spacesUnavailable)
        }
        guard targetIndex != currentIndex else { return .success(()) }

        // Prefer one "Switch to Desktop N" press; otherwise step with ⌃←/⌃→.
        let desktopNumber = desktopShortcutNumber(of: targetSpaceID)
        let directShortcut = desktopNumber.flatMap { desktopShortcut(number: $0) }
        if directShortcut == nil, spaceSwitchShortcut(right: targetIndex > currentIndex) == nil {
            return .failure(.shortcutDisabled)
        }

        guard cgBounds(of: windowID) != nil else { return .failure(.windowNotFound) }
        debugLog("SpaceMover: wid=\(windowID) from=\(currentIndex) to=\(targetIndex) desktopN=\(desktopNumber.map(String.init) ?? "nil") direct=\(directShortcut.map { "key=\($0.keyCode) flags=0x\(String($0.flags.rawValue, radix: 16))" } ?? "off")")

        var held: HeldWindow
        switch await holdWindow(windowID: windowID, pid: pid) {
        case .success(let h): held = h
        case .failure(let error): return .failure(error)
        }
        let source = held.source

        var failure: SpaceMoveError?
        var arrived = false
        if let directShortcut {
            postKey(directShortcut, source: source)
            arrived = await waitUntil(timeout: switchTimeout) {
                spaces(forDisplayID: displayID)?.currentSpaceID == targetSpaceID
            }
            debugLog("SpaceMover: direct jump \(arrived ? "reached target" : "missed; falling back to arrows")")
            if arrived {
                try? await Task.sleep(nanoseconds: switchSettleDelay)
            }
        }

        // Step from wherever the display is now (a missed jump may have moved it).
        while !arrived {
            guard let live = spaces(forDisplayID: displayID),
                  let liveIndex = live.spaces.firstIndex(where: { $0.id == live.currentSpaceID }),
                  let liveTarget = live.spaces.firstIndex(where: { $0.id == targetSpaceID }) else {
                failure = .spacesUnavailable
                break
            }
            if liveIndex == liveTarget {
                arrived = true
                break
            }
            let right = liveTarget > liveIndex
            guard let arrow = spaceSwitchShortcut(right: right) else {
                failure = .shortcutDisabled
                break
            }
            let expectedID = live.spaces[liveIndex + (right ? 1 : -1)].id
            postKey(arrow, source: source)
            let switched = await waitUntil(timeout: switchTimeout) {
                spaces(forDisplayID: displayID)?.currentSpaceID == expectedID
            }
            guard switched else {
                failure = .spaceSwitchTimedOut
                break
            }
            try? await Task.sleep(nanoseconds: switchSettleDelay)
            held.keepAlive(towardsRight: right)
        }

        await release(held)

        if let failure {
            debugLog("SpaceMover: failed \(failure)")
            return .failure(failure)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let finalSpace = spaceID(ofWindow: windowID)
        debugLog("SpaceMover: window now on space \(finalSpace.map(String.init) ?? "nil") target=\(targetSpaceID)")
        guard finalSpace == targetSpaceID else { return .failure(.windowDidNotMove) }

        if let windowElement {
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        }
        return .success(())
    }

    // MARK: - Carrying a window through a switch

    /// Holds the window by its top edge, presses `shortcut` (a space-switch
    /// key the user pressed and Tiley swallowed), and lets go once the display
    /// has landed on another space. The window rides along in the same
    /// animation. Returns the space the display ended on.
    ///
    /// When the window can't be held, the shortcut is still pressed so the
    /// user's switch happens; the result is then `.failure`.
    @MainActor
    static func carryWindow(
        windowID: CGWindowID,
        pid: pid_t,
        windowElement: AXUIElement?,
        pressing shortcut: SpaceSwitchShortcut,
        displayID: CGDirectDisplayID
    ) async -> Result<UInt64, SpaceMoveError> {
        guard let startSpace = spaces(forDisplayID: displayID)?.currentSpaceID else {
            postKey(shortcut, source: CGEventSource(stateID: .hidSystemState))
            return .failure(.spacesUnavailable)
        }
        // Bring it above the app's other windows so the grab lands on it.
        // Activating the app could switch to another of its spaces, so
        // only raise; the grab's hit-test skips points covered by other apps.
        if let windowElement {
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        }

        let hold = await holdWindow(windowID: windowID, pid: pid)
        // holdWindow waits for the user to let go of the modifiers. If they
        // switched again meanwhile (repeat presses pass through), replaying
        // the swallowed press would overshoot; leave the window to the
        // catch-up follow instead.
        if spaces(forDisplayID: displayID)?.currentSpaceID != startSpace {
            if case .success(let held) = hold { await release(held) }
            return .failure(.windowNotOnCurrentSpace)
        }
        let held: HeldWindow
        switch hold {
        case .success(let h):
            held = h
        case .failure(let error):
            postKey(shortcut, source: CGEventSource(stateID: .hidSystemState))
            return .failure(error)
        }

        postKey(shortcut, source: held.source)
        var landed: UInt64?
        let switched = await waitUntil(timeout: switchTimeout) {
            guard let now = spaces(forDisplayID: displayID)?.currentSpaceID, now != startSpace else { return false }
            landed = now
            return true
        }
        if switched {
            try? await Task.sleep(nanoseconds: switchSettleDelay)
        }
        await release(held)

        guard switched, let landed else {
            debugLog("SpaceMover: carry wid=\(windowID) — the switch never happened")
            return .failure(.spaceSwitchTimedOut)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        guard spaceID(ofWindow: windowID) == landed else {
            debugLog("SpaceMover: carry wid=\(windowID) — the window stayed behind")
            return .failure(.windowDidNotMove)
        }
        if let windowElement {
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        }
        return .success(landed)
    }

    // MARK: - Holding a window

    /// A window held by a synthesized title-bar mouse-down.
    struct HeldWindow {
        let windowID: CGWindowID
        /// Where the mouse button went down.
        let grab: CGPoint
        /// The current (nudged) cursor position of the drag.
        var dragPoint: CGPoint
        let source: CGEventSource?
        /// The user's cursor position before the grab, restored on release.
        let savedCursor: CGPoint?

        /// Nudges the drag so the window stays attached across a switch.
        mutating func keepAlive(towardsRight right: Bool) {
            dragPoint.x += right ? 1 : -1
            SpaceMover.postMouse(.leftMouseDragged, at: dragPoint, source: source)
        }
    }

    /// Presses the mouse on the window's top edge, trying points until one
    /// actually drags the window. Waits for physically held modifiers to be
    /// released first, since they would merge into the synthesized events.
    @MainActor
    static func holdWindow(windowID: CGWindowID, pid: pid_t) async -> Result<HeldWindow, SpaceMoveError> {
        _ = await waitUntil(timeout: 2.0) {
            CGEventSource.flagsState(.hidSystemState)
                .intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty
        }
        guard let bounds = cgBounds(of: windowID) else { return .failure(.windowNotFound) }

        let source = CGEventSource(stateID: .hidSystemState)
        let savedCursor = CGEvent(source: nil)?.location

        // Apps that draw their own title bar (Chrome's tab strip) ignore
        // window drags over tabs and controls.
        for candidate in grabCandidates(bounds: bounds, pid: pid).prefix(maxGrabAttempts) {
            if await beginWindowDrag(windowID: windowID, at: candidate, source: source) {
                return .success(HeldWindow(
                    windowID: windowID,
                    grab: candidate,
                    dragPoint: CGPoint(x: candidate.x + grabProbeDistance, y: candidate.y),
                    source: source,
                    savedCursor: savedCursor
                ))
            }
        }
        if let savedCursor { CGWarpMouseCursorPosition(savedCursor) }
        debugLog("SpaceMover: no point on the top edge dragged the window")
        return .failure(.noDraggableArea)
    }

    /// Lets go of a held window and puts the cursor back.
    @MainActor
    static func release(_ held: HeldWindow) async {
        // Return to the grab point before releasing so the keep-alive nudges
        // don't shift the window sideways.
        postMouse(.leftMouseDragged, at: held.grab, source: held.source)
        try? await Task.sleep(nanoseconds: 50_000_000)
        postMouse(.leftMouseUp, at: held.grab, source: held.source)
        if let savedCursor = held.savedCursor {
            try? await Task.sleep(nanoseconds: 50_000_000)
            CGWarpMouseCursorPosition(savedCursor)
        }
    }

    // MARK: - Helpers

    /// Stamped into every event Tiley synthesizes (eventSourceUserData), so
    /// Tiley's own event taps can tell them from the user's.
    static let syntheticEventMarker: Int64 = 0x5449_4C59 // "TILY"

    /// Window bounds in CoreGraphics (top-left origin) coordinates.
    private static func cgBounds(of windowID: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]],
              let info = list.first,
              let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict)
    }

    /// AX roles of controls that would swallow a click instead of starting a
    /// window drag.
    private static let interactiveRoles: Set<String> = [
        kAXButtonRole, kAXTextFieldRole, kAXPopUpButtonRole, kAXMenuButtonRole,
        kAXCheckBoxRole, kAXRadioButtonRole, "AXSegmentedControl", kAXComboBoxRole,
        "AXSearchField", kAXTabGroupRole, kAXSliderRole, kAXIncrementorRole,
        kAXTextAreaRole, "AXLink",
    ]

    /// How many top-edge points to try before giving up.
    private static let maxGrabAttempts = 8
    /// How far the probe drag moves the window (points).
    private static let grabProbeDistance: CGFloat = 3

    /// Points on the top edge to try, best first, skipping ones over controls
    /// the accessibility hit-test can see. The centre suits standard title
    /// bars; the right end suits tab strips, which keep empty space there.
    private static func grabCandidates(bounds: CGRect, pid: pid_t) -> [CGPoint] {
        let systemWide = AXUIElementCreateSystemWide()
        // (x, distance from the top). The thin strip above Chrome's tabs is
        // draggable, so the centre is tried at 4 pt before moving sideways.
        let spots: [(CGFloat, CGFloat)] = [
            (bounds.midX, 8), (bounds.midX, 4),
            (bounds.maxX - 80, 8), (bounds.maxX - 130, 8), (bounds.maxX - 200, 8),
            (bounds.minX + bounds.width * 0.3, 8), (bounds.minX + bounds.width * 0.7, 8),
            (bounds.maxX - 80, 4),
        ]
        var preferred: [CGPoint] = []
        var result: [CGPoint] = []
        for (x, dy) in spots where x > bounds.minX + 80 && x < bounds.maxX - 10 {
            do {
                let point = CGPoint(x: x, y: bounds.minY + dy)
                var element: AXUIElement?
                var role = "?"
                var subrole = ""
                if AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &element) == .success,
                   let element {
                    var elementPID: pid_t = 0
                    AXUIElementGetPid(element, &elementPID)
                    guard elementPID == pid else { continue }
                    var value: CFTypeRef?
                    if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success {
                        role = value as? String ?? "?"
                    }
                    if AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success {
                        subrole = value as? String ?? ""
                    }
                }
                let skip = interactiveRoles.contains(role) || subrole == "AXTabButton"
                debugLog("SpaceMover: candidate \(point) role=\(role) subrole=\(subrole)\(skip ? " (skipped)" : "")")
                if skip { continue }
                // Window-frame elements are known to drag the window; try
                // them before anything else (e.g. Chrome's tab strip).
                if frameRoles.contains(role) {
                    preferred.append(point)
                } else {
                    result.append(point)
                }
            }
        }
        return preferred + result
    }

    /// AX roles of window-frame areas that drag the window when pressed.
    private static let frameRoles: Set<String> = [kAXToolbarRole, kAXWindowRole]

    /// Presses at `point` and nudges the cursor. Returns true when the window
    /// follows (the button stays down); otherwise releases where it pressed.
    @MainActor
    private static func beginWindowDrag(windowID: CGWindowID, at point: CGPoint, source: CGEventSource?) async -> Bool {
        guard let before = cgBounds(of: windowID) else { return false }
        postMouse(.mouseMoved, at: point, source: source)
        try? await Task.sleep(nanoseconds: 30_000_000)
        postMouse(.leftMouseDown, at: point, source: source)
        try? await Task.sleep(nanoseconds: 80_000_000)
        postMouse(.leftMouseDragged, at: CGPoint(x: point.x + grabProbeDistance, y: point.y), source: source)
        let moved = await waitUntil(timeout: 0.25) {
            guard let now = cgBounds(of: windowID) else { return false }
            return abs(now.minX - before.minX - grabProbeDistance) < 1.5
        }
        debugLog("SpaceMover: grab at \(point) \(moved ? "holds the window" : "did not move it")")
        if !moved {
            postMouse(.leftMouseDragged, at: point, source: source)
            postMouse(.leftMouseUp, at: point, source: source)
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return moved
    }

    private static func postMouse(_ type: CGEventType, at point: CGPoint, source: CGEventSource?) {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: .left) else { return }
        event.flags = []
        event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        event.post(tap: .cghidEventTap)
    }

    private static func postKey(_ shortcut: SpaceSwitchShortcut, source: CGEventSource?) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: down) else { continue }
            event.flags = shortcut.flags
            event.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Polls `condition` every 30 ms until it holds or `timeout` elapses.
    @MainActor
    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 30_000_000)
        }
        return condition()
    }
}
