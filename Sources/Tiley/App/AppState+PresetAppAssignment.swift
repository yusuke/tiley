import AppKit
import TelemetryDeck
import UniformTypeIdentifiers

// MARK: - Preset App Assignment
//
// `LayoutPreset.rectangleApps` pins each rectangle to an application bundle
// identifier. Assigned rectangles receive the frontmost window of that app on
// apply; unassigned rectangles keep the existing selection/z-order fill.
//
// Unassigning a slot moves it to the end of `allSelections` so that its
// visible index becomes the last unassigned number. `groupedPairs` indices are
// remapped through the same permutation.

extension AppState {

    // MARK: - Mutations

    /// Assigns an app bundle identifier to the rectangle at `selectionIndex`.
    /// The slot keeps its position in `allSelections`; only `rectangleApps` is
    /// updated.
    func assignApp(bundleID: String, toSelectionIndex selectionIndex: Int, ofPresetID presetID: UUID) {
        updateLayoutPreset(presetID) { preset in
            var apps = preset.normalizedRectangleApps
            guard selectionIndex >= 0, selectionIndex < apps.count else { return }
            apps[selectionIndex] = bundleID
            preset.rectangleApps = apps
        }
    }

    /// Removes the app assignment at `selectionIndex` and moves that entry to
    /// the end of `allSelections`. `groupedPairs` indices are remapped through
    /// the resulting permutation.
    func unassignApp(fromSelectionIndex selectionIndex: Int, ofPresetID presetID: UUID) {
        updateLayoutPreset(presetID) { preset in
            let allSelections = preset.allSelections
            let apps = preset.normalizedRectangleApps
            let n = allSelections.count
            guard selectionIndex >= 0, selectionIndex < n else { return }
            guard apps[selectionIndex] != nil else { return }

            // Build permutation: oldIndex -> newIndex
            var mapping: [Int: Int] = [:]
            var cursor = 0
            for i in 0..<n where i != selectionIndex {
                mapping[i] = cursor
                cursor += 1
            }
            mapping[selectionIndex] = n - 1

            // Reorder selections + apps.
            var newSelections = Array(repeating: LayoutPreset.emptySelection, count: n)
            var newApps: [String?] = Array(repeating: nil, count: n)
            for (oldIdx, newIdx) in mapping {
                newSelections[newIdx] = allSelections[oldIdx]
                newApps[newIdx] = apps[oldIdx]
            }
            // The freshly-unassigned slot is the new last entry.
            newApps[n - 1] = nil

            preset.selection = newSelections[0]
            preset.secondarySelections = Array(newSelections.dropFirst())
            preset.rectangleApps = newApps

            // Remap groupedPairs through the permutation.
            preset.groupedPairs = preset.groupedPairs.map { pair in
                let newA = mapping[pair.indexA] ?? pair.indexA
                let newB = mapping[pair.indexB] ?? pair.indexB
                return PresetGroupPair(newA, newB)
            }
        }
    }

    /// Removes the selection at `selectionIndex` entirely (user clicked the
    /// delete button on a committed rectangle). Also drops the corresponding
    /// `rectangleApps` entry and remaps `groupedPairs`. Used by the preset
    /// editor's per-rectangle delete action.
    func removeSelection(atIndex selectionIndex: Int, ofPresetID presetID: UUID) {
        updateLayoutPreset(presetID) { preset in
            let n = preset.allSelections.count
            guard selectionIndex >= 0, selectionIndex < n else { return }

            if selectionIndex == 0 {
                if !preset.secondarySelections.isEmpty {
                    preset.selection = preset.secondarySelections.removeFirst()
                } else {
                    preset.selection = LayoutPreset.emptySelection
                }
            } else {
                let secondaryIndex = selectionIndex - 1
                if secondaryIndex < preset.secondarySelections.count {
                    preset.secondarySelections.remove(at: secondaryIndex)
                }
            }

            var apps = preset.normalizedRectangleApps
            if selectionIndex < apps.count {
                apps.remove(at: selectionIndex)
            }
            preset.rectangleApps = apps

            preset.groupedPairs = preset.groupedPairs.compactMap { pair in
                if pair.indexA == selectionIndex || pair.indexB == selectionIndex { return nil }
                let newA = pair.indexA > selectionIndex ? pair.indexA - 1 : pair.indexA
                let newB = pair.indexB > selectionIndex ? pair.indexB - 1 : pair.indexB
                return PresetGroupPair(newA, newB)
            }
        }
    }

    // MARK: - App picker menu

    struct PresetAppPickContext {
        let presetID: UUID
        let selectionIndex: Int
        let bundleID: String
    }

    struct PresetAppBrowseContext {
        let presetID: UUID
        let selectionIndex: Int
    }

