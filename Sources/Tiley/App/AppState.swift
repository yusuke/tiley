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
    private(set) var hasUpdateBadge = false
    var showsUpdateIndicator: Bool { hasUpdateBadge || debugSimulateUpdate }
    @ObservationIgnored private var menuIconTemporarilyShown = false

    @ObservationIgnored private let accessibilityService = AccessibilityService()
    @ObservationIgnored private var windowManager: WindowManager?
    @ObservationIgnored private var originalMenuIcon: NSImage?
    @ObservationIgnored private var appearanceObservation: NSKeyValueObservation?
    @ObservationIgnored private var statusItem: NSStatusItem?
    /// Tracks the last appearance name used to render the status icon badge,
    /// preventing redundant redraws that can cause a CPU-spinning feedback loop.
    @ObservationIgnored private var lastStatusIconAppearance: NSAppearance.Name?
    /// Re-entrancy guard for `applyStatusItemIcon()`.
    @ObservationIgnored private var isApplyingStatusIcon = false
    @ObservationIgnored private var mainWindowControllers: [CGDirectDisplayID: MainWindowController] = [:]
    @ObservationIgnored private var targetScreenDisplayID: CGDirectDisplayID?
    @ObservationIgnored private var screenChangeTask: Task<Void, Never>?
    @ObservationIgnored private var isSwitchingActivationPolicy = false
    @ObservationIgnored private(set) var isRecreatingWindows = false
    @ObservationIgnored private var hotKeyRef: EventHotKeyRef?
    @ObservationIgnored private var presetHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored private var presetHotKeyIDs: [UInt32: UUID] = [:]
    @ObservationIgnored private var displayHotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    @ObservationIgnored private var displayHotKeyActions: [UInt32: DisplayHotKeyAction] = [:]
    @ObservationIgnored private var shortcutRecordingSessionCount = 0
    var isEditingLayoutPresets = false
    @ObservationIgnored private var hotKeyHandler: EventHandlerRef?
    @ObservationIgnored private var hotKeysYieldedToDebug = false
    @ObservationIgnored private var lastSelection: GridSelection?
    @ObservationIgnored private var lastSelectionRows: Int?
    @ObservationIgnored private var lastSelectionColumns: Int?
    @ObservationIgnored private var transientLayoutPresetID = UUID()
    @ObservationIgnored private var dismissedTransientLayoutPresetSignature: String?
    @ObservationIgnored private var lastTargetPID: pid_t?
    @ObservationIgnored private var workspaceObserverTask: Task<Void, Never>?
    @ObservationIgnored private var appActivationTask: Task<Void, Never>?
    @ObservationIgnored private var appDeactivationTask: Task<Void, Never>?
    @ObservationIgnored private var activeLayoutTarget: WindowTarget?
    @ObservationIgnored private var cachedResizability: WindowResizability?
    @ObservationIgnored private var cachedResizabilityPID: pid_t?
    @ObservationIgnored private var layoutPreviewController: LayoutPreviewOverlayController?
    @ObservationIgnored private var windowHighlightController: WindowHighlightController?
    @ObservationIgnored private var availableWindowTargets: [WindowTarget] = []
    /// Mission Control space list (empty when detection is unavailable).
    @ObservationIgnored private(set) var spaceList: [SpaceInfo] = []
    /// The currently active Mission Control space IDs (one per display).
    @ObservationIgnored private(set) var activeSpaceIDs: Set<UInt64> = []
    @ObservationIgnored private var activeTargetIndex: Int = 0
    /// All currently selected window indices for multi-selection.
    /// Invariant: always contains `activeTargetIndex`.
    @ObservationIgnored private(set) var selectedWindowIndices: Set<Int> = [0]
    /// Window indices in the order they were selected. First element = primary.
    @ObservationIgnored private(set) var selectionOrder: [Int] = [0]
    /// Anchor index for Shift+click range selection.
    @ObservationIgnored private var selectionAnchorIndex: Int? = nil
    @ObservationIgnored private var originalFrontmostPID: pid_t?
    @ObservationIgnored private var originalFrontmostTarget: WindowTarget?

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
    /// Incremented to signal Cmd+F when search field IS focused: hide sidebar.
    var windowSearchHideRequestVersion: Int = 0
    /// Current window search query, synced from the UI for filtered cycling.
    var windowSearchQuery: String = ""
    /// Incremented to signal the action bar to show the "Move to Other Display" popup.
    /// Only the window on the display matching `moveToOtherDisplayTargetID` should respond.
    var moveToOtherDisplayRequestVersion: Int = 0
    @ObservationIgnored var moveToOtherDisplayTargetID: CGDirectDisplayID = 0
    /// Whether the window list sidebar is visible (shared across all windows).
    var isSidebarVisible: Bool = UserDefaults.standard.object(forKey: UserDefaultsKey.windowListSidebarVisible) != nil
        ? UserDefaults.standard.bool(forKey: UserDefaultsKey.windowListSidebarVisible)
        : true {
        didSet { UserDefaults.standard.set(isSidebarVisible, forKey: UserDefaultsKey.windowListSidebarVisible) }
    }

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
        isEditingSettings = false
        isShowingLayoutGrid = true
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Applied grid settings.", comment: "Settings applied confirmation")
        openMainWindow()
        showHighlightForActiveTarget()
    }

    func cancelSettingsEditing() {
        hidePreviewOverlay()
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
        activeLayoutTarget = initialLayoutTarget()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        windowHighlightController?.hide()
        windowHighlightController = nil
        closeSecondaryWindows()
        openMainWindow()
    }

    func beginSettingsEditing(on screen: NSScreen) {
        activeLayoutTarget = initialLayoutTarget()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        windowHighlightController?.hide()
        windowHighlightController = nil
        openTargetScreenWindow(on: screen)
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
    private func applyToMultipleWindows(selection: GridSelection, secondarySelections: [GridSelection] = [], visibleFrame: CGRect? = nil, screenFrame: CGRect? = nil) {
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

    func cancelLayoutGrid() {
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

    func cycleTargetWindow(forward: Bool) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }

        if originalFrontmostPID == nil {
            refreshAvailableWindows()
        }
        guard !availableWindowTargets.isEmpty else { return }

        // Record the original frontmost app on first cycle.
        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            // Snapshot the initial z-order so we can restore it when switching targets.
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        // Use the sidebar display order so Tab cycles in the same visual order.
        let query = windowSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredIndices: [Int]
        if !sidebarWindowOrder.isEmpty {
            // Use sidebar order, filtering out any stale indices.
            let valid = sidebarWindowOrder.filter { $0 < availableWindowTargets.count }
            if query.isEmpty {
                filteredIndices = valid
            } else {
                filteredIndices = valid.filter { i in
                    let target = availableWindowTargets[i]
                    let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return target.appName.lowercased().contains(query)
                        || title.lowercased().contains(query)
                }
            }
        } else {
            // Fallback: screen-ordered indices (sidebar not yet rendered).
            var baseIndices: [Int]
            if query.isEmpty {
                baseIndices = Array(availableWindowTargets.indices)
            } else {
                baseIndices = availableWindowTargets.indices.filter { i in
                    let target = availableWindowTargets[i]
                    let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return target.appName.lowercased().contains(query)
                        || title.lowercased().contains(query)
                }
            }
            filteredIndices = screenOrderedIndices(baseIndices)
        }

        if let currentPos = filteredIndices.firstIndex(of: activeTargetIndex) {
            let nextPos = forward
                ? (currentPos + 1) % filteredIndices.count
                : (currentPos - 1 + filteredIndices.count) % filteredIndices.count
            activeTargetIndex = filteredIndices[nextPos]
        } else {
            activeTargetIndex = forward ? filteredIndices.first! : filteredIndices.last!
        }

        // Tab cycling always resets to single selection.
        selectedWindowIndices = [activeTargetIndex]
        selectionOrder = [activeTargetIndex]
        selectionAnchorIndex = activeTargetIndex

        applyTargetAtCurrentIndex()
    }

    /// Reorders a list of window-target indices so that windows on the mouse
    /// cursor's screen come first, followed by windows on other screens.
    private func screenOrderedIndices(_ indices: [Int]) -> [Int] {
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreenID = NSScreen.screens
            .first(where: { $0.frame.contains(mouseLocation) })?.displayID

        // Partition into mouse-screen group and other groups.
        var mouseScreenGroup: [Int] = []
        var otherGroups: [CGDirectDisplayID: [Int]] = [:]
        for i in indices {
            let target = availableWindowTargets[i]
            let screenID = NSScreen.screen(containing: target.screenFrame)?.displayID
            if screenID == mouseScreenID {
                mouseScreenGroup.append(i)
            } else {
                otherGroups[screenID ?? 0, default: []].append(i)
            }
        }

        // Mouse screen first, then other screens in stable order.
        var result = mouseScreenGroup
        for (_, group) in otherGroups.sorted(by: { $0.key < $1.key }) {
            result.append(contentsOf: group)
        }
        return result
    }

    func selectWindowTarget(at index: Int) {
        selectWindowTarget(at: index, shift: false, cmd: false)
    }

    /// Select a window target with optional modifier keys for multi-selection.
    /// - Parameters:
    ///   - index: The window index to select.
    ///   - shift: True when Shift is held (range selection).
    ///   - cmd: True when Cmd is held (toggle selection).
    func selectWindowTarget(at index: Int, shift: Bool, cmd: Bool) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard index >= 0, index < availableWindowTargets.count else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        if cmd {
            // Cmd+click: toggle this window in/out of the selection.
            if selectedWindowIndices.contains(index) {
                // Don't deselect the last remaining item.
                if selectedWindowIndices.count > 1 {
                    selectedWindowIndices.remove(index)
                    selectionOrder.removeAll { $0 == index }
                    // If the removed item was the primary, pick another.
                    if activeTargetIndex == index {
                        activeTargetIndex = selectionOrder.first ?? selectedWindowIndices.first!
                    }
                }
                // else: sole item Cmd-clicked → no-op
            } else {
                selectedWindowIndices.insert(index)
                selectionOrder.append(index)
                activeTargetIndex = index
            }
        } else if shift {
            // Shift+click: select contiguous range in sidebar order.
            let anchor = selectionAnchorIndex ?? activeTargetIndex
            let order: [Int]
            if !sidebarWindowOrder.isEmpty {
                order = sidebarWindowOrder.filter { $0 < availableWindowTargets.count }
            } else {
                order = Array(availableWindowTargets.indices)
            }
            if let anchorPos = order.firstIndex(of: anchor),
               let clickPos = order.firstIndex(of: index) {
                let lo = min(anchorPos, clickPos)
                let hi = max(anchorPos, clickPos)
                let rangeIndices = Array(order[lo...hi])
                selectedWindowIndices = Set(rangeIndices)
                // Selection order: anchor first, then the rest in sidebar order.
                // Preserve existing selectionOrder entries that are still selected,
                // then append new ones from the range.
                let previousOrder = selectionOrder.filter { selectedWindowIndices.contains($0) }
                let newIndices = rangeIndices.filter { !previousOrder.contains($0) }
                selectionOrder = previousOrder + newIndices
            } else {
                selectedWindowIndices = [index]
                selectionOrder = [index]
            }
            activeTargetIndex = index
            // Don't update selectionAnchorIndex on shift-click.
        } else {
            // Plain click: single selection.
            selectedWindowIndices = [index]
            selectionOrder = [index]
            selectionAnchorIndex = index
            activeTargetIndex = index
        }

        windowTargetListVersion += 1
        applyTargetAtCurrentIndex()
    }

    /// Select all windows belonging to the given app (PID).
    func selectAllWindowsOfApp(pid: pid_t) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        let indices = availableWindowTargets.indices.filter { availableWindowTargets[$0].processIdentifier == pid }
        guard !indices.isEmpty else { return }
        selectedWindowIndices = Set(indices)
        // Selection order: current active first (if in this app), then rest in index order.
        let currentActive = activeTargetIndex
        if indices.contains(currentActive) {
            selectionOrder = [currentActive] + indices.filter { $0 != currentActive }
        } else {
            selectionOrder = indices
        }
        selectionAnchorIndex = nil
        activeTargetIndex = selectionOrder.first!
        windowTargetListVersion += 1
        applyTargetAtCurrentIndex()
    }

    /// Select all windows on the given display.
    func selectAllWindowsOnScreen(displayID: CGDirectDisplayID) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        let indices = availableWindowTargets.indices.filter {
            NSScreen.screen(containing: availableWindowTargets[$0].screenFrame)?.displayID == displayID
        }
        guard !indices.isEmpty else { return }
        selectedWindowIndices = Set(indices)
        let currentActive = activeTargetIndex
        if indices.contains(currentActive) {
            selectionOrder = [currentActive] + indices.filter { $0 != currentActive }
        } else {
            selectionOrder = indices
        }
        selectionAnchorIndex = nil
        activeTargetIndex = selectionOrder.first!
        windowTargetListVersion += 1
        applyTargetAtCurrentIndex()
    }

    /// Select all windows in the current window list.
    func selectAllWindows() {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard !availableWindowTargets.isEmpty else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        selectedWindowIndices = Set(availableWindowTargets.indices)
        selectionAnchorIndex = nil
        // Keep activeTargetIndex as is, or set to 0 if invalid.
        if activeTargetIndex >= availableWindowTargets.count {
            activeTargetIndex = 0
        }
        // Selection order: current active first, then rest in index order.
        let allIndices = Array(availableWindowTargets.indices)
        selectionOrder = [activeTargetIndex] + allIndices.filter { $0 != activeTargetIndex }
        windowTargetListVersion += 1
    }

    /// Raises (brings to front) the currently selected target window and activates its app.
    /// If the mouse pointer is on a different screen than the window, the window is moved
    /// to the mouse pointer's screen first, preferring repositioning over resizing.
    /// Displaced windows are animated back to their original positions in the background.
    func raiseCurrentTargetWindow() {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard activeTargetIndex >= 0, activeTargetIndex < availableWindowTargets.count else { return }
        let target = availableWindowTargets[activeTargetIndex]

        dismissOverlayImmediately()

        if let window = target.windowElement {
            moveWindowToMouseScreenIfNeeded(window: window, windowScreenFrame: target.screenFrame, windowFrame: target.frame)
            accessibilityService.raiseWindow(window)
        }
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate()

        // Animate displaced windows back after the selected window is operational.
        clearWindowCyclingState(animateRestore: true)
    }

    /// Moves a window to the mouse pointer's screen when they are on different screens.
    /// Prefers repositioning over resizing; only resizes if the window is larger than the screen.
    private func moveWindowToMouseScreenIfNeeded(window: AXUIElement, windowScreenFrame: CGRect, windowFrame: CGRect) {
        let mouseLocation = NSEvent.mouseLocation
        let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
        let windowScreen = NSScreen.screens.first(where: { $0.frame == windowScreenFrame })
            ?? NSScreen.screen(containing: windowFrame)

        guard let mouseScreen = mouseScreen,
              let windowScreen = windowScreen,
              mouseScreen.displayID != windowScreen.displayID else { return }

        moveWindowToDestinationScreen(window: window, destination: mouseScreen)
    }

    /// Moves a window to the destination screen, keeping its size if possible.
    /// Prefers repositioning over resizing; only resizes if the window is larger than the screen.
    private func moveWindowToDestinationScreen(window: AXUIElement, destination: NSScreen) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? destination.frame.maxY
        let (currentPos, currentSize) = accessibilityService.readPositionAndSize(of: window)
        let destVisible = destination.visibleFrame

        // Visible frame bounds in AX coordinates (top-left origin on primary screen)
        let visibleAXTop = primaryMaxY - destVisible.maxY
        let visibleAXLeft = destVisible.minX
        let visibleAXRight = destVisible.maxX
        let visibleAXBottom = primaryMaxY - destVisible.minY

        var newPos = currentPos
        var newSize = currentSize

        // If the window is larger than the destination screen, resize to fit
        if newSize.width > destVisible.width {
            newSize.width = destVisible.width
        }
        if newSize.height > destVisible.height {
            newSize.height = destVisible.height
        }

        // Clamp position so the window stays within the visible area
        if newPos.x + newSize.width > visibleAXRight {
            newPos.x = visibleAXRight - newSize.width
        }
        newPos.x = max(newPos.x, visibleAXLeft)

        if newPos.y + newSize.height > visibleAXBottom {
            newPos.y = visibleAXBottom - newSize.height
        }
        newPos.y = max(newPos.y, visibleAXTop)

        // Apply size change first if needed, then position
        let needsResize = abs(newSize.width - currentSize.width) > 1
                       || abs(newSize.height - currentSize.height) > 1
        if needsResize {
            var size = newSize
            if let sizeVal = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            }
        }
        var pos = newPos
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
        }
    }

    /// The initial z-order of CG window IDs captured when cycling begins.
    /// Used to restore the original stacking order before raising a new window.
    private var initialZOrderWindowIDs: [CGWindowID] = []

    /// Active displacement animation timer.
    private var displacementAnimationTimer: DispatchSourceTimer?

    /// Separate timer for restoring displaced windows after confirmation.
    /// Kept independent from `displacementAnimationTimer` so that a
    /// secondary `clearWindowCyclingState()` call (e.g. from
    /// `handleMainWindowHidden`) does not cancel the restore animation.
    private var restorationAnimationTimer: DispatchSourceTimer?

    /// Maps window IDs that have been moved off-screen to their original
    /// positions, so they can be restored when selection changes or cycling ends.
    private var displacedWindowFrames: [CGWindowID: CGPoint] = [:]

    private func applyTargetAtCurrentIndex() {
        let newTarget = availableWindowTargets[activeTargetIndex]
        let previousScreenFrame = activeLayoutTarget?.screenFrame
        activeLayoutTarget = newTarget
        clearResizabilityCache()
        lastTargetPID = newTarget.processIdentifier
        windowTargetListVersion += 1

        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: newTarget)

        launchMessage = String(
            format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
            newTarget.appName
        )

        // When the target moves to a different screen, update the target
        // display ID without recreating windows (which causes visible flicker).
        let screenChanged = previousScreenFrame != newTarget.screenFrame
        if screenChanged {
            if let screenFrame = newTarget.screenFrame as CGRect?,
               let screen = NSScreen.screen(containing: screenFrame) {
                targetScreenDisplayID = screen.displayID
            }
        }

        // 1. Hide the old highlight and flush the change so it is
        //    visually removed before any window movement begins.
        windowHighlightController?.hide()
        windowHighlightController = nil
        CATransaction.flush()

        // 2. Move windows that occlude the selected target off-screen so it
        //    becomes visible without changing focus.
        if newTarget.cgWindowID != 0 {
            displaceOccludingWindows(for: newTarget)
        }

        // 3. Show the highlight border last, after the target is fully visible.
        windowHighlightController = WindowHighlightController()
        windowHighlightController?.show(around: newTarget.frame)
    }

    func refreshAvailableWindows() {
        let captured = windowManager?.captureAllWindows(includeOtherSpaces: true)
        availableWindowTargets = captured?.targets ?? []
        spaceList = captured?.spaceList ?? []
        activeSpaceIDs = captured?.activeSpaceIDs ?? []
        windowTargetListVersion += 1

        if let pendingIndex = pendingTargetIndexAfterClose {
            pendingTargetIndexAfterClose = nil
            // Clamp to the new list bounds so the selection lands on the next window,
            // or the new last window if the closed one was at the end.
            if availableWindowTargets.isEmpty {
                activeTargetIndex = 0
            } else {
                activeTargetIndex = min(pendingIndex, availableWindowTargets.count - 1)
            }
        } else if let current = activeLayoutTarget {
            activeTargetIndex = availableWindowTargets.firstIndex(where: {
                $0.processIdentifier == current.processIdentifier
                && $0.windowElement == current.windowElement
            }) ?? availableWindowTargets.firstIndex(where: {
                $0.processIdentifier == current.processIdentifier
                && $0.windowTitle == current.windowTitle
            }) ?? 0
        } else {
            activeTargetIndex = 0
        }

        // Reconcile multi-selection: remove stale indices and ensure invariant.
        selectedWindowIndices = selectedWindowIndices.filter { $0 < availableWindowTargets.count }
        selectionOrder = selectionOrder.filter { $0 < availableWindowTargets.count }
        selectedWindowIndices.insert(activeTargetIndex)
        if !selectionOrder.contains(activeTargetIndex) {
            selectionOrder.insert(activeTargetIndex, at: 0)
        }
    }

    /// Closes the window at the given index in the window list.
    /// If `quitAppOnLastWindowClose` is true and this is the app's last window,
    /// the app itself is terminated.
    /// The index to select after the next `refreshAvailableWindows` call.
    /// Set by `closeWindowTarget` so the selection lands on the next window
    /// rather than jumping to the top of the list.
    private var pendingTargetIndexAfterClose: Int?

    /// Brings the window at the given index to the foreground and dismisses the layout grid.
    func focusWindowAndDismiss(at index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = unhideAppIfNeeded(availableWindowTargets[index])
        dismissOverlayImmediately()
        activeLayoutTarget = nil
        clearResizabilityCache()
        if let window = target.windowElement {
            moveWindowToMouseScreenIfNeeded(window: window, windowScreenFrame: target.screenFrame, windowFrame: target.frame)
            accessibilityService.raiseWindow(window)
        }
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate()

        // Animate displaced windows back after the selected window is operational.
        clearWindowCyclingState(animateRestore: true)
    }

    func closeWindowTarget(at index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]

        // Remember where the selection should land after the window disappears.
        // The closed window will be removed, so `index` will point at the next one.
        // If it was the last item, clamp to the new last item.
        pendingTargetIndexAfterClose = index

        if let window = target.windowElement {
            accessibilityService.closeWindow(window)
        }

        // Refresh the window list after a short delay to let the window close.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Close other windows of the same application, keeping the one at the given index.
    func closeOtherWindowTargets(except index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let keepTarget = availableWindowTargets[index]

        for (i, target) in availableWindowTargets.enumerated()
            where i != index && target.processIdentifier == keepTarget.processIdentifier {
            if let window = target.windowElement {
                accessibilityService.closeWindow(window)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Quit the application that owns the window at the given index.
    func quitApp(at index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]
        NSRunningApplication(processIdentifier: target.processIdentifier)?.terminate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Hide all applications except the one that owns the window at the given index.
    /// If the selected app is currently hidden, it will be unhidden first.
    func hideOtherApps(except index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let keepPID = availableWindowTargets[index].processIdentifier
        let selfPID = getpid()
        let keepApp = NSRunningApplication(processIdentifier: keepPID)
        // Unhide the keep app first if needed.
        if keepApp?.isHidden == true {
            keepApp?.unhide()
        }
        // Activate the keep app so it becomes the frontmost regular app.
        // macOS won't hide the active app via hide(), so by making the
        // keep app active first, all other regular apps become hideable.
        // We need a short delay for the activation to fully propagate
        // before calling hide() on others.
        keepApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            for app in NSWorkspace.shared.runningApplications
                where app.activationPolicy == .regular
                    && app.processIdentifier != keepPID
                    && app.processIdentifier != selfPID {
                app.hide()
            }
            // Refresh to reflect hidden state (opacity) in the sidebar.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refreshAvailableWindows()
            }
        }
    }

    /// Hide all other apps except the one with the given PID.
    func hideOtherApps(exceptPID keepPID: pid_t) {
        let selfPID = getpid()
        let keepApp = NSRunningApplication(processIdentifier: keepPID)
        if keepApp?.isHidden == true {
            keepApp?.unhide()
        }
        keepApp?.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            for app in NSWorkspace.shared.runningApplications
                where app.activationPolicy == .regular
                    && app.processIdentifier != keepPID
                    && app.processIdentifier != selfPID {
                app.hide()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self?.refreshAvailableWindows()
            }
        }
    }

    /// Move a single window (by index) to the center of the given screen.
    func moveWindowToScreen(at index: Int, screen: NSScreen) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]
        guard let window = target.windowElement else { return }

        moveWindowToDestinationScreen(window: window, destination: screen)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Move all windows belonging to the given PID to the given screen.
    func moveAllAppWindowsToScreen(pid: pid_t, screen: NSScreen) {
        let indices = availableWindowTargets.enumerated()
            .filter { $0.element.processIdentifier == pid }
            .map(\.offset)
        for index in indices {
            moveWindowToScreen(at: index, screen: screen)
        }
    }

    /// Close all windows belonging to the given PID (e.g., for Finder which cannot be quit).
    func closeAllWindows(pid: pid_t) {
        for target in availableWindowTargets where target.processIdentifier == pid {
            if let window = target.windowElement {
                accessibilityService.closeWindow(window)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Gather all windows from other screens to the given screen.
    func gatherWindowsToScreen(_ screen: NSScreen) {
        let destDisplayID = screen.displayID
        for (index, target) in availableWindowTargets.enumerated() {
            let targetScreen = NSScreen.screen(containing: target.screenFrame)
            if targetScreen?.displayID != destDisplayID {
                moveWindowToScreen(at: index, screen: screen)
            }
        }
    }

    /// Move all windows on the given screen to the destination screen.
    func moveScreenWindowsToScreen(from sourceDisplayID: CGDirectDisplayID, to destScreen: NSScreen) {
        for (index, target) in availableWindowTargets.enumerated() {
            let targetScreen = NSScreen.screen(containing: target.screenFrame)
            if targetScreen?.displayID == sourceDisplayID {
                moveWindowToScreen(at: index, screen: destScreen)
            }
        }
    }

    /// Quit the application with the given PID.
    func quitApp(pid: pid_t) {
        NSRunningApplication(processIdentifier: pid)?.terminate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    // MARK: - Multi-Selection Batch Actions

    /// Raises all selected windows, preserving their relative Z-order.
    ///
    /// `availableWindowTargets` is in z-order (front-to-back from CGWindowList,
    /// index 0 = frontmost).
    ///
    /// When `CGSOrderWindow` is available we use it to place each selected
    /// window directly above the previously placed one, building an exact
    /// cross-app stacking order that the public AX/NS APIs cannot achieve.
    /// Falls back to activate+AXRaise when the private API is unavailable.
    func raiseSelectedWindows() {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard !selectedWindowIndices.isEmpty else { return }

        dismissOverlayImmediately()

        // Use selection order: the first selected window becomes the frontmost.
        let sidebarOrder = selectionOrder.filter { $0 < availableWindowTargets.count }

        guard !sidebarOrder.isEmpty else {
            clearWindowCyclingState(animateRestore: true)
            return
        }

        // Move windows to mouse screen if needed (before reordering).
        for idx in sidebarOrder {
            let target = availableWindowTargets[idx]
            if let window = target.windowElement {
                moveWindowToMouseScreenIfNeeded(window: window, windowScreenFrame: target.screenFrame, windowFrame: target.frame)
            }
        }

        // アプリ間: 最後に activate したアプリが前面に来る
        //   → サイドバー下位のアプリを先に、上位のアプリを最後に処理
        // アプリ内: 最後に AXRaise したウインドウがアプリ内最前面になる
        //   → サイドバー下位のウインドウを先に、上位のウインドウを最後に AXRaise

        // サイドバー順で選択ウインドウをアプリ別にグループ化
        var appOrder: [pid_t] = []
        var windowsByApp: [pid_t: [Int]] = [:]
        for idx in sidebarOrder {
            let pid = availableWindowTargets[idx].processIdentifier
            if windowsByApp[pid] == nil {
                appOrder.append(pid)
            }
            windowsByApp[pid, default: []].append(idx)
        }

        // サイドバー下位のアプリから処理（最後に処理したアプリが最前面）
        for pid in appOrder.reversed() {
            guard let indices = windowsByApp[pid] else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            app?.activate()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            // アプリ内: サイドバー下位から AXRaise（最後に raise = 最前面）
            for idx in indices.reversed() {
                let target = availableWindowTargets[idx]
                if let window = target.windowElement {
                    accessibilityService.raiseWindow(window)
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }

        clearWindowCyclingState(animateRestore: true)
    }

    /// Closes all selected windows. If all windows of an app are selected, quits that app instead.
    func closeSelectedWindows() {
        guard !selectedWindowIndices.isEmpty else { return }

        // Group selected indices by PID.
        var selectedByPID: [pid_t: [Int]] = [:]
        for idx in selectedWindowIndices where idx < availableWindowTargets.count {
            let pid = availableWindowTargets[idx].processIdentifier
            selectedByPID[pid, default: []].append(idx)
        }

        // Count total windows per PID.
        var totalByPID: [pid_t: Int] = [:]
        for target in availableWindowTargets {
            totalByPID[target.processIdentifier, default: 0] += 1
        }

        // Remember the lowest selected index for post-close selection.
        pendingTargetIndexAfterClose = selectedWindowIndices.min()

        var quittedPIDs: Set<pid_t> = []
        for (pid, selectedIndices) in selectedByPID {
            let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
            let allSelected = selectedIndices.count >= (totalByPID[pid] ?? 0)

            if allSelected && !isFinder {
                // All windows of this non-Finder app are selected: quit the app.
                NSRunningApplication(processIdentifier: pid)?.terminate()
                quittedPIDs.insert(pid)
            } else {
                // Close individual windows.
                for idx in selectedIndices {
                    if let window = availableWindowTargets[idx].windowElement {
                        accessibilityService.closeWindow(window)
                    }
                }
            }
        }

        // Reset selection and refresh.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    /// Move all selected windows to the given screen.
    func moveSelectedWindowsToScreen(_ screen: NSScreen) {
        for idx in selectedWindowIndices where idx < availableWindowTargets.count {
            let target = availableWindowTargets[idx]
            guard let window = target.windowElement else { continue }
            moveWindowToDestinationScreen(window: window, destination: screen)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refreshAvailableWindows()
        }
    }

    private func clearWindowCyclingState(animateRestore: Bool = false) {
        windowHighlightController?.hide()
        windowHighlightController = nil
        CATransaction.flush()
        displacementAnimationTimer?.cancel()
        displacementAnimationTimer = nil
        if animateRestore {
            restoreDisplacedWindowsAnimated()
        } else {
            restoreDisplacedWindows()
        }
        originalFrontmostPID = nil
        originalFrontmostTarget = nil
        initialZOrderWindowIDs = []
        // Keep availableWindowTargets so the sidebar can show the previous
        // window list immediately on the next overlay open while the deferred
        // refresh is still pending.
        activeTargetIndex = 0
        selectedWindowIndices = [0]
        selectionOrder = [0]
        selectionAnchorIndex = nil
    }

    /// Moves windows that occlude the selected target off-screen so it
    /// becomes visible, and restores any previously displaced windows
    /// that no longer need to be moved.
    private func displaceOccludingWindows(for selectedTarget: WindowTarget) {
        let selectedWID = selectedTarget.cgWindowID
        guard let selectedIdx = initialZOrderWindowIDs.firstIndex(of: selectedWID) else { return }
        let selectedFrame = selectedTarget.frame

        // Determine which windows should be displaced: in front of the
        // selected window AND overlapping its frame.
        var shouldDisplace = Set<CGWindowID>()
        for i in 0..<selectedIdx {
            let wid = initialZOrderWindowIDs[i]
            if let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }),
               target.frame.intersects(selectedFrame) {
                shouldDisplace.insert(wid)
            }
        }

        // Build a list of (window, currentPosition, targetPosition) for animation.
        var moves: [(window: AXUIElement, from: CGPoint, to: CGPoint)] = []

        // Restore windows that were displaced but no longer need to be.
        let toRestore = Set(displacedWindowFrames.keys).subtracting(shouldDisplace)
        for wid in toRestore {
            if let originalOrigin = displacedWindowFrames.removeValue(forKey: wid),
               let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }),
               let window = target.windowElement {
                let (currentPos, _) = accessibilityService.readPositionAndSize(of: window)
                moves.append((window: window, from: currentPos, to: originalOrigin))
            }
        }

        // Move all occluding windows down below the selected window's bottom edge.
        // Read the selected window's AX position directly (it's never displaced,
        // so its AX position is always accurate).
        let gap: CGFloat = 10
        var selectedBottomAX = selectedFrame.maxY  // fallback to CG
        if let selWindow = selectedTarget.windowElement {
            let (axPos, axSize) = accessibilityService.readPositionAndSize(of: selWindow)
            if axSize.height > 0 {
                selectedBottomAX = axPos.y + axSize.height
            }
        }
        var nextY = selectedBottomAX + gap
        debugLog("displaceOccluding: selectedCGMaxY=\(selectedFrame.maxY) selectedAXBottom=\(selectedBottomAX) nextY=\(nextY)")

        // Sort by original Y position so stacking order is predictable.
        let sortedDisplace = shouldDisplace.sorted { a, b in
            let aTarget = availableWindowTargets.first(where: { $0.cgWindowID == a })
            let bTarget = availableWindowTargets.first(where: { $0.cgWindowID == b })
            return (aTarget?.frame.minY ?? 0) < (bTarget?.frame.minY ?? 0)
        }

        for wid in sortedDisplace {
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }),
                  let window = target.windowElement else { continue }

            // Save original position if not already tracked.
            if displacedWindowFrames[wid] == nil {
                let (axPos, _) = accessibilityService.readPositionAndSize(of: window)
                displacedWindowFrames[wid] = axPos
            }

            let destination = CGPoint(x: target.frame.minX, y: nextY)
            nextY += gap

            let (currentPos, axSize) = accessibilityService.readPositionAndSize(of: window)
            debugLog("displaceOccluding: wid=\(wid) cgFrame=\(target.frame) axPos=\(currentPos) axSize=\(axSize) to=\(destination)")
            moves.append((window: window, from: currentPos, to: destination))
        }

        animateWindowMoves(moves)
    }

    /// Animates multiple window moves simultaneously over a short duration.
    private func animateWindowMoves(_ moves: [(window: AXUIElement, from: CGPoint, to: CGPoint)]) {
        displacementAnimationTimer?.cancel()
        displacementAnimationTimer = nil

        guard !moves.isEmpty else { return }

        // Filter out moves with negligible distance.
        let significantMoves = moves.filter {
            abs($0.from.x - $0.to.x) > 1 || abs($0.from.y - $0.to.y) > 1
        }
        guard !significantMoves.isEmpty else {
            for move in moves {
                accessibilityService.setPosition(move.to, for: move.window)
            }
            return
        }

        let totalSteps = 16
        var step = 0

        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(15))
        timer.setEventHandler { [weak self] in
            step += 1
            let t = min(Double(step) / Double(totalSteps), 1.0)
            // Ease-out cubic: fast start, slow finish.
            let inv = 1.0 - t
            let eased = 1.0 - inv * inv * inv

            for move in significantMoves {
                let x = move.from.x + (move.to.x - move.from.x) * eased
                let y = move.from.y + (move.to.y - move.from.y) * eased
                self?.accessibilityService.setPosition(CGPoint(x: x, y: y), for: move.window)
            }

            if step >= totalSteps {
                timer.cancel()
                self?.displacementAnimationTimer = nil
            }
        }
        displacementAnimationTimer = timer
        timer.resume()
    }

    /// Shows a highlight border around the current `activeLayoutTarget`.
    private func showHighlightForActiveTarget() {
        guard let frame = activeLayoutTarget?.frame else { return }
        windowHighlightController = WindowHighlightController()
        windowHighlightController?.show(around: frame)
    }

    /// Restores all displaced windows back to their original positions instantly.
    private func restoreDisplacedWindows() {
        guard !displacedWindowFrames.isEmpty else { return }
        for (wid, originalOrigin) in displacedWindowFrames {
            if let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }),
               let window = target.windowElement {
                accessibilityService.setPosition(originalOrigin, for: window)
            }
        }
        displacedWindowFrames.removeAll()
    }

    /// Restores all displaced windows back to their original positions with animation.
    /// Uses a dedicated timer (`restorationAnimationTimer`) that is independent of
    /// the cycling state, so it survives secondary `clearWindowCyclingState()` calls.
    private func restoreDisplacedWindowsAnimated() {
        guard !displacedWindowFrames.isEmpty else { return }

        var moves: [(window: AXUIElement, from: CGPoint, to: CGPoint)] = []
        for (wid, originalOrigin) in displacedWindowFrames {
            if let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }),
               let window = target.windowElement {
                let (currentPos, _) = accessibilityService.readPositionAndSize(of: window)
                moves.append((window: window, from: currentPos, to: originalOrigin))
            }
        }
        displacedWindowFrames.removeAll()

        restorationAnimationTimer?.cancel()
        restorationAnimationTimer = nil

        let significantMoves = moves.filter {
            abs($0.from.x - $0.to.x) > 1 || abs($0.from.y - $0.to.y) > 1
        }
        guard !significantMoves.isEmpty else {
            for move in moves {
                accessibilityService.setPosition(move.to, for: move.window)
            }
            return
        }

        let totalSteps = 16
        var step = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(15))
        timer.setEventHandler { [weak self] in
            step += 1
            let t = min(Double(step) / Double(totalSteps), 1.0)
            let inv = 1.0 - t
            let eased = 1.0 - inv * inv * inv

            for move in significantMoves {
                let x = move.from.x + (move.to.x - move.from.x) * eased
                let y = move.from.y + (move.to.y - move.from.y) * eased
                self?.accessibilityService.setPosition(CGPoint(x: x, y: y), for: move.window)
            }

            if step >= totalSteps {
                timer.cancel()
                self?.restorationAnimationTimer = nil
            }
        }
        restorationAnimationTimer = timer
        timer.resume()
    }

    /// Checks whether the current `activeLayoutTarget` still exists (its
    /// AX position is queryable).  If the window has disappeared (e.g. a
    /// transient HUD), falls back to the first available window target and
    /// updates the highlight border.
    private func revalidateActiveTarget() {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard let current = activeLayoutTarget,
              let window = current.windowElement else { return }
        // If we can still read the position, the window is alive.
        let (pos, size) = accessibilityService.readPositionAndSize(of: window)
        if size.width > 0 && size.height > 0 { return }

        // Target window has disappeared — switch to the first available.
        guard let fallback = availableWindowTargets.first else { return }
        activeLayoutTarget = fallback
        lastTargetPID = fallback.processIdentifier
        clearResizabilityCache()
        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: fallback)
        windowTargetListVersion += 1
        launchMessage = String(
            format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
            fallback.appName
        )
        windowHighlightController?.hide()
        windowHighlightController = WindowHighlightController()
        windowHighlightController?.show(around: fallback.frame)
    }

    /// If the target's app is hidden (Cmd-H), unhide it so the window becomes
    /// visible before we try to raise/move it.
    /// Returns an updated target with a valid `windowElement` when possible.
    @discardableResult
    private func unhideAppIfNeeded(_ target: WindowTarget) -> WindowTarget {
        guard target.isHidden else { return target }
        let app = NSRunningApplication(processIdentifier: target.processIdentifier)
        app?.unhide()

        // If the target already has a window element, just return it.
        if target.windowElement != nil { return target }

        // For placeholders (windowElement == nil), activate the app and re-capture
        // its frontmost window so we have a real AXUIElement to work with.
        app?.activate()
        // Give the app a moment to unhide and surface its windows.
        // Use RunLoop instead of Thread.sleep so the main thread can
        // continue processing events (e.g. Accessibility notifications)
        // and avoid a CPU spike from queued-up work after the sleep.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.15))

        if let freshTarget = try? accessibilityService.focusedWindowTarget(
            preferredPID: target.processIdentifier
        ) {
            return freshTarget
        }
        return target
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

        if selectedWindowIndices.count > 1 {
            applyToMultipleWindows(selection: selection, secondarySelections: secondarySelections, visibleFrame: visibleFrame, screenFrame: screenFrame)
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

    @objc private func handleStatusItemButtonClick() {
        debugLog("handleStatusItemButtonClick start")
        if isEditingSettings {
            cancelSettingsEditing()
            openMainWindow()
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

    func updateLayoutPreview(_ selection: GridSelection?, screenContext: ScreenContext? = nil, colorIndex: Int? = nil) {
        guard isShowingLayoutGrid else {
            hidePreviewOverlay()
            return
        }
        guard let selection else {
            hidePreviewOverlay()
            return
        }

        let previewScreenFrame: CGRect
        let previewVisibleFrame: CGRect
        if let ctx = screenContext,
           let screen = NSScreen.screens.first(where: { $0.frame == ctx.screenFrame }) {
            // Use current screen values to avoid stale ScreenContext.
            previewScreenFrame = screen.frame
            previewVisibleFrame = screen.visibleFrame
        } else if let ctx = screenContext {
            previewScreenFrame = ctx.screenFrame
            previewVisibleFrame = ctx.visibleFrame
        } else if let target = activeLayoutTarget,
                  let screen = NSScreen.screens.first(where: { $0.frame == target.screenFrame }) {
            previewScreenFrame = screen.frame
            previewVisibleFrame = screen.visibleFrame
        } else if let target = activeLayoutTarget {
            previewScreenFrame = target.screenFrame
            previewVisibleFrame = target.visibleFrame
        } else {
            hidePreviewOverlay()
            return
        }

        if layoutPreviewController == nil ||
            layoutPreviewController?.screenFrame != previewScreenFrame ||
            layoutPreviewController?.visibleFrame != previewVisibleFrame {
            layoutPreviewController?.hide()
            layoutPreviewController = LayoutPreviewOverlayController(
                screenFrame: previewScreenFrame,
                visibleFrame: previewVisibleFrame
            )
        }

        let parentWindow = windowControllerForScreen(frame: previewScreenFrame)?.nsWindow
            ?? targetWindowController?.nsWindow

        let resizability = resizabilityForActiveTarget()
        let windowSize = activeLayoutTarget?.frame.size
        let appIcon: NSImage? = activeLayoutTarget.flatMap {
            NSRunningApplication(processIdentifier: $0.processIdentifier)?.icon
        }

        layoutPreviewController?.showSelection(
            selection,
            rows: rows,
            columns: columns,
            gap: gap,
            behind: parentWindow,
            resizability: resizability,
            windowSize: windowSize,
            appIcon: appIcon,
            windowTitle: activeLayoutTarget?.windowTitle,
            appName: activeLayoutTarget?.appName,
            colorIndex: colorIndex
        )
    }

    /// Shows preview rectangles for multiple selections mapped to selected windows.
    func updateLayoutPreviewForPreset(_ preset: LayoutPreset, screenContext: ScreenContext? = nil) {
        guard isShowingLayoutGrid else {
            hidePreviewOverlay()
            return
        }

        let allSelections = preset.allScaledSelections(toRows: rows, columns: columns)
        guard !allSelections.isEmpty else {
            hidePreviewOverlay()
            return
        }

        // If only one selection or single window, fall back to normal preview.
        if allSelections.count <= 1 || selectedWindowIndices.count <= 1 {
            updateLayoutPreview(allSelections.first, screenContext: screenContext)
            return
        }

        let previewScreenFrame: CGRect
        let previewVisibleFrame: CGRect
        if let ctx = screenContext,
           let screen = NSScreen.screens.first(where: { $0.frame == ctx.screenFrame }) {
            previewScreenFrame = screen.frame
            previewVisibleFrame = screen.visibleFrame
        } else if let ctx = screenContext {
            previewScreenFrame = ctx.screenFrame
            previewVisibleFrame = ctx.visibleFrame
        } else if let target = activeLayoutTarget,
                  let screen = NSScreen.screens.first(where: { $0.frame == target.screenFrame }) {
            previewScreenFrame = screen.frame
            previewVisibleFrame = screen.visibleFrame
        } else if let target = activeLayoutTarget {
            previewScreenFrame = target.screenFrame
            previewVisibleFrame = target.visibleFrame
        } else {
            hidePreviewOverlay()
            return
        }

        if layoutPreviewController == nil ||
            layoutPreviewController?.screenFrame != previewScreenFrame ||
            layoutPreviewController?.visibleFrame != previewVisibleFrame {
            layoutPreviewController?.hide()
            layoutPreviewController = LayoutPreviewOverlayController(
                screenFrame: previewScreenFrame,
                visibleFrame: previewVisibleFrame
            )
        }

        let parentWindow = windowControllerForScreen(frame: previewScreenFrame)?.nsWindow
            ?? targetWindowController?.nsWindow

        // Order selected window indices by selection order (first selected = primary).
        let orderedIndices = selectionOrder.filter { $0 < availableWindowTargets.count }

        // Build preview items: map each window to its selection.
        var items: [SelectionPreviewItem] = []
        for (windowPosition, idx) in orderedIndices.enumerated() {
            let selectionIndex = min(windowPosition, allSelections.count - 1)
            let sel = allSelections[selectionIndex]
            let target = availableWindowTargets[idx]
            let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
            items.append(SelectionPreviewItem(
                selection: sel,
                resizability: windowPosition == 0 ? resizabilityForActiveTarget() : .both,
                windowSize: target.frame.size,
                appIcon: appIcon,
                windowTitle: target.windowTitle,
                appName: target.appName
            ))
        }

        layoutPreviewController?.showMultipleSelections(
            items,
            rows: rows,
            columns: columns,
            gap: gap,
            behind: parentWindow
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
            layoutPreviewController?.hide()
            layoutPreviewController = makeLayoutPreviewController(for: target)
        }
        layoutPreviewController?.showGrid(
            rows: settings.rows,
            columns: settings.columns,
            gap: settings.gap,
            behind: targetWindowController?.nsWindow
        )
    }

    func hidePreviewOverlay() {
        layoutPreviewController?.hide()
        layoutPreviewController = nil
    }

    /// Immediately dismisses the overlay, layout grid, and all main windows
    /// so the user doesn't wait for subsequent (potentially slow) AX operations.
    private func dismissOverlayImmediately() {
        windowHighlightController?.hide()
        windowHighlightController = nil
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        hideAllMainWindows()
    }

    /// Returns the resize capability of the active layout target window,
    /// caching the result per PID to avoid repeated probes.
    private func resizabilityForActiveTarget() -> WindowResizability {
        guard let target = activeLayoutTarget else { return .both }
        // Return cached result if we're still targeting the same process.
        if let cached = cachedResizability, cachedResizabilityPID == target.processIdentifier {
            return cached
        }
        guard let window = target.windowElement else { return .both }
        let result = accessibilityService.detectResizability(of: window)
        cachedResizability = result
        cachedResizabilityPID = target.processIdentifier
        return result
    }

    private func clearResizabilityCache() {
        cachedResizability = nil
        cachedResizabilityPID = nil
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

    private func allDisplayShortcuts(isGlobal: Bool) -> [HotKeyShortcut] {
        allDisplayShortcutSlots(isGlobal: isGlobal).map(\.1)
    }

    /// Returns (keyPath identifier, shortcut) pairs for all assigned display shortcuts.
    private func allDisplayShortcutSlots(isGlobal: Bool) -> [(String, HotKeyShortcut)] {
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
        applyPresetOnMouseScreen(id: id)
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
        let target: WindowTarget
        if let existing = activeLayoutTarget {
            target = existing
        } else {
            guard let resolved = resolveWindowTarget() else { return }
            target = resolved
        }

        activeLayoutTarget = target
        lastTargetPID = target.processIdentifier
        let selection = preset.scaledSelection(toRows: rows, columns: columns)
        if selectedWindowIndices.count > 1 {
            let secondarySelections = preset.scaledSecondarySelections(toRows: rows, columns: columns)
            applyToMultipleWindows(selection: selection, secondarySelections: secondarySelections)
        } else {
            apply(selection: selection, to: target)
        }
        TelemetryDeck.signal("presetApplied", parameters: ["presetName": preset.name])
    }

    /// Applies a layout preset on the screen where the mouse cursor is located.
    /// Falls back to the target window's screen when the cursor screen cannot be determined.
    private func applyPresetOnMouseScreen(id: UUID) {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            applyLayoutPresetOnScreen(id: id, visibleFrame: screen.visibleFrame, screenFrame: screen.frame)
        } else {
            applyLayoutPreset(id: id)
        }
    }

    func handleLocalShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard isShowingLayoutGrid, !isEditingSettings else { return false }
        if let preset = layoutPresets.first(where: { $0.localShortcuts.contains(shortcut) }) {
            applyPresetOnMouseScreen(id: preset.id)
            return true
        }
        if let action = displayShortcutLocalAction(for: shortcut) {
            executeDisplayShortcutLocal(action)
            return true
        }
        return false
    }

    // MARK: - Display movement shortcuts

    private func displayShortcutLocalAction(for shortcut: HotKeyShortcut) -> DisplayHotKeyAction? {
        // Display movement shortcuts are global-only; local shortcuts are not used.
        return nil
    }

    /// Executes a display movement action using the frontmost window (global shortcut path).
    func executeDisplayShortcutGlobal(_ action: DisplayHotKeyAction) {
        guard accessibilityGranted else { return }
        if case .moveToOther = action {
            guard let target = windowManager?.captureFocusedWindow() else { return }
            showDisplayPickerMenu(for: target, isLocal: false)
            return
        }
        guard let target = windowManager?.captureFocusedWindow() else { return }
        moveWindowToDisplay(target: target, action: action)
    }

    /// Executes a display movement action using the overlay's active target (local shortcut path).
    func executeDisplayShortcutLocal(_ action: DisplayHotKeyAction) {
        if case .moveToOther = action {
            // Signal the action bar on the mouse cursor's display to show the popup.
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                moveToOtherDisplayTargetID = screen.displayID
            }
            moveToOtherDisplayRequestVersion += 1
            return
        }
        guard let target = activeLayoutTarget else { return }
        dismissOverlayImmediately()
        moveWindowToDisplay(target: target, action: action)
    }

    private func moveWindowToDisplay(target: WindowTarget, action: DisplayHotKeyAction) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard !screens.isEmpty else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]
        let currentIndex = screens.firstIndex(where: { $0.displayID == currentScreen.displayID }) ?? 0

        let destinationScreen: NSScreen
        switch action {
        case .moveToPrimary:
            guard let primary = NSScreen.screens.first,
                  primary.displayID != currentScreen.displayID else { return }
            destinationScreen = primary

        case .moveToNext:
            guard screens.count > 1 else { return }
            destinationScreen = screens[(currentIndex + 1) % screens.count]

        case .moveToPrevious:
            guard screens.count > 1 else { return }
            destinationScreen = screens[(currentIndex - 1 + screens.count) % screens.count]

        case .moveToOther:
            return // handled separately via popup menu

        case .moveToDisplay(let targetDisplayID):
            guard screens.count > 1,
                  let target = screens.first(where: { $0.displayID == targetDisplayID }),
                  target.displayID != currentScreen.displayID else { return }
            destinationScreen = target
        }

        moveWindowProportionally(target: target, from: currentScreen, to: destinationScreen)
    }

    /// Moves a window to a specific display index (used by the display picker menu).
    func moveWindowToDisplayIndex(_ displayIndex: Int, target: WindowTarget, dismissOverlay: Bool) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard displayIndex < screens.count else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]

        let destinationScreen = screens[displayIndex]
        guard destinationScreen.displayID != currentScreen.displayID else { return }

        if dismissOverlay {
            dismissOverlayImmediately()
        }
        moveWindowProportionally(target: target, from: currentScreen, to: destinationScreen)
    }

    private func moveWindowProportionally(target: WindowTarget, from srcScreen: NSScreen, to dstScreen: NSScreen) {
        let srcVisible = srcScreen.visibleFrame
        let dstVisible = dstScreen.visibleFrame

        let relX = srcVisible.width > 0 ? (target.frame.minX - srcVisible.minX) / srcVisible.width : 0
        let relY = srcVisible.height > 0 ? (target.frame.minY - srcVisible.minY) / srcVisible.height : 0
        let relW = srcVisible.width > 0 ? target.frame.width / srcVisible.width : 1
        let relH = srcVisible.height > 0 ? target.frame.height / srcVisible.height : 1

        let newFrame = CGRect(
            x: (dstVisible.minX + relX * dstVisible.width).rounded(),
            y: (dstVisible.minY + relY * dstVisible.height).rounded(),
            width: (relW * dstVisible.width).rounded(),
            height: (relH * dstVisible.height).rounded()
        )

        do {
            try windowManager?.move(target: target, to: newFrame, onScreenFrame: dstScreen.frame)
        } catch {
            debugLog("moveWindowToDisplay error: \(error)")
        }
    }

    /// Shows a popup menu listing available displays for the "Move to Other Display" action.
    private func showDisplayPickerMenu(for target: WindowTarget, isLocal: Bool) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard screens.count > 1 else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]

        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: NSLocalizedString("Move to Other Display", comment: "Display picker menu header"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        header.attributedTitle = NSAttributedString(string: header.title, attributes: headerAttrs)
        menu.addItem(header)
        menu.addItem(.separator())

        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName
            let title: String
            if screen.displayID == NSScreen.screens.first?.displayID {
                title = "\(name) (\(NSLocalizedString("Primary", comment: "Primary display label")))"
            } else {
                title = name
            }
            let item = NSMenuItem(title: title, action: #selector(AppState.displayPickerMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = DisplayPickerContext(target: target, isLocal: isLocal)
            item.image = Self.screenArrangementImage(highlightDisplayID: screen.displayID, size: 16)
            if screen.displayID == currentScreen.displayID {
                item.state = .on
            }
            menu.addItem(item)
        }

        // Show menu at the mouse cursor location using a temporary transparent window,
        // so the menu works even when Tiley has no visible windows (global shortcut).
        let mouseLocation = NSEvent.mouseLocation
        let menuWindow = NSWindow(
            contentRect: NSRect(x: mouseLocation.x - 1, y: mouseLocation.y - 1, width: 2, height: 2),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        menuWindow.level = .popUpMenu
        menuWindow.backgroundColor = .clear
        menuWindow.isOpaque = false
        menuWindow.orderFront(nil)
        menu.popUp(positioning: nil, at: NSPoint(x: 1, y: 1), in: menuWindow.contentView)
        menuWindow.orderOut(nil)
    }

    /// Renders a ScreenArrangementIcon as an NSImage for use in NSMenu items.
    private static func screenArrangementImage(highlightDisplayID: CGDirectDisplayID, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return true }

            var union = CGRect.null
            for screen in screens { union = union.union(screen.frame) }
            guard union.width > 0, union.height > 0 else { return true }

            let inset: CGFloat = 0.5
            let available = CGSize(width: rect.width - inset * 2, height: rect.height - inset * 2)
            let scale = min(available.width / union.width, available.height / union.height)
            let scaledWidth = union.width * scale
            let scaledHeight = union.height * scale
            let offsetX = (rect.width - scaledWidth) / 2
            let offsetY = (rect.height - scaledHeight) / 2
            let gap: CGFloat = 0.5

            for screen in screens {
                let f = screen.frame
                let x = (f.minX - union.minX) * scale + offsetX + gap
                let y = (union.maxY - f.maxY) * scale + offsetY + gap
                let w = f.width * scale - gap * 2
                let h = f.height * scale - gap * 2
                let screenRect = NSRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                let cornerRadius: CGFloat = 1
                let path = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)
                if screen.displayID == highlightDisplayID {
                    NSColor.labelColor.setFill()
                    path.fill()
                } else {
                    NSColor.tertiaryLabelColor.setFill()
                    path.fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc private func displayPickerMenuAction(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? DisplayPickerContext else { return }
        moveWindowToDisplayIndex(sender.tag, target: context.target, dismissOverlay: context.isLocal)
    }

    // MARK: - Display highlight overlay

    @ObservationIgnored private var displayHighlightWindow: NSWindow?

    /// Shows a red border on the screen matching the given displayID.
    func showDisplayHighlight(displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            hideDisplayHighlight()
            return
        }
        var frame = screen.frame
        // 内蔵ディスプレイはノッチ・角丸を避けるためメニューバー下に描画
        if CGDisplayIsBuiltin(displayID) != 0 {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            frame.size.height -= menuBarHeight
        }
        if let existing = displayHighlightWindow {
            existing.setFrame(frame, display: false)
            (existing.contentView as? DisplayHighlightView)?.frame = NSRect(origin: .zero, size: frame.size)
            existing.orderFront(nil)
            return
        }
        let window = DisplayHighlightWindow(frame: frame)
        window.orderFront(nil)
        displayHighlightWindow = window
    }

    /// Hides the display highlight overlay.
    func hideDisplayHighlight() {
        displayHighlightWindow?.orderOut(nil)
        displayHighlightWindow = nil
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
        hideAllMainWindows()
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
            } else if let lastTargetPID,
                      let name = NSRunningApplication(processIdentifier: lastTargetPID)?.localizedName {
                isShowingLayoutGrid = true
                launchMessage = String(
                    format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                    name
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
        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: target)
        return target
    }

    private func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemButtonClick)
            button.sendAction(on: [.leftMouseUp])
        }
        if let iconURL = resourceBundle.url(forResource: "menu-icon", withExtension: "pdf"),
           let icon = NSImage(contentsOf: iconURL),
           let button = item.button {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            originalMenuIcon = icon
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            item.button?.title = NSLocalizedString("Tiley", comment: "App name fallback title")
        }
        item.menu = nil
        // Show immediately — the template icon adapts to any appearance
        // automatically, so there is no black flash.
        statusItem = item
        // Observe effectiveAppearance changes to redraw badge overlays.
        // Skip .initial; instead delay the first badge application so the
        // button's effectiveAppearance has settled in the menu bar.
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            let newAppearance = button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight])
            DispatchQueue.main.async {
                guard let self, newAppearance != self.lastStatusIconAppearance else { return }
                self.applyStatusItemIcon()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyStatusItemIcon()
        }
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        appearanceObservation?.invalidate()
        appearanceObservation = nil
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

    func setUpdateBadge(_ show: Bool) {
        hasUpdateBadge = show
        lastStatusIconAppearance = nil   // Force redraw on badge state change
        if show && statusItem == nil {
            // Menu icon is hidden — temporarily show it so the badge is visible.
            installStatusItem()
            menuIconTemporarilyShown = true
        }
        if !show && menuIconTemporarilyShown {
            // Restore the hidden state when the badge is cleared.
            menuIconTemporarilyShown = false
            if !menuIconVisible {
                removeStatusItem()
                return
            }
        }
        applyStatusItemIcon()
        applyDockIconBadge()
    }

    /// Updates the status item icon according to the current state.
    /// - Update badge or simulating update: overlay info.circle.fill (red)
    /// - DEBUG build (otherwise): overlay ladybug.fill (green)
    /// - Otherwise: use the original template icon as-is
    private func applyStatusItemIcon() {
        guard !isApplyingStatusIcon else { return }
        isApplyingStatusIcon = true
        defer { isApplyingStatusIcon = false }

        guard let button = statusItem?.button,
              let baseIcon = originalMenuIcon else { return }

        // Determine which badge to display
        let badgeInfo: (symbolName: String, colors: [NSColor])?
        // Get the menu bar foreground color
        let currentAppearance = button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight])
        let menuBarForeground: NSColor
        if let appearance = currentAppearance {
            menuBarForeground = appearance == .vibrantDark ? .white : .black
        } else {
            menuBarForeground = .white
        }

        if hasUpdateBadge || debugSimulateUpdate {
            badgeInfo = ("exclamationmark.circle", [menuBarForeground])
        } else if enableDebugLog {
            badgeInfo = ("ladybug.fill", [.systemGreen, .white])
        } else {
            #if DEBUG
            badgeInfo = ("ladybug.fill", [.systemGreen, .white])
            #else
            badgeInfo = nil
            #endif
        }

        guard let badge = badgeInfo else {
            // No badge — restore the original template icon (template adapts automatically)
            if button.image !== baseIcon {
                baseIcon.isTemplate = true
                button.image = baseIcon
            }
            lastStatusIconAppearance = nil
            return
        }

        // Skip redundant badge redraws when appearance hasn't changed
        if currentAppearance == lastStatusIconAppearance {
            return
        }
        lastStatusIconAppearance = currentAppearance

        let iconSize = baseIcon.size          // 18×18
        let badgeSize: CGFloat = 16
        let margin: CGFloat = 0.5
        let clearDiameter = badgeSize + margin * 2  // 10pt

        guard let symbol = NSImage(systemSymbolName: badge.symbolName,
                                   accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(paletteColors: badge.colors)
            .applying(NSImage.SymbolConfiguration(pointSize: badgeSize, weight: .heavy))
        let coloredSymbol = symbol.withSymbolConfiguration(config) ?? symbol

        // Tint the original icon with the menu bar color
        let tintedBase = NSImage(size: iconSize, flipped: false) { rect in
            baseIcon.draw(in: rect)
            menuBarForeground.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        let composite = NSImage(size: iconSize, flipped: false) { drawRect in
            // 1) Draw the tinted original icon
            tintedBase.draw(in: drawRect)

            // Badge center (bottom-right, offset 3pt right to extend beyond icon edge)
            let centerX = iconSize.width - badgeSize / 2 + 1
            let centerY = badgeSize / 2 - 1

            // 2) Clear the original icon with a circle (slightly lower to match badge visual center)
            let clearRect = NSRect(
                x: centerX - clearDiameter / 2,
                y: centerY - clearDiameter / 2,
                width: clearDiameter,
                height: clearDiameter
            )
            let clearPath = NSBezierPath(ovalIn: clearRect)
            NSGraphicsContext.current?.compositingOperation = .clear
            clearPath.fill()

            // 3) Draw the badge symbol
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let symbolOffsetY: CGFloat = badge.symbolName.hasPrefix("ladybug") ? 1.0 : 0
            let badgeRect = NSRect(
                x: centerX - badgeSize / 2,
                y: centerY - badgeSize / 2 + symbolOffsetY,
                width: badgeSize,
                height: badgeSize
            )
            coloredSymbol.draw(in: badgeRect)

            return true
        }

        composite.isTemplate = false
        button.image = composite
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

    private func registerAllHotKeys() {
        guard !hotKeysYieldedToDebug else { return }
        guard shortcutRecordingSessionCount == 0 else { return }
        registerMainHotKey()
        registerPresetHotKeys()
        registerDisplayHotKeys()
    }

    private func registerMainHotKey() {
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

    private func registerPresetHotKeys() {
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
        unregisterDisplayHotKeys()
    }

    private func registerDisplayHotKeys() {
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

    private func unregisterDisplayHotKeys() {
        for ref in displayHotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        displayHotKeyRefs.removeAll()
        displayHotKeyActions.removeAll()
    }

    // MARK: - Debug/Release hotkey coordination

    private static let debugBundleID = "one.cafebabe.tiley.debug"

    /// Returns true when a debug build of Tiley is running alongside this release build.
    private var isDebugVersionRunning: Bool {
        #if DEBUG
        return false
        #else
        return !NSRunningApplication.runningApplications(withBundleIdentifier: Self.debugBundleID).isEmpty
        #endif
    }

    /// Release build: observe workspace app launch/terminate to yield hotkeys to the debug build.
    private func installDebugHotKeyCoordination() {
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
    @objc private func handleAppDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.debugBundleID else { return }
        unregisterAllHotKeys()
        hotKeysYieldedToDebug = true
    }

    @objc private func handleAppDidTerminate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == Self.debugBundleID else { return }
        hotKeysYieldedToDebug = false
        registerAllHotKeys()
    }
    #endif

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

    func applyDockIconVisibility(isInitialStartup: Bool = false) {
        if dockIconVisible {
            _ = NSApp.setActivationPolicy(.regular)
            applyDockIconBadge()
        } else {
            if isInitialStartup {
                // Activation policy is already .accessory (set in
                // applicationWillFinishLaunching).  Skip the .prohibited
                // → .accessory dance to avoid a use-after-free crash
                // caused by rapid activation policy transitions during
                // early app startup.
                return
            }
            // Switching to .accessory causes macOS to hide all windows and
            // fire windowDidResignKey, which normally resets UI state via
            // handleMainWindowHidden(). Use a flag to suppress that reset.
            let anyVisible = mainWindowControllers.values.contains { $0.isVisible }
            isSwitchingActivationPolicy = true
            // Transition through .prohibited to force macOS to fully
            // de-register the Dock tile, then back to .accessory.
            _ = NSApp.setActivationPolicy(.prohibited)
            _ = NSApp.setActivationPolicy(.accessory)
            if anyVisible {
                // macOS hides windows asynchronously after the policy change.
                // A short delay ensures our restore happens after that.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.isSwitchingActivationPolicy = false
                    for (displayID, controller) in self.mainWindowControllers {
                        if displayID != self.targetScreenDisplayID {
                            controller.show(asKey: true)
                        }
                    }
                    self.targetWindowController?.show(asKey: true)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                isSwitchingActivationPolicy = false
            }
        }
    }

    /// Apply or remove a badge on the Dock icon.
    /// Uses NSDockTile.contentView so the shadow is not clipped even when the badge extends beyond the icon.
    /// The icon is drawn to fill the entire tile, and the badge extends beyond it.
    private func applyDockIconBadge() {
        guard dockIconVisible else { return }
        let dockTile = NSApp.dockTile

        // Determine which badge to display (same priority as the menu icon)
        let badgeInfo: (symbolName: String, colors: [NSColor])?
        if showsUpdateIndicator {
            badgeInfo = ("exclamationmark.circle.fill", [.white, .systemRed])
        } else if enableDebugLog {
            badgeInfo = ("ladybug.circle.fill", [.white, .systemGreen])
        } else {
            #if DEBUG
            badgeInfo = ("ladybug.circle.fill", [.white, .systemGreen])
            #else
            badgeInfo = nil
            #endif
        }

        guard let badge = badgeInfo else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }

        guard let appIcon = NSImage(named: NSImage.applicationIconName) else { return }
        guard let symbol = NSImage(systemSymbolName: badge.symbolName,
                                   accessibilityDescription: nil) else { return }

        let tileSize = dockTile.size
        let view = NSImageView(frame: NSRect(origin: .zero, size: tileSize))
        // Create a composite image with the icon filling the tile and the badge overlapping at the top-right
        let badgeDiameter = tileSize.width * 0.47
        let config = NSImage.SymbolConfiguration(paletteColors: badge.colors)
            .applying(NSImage.SymbolConfiguration(pointSize: badgeDiameter, weight: .bold))
        let coloredSymbol = symbol.withSymbolConfiguration(config) ?? symbol

        let composite = NSImage(size: tileSize, flipped: false) { _ in
            // Draw the icon to fill the entire tile
            appIcon.draw(in: NSRect(origin: .zero, size: tileSize))

            // Place the badge at the top-right (flush with the tile edge)
            let margin: CGFloat = 2
            let badgeRect = NSRect(
                x: tileSize.width - badgeDiameter - margin,
                y: tileSize.height - badgeDiameter - margin,
                width: badgeDiameter,
                height: badgeDiameter
            )

            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -2),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.4).cgColor
            )
            coloredSymbol.draw(in: badgeRect)
            ctx.restoreGState()

            return true
        }

        view.image = composite
        dockTile.contentView = view
        dockTile.display()
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
        migrateRemoveArrowShortcutsFromPresets()
        migrateRemoveSlashShortcutFromPresets()
        sanitizePresetGlobalShortcutEligibility()
        selectedLayoutPresetID = layoutPresets.first?.id
    }

    /// Remove UpArrow / DownArrow shortcuts from layout presets.
    /// These keys are now reserved for window cycling (↑/↓).
    private func migrateRemoveArrowShortcutsFromPresets() {
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
    private func migrateRemoveSlashShortcutFromPresets() {
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

    private func saveLayoutPresets() {
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

    private func handleMainWindowHidden(displayID: CGDirectDisplayID) {
        // During an activation-policy switch the window is temporarily hidden
        // by macOS. Don't reset UI state — the window will be restored shortly.
        guard !isSwitchingActivationPolicy else { return }
        // During window controller recreation the old windows are dismissed.
        // Don't reset UI state — new windows are about to be shown.
        guard !isRecreatingWindows else { return }
        // If any Tiley window is still visible, don't reset state.
        let anyVisible = mainWindowControllers.values.contains { $0.isVisible }
        if anyVisible { return }
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingPermissionsOnly = false
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        clearResizabilityCache()
        clearWindowCyclingState()
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
        if isShowingLayoutGrid {
            cancelLayoutGrid()
            return true
        }
        return false
    }

    private var targetWindowController: MainWindowController? {
        guard let id = targetScreenDisplayID else { return nil }
        return mainWindowControllers[id]
    }

    private func windowControllerForScreen(frame screenFrame: CGRect) -> MainWindowController? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) else { return nil }
        return mainWindowControllers[screen.displayID]
    }

    private func openMainWindow() {
        debugLog("openMainWindow start (isShowingLayoutGrid=\(isShowingLayoutGrid ? 1 : 0), isEditingSettings=\(isEditingSettings ? 1 : 0))")
        if isEditingSettings || isShowingPermissionsOnly {
            openTargetScreenWindow()
        } else if isShowingLayoutGrid {
            NSApp.activate(ignoringOtherApps: true)
            openAllScreenWindows()
        } else {
            openTargetScreenWindow()
        }
    }

    private func openTargetScreenWindow() {
        openTargetScreenWindow(on: targetScreenForWindow())
    }

    private func openTargetScreenWindow(on targetScreen: NSScreen) {
        let displayID = targetScreen.displayID
        targetScreenDisplayID = displayID

        // Use dismissSilently() to avoid triggering handleMainWindowHidden
        // which would re-register preset global hotkeys and reset state.
        // Set isRecreatingWindows to suppress windowDidResignKey state resets
        // that occur when the old key window is ordered out during recreation.
        isRecreatingWindows = true
        for controller in mainWindowControllers.values {
            controller.dismissSilently()
        }

        if !isEditingSettings, let existingCtrl = mainWindowControllers[displayID] {
            // Reuse existing controller — just update state and show.
            // Discard secondary controllers that are no longer needed.
            mainWindowControllers = mainWindowControllers.filter { $0.key == displayID }
            existingCtrl.prepareForReuse(screenRole: .target, targetScreen: targetScreen)
            NSApp.activate(ignoringOtherApps: true)
            selectedLayoutPresetID = nil
            existingCtrl.show()
        } else {
            // Always recreate when entering settings to avoid stale SwiftUI
            // layout state that causes Toggle switch knobs to render incorrectly.
            mainWindowControllers.removeAll()
            mainWindowControllers[displayID] = createWindowController(for: targetScreen, isTarget: true)
            NSApp.activate(ignoringOtherApps: true)
            selectedLayoutPresetID = nil
            mainWindowControllers[displayID]?.show()
        }
        isRecreatingWindows = false
    }

    private func openAllScreenWindows() {
        let perfStart = CFAbsoluteTimeGetCurrent()
        func perfLog(_ label: String) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
            debugLog("openAllScreenWindows: \(label) (t=\(String(format: "%.1f", elapsed))ms)")
        }
        let screens = NSScreen.screens
        perfLog("start (screens=\(screens.count))")
        guard !screens.isEmpty else { return }

        let targetScreen: NSScreen
        if let screenFrame = activeLayoutTarget?.screenFrame,
           let screen = NSScreen.screen(containing: screenFrame) {
            targetScreen = screen
        } else {
            targetScreen = NSScreen.main ?? screens.first!
        }
        targetScreenDisplayID = targetScreen.displayID

        let currentDisplayIDs = Set(screens.map { $0.displayID })
        let cachedDisplayIDs = Set(mainWindowControllers.keys)
        let canReuse = currentDisplayIDs == cachedDisplayIDs && !cachedDisplayIDs.isEmpty

        // Use dismissSilently() to avoid triggering handleMainWindowHidden
        // which would re-register preset global hotkeys and reset state.
        // Set isRecreatingWindows to suppress windowDidResignKey state resets
        // that occur when the old key window is ordered out during recreation.
        isRecreatingWindows = true
        for controller in mainWindowControllers.values {
            controller.dismissSilently()
        }

        if canReuse {
            // --- Reuse path: same screens, just update state and show ---
            // prepareForReuse is <1ms so we show ALL windows synchronously.
            perfLog("reusing controllers")
            selectedLayoutPresetID = nil

            let targetCtrl = mainWindowControllers[targetScreen.displayID]!
            targetCtrl.prepareForReuse(screenRole: .target, targetScreen: targetScreen)
            targetCtrl.show(asKey: true)
            perfLog("target window shown (reused)")

            for screen in screens where screen.displayID != targetScreen.displayID {
                if let ctrl = mainWindowControllers[screen.displayID] {
                    ctrl.prepareForReuse(
                        screenRole: .secondary(screen: screen),
                        targetScreen: screen
                    )
                    ctrl.show(asKey: false)
                }
            }
            perfLog("all windows shown (reused)")
            isRecreatingWindows = false
        } else {
            // --- Recreate path: screen configuration changed ---
            mainWindowControllers.removeAll()
            perfLog("dismissed old controllers (recreate)")

            selectedLayoutPresetID = nil
            mainWindowControllers[targetScreen.displayID] = createWindowController(for: targetScreen, isTarget: true)
            mainWindowControllers[targetScreen.displayID]?.show(asKey: true)
            perfLog("target window shown (new)")

            let secondaryScreens = screens.filter { $0.displayID != targetScreen.displayID }
            if secondaryScreens.isEmpty {
                perfLog("all windows shown (single screen, new)")
                isRecreatingWindows = false
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    for screen in secondaryScreens {
                        let displayID = screen.displayID
                        self.mainWindowControllers[displayID] = self.createWindowController(for: screen, isTarget: false)
                        self.mainWindowControllers[displayID]?.show(asKey: false)
                    }
                    perfLog("secondary windows shown (deferred, new)")
                    self.isRecreatingWindows = false
                }
            }
        }
    }

    private func closeSecondaryWindows() {
        for (displayID, controller) in mainWindowControllers {
            if displayID != targetScreenDisplayID {
                controller.dismissSilently()
            }
        }
        mainWindowControllers = mainWindowControllers.filter { $0.key == targetScreenDisplayID }
    }

    private func hideAllMainWindows() {
        for controller in mainWindowControllers.values {
            controller.hide()
        }
    }

    private func targetScreenForWindow() -> NSScreen {
        if let screenFrame = activeLayoutTarget?.screenFrame,
           let screen = NSScreen.screen(containing: screenFrame) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    private func createWindowController(for screen: NSScreen, isTarget: Bool) -> MainWindowController {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let displayID = screen.displayID
        let role: ScreenRole = isTarget ? .target : .secondary(screen: screen)

        let controller = MainWindowController(
            appState: self,
            screenRole: role,
            targetScreen: screen,
            onHide: { [weak self] in
                Task { @MainActor in
                    self?.handleMainWindowHidden(displayID: displayID)
                }
            },
            onEscape: { [weak self] in
                guard let self else { return false }
                return self.handleMainWindowEscape()
            },
            onLocalShortcut: { [weak self] shortcut in
                guard let self else { return false }
                return self.handleLocalShortcut(shortcut)
            },
            onKeyCommand: { [weak self] event in
                guard let self else { return false }
                return self.handleMainWindowKeyCommand(event)
            }
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("createWindowController displayID=\(displayID) isTarget=\(isTarget ? 1 : 0) (\(String(format: "%.1f", elapsed))ms)")
        return controller
    }

    private func handleMainWindowKeyCommand(_ event: NSEvent) -> Bool {
        guard !isEditingSettings else { return false }

        // Check configurable window cycling shortcuts.
        let eventShortcut = HotKeyShortcut.from(event: event, requireModifiers: false)
        if let shortcut = eventShortcut {
            if displayShortcutSettings.selectNextWindow.localEnabled,
               let s = displayShortcutSettings.selectNextWindow.local, s == shortcut {
                cycleTargetWindow(forward: true)
                return true
            }
            if displayShortcutSettings.selectPreviousWindow.localEnabled,
               let s = displayShortcutSettings.selectPreviousWindow.local, s == shortcut {
                cycleTargetWindow(forward: false)
                return true
            }
            if displayShortcutSettings.bringToFront.localEnabled,
               let s = displayShortcutSettings.bringToFront.local, s == shortcut {
                if selectedWindowIndices.count > 1 {
                    raiseSelectedWindows()
                } else {
                    raiseCurrentTargetWindow()
                }
                return true
            }
            if displayShortcutSettings.closeOrQuit.localEnabled,
               let s = displayShortcutSettings.closeOrQuit.local, s == shortcut {
                if selectedWindowIndices.count > 1 {
                    closeSelectedWindows()
                } else {
                    let idx = activeTargetIndex
                    if idx >= 0, idx < availableWindowTargets.count {
                        let target = availableWindowTargets[idx]
                        let isFinder = NSRunningApplication(processIdentifier: target.processIdentifier)?.bundleIdentifier == "com.apple.finder"
                        let windowCount = availableWindowTargets.filter { $0.processIdentifier == target.processIdentifier }.count
                        if isFinder || windowCount > 1 {
                            closeWindowTarget(at: idx)
                        } else {
                            quitApp(at: idx)
                        }
                    }
                }
                return true
            }
        }

        switch Int(event.keyCode) {
        case kVK_ANSI_Slash where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
            if selectedWindowIndices.count > 1 {
                closeSelectedWindows()
            } else {
                let idx = activeTargetIndex
                if idx >= 0, idx < availableWindowTargets.count {
                    let target = availableWindowTargets[idx]
                    let isFinder = NSRunningApplication(processIdentifier: target.processIdentifier)?.bundleIdentifier == "com.apple.finder"
                    let windowCount = availableWindowTargets.filter { $0.processIdentifier == target.processIdentifier }.count
                    if isFinder || windowCount > 1 {
                        closeWindowTarget(at: idx)
                    } else {
                        quitApp(at: idx)
                    }
                }
            }
            return true
        case kVK_ANSI_A where event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command:
            selectAllWindows()
            return true
        case kVK_ANSI_F where event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command:
            // Handled in MainWindowController.performKeyEquivalent which checks first responder.
            return false
        default:
            return false
        }
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

        appDeactivationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didResignActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleAppDidResignActive()
                }
            }
        }

        screenChangeTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleScreenConfigurationChange()
                }
            }
        }

        Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: Notification.Name("NSWorkspaceDidChangeDesktopImageNotification")
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.desktopImageVersion += 1
                    // Redraw the badge icon tint color to match the light/dark appearance
                    self?.applyStatusItemIcon()
                }
            }
        }
    }

    private func handleScreenConfigurationChange() {
        // Re-register display hotkeys so newly connected displays become active
        // and disconnected display hotkeys are cleaned up.
        registerDisplayHotKeys()
        guard isShowingLayoutGrid, !isEditingSettings, !isShowingPermissionsOnly else { return }
        openAllScreenWindows()
    }

    private func handleAppDidResignActive() {
        guard !isSwitchingActivationPolicy else { return }
        guard !isRecreatingWindows else { return }
        guard !isShowingPermissionsOnly else { return }
        hidePreviewOverlay()
        hideMainWindow()
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
    static let windowListSidebarVisible = "windowListSidebarVisible"
    static let quitAppOnLastWindowClose = "quitAppOnLastWindowClose"
    static let enableDebugLog = "enableDebugLog"
    static let debugSimulateUpdate = "debugSimulateUpdate"
    static let displayShortcuts = "displayShortcuts"
}

private final class DisplayPickerContext: NSObject {
    let target: WindowTarget
    let isLocal: Bool
    init(target: WindowTarget, isLocal: Bool) {
        self.target = target
        self.isLocal = isLocal
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}

private final class DisplayHighlightWindow: NSWindow {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = DisplayHighlightView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = view
    }
}

private final class DisplayHighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setStroke()
        let borderWidth: CGFloat = 4
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth
        path.stroke()
    }
}

private final class TaggableView: NSView {
    var assignedTag: Int = 0
    override var tag: Int { assignedTag }
}


