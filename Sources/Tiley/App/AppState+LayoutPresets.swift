import AppKit
import TelemetryDeck

extension AppState {

    // MARK: - Reset / Update / Move

    func resetLayoutPresetsToDefault() {
        layoutPresets = LayoutPreset.defaultPresets(rows: rows, columns: columns)
        selectedLayoutPresetID = layoutPresets.first?.id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    func updateLayoutPreset(_ id: UUID, mutate: (inout LayoutPreset) -> Void) {
        guard let index = layoutPresets.firstIndex(where: { $0.id == id }) else { return }
        mutate(&layoutPresets[index])
        sanitizeShortcutGlobalFlags(for: &layoutPresets[index])
        selectedLayoutPresetID = id
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    /// Creates a new blank layout preset, appends it to `layoutPresets`, and returns its ID.
    /// The caller is responsible for entering edit mode on the returned preset.
    @discardableResult
    func createNewLayoutPreset() -> UUID {
        let preset = LayoutPreset(
            id: UUID(),
            name: NSLocalizedString("New Layout Preset", comment: "Default name for a newly created layout preset"),
            selection: LayoutPreset.emptySelection,
            baseRows: rows,
            baseColumns: columns,
            shortcuts: []
        )
        layoutPresets.append(preset)
        selectedLayoutPresetID = preset.id
        saveLayoutPresets()
        registerPresetHotKeys()
        return preset.id
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

    // MARK: - Query / Select / Apply

    func selectLayoutPreset(_ id: UUID) {
        selectedLayoutPresetID = id
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
        let allSelections = preset.allScaledSelections(toRows: rows, columns: columns)
        let rectangleApps = preset.normalizedRectangleApps
        let hasAnyAssignment = rectangleApps.contains(where: { $0 != nil })

        if hasAnyAssignment {
            Task { @MainActor [self] in
                await applyPresetWithAppAssignments(
                    presetID: id,
                    allSelections: allSelections,
                    rectangleApps: rectangleApps,
                    groupedPairs: preset.groupedPairs,
                    anchorTarget: target,
                    presetName: preset.name
                )
            }
            return
        }

        if selectedWindowIndices.count > 1 {
            if selectedWindowIndices.count >= allSelections.count {
                // Enough selected windows — use explicit selection order.
                let selection = allSelections[0]
                let secondarySelections = Array(allSelections.dropFirst())
                applyToMultipleWindows(selection: selection, secondarySelections: secondarySelections, groupedPairs: preset.groupedPairs)
            } else {
                // Not enough selected windows — selected first, fill from z-order.
                applyPresetToZOrderedWindows(selections: allSelections, groupedPairs: preset.groupedPairs)
            }
        } else if allSelections.count > 1 {
            // Single window but multi-layout preset — fill from z-order.
            applyPresetToZOrderedWindows(selections: allSelections, groupedPairs: preset.groupedPairs)
        } else {
            apply(selection: allSelections.first ?? preset.scaledSelection(toRows: rows, columns: columns), to: target)
        }
        TelemetryDeck.signal("presetApplied", parameters: ["presetName": preset.name])
    }

    /// Applies a layout preset on the screen where the mouse cursor is located.
    /// Falls back to the target window's screen when the cursor screen cannot be determined.
    func applyPresetOnMouseScreen(id: UUID) {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            applyLayoutPresetOnScreen(id: id, visibleFrame: screen.visibleFrame, screenFrame: screen.frame)
        } else {
            applyLayoutPreset(id: id)
        }
    }

    func handleLocalShortcut(_ shortcut: HotKeyShortcut) -> Bool {
        guard isShowingLayoutGrid, !isEditingSettings else { return false }

        // When in modifier-held mode, also try matching with the toggle
        // modifiers stripped (e.g. Shift+Cmd+M → M).
        let candidates = [shortcut, strippedShortcut(shortcut)].compactMap { $0 }

        for s in candidates {
            if let preset = layoutPresets.first(where: { $0.localShortcuts.contains(s) }) {
                removeModifierReleaseMonitor()
                applyPresetOnMouseScreen(id: preset.id)
                return true
            }
            if let action = displayShortcutLocalAction(for: s) {
                removeModifierReleaseMonitor()
                executeDisplayShortcutLocal(action)
                return true
            }
        }
        return false
    }

    // MARK: - Remove

    func removeLayoutPreset(id: UUID) {
        guard let index = layoutPresets.firstIndex(where: { $0.id == id }) else { return }
        layoutPresets.remove(at: index)
        if selectedLayoutPresetID == id {
            selectedLayoutPresetID = layoutPresets.first?.id
        }
        saveLayoutPresets()
        registerPresetHotKeys()
    }

    // MARK: - Lookup

    func layoutPreset(for id: UUID) -> LayoutPreset? {
        layoutPresets.first(where: { $0.id == id })
    }

    // MARK: - Edge alignment after multi-rectangle preset application

    /// After a multi-rectangle preset has been applied, walk the grid-level
    /// adjacencies and — when one window of an adjacent pair was forced
    /// larger than its target by its app's minimum-size constraint — adjust
    /// the *other* window's width/height so the shared edge stays aligned
    /// (preserving the preset gap). Best-effort: if both windows are
    /// constrained on the relevant axis the pair is left as-is.
    ///
    /// `placements` is in apply order; only the first placement per
    /// `selectionIndex` participates (extras piled on the last selection are
    /// ignored).
    func alignAdjacentEdgesAfterPreset(
        placements: [(selectionIndex: Int, target: WindowTarget, targetFrame: CGRect)],
        selections: [GridSelection],
        screenFrame: CGRect
    ) {
        guard placements.count >= 2, selections.count >= 2 else { return }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0

        var windowBySel: [Int: AXUIElement] = [:]
        var targetFrameBySel: [Int: CGRect] = [:]
        var actualFrameBySel: [Int: CGRect] = [:]
        for placement in placements {
            let sel = placement.selectionIndex
            guard windowBySel[sel] == nil else { continue }
            guard let window = placement.target.windowElement else { continue }
            let (pos, size) = accessibilityService.readPositionAndSize(of: window)
            guard size.width > 0, size.height > 0 else { continue }
            let appkitMinY = primaryMaxY - (pos.y + size.height)
            windowBySel[sel] = window
            targetFrameBySel[sel] = placement.targetFrame
            actualFrameBySel[sel] = CGRect(x: pos.x, y: appkitMinY, width: size.width, height: size.height)
        }

        let adjacencies = SelectionAdjacencyDetector.detect(selections: selections)
        let epsilon: CGFloat = 2
        let minDim: CGFloat = 40

        for adj in adjacencies {
            guard let winA = windowBySel[adj.indexA],
                  let winB = windowBySel[adj.indexB],
                  winA != winB,
                  let actualA = actualFrameBySel[adj.indexA],
                  let actualB = actualFrameBySel[adj.indexB],
                  let targetA = targetFrameBySel[adj.indexA],
                  let targetB = targetFrameBySel[adj.indexB] else { continue }

            let horizontal = (adj.edgeOfA == .left || adj.edgeOfA == .right)
            let dimA = horizontal ? actualA.width : actualA.height
            let dimB = horizontal ? actualB.width : actualB.height
            let tDimA = horizontal ? targetA.width : targetA.height
            let tDimB = horizontal ? targetB.width : targetB.height
            let aOversized = dimA > tDimA + epsilon
            let bOversized = dimB > tDimB + epsilon
            if !aOversized && !bOversized { continue }
            if aOversized && bOversized { continue }

            // The oversized window is the anchor; its actual edge sets the
            // alignment target. The other window is reshaped to match.
            let anchorIsA = aOversized
            let anchorActual = anchorIsA ? actualA : actualB
            let anchorTarget = anchorIsA ? targetA : targetB
            let adjustableTarget = anchorIsA ? targetB : targetA
            let adjustableWindow: AXUIElement = anchorIsA ? winB : winA

            // The adjustable window's edge that faces the anchor.
            let nearEdge: WindowAdjacency.Edge
            switch adj.edgeOfA {
            case .right: nearEdge = anchorIsA ? .left  : .right
            case .left:  nearEdge = anchorIsA ? .right : .left
            case .bottom: nearEdge = anchorIsA ? .top    : .bottom
            case .top:    nearEdge = anchorIsA ? .bottom : .top
            }

            var newFrame = adjustableTarget
            let farEdge: WindowAdjacency.Edge
            let farValue: CGFloat
            switch nearEdge {
            case .left:
                // Adjustable is right of anchor.
                let gapValue = adjustableTarget.minX - anchorTarget.maxX
                let newMinX = anchorActual.maxX + gapValue
                farEdge = .right
                farValue = adjustableTarget.maxX
                newFrame.origin.x = newMinX
                newFrame.size.width = farValue - newMinX
            case .right:
                // Adjustable is left of anchor.
                let gapValue = anchorTarget.minX - adjustableTarget.maxX
                let newMaxX = anchorActual.minX - gapValue
                farEdge = .left
                farValue = adjustableTarget.minX
                newFrame.origin.x = farValue
                newFrame.size.width = newMaxX - farValue
            case .bottom:
                // Adjustable sits below anchor in screen layout (anchor.minY > adjustable.maxY).
                let gapValue = anchorTarget.minY - adjustableTarget.maxY
                let newMaxY = anchorActual.minY - gapValue
                farEdge = .bottom
                farValue = adjustableTarget.minY
                newFrame.origin.y = farValue
                newFrame.size.height = newMaxY - farValue
            case .top:
                // Adjustable sits above anchor.
                let gapValue = adjustableTarget.minY - anchorTarget.maxY
                let newMinY = anchorActual.maxY + gapValue
                farEdge = .top
                farValue = adjustableTarget.maxY
                newFrame.origin.y = newMinY
                newFrame.size.height = farValue - newMinY
            }

            if newFrame.width < minDim || newFrame.height < minDim { continue }
            if abs(newFrame.minX - adjustableTarget.minX) < epsilon &&
               abs(newFrame.minY - adjustableTarget.minY) < epsilon &&
               abs(newFrame.width - adjustableTarget.width) < epsilon &&
               abs(newFrame.height - adjustableTarget.height) < epsilon {
                continue
            }

            _ = accessibilityService.setFrameLightweightPreservingEdge(
                newFrame,
                preservingEdge: farEdge,
                edgeValue: farValue,
                on: screenFrame,
                for: adjustableWindow
            )
        }
    }
}
