import AppKit
import Carbon
import Observation
import ServiceManagement
import Sparkle
import SwiftUI

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
        var useAppleScriptResize: Bool
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
    var useAppleScriptResize = false {
        didSet { UserDefaults.standard.set(useAppleScriptResize, forKey: UserDefaultsKey.useAppleScriptResize) }
    }
    var layoutPresets: [LayoutPreset] = []
    var selectedLayoutPresetID: UUID?
    var launchMessage = NSLocalizedString("Show the grid from the menu bar or use the global shortcut.", comment: "Initial launch message")

    @ObservationIgnored var updater: SPUUpdater?
    private(set) var hasUpdateBadge = false
    @ObservationIgnored private var menuIconTemporarilyShown = false

    @ObservationIgnored private let accessibilityService = AccessibilityService()
    @ObservationIgnored private var windowManager: WindowManager?
    @ObservationIgnored private var statusItem: NSStatusItem?
    @ObservationIgnored private var mainWindowControllers: [CGDirectDisplayID: MainWindowController] = [:]
    @ObservationIgnored private var targetScreenDisplayID: CGDirectDisplayID?
    @ObservationIgnored private var screenChangeTask: Task<Void, Never>?
    @ObservationIgnored private var isSwitchingActivationPolicy = false
    @ObservationIgnored private(set) var isRecreatingWindows = false
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
    @ObservationIgnored private var cachedResizability: WindowResizability?
    @ObservationIgnored private var cachedResizabilityPID: pid_t?
    @ObservationIgnored private var layoutPreviewController: LayoutPreviewOverlayController?
    @ObservationIgnored private var availableWindowTargets: [WindowTarget] = []
    @ObservationIgnored private var activeTargetIndex: Int = 0
    @ObservationIgnored private var originalFrontmostPID: pid_t?
    /// Whether the user has cycled the target window at least once via Tab.
    var hasUsedTabCycling: Bool { originalFrontmostPID != nil }
    var windowTargetListVersion: Int = 0
    /// Incremented to signal the UI to toggle the window list sidebar.
    var windowTargetMenuRequestVersion: Int = 0
    /// Incremented to signal Cmd+F when search field is NOT focused: show sidebar and focus search.
    var windowSearchFocusRequestVersion: Int = 0
    /// Incremented to signal Cmd+F when search field IS focused: hide sidebar.
    var windowSearchHideRequestVersion: Int = 0
    /// Current window search query, synced from the UI for filtered cycling.
    var windowSearchQuery: String = ""
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
            useAppleScriptResize: useAppleScriptResize
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

    var windowTargetList: [WindowTarget] {
        _ = windowTargetListVersion
        return availableWindowTargets
    }

    var currentWindowTargetIndex: Int {
        _ = windowTargetListVersion
        return activeTargetIndex
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
        _ = updateLaunchAtLogin(enabled: settings.launchAtLoginEnabled, updateMessageOnFailure: true)
        setMenuIconVisible(settings.menuIconVisible)
        setDockIconVisible(settings.dockIconVisible)
        quitAppOnLastWindowClose = settings.quitAppOnLastWindowClose
        useAppleScriptResize = settings.useAppleScriptResize
        sanitizePresetGlobalShortcutEligibility()
        // Only register the main toggle hotkey; keep preset global hotkeys
        // unregistered while the layout grid is visible so local shortcuts work.
        unregisterPresetHotKeys()
        registerMainHotKey()
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingLayoutGrid = true
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Applied grid settings.", comment: "Settings applied confirmation")
        openMainWindow()
    }

    func cancelSettingsEditing() {
        hidePreviewOverlay()
        isEditingSettings = false
        isShowingLayoutGrid = true
        // Only register the main toggle hotkey; keep preset global hotkeys
        // unregistered while the layout grid is visible so local shortcuts work.
        unregisterPresetHotKeys()
        registerMainHotKey()
        activeLayoutTarget = initialLayoutTarget()
        launchMessage = NSLocalizedString("Canceled settings changes.", comment: "Settings canceled confirmation")
        openMainWindow()
    }

    func beginSettingsEditing() {
        activeLayoutTarget = initialLayoutTarget()
        unregisterAllHotKeys()
        isShowingLayoutGrid = false
        isEditingSettings = true
        closeSecondaryWindows()
        openMainWindow()
    }

    func toggleOverlay() {
        refreshAccessibilityState()
        guard accessibilityGranted else {
            showPermissionsOnly()
            return
        }

        if isShowingLayoutGrid {
            NSApp.activate(ignoringOtherApps: true)
            windowTargetMenuRequestVersion += 1
            return
        }

        guard let target = resolveWindowTarget() else { return }

        activeLayoutTarget = target
        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: target)
        lastTargetPID = target.processIdentifier
        originalFrontmostPID = nil
        refreshAvailableWindows()
        isEditingSettings = false
        // Unregister preset global hotkeys while the overlay is visible so that
        // key events reach the NSWindow's performKeyEquivalent and can be handled
        // as local shortcuts. They are re-registered in handleMainWindowHidden().
        unregisterPresetHotKeys()
        windowSearchQuery = ""
        isShowingLayoutGrid = true
        openMainWindow()
        // Bump version after the window is open so the view picks up the latest
        // target info and window list.
        windowTargetListVersion += 1
        launchMessage = String(
            format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
            target.appName
        )
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
        apply(selection: selection, to: target)
    }

    func cancelLayoutGrid() {
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        clearResizabilityCache()
        hideAllMainWindows()
        // Reactivate the original app (before any Tab cycling), not the current target.
        if let originalPID = originalFrontmostPID {
            NSRunningApplication(processIdentifier: originalPID)?.activate()
        } else {
            _ = reactivateLastTargetApp(clearingState: false)
        }
        clearWindowCyclingState()
        launchMessage = NSLocalizedString("Canceled layout selection.", comment: "Layout selection canceled")
    }

    func cycleTargetWindow(forward: Bool) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }

        refreshAvailableWindows()
        guard !availableWindowTargets.isEmpty else { return }

        // Record the original frontmost app on first cycle.
        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
        }

        // Build filtered index list based on search query.
        let query = windowSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filteredIndices: [Int]
        if query.isEmpty {
            filteredIndices = Array(availableWindowTargets.indices)
        } else {
            filteredIndices = availableWindowTargets.indices.filter { i in
                let target = availableWindowTargets[i]
                let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return target.appName.lowercased().contains(query)
                    || title.lowercased().contains(query)
            }
        }
        guard !filteredIndices.isEmpty else { return }

        if let currentPos = filteredIndices.firstIndex(of: activeTargetIndex) {
            let nextPos = forward
                ? (currentPos + 1) % filteredIndices.count
                : (currentPos - 1 + filteredIndices.count) % filteredIndices.count
            activeTargetIndex = filteredIndices[nextPos]
        } else {
            activeTargetIndex = forward ? filteredIndices.first! : filteredIndices.last!
        }

        applyTargetAtCurrentIndex()
    }

    func selectWindowTarget(at index: Int) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard index >= 0, index < availableWindowTargets.count else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
        }

        activeTargetIndex = index
        applyTargetAtCurrentIndex()
    }

    /// Raises (brings to front) the currently selected target window and activates its app.
    func raiseCurrentTargetWindow() {
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        guard activeTargetIndex >= 0, activeTargetIndex < availableWindowTargets.count else { return }
        let target = availableWindowTargets[activeTargetIndex]
        if let window = target.windowElement {
            accessibilityService.raiseWindow(window)
        }
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate()
    }

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
    }

    func refreshAvailableWindows() {
        availableWindowTargets = windowManager?.captureAllWindows() ?? []
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
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        clearResizabilityCache()
        hideAllMainWindows()
        if let window = target.windowElement {
            accessibilityService.raiseWindow(window)
        }
        NSRunningApplication(processIdentifier: target.processIdentifier)?.activate()
        clearWindowCyclingState()
    }

    func closeWindowTarget(at index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]

        // Check if this is the last window of its app.
        let isLastWindow = availableWindowTargets.filter {
            $0.processIdentifier == target.processIdentifier
        }.count == 1

        // Remember where the selection should land after the window disappears.
        // The closed window will be removed, so `index` will point at the next one.
        // If it was the last item, clamp to the new last item.
        pendingTargetIndexAfterClose = index

        if isLastWindow && quitAppOnLastWindowClose {
            NSRunningApplication(processIdentifier: target.processIdentifier)?.terminate()
        } else if let window = target.windowElement {
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

    private func clearWindowCyclingState() {
        originalFrontmostPID = nil
        availableWindowTargets = []
        activeTargetIndex = 0
        windowTargetListVersion += 1
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
        Thread.sleep(forTimeInterval: 0.15)

        if let freshTarget = try? accessibilityService.focusedWindowTarget(
            preferredPID: target.processIdentifier
        ) {
            return freshTarget
        }
        return target
    }

    func apply(selection: GridSelection, to target: WindowTarget) {
        let target = unhideAppIfNeeded(target)
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

        do {
            let constrained: Bool
            if useAppleScriptResize {
                try windowManager?.moveWithLog(target: target, to: frame, on: target.screenFrame)
            }
            constrained = try windowManager?.move(target: target, to: frame) ?? false
            windowManager?.raiseWindow(target: target)
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: constrained)
        } catch {
            NSLog("[Tiley] apply(selection:to:) error: %@", error.localizedDescription)
            launchMessage = error.localizedDescription
        }
    }

    /// Commits a layout selection on a specific screen (used by multi-screen grid/preset interactions).
    func commitLayoutSelectionOnScreen(_ selection: GridSelection, visibleFrame: CGRect, screenFrame: CGRect) {
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

        do {
            let constrained: Bool
            if useAppleScriptResize {
                try windowManager?.moveWithLog(target: target, to: frame, on: currentScreenFrame)
            }
            constrained = try windowManager?.move(target: target, to: frame, onScreenFrame: currentScreenFrame) ?? false
            windowManager?.raiseWindow(target: target)
            recordSelectionAndHide(selection: selection, appName: target.appName, wasConstrained: constrained)
        } catch {
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
        commitLayoutSelectionOnScreen(selection, visibleFrame: visibleFrame, screenFrame: screenFrame)
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
        hidePreviewOverlay()
        activeLayoutTarget = nil
        clearResizabilityCache()
        isShowingLayoutGrid = false
        hideAllMainWindows()
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
        clearWindowCyclingState()
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

    func updateLayoutPreview(_ selection: GridSelection?, screenContext: ScreenContext? = nil) {
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

        layoutPreviewController?.showSelection(
            selection,
            rows: rows,
            columns: columns,
            gap: gap,
            behind: parentWindow,
            resizability: resizability,
            windowSize: windowSize
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

    func layoutShortcutConflictMessage(for shortcut: HotKeyShortcut, excluding presetID: UUID) -> String? {
        // Tab and Shift+Tab are reserved for window target cycling.
        if shortcut.keyCode == UInt32(kVK_Tab),
           shortcut.modifiers == 0 || shortcut.modifiers == UInt32(shiftKey) {
            return NSLocalizedString("Tab is reserved for switching target windows.", comment: "Tab shortcut reserved for window cycling")
        }

        // Return is reserved for raising the selected window.
        if shortcut.keyCode == UInt32(kVK_Return),
           shortcut.modifiers == 0 {
            return NSLocalizedString("Return is reserved for raising the selected window.", comment: "Return shortcut reserved for raising window")
        }

        // Up/Down arrows are reserved for window cycling.
        if (shortcut.keyCode == UInt32(kVK_UpArrow) || shortcut.keyCode == UInt32(kVK_DownArrow)),
           shortcut.modifiers == 0 {
            return NSLocalizedString("Arrow keys are reserved for switching target windows.", comment: "Arrow key shortcut reserved for window cycling")
        }

        // "/" is reserved for closing the selected window.
        if shortcut.keyCode == UInt32(kVK_ANSI_Slash),
           shortcut.modifiers == 0 {
            return NSLocalizedString("/ is reserved for closing the selected window.", comment: "Slash shortcut reserved for closing window")
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
        apply(selection: selection, to: target)
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
        guard let preset = layoutPresets.first(where: { $0.localShortcuts.contains(shortcut) }) else { return false }
        applyPresetOnMouseScreen(id: preset.id)
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
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            item.button?.title = NSLocalizedString("Tiley", comment: "App name fallback title")
        }
        item.menu = nil
        statusItem = item
        if hasUpdateBadge {
            applyUpdateBadgeIcon()
        }
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

    func setUpdateBadge(_ show: Bool) {
        hasUpdateBadge = show
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
        if show {
            applyUpdateBadgeIcon()
        } else {
            removeUpdateBadgeIcon()
        }
    }

    private static let updateBadgeViewTag = 9999

    private func applyUpdateBadgeIcon() {
        guard let button = statusItem?.button else { return }
        guard button.viewWithTag(Self.updateBadgeViewTag) == nil else { return }
        let badgeDiameter: CGFloat = 6
        let dot = TaggableView(frame: NSRect(
            x: button.bounds.maxX - badgeDiameter,
            y: 0,
            width: badgeDiameter,
            height: badgeDiameter
        ))
        dot.assignedTag = Self.updateBadgeViewTag
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = badgeDiameter / 2
        dot.autoresizingMask = [.minXMargin, .minYMargin]
        button.addSubview(dot)
    }

    private func removeUpdateBadgeIcon() {
        guard let button = statusItem?.button else { return }
        button.viewWithTag(Self.updateBadgeViewTag)?.removeFromSuperview()
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
        if let storedQuitAppOnLastWindowClose = defaults.object(forKey: UserDefaultsKey.quitAppOnLastWindowClose) as? Bool {
            quitAppOnLastWindowClose = storedQuitAppOnLastWindowClose
        }
        if let storedUseAppleScriptResize = defaults.object(forKey: UserDefaultsKey.useAppleScriptResize) as? Bool {
            useAppleScriptResize = storedUseAppleScriptResize
        }
        refreshLaunchAtLoginState()
    }

    func applyDockIconVisibility() {
        if dockIconVisible {
            _ = NSApp.setActivationPolicy(.regular)
        } else {
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
        let targetScreen = targetScreenForWindow()
        let displayID = targetScreen.displayID
        targetScreenDisplayID = displayID

        // Always recreate to ensure fresh ScreenContext and correct role.
        // Use dismissSilently() to avoid triggering handleMainWindowHidden
        // which would re-register preset global hotkeys and reset state.
        // Set isRecreatingWindows to suppress windowDidResignKey state resets
        // that occur when the old key window is ordered out during recreation.
        isRecreatingWindows = true
        for controller in mainWindowControllers.values {
            controller.dismissSilently()
        }
        mainWindowControllers.removeAll()

        mainWindowControllers[displayID] = createWindowController(for: targetScreen, isTarget: true)
        NSApp.activate(ignoringOtherApps: true)
        selectedLayoutPresetID = nil
        mainWindowControllers[displayID]?.show()
        isRecreatingWindows = false
    }

    private func openAllScreenWindows() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let targetScreen: NSScreen
        if let screenFrame = activeLayoutTarget?.screenFrame,
           let screen = NSScreen.screen(containing: screenFrame) {
            targetScreen = screen
        } else {
            targetScreen = NSScreen.main ?? screens.first!
        }
        targetScreenDisplayID = targetScreen.displayID

        // Always recreate all controllers so that ScreenContext (which
        // captures each screen's visibleFrame at init time) stays fresh
        // and roles are always correct for the current target screen.
        // Use dismissSilently() to avoid triggering handleMainWindowHidden
        // which would re-register preset global hotkeys and reset state.
        // Set isRecreatingWindows to suppress windowDidResignKey state resets
        // that occur when the old key window is ordered out during recreation.
        isRecreatingWindows = true
        for controller in mainWindowControllers.values {
            controller.dismissSilently()
        }
        mainWindowControllers.removeAll()

        for screen in screens {
            let displayID = screen.displayID
            let isTarget = (displayID == targetScreenDisplayID)
            mainWindowControllers[displayID] = createWindowController(for: screen, isTarget: isTarget)
        }

        // Show secondary windows first, then target window last so it gets initial key focus.
        selectedLayoutPresetID = nil
        for (displayID, controller) in mainWindowControllers {
            if displayID != targetScreenDisplayID {
                controller.show(asKey: true)
            }
        }
        mainWindowControllers[targetScreenDisplayID ?? 0]?.show(asKey: true)
        isRecreatingWindows = false
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
        let displayID = screen.displayID
        let role: ScreenRole = isTarget ? .target : .secondary(screen: screen)

        return MainWindowController(
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
    }

    private func handleMainWindowKeyCommand(_ event: NSEvent) -> Bool {
        guard !isEditingSettings else { return false }

        switch Int(event.keyCode) {
        case kVK_Tab:
            let isShift = event.modifierFlags.contains(.shift)
            cycleTargetWindow(forward: !isShift)
            return true
        case kVK_UpArrow:
            cycleTargetWindow(forward: false)
            return true
        case kVK_DownArrow:
            cycleTargetWindow(forward: true)
            return true
        case kVK_Return:
            raiseCurrentTargetWindow()
            return true
        case kVK_ANSI_Slash where event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty:
            closeWindowTarget(at: activeTargetIndex)
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
    }

    private func handleScreenConfigurationChange() {
        guard isShowingLayoutGrid, !isEditingSettings, !isShowingPermissionsOnly else { return }
        openAllScreenWindows()
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
    static let useAppleScriptResize = "useAppleScriptResize"
}

private final class TaggableView: NSView {
    var assignedTag: Int = 0
    override var tag: Int { assignedTag }
}
