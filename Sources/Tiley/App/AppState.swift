import AppKit
import Carbon
import Observation
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
@Observable
final class AppState: NSObject, NSMenuDelegate {
    private var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    struct SettingsSnapshot: Equatable {
        var columns: Int
        var rows: Int
        var gap: CGFloat
        var hotKeyShortcut: HotKeyShortcut
        var launchAtLoginEnabled: Bool
        var menuIconVisible: Bool
        var dockIconVisible: Bool
    }

    var accessibilityGranted = false
    var isEditingSettings = false
    var isShowingPermissionsOnly = false
    var isShowingLayoutGrid = false
    var columns = 6 {
        didSet { UserDefaults.standard.set(columns, forKey: UserDefaultsKey.columns) }
    }
    var rows = 6 {
        didSet { UserDefaults.standard.set(rows, forKey: UserDefaultsKey.rows) }
    }
    var gap: CGFloat = 0 {
        didSet { UserDefaults.standard.set(Double(gap), forKey: UserDefaultsKey.gap) }
    }
    var hotKeyShortcut = HotKeyShortcut.default {
        didSet {
            UserDefaults.standard.set(Int(hotKeyShortcut.keyCode), forKey: UserDefaultsKey.hotKeyCode)
            UserDefaults.standard.set(Int(hotKeyShortcut.modifiers), forKey: UserDefaultsKey.hotKeyModifiers)
        }
    }
    var launchAtLoginEnabled = false
    var menuIconVisible = true
    var dockIconVisible = false
    var layoutPresets: [LayoutPreset] = []
    var selectedLayoutPresetID: UUID?
    var launchMessage = NSLocalizedString("Show the grid from the menu bar or use the global shortcut.", comment: "Initial launch message")

    @ObservationIgnored var updater: SPUUpdater?

    @ObservationIgnored private let accessibilityService = AccessibilityService()
    @ObservationIgnored private var windowManager: WindowManager?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var mainWindowController: MainWindowController?
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var presetHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored private var presetHotKeyIDs: [UInt32: UUID] = [:]
    @ObservationIgnored private var shortcutRecordingSessionCount = 0
    var isEditingLayoutPresets = false
    @ObservationIgnored private var hotKeyHandler: EventHandlerRef?
    @ObservationIgnored private var lastSelection: GridSelection?
    @ObservationIgnored private var lastSelectionRows: Int?
    @ObservationIgnored private var lastSelectionColumns: Int?
    @ObservationIgnored private var transientLayoutPresetID = UUID()
    @ObservationIgnored private var dismissedTransientLayoutPresetSignature: String?
    @ObservationIgnored private var lastTargetPID: pid_t?
    @ObservationIgnored private var workspaceObserverTask: Task<Void, Never>?
    @ObservationIgnored private var appActivationTask: Task<Void, Never>?
    @ObservationIgnored private var activeLayoutTarget: WindowTarget?
    @ObservationIgnored private var layoutPreviewController: LayoutPreviewOverlayController?

    var settingsSnapshot: SettingsSnapshot {
        SettingsSnapshot(
            columns: columns,
            rows: rows,
            gap: gap,
            hotKeyShortcut: hotKeyShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            menuIconVisible: menuIconVisible,
            dockIconVisible: dockIconVisible
        )
    }

    var currentLayoutTargetIcon: NSImage? {
        guard let pid = activeLayoutTarget?.processIdentifier ?? lastTargetPID else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }

    var currentLayoutTargetPrimaryText: String {
        guard let target = activeLayoutTarget else {
            return NSLocalizedString("No active target", comment: "No active window target label")
        }
        return target.appName
    }

