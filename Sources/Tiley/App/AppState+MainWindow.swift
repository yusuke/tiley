import AppKit
import Carbon

extension AppState {

    // MARK: - Hide / Quit

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

        // If the settings window is already open, just bring it back.
        if isEditingSettings {
            settingsWindowController?.show()
            return
        }

        if showNearIcon {
            let mousePos = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mousePos) }) {
                let sf = screen.frame
                let vf = screen.visibleFrame
                let dockOnBottom = vf.minY - sf.minY > 1
                let dockOnLeft = vf.minX - sf.minX > 1
                let dockOnRight = sf.maxX - vf.maxX > 1
                if dockOnBottom {
                    triggerIconCenter = NSPoint(x: mousePos.x, y: vf.minY)
                } else if dockOnRight {
                    triggerIconCenter = NSPoint(x: vf.maxX, y: mousePos.y)
                } else if dockOnLeft {
                    triggerIconCenter = NSPoint(x: vf.minX, y: mousePos.y)
                }
                triggerIconDisplayID = screen.displayID
            }
        }
        if !isShowingLayoutGrid {
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

        // Populate the sidebar window list — same pattern as toggleOverlay().
        if hasWindowListCache {
            // Realign the cache against the current CG z-order so the sidebar
            // renders the correct order immediately.  See `realignCacheWithLiveZOrder`.
            realignCacheWithLiveZOrder()
            availableWindowTargets = cachedWindowTargets
            spaceList = cachedSpaceList
            activeSpaceIDs = cachedActiveSpaceIDs
            windowTargetListVersion += 1
            if let current = activeLayoutTarget {
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
            selectedWindowIndices = [activeTargetIndex]
            selectionOrder = [activeTargetIndex]
            isLoadingWindowList = false
        } else {
            isLoadingWindowList = true
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // snapToFreshTop: trust the authoritative z-order from CGWindowList
            // over any stale target Phase 1 may have picked via async APIs.
            //
            // Note: `refreshAvailableWindows` is asynchronous.  Clearing
            // `isLoadingWindowList` is handled by `applyRefreshedWindowList`
            // when the capture lands, so the spinner stays visible until
            // real data is populated.
            self.refreshAvailableWindows(snapToFreshTop: true)
            self.revalidateActiveTarget()
        }
        windowTargetListVersion += 1
    }

    @objc func quit() {
        quitApp()
    }

    // MARK: - Window Target Resolution

    func resolveWindowTarget() -> WindowTarget? {
        if let frontmostApp = NSWorkspace.shared.frontmostApplication,
           frontmostApp.processIdentifier == getpid(),
           lastTargetPID == nil {
            launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt when frontmost app is self")
            return nil
        }

        // Get all real standard windows (CGWindowList excludes desktop elements).
        let (allTargets, _, _) = windowManager?.captureAllWindows() ?? ([], [], [])

        if let focused = windowManager?.captureFocusedWindow(preferredPID: lastTargetPID) {
            // Validate the focused window exists in the real window list.
            // Finder's desktop is returned by AX but excluded from CGWindowList,
            // so it won't match here.
            let tolerance: CGFloat = 5
            let isRealWindow = allTargets.contains {
                $0.processIdentifier == focused.processIdentifier
                && abs($0.frame.origin.x - focused.frame.origin.x) < tolerance
                && abs($0.frame.origin.y - focused.frame.origin.y) < tolerance
                && abs($0.frame.width - focused.frame.width) < tolerance
                && abs($0.frame.height - focused.frame.height) < tolerance
            }
            if isRealWindow {
                return focused
            }
            // The focused window is not a real window (e.g. Finder's desktop).
            // Try to find a real window from the same app instead.
            if let sameApp = allTargets.first(where: { $0.processIdentifier == focused.processIdentifier }) {
                debugLog("resolveWindowTarget: focused window is desktop/non-standard, using real window from \(sameApp.appName)")
                return sameApp
            }
            debugLog("resolveWindowTarget: focused window (\(focused.appName)) is desktop/non-standard with no real windows")
        }

        // Frontmost app may have no windows (menu bar app, Finder with no windows, etc.).
        // Fall back to the topmost visible window on screen.
        if let fallback = allTargets.first {
            debugLog("resolveWindowTarget: falling back to topmost visible window: \(fallback.appName)")
            return fallback
        }

        hidePreviewOverlay()
        return nil
    }

    func initialLayoutTarget() -> WindowTarget? {
        guard accessibilityGranted else { return nil }
        let target: WindowTarget?
        if hasWindowListCache {
            // Prefer the AX system-wide focused application over both
            // `lastTargetPID` and `NSWorkspace.frontmostApplication`.  See
            // the equivalent block in `toggleOverlay` for the full rationale.
            let liveFrontmostPID: pid_t? = {
                if let pid = AccessibilityService.focusedApplicationPID(), pid != getpid() {
                    return pid
                }
                if let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   pid != getpid() {
                    return pid
                }
                return nil
            }()
            if let liveFrontmostPID {
                lastTargetPID = liveFrontmostPID
            }
            // Realign the cache against the current CG z-order (fast, ~1–5 ms)
            // so the sidebar renders the correct order immediately.
            realignCacheWithLiveZOrder()
            let preferredPID = liveFrontmostPID ?? lastTargetPID
            target = preferredPID.flatMap { pid in
                cachedWindowTargets.first { $0.processIdentifier == pid }
            } ?? cachedWindowTargets.first
        } else {
            target = resolveWindowTarget()
        }
        guard let target else {
            hidePreviewOverlay()
            return nil
        }
        layoutPreviewController?.hide()
        layoutPreviewController = makeLayoutPreviewController(for: target)
        return target
    }

    // MARK: - Accessibility

    func refreshAccessibilityState() {
        accessibilityGranted = accessibilityService.checkAccess(prompt: false)
    }

    // MARK: - Target App Reactivation

    @discardableResult
    func reactivateLastTargetApp(clearingState: Bool) -> Bool {
        guard let lastTargetPID else { return false }
        let activated = NSRunningApplication(processIdentifier: lastTargetPID)?.activate() ?? false
        if clearingState {
            self.lastTargetPID = nil
        }
        return activated
    }

    func refocusLastTargetApp() {
        guard let lastTargetPID else { return }
        NSRunningApplication(processIdentifier: lastTargetPID)?.activate()
    }

    // MARK: - Main Window Lifecycle

    func handleMainWindowHidden(displayID: CGDirectDisplayID) {
        // During an activation-policy switch the window is temporarily hidden
        // by macOS. Don't reset UI state — the window will be restored shortly.
        guard !isSwitchingActivationPolicy else { return }
        // During window controller recreation the old windows are dismissed.
        // Don't reset UI state — new windows are about to be shown.
        guard !isRecreatingWindows else { return }
        // Settings editing hides main windows but needs activeLayoutTarget to
        // remain set so the grid preview overlay can be shown on hover.
        guard !isEditingSettings else { return }
        // If any Tiley window is still visible, don't reset state.
        let anyVisible = mainWindowControllers.values.contains { $0.isVisible }
        if anyVisible { return }
        removeModifierReleaseMonitor()
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        activeLayoutTarget = nil
        clearResizabilityCache()
        clearWindowCyclingState()
        registerAllHotKeys()
        bubbleArrowEdge = nil
        bubbleArrowDisplayID = nil
        if !NSApp.isActive {
            refocusLastTargetApp()
        }
        // Pre-cache the window list for next overlay open.
        scheduleWindowListCacheRefresh()
    }

    func handleMainWindowEscape() -> Bool {
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

    var targetWindowController: MainWindowController? {
        guard let id = targetScreenDisplayID else { return nil }
        return mainWindowControllers[id]
    }

    func windowControllerForScreen(frame screenFrame: CGRect) -> MainWindowController? {
        guard let screen = NSScreen.screens.first(where: { $0.frame == screenFrame }) else { return nil }
        return mainWindowControllers[screen.displayID]
    }

    func openMainWindow() {
        debugLog("openMainWindow start (isShowingLayoutGrid=\(isShowingLayoutGrid ? 1 : 0))")
        // Reset any stale bubble arrow state from a previous open cycle.
        // If this open was triggered by an icon click, triggerIconCenter is set
        // and MainWindowController.positionWindow() will set bubbleArrowEdge again.
        // Otherwise (global shortcut, settings close, etc.), no arrow should appear.
        if triggerIconCenter == nil {
            bubbleArrowEdge = nil
            bubbleArrowDisplayID = nil
        }
        if isShowingLayoutGrid {
            NSApp.activate(ignoringOtherApps: true)
            openAllScreenWindows()
        } else {
            openTargetScreenWindow()
        }
    }

    func openTargetScreenWindow() {
        openTargetScreenWindow(on: targetScreenForWindow())
    }

    func openTargetScreenWindow(on targetScreen: NSScreen) {
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

        if let existingCtrl = mainWindowControllers[displayID] {
            // Reuse existing controller — just update state and show.
            // Fully remove secondary controllers that are no longer needed.
            for (id, ctrl) in mainWindowControllers where id != displayID {
                ctrl.teardown()
            }
            mainWindowControllers = mainWindowControllers.filter { $0.key == displayID }
            existingCtrl.prepareForReuse(screenRole: .target, targetScreen: targetScreen)
            NSApp.activate(ignoringOtherApps: true)
            selectedLayoutPresetID = nil
            existingCtrl.show()
        } else {
            for controller in mainWindowControllers.values {
                controller.teardown()
            }
            mainWindowControllers.removeAll()
            mainWindowControllers[displayID] = createWindowController(for: targetScreen, isTarget: true)
            NSApp.activate(ignoringOtherApps: true)
            selectedLayoutPresetID = nil
            mainWindowControllers[displayID]?.show()
        }
        isRecreatingWindows = false
        applyWindowLevel()
    }

    func openAllScreenWindows() {
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
            applyWindowLevel()
        } else {
            // --- Recreate path: screen configuration changed ---
            // Fully remove old windows from screen since controllers will be discarded.
            for controller in mainWindowControllers.values {
                controller.teardown()
            }
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
                applyWindowLevel()
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
                    self.applyWindowLevel()
                }
            }
        }
    }

    func hideAllMainWindows() {
        for controller in mainWindowControllers.values {
            controller.hide()
        }
    }

    /// Fully remove all main windows from screen (orderOut) so they don't
    /// interfere visually during window resize operations. Unlike `hide()`
    /// which keeps windows at alphaValue=0 for instant re-show, this method
    /// removes them from the window server entirely and flushes the
    /// transaction so the visual change is committed before returning.
    func orderOutAllMainWindows() {
        for controller in mainWindowControllers.values {
            controller.window?.orderOut(nil)
        }
        CATransaction.flush()
    }

    func targetScreenForWindow() -> NSScreen {
        if let screenFrame = activeLayoutTarget?.screenFrame,
           let screen = NSScreen.screen(containing: screenFrame) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first!
    }

    func createWindowController(for screen: NSScreen, isTarget: Bool) -> MainWindowController {
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

    // MARK: - Key Commands

    /// Returns true if `eventShortcut` matches `expected`, also considering
    /// modifier-held mode where the toggle modifiers may be held alongside
    /// the expected shortcut's modifiers.
    private func matchesShortcut(_ eventShortcut: HotKeyShortcut, _ expected: HotKeyShortcut) -> Bool {
        if eventShortcut == expected { return true }
        if let stripped = strippedShortcut(eventShortcut) {
            return stripped == expected
        }
        return false
    }

    func handleMainWindowKeyCommand(_ event: NSEvent) -> Bool {
        guard !isEditingSettings else { return false }

        // Check configurable window cycling shortcuts.
        let eventShortcut = HotKeyShortcut.from(event: event, requireModifiers: false)
        if let shortcut = eventShortcut {
            if displayShortcutSettings.selectNextWindow.localEnabled,
               let s = displayShortcutSettings.selectNextWindow.local, matchesShortcut(shortcut, s) {
                cycleTargetWindow(forward: true)
                return true
            }
            if displayShortcutSettings.selectPreviousWindow.localEnabled,
               let s = displayShortcutSettings.selectPreviousWindow.local, matchesShortcut(shortcut, s) {
                cycleTargetWindow(forward: false)
                return true
            }
            if displayShortcutSettings.bringToFront.localEnabled,
               let s = displayShortcutSettings.bringToFront.local, matchesShortcut(shortcut, s) {
                if selectedWindowIndices.count > 1 {
                    raiseSelectedWindows()
                } else {
                    raiseCurrentTargetWindow()
                }
                return true
            }
            if displayShortcutSettings.closeOrQuit.localEnabled,
               let s = displayShortcutSettings.closeOrQuit.local, matchesShortcut(shortcut, s) {
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

    // MARK: - Layout Preview

    func makeLayoutPreviewController(for target: WindowTarget) -> LayoutPreviewOverlayController {
        LayoutPreviewOverlayController(
            screenFrame: target.screenFrame,
            visibleFrame: target.visibleFrame
        )
    }
}
