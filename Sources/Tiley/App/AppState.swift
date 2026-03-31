import AppKit
import Carbon
import Observation
import ServiceManagement
import Sparkle
import SwiftUI
import TelemetryDeck

/// Captured at module-load time, before Tiley becomes the frontmost app.
/// Force-evaluated in AppDelegate init via `AppState.captureLaunchTimeFrontmostPID()`.
private nonisolated(unsafe) var launchTimeFrontmostPID: pid_t?

@MainActor
@Observable
final class AppState: NSObject, NSMenuDelegate {
    /// Call as early as possible (e.g. AppDelegate init) to snapshot the
    /// frontmost app before Tiley activates.
    nonisolated static func captureLaunchTimeFrontmostPID() {
        guard launchTimeFrontmostPID == nil else { return }
        // First try NSWorkspace (works when another app is still frontmost).
        if let app = NSWorkspace.shared.frontmostApplication,
           app.processIdentifier != getpid() {
            launchTimeFrontmostPID = app.processIdentifier
            return
        }
        // NSWorkspace already reports Tiley as frontmost.
        // Fall back to the on-screen window list: the topmost non-Tiley
        // standard window is very likely the app the user was interacting
        // with immediately before launching Tiley.
        if let pid = topmostNonSelfWindowOwnerPID() {
            launchTimeFrontmostPID = pid
        }
    }

    /// Returns the PID that owns the topmost on-screen standard window
    /// that does not belong to this process.
    private nonisolated static func topmostNonSelfWindowOwnerPID() -> pid_t? {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return nil }