    var currentLayoutTargetSecondaryText: String? {
        guard let title = activeLayoutTarget?.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    var displayedLayoutPresets: [LayoutPreset] {
        if let transientLayoutPreset {
            return layoutPresets + [transientLayoutPreset]
        }
        return layoutPresets
    }

    var preferredMainWindowScreenFrame: CGRect? {
        activeLayoutTarget?.screenFrame
    }

    var preferredMainWindowVisibleFrame: CGRect? {
        activeLayoutTarget?.visibleFrame
    }

    func start(showMainWindowOnLaunch: Bool = true) {
        windowManager = WindowManager(accessibilityService: accessibilityService)
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.processIdentifier != getpid() {
            lastTargetPID = frontmostApp.processIdentifier
        }
        loadSettings()
        loadLayoutPresets()
        isEditingSettings = false
        isShowingLayoutGrid = false
        refreshAccessibilityState()
        installWorkspaceObserver()
        applyStatusItemVisibility()
        applyDockIconVisibility()
        installHotKeyHandler()
        registerAllHotKeys()

        guard accessibilityGranted else {
            if showMainWindowOnLaunch {
                Task { @MainActor [weak self] in
                    self?.showPermissionsOnly()
                    self?.promptLaunchAtLoginIfNeeded()
                }
            }
            return
        }

        activeLayoutTarget = initialLayoutTarget()
        if activeLayoutTarget == nil {
            launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt to activate target window")
        } else if let activeLayoutTarget {
            launchMessage = String(
                format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                activeLayoutTarget.appName
            )
            if showMainWindowOnLaunch {
                isShowingLayoutGrid = true
            }
        }
        Task { @MainActor [weak self] in
            if showMainWindowOnLaunch {
                self?.openMainWindow()
            }
            self?.promptLaunchAtLoginIfNeeded()
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        for hotKeyRef in presetHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
        workspaceObserverTask?.cancel()
        appActivationTask?.cancel()
    }

    func requestAccessibilityAccess() {
        accessibilityGranted = accessibilityService.checkAccess(prompt: true)
        if accessibilityGranted {
            dismissPermissionsOnly()
        }
        updateStatusMenu()
    }

    func showPermissionsOnly() {
        isShowingLayoutGrid = false
        isEditingSettings = true
        isShowingPermissionsOnly = true
        openMainWindow()
    }

    func dismissPermissionsOnly() {
        guard isShowingPermissionsOnly else { return }
        isShowingPermissionsOnly = false
        isEditingSettings = false
    }

    func apply(settings: SettingsSnapshot) {
        columns = settings.columns
        rows = settings.rows
        gap = settings.gap
        hotKeyShortcut = settings.hotKeyShortcut
        _ = updateLaunchAtLogin(enabled: settings.launchAtLoginEnabled, updateMessageOnFailure: true)
        setMenuIconVisible(settings.menuIconVisible)
        setDockIconVisible(settings.dockIconVisible)
        sanitizePresetGlobalShortcutEligibility()
        registerAllHotKeys()
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingLayoutGrid = true
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Applied grid settings.", comment: "Settings applied confirmation")
    }

    func cancelSettingsEditing() {
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingLayoutGrid = true
        registerAllHotKeys()
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Canceled settings changes.", comment: "Settings canceled confirmation")
    }

    func beginSettingsEditing() {
        activeLayoutTarget = initialLayoutTarget()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        openMainWindow()
    }

    func toggleOverlay() {
        refreshAccessibilityState()
        guard accessibilityGranted else {
            showPermissionsOnly()
            return
        }

        if isShowingLayoutGrid {
            cancelLayoutGrid()
            return
        }

        guard let target = resolveWindowTarget() else { return }

        activeLayoutTarget = target
        layoutPreviewController = makeLayoutPreviewController(for: target)
        lastTargetPID = target.processIdentifier
        isEditingSettings = false
        isShowingLayoutGrid = true
        openMainWindow()
        launchMessage = String(
            format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
            target.appName
        )
    }

    func commitLayoutSelection(_ selection: GridSelection) {
        guard let target = activeLayoutTarget else {
            launchMessage = NSLocalizedString("No active target window.", comment: "No active target error")
            isShowingLayoutGrid = false
            hidePreviewOverlay()
            return
        }
        apply(selection: selection, to: target)
    }

    func cancelLayoutGrid() {
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        mainWindowController?.hide()
        _ = reactivateLastTargetApp(clearingState: false)
        launchMessage = NSLocalizedString("Canceled layout selection.", comment: "Layout selection canceled")
    }

    func apply(selection: GridSelection, to target: WindowTarget) {
        let frame = GridCalculator.frame(
            for: selection,
            in: target.visibleFrame,
            rows: rows,
            columns: columns,
            gap: gap
        )

        do {
            try windowManager?.move(target: target, to: frame)
            lastSelection = selection
            lastSelectionRows = rows
            lastSelectionColumns = columns
            let newSignature = transientLayoutPresetSignature
            if dismissedTransientLayoutPresetSignature != newSignature {
                dismissedTransientLayoutPresetSignature = nil
            }
            transientLayoutPresetID = UUID()
            hidePreviewOverlay()
            activeLayoutTarget = nil
            isShowingLayoutGrid = false
            mainWindowController?.hide()
        launchMessage = String(
            format: NSLocalizedString("Moved %@ to %@.", comment: "Window moved message"),
            target.appName,
            selection.description
        )
            _ = reactivateLastTargetApp(clearingState: false)
        } catch {
            launchMessage = error.localizedDescription
        }
    }

    @objc private func showLayoutGrid() {
        toggleOverlay()
    }

    @objc private func handleStatusItemButtonClick() {
        if isEditingSettings {
            cancelSettingsEditing()
            openMainWindow()
            return
        }
        if isShowingLayoutGrid {
            openMainWindow()
            return
        }
        toggleOverlay()
    }

    @objc private func openAccessibilityPrompt() {
        requestAccessibilityAccess()
    }

    @objc private func openSettings() {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication, frontmostApp.processIdentifier != getpid() {
            lastTargetPID = frontmostApp.processIdentifier
        }
        beginSettingsEditing()
    }

    func openSettingsFromAppMenu() {
        openSettings()
    }

    func updateLayoutPreview(_ selection: GridSelection?) {
        guard isShowingLayoutGrid else {
            hidePreviewOverlay()
            return
        }
        guard let selection, let target = activeLayoutTarget else {
            hidePreviewOverlay()
            return
        }

        if layoutPreviewController == nil ||
            layoutPreviewController?.screenFrame != target.screenFrame ||
            layoutPreviewController?.visibleFrame != target.visibleFrame {
            layoutPreviewController = makeLayoutPreviewController(for: target)
        }
        layoutPreviewController?.showSelection(
            selection,
            rows: rows,
            columns: columns,
            gap: gap,
            behind: mainWindowController?.nsWindow
        )
    }

    func updateSettingsPreview(_ settings: SettingsSnapshot) {
        guard isEditingSettings, let target = activeLayoutTarget else {
            hidePreviewOverlay()
            return
        }

        if layoutPreviewController == nil ||
            layoutPreviewController?.screenFrame != target.screenFrame ||
            layoutPreviewController?.visibleFrame != target.visibleFrame {
            layoutPreviewController = makeLayoutPreviewController(for: target)
        }
        layoutPreviewController?.showGrid(
            rows: settings.rows,
            columns: settings.columns,
            gap: settings.gap,
            behind: mainWindowController?.nsWindow
        )
    }

    func hidePreviewOverlay() {
        layoutPreviewController?.hide()
        layoutPreviewController = nil
    }

    func resetLayoutPresetsToDefault() {
        layoutPresets = LayoutPreset.defaultPresets(rows: rows, columns: columns)
        selectedLayoutPresetID = layoutPresets.first?.id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func updateLayoutPreset(_ id: UUID, mutate: (inout LayoutPreset) -> Void) {
        let persistedID = ensurePersistedLayoutPreset(id: id)
        guard let index = layoutPresets.firstIndex(where: { $0.id == persistedID }) else { return }
        mutate(&layoutPresets[index])
        sanitizeShortcutGlobalFlags(for: &layoutPresets[index])
        selectedLayoutPresetID = persistedID
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func moveLayoutPreset(from sourceID: UUID?, to targetID: UUID) {
        guard let sourceID else { return }
        guard sourceID != targetID else { return }
        guard let sourceIndex = layoutPresets.firstIndex(where: { $0.id == sourceID }) else { return }
        let preset = layoutPresets.remove(at: sourceIndex)
        let targetIndex = layoutPresets.firstIndex(where: { $0.id == targetID }) ?? layoutPresets.count
        let insertIndex = min(max(0, targetIndex), layoutPresets.count)
        layoutPresets.insert(preset, at: insertIndex)
        selectedLayoutPresetID = preset.id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func moveLayoutPreset(from sourceID: UUID?, toIndex targetIndex: Int) {
        guard let sourceID else { return }
        guard let sourceIndex = layoutPresets.firstIndex(where: { $0.id == sourceID }) else { return }

        let preset = layoutPresets.remove(at: sourceIndex)
        var insertIndex = targetIndex
        if sourceIndex < targetIndex {
            insertIndex = max(0, insertIndex - 1)
        }
        insertIndex = min(max(0, insertIndex), layoutPresets.count)

        guard insertIndex != sourceIndex else {
            layoutPresets.insert(preset, at: sourceIndex)
            return
        }

        layoutPresets.insert(preset, at: insertIndex)
        selectedLayoutPresetID = preset.id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func moveLayoutPresetToEnd(from sourceID: UUID?) {
        guard let sourceID else { return }
        guard let sourceIndex = layoutPresets.firstIndex(where: { $0.id == sourceID }) else { return }
        let preset = layoutPresets.remove(at: sourceIndex)
        layoutPresets.append(preset)
        selectedLayoutPresetID = preset.id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func layoutShortcutConflictMessage(for shortcut: HotKeyShortcut, excluding presetID: UUID) -> String? {
        if shortcut == hotKeyShortcut {
            return NSLocalizedString("This shortcut is already used by the global shortcut.", comment: "Layout shortcut conflict with app global shortcut")
        }

        if layoutPresets.contains(where: { $0.id != presetID && $0.shortcuts.contains(shortcut) }) {
            return NSLocalizedString("This shortcut is already used by another layout.", comment: "Layout shortcut conflict with another layout")
        }

        if let preset = layoutPresets.first(where: { $0.id == presetID }), preset.shortcuts.contains(shortcut) {
            return NSLocalizedString("This shortcut is already assigned to this layout.", comment: "Layout shortcut duplicate within same layout")
        }

        return nil
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

    @discardableResult
    func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
        updateLaunchAtLogin(enabled: enabled, updateMessageOnFailure: true)
    }

    func setMenuIconVisible(_ visible: Bool) {
        menuIconVisible = visible
        UserDefaults.standard.set(visible, forKey: UserDefaultsKey.menuIconVisible)
        applyStatusItemVisibility()
    }

    func setDockIconVisible(_ visible: Bool) {
        dockIconVisible = visible
        UserDefaults.standard.set(visible, forKey: UserDefaultsKey.dockIconVisible)
        applyDockIconVisibility()
    }

    func isPersistedLayoutPreset(_ id: UUID) -> Bool {
        layoutPresets.contains(where: { $0.id == id })
    }

    func selectLayoutPreset(_ id: UUID) {
        selectedLayoutPresetID = id
    }

    @discardableResult
    func applySelectedLayoutPreset() -> Bool {
        guard let id = selectedLayoutPresetID else { return false }
        applyLayoutPreset(id: id)
        return true
    }

    func moveLayoutPresetSelection(by offset: Int) {
        guard offset != 0 else { return }
        let presets = displayedLayoutPresets
        guard !presets.isEmpty else { return }
        let ids = presets.map(\.id)
        guard let selectedID = selectedLayoutPresetID,
              let currentIndex = ids.firstIndex(of: selectedID) else {
            selectedLayoutPresetID = offset > 0 ? ids.first : ids.last
            return
        }
        let count = ids.count
        let rawIndex = (currentIndex + offset) % count
        let wrappedIndex = rawIndex >= 0 ? rawIndex : rawIndex + count
        selectedLayoutPresetID = ids[wrappedIndex]
    }

    func applyLayoutPreset(id: UUID) {
        guard let preset = layoutPreset(for: id) else { return }
        guard accessibilityGranted || accessibilityService.checkAccess(prompt: false) else {
            requestAccessibilityAccess()
            return
        }
        guard let target = resolveWindowTarget() else { return }

        activeLayoutTarget = target
        lastTargetPID = target.processIdentifier
        let selection = preset.scaledSelection(toRows: rows, columns: columns)
        apply(selection: selection, to: target)
    }

    func handleLocalShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard isShowingLayoutGrid, !isEditingSettings else { return false }
        guard let preset = layoutPresets.first(where: { $0.localShortcuts.contains(shortcut) }) else { return false }
        applyLayoutPreset(id: preset.id)
        return true
    }

    func removeLayoutPreset(id: UUID) {
        if let index = layoutPresets.firstIndex(where: { $0.id == id }) {
            layoutPresets.remove(at: index)
            if selectedLayoutPresetID == id {
                selectedLayoutPresetID = layoutPresets.first?.id
            }
            saveLayoutPresets()
            registerPresetHotKeys()
            return
        }

        guard transientLayoutPreset?.id == id else { return }
        dismissedTransientLayoutPresetSignature = transientLayoutPresetSignature
        if selectedLayoutPresetID == id {
            selectedLayoutPresetID = layoutPresets.first?.id
        }
    }

    func hideMainWindow() {
        mainWindowController?.hide()
    }

    func quitApp() {
        NSApp.terminate(nil)
    }

    func reopenMainWindowFromDock() {
        refreshAccessibilityState()
        guard accessibilityGranted else {
            showPermissionsOnly()
            return
        }
        if !isEditingSettings && !isShowingLayoutGrid {
            activeLayoutTarget = initialLayoutTarget()
            if let activeLayoutTarget {
                isShowingLayoutGrid = true
                launchMessage = String(
                    format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                    activeLayoutTarget.appName
                )
            } else {
                launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt to activate target window")
            }
        }
        openMainWindow()
    }

    @objc private func quit() {
        quitApp()
    }

    private func resolveWindowTarget() -> WindowTarget? {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.processIdentifier == getpid(),
           lastTargetPID == nil {
            launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt when frontmost app is self")
            return nil
        }

        guard let target = windowManager?.captureFocusedWindow(preferredPID: lastTargetPID) else {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let frontmostName = frontmost?.localizedName ?? NSLocalizedString("Unknown", comment: "Unknown app name fallback")
            let frontmostPID = frontmost?.processIdentifier ?? 0
            hidePreviewOverlay()
            launchMessage = String(
                format: NSLocalizedString("No standard focused window was found. frontmost=%@(%d) preferred=%d", comment: "Focused window diagnostic"),
                frontmostName,
                frontmostPID,
                lastTargetPID ?? 0
            )
            return nil
        }
        return target
    }

    private func initialLayoutTarget() -> WindowTarget? {
        guard accessibilityGranted else { return nil }
        guard let target = windowManager?.captureFocusedWindow(preferredPID: lastTargetPID) else {
            hidePreviewOverlay()
            return nil
        }
        layoutPreviewController = makeLayoutPreviewController(for: target)
        return target
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemButtonClick)
            button.sendAction(on: [.leftMouseUp])
        }
        if let iconURL = resourceBundle.url(forResource: "menu-icon", withExtension: "pdf"),
           let icon = NSImage(contentsOf: iconURL),
           let button = item.button {
            icon.isTemplate = true
            icon.size = NSSize(width: 34, height: 34)
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            item.button?.title = NSLocalizedString("Tiley", comment: "App name fallback title")
        }
        item.menu = nil
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func applyStatusItemVisibility() {
        if menuIconVisible {
            installStatusItem()
        } else {
            removeStatusItem()
        }
    }

    private func updateStatusMenu() {
        // Status item menu is intentionally disabled.
    }

    private func refreshAccessibilityState() {
        accessibilityGranted = accessibilityService.checkAccess(prompt: false)
    }

    private func installHotKeyHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            let appState = Unmanaged<AppState>.fromOpaque(userData).takeUnretainedValue()
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            if hotKeyID.id == 1 {
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
            }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &hotKeyHandler)
    }

    private func registerAllHotKeys() {
        guard shortcutRecordingSessionCount == 0 else { return }
        registerMainHotKey()
        registerPresetHotKeys()
    }

    private func registerMainHotKey() {
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

    private func registerPresetHotKeys() {
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

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func unregisterPresetHotKeys() {
        for hotKeyRef in presetHotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }
        presetHotKeyRefs.removeAll()
        presetHotKeyIDs.removeAll()
    }

    private func unregisterAllHotKeys() {
        unregisterHotKey()
        unregisterPresetHotKeys()
    }

    private func canEnableGlobalShortcut(for shortcut: HotKeyShortcut) -> Bool {
        // Preset shortcuts accept non-modifier keys as well.
        // Keep only the hard conflict guard against Tiley's own main global shortcut.
        if shortcut == hotKeyShortcut {
            return false
        }
        return true
    }

    private func sanitizePresetGlobalShortcutEligibility() {
        for presetIndex in layoutPresets.indices {
            sanitizeShortcutGlobalFlags(for: &layoutPresets[presetIndex])
        }
    }

    private func sanitizeShortcutGlobalFlags(for preset: inout LayoutPreset) {
        for shortcutIndex in preset.shortcuts.indices {
            if preset.shortcuts[shortcutIndex].isGlobal,
               !canEnableGlobalShortcut(for: preset.shortcuts[shortcutIndex]) {
                preset.shortcuts[shortcutIndex].isGlobal = false
            }
        }
    }

    private var transientLayoutPreset: LayoutPreset? {
        guard let lastSelection,
              let lastSelectionRows,
              let lastSelectionColumns else {
            return nil
        }

        guard dismissedTransientLayoutPresetSignature != transientLayoutPresetSignature else {
            return nil
        }

        let candidate = LayoutPreset(
            id: transientLayoutPresetID,
            name: NSLocalizedString("Last Selection", comment: "Transient preset name"),
            selection: lastSelection.normalized,
            baseRows: lastSelectionRows,
            baseColumns: lastSelectionColumns,
            shortcuts: []
        )

        let candidateSelection = candidate.scaledSelection(toRows: rows, columns: columns)
        guard !layoutPresets.contains(where: { $0.scaledSelection(toRows: rows, columns: columns) == candidateSelection }) else {
            return nil
        }

        return candidate
    }

    private var transientLayoutPresetSignature: String? {
        guard let lastSelection,
              let lastSelectionRows,
              let lastSelectionColumns else {
            return nil
        }
        return "\(lastSelectionRows)x\(lastSelectionColumns):\(lastSelection.normalized.description)"
    }

    private func layoutPreset(for id: UUID) -> LayoutPreset? {
        if let preset = layoutPresets.first(where: { $0.id == id }) {
            return preset
        }
        guard let transientLayoutPreset, transientLayoutPreset.id == id else { return nil }
        return transientLayoutPreset
    }

    private func ensurePersistedLayoutPreset(id: UUID) -> UUID {
        if layoutPresets.contains(where: { $0.id == id }) {
            return id
        }

        guard let transientLayoutPreset, transientLayoutPreset.id == id else {
            return id
        }

        layoutPresets.append(transientLayoutPreset)
        dismissedTransientLayoutPresetSignature = transientLayoutPresetSignature
        return transientLayoutPreset.id
    }

    private func loadSettings() {
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
        refreshLaunchAtLoginState()
    }

    private func applyDockIconVisibility() {
        let activationPolicy: NSApplication.ActivationPolicy = dockIconVisible ? .regular : .accessory
        _ = NSApp.setActivationPolicy(activationPolicy)
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = (SMAppService.mainApp.status == .enabled)
    }

    @discardableResult
    private func updateLaunchAtLogin(enabled: Bool, updateMessageOnFailure: Bool) -> Bool {
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

    private func promptLaunchAtLoginIfNeeded() {
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

    private func loadLayoutPresets() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: UserDefaultsKey.layoutPresets),
           let presets = try? JSONDecoder().decode([LayoutPreset].self, from: data),
           !presets.isEmpty {
            layoutPresets = presets
        } else {
            layoutPresets = LayoutPreset.defaultPresets(rows: rows, columns: columns)
            saveLayoutPresets()
        }
        sanitizePresetGlobalShortcutEligibility()
        selectedLayoutPresetID = layoutPresets.first?.id
    }

    private func saveLayoutPresets() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(layoutPresets) {
            defaults.set(data, forKey: UserDefaultsKey.layoutPresets)
        }
    }

    @discardableResult
    private func reactivateLastTargetApp(clearingState: Bool) -> Bool {
        guard let lastTargetPID else { return false }
        let activated = NSRunningApplication(processIdentifier: lastTargetPID)?.activate() ?? false
        if clearingState {
            self.lastTargetPID = nil
        }
        return activated
    }

    private func refocusLastTargetApp() {
        guard let lastTargetPID else { return }
        NSRunningApplication(processIdentifier: lastTargetPID)?.activate()
    }

    private func handleMainWindowHidden() {
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingPermissionsOnly = false
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        registerAllHotKeys()
        if !NSApp.isActive {
            refocusLastTargetApp()
        }
    }

    private func handleMainWindowEscape() -> Bool {
        if isEditingSettings {
            cancelSettingsEditing()
            return true
        }
        if isEditingLayoutPresets {
            isEditingLayoutPresets = false
            return true
        }
        return false
    }

    private func openMainWindow() {
        if mainWindowController == nil {
            mainWindowController = MainWindowController(appState: self, onHide: { [weak self] in
                Task { @MainActor in
                    self?.handleMainWindowHidden()
                }
            }, onEscape: { [weak self] in
                guard let self else { return false }
                return self.handleMainWindowEscape()
            }, onLocalShortcut: { [weak self] shortcut in
                guard let self else { return false }
                return self.handleLocalShortcut(shortcut)
            }, onKeyCommand: { [weak self] event in
                guard let self else { return false }
                return self.handleMainWindowKeyCommand(event)
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        Task { @MainActor [weak self] in
            self?.selectedLayoutPresetID = nil
            self?.mainWindowController?.show()
        }
    }

    private func handleMainWindowKeyCommand(_ event: NSEvent) -> Bool {
        guard !isEditingSettings else { return false }

        switch Int(event.keyCode) {
        case kVK_UpArrow:
            if hasRegisteredLocalShortcut(for: event) {
                return false
            }
            moveLayoutPresetSelection(by: -1)
            return true
        case kVK_DownArrow:
            if hasRegisteredLocalShortcut(for: event) {
                return false
            }
            moveLayoutPresetSelection(by: 1)
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            return applySelectedLayoutPreset()
        default:
            return false
        }
    }

    private func hasRegisteredLocalShortcut(for event: NSEvent) -> Bool {
        guard let shortcut = HotKeyShortcut.from(event: event, requireModifiers: false) else { return false }
        return layoutPresets.contains(where: { $0.localShortcuts.contains(shortcut) })
    }

    private func makeLayoutPreviewController(for target: WindowTarget) -> LayoutPreviewOverlayController {
        LayoutPreviewOverlayController(
            screenFrame: target.screenFrame,
            visibleFrame: target.visibleFrame
        )
    }

    private func installWorkspaceObserver() {
        workspaceObserverTask = Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            )
            for await notification in notifications {
                guard !Task.isCancelled else { break }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != getpid() else {
                    continue
                }
                await MainActor.run { [weak self] in
                    self?.lastTargetPID = app.processIdentifier
                    self?.refreshAccessibilityState()
                    self?.updateStatusMenu()
                }
            }
        }

        appActivationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleAppDidBecomeActive()
                }
            }
        }
    }

    private func handleAppDidBecomeActive() {
        guard isShowingPermissionsOnly else { return }
        refreshAccessibilityState()
        guard accessibilityGranted else { return }
        dismissPermissionsOnly()
        activeLayoutTarget = initialLayoutTarget()
        if let activeLayoutTarget {
            isShowingLayoutGrid = true
            launchMessage = String(
                format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                activeLayoutTarget.appName
            )
        } else {
            launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt to activate target window")
        }
        openMainWindow()
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshAccessibilityState()
        updateStatusMenu()
    }
}

private enum UserDefaultsKey {
    static let columns = "gridColumns"
    static let rows = "gridRows"
    static let gap = "gridGap"
    static let hotKeyCode = "globalHotKeyCode"
    static let hotKeyModifiers = "globalHotKeyModifiers"
    static let layoutPresets = "layoutPresets"
    static let didPromptLaunchAtLogin = "didPromptLaunchAtLogin"
    static let menuIconVisible = "menuIconVisible"
    static let dockIconVisible = "dockIconVisible"
}
