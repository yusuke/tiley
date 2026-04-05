import AppKit

extension AppState {
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

    /// Returns the identity (PID, window element, title) of the window that should be
    /// selected after closing the window(s) at the given indices, based on sidebar order.
    /// Prefers the item below the lowest closed index in sidebar order; falls back to above.
    private func nextSidebarTarget(afterClosing closedIndices: Set<Int>) -> (pid: pid_t, windowElement: AXUIElement?, windowTitle: String?)? {
        let order: [Int]
        if !sidebarWindowOrder.isEmpty {
            order = sidebarWindowOrder.filter { $0 < availableWindowTargets.count }
        } else {
            order = Array(0..<availableWindowTargets.count)
        }
        guard !order.isEmpty else { return nil }

        // Find the first sidebar position among the closed indices.
        let closedPositions = order.enumerated().compactMap { closedIndices.contains($0.element) ? $0.offset : nil }
        guard let firstClosedPos = closedPositions.min() else { return nil }

        // Look for the first non-closed item below in sidebar order.
        for pos in (firstClosedPos + 1)..<order.count {
            let idx = order[pos]
            if !closedIndices.contains(idx) {
                let t = availableWindowTargets[idx]
                return (t.processIdentifier, t.windowElement, t.windowTitle)
            }
        }
        // Fall back to the first non-closed item above.
        for pos in stride(from: firstClosedPos - 1, through: 0, by: -1) {
            let idx = order[pos]
            if !closedIndices.contains(idx) {
                let t = availableWindowTargets[idx]
                return (t.processIdentifier, t.windowElement, t.windowTitle)
            }
        }
        return nil
    }

    func closeWindowTarget(at index: Int) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]

        // Remember which window to select after close, based on sidebar order.
        pendingTargetAfterClose = nextSidebarTarget(afterClosing: [index])

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

        // All windows of this app will disappear; collect their indices.
        let closedIndices = Set(availableWindowTargets.enumerated()
            .filter { $0.element.processIdentifier == target.processIdentifier }
            .map(\.offset))
        pendingTargetAfterClose = nextSidebarTarget(afterClosing: closedIndices)

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

        // Collect all indices that will disappear (closed + quit app windows).
        var allClosedIndices = selectedWindowIndices
        // Pre-scan for apps that will be quit entirely — their other windows also disappear.
        for (pid, selectedIndices) in selectedByPID {
            let isFinder = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.finder"
            let allSelected = selectedIndices.count >= (totalByPID[pid] ?? 0)
            if allSelected && !isFinder {
                for (i, t) in availableWindowTargets.enumerated() where t.processIdentifier == pid {
                    allClosedIndices.insert(i)
                }
            }
        }
        pendingTargetAfterClose = nextSidebarTarget(afterClosing: allClosedIndices)

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

    /// Resize a window to the given size, keeping its top-left position.
    /// If the resized window would extend beyond the screen, it is shifted to fit.
    func resizeWindow(at index: Int, to newSize: CGSize) {
        guard index >= 0, index < availableWindowTargets.count else { return }
        let target = availableWindowTargets[index]
        guard let window = target.windowElement else { return }

        // Hide Tiley UI first so it visually disappears before the resize.
        hideResizePreview()
        dismissOverlayImmediately()

        // Perform the actual resize after a short delay so the window
        // system has time to remove Tiley's windows from the screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }

            let screen = NSScreen.screen(containing: target.screenFrame) ?? NSScreen.screens.first!
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let destVisible = screen.visibleFrame

            let (currentPos, _) = self.accessibilityService.readPositionAndSize(of: window)

            // Apply new size
            var size = newSize
            if let sizeVal = AXValueCreate(.cgSize, &size) {
                AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeVal)
            }

            // Re-read actual size (app may constrain it)
            let (_, actualSize) = self.accessibilityService.readPositionAndSize(of: window)

            // Visible frame bounds in AX coordinates (top-left origin on primary screen)
            let visibleAXTop = primaryMaxY - destVisible.maxY
            let visibleAXLeft = destVisible.minX
            let visibleAXRight = destVisible.maxX
            let visibleAXBottom = primaryMaxY - destVisible.minY

            // Adjust position to keep window on screen
            var newPos = currentPos
            if newPos.x + actualSize.width > visibleAXRight {
                newPos.x = visibleAXRight - actualSize.width
            }
            newPos.x = max(newPos.x, visibleAXLeft)

            if newPos.y + actualSize.height > visibleAXBottom {
                newPos.y = visibleAXBottom - actualSize.height
            }
            newPos.y = max(newPos.y, visibleAXTop)

            if let posVal = AXValueCreate(.cgPoint, &newPos) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posVal)
            }

            // Bring the resized window to front
            self.accessibilityService.raiseWindow(window)
            NSRunningApplication(processIdentifier: target.processIdentifier)?.activate()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.refreshAvailableWindows()
            }
        }
    }
}