        let selfPID = getpid()
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                  ownerPID != selfPID else { continue }
            // Skip menu bar items, overlays, etc. — only consider
            // standard windows (layer == 0).
            let layer = info[kCGWindowLayer] as? Int ?? -1
            guard layer == 0 else { continue }
            return ownerPID
        }
        return nil
    }

    var resourceBundle: Bundle {
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
        var quitAppOnLastWindowClose: Bool
        var enableDebugLog: Bool
        var debugSimulateUpdate: Bool
        var displayShortcutSettings: DisplayShortcutSettings
    }

    var desktopImageVersion: Int = 0

    /// Whether the macOS menu bar currently uses dark (vibrant dark) appearance.
    /// Updated whenever the wallpaper changes via desktopImageVersion.
    var menuBarIsDark: Bool {
        guard let button = statusItem?.button else { return true }
        return button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight]) == .vibrantDark
    }

    /// The screen that currently hosts the status item (for per-screen menu bar colour).
    var statusItemScreen: NSScreen? {
        statusItem?.button?.window?.screen
    }
    var accessibilityGranted = false
    var isEditingSettings = false
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
    var quitAppOnLastWindowClose = true {
        didSet { UserDefaults.standard.set(quitAppOnLastWindowClose, forKey: UserDefaultsKey.quitAppOnLastWindowClose) }
    }
    var enableDebugLog = false {
        didSet {
            UserDefaults.standard.set(enableDebugLog, forKey: UserDefaultsKey.enableDebugLog)
            applyStatusItemIcon()
            applyDockIconBadge()
        }
    }
    var debugSimulateUpdate = false {
        didSet {
            UserDefaults.standard.set(debugSimulateUpdate, forKey: UserDefaultsKey.debugSimulateUpdate)
            applyStatusItemIcon()
            applyDockIconBadge()
        }
    }
    var displayShortcutSettings = DisplayShortcutSettings.default
    var layoutPresets: [LayoutPreset] = []
    var selectedLayoutPresetID: UUID?
    var launchMessage = NSLocalizedString("Show the grid from the menu bar or use the global shortcut.", comment: "Initial launch message")

    @ObservationIgnored var updater: SPUUpdater?
    var hasUpdateBadge = false
    var showsUpdateIndicator: Bool { hasUpdateBadge || debugSimulateUpdate }
    @ObservationIgnored var menuIconTemporarilyShown = false

    @ObservationIgnored var accessibilityService = AccessibilityService()
    @ObservationIgnored var windowManager: WindowManager?
    @ObservationIgnored var originalMenuIcon: NSImage?
    @ObservationIgnored var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored var statusItem: NSStatusItem?
    /// Tracks the last appearance name used to render the status icon badge,
    /// preventing redundant redraws that can cause a CPU-spinning feedback loop.
    @ObservationIgnored var lastStatusIconAppearance: NSAppearance.Name?
    /// Re-entrancy guard for `applyStatusItemIcon()`.
    @ObservationIgnored var isApplyingStatusIcon = false
    @ObservationIgnored var settingsWindowController: SettingsWindowController?
    @ObservationIgnored var permissionsWindowController: PermissionsWindowController?
    @ObservationIgnored var mainWindowControllers: [CGDirectDisplayID: MainWindowController] = [:]
    @ObservationIgnored var targetScreenDisplayID: CGDirectDisplayID?
    @ObservationIgnored var screenChangeTask: Task<Void, Never>?
    @ObservationIgnored var isSwitchingActivationPolicy = false
    @ObservationIgnored var isRecreatingWindows = false
    @ObservationIgnored var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored var presetHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored var presetHotKeyIDs: [UInt32: UUID] = [:]
    @ObservationIgnored var displayHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored var displayHotKeyActions: [UInt32: DisplayHotKeyAction] = [:]
    @ObservationIgnored var shortcutRecordingSessionCount = 0
    var isEditingLayoutPresets = false
    @ObservationIgnored var hotKeyHandler: EventHandlerRef?
    @ObservationIgnored var hotKeysYieldedToDebug = false
    @ObservationIgnored var lastSelection: GridSelection?
    @ObservationIgnored var lastSelectionRows: Int?
    @ObservationIgnored var lastSelectionColumns: Int?
    @ObservationIgnored var transientLayoutPresetID = UUID()
    @ObservationIgnored var dismissedTransientLayoutPresetSignature: String?
    @ObservationIgnored var lastTargetPID: pid_t?
    @ObservationIgnored var workspaceObserverTask: Task<Void, Never>?
    @ObservationIgnored var appActivationTask: Task<Void, Never>?
    @ObservationIgnored var appDeactivationTask: Task<Void, Never>?
    @ObservationIgnored var activeLayoutTarget: WindowTarget?
    @ObservationIgnored var cachedResizability: WindowResizability?
    @ObservationIgnored var cachedResizabilityPID: pid_t?
    @ObservationIgnored var layoutPreviewController: LayoutPreviewOverlayController?
    @ObservationIgnored var windowHighlightController: WindowHighlightController?
    @ObservationIgnored var availableWindowTargets: [WindowTarget] = []
    /// Mission Control space list (empty when detection is unavailable).
    @ObservationIgnored var spaceList: [SpaceInfo] = []
    /// The currently active Mission Control space IDs (one per display).
    @ObservationIgnored var activeSpaceIDs: Set<UInt64> = []
    @ObservationIgnored var activeTargetIndex: Int = 0
    /// All currently selected window indices for multi-selection.
    /// Invariant: always contains `activeTargetIndex`.
    @ObservationIgnored var selectedWindowIndices: Set<Int> = [0]
    /// Window indices in the order they were selected. First element = primary.
    @ObservationIgnored var selectionOrder: [Int] = [0]
    /// Anchor index for Shift+click range selection.
    @ObservationIgnored var selectionAnchorIndex: Int? = nil
    @ObservationIgnored var originalFrontmostPID: pid_t?
    @ObservationIgnored var originalFrontmostTarget: WindowTarget?

    /// The initial z-order of CG window IDs captured when cycling begins.
    @ObservationIgnored var initialZOrderWindowIDs: [CGWindowID] = []
    /// Active displacement animation timer.
    @ObservationIgnored var displacementAnimationTimer: DispatchSourceTimer?
    /// Separate timer for restoring displaced windows after confirmation.
    @ObservationIgnored var restorationAnimationTimer: DispatchSourceTimer?
    /// Maps window IDs that have been moved off-screen to their original
    /// positions and AX elements, so they can be restored when selection
    /// changes or cycling ends.  Storing the `AXUIElement` directly avoids
    /// relying on `availableWindowTargets` at restoration time — the list
    /// may have been refreshed and the entry could be missing.
    @ObservationIgnored var displacedWindowFrames: [CGWindowID: (origin: CGPoint, window: AXUIElement)] = [:]
    /// The index to select after the next `refreshAvailableWindows` call.
    @ObservationIgnored var pendingTargetIndexAfterClose: Int?
    @ObservationIgnored var displayHighlightWindow: NSWindow?

    // MARK: - Modifier-held cycling (Cmd+Tab-like interaction)
    /// True when the user opened the overlay and is still holding the toggle modifiers.
    var isModifierHeldMode = false
    /// True when the user pressed an additional key (cycling or layout shortcut)
    /// while in modifier-held mode. Used to decide whether releasing modifiers
    /// should confirm the selection or just exit modifier-held mode.
    @ObservationIgnored var hasActedDuringModifierHeld = false
    @ObservationIgnored var modifierReleaseGlobalMonitor: Any?
    @ObservationIgnored var modifierReleaseLocalMonitor: Any?

    /// True while the user is cycling through target windows (Tab/arrow/click
    /// in the sidebar).  Used to suppress Tiley from hiding itself when the
    /// target app is briefly activated to bring its window to the front.
    /// The window target that was most recently raised during cycling/selection,
    /// so we can restore its Z-order when switching to another target.
    /// Whether the user has cycled the target window at least once via Tab.
    var hasUsedTabCycling: Bool { originalFrontmostPID != nil }
    var windowTargetListVersion: Int = 0
    /// The window-target indices in the order displayed in the sidebar.
    /// Updated by the sidebar view whenever its rows are recomputed.
    @ObservationIgnored var sidebarWindowOrder: [Int] = []
    /// True while the deferred `refreshAvailableWindows` is pending.
    var isLoadingWindowList = false
    /// Incremented to signal the UI to toggle the window list sidebar.
    var windowTargetMenuRequestVersion: Int = 0
    /// Incremented to signal Cmd+F when search field is NOT focused: show sidebar and focus search.
    var windowSearchFocusRequestVersion: Int = 0

    /// Maps window indices to layout color indices during preset hover preview.
    /// Used by the sidebar to highlight which windows will be affected and with which color.
    var presetHoverHighlights: [Int: Int] = [:]

    /// Window info per layout selection index during preset hover, for the mini-grid preview.
    struct PresetHoverWindowInfo {
        let appIcon: NSImage?
        let appName: String
        let windowTitle: String
    }
    var presetHoverWindowInfo: [PresetHoverWindowInfo] = []
    /// Incremented to signal Cmd+F when search field IS focused: hide sidebar.
    var windowSearchHideRequestVersion: Int = 0
    /// Current window search query, synced from the UI for filtered cycling.
    var windowSearchQuery: String = ""
    /// Incremented to signal the action bar to show the "Move to Other Display" popup.
    /// Only the window on the display matching `moveToOtherDisplayTargetID` should respond.
    var moveToOtherDisplayRequestVersion: Int = 0
    @ObservationIgnored var moveToOtherDisplayTargetID: CGDirectDisplayID = 0
    var settingsSnapshot: SettingsSnapshot {
        SettingsSnapshot(
            columns: columns,
            rows: rows,
            gap: gap,
            hotKeyShortcut: hotKeyShortcut,
            launchAtLoginEnabled: launchAtLoginEnabled,
            menuIconVisible: menuIconVisible,
            dockIconVisible: dockIconVisible,
            quitAppOnLastWindowClose: quitAppOnLastWindowClose,
            enableDebugLog: enableDebugLog,
            debugSimulateUpdate: debugSimulateUpdate,
            displayShortcutSettings: displayShortcutSettings
        )
    }

    var currentLayoutTargetIcon: NSImage? {
        // Access windowTargetListVersion to trigger SwiftUI updates when the target changes.
        _ = windowTargetListVersion
        guard let pid = activeLayoutTarget?.processIdentifier ?? lastTargetPID else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.icon
    }

    var currentLayoutTargetPrimaryText: String {
        _ = windowTargetListVersion
        if let target = activeLayoutTarget {
            return target.appName
        }
        if let pid = lastTargetPID,
           let name = NSRunningApplication(processIdentifier: pid)?.localizedName {
            return name
        }
        return NSLocalizedString("No active target", comment: "No active window target label")
    }

    var currentLayoutTargetSecondaryText: String? {
        _ = windowTargetListVersion
        guard let title = activeLayoutTarget?.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return nil
        }
        return title
    }

    /// Menu bar titles fetched asynchronously from the target app via Accessibility API.
    /// Falls back to localized placeholder strings until the fetch completes.
    var targetMenuBarTitles: [String] = [
        NSLocalizedString("menu.bar.fallback.file", comment: "Fallback menu title: File"),
        NSLocalizedString("menu.bar.fallback.edit", comment: "Fallback menu title: Edit"),
        NSLocalizedString("menu.bar.fallback.view", comment: "Fallback menu title: View"),
    ]

    /// Fetches the menu bar item titles from the target app using Accessibility API.
    /// Updates targetMenuBarTitles on the main actor when done.
    func fetchTargetMenuBarTitles() {
        let pid = activeLayoutTarget?.processIdentifier ?? lastTargetPID
        guard let pid else {
            targetMenuBarTitles = [
                NSLocalizedString("menu.bar.fallback.file", comment: "Fallback menu title: File"),
                NSLocalizedString("menu.bar.fallback.edit", comment: "Fallback menu title: Edit"),
                NSLocalizedString("menu.bar.fallback.view", comment: "Fallback menu title: View"),
            ]
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            let titles = Self.readMenuBarTitles(pid: pid)
            await MainActor.run { [weak self] in
                if !titles.isEmpty {
                    self?.targetMenuBarTitles = titles
                }
            }
        }
    }

    /// Reads menu bar item titles synchronously via AX (call from a background task).
    private nonisolated static func readMenuBarTitles(pid: pid_t) -> [String] {
        let axApp = AXUIElementCreateApplication(pid)
        var menuBarRef: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXMenuBarAttribute as CFString, &menuBarRef) == .success,
              let menuBar = menuBarRef else { return [] }
        var childrenRef: AnyObject?
        guard AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return [] }
        var titles: [String] = []
        for child in children {
            var titleRef: AnyObject?
            if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String,
               !title.isEmpty {
                titles.append(title)
            }
        }
        // Drop the Apple menu (first item, always "Apple" or empty)
        if !titles.isEmpty { titles.removeFirst() }
        // Drop the application name menu (second item) — it's already shown
        // separately as bold text in the menu bar composite view.
        if !titles.isEmpty { titles.removeFirst() }
        return titles
    }

    var windowTargetList: [WindowTarget] {
        _ = windowTargetListVersion
        return availableWindowTargets
    }

    /// Mission Control space list for the current refresh cycle.
    var currentSpaceList: [SpaceInfo] {
        _ = windowTargetListVersion
        return spaceList
    }

    /// The active Mission Control space IDs (one per display) for the current refresh cycle.
    var currentActiveSpaceIDs: Set<UInt64> {
        _ = windowTargetListVersion
        return activeSpaceIDs
    }

    var currentWindowTargetIndex: Int {
        _ = windowTargetListVersion
        return activeTargetIndex
    }

    /// The set of all selected window indices (for multi-selection).
    var currentSelectedWindowIndices: Set<Int> {
        _ = windowTargetListVersion
        return selectedWindowIndices
    }

    /// True when multiple windows are selected.
    var isMultiSelection: Bool {
        _ = windowTargetListVersion
        return selectedWindowIndices.count > 1
    }

    /// The display ID of the screen currently hosting the layout target.
    var currentTargetScreenDisplayID: CGDirectDisplayID? {
        targetScreenDisplayID
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

    var currentLayoutTargetRelativeFrame: WindowFrameRelative? {
        _ = windowTargetListVersion
        guard let target = activeLayoutTarget,
              !target.isHidden,
              target.visibleFrame.width > 0,
              target.visibleFrame.height > 0 else { return nil }

        let vf = target.visibleFrame
        let wf = target.frame

        let relX = (wf.minX - vf.minX) / vf.width
        let relY = (vf.maxY - wf.maxY) / vf.height
        let relW = wf.width / vf.width
        let relH = wf.height / vf.height

        let menuBarHeight = target.screenFrame.height - vf.height - vf.minY + target.screenFrame.minY
        let menuBarFraction = max(0, menuBarHeight / vf.height)

        let icon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
        return WindowFrameRelative(
            x: relX, y: relY, width: relW, height: relH,
            menuBarHeightFraction: menuBarFraction,
            windowTitle: target.windowTitle,
            appName: target.appName,
            appIcon: icon
        )
    }

    func start(showMainWindowOnLaunch: Bool = true) {
        windowManager = WindowManager(accessibilityService: accessibilityService)
        // Use the PID captured at module-load time (before Tiley became active),
        // falling back to the current frontmost app.
        if let launchTimeFrontmostPID {
            lastTargetPID = launchTimeFrontmostPID
        } else if let frontmostApp = NSWorkspace.shared.frontmostApplication,
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
        applyDockIconVisibility(isInitialStartup: true)
        installHotKeyHandler()
        installDebugHotKeyCoordination()
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
        if activeLayoutTarget == nil, lastTargetPID != nil {
            // AX window is not available yet (Tiley just launched and is frontmost).
            // Show the grid using the app name from NSRunningApplication; the actual
            // AX window will be resolved when the user commits a layout selection.
            let targetAppName = NSRunningApplication(processIdentifier: lastTargetPID!)?.localizedName
                ?? NSLocalizedString("App", comment: "Generic app name fallback")
            launchMessage = String(
                format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                targetAppName
            )
            if showMainWindowOnLaunch {
                isShowingLayoutGrid = true
            }
        } else if activeLayoutTarget == nil {
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
                self?.showHighlightForActiveTarget()
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
        #if !DEBUG
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        #endif
        workspaceObserverTask?.cancel()
        appActivationTask?.cancel()
        appDeactivationTask?.cancel()
        screenChangeTask?.cancel()
    }

    func requestAccessibilityAccess() {
        accessibilityGranted = accessibilityService.checkAccess(prompt: true)
        if accessibilityGranted {
            dismissPermissionsOnly()
        }
        updateStatusMenu()
    }

    /// Sets the main (grid/sidebar) windows to floating level.
    func applyWindowLevel() {
        for controller in mainWindowControllers.values {
            controller.window?.level = .floating
        }
    }

    func showPermissionsOnly() {
        hideAllMainWindows()
        if permissionsWindowController == nil {
            permissionsWindowController = PermissionsWindowController(appState: self)
        }
        permissionsWindowController?.show()
    }

    func dismissPermissionsOnly() {
        guard permissionsWindowController != nil else { return }
        permissionsWindowController?.dismiss()
        permissionsWindowController = nil
    }

    func apply(settings: SettingsSnapshot) {
        columns = settings.columns
        rows = settings.rows
        gap = settings.gap
        hotKeyShortcut = settings.hotKeyShortcut
        displayShortcutSettings = settings.displayShortcutSettings
        saveDisplayShortcuts()
        _ = updateLaunchAtLogin(enabled: settings.launchAtLoginEnabled, updateMessageOnFailure: true)
        setMenuIconVisible(settings.menuIconVisible)
        setDockIconVisible(settings.dockIconVisible)
        quitAppOnLastWindowClose = settings.quitAppOnLastWindowClose
        enableDebugLog = settings.enableDebugLog
        debugSimulateUpdate = settings.debugSimulateUpdate
        sanitizePresetGlobalShortcutEligibility()
        TelemetryDeck.signal("settingsChanged", parameters: [
            "columns": "\(settings.columns)",
            "rows": "\(settings.rows)",
            "gap": "\(settings.gap)",
        ])
        // Only register the main toggle hotkey; keep preset global hotkeys
        // unregistered while the layout grid is visible so local shortcuts work.
        unregisterPresetHotKeys()
        unregisterDisplayHotKeys()
        registerMainHotKey()
        hidePreviewOverlay()
        settingsWindowController?.dismiss()
        settingsWindowController = nil
        isEditingSettings = false
        isShowingLayoutGrid = true
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Applied grid settings.", comment: "Settings applied confirmation")
        openMainWindow()
        showHighlightForActiveTarget()
    }

    func cancelSettingsEditing() {
        hidePreviewOverlay()
        settingsWindowController?.dismiss()
        settingsWindowController = nil
        isEditingSettings = false
        isShowingLayoutGrid = true
        // Only register the main toggle hotkey; keep preset and display global
        // hotkeys unregistered while the layout grid is visible so local shortcuts work.
        unregisterPresetHotKeys()
        unregisterDisplayHotKeys()
        registerMainHotKey()
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Canceled settings changes.", comment: "Settings canceled confirmation")
        openMainWindow()
        showHighlightForActiveTarget()
    }

    func beginSettingsEditing() {
        let mainFrame = targetWindowController?.window?.frame
        activeLayoutTarget = initialLayoutTarget()
        removeModifierReleaseMonitor()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        windowHighlightController?.hide()
        windowHighlightController = nil
        hideAllMainWindows()
        settingsWindowController = SettingsWindowController(appState: self, mainWindowFrame: mainFrame)
        settingsWindowController?.show()
    }

    func beginSettingsEditing(on screen: NSScreen) {
        let mainFrame = targetWindowController?.window?.frame
        activeLayoutTarget = initialLayoutTarget()
        removeModifierReleaseMonitor()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        windowHighlightController?.hide()
        windowHighlightController = nil
        hideAllMainWindows()
        settingsWindowController = SettingsWindowController(appState: self, mainWindowFrame: mainFrame)
        settingsWindowController?.show()
    }

    /// Called when the settings window is closed externally (e.g. by the window manager).
    func handleSettingsWindowClosed() {
        guard isEditingSettings else { return }
        cancelSettingsEditing()
    }

    func toggleOverlay() {
        let perfStart = CFAbsoluteTimeGetCurrent()
        func perfLog(_ label: String) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
            debugLog("\(label) (t=\(String(format: "%.1f", elapsed))ms)")
        }
        debugLog("toggleOverlay start")
        refreshAccessibilityState()
        perfLog("refreshAccessibilityState done")
        guard accessibilityGranted else {
            showPermissionsOnly()
            return
        }

        if isShowingLayoutGrid {
            if isModifierHeldMode {
                hasActedDuringModifierHeld = true
                cycleTargetWindow(forward: true)
                return
            }
            cancelLayoutGrid()
            return
        }

        guard let target = resolveWindowTarget() else {
            perfLog("resolveWindowTarget returned nil")
            return
        }
        perfLog("resolveWindowTarget done")

        activeLayoutTarget = target
        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: target)
        perfLog("makeLayoutPreviewController done")
        lastTargetPID = target.processIdentifier
        originalFrontmostPID = nil
        isEditingSettings = false
        // Unregister preset and display global hotkeys while the overlay is visible
        // so that key events reach the NSWindow's performKeyEquivalent and can be
        // handled as local shortcuts. They are re-registered in handleMainWindowHidden().
        unregisterPresetHotKeys()
        unregisterDisplayHotKeys()
        windowSearchQuery = ""
        isShowingLayoutGrid = true
        openMainWindow()
        perfLog("openMainWindow done")
        // Show a highlight border around the initially selected (frontmost) window.
        showHighlightForActiveTarget()
        // Enter modifier-held mode so that re-pressing the trigger key cycles
        // windows and releasing the modifiers confirms the selection.
        installModifierReleaseMonitor()
        // Bump version after the window is open so the view picks up the latest
        // target info and window list.
        windowTargetListVersion += 1
        // Asynchronously fetch the actual menu bar titles from the target app.
        fetchTargetMenuBarTitles()
        // Defer window list population so it doesn't block overlay appearance.
        isLoadingWindowList = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshAvailableWindows()
            self.isLoadingWindowList = false
            debugLog("refreshAvailableWindows done (deferred)")

            // The initially captured target may have been a transient window
            // (e.g. Xcode's "Build Succeeded" HUD) that has since disappeared.
            // Verify it still exists; if not, fall back to the next window.
            self.revalidateActiveTarget()
        }
        launchMessage = String(
            format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
            target.appName
        )
        TelemetryDeck.signal("gridOverlayOpened")
        perfLog("toggleOverlay end")
    }

    func commitLayoutSelection(_ selection: GridSelection) {
        if activeLayoutTarget == nil, lastTargetPID != nil {
            // AX target was not available at launch; resolve it now.
            activeLayoutTarget = resolveWindowTarget()
        }
        guard let target = activeLayoutTarget else {
            launchMessage = NSLocalizedString("No active target window.", comment: "No active target error")
            isShowingLayoutGrid = false
            hidePreviewOverlay()
            return
        }

        if selectedWindowIndices.count > 1 {
            // Multi-selection: apply the same layout to all selected windows.
            applyToMultipleWindows(selection: selection)
        } else {
            apply(selection: selection, to: target)
        }
    }

    /// Apply a grid selection to all windows in the multi-selection.
    /// - Parameters:
    ///   - selection: The primary grid selection.
    ///   - secondarySelections: Additional selections for 2nd, 3rd, ... windows (by sidebar/Z-order).
    ///   - visibleFrame: If provided, use this screen's visible frame (e.g. from mouse pointer's screen).
    ///   - screenFrame: If provided, use this screen frame for coordinate conversion.
    func applyToMultipleWindows(selection: GridSelection, secondarySelections: [GridSelection] = [], visibleFrame: CGRect? = nil, screenFrame: CGRect? = nil) {
        guard let primaryTarget = activeLayoutTarget else { return }

        // Determine the target screen: use the provided screen (mouse pointer's screen)
        // or fall back to the primary target's screen.
        let currentVisibleFrame: CGRect
        let currentScreenFrame: CGRect
        if let vf = visibleFrame, let sf = screenFrame {
            // Re-fetch from actual screen to avoid stale values.
            if let screen = NSScreen.screens.first(where: { $0.frame == sf }) {
                currentVisibleFrame = screen.visibleFrame
                currentScreenFrame = screen.frame
            } else {
                currentVisibleFrame = vf
                currentScreenFrame = sf
            }
        } else if let screen = NSScreen.screens.first(where: { $0.frame == primaryTarget.screenFrame }) {
            currentVisibleFrame = screen.visibleFrame
            currentScreenFrame = screen.frame
        } else {
            currentVisibleFrame = primaryTarget.visibleFrame
            currentScreenFrame = primaryTarget.screenFrame
        }

        let allSelections = [selection] + secondarySelections

        dismissOverlayImmediately()

        // Order selected window indices by selection order (first selected = primary).
        let orderedIndices = selectionOrder.filter { $0 < availableWindowTargets.count }

        for (windowPosition, idx) in orderedIndices.enumerated() {
            var target = availableWindowTargets[idx]
            target = unhideAppIfNeeded(target)

            // Map window position to selection: clamp to last available selection.
            let selectionIndex = min(windowPosition, allSelections.count - 1)
            let sel = allSelections[selectionIndex]

            let frame = GridCalculator.frame(
                for: sel,
                in: currentVisibleFrame,
                rows: rows,
                columns: columns,
                gap: gap
            )

            // If the window is on a different screen, move it to the target screen first.
            if let window = target.windowElement,
               target.screenFrame != currentScreenFrame {
                let destScreen = NSScreen.screens.first(where: { $0.frame == currentScreenFrame })
                if let dest = destScreen {
                    moveWindowToDestinationScreen(window: window, destination: dest)
                }
            }

            do {
                if enableDebugLog {
                    _ = try windowManager?.moveWithLog(target: target, to: frame, on: currentScreenFrame)
                } else {
                    _ = try windowManager?.move(target: target, to: frame, onScreenFrame: currentScreenFrame)
                }
                windowManager?.raiseWindow(target: target)
            } catch {
                NSLog("[Tiley] applyToMultipleWindows error for index \(idx): %@", error.localizedDescription)
            }
        }

        // Clear displaced window frames so restoreDisplacedWindowsAnimated()
        // (called from recordSelectionAndHide) doesn't undo the positions
        // we just set.
        displacedWindowFrames.removeAll()

        // Activate the primary window (frontmost in sidebar order) so it
        // becomes the active window after layout application.
        let primaryWindowTarget: WindowTarget? = orderedIndices.first.map { availableWindowTargets[$0] }
        if let primary = primaryWindowTarget {
            lastTargetPID = primary.processIdentifier
        }

        recordSelectionAndHide(selection: selection, appName: primaryWindowTarget?.appName ?? primaryTarget.appName, wasConstrained: false)
        let norm = selection.normalized
        TelemetryDeck.signal("layoutApplied", parameters: [
            "columns": "\(norm.endColumn - norm.startColumn + 1)",
            "rows": "\(norm.endRow - norm.startRow + 1)",
            "multiSelection": "\(selectedWindowIndices.count)",
            "selectionCount": "\(allSelections.count)",
        ])
    }

    /// Builds an ordered list of window indices for a multi-layout preset.
    /// Selected windows come first (in selection order), then unselected
    /// windows are filled in by z-order (frontmost first) up to `count`.
    func buildZOrderedWindowIndices(count: Int) -> [Int] {
        let selectedIndices = selectionOrder.filter { $0 < availableWindowTargets.count }
        let selectedSet = Set(selectedIndices)
        var result = selectedIndices

        // Fill remaining slots with unselected windows by z-order.
        for i in 0..<availableWindowTargets.count {
            guard result.count < count else { break }
            if !selectedSet.contains(i) {
                result.append(i)
            }
        }
        return Array(result.prefix(count))
    }

    /// Applies a multi-layout preset. Selected windows are placed first
    /// (as primary, secondary, …), then remaining layout slots are filled
    /// with unselected windows picked by actual z-order (frontmost first).
    func applyPresetToZOrderedWindows(selections: [GridSelection], visibleFrame: CGRect? = nil, screenFrame: CGRect? = nil) {
        guard let primaryTarget = activeLayoutTarget else { return }

        let currentVisibleFrame: CGRect
        let currentScreenFrame: CGRect
        if let vf = visibleFrame, let sf = screenFrame {
            if let screen = NSScreen.screens.first(where: { $0.frame == sf }) {
                currentVisibleFrame = screen.visibleFrame
                currentScreenFrame = screen.frame
            } else {
                currentVisibleFrame = vf
                currentScreenFrame = sf
            }
        } else if let screen = NSScreen.screens.first(where: { $0.frame == primaryTarget.screenFrame }) {
            currentVisibleFrame = screen.visibleFrame
            currentScreenFrame = screen.frame
        } else {
            currentVisibleFrame = primaryTarget.visibleFrame
            currentScreenFrame = primaryTarget.screenFrame
        }

        dismissOverlayImmediately()

        // Selected windows first, then fill from z-order.
        let orderedIndices = buildZOrderedWindowIndices(count: selections.count)

        for (position, idx) in orderedIndices.enumerated() {
            var target = availableWindowTargets[idx]
            target = unhideAppIfNeeded(target)
            let sel = selections[position]

            let frame = GridCalculator.frame(
                for: sel,
                in: currentVisibleFrame,
                rows: rows,
                columns: columns,
                gap: gap
            )

            if let window = target.windowElement,
               target.screenFrame != currentScreenFrame {
                let destScreen = NSScreen.screens.first(where: { $0.frame == currentScreenFrame })
                if let dest = destScreen {
                    moveWindowToDestinationScreen(window: window, destination: dest)
                }
            }

            do {
                if enableDebugLog {
                    _ = try windowManager?.moveWithLog(target: target, to: frame, on: currentScreenFrame)
                } else {
                    _ = try windowManager?.move(target: target, to: frame, onScreenFrame: currentScreenFrame)
                }
                windowManager?.raiseWindow(target: target)
            } catch {
                NSLog("[Tiley] applyPresetToZOrderedWindows error for index \(idx): %@", error.localizedDescription)
            }
        }

        displacedWindowFrames.removeAll()

        let primaryWindowTarget: WindowTarget? = orderedIndices.first.map { availableWindowTargets[$0] }
        if let primary = primaryWindowTarget {
            lastTargetPID = primary.processIdentifier
        }

        let primarySelection = selections[0]
        recordSelectionAndHide(selection: primarySelection, appName: primaryWindowTarget?.appName ?? primaryTarget.appName, wasConstrained: false)
        let norm = primarySelection.normalized
        TelemetryDeck.signal("layoutApplied", parameters: [
            "columns": "\(norm.endColumn - norm.startColumn + 1)",
            "rows": "\(norm.endRow - norm.startRow + 1)",
            "multiSelection": "\(selectedWindowIndices.count)",
            "selectionCount": "\(selections.count)",
            "zOrderBased": "true",
        ])
    }

    func cancelLayoutGrid() {
        removeModifierReleaseMonitor()
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        clearResizabilityCache()

        // Restore the original window to the foreground BEFORE hiding Tiley's
        // windows.  If we hide first, macOS may auto-activate the previously
        // raised (cycled) window's app, causing it to flash to the front.
        // By raising + activating the original while Tiley is still present,
        // the activation target is deterministic.
        if let originalTarget = originalFrontmostTarget,
           let window = originalTarget.windowElement {
            accessibilityService.raiseWindow(window)
            NSRunningApplication(processIdentifier: originalTarget.processIdentifier)?.activate()
            // Restore lastTargetPID so that handleMainWindowHidden →
            // refocusLastTargetApp does not re-activate the cycled window.
            lastTargetPID = originalTarget.processIdentifier
        } else if let originalPID = originalFrontmostPID {
            NSRunningApplication(processIdentifier: originalPID)?.activate()
            lastTargetPID = originalPID
        } else {
            _ = reactivateLastTargetApp(clearingState: false)
        }

        hideAllMainWindows()
        clearWindowCyclingState(animateRestore: true)
        launchMessage = NSLocalizedString("Canceled layout selection.", comment: "Layout selection canceled")
    }

    func apply(selection: GridSelection, to target: WindowTarget) {
        let target = unhideAppIfNeeded(target)

        // If the target window is on a different space than the selected space,
        // switch to that space and move the window there.

        // Re-fetch the current visibleFrame from the actual screen to avoid
        // using stale values captured when the target was resolved. The Dock
        // or menu bar may have auto-shown/hidden since then.
        let currentVisibleFrame: CGRect
        if let screen = NSScreen.screens.first(where: { $0.frame == target.screenFrame }) {
            currentVisibleFrame = screen.visibleFrame
        } else {
            currentVisibleFrame = target.visibleFrame
        }

        let frame = GridCalculator.frame(
            for: selection,
            in: currentVisibleFrame,
            rows: rows,
            columns: columns,
            gap: gap
        )

        dismissOverlayImmediately()

        do {
            let constrained: Bool
            if enableDebugLog {
                constrained = try windowManager?.moveWithLog(target: target, to: frame, on: target.screenFrame) ?? false
            } else {
                constrained = try windowManager?.move(target: target, to: frame) ?? false
            }
            windowManager?.raiseWindow(target: target)
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: constrained)
            let norm = selection.normalized
            TelemetryDeck.signal("layoutApplied", parameters: [
                "columns": "\(norm.endColumn - norm.startColumn + 1)",
                "rows": "\(norm.endRow - norm.startRow + 1)",
            ])
        } catch {
            NSLog("[Tiley] apply(selection:to:) error: %@", error.localizedDescription)
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: false)
            launchMessage = error.localizedDescription
        }
    }

    /// Commits a layout selection on a specific screen (used by multi-screen grid/preset interactions).
    func commitLayoutSelectionOnScreen(_ selection: GridSelection, secondarySelections: [GridSelection] = [], visibleFrame: CGRect, screenFrame: CGRect) {
        if activeLayoutTarget == nil, lastTargetPID != nil {
            activeLayoutTarget = resolveWindowTarget()
        }
        guard var target = activeLayoutTarget else {
            launchMessage = NSLocalizedString("No active target window.", comment: "No active target error")
            isShowingLayoutGrid = false
            hidePreviewOverlay()
            return
        }
        target = unhideAppIfNeeded(target)
        activeLayoutTarget = target

        let allSelections = [selection] + secondarySelections
        if allSelections.count > 1 {
            if selectedWindowIndices.count >= allSelections.count {
                applyToMultipleWindows(selection: selection, secondarySelections: secondarySelections, visibleFrame: visibleFrame, screenFrame: screenFrame)
            } else {
                applyPresetToZOrderedWindows(selections: allSelections, visibleFrame: visibleFrame, screenFrame: screenFrame)
            }
            return
        }

        // If the target window is on a different space, move it and switch.

        // Re-fetch the current visibleFrame from the actual screen to avoid
        // using stale values captured at overlay-open time. The Dock or menu
        // bar may have auto-shown/hidden since then, changing visibleFrame.
        let currentVisibleFrame: CGRect
        let currentScreenFrame: CGRect
        if let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) {
            currentVisibleFrame = screen.visibleFrame
            currentScreenFrame = screen.frame
        } else {
            currentVisibleFrame = visibleFrame
            currentScreenFrame = screenFrame
        }

        let frame = GridCalculator.frame(
            for: selection,
            in: currentVisibleFrame,
            rows: rows,
            columns: columns,
            gap: gap
        )

        dismissOverlayImmediately()

        do {
            let constrained: Bool
            if enableDebugLog {
                constrained = try windowManager?.moveWithLog(target: target, to: frame, on: currentScreenFrame) ?? false
            } else {
                constrained = try windowManager?.move(target: target, to: frame, onScreenFrame: currentScreenFrame) ?? false
            }
            windowManager?.raiseWindow(target: target)
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: constrained)
        } catch {
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: false)
            launchMessage = error.localizedDescription
        }
    }

    /// Applies a layout preset targeting a specific screen.
    func applyLayoutPresetOnScreen(id: UUID, visibleFrame: CGRect, screenFrame: CGRect) {
        guard let preset = layoutPreset(for: id) else { return }
        guard accessibilityGranted || accessibilityService.checkAccess(prompt: false) else {
            requestAccessibilityAccess()
            return
        }
        var target: WindowTarget
        if let existing = activeLayoutTarget {
            target = existing
        } else {
            guard let resolved = resolveWindowTarget() else { return }
            target = resolved
        }
        target = unhideAppIfNeeded(target)

        activeLayoutTarget = target
        lastTargetPID = target.processIdentifier
        let selection = preset.scaledSelection(toRows: rows, columns: columns)
        let secondarySelections = preset.scaledSecondarySelections(toRows: rows, columns: columns)
        commitLayoutSelectionOnScreen(selection, secondarySelections: secondarySelections, visibleFrame: visibleFrame, screenFrame: screenFrame)
    }

    private func recordSelectionAndHide(selection: GridSelection, appName: String, wasConstrained: Bool = false) {
        lastSelection = selection
        lastSelectionRows = rows
        lastSelectionColumns = columns
        let newSignature = transientLayoutPresetSignature
        if dismissedTransientLayoutPresetSignature != newSignature {
            dismissedTransientLayoutPresetSignature = nil
        }
        transientLayoutPresetID = UUID()
        // hidePreviewOverlay / isShowingLayoutGrid / hideAllMainWindows are
        // already called by the caller before the resize for faster feedback.
        activeLayoutTarget = nil
        clearResizabilityCache()
        if wasConstrained {
            launchMessage = String(
                format: NSLocalizedString("Moved %@ to %@ (size adjusted due to window constraints).", comment: "Window moved with size constraint message"),
                appName,
                selection.description
            )
        } else {
            launchMessage = String(
                format: NSLocalizedString("Moved %@ to %@.", comment: "Window moved message"),
                appName,
                selection.description
            )
        }
        _ = reactivateLastTargetApp(clearingState: false)
        clearWindowCyclingState(animateRestore: true)
    }

    @objc private func showLayoutGrid() {
        toggleOverlay()
    }

    @objc func handleStatusItemButtonClick() {
        debugLog("handleStatusItemButtonClick start")
        if isEditingSettings {
            cancelSettingsEditing()
            return
        }
        if isShowingLayoutGrid {
            cancelLayoutGrid()
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

}



