import AppKit
import Carbon

extension AppState {

    func layoutShortcutConflictMessage(for shortcut: HotKeyShortcut, excluding presetID: UUID?) -> String? {
        // Check against configured window action shortcuts.
        if windowActionShortcutConflicts(with: shortcut) {
            return NSLocalizedString("This shortcut is already used for a window action.", comment: "Shortcut conflict with window action")
        }

        // Cmd+F is reserved for the window search field.
        if shortcut.keyCode == UInt32(kVK_ANSI_F),
           shortcut.modifiers == UInt32(cmdKey) {
            return NSLocalizedString("⌘F is reserved for searching the window list.", comment: "Cmd+F shortcut reserved for window search")
        }

        if shortcut == hotKeyShortcut {
            return NSLocalizedString("This shortcut is already used by the global shortcut.", comment: "Layout shortcut conflict with app global shortcut")
        }

        if layoutPresets.contains(where: { $0.id != presetID && $0.shortcuts.contains(shortcut) }) {
            return NSLocalizedString("This shortcut is already used by another layout.", comment: "Layout shortcut conflict with another layout")
        }

        if let preset = layoutPresets.first(where: { $0.id == presetID }), preset.shortcuts.contains(shortcut) {
            return NSLocalizedString("This shortcut is already assigned to this layout.", comment: "Layout shortcut duplicate within same layout")
        }

        if allDisplayShortcuts(isGlobal: shortcut.isGlobal).contains(shortcut) {
            return NSLocalizedString("This shortcut is already used by a display shortcut.", comment: "Layout shortcut conflict with display shortcut")
        }

        return nil
    }

    /// Returns a conflict message if the given display shortcut conflicts with existing shortcuts.
    /// `excludeKeyPath` identifies which slot is being edited so it can be excluded from the check.
    func displayShortcutConflictMessage(for shortcut: HotKeyShortcut, excludeKeyPath: String) -> String? {
        // Check reserved keys (same rules as layout shortcuts for local shortcuts).
        if !shortcut.isGlobal {
            // Check against configured window action shortcuts (excluding self).
            if !excludeKeyPath.hasPrefix("selectNextWindow") && !excludeKeyPath.hasPrefix("selectPreviousWindow") && !excludeKeyPath.hasPrefix("bringToFront") && !excludeKeyPath.hasPrefix("closeOrQuit") {
                if windowActionShortcutConflicts(with: shortcut) {
                    return NSLocalizedString("This shortcut is already used for a window action.", comment: "Shortcut conflict with window action")
                }
            }
            if shortcut.keyCode == UInt32(kVK_ANSI_F), shortcut.modifiers == UInt32(cmdKey) {
                return NSLocalizedString("⌘F is reserved for searching the window list.", comment: "Cmd+F shortcut reserved for window search")
            }
        }

        if shortcut == hotKeyShortcut {
            return NSLocalizedString("This shortcut is already used by the global shortcut.", comment: "Layout shortcut conflict with app global shortcut")
        }

        // Check layout presets.
        if layoutPresets.contains(where: { $0.shortcuts.contains(shortcut) }) {
            return NSLocalizedString("This shortcut is already used by a layout.", comment: "Display shortcut conflict with layout preset")
        }

        // Check other display shortcuts (excluding the current slot).
        let allSlots = allDisplayShortcutSlots(isGlobal: shortcut.isGlobal)
        for (keyPath, s) in allSlots where keyPath != excludeKeyPath {
            if s == shortcut {
                return NSLocalizedString("This shortcut is already used by another display shortcut.", comment: "Display shortcut conflict with another display shortcut")
            }
        }

        return nil
    }

