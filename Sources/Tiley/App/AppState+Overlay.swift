import AppKit

extension AppState {
    func updateLayoutPreview(_ selection: GridSelection?, screenContext: ScreenContext? = nil, colorIndex: Int = 0, overrideFillNSColor: NSColor? = nil) {
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
            colorIndex: colorIndex,
            overrideFillNSColor: overrideFillNSColor
        )
    }

    /// Shows preview rectangles for multiple selections mapped to selected windows.
    func updateLayoutPreviewForPreset(_ preset: LayoutPreset, screenContext: ScreenContext? = nil, showIndexLabels: Bool = false) {
        guard isShowingLayoutGrid else {
            hidePreviewOverlay()
            return
        }

        let allSelections = preset.allScaledSelections(toRows: rows, columns: columns)
        guard !allSelections.isEmpty else {
            hidePreviewOverlay()
            return
        }

        // If only one selection, fall back to normal preview.
        if allSelections.count <= 1 {
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

        // App assignments parallel to `allSelections`.
        let rectangleApps = preset.normalizedRectangleApps

        // Pre-compute display index (1-based, position among unassigned slots
        // only) and unassigned-color cycle index for each slot.
        var unassignedDisplayIndex: [Int: Int] = [:]
        var unassignedCursor = 0
        for (idx, app) in rectangleApps.enumerated() where app == nil {
            unassignedCursor += 1
            unassignedDisplayIndex[idx] = unassignedCursor
        }

        // Claim the frontmost window of every assigned bundle ID so the
        // unassigned-slot pool doesn't pick the same window as its filler.
        // Matches the real apply behavior: assigned slots consume the app's
        // frontmost window.
        var claimedWIDs: Set<CGWindowID> = []
        let assignedBundleIDs: Set<String> = Set(rectangleApps.compactMap { $0 })
        if !assignedBundleIDs.isEmpty {
            var seenBundles: Set<String> = []
            for target in availableWindowTargets {
                guard let bid = NSRunningApplication(processIdentifier: target.processIdentifier)?.bundleIdentifier,
                      assignedBundleIDs.contains(bid), !seenBundles.contains(bid) else { continue }
                seenBundles.insert(bid)
                if target.cgWindowID != 0 {
                    claimedWIDs.insert(target.cgWindowID)
                }
            }
        }

        // Pick windows for unassigned slots from user selection + z-order,
        // excluding windows already claimed by assigned slots.
        let unassignedSlotIndices: [Int] = rectangleApps.enumerated().compactMap { idx, app in
            app == nil && idx < allSelections.count ? idx : nil
        }
        let orderedIndices = buildZOrderedWindowIndices(count: availableWindowTargets.count)
            .filter { idx in
                guard idx < availableWindowTargets.count else { return false }
                return !claimedWIDs.contains(availableWindowTargets[idx].cgWindowID)
            }
        var windowBySlot: [Int: WindowTarget] = [:]
        for (i, slotIdx) in unassignedSlotIndices.enumerated() {
            guard i < orderedIndices.count else { break }
            let target = availableWindowTargets[orderedIndices[i]]
            windowBySlot[slotIdx] = target
        }

        // Build preview items in slot order so rectangles render in their
        // intended positions. Assigned slots render with the bound app's
        // icon/name and the `isAssigned` flag; unassigned slots render with
        // the selected/z-order window info and the display-among-unassigned
        // color/label.
        var items: [SelectionPreviewItem] = []
        for (slotIdx, sel) in allSelections.enumerated() {
            if let bid = rectangleApps[safe: slotIdx], let bid {
                let appIcon = AppIconLookup.icon(forBundleID: bid)
                let appName = AppIconLookup.localizedName(forBundleID: bid)
                items.append(SelectionPreviewItem(
                    selection: sel,
                    resizability: .both,
                    windowSize: nil,
                    appIcon: appIcon,
                    windowTitle: nil,
                    appName: appName,
                    isAssigned: true
                ))
            } else {
                let colorIdx = (unassignedDisplayIndex[slotIdx] ?? (slotIdx + 1)) - 1
                if let target = windowBySlot[slotIdx] {
                    let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
                    items.append(SelectionPreviewItem(
                        selection: sel,
                        resizability: slotIdx == 0 ? resizabilityForActiveTarget() : .both,
                        windowSize: target.frame.size,
                        appIcon: appIcon,
                        windowTitle: target.windowTitle,
                        appName: target.appName,
                        isAssigned: false,
                        unassignedColorIndex: colorIdx,
                        displayLabel: unassignedDisplayIndex[slotIdx]
                    ))
                } else {
                    items.append(SelectionPreviewItem(
                        selection: sel,
                        resizability: .both,
                        windowSize: nil,
                        appIcon: nil,
                        windowTitle: nil,
                        appName: nil,
                        isAssigned: false,
                        unassignedColorIndex: colorIdx,
                        displayLabel: unassignedDisplayIndex[slotIdx]
                    ))
                }
            }
        }

        layoutPreviewController?.showMultipleSelections(
            items,
            rows: rows,
            columns: columns,
            gap: gap,
            behind: parentWindow,
            showIndexLabels: showIndexLabels
        )
    }

    /// Computes sidebar highlight mapping and window info for a preset hover.
    /// Selected windows come first, remaining slots filled by z-order.
    /// Returns (highlights, windowInfo) — highlights maps window indices to color indices,
    /// windowInfo is parallel to `allSelections` (index i = slot i's preview
    /// info: the assigned app for assigned slots, the picked
    /// selected/z-ordered window for unassigned slots).
    func computePresetHoverInfo(for preset: LayoutPreset) -> (highlights: [Int: Int], windowInfo: [PresetHoverWindowInfo]) {
        let allSelections = preset.allScaledSelections(toRows: rows, columns: columns)

        if allSelections.count <= 1 {
            // Single-layout preset. If the sole slot is app-assigned, preview
            // the assigned app. Otherwise, preview the active target.
            var windowInfo: [PresetHoverWindowInfo] = []
            if let bid = preset.appAssignment(atSelectionIndex: 0) {
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: AppIconLookup.icon(forBundleID: bid),
                    appName: AppIconLookup.localizedName(forBundleID: bid) ?? bid,
                    windowTitle: ""
                ))
            } else if let target = activeLayoutTarget {
                let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: appIcon,
                    appName: target.appName,
                    windowTitle: target.windowTitle ?? ""
                ))
            }
            return ([:], windowInfo)
        }

        let rectangleApps = preset.normalizedRectangleApps

        // Claim the frontmost window of each assigned bundle ID so the
        // unassigned-slot filler doesn't pick them.
        var claimedWIDs: Set<CGWindowID> = []
        let assignedBundleIDs: Set<String> = Set(rectangleApps.compactMap { $0 })
        if !assignedBundleIDs.isEmpty {
            var seenBundles: Set<String> = []
            for target in availableWindowTargets {
                guard let bid = NSRunningApplication(processIdentifier: target.processIdentifier)?.bundleIdentifier,
                      assignedBundleIDs.contains(bid), !seenBundles.contains(bid) else { continue }
                seenBundles.insert(bid)
                if target.cgWindowID != 0 {
                    claimedWIDs.insert(target.cgWindowID)
                }
            }
        }

        // Unassigned slot fillers, in selection + z-order, skipping claimed.
        let unassignedSlotIndices: [Int] = rectangleApps.enumerated().compactMap { idx, app in
            app == nil && idx < allSelections.count ? idx : nil
        }
        let candidateIndices = buildZOrderedWindowIndices(count: availableWindowTargets.count)
            .filter { idx in
                guard idx < availableWindowTargets.count else { return false }
                return !claimedWIDs.contains(availableWindowTargets[idx].cgWindowID)
            }

        var slotToWindowIndex: [Int: Int] = [:]
        for (i, slotIdx) in unassignedSlotIndices.enumerated() where i < candidateIndices.count {
            slotToWindowIndex[slotIdx] = candidateIndices[i]
        }

        // Build windowInfo parallel to allSelections.
        var windowInfo: [PresetHoverWindowInfo] = []
        for (slotIdx, _) in allSelections.enumerated() {
            if let bid = rectangleApps[safe: slotIdx], let bid {
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: AppIconLookup.icon(forBundleID: bid),
                    appName: AppIconLookup.localizedName(forBundleID: bid) ?? bid,
                    windowTitle: ""
                ))
            } else if let windowIdx = slotToWindowIndex[slotIdx] {
                let target = availableWindowTargets[windowIdx]
                let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: appIcon,
                    appName: target.appName,
                    windowTitle: target.windowTitle ?? ""
                ))
            } else {
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: nil,
                    appName: "",
                    windowTitle: ""
                ))
            }
        }

        // highlights: map each window index to the color/index it will display
        // in the sidebar. Colors cycle by **unassigned** position (blue/green/
        // orange/purple) so the first unassigned slot's window is always blue
        // regardless of how many assigned slots precede it.
        var unassignedDisplayIndex: [Int: Int] = [:]
        var cursor = 0
        for (idx, app) in rectangleApps.enumerated() where app == nil {
            unassignedDisplayIndex[idx] = cursor
            cursor += 1
        }

        var highlights: [Int: Int] = [:]
        for (slotIdx, windowIdx) in slotToWindowIndex {
            highlights[windowIdx] = unassignedDisplayIndex[slotIdx] ?? slotIdx
        }
        // Selected windows beyond the preset layout count are clamped to the
        // last layout during apply, so highlight them with the last unassigned
        // slot's color. If there are no unassigned slots, fall back to 0.
        let lastColorIndex = max(0, cursor - 1)
        let assignedWindowIndices = Set(slotToWindowIndex.values)
        for idx in selectionOrder where idx < availableWindowTargets.count {
            if !assignedWindowIndices.contains(idx),
               !claimedWIDs.contains(availableWindowTargets[idx].cgWindowID) {
                highlights[idx] = lastColorIndex
            }
        }
        return (highlights, windowInfo)
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
            behind: settingsWindowController?.window ?? targetWindowController?.nsWindow
        )
    }

    func hidePreviewOverlay() {
        layoutPreviewController?.hide()
        layoutPreviewController = nil
        if !presetHoverHighlights.isEmpty {
            presetHoverHighlights = [:]
        }
        if !presetHoverWindowInfo.isEmpty {
            presetHoverWindowInfo = []
        }
    }

    // MARK: - Resize Preview

    /// Show a resize preview on the screen overlay (behind main window) and update the grid mini preview.
    /// `frame` is in AppKit screen coordinates (bottom-left origin).
    func showResizePreview(frame: CGRect, on screen: NSScreen, windowTitle: String? = nil, appName: String? = nil, appIcon: NSImage? = nil) {
        let previewScreenFrame = screen.frame
        let previewVisibleFrame = screen.visibleFrame

        // Create or reuse the overlay controller
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

        // Show real-size overlay behind the Tiley main window
        layoutPreviewController?.showResizePreview(frame: frame, behind: parentWindow, appIcon: appIcon, windowTitle: windowTitle, appName: appName)

        // Update the grid mini preview via observable property
        let vf = previewVisibleFrame
        let relX = (frame.minX - vf.minX) / vf.width
        let relY = (vf.maxY - frame.maxY) / vf.height
        let relW = frame.width / vf.width
        let relH = frame.height / vf.height
        let menuBarHeight = previewScreenFrame.height - vf.height - vf.minY + previewScreenFrame.minY
        let menuBarFraction = max(0, menuBarHeight / vf.height)

        resizePreviewRelativeFrame = WindowFrameRelative(
            x: relX, y: relY, width: relW, height: relH,
            menuBarHeightFraction: menuBarFraction,
            windowTitle: windowTitle, appName: appName, appIcon: appIcon
        )
    }

    /// Hide the resize preview overlay and grid mini preview.
    func hideResizePreview() {
        layoutPreviewController?.hide()
        layoutPreviewController = nil
        resizePreviewRelativeFrame = nil
    }

    /// Immediately dismisses the overlay, layout grid, and all main windows
    /// so the user doesn't wait for subsequent (potentially slow) AX operations.
    func dismissOverlayImmediately() {
        removeModifierReleaseMonitor()
        hidePreviewOverlay()
        isShowingLayoutGrid = false
        hideAllMainWindows()
    }

    /// Returns the resize capability of the active layout target window,
    /// caching the result per PID to avoid repeated probes.
    func resizabilityForActiveTarget() -> WindowResizability {
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

    func clearResizabilityCache() {
        cachedResizability = nil
        cachedResizabilityPID = nil
    }
}
