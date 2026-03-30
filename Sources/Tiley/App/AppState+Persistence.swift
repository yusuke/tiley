import AppKit
import Carbon
import ServiceManagement

enum UserDefaultsKey {
    static let columns = "gridColumns"
    static let rows = "gridRows"
    static let gap = "gridGap"
    static let hotKeyCode = "globalHotKeyCode"
    static let hotKeyModifiers = "globalHotKeyModifiers"
    static let layoutPresets = "layoutPresets"
    static let didPromptLaunchAtLogin = "didPromptLaunchAtLogin"
    static let menuIconVisible = "menuIconVisible"
    static let dockIconVisible = "dockIconVisible"
    static let windowListSidebarVisible = "windowListSidebarVisible"
    static let quitAppOnLastWindowClose = "quitAppOnLastWindowClose"
    static let enableDebugLog = "enableDebugLog"
    static let debugSimulateUpdate = "debugSimulateUpdate"
    static let displayShortcuts = "displayShortcuts"
}

extension AppState {

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
        updateLaunchAtLogin(enabled: enabled, updateMessageOnFailure: true)
    }

    func loadSettings() {
        let defaults = UserDefaults.standard
        let storedColumns = defaults.integer(forKey: UserDefaultsKey.columns)
        let storedRows = defaults.integer(forKey: UserDefaultsKey.rows)
        let storedGap = defaults.object(forKey: UserDefaultsKey.gap) as? Double
        let storedHotKeyCode = defaults.object(forKey: UserDefaultsKey.hotKeyCode) as? Int
        let storedHotKeyModifiers = defaults.object(forKey: UserDefaultsKey.hotKeyModifiers) as? Int

        if storedColumns != 0 {
            columns = storedColumns
        }
        if storedRows != 0 {
            rows = storedRows
        }
        if let storedGap {
            gap = CGFloat(storedGap)
        }
        if let storedHotKeyCode, let storedHotKeyModifiers {
            hotKeyShortcut = HotKeyShortcut(
                keyCode: UInt32(storedHotKeyCode),
                modifiers: UInt32(storedHotKeyModifiers)
            )
        }
        if let storedMenuIconVisible = defaults.object(forKey: UserDefaultsKey.menuIconVisible) as? Bool {
            menuIconVisible = storedMenuIconVisible
        }
        if let storedDockIconVisible = defaults.object(forKey: UserDefaultsKey.dockIconVisible) as? Bool {
            dockIconVisible = storedDockIconVisible
        } else {
            dockIconVisible = false
        }
        if let storedQuitAppOnLastWindowClose = defaults.object(forKey: UserDefaultsKey.quitAppOnLastWindowClose) as? Bool {
            quitAppOnLastWindowClose = storedQuitAppOnLastWindowClose
        }
        if let storedEnableDebugLog = defaults.object(forKey: UserDefaultsKey.enableDebugLog) as? Bool {
            enableDebugLog = storedEnableDebugLog
        }
        if let storedDebugSimulateUpdate = defaults.object(forKey: UserDefaultsKey.debugSimulateUpdate) as? Bool {
            debugSimulateUpdate = storedDebugSimulateUpdate
        }
        if let data = defaults.data(forKey: UserDefaultsKey.displayShortcuts),
           let settings = try? JSONDecoder().decode(DisplayShortcutSettings.self, from: data) {
            displayShortcutSettings = settings
        }
        refreshLaunchAtLoginState()
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    @discardableResult
    func updateLaunchAtLogin(enabled: Bool, updateMessageOnFailure: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            return launchAtLoginEnabled == enabled
        } catch {
            launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
            if updateMessageOnFailure {
                launchMessage = String(
                    format: NSLocalizedString("Could not update login item: %@", comment: "Login item update error"),
                    error.localizedDescription
                )
            }
            return false
        }
    }

    func promptLaunchAtLoginIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: UserDefaultsKey.didPromptLaunchAtLogin) else { return }
        guard !launchAtLoginEnabled else {
            defaults.set(true, forKey: UserDefaultsKey.didPromptLaunchAtLogin)
            return
        }

        defaults.set(true, forKey: UserDefaultsKey.didPromptLaunchAtLogin)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = NSLocalizedString("Launch Tiley at login?", comment: "Launch at login prompt title")
        alert.informativeText = NSLocalizedString("Tiley can start automatically when you log in.", comment: "Launch at login prompt body")
        alert.addButton(withTitle: NSLocalizedString("Add to Login Items", comment: "Launch at login accept button"))
        alert.addButton(withTitle: NSLocalizedString("Not Now", comment: "Launch at login cancel button"))
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            _ = updateLaunchAtLogin(enabled: true, updateMessageOnFailure: true)
        }
    }

    func loadLayoutPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: UserDefaultsKey.layoutPresets),
           let presets = try? JSONDecoder().decode([LayoutPreset].self, from: data),
           !presets.isEmpty {
            layoutPresets = presets
        } else {
            layoutPresets = LayoutPreset.defaultPresets(rows: rows, columns: columns)
            saveLayoutPresets()
        }
        migrateRemoveArrowShortcutsFromPresets()
        migrateRemoveSlashShortcutFromPresets()
        sanitizePresetGlobalShortcutEligibility()
        selectedLayoutPresetID = layoutPresets.first?.id
    }

    /// Remove UpArrow / DownArrow shortcuts from layout presets.
    /// These keys are now reserved for window cycling (↑/↓).
    func migrateRemoveArrowShortcutsFromPresets() {
        let migrationKey = "didMigrateRemoveArrowShortcuts"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)

        let reservedKeyCodes: Set<UInt32> = [UInt32(kVK_UpArrow), UInt32(kVK_DownArrow)]
        var changed = false
        for i in layoutPresets.indices {
            let before = layoutPresets[i].shortcuts.count
            layoutPresets[i].shortcuts.removeAll { shortcut in
                reservedKeyCodes.contains(shortcut.keyCode) && shortcut.modifiers == 0
            }
            if layoutPresets[i].shortcuts.count != before { changed = true }
        }
        if changed { saveLayoutPresets() }
    }

    /// Remove "/" (Slash) shortcut from layout presets.
    /// This key is now reserved for closing the selected window.
    func migrateRemoveSlashShortcutFromPresets() {
        let migrationKey = "didMigrateRemoveSlashShortcut"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        UserDefaults.standard.set(true, forKey: migrationKey)

        var changed = false
        for i in layoutPresets.indices {
            let before = layoutPresets[i].shortcuts.count
            layoutPresets[i].shortcuts.removeAll { shortcut in
                shortcut.keyCode == UInt32(kVK_ANSI_Slash) && shortcut.modifiers == 0
            }
            if layoutPresets[i].shortcuts.count != before { changed = true }
        }
        if changed { saveLayoutPresets() }
    }

    func saveLayoutPresets() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(layoutPresets) {
            defaults.set(data, forKey: UserDefaultsKey.layoutPresets)
        }
    }

    func saveDisplayShortcuts() {
        if let data = try? JSONEncoder().encode(displayShortcutSettings) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKey.displayShortcuts)
        }
    }
}
