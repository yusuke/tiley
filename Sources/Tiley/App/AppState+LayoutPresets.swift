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
        if selectedWindowIndices.count > 1 {
            if selectedWindowIndices.count >= allSelections.count {
                // Enough selected windows — use explicit selection order.
                let selection = allSelections[0]
                let secondarySelections = Array(allSelections.dropFirst())
                applyToMultipleWindows(selection: selection, secondarySelections: secondarySelections)
            } else {
                // Not enough selected windows — selected first, fill from z-order.
                applyPresetToZOrderedWindows(selections: allSelections)
            }
        } else if allSelections.count > 1 {
            // Single window but multi-layout preset — fill from z-order.
            applyPresetToZOrderedWindows(selections: allSelections)
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
}
