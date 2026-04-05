import AppKit

extension AppState {
    func updateLayoutPreview(_ selection: GridSelection?, screenContext: ScreenContext? = nil, colorIndex: Int = 0) {
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

        // Selected windows first, then fill remaining from z-order.
        let orderedIndices = buildZOrderedWindowIndices(count: allSelections.count)

        // Build preview items: only show as many windows as selections defined.
        var items: [SelectionPreviewItem] = []
        for (windowPosition, idx) in orderedIndices.prefix(allSelections.count).enumerated() {
            let sel = allSelections[windowPosition]
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
            behind: parentWindow,
            showIndexLabels: showIndexLabels
        )
    }

    /// Computes sidebar highlight mapping and window info for a preset hover.
    /// Selected windows come first, remaining slots filled by z-order.
    /// Returns (highlights, windowInfo) — highlights maps window indices to color indices,
    /// windowInfo provides app/window names per layout selection index.
    func computePresetHoverInfo(for preset: LayoutPreset) -> (highlights: [Int: Int], windowInfo: [PresetHoverWindowInfo]) {
        let allSelections = preset.allScaledSelections(toRows: rows, columns: columns)

        if allSelections.count <= 1 {
            // Single-layout preset: return window info for the active target only.
            var windowInfo: [PresetHoverWindowInfo] = []
            if let target = activeLayoutTarget {
                let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
                windowInfo.append(PresetHoverWindowInfo(
                    appIcon: appIcon,
                    appName: target.appName,
                    windowTitle: target.windowTitle ?? ""
                ))
            }
            return ([:], windowInfo)
        }

        let orderedIndices = buildZOrderedWindowIndices(count: allSelections.count)
        var highlights: [Int: Int] = [:]
        var windowInfo: [PresetHoverWindowInfo] = []
        for (colorIndex, idx) in orderedIndices.enumerated() {
            highlights[idx] = colorIndex
            let target = availableWindowTargets[idx]
            let appIcon = NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
            windowInfo.append(PresetHoverWindowInfo(
                appIcon: appIcon,
                appName: target.appName,
                windowTitle: target.windowTitle ?? ""
            ))
        }
        // Selected windows beyond the preset layout count are clamped to the last layout
        // during apply, so highlight them with the last layout's color.
        let lastColorIndex = allSelections.count - 1
        let assignedSet = Set(orderedIndices)
        for idx in selectionOrder where idx < availableWindowTargets.count {
            if !assignedSet.contains(idx) {
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