    /// Entries in the app-picker menu, filtered to `.regular` activation-policy
    /// apps with a non-nil bundle identifier, sorted by localized name.
    func runningAppsForPicker() -> [(bundleID: String, name: String, icon: NSImage?)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> (String, String, NSImage?)? in
                guard let bid = app.bundleIdentifier else { return nil }
                let name = app.localizedName ?? bid
                return (bid, name, app.icon)
            }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
    }

    /// Builds and pops an NSMenu rooted at `sourceView`. The menu contains all
    /// running regular apps followed by an "Other Application…" browse entry.
    func presentAppPicker(forPresetID presetID: UUID, selectionIndex: Int, at point: NSPoint, in sourceView: NSView) {
        let menu = NSMenu()

        let header = NSMenuItem(
            title: NSLocalizedString("Assign Application", comment: "Header for the per-rectangle app assignment menu"),
            action: nil,
            keyEquivalent: ""
        )
        menu.addItem(header)
        menu.addItem(NSMenuItem.separator())

        for entry in runningAppsForPicker() {
            let item = NSMenuItem(
                title: entry.name,
                action: #selector(presetAppPickerMenuAction(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = PresetAppPickContext(
                presetID: presetID,
                selectionIndex: selectionIndex,
                bundleID: entry.bundleID
            )
            if let icon = entry.icon {
                let sized = icon.copy() as? NSImage ?? icon
                sized.size = NSSize(width: 16, height: 16)
                item.image = sized
            }
            menu.addItem(item)
        }

        if !menu.items.isEmpty {
            menu.addItem(NSMenuItem.separator())
        }

        let browse = NSMenuItem(
            title: NSLocalizedString("Other Application…", comment: "Menu item that opens a file picker to assign a non-running application"),
            action: #selector(presetAppPickerBrowseAction(_:)),
            keyEquivalent: ""
        )
        browse.target = self
        browse.representedObject = PresetAppBrowseContext(
            presetID: presetID,
            selectionIndex: selectionIndex
        )
        menu.addItem(browse)

        menu.popUp(positioning: nil, at: point, in: sourceView)
    }

    @objc func presetAppPickerMenuAction(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? PresetAppPickContext else { return }
        assignApp(bundleID: ctx.bundleID, toSelectionIndex: ctx.selectionIndex, ofPresetID: ctx.presetID)
    }

    @objc func presetAppPickerBrowseAction(_ sender: NSMenuItem) {
        guard let ctx = sender.representedObject as? PresetAppBrowseContext else { return }
        requestAppBrowse(forSelectionIndex: ctx.selectionIndex, ofPresetID: ctx.presetID)
    }

    // MARK: - Anchor resolution

    /// Resolves the anchor window for an assigned-slot bundle identifier.
    ///
    /// - Running app with at least one window: returns the focused/main/first
    ///   window via the existing `AccessibilityService.windowTarget(for:)`
    ///   cascade.
    /// - Running app with zero standard windows: posts a "no window" banner
    ///   and returns `nil`.
    /// - Not running: launches the app and waits up to 30s for a window to
    ///   appear. On timeout, posts a "window never appeared" banner and
    ///   returns `nil`.
    func resolveAppAnchor(bundleID: String) async -> WindowTarget? {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular })

        if let running {
            // Prefer the authoritative entry from availableWindowTargets so
            // the returned WindowTarget carries a valid cgWindowID. Matches
            // the preview's "frontmost window of the bundle" semantics.
            let pid = running.processIdentifier
            if let existing = availableWindowTargets.first(where: { $0.processIdentifier == pid }) {
                return existing
            }
            if let target = try? accessibilityService.windowTarget(for: pid) {
                return target
            }
            let name = running.localizedName
                ?? AppIconLookup.localizedName(forBundleID: bundleID)
                ?? bundleID
            PresetNotificationService.shared.postNoWindow(appName: name)
            return nil
        }

        if let target = await AppLauncher.launchAndWaitForWindow(
            bundleID: bundleID,
            using: accessibilityService,
            timeout: 30
        ) {
            // After launch, refresh the window list and try to use the
            // authoritative entry (for accurate cgWindowID bookkeeping).
            refreshAvailableWindows()
            if let existing = availableWindowTargets.first(where: { $0.processIdentifier == target.processIdentifier }) {
                return existing
            }
            return target
        }

        let name = AppIconLookup.localizedName(forBundleID: bundleID) ?? bundleID
        PresetNotificationService.shared.postWindowNeverAppeared(appName: name)
        return nil
    }

    // MARK: - Apply

    /// Apply path for presets that have one or more app-assigned slots. Runs
    /// asynchronously because resolving an assigned slot's anchor may launch
    /// the app and wait for its window to appear.
    func applyPresetWithAppAssignments(
        presetID: UUID,
        allSelections: [GridSelection],
        rectangleApps: [String?],
        groupedPairs: [PresetGroupPair],
        anchorTarget: WindowTarget,
        presetName: String
    ) async {
        // 1. Screen frame resolution — use the anchor target's screen.
        let currentVisibleFrame: CGRect
        let currentScreenFrame: CGRect
        if let screen = NSScreen.screens.first(where: { $0.frame == anchorTarget.screenFrame }) {
            currentVisibleFrame = screen.visibleFrame
            currentScreenFrame = screen.frame
        } else {
            currentVisibleFrame = anchorTarget.visibleFrame
            currentScreenFrame = anchorTarget.screenFrame
        }

        // 2. Resolve assigned-slot anchors (may launch apps + wait up to 30s).
        var entries: [(target: WindowTarget, selection: GridSelection, slotIndex: Int)] = []
        var claimedWIDs: Set<CGWindowID> = []

        for (slotIdx, maybeBID) in rectangleApps.enumerated() {
            guard let bid = maybeBID, slotIdx < allSelections.count else { continue }
            guard let anchor = await resolveAppAnchor(bundleID: bid) else { continue }
            entries.append((anchor, allSelections[slotIdx], slotIdx))
            if anchor.cgWindowID != 0 {
                claimedWIDs.insert(anchor.cgWindowID)
            }
        }

        // 3. Fill unassigned slots from user selection order + z-order, skipping claimed windows.
        let unassignedSlotIndices: [Int] = rectangleApps.enumerated().compactMap { idx, bid in
            bid == nil && idx < allSelections.count ? idx : nil
        }
        if !unassignedSlotIndices.isEmpty {
            let allZOrderIndices = buildZOrderedWindowIndices(count: availableWindowTargets.count)
            let filtered = allZOrderIndices.filter { i in
                guard i < availableWindowTargets.count else { return false }
                return !claimedWIDs.contains(availableWindowTargets[i].cgWindowID)
            }
            for (i, slotIdx) in unassignedSlotIndices.enumerated() {
                guard i < filtered.count else { break }
                let target = availableWindowTargets[filtered[i]]
                entries.append((target, allSelections[slotIdx], slotIdx))
                if target.cgWindowID != 0 {
                    claimedWIDs.insert(target.cgWindowID)
                }
            }
        }

        guard !entries.isEmpty else { return }

        // 4. Placement (adapted from applyToMultipleWindows).
        dismissOverlayImmediately()
        orderOutAllMainWindows()

        displacementAnimationTimer?.cancel()
        displacementAnimationTimer = nil
        restorationAnimationTimer?.cancel()
        restorationAnimationTimer = nil

        for entry in entries {
            var target = entry.target
            target = unhideAppIfNeeded(target)
            let frame = GridCalculator.frame(
                for: entry.selection,
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
            } catch {
                NSLog("[Tiley] applyPresetWithAppAssignments error for slot \(entry.slotIndex): %@", error.localizedDescription)
            }
        }

        // 5. Restore displaced non-target windows.
        let movedWIDs = Set(entries.map { $0.target.cgWindowID })
        for (wid, entry) in displacedWindowFrames where !movedWIDs.contains(wid) {
            accessibilityService.setPosition(entry.origin, for: entry.window)
        }
        displacedWindowFrames.removeAll()

        // 6. Raise primary first, secondaries after — use slotIndex ascending
        // so slot 0 ends up topmost. Reuse the existing index-based raise when
        // possible; otherwise raise by AX element directly.
        raiseEntriesPreservingOrder(entries: entries.sorted(by: { $0.slotIndex < $1.slotIndex }))

        let primaryEntry = entries.min(by: { $0.slotIndex < $1.slotIndex })
        if let primary = primaryEntry {
            lastTargetPID = primary.target.processIdentifier
        }

        let primarySelection = allSelections.first ?? LayoutPreset.emptySelection
        let primaryName = primaryEntry?.target.appName ?? anchorTarget.appName
        recordSelectionAndHide(selection: primarySelection, appName: primaryName, wasConstrained: false)
        let norm = primarySelection.normalized
        TelemetryDeck.signal("layoutApplied", parameters: [
            "columns": "\(norm.endColumn - norm.startColumn + 1)",
            "rows": "\(norm.endRow - norm.startRow + 1)",
            "multiSelection": "\(selectedWindowIndices.count)",
            "selectionCount": "\(allSelections.count)",
            "hasAppAssignments": "true",
        ])

        // 7. Build windowIDBySelectionIndex for autoLinkPresetGroups + satellite registration.
        var windowIDBySelectionIndex: [Int: CGWindowID] = [:]
        for entry in entries where entry.target.cgWindowID != 0 {
            windowIDBySelectionIndex[entry.slotIndex] = entry.target.cgWindowID
        }
        debugLog("PresetApply: entries=\(entries.count), pairs=\(groupedPairs.count), windowIDBySelectionIndex=\(windowIDBySelectionIndex)")

        let movedWindowIDs = entries.map { $0.target.cgWindowID }.filter { $0 != 0 }
        refreshGroupCandidatesAfterPresetApply(targetWindowIDs: movedWindowIDs)

        if !groupedPairs.isEmpty {
            // Run the regular spatial-group linkage for every marked pair —
            // this gives the current apply a proper WindowGroup (visible
            // badges + movement linkage + raise linkage).
            autoLinkPresetGroups(
                groupedPairs: groupedPairs,
                selections: allSelections,
                windowIDBySelectionIndex: windowIDBySelectionIndex,
                visibleFrame: currentVisibleFrame
            )

            // Additionally, for pairs where one or both sides are app-assigned,
            // register session-only satellite links keyed by bundle ID. These
            // outlive the spatial group: when the user applies the preset
            // again with a different window, the previous spatial pair drops
            // (frames no longer touch, member kicked out on revalidation),
            // but the satellite keeps the raise-linkage alive — clicking the
            // old partner still surfaces the anchor app, and vice-versa.
            for pair in groupedPairs {
                let aBID = pair.indexA < rectangleApps.count ? rectangleApps[pair.indexA] : nil
                let bBID = pair.indexB < rectangleApps.count ? rectangleApps[pair.indexB] : nil
                guard let wa = windowIDBySelectionIndex[pair.indexA],
                      let wb = windowIDBySelectionIndex[pair.indexB] else { continue }

                if let bid = aBID, bBID == nil {
                    appSlotSatellites[bid, default: []].insert(wb)
                    debugLog("PresetApply: satellite link \(bid) ← wid=\(wb)")
                    observeSatelliteAndAnchor(satelliteWID: wb, anchorWID: wa)
                    // The just-applied pair is now the active binding for
                    // this bundle; remember its position.
                    activeSatellitePerBundle[bid] = wb
                    saveCurrentPairFrames(bundleID: bid, satelliteWID: wb)
                } else if let bid = bBID, aBID == nil {
                    appSlotSatellites[bid, default: []].insert(wa)
                    debugLog("PresetApply: satellite link \(bid) ← wid=\(wa)")
                    observeSatelliteAndAnchor(satelliteWID: wa, anchorWID: wb)
                    activeSatellitePerBundle[bid] = wa
                    saveCurrentPairFrames(bundleID: bid, satelliteWID: wa)
                }
                // Both sides assigned: each anchor becomes a satellite of the other.
                if let aBID, let bBID, aBID != bBID {
                    appSlotSatellites[aBID, default: []].insert(wb)
                    appSlotSatellites[bBID, default: []].insert(wa)
                    debugLog("PresetApply: dual-anchor satellite \(aBID)↔\(bBID)")
                    observeSatelliteAndAnchor(satelliteWID: wa, anchorWID: wb)
                    observeSatelliteAndAnchor(satelliteWID: wb, anchorWID: wa)
                    activeSatellitePerBundle[aBID] = wb
                    activeSatellitePerBundle[bBID] = wa
                    saveCurrentPairFrames(bundleID: aBID, satelliteWID: wb)
                    saveCurrentPairFrames(bundleID: bBID, satelliteWID: wa)
                }
            }
            // The preset apply may have dissolved an older spatial group —
            // which `stopObserving()`s its members. Re-attach observation on
            // every still-registered satellite so Cmd+Tab / focus-change
            // events continue to fire.
            ensureAllSatellitesObserved()
        }

        TelemetryDeck.signal("presetApplied", parameters: ["presetName": presetName])
    }

    /// Raise helper for `applyPresetWithAppAssignments`. Groups entries by PID
    /// (preserving slot order) and activates each app + raises each window in
    /// reverse order so the first entry in `entries` ends up topmost —
    /// mirrors the logic in `raiseWindowsPreservingOrder(indices:)`.
    func raiseEntriesPreservingOrder(
        entries: [(target: WindowTarget, selection: GridSelection, slotIndex: Int)]
    ) {
        guard !entries.isEmpty else { return }

        var appOrder: [pid_t] = []
        var entriesByApp: [pid_t: [WindowTarget]] = [:]
        for entry in entries {
            let pid = entry.target.processIdentifier
            if entriesByApp[pid] == nil {
                appOrder.append(pid)
            }
            entriesByApp[pid, default: []].append(entry.target)
        }

        for pid in appOrder.reversed() {
            guard let windows = entriesByApp[pid] else { continue }
            NSRunningApplication(processIdentifier: pid)?.activate()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))

            for target in windows.reversed() {
                if let window = target.windowElement {
                    accessibilityService.raiseWindow(window)
                }
            }
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        }
    }

    // MARK: - Satellite raise

    /// Called after the click monitor detects a new focused window. If the
    /// focused window is either an anchor (its PID matches an assigned
    /// bundleID) or a recorded satellite, raise the linked counterpart so
    /// both app + satellite come forward together.
    ///
    /// Cross-app raises require `NSRunningApplication.activate()` *plus*
    /// `kAXRaiseAction`. Just calling `raiseWindow` on an inactive app's
    /// window is a no-op — the kAXRaiseAction only works intra-app.
    func handleAppSlotSatelliteRaise(focusedID: CGWindowID) {
        guard !appSlotSatellites.isEmpty else {
            debugLog("SatelliteRaise: skipped (no satellites registered) focusedID=\(focusedID)")
            return
        }
        // While the Tiley overlay is showing, suppress raise linkage — the
        // user is interacting with Tiley's UI, not arranging windows yet.
        if isShowingLayoutGrid {
            debugLog("SatelliteRaise: skipped (isShowingLayoutGrid) focusedID=\(focusedID)")
            return
        }
        debugLog("SatelliteRaise: focusedID=\(focusedID), satellites=\(appSlotSatellites)")

        // Case A: focused window is a satellite of some bundleID → activate
        // the anchor app and raise its current frontmost window. Everything
        // we bring forward (the anchor, plus stale satellites of the same
        // anchor that share an app with the clicked one) is then explicitly
        // seated *below* the clicked satellite via CGSOrderWindow, so the
        // clicked window stays on top in z-order.
        for (bundleID, satellites) in appSlotSatellites where satellites.contains(focusedID) {
            debugLog("SatelliteRaise:   matched bundle=\(bundleID) satellites=\(satellites)")
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.activationPolicy == .regular }) else {
                debugLog("SatelliteRaise:   no running app for bundle=\(bundleID)")
                continue
            }
            // Prefer the entry from availableWindowTargets (authoritative
            // cgWindowID) so we don't self-raise the clicked satellite.
            let anchor: WindowTarget?
            if let existing = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }) {
                anchor = existing
            } else {
                anchor = try? accessibilityService.windowTarget(for: app.processIdentifier)
            }
            guard let anchor else {
                debugLog("SatelliteRaise:   no anchor WindowTarget for pid=\(app.processIdentifier)")
                continue
            }
            if anchor.cgWindowID == focusedID {
                debugLog("SatelliteRaise:   anchor==focused; skipping self-raise")
                continue
            }
            debugLog("SatelliteRaise:   anchor pid=\(anchor.processIdentifier) wid=\(anchor.cgWindowID) name=\(anchor.appName)")

            // If the active satellite is changing (e.g. user clicked Win1
            // while Win2 was the current active partner), restore the
            // remembered frames for the new pair BEFORE we rebuild the
            // spatial group or evaluate adjacency — the group's adjacency
            // check should see the restored positions.
            let previouslyActive = activeSatellitePerBundle[bundleID]
            if previouslyActive != focusedID {
                restorePairFrames(bundleID: bundleID, satelliteWID: focusedID)
                activeSatellitePerBundle[bundleID] = focusedID
            }
            // Skip the activate+raise path when the spatial group machinery
            // already handled this pair — otherwise we'd bring the anchor
            // back above the clicked satellite and undo
            // `handleGroupMemberRaised`'s CGSOrderWindow pass.
            let spatialHandled: Bool = {
                guard let clickedGID = groupIndexByWindow[focusedID],
                      let anchorGID = groupIndexByWindow[anchor.cgWindowID] else { return false }
                return clickedGID == anchorGID
            }()
            if !spatialHandled {
                debugLog("SatelliteRaise:   activate+raise anchor pid=\(app.processIdentifier)")
                app.activate()
                // Pump the run loop briefly so the activation actually lands
                // before we AXRaise. Without this, kAXRaiseAction can be a
                // no-op because Claude's app isn't frontmost yet — matches
                // the pattern already used by `raiseWindowsPreservingOrder`.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                if let window = anchor.windowElement {
                    accessibilityService.raiseWindow(window)
                } else {
                    debugLog("SatelliteRaise:   anchor has no windowElement")
                }
            } else {
                debugLog("SatelliteRaise:   skipping activate+raise (spatialHandled)")
            }

            // Push every *other* satellite of this anchor below the clicked
            // one — this cancels macOS's "activate surfaces all app windows"
            // behaviour for stale satellites that happen to share an app with
            // the clicked window. The anchor itself is intentionally *not*
            // pushed down: clicking a satellite is meant to bring the anchor
            // forward so the user can see the pinned app window.
            if CGSPrivate.isOrderWindowAvailable {
                for other in satellites where other != focusedID && other != 0 {
                    let ok = CGSPrivate.orderWindow(other, mode: CGSPrivate.kCGSOrderBelow, relativeTo: focusedID)
                    debugLog("SatelliteRaise:   CGSOrderWindow other-satellite=\(other) below focused=\(focusedID) → \(ok)")
                }
            }

            // Dynamically rebuild the spatial group so that anchor + clicked
            // satellite become the active linked pair (movement linkage
            // follows whoever's currently frontmost). If the two windows
            // aren't adjacent (e.g. the satellite's app refused the sizing),
            // the helper preserves the existing group.
            rebuildAnchorSatelliteGroup(anchorWID: anchor.cgWindowID, satelliteWID: focusedID)
        }

        // Case B: focused window is the anchor of some bundleID → activate
        // the frontmost satellite's app and raise it, then seat it below the
        // clicked anchor so the user's click target stays on top.
        if let focusedTarget = availableWindowTargets.first(where: { $0.cgWindowID == focusedID }),
           let focusedBID = NSRunningApplication(processIdentifier: focusedTarget.processIdentifier)?.bundleIdentifier,
           let satellites = appSlotSatellites[focusedBID],
           !satellites.isEmpty {
            // Query CGWindowList directly for a fresh z-order snapshot.
            // `availableWindowTargets` can lag by a refresh cycle, which
            // would make a stale satellite look "frontmost" right after the
            // user clicked a newer partner.
            let frontmostSatelliteID: CGWindowID? = {
                guard let list = CGWindowListCopyWindowInfo(
                    [.optionOnScreenOnly, .excludeDesktopElements],
                    kCGNullWindowID
                ) as? [[String: Any]] else { return nil }
                for info in list {
                    guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
                    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
                    if satellites.contains(wid) { return wid }
                }
                return nil
            }()
            guard let satID = frontmostSatelliteID,
                  let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == satID }),
                  let window = satTarget.windowElement else {
                debugLog("SatelliteRaise:   Case B — no live satellite target for bundle=\(focusedBID)")
                return
            }
            // Skip the activate+raise path when the spatial group machinery
            // already handled this pair.
            let spatialHandled: Bool = {
                guard let clickedGID = groupIndexByWindow[focusedID],
                      let satGID = groupIndexByWindow[satID] else { return false }
                return clickedGID == satGID
            }()
            // If the picked satellite isn't the currently-active partner,
            // restore the anchor's saved position for this pair before
            // raising. Mirrors the Case A behaviour so clicking the anchor
            // also recreates the saved spatial relationship for whichever
            // satellite ends up being surfaced.
            let previouslyActive = activeSatellitePerBundle[focusedBID]
            if previouslyActive != satID {
                restorePairFrames(bundleID: focusedBID, satelliteWID: satID)
                activeSatellitePerBundle[focusedBID] = satID
            }

            if !spatialHandled {
                debugLog("SatelliteRaise:   Case B — activate+raise satellite wid=\(satID) pid=\(satTarget.processIdentifier)")
                NSRunningApplication(processIdentifier: satTarget.processIdentifier)?.activate()
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                accessibilityService.raiseWindow(window)
            } else {
                debugLog("SatelliteRaise:   Case B — spatialHandled, skip activate+raise")
            }
            // Picked satellite is now the active partner for this anchor.
            activeSatellitePerBundle[focusedBID] = satID
            // Seat satellites below the clicked anchor so the anchor stays
            // topmost. Preserve the user's recency order: push older
            // satellites below the frontmost satellite first, then push the
            // frontmost satellite directly below the anchor. This way the
            // most recently-interacted satellite (as seen in the current
            // CGWindowList z-order) ends up closest to the anchor.
            if CGSPrivate.isOrderWindowAvailable {
                // Older satellites (any satellite other than the picked one
                // and the clicked anchor) go below the picked satellite.
                for sat in satellites where sat != 0 && sat != focusedID && sat != satID {
                    let ok = CGSPrivate.orderWindow(sat, mode: CGSPrivate.kCGSOrderBelow, relativeTo: satID)
                    debugLog("SatelliteRaise:   CGSOrderWindow older-satellite=\(sat) below picked=\(satID) → \(ok)")
                }
                // Picked satellite goes directly below the clicked anchor.
                if satID != 0 && satID != focusedID {
                    let ok = CGSPrivate.orderWindow(satID, mode: CGSPrivate.kCGSOrderBelow, relativeTo: focusedID)
                    debugLog("SatelliteRaise:   CGSOrderWindow picked-satellite=\(satID) below focused-anchor=\(focusedID) → \(ok)")
                }
            }

            // Dynamically rebuild the spatial group so anchor's partner is
            // the picked satellite — matches the user's mental model where
            // whichever satellite is currently in front is the one grouped
            // with the anchor.
            rebuildAnchorSatelliteGroup(anchorWID: focusedID, satelliteWID: satID)
        }
    }

    // MARK: - Observation

    /// Ensures both the satellite and the anchor window are AX-observed so
    /// focus-change / raise / move / destroy events fire even when they
    /// aren't members of any spatial `WindowGroup`. This is what lets the
    /// raise linkage trigger on Cmd+Tab or application-switcher activations
    /// (the mouse click monitor only catches mouse events).
    func observeSatelliteAndAnchor(satelliteWID: CGWindowID, anchorWID: CGWindowID) {
        guard let service = windowObservationService else { return }
        if let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == satelliteWID }) {
            service.observe(target: satTarget)
        }
        if let anchorTarget = availableWindowTargets.first(where: { $0.cgWindowID == anchorWID }) {
            service.observe(target: anchorTarget)
        }
    }

    /// Observes every registered satellite and its anchor, across all bundle
    /// IDs in `appSlotSatellites`. Call after any operation that might have
    /// dropped observation — notably `dissolveGroup` (which stops observing
    /// its members) or a preset apply that dissolved an older group whose
    /// members are still tracked as satellites.
    ///
    /// `observe(target:)` is idempotent, so repeated calls are cheap.
    func ensureAllSatellitesObserved() {
        guard let service = windowObservationService else { return }
        for (bundleID, satellites) in appSlotSatellites {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.activationPolicy == .regular }),
               let anchorTarget = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }) {
                service.observe(target: anchorTarget)
            }
            for wid in satellites {
                if let target = availableWindowTargets.first(where: { $0.cgWindowID == wid }) {
                    service.observe(target: target)
                }
            }
        }
    }

    // MARK: - Position memory per satellite pair

    /// Snapshots the current anchor + satellite frames for the pair
    /// `(bundleID, satelliteWID)` into `savedSatellitePairFrames`.
    ///
    /// Reads **live** AX frames rather than relying on the cached
    /// `WindowTarget.frame`, which can lag by a full refresh cycle
    /// immediately after a `windowManager.move` (e.g. right after a preset
    /// apply placed the windows).
    ///
    /// After capturing, the anchor is **snapped** to be exactly flush with
    /// the satellite on the detected adjacency edge. Without the snap, the
    /// few-pixel slack allowed by the adjacency epsilon would accumulate
    /// across repeated drag cycles and the restored pair would end up with
    /// a visible gap/overlap.
    func saveCurrentPairFrames(bundleID: String, satelliteWID: CGWindowID) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }),
              let anchorTarget = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }),
              let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == satelliteWID }) else {
            return
        }
        let anchorFrame = liveFrame(of: anchorTarget.cgWindowID) ?? anchorTarget.frame
        let satFrame = liveFrame(of: satelliteWID) ?? satTarget.frame

        // Snap the anchor onto the satellite's edge if the two are within
        // the adjacency epsilon. This removes any sub-pixel / few-pixel
        // slack from the save so subsequent restores reproduce pixel-
        // perfect adjacency.
        let epsilon: CGFloat = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
        let snappedAnchor = Self.snapAnchor(
            anchorFrame: anchorFrame,
            satelliteFrame: satFrame,
            anchorID: anchorTarget.cgWindowID,
            satelliteID: satelliteWID,
            epsilon: epsilon
        )

        let frames = SatellitePairFrames(
            anchor: snappedAnchor,
            satellite: satFrame,
            screenFrame: anchorTarget.screenFrame,
            visibleFrame: anchorTarget.visibleFrame
        )
        savedSatellitePairFrames[bundleID, default: [:]][satelliteWID] = frames
        debugLog("PairFrames: saved (\(bundleID), \(satelliteWID)) anchor=\(frames.anchor) satellite=\(frames.satellite) (snapped from raw=\(anchorFrame))")
    }

    /// Returns an anchor frame that's **exactly** flush with the satellite
    /// on whichever edge the adjacency detector matched, and — when the
    /// windows share their width/height on the perpendicular axis — snaps
    /// that axis to match too so a preset-placed full-width pair doesn't
    /// drift sideways across repeated drag cycles.
    private static func snapAnchor(
        anchorFrame: CGRect,
        satelliteFrame: CGRect,
        anchorID: CGWindowID,
        satelliteID: CGWindowID,
        epsilon: CGFloat
    ) -> CGRect {
        guard let adj = WindowAdjacencyDetector.adjacency(
            a: anchorID, frameA: anchorFrame,
            b: satelliteID, frameB: satelliteFrame,
            edgeEpsilon: epsilon
        ) else {
            return anchorFrame
        }
        var result = anchorFrame
        let perpEpsilon = epsilon  // reuse the same tolerance for perpendicular snapping
        switch adj.edgeOfA {
        case .top:
            // anchor's top edge ≈ satellite's bottom edge → anchor is below.
            result.origin.y = satelliteFrame.minY - anchorFrame.height
            // Snap X: if widths roughly match or left edges already near,
            // align with satellite's x origin.
            if abs(anchorFrame.width - satelliteFrame.width) <= perpEpsilon
                || abs(anchorFrame.minX - satelliteFrame.minX) <= perpEpsilon {
                result.origin.x = satelliteFrame.minX
            }
        case .bottom:
            // anchor's bottom edge ≈ satellite's top edge → anchor is above.
            result.origin.y = satelliteFrame.maxY
            if abs(anchorFrame.width - satelliteFrame.width) <= perpEpsilon
                || abs(anchorFrame.minX - satelliteFrame.minX) <= perpEpsilon {
                result.origin.x = satelliteFrame.minX
            }
        case .left:
            // anchor's left edge ≈ satellite's right edge → anchor is right of satellite.
            result.origin.x = satelliteFrame.maxX
            if abs(anchorFrame.height - satelliteFrame.height) <= perpEpsilon
                || abs(anchorFrame.minY - satelliteFrame.minY) <= perpEpsilon {
                result.origin.y = satelliteFrame.minY
            }
        case .right:
            // anchor's right edge ≈ satellite's left edge → anchor is left of satellite.
            result.origin.x = satelliteFrame.minX - anchorFrame.width
            if abs(anchorFrame.height - satelliteFrame.height) <= perpEpsilon
                || abs(anchorFrame.minY - satelliteFrame.minY) <= perpEpsilon {
                result.origin.y = satelliteFrame.minY
            }
        }
        return result
    }

    /// Restores the remembered **anchor** position for
    /// `(bundleID, satelliteWID)` — placed relative to the satellite's
    /// *current* frame so the pixel-perfect adjacency that existed when the
    /// pair was saved is reproduced even if the satellite has drifted.
    ///
    /// Only the anchor is moved. The satellite stays wherever it is; the
    /// anchor is translated by the offset recorded at save time so their
    /// relative arrangement (top/bottom, left/right, perfectly flush) is
    /// preserved.
    func restorePairFrames(bundleID: String, satelliteWID: CGWindowID) {
        guard let frames = savedSatellitePairFrames[bundleID]?[satelliteWID] else {
            debugLog("PairFrames: no saved frames for (\(bundleID), \(satelliteWID))")
            return
        }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }),
              let anchorTarget = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }) else {
            return
        }

        // Compute the anchor's new frame relative to the satellite's
        // *current* (live) position. Preserves the saved anchor size and
        // the anchor↔satellite offset captured at save time.
        let liveSatOrigin: CGPoint = liveFrame(of: satelliteWID)?.origin ??
            availableWindowTargets.first(where: { $0.cgWindowID == satelliteWID })?.frame.origin ??
            frames.satellite.origin
        let offset = CGPoint(
            x: frames.anchor.origin.x - frames.satellite.origin.x,
            y: frames.anchor.origin.y - frames.satellite.origin.y
        )
        let newAnchorFrame = CGRect(
            origin: CGPoint(x: liveSatOrigin.x + offset.x, y: liveSatOrigin.y + offset.y),
            size: frames.anchor.size
        )

        // Suppress the observation side-effects and the spatial-group
        // polling follower for the full settle window (~2 s). Without this,
        // the polling can kick in between our retries and re-drag the
        // anchor to a position we then have to correct again. Cancel any
        // pre-existing settle timer and install a fresh one.
        isApplyingGroupTransform = true
        pairRestoreSettleTimer?.cancel()
        let settleTimer = DispatchSource.makeTimerSource(queue: .main)
        settleTimer.schedule(deadline: .now() + 2.0)
        settleTimer.setEventHandler { [weak self] in
            self?.isApplyingGroupTransform = false
            self?.pairRestoreSettleTimer = nil
        }
        settleTimer.resume()
        pairRestoreSettleTimer = settleTimer

        do {
            _ = try windowManager?.move(target: anchorTarget, to: newAnchorFrame, onScreenFrame: frames.screenFrame)
        } catch {
            debugLog("PairFrames: restore error: \(error.localizedDescription)")
        }
        debugLog("PairFrames: restored (\(bundleID), \(satelliteWID)) newAnchor=\(newAnchorFrame) (offset=\(offset) from liveSat=\(liveSatOrigin)) — satellite left in place")

        // Some apps (e.g. Xcode) auto-reposition their window a few hundred
        // ms after activation — by which time our initial restore has
        // landed on a stale satellite position. Kick off a small retry
        // schedule that re-checks adjacency and re-snaps the anchor to
        // the satellite's live position at several points during the
        // settle window.
        let retryDelays: [TimeInterval] = [0.35, 0.7, 1.1, 1.6]
        for delay in retryDelays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.verifyAndReRestoreIfDrifted(bundleID: bundleID, satelliteWID: satelliteWID)
            }
        }
    }

    /// Verification pass that runs shortly after `restorePairFrames`. If the
    /// pair is no longer edge-adjacent (common when apps auto-reposition on
    /// activation, or when the spatial-group follower overshoots during
    /// post-restore settling), recompute the anchor position against the
    /// satellite's *new* live frame and move the anchor again. Runs
    /// multiple times at scheduled intervals so we can catch later drifts.
    private func verifyAndReRestoreIfDrifted(bundleID: String, satelliteWID: CGWindowID) {
        // Only re-restore when this pair is still the currently-active one.
        // If the user has since switched to a different satellite, leave
        // everything alone — re-restoring here would clobber the new pair.
        guard activeSatellitePerBundle[bundleID] == satelliteWID else { return }

        guard let frames = savedSatellitePairFrames[bundleID]?[satelliteWID] else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.activationPolicy == .regular }),
              let anchorTarget = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }),
              let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == satelliteWID }) else {
            return
        }
        let liveAnchor = liveFrame(of: anchorTarget.cgWindowID) ?? anchorTarget.frame
        let liveSat = liveFrame(of: satelliteWID) ?? satTarget.frame
        let epsilon: CGFloat = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
        if WindowAdjacencyDetector.adjacency(
            a: anchorTarget.cgWindowID, frameA: liveAnchor,
            b: satelliteWID, frameB: liveSat,
            edgeEpsilon: epsilon
        ) != nil {
            // Still adjacent — nothing to do.
            return
        }

        // Compute the target anchor frame from the saved offset and the
        // satellite's current live position.
        let offset = CGPoint(
            x: frames.anchor.origin.x - frames.satellite.origin.x,
            y: frames.anchor.origin.y - frames.satellite.origin.y
        )
        let newAnchorFrame = CGRect(
            origin: CGPoint(x: liveSat.origin.x + offset.x, y: liveSat.origin.y + offset.y),
            size: frames.anchor.size
        )

        // Skip the move if the anchor is already at the target position
        // within a small tolerance — otherwise we'd keep issuing no-op
        // moves each retry while the adjacency check somehow still fails.
        let tolerance: CGFloat = 2
        if abs(liveAnchor.origin.x - newAnchorFrame.origin.x) <= tolerance
            && abs(liveAnchor.origin.y - newAnchorFrame.origin.y) <= tolerance
            && abs(liveAnchor.size.width - newAnchorFrame.size.width) <= tolerance
            && abs(liveAnchor.size.height - newAnchorFrame.size.height) <= tolerance {
            debugLog("PairFrames: re-restore no-op — anchor already at target (liveAnchor=\(liveAnchor), target=\(newAnchorFrame), liveSat=\(liveSat))")
            return
        }

        do {
            _ = try windowManager?.move(target: anchorTarget, to: newAnchorFrame, onScreenFrame: frames.screenFrame)
        } catch {
            debugLog("PairFrames: re-restore error: \(error.localizedDescription)")
        }
        debugLog("PairFrames: re-restored after satellite drift — newAnchor=\(newAnchorFrame) liveAnchor=\(liveAnchor) liveSat=\(liveSat.origin)")
    }

    /// If `movedWID` belongs to an active pair (either as anchor or as the
    /// active satellite for its bundle), refresh that pair's saved frames —
    /// but only when the pair is **still edge-adjacent** at this sample.
    ///
    /// Skipping non-adjacent samples avoids capturing transient mid-drag
    /// positions where the follower lags one tick behind the source. Those
    /// frames aren't pixel-perfect adjacent, so restoring them later would
    /// fail to reproduce ぴったり.
    func updateSavedFramesIfActivePair(movedWID: CGWindowID) {
        for (bundleID, activeSat) in activeSatellitePerBundle {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                .first(where: { $0.activationPolicy == .regular }),
                  let anchorTarget = availableWindowTargets.first(where: { $0.processIdentifier == app.processIdentifier }) else {
                continue
            }
            let anchorWID = anchorTarget.cgWindowID
            guard movedWID == anchorWID || movedWID == activeSat else { continue }
            guard let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == activeSat }) else { continue }
            let anchorFrame = liveFrame(of: anchorWID) ?? anchorTarget.frame
            let satFrame = liveFrame(of: activeSat) ?? satTarget.frame

            // Adjacency check — skip the save when the two windows aren't
            // currently edge-adjacent. This prevents a mid-drag (when the
            // spatial-group follower hasn't caught up) from overwriting an
            // earlier clean snapshot with a misaligned one.
            let epsilon: CGFloat = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
            guard WindowAdjacencyDetector.adjacency(
                a: anchorWID, frameA: anchorFrame,
                b: activeSat, frameB: satFrame,
                edgeEpsilon: epsilon
            ) != nil else {
                continue
            }

            // Snap the anchor onto the satellite's edge — removes the
            // few-pixel slack that would otherwise accumulate across
            // repeated drag cycles.
            let snappedAnchor = Self.snapAnchor(
                anchorFrame: anchorFrame,
                satelliteFrame: satFrame,
                anchorID: anchorWID,
                satelliteID: activeSat,
                epsilon: epsilon
            )

            let frames = SatellitePairFrames(
                anchor: snappedAnchor,
                satellite: satFrame,
                screenFrame: anchorTarget.screenFrame,
                visibleFrame: anchorTarget.visibleFrame
            )
            let prev = savedSatellitePairFrames[bundleID]?[activeSat]
            savedSatellitePairFrames[bundleID, default: [:]][activeSat] = frames
            let oldOffset = prev.map { "\($0.anchor.origin.x - $0.satellite.origin.x),\($0.anchor.origin.y - $0.satellite.origin.y)" } ?? "-"
            let newOffset = "\(frames.anchor.origin.x - frames.satellite.origin.x),\(frames.anchor.origin.y - frames.satellite.origin.y)"
            if oldOffset != newOffset {
                debugLog("PairFrames: update (\(bundleID), \(activeSat)) offset \(oldOffset) → \(newOffset) (snappedAnchor=\(snappedAnchor), rawAnchor=\(anchorFrame), satFrame=\(satFrame))")
            }
        }
    }

    /// Explicitly removes the app-slot satellite binding for a pair the user
    /// just unlinked via the grouping badge. If `windowA` is the anchor of a
    /// bundle whose satellites include `windowB` (or vice-versa), drops the
    /// satellite, its saved frames, and — if it was the active partner —
    /// the `activeSatellitePerBundle` entry. A no-op when the pair isn't a
    /// known satellite binding.
    func unlinkAppSlotSatellitePair(windowA: CGWindowID, windowB: CGWindowID) {
        guard !appSlotSatellites.isEmpty else { return }

        let pidA = availableWindowTargets.first(where: { $0.cgWindowID == windowA })?.processIdentifier
        let pidB = availableWindowTargets.first(where: { $0.cgWindowID == windowB })?.processIdentifier
        let bidA = pidA.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }
        let bidB = pidB.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier }

        // Treat each direction: if windowA is the anchor of bundle bidA and
        // windowB is a satellite of bidA, remove it.
        func tryRemove(anchorBundle: String?, candidateSat: CGWindowID) {
            guard let bundleID = anchorBundle else { return }
            guard var satellites = appSlotSatellites[bundleID],
                  satellites.contains(candidateSat) else { return }
            satellites.remove(candidateSat)
            if satellites.isEmpty {
                appSlotSatellites.removeValue(forKey: bundleID)
            } else {
                appSlotSatellites[bundleID] = satellites
            }
            // Also drop its saved frames and, if it was active, clear the
            // active-partner pointer.
            if var bundleFrames = savedSatellitePairFrames[bundleID] {
                bundleFrames.removeValue(forKey: candidateSat)
                if bundleFrames.isEmpty {
                    savedSatellitePairFrames.removeValue(forKey: bundleID)
                } else {
                    savedSatellitePairFrames[bundleID] = bundleFrames
                }
            }
            if activeSatellitePerBundle[bundleID] == candidateSat {
                activeSatellitePerBundle.removeValue(forKey: bundleID)
            }
            debugLog("SatelliteUnlink: removed \(candidateSat) from \(bundleID) (user unlink)")
        }

        tryRemove(anchorBundle: bidA, candidateSat: windowB)
        tryRemove(anchorBundle: bidB, candidateSat: windowA)
    }

    /// Cleanly removes a satellite's frame memory (called on window destroy).
    func removeFrameMemory(for satelliteWID: CGWindowID) {
        for (bundleID, var frames) in savedSatellitePairFrames where frames[satelliteWID] != nil {
            frames.removeValue(forKey: satelliteWID)
            if frames.isEmpty {
                savedSatellitePairFrames.removeValue(forKey: bundleID)
            } else {
                savedSatellitePairFrames[bundleID] = frames
            }
        }
        for (bundleID, active) in activeSatellitePerBundle where active == satelliteWID {
            activeSatellitePerBundle.removeValue(forKey: bundleID)
        }
    }

    // MARK: - Dynamic spatial group switching

    /// Rebuilds the spatial `WindowGroup` containing `anchor` so that its sole
    /// partner is `satelliteWID`. Used after a click flips the "currently
    /// active" satellite so that movement linkage tracks the new pair
    /// (matching the user's expectation: whichever satellite is frontmost
    /// becomes the anchor's group partner — no stale partner from a previous
    /// apply should keep claiming the binding).
    ///
    /// If the new pair isn't frame-adjacent (e.g. the satellite's app
    /// refused the preset's size and overflows), the old group is still
    /// dissolved but no new spatial group is formed — the satellite raise
    /// linkage alone governs the relationship. This matches the user's
    /// expectation that clicking a different satellite should cancel the
    /// old pair's movement linkage immediately.
    func rebuildAnchorSatelliteGroup(anchorWID: CGWindowID, satelliteWID: CGWindowID) {
        guard anchorWID != 0, satelliteWID != 0, anchorWID != satelliteWID else { return }

        // Already grouped as exactly this pair? No-op.
        if let gid = groupIndexByWindow[anchorWID],
           let group = windowGroups[gid],
           group.members == Set([anchorWID, satelliteWID]) {
            return
        }

        // Detect adjacency for the new pair using **live** AX frames —
        // cached `WindowTarget.frame` can lag by a refresh cycle, which
        // would cause us to form the group using stale positions.
        let newAdj: WindowAdjacency? = {
            guard let anchorTarget = availableWindowTargets.first(where: { $0.cgWindowID == anchorWID }),
                  let satTarget = availableWindowTargets.first(where: { $0.cgWindowID == satelliteWID }) else {
                return nil
            }
            let anchorFrame = liveFrame(of: anchorWID) ?? anchorTarget.frame
            let satFrame = liveFrame(of: satelliteWID) ?? satTarget.frame
            return WindowAdjacencyDetector.adjacency(
                a: anchorWID, frameA: anchorFrame,
                b: satelliteWID, frameB: satFrame,
                edgeEpsilon: max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
            )
        }()

        // Dissolve any existing group containing the anchor or the new
        // partner — regardless of whether we can form a new one. A stale
        // partner must not keep its spatial/raise claim on the anchor.
        if let gid = groupIndexByWindow[anchorWID] { dissolveGroup(gid) }
        if let gid = groupIndexByWindow[satelliteWID] { dissolveGroup(gid) }

        if let adj = newAdj {
            linkAdjacency(adj)
            debugLog("DynamicGroup: formed spatial group anchor=\(anchorWID) satellite=\(satelliteWID)")
        } else {
            debugLog("DynamicGroup: dissolved stale group; no adjacency for anchor=\(anchorWID) satellite=\(satelliteWID) — raise-only linkage")
        }
        // dissolveGroup()'s stopObserving may have un-observed windows that
        // are still registered as satellites. Re-attach observation so
        // Cmd+Tab / focus-change events continue firing.
        ensureAllSatellitesObserved()
    }

    // MARK: - Satellite bookkeeping

    /// Intentionally a no-op: satellite links are session-scoped and we keep
    /// them around even when a satellite's window doesn't currently appear in
    /// `availableWindowTargets`. A transient refresh that misses a window
    /// (e.g. during an apply's displacement step) must not permanently drop
    /// the satellite — `handleAppSlotSatelliteRaise` already degrades
    /// gracefully when it can't resolve a satellite at click time. Satellites
    /// are explicitly cleared when their window is destroyed (see
    /// `removeDestroyedWindowFromSatellites`).
    func pruneStaleAppSlotSatellites() {
        // no-op by design
    }

    /// Removes a CGWindowID from every satellite set. Called when a window is
    /// observed to be destroyed (via the grouping AX observer).
    func removeDestroyedWindowFromSatellites(_ id: CGWindowID) {
        guard !appSlotSatellites.isEmpty else { return }
        var touched = false
        for (bid, satellites) in appSlotSatellites where satellites.contains(id) {
            var updated = satellites
            updated.remove(id)
            if updated.isEmpty {
                appSlotSatellites.removeValue(forKey: bid)
            } else {
                appSlotSatellites[bid] = updated
            }
            touched = true
        }
        if touched {
            debugLog("SatellitePrune: removed destroyed wid=\(id) from satellites")
        }
    }

    /// Presents an `NSOpenPanel` for the user to pick an application bundle,
    /// then assigns its bundle identifier to the given preset rectangle.
    func requestAppBrowse(forSelectionIndex selectionIndex: Int, ofPresetID presetID: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = NSLocalizedString("Assign", comment: "Open panel prompt for choosing an application to assign")
        panel.message = NSLocalizedString("Choose an application to assign to this region.", comment: "Open panel message when browsing for an application")

        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier else { return }
        assignApp(bundleID: bid, toSelectionIndex: selectionIndex, ofPresetID: presetID)
    }
}
