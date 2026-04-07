import AppKit

extension AppState {

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

        let matchesQuery: (Int) -> Bool = { i in
            let target = self.availableWindowTargets[i]
            let title = target.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var appPart = target.appName
            if let orig = Self.originalAppName(for: target.processIdentifier) {
                appPart += " " + orig
            }
            return (appPart + " " + title).lowercased().isSubsequence(of: query)
        }

        let filteredIndices: [Int]
        if !sidebarWindowOrder.isEmpty {
            // Use sidebar order, filtering out any stale indices.
            let valid = sidebarWindowOrder.filter { $0 < availableWindowTargets.count }
            filteredIndices = query.isEmpty ? valid : valid.filter(matchesQuery)
        } else {
            // Fallback: screen-ordered indices (sidebar not yet rendered).
            let baseIndices: [Int]
            if query.isEmpty {
                baseIndices = Array(availableWindowTargets.indices)
            } else {
                baseIndices = availableWindowTargets.indices.filter(matchesQuery)
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
    func screenOrderedIndices(_ indices: [Int]) -> [Int] {
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
    func selectAllWindowsOfApp(pid: pid_t, shift: Bool = false, cmd: Bool = false) {
        guard isShowingLayoutGrid, !isEditingSettings else { return }

        if originalFrontmostPID == nil {
            originalFrontmostPID = lastTargetPID
            originalFrontmostTarget = activeLayoutTarget
            initialZOrderWindowIDs = availableWindowTargets.map(\.cgWindowID).filter { $0 != 0 }
        }

        let appIndices = availableWindowTargets.indices.filter { availableWindowTargets[$0].processIdentifier == pid }
        guard !appIndices.isEmpty else { return }

        if cmd {
            // Cmd+click: toggle all windows of this app in/out of the selection.
            let allAlreadySelected = appIndices.allSatisfy { selectedWindowIndices.contains($0) }
            if allAlreadySelected {
                // Remove all app windows, but don't leave selection empty.
                let remaining = selectedWindowIndices.subtracting(appIndices)
                if !remaining.isEmpty {
                    selectedWindowIndices = remaining
                    selectionOrder.removeAll { appIndices.contains($0) }
                    if appIndices.contains(activeTargetIndex) {
                        activeTargetIndex = selectionOrder.first ?? remaining.first!
                    }
                }
                // else: all selected items belong to this app → no-op (keep selection)
            } else {
                // Add all app windows to the selection.
                selectedWindowIndices.formUnion(appIndices)
                let newIndices = appIndices.filter { !selectionOrder.contains($0) }
                selectionOrder.append(contentsOf: newIndices)
                activeTargetIndex = appIndices.first!
            }
        } else if shift {
            // Shift+click: select contiguous range from anchor to the app group boundaries.
            let anchor = selectionAnchorIndex ?? activeTargetIndex
            let order: [Int]
            if !sidebarWindowOrder.isEmpty {
                order = sidebarWindowOrder.filter { $0 < availableWindowTargets.count }
            } else {
                order = Array(availableWindowTargets.indices)
            }
            // Find the sidebar positions of the app's first and last windows.
            let appPositions = appIndices.compactMap { order.firstIndex(of: $0) }
            guard let appFirst = appPositions.min(), let appLast = appPositions.max(),
                  let anchorPos = order.firstIndex(of: anchor) else { return }
            // Extend range from anchor to the farthest edge of the app group.
            let lo = min(anchorPos, appFirst)
            let hi = max(anchorPos, appLast)
            let rangeIndices = Array(order[lo...hi])
            selectedWindowIndices = Set(rangeIndices)
            let previousOrder = selectionOrder.filter { selectedWindowIndices.contains($0) }
            let newIndices = rangeIndices.filter { !previousOrder.contains($0) }
            selectionOrder = previousOrder + newIndices
            activeTargetIndex = appIndices.first!
            // Don't update selectionAnchorIndex on shift-click.
        } else {
            // Plain click: select all app windows in index order.
            selectedWindowIndices = Set(appIndices)
            selectionOrder = appIndices
            selectionAnchorIndex = appIndices.first
            activeTargetIndex = appIndices.first!
        }

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
    func moveWindowToMouseScreenIfNeeded(window: AXUIElement, windowScreenFrame: CGRect, windowFrame: CGRect) {
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
    func moveWindowToDestinationScreen(window: AXUIElement, destination: NSScreen) {
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

    func applyTargetAtCurrentIndex() {
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

        CATransaction.flush()

        // Move windows that occlude the selected target off-screen so it
        // becomes visible without changing focus.
        if newTarget.cgWindowID != 0 {
            displaceOccludingWindows(for: newTarget)
        }
    }

    func refreshAvailableWindows() {
        let captured = windowManager?.captureAllWindows(includeOtherSpaces: true)
        availableWindowTargets = captured?.targets ?? []
        spaceList = captured?.spaceList ?? []
        activeSpaceIDs = captured?.activeSpaceIDs ?? []
        windowTargetListVersion += 1

        if let pending = pendingTargetAfterClose {
            pendingTargetAfterClose = nil
            // Find the pending target by PID + window element, falling back to PID + title.
            if let matchIdx = availableWindowTargets.firstIndex(where: {
                $0.processIdentifier == pending.pid && $0.windowElement == pending.windowElement
            }) ?? availableWindowTargets.firstIndex(where: {
                $0.processIdentifier == pending.pid && $0.windowTitle == pending.windowTitle
            }) {
                activeTargetIndex = matchIdx
            } else {
                activeTargetIndex = 0
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

    func clearWindowCyclingState(animateRestore: Bool = true) {
        CATransaction.flush()
        displacementAnimationTimer?.cancel()
        displacementAnimationTimer = nil
        if animateRestore {
            restoreDisplacedWindowsAnimated()
        } else {
            // Cancel any in-flight restoration animation so it doesn't
            // continue moving windows after the instant restore.
            restorationAnimationTimer?.cancel()
            restorationAnimationTimer = nil
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
    func displaceOccludingWindows(for selectedTarget: WindowTarget) {
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
        // Don't remove entries from displacedWindowFrames yet — defer
        // removal until the animation completes. If the animation is
        // cancelled (e.g. by rapid cycling), the entries remain so that
        // clearWindowCyclingState can still restore them.
        let toRestore = Set(displacedWindowFrames.keys).subtracting(shouldDisplace)
        var restoringWIDs: [CGWindowID] = []
        for wid in toRestore {
            if let entry = displacedWindowFrames[wid] {
                let (currentPos, _) = accessibilityService.readPositionAndSize(of: entry.window)
                moves.append((window: entry.window, from: currentPos, to: entry.origin))
                restoringWIDs.append(wid)
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
                displacedWindowFrames[wid] = (origin: axPos, window: window)
            }

            let destination = CGPoint(x: target.frame.minX, y: nextY)
            nextY += gap

            let (currentPos, axSize) = accessibilityService.readPositionAndSize(of: window)
            debugLog("displaceOccluding: wid=\(wid) cgFrame=\(target.frame) axPos=\(currentPos) axSize=\(axSize) to=\(destination)")
            moves.append((window: window, from: currentPos, to: destination))
        }

        animateWindowMoves(moves) { [weak self] in
            // Animation completed naturally — safe to remove restored entries.
            for wid in restoringWIDs {
                self?.displacedWindowFrames.removeValue(forKey: wid)
            }
        }
    }

    /// Animates multiple window moves simultaneously over a short duration.
    /// The optional `completion` closure is called only when the animation
    /// finishes naturally (all steps complete). It is NOT called when the
    /// animation is cancelled by a subsequent call — this lets callers
    /// defer cleanup (e.g. removing `displacedWindowFrames` entries) so
    /// the entries survive cancellation and can be restored later.
    func animateWindowMoves(_ moves: [(window: AXUIElement, from: CGPoint, to: CGPoint)], completion: (() -> Void)? = nil) {
        displacementAnimationTimer?.cancel()
        displacementAnimationTimer = nil

        guard !moves.isEmpty else {
            completion?()
            return
        }

        // Filter out moves with negligible distance.
        let significantMoves = moves.filter {
            abs($0.from.x - $0.to.x) > 1 || abs($0.from.y - $0.to.y) > 1
        }
        guard !significantMoves.isEmpty else {
            for move in moves {
                accessibilityService.setPosition(move.to, for: move.window)
            }
            completion?()
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
                completion?()
            }
        }
        displacementAnimationTimer = timer
        timer.resume()
    }


    /// Restores all displaced windows back to their original positions instantly.
    func restoreDisplacedWindows() {
        guard !displacedWindowFrames.isEmpty else { return }
        for (_, entry) in displacedWindowFrames {
            accessibilityService.setPosition(entry.origin, for: entry.window)
        }
        displacedWindowFrames.removeAll()
    }

    /// Restores all displaced windows back to their original positions with animation.
    /// Uses a dedicated timer (`restorationAnimationTimer`) that is independent of
    /// the cycling state, so it survives secondary `clearWindowCyclingState()` calls.
    func restoreDisplacedWindowsAnimated() {
        guard !displacedWindowFrames.isEmpty else { return }

        var moves: [(window: AXUIElement, from: CGPoint, to: CGPoint)] = []
        for (_, entry) in displacedWindowFrames {
            let (currentPos, _) = accessibilityService.readPositionAndSize(of: entry.window)
            moves.append((window: entry.window, from: currentPos, to: entry.origin))
        }

        restorationAnimationTimer?.cancel()
        restorationAnimationTimer = nil

        let significantMoves = moves.filter {
            abs($0.from.x - $0.to.x) > 1 || abs($0.from.y - $0.to.y) > 1
        }
        guard !significantMoves.isEmpty else {
            for move in moves {
                accessibilityService.setPosition(move.to, for: move.window)
            }
            displacedWindowFrames.removeAll()
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
                self?.displacedWindowFrames.removeAll()
            }
        }
        restorationAnimationTimer = timer
        timer.resume()
    }

    /// Checks whether the current `activeLayoutTarget` still exists (its
    /// AX position is queryable).  If the window has disappeared (e.g. a
    /// transient HUD), falls back to the first available window target and
    /// updates the highlight border.
    func revalidateActiveTarget() {
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
    }

    /// If the target's app is hidden (Cmd-H), unhide it so the window becomes
    /// visible before we try to raise/move it.
    /// Returns an updated target with a valid `windowElement` when possible.
    @discardableResult
    func unhideAppIfNeeded(_ target: WindowTarget) -> WindowTarget {
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

    /// Returns the non-localized app name if it differs from the localized one.
    private static func originalAppName(for pid: pid_t) -> String? {
        guard let app = NSRunningApplication(processIdentifier: pid),
              let bundleURL = app.bundleURL,
              let bundle = Bundle(url: bundleURL),
              let name = bundle.infoDictionary?["CFBundleName"] as? String,
              name.lowercased() != app.localizedName?.lowercased()
        else { return nil }
        return name
    }
}