    /// Collects all assigned display shortcuts (local or global).
    /// Returns true if the given shortcut conflicts with a configured window action shortcut
    /// (window cycling or bring to front).
    func windowActionShortcutConflicts(with shortcut: HotKeyShortcut) -> Bool {
        if displayShortcutSettings.selectNextWindow.localEnabled,
           let s = displayShortcutSettings.selectNextWindow.local, s == shortcut { return true }
        if displayShortcutSettings.selectPreviousWindow.localEnabled,
           let s = displayShortcutSettings.selectPreviousWindow.local, s == shortcut { return true }
        if displayShortcutSettings.bringToFront.localEnabled,
           let s = displayShortcutSettings.bringToFront.local, s == shortcut { return true }
        if displayShortcutSettings.closeOrQuit.localEnabled,
           let s = displayShortcutSettings.closeOrQuit.local, s == shortcut { return true }
        return false
    }

    func allDisplayShortcuts(isGlobal: Bool) -> [HotKeyShortcut] {
        allDisplayShortcutSlots(isGlobal: isGlobal).map(\.1)
    }

    /// Returns (keyPath identifier, shortcut) pairs for all assigned display shortcuts.
    func allDisplayShortcutSlots(isGlobal: Bool) -> [(String, HotKeyShortcut)] {
        var result: [(String, HotKeyShortcut)] = []
        let suffix = isGlobal ? ".global" : ".local"
        if let s = isGlobal ? displayShortcutSettings.moveToPrimary.global : displayShortcutSettings.moveToPrimary.local {
            result.append(("moveToPrimary\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.moveToNext.global : displayShortcutSettings.moveToNext.local {
            result.append(("moveToNext\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.moveToPrevious.global : displayShortcutSettings.moveToPrevious.local {
            result.append(("moveToPrevious\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.moveToOther.global : displayShortcutSettings.moveToOther.local {
            result.append(("moveToOther\(suffix)", s))
        }
        for entry in displayShortcutSettings.moveToDisplay {
            let key = "moveToDisplay.\(entry.fingerprint.vendorNumber).\(entry.fingerprint.modelNumber).\(entry.fingerprint.serialNumber).\(entry.occurrenceIndex)"
            if let s = isGlobal ? entry.shortcuts.global : entry.shortcuts.local {
                result.append(("\(key)\(suffix)", s))
            }
        }
        if let s = isGlobal ? displayShortcutSettings.selectNextWindow.global : displayShortcutSettings.selectNextWindow.local {
            result.append(("selectNextWindow\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.selectPreviousWindow.global : displayShortcutSettings.selectPreviousWindow.local {
            result.append(("selectPreviousWindow\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.bringToFront.global : displayShortcutSettings.bringToFront.local {
            result.append(("bringToFront\(suffix)", s))
        }
        if let s = isGlobal ? displayShortcutSettings.closeOrQuit.global : displayShortcutSettings.closeOrQuit.local {
            result.append(("closeOrQuit\(suffix)", s))
        }
        return result
    }

    func setShortcutRecordingActive(_ isActive: Bool) {
        if isActive {
            shortcutRecordingSessionCount += 1
            if shortcutRecordingSessionCount == 1 {
                unregisterAllHotKeys()
            }
            return
        }

        guard shortcutRecordingSessionCount > 0 else { return }
        shortcutRecordingSessionCount -= 1
        if shortcutRecordingSessionCount == 0 {
            registerAllHotKeys()
        }
    }

    // MARK: - HotKey Registration

    func installHotKeyHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            let appState = Unmanaged<AppState>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            // Release build: skip handling if a debug version is running.
            if appState.hotKeysYieldedToDebug || appState.isDebugVersionRunning {
                return noErr
            }
            if hotKeyID.id == 1 {
                debugLog("hotkey triggered")
                if appState.isEditingSettings {
                    return noErr
                }
                Task { @MainActor in
                    appState.toggleOverlay()
                }
            } else if let presetID = appState.presetHotKeyIDs[hotKeyID.id] {
                Task { @MainActor in
                    appState.applyLayoutPreset(id: presetID)
                }
            } else if let action = appState.displayHotKeyActions[hotKeyID.id] {
                Task { @MainActor in
                    appState.executeDisplayShortcutGlobal(action)
                }
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    func registerAllHotKeys() {
        guard !hotKeysYieldedToDebug else { return }
        guard shortcutRecordingSessionCount == 0 else { return }
        registerMainHotKey()
        registerPresetHotKeys()
        registerDisplayHotKeys()
    }

    func registerMainHotKey() {
        guard !hotKeysYieldedToDebug else { return }
        unregisterHotKey()
        let hotKeyID = EventHotKeyID(signature: OSType(0x44565659), id: 1)
        RegisterEventHotKey(
            hotKeyShortcut.keyCode,
            hotKeyShortcut.eventHotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func registerPresetHotKeys() {
        guard !hotKeysYieldedToDebug else { return }
        unregisterPresetHotKeys()
        var nextID: UInt32 = 100

        for preset in layoutPresets {
            for shortcut in preset.globalShortcuts {
                guard canEnableGlobalShortcut(for: shortcut) else { continue }
                let hotKeyID = EventHotKeyID(signature: OSType(0x54594c59), id: nextID)
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(
                    shortcut.keyCode,
                    shortcut.eventHotKeyModifiers,
                    hotKeyID,
                    GetApplicationEventTarget(),
                    0,
                    &ref
                )
                if status == noErr, let ref {
                    presetHotKeyRefs[nextID] = ref
                    presetHotKeyIDs[nextID] = preset.id
                    nextID += 1
                }
            }
        }
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    func unregisterPresetHotKeys() {
        for hotKeyRef in presetHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        presetHotKeyRefs.removeAll()
        presetHotKeyIDs.removeAll()
    }

    func unregisterAllHotKeys() {
        unregisterHotKey()
        unregisterPresetHotKeys()
        unregisterDisplayHotKeys()
    }

    func registerDisplayHotKeys() {
        guard !hotKeysYieldedToDebug else { return }
        unregisterDisplayHotKeys()
        var nextID: UInt32 = 200
        let signature = OSType(0x54594453) // "TYDS"

        func registerOne(_ shortcut: HotKeyShortcut?, action: DisplayHotKeyAction) {
            guard let shortcut, shortcut.isGlobal else { return }
            let hotKeyID = EventHotKeyID(signature: signature, id: nextID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.keyCode,
                shortcut.eventHotKeyModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                displayHotKeyRefs[nextID] = ref
                displayHotKeyActions[nextID] = action
            }
            nextID += 1
        }

        if displayShortcutSettings.moveToPrimary.globalEnabled {
            registerOne(displayShortcutSettings.moveToPrimary.global, action: .moveToPrimary)
        }
        if displayShortcutSettings.moveToNext.globalEnabled {
            registerOne(displayShortcutSettings.moveToNext.global, action: .moveToNext)
        }
        if displayShortcutSettings.moveToPrevious.globalEnabled {
            registerOne(displayShortcutSettings.moveToPrevious.global, action: .moveToPrevious)
        }
        if displayShortcutSettings.moveToOther.globalEnabled {
            registerOne(displayShortcutSettings.moveToOther.global, action: .moveToOther)
        }
        let resolver = DisplayFingerprintResolver()
        for entry in displayShortcutSettings.moveToDisplay {
            guard entry.shortcuts.globalEnabled,
                  let resolved = resolver.resolve(entry.fingerprint, occurrenceIndex: entry.occurrenceIndex) else { continue }
            registerOne(entry.shortcuts.global, action: .moveToDisplay(displayID: resolved.displayID))
        }
    }

    func unregisterDisplayHotKeys() {
        for ref in displayHotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        displayHotKeyRefs.removeAll()
        displayHotKeyActions.removeAll()
    }

    // MARK: - Debug/Release hotkey coordination

    static let debugBundleID = "one.cafebabe.tiley.debug"

    /// Returns true when a debug build of Tiley is running alongside this release build.
    var isDebugVersionRunning: Bool {
        #if DEBUG
        return false
        #else
        return !NSRunningApplication.runningApplications(withBundleIdentifier: Self.debugBundleID).isEmpty
        #endif
    }

    /// Release build: observe workspace app launch/terminate to yield hotkeys to the debug build.
    func installDebugHotKeyCoordination() {
        #if DEBUG
        // Debug version needs no coordination — it always owns hotkeys.
        #else
        if isDebugVersionRunning {
            hotKeysYieldedToDebug = true
        }
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(handleAppDidLaunch(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(handleAppDidTerminate(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
        #endif
    }

    #if !DEBUG
    @objc func handleAppDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.debugBundleID else { return }
        unregisterAllHotKeys()
        hotKeysYieldedToDebug = true
    }

    @objc func handleAppDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.debugBundleID else { return }
        hotKeysYieldedToDebug = false
        registerAllHotKeys()
    }
    #endif

    func canEnableGlobalShortcut(for shortcut: HotKeyShortcut) -> Bool {
        // Preset shortcuts accept non-modifier keys as well.
        // Keep only the hard conflict guard against Tiley's own main global shortcut.
        if shortcut == hotKeyShortcut {
            return false
        }
        return true
    }

    func sanitizePresetGlobalShortcutEligibility() {
        for presetIndex in layoutPresets.indices {
            sanitizeShortcutGlobalFlags(for: &layoutPresets[presetIndex])
        }
    }

    func sanitizeShortcutGlobalFlags(for preset: inout LayoutPreset) {
        for shortcutIndex in preset.shortcuts.indices {
            if preset.shortcuts[shortcutIndex].isGlobal,
               !canEnableGlobalShortcut(for: preset.shortcuts[shortcutIndex]) {
                preset.shortcuts[shortcutIndex].isGlobal = false
            }
        }
    }

    // MARK: - Modifier-held cycling (Cmd+Tab-like interaction)

    /// Installs global+local flagsChanged monitors to detect when the toggle
    /// modifier keys are released, enabling Cmd+Tab-like window cycling.
    func installModifierReleaseMonitor() {
        let toggleMods = hotKeyShortcut.modifiers
        guard toggleMods != 0 else { return }

        removeModifierReleaseMonitor()

        let handler: (NSEvent) -> Void = { [weak self] event in
            guard let self else { return }
            let currentMods = HotKeyShortcut.carbonModifiers(from: event.modifierFlags)
            if (currentMods & toggleMods) != toggleMods {
                // Toggle modifiers released — confirm the current selection.
                Task { @MainActor in
                    self.confirmModifierHeldSelection()
                }
            }
        }

        modifierReleaseGlobalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged, handler: handler
        )
        modifierReleaseLocalMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { event in
            handler(event)
            return event
        }
        isModifierHeldMode = true
    }

    /// Removes the modifier-release monitors and exits modifier-held mode.
    func removeModifierReleaseMonitor() {
        if let monitor = modifierReleaseGlobalMonitor {
            NSEvent.removeMonitor(monitor)
            modifierReleaseGlobalMonitor = nil
        }
        if let monitor = modifierReleaseLocalMonitor {
            NSEvent.removeMonitor(monitor)
            modifierReleaseLocalMonitor = nil
        }
        isModifierHeldMode = false
        hasActedDuringModifierHeld = false
    }

    /// Called when the user releases the toggle modifiers.
    /// If the user interacted (cycled windows or applied a layout), confirms
    /// the current selection. Otherwise just exits modifier-held mode.
    func confirmModifierHeldSelection() {
        guard isShowingLayoutGrid else {
            removeModifierReleaseMonitor()
            return
        }
        let acted = hasActedDuringModifierHeld
        removeModifierReleaseMonitor()

        guard acted else { return }

        if selectedWindowIndices.count > 1 {
            raiseSelectedWindows()
        } else {
            raiseCurrentTargetWindow()
        }
    }

    /// Returns a copy of `shortcut` with the toggle modifier keys stripped,
    /// or nil if not in modifier-held mode or stripping changes nothing.
    func strippedShortcut(_ shortcut: HotKeyShortcut) -> HotKeyShortcut? {
        guard isModifierHeldMode else { return nil }
        let stripped = shortcut.modifiers & ~hotKeyShortcut.modifiers
        guard stripped != shortcut.modifiers else { return nil }
        return HotKeyShortcut(keyCode: shortcut.keyCode, modifiers: stripped)
    }
}
