import AppKit
import ApplicationServices

// MARK: - Window Grouping
//
// AppState extension that owns window-group state and linkage logic.
// Stored properties live on AppState itself (`windowGroups`,
// `groupIndexByWindow`, `pendingGroupCandidates`, `groupLinkBadgeController`,
// `windowObservationService`, `isApplyingGroupTransform`, `isApplyingGroupRaise`).

extension AppState {

    // MARK: - Installation

    /// Called from `start()`. Creates the AX observation service and wires it
    /// into AppState.
    func installGroupObservation() {
        guard windowObservationService == nil else { return }
        let service = WindowObservationService()
        service.onEvent = { [weak self] event in
            self?.handleGroupObservationEvent(event)
        }
        windowObservationService = service
        installGroupClickMonitor()
        // Watch every currently-known window so manual move/resize gestures
        // outside of any existing group surface "form group" badges on release.
        ensureAllAvailableWindowsObservedForManualMove()
    }

    /// Called from `stop()`. Tears down all observations.
    func uninstallGroupObservation() {
        groupPollingTimer?.cancel()
        groupPollingTimer = nil
        groupPollingSourceID = nil
        groupPollingIntendedSourceID = nil
        stopGroupSpaceMonitorTimer()
        windowObservationService?.stopAll()
        windowObservationService = nil
        uninstallGroupClickMonitor()
        groupLinkBadgeController?.hide()
        groupLinkBadgeController = nil
        windowGroups.removeAll()
        groupIndexByWindow.removeAll()
        pendingGroupCandidates.removeAll()
        manualMoveSettleTimer?.cancel()
        manualMoveSettleTimer = nil
        manuallyMovedWindowIDs.removeAll()
    }

    // MARK: - Click monitor (catches intra-app window switches)

    /// Watches mouse-down events via a CGEventTap.
    /// AX notifications (kAXFocusedWindowChangedNotification / kAXMainWindowChangedNotification)
    /// do not fire in some scenarios (notably intra-app window switches), so we
    /// watch mouse clicks directly and then check — right after the click — whether
    /// the focused window belongs to a group member.
    private func installGroupClickMonitor() {
        guard groupClickEventTap == nil else { return }
        let mask = (1 << CGEventType.leftMouseDown.rawValue)
                 | (1 << CGEventType.rightMouseDown.rawValue)
                 | (1 << CGEventType.leftMouseUp.rawValue)
                 | (1 << CGEventType.rightMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
                let isMouseUp = (type == .leftMouseUp || type == .rightMouseUp)
                DispatchQueue.main.async {
                    if isMouseUp {
                        appState.handleSystemMouseUp()
                    } else {
                        appState.handleSystemMouseDown()
                    }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )
        guard let tap = tap else {
            debugLog("WindowGrouping: CGEventTap creation failed (accessibility permission?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        groupClickEventTap = tap
        groupClickEventTapSource = source
        debugLog("WindowGrouping: click monitor installed (mouse down + up)")
    }

    private func uninstallGroupClickMonitor() {
        if let tap = groupClickEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = groupClickEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        groupClickEventTap = nil
        groupClickEventTapSource = nil
    }

    /// Invoked right after a mouse-down. Waits briefly for the focused window to
    /// settle, then triggers the raise linkage if that window is a group member
    /// or an app-anchored satellite.
    func handleSystemMouseDown() {
        // No groups or app-anchored satellites → nothing to do (save CPU).
        guard !windowGroups.isEmpty || !appSlotSatellites.isEmpty else { return }
        // Give the system a moment to finish the click handoff. ~50ms is enough.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.checkFrontmostForGroupRaise()
        }
    }

    /// Invoked right after a mouse-up. If a group drag/resize session is in
    /// progress, stop polling **immediately** (without waiting the 200 ms idle
    /// timeout) so the on-release resolve pass can run quickly.
    func handleSystemMouseUp() {
        // If a Tiley group polling session is in progress, end it promptly.
        if groupPollingTimer != nil {
            // Stop polling ~50 ms later → resolve. The small delay lets any final
            // in-flight AX event arrive first.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                if self.groupPollingTimer != nil {
                    self.stopGroupPollingTimer()
                }
            }
        }
        // If the user dragged/resized any non-group window, finalize the
        // manual-move detection pass shortly after release. The small delay
        // lets the trailing AX move/resize event arrive first.
        if !manuallyMovedWindowIDs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                self?.processManuallyMovedWindows()
            }
        }
    }

    /// Look up the currently-focused window; if it is a group member, trigger
    /// the raise linkage.
    private func checkFrontmostForGroupRaise() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else { return }
        let pid = frontmostApp.processIdentifier
        if pid == getpid() { return }  // Ignore clicks on Tiley itself.
        guard let cgID = resolveFocusedWindowID(for: pid) else { return }
        if groupIndexByWindow[cgID] != nil {
            handleGroupMemberRaised(id: cgID)
        }
        // Regardless of group membership, also evaluate the app-anchored
        // satellite linkage: clicking a satellite raises the assigned app
        // window, and clicking the anchor raises the frontmost satellite.
        handleAppSlotSatelliteRaise(focusedID: cgID)
    }

    // MARK: - Preset apply hook

    /// Called after a preset has been applied. For any `groupedPairs` marked
    /// in the preset, directly link the corresponding window pair (no badge
    /// click required). Uses the post-apply target frames computed from the
    /// grid rather than AX-reported frames so the link is deterministic and
    /// doesn't have to wait for AX state propagation.
    ///
    /// `windowIDBySelectionIndex` maps each selection index (0 = primary,
    /// 1+ = secondaries) to the CGWindowID that actually landed on it. Pairs
    /// referencing unmapped indices are skipped.
    func autoLinkPresetGroups(
        groupedPairs: [PresetGroupPair],
        selections: [GridSelection],
        windowIDBySelectionIndex: [Int: CGWindowID],
        visibleFrame: CGRect
    ) {
        guard !groupedPairs.isEmpty else { return }
        guard accessibilityGranted else { return }

        let targetFrames: [Int: CGRect] = Dictionary(
            uniqueKeysWithValues: selections.enumerated().map { idx, sel in
                (idx, GridCalculator.frame(for: sel, in: visibleFrame, rows: rows, columns: columns, gap: gap))
            }
        )
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
        for pair in groupedPairs {
            guard let widA = windowIDBySelectionIndex[pair.indexA],
                  let widB = windowIDBySelectionIndex[pair.indexB] else { continue }
            if widA == widB { continue }
            // Skip if already in the same group.
            if let gidA = groupIndexByWindow[widA], let gidB = groupIndexByWindow[widB], gidA == gidB {
                continue
            }
            guard let frameA = targetFrames[pair.indexA], let frameB = targetFrames[pair.indexB] else { continue }
            guard let adj = WindowAdjacencyDetector.adjacency(
                a: widA, frameA: frameA, b: widB, frameB: frameB, edgeEpsilon: epsilon
            ) else {
                debugLog("WindowGrouping: autoLinkPresetGroups skipped pair (\(pair.indexA),\(pair.indexB)) — target frames not adjacent within epsilon \(epsilon)")
                continue
            }
            debugLog("WindowGrouping: autoLinkPresetGroups linking pair (\(pair.indexA),\(pair.indexB)) windows=\(widA),\(widB)")
            linkAdjacency(adj)
        }
    }

    /// Called after a preset has been applied. Detects newly touching edges and
    /// surfaces candidate badges. Adjacencies of existing groups are recomputed
    /// from the current frames; pairs that no longer touch are dropped.
    ///
    /// `targetWindowIDs`: CGWindowIDs of the windows that the preset actually
    /// moved/arranged. Passing these scopes candidate detection and excludes
    /// accidental contacts between unrelated background windows.
    func refreshGroupCandidatesAfterPresetApply(targetWindowIDs: [CGWindowID]) {
        guard accessibilityGranted else {
            debugLog("WindowGrouping: skipping candidate refresh — AX permission not granted")
            return
        }

        debugLog("WindowGrouping: refreshGroupCandidatesAfterPresetApply triggered (targets=\(targetWindowIDs))")
        // Run detection **immediately** so badges appear without delay. Preset
        // apply is synchronous, so the live AX frames reflect the new positions.
        recomputeGroupsAndCandidates(targetWindowIDs: targetWindowIDs)
        // Re-run after a short delay as a fallback for apps where AX state
        // propagation is slow.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.recomputeGroupsAndCandidates(targetWindowIDs: targetWindowIDs)
        }
    }

    /// Current window frames (AppKit coordinates) keyed by CGWindowID.
    /// Reads the **live** AX values. `target.frame` is a cached value and may
    /// be stale, so it is intentionally not used here.
    private func frameSnapshot(for ids: Set<CGWindowID>) -> [CGWindowID: CGRect] {
        let all = allAvailableFrames()
        var result: [CGWindowID: CGRect] = [:]
        for id in ids {
            if let f = all[id] { result[id] = f }
        }
        return result
    }

    /// **Live** frames (read from AX) for every `availableWindowTargets`, keyed
    /// by CGWindowID. `target.frame` is a cache that can lag behind — especially
    /// right after a preset is applied — so we always re-read from AX here.
    private func allAvailableFrames() -> [CGWindowID: CGRect] {
        var result: [CGWindowID: CGRect] = [:]
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        for target in availableWindowTargets where target.cgWindowID != 0 {
            guard let window = target.windowElement else {
                result[target.cgWindowID] = target.frame
                continue
            }
            let (axPos, size) = accessibilityService.readPositionAndSize(of: window)
            guard size.width > 0, size.height > 0 else {
                result[target.cgWindowID] = target.frame
                continue
            }
            let frame = CGRect(
                x: axPos.x,
                y: primaryMaxY - axPos.y - size.height,
                width: size.width,
                height: size.height
            )
            result[target.cgWindowID] = frame
        }
        return result
    }

    /// Refreshes adjacencies of existing groups, recomputes candidate badges,
    /// and updates the overlay.
    ///
    /// If `targetWindowIDs` is nil, only existing groups are revalidated (no
    /// new candidates are generated). Otherwise candidate detection is limited
    /// to those windows plus existing group members.
    private func recomputeGroupsAndCandidates(targetWindowIDs: [CGWindowID]? = nil) {
        // Scope: windows the preset moved + existing group members.
        var candidateScope: Set<CGWindowID> = Set(targetWindowIDs ?? [])
        for group in windowGroups.values {
            candidateScope.formUnion(group.members)
        }

        let frames = allAvailableFrames()
        debugLog("WindowGrouping: recomputeGroupsAndCandidates — totalFrames=\(frames.count) scope=\(candidateScope.count)")
        for (wid, f) in frames where candidateScope.isEmpty || candidateScope.contains(wid) {
            debugLog("WindowGrouping:   window \(wid) frame=\(f)")
        }

        // Tiley-driven moves that touched only part of a group dissolve that
        // group — even if the untouched members still happen to be adjacent.
        // A Tiley resize on one member without its partner is, by the user's
        // intent, a "break the link" gesture.
        let tileyMovedSet: Set<CGWindowID> = Set(targetWindowIDs ?? [])

        // Revalidate each existing group's adjacencies against current frames
        // and drop pairs that no longer touch.
        for (gid, var group) in windowGroups {
            // Drop members that no longer exist.
            group.members = group.members.filter { frames[$0] != nil }
            if group.members.count < 2 {
                dissolveGroup(gid)
                continue
            }
            if !tileyMovedSet.isEmpty {
                let moved = group.members.intersection(tileyMovedSet)
                if !moved.isEmpty && moved.count < group.members.count {
                    debugLog("WindowGrouping: partial Tiley resize on group \(gid) (moved=\(moved.count)/\(group.members.count)) — dissolving")
                    dissolveGroup(gid)
                    continue
                }
            }
            // Recompute intra-group adjacencies.
            var retained: [WindowAdjacency] = []
            for adj in group.adjacencies {
                guard let fA = frames[adj.windowA], let fB = frames[adj.windowB] else { continue }
                if let newAdj = WindowAdjacencyDetector.adjacency(a: adj.windowA, frameA: fA, b: adj.windowB, frameB: fB) {
                    retained.append(newAdj)
                }
            }
            group.adjacencies = retained
            // No adjacencies left → dissolve the group.
            if retained.isEmpty {
                dissolveGroup(gid)
                continue
            }
            group.lastKnownFrames = frameSnapshot(for: group.members)
            windowGroups[gid] = group
        }

        // Candidate detection: use only the subset of frames within scope.
        // Widen the tolerance to `gap + 4pt` so layouts that use a gap still
        // register as "touching" for badge purposes.
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)

        // If targetWindowIDs is nil, skip candidate detection entirely —
        // only existing groups are revalidated.
        if targetWindowIDs != nil {
            let scopedFrames = frames.filter { candidateScope.contains($0.key) }
            let detected = WindowAdjacencyDetector.detect(frames: scopedFrames, edgeEpsilon: epsilon)
            debugLog("WindowGrouping: detected \(detected.count) adjacency pair(s) (epsilon=\(epsilon), scopedFrames=\(scopedFrames.count))")
            for adj in detected {
                debugLog("WindowGrouping:   adj windowA=\(adj.windowA) windowB=\(adj.windowB) edgeOfA=\(adj.edgeOfA.rawValue) mid=\(adj.midpoint)")
            }
            // Merge: keep existing pending candidates, add newly detected ones,
            // and exclude adjacencies that are already inside an existing group.
            var merged: [AdjacencyKey: WindowAdjacency] = [:]
            for adj in pendingGroupCandidates {
                merged[adj.unorderedKey] = adj
            }
            for adj in detected {
                let aInGroup = groupIndexByWindow[adj.windowA]
                let bInGroup = groupIndexByWindow[adj.windowB]
                if let a = aInGroup, let b = bInGroup, a == b { continue }
                merged[adj.unorderedKey] = adj
            }
            pendingGroupCandidates = Array(merged.values)
            // Record a detection timestamp for each new candidate and schedule
            // a 5-second fade-out. Also start AX-observing the candidate windows
            // so that adjacency loss (move/resize) is reflected immediately.
            let now = CFAbsoluteTimeGetCurrent()
            for adj in pendingGroupCandidates {
                let key = adj.unorderedKey
                if pendingCandidateTimestamps[key] == nil {
                    pendingCandidateTimestamps[key] = now
                    let work = DispatchWorkItem { [weak self] in
                        self?.expirePendingCandidate(key: key)
                    }
                    pendingCandidateFadeItems[key] = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
                }
                observeWindowForCandidate(cgWindowID: adj.windowA)
                observeWindowForCandidate(cgWindowID: adj.windowB)
            }
        }
        debugLog("WindowGrouping: pending candidates after filtering: \(pendingGroupCandidates.count)")

        refreshBadgeOverlays()
    }

    // MARK: - Manual move/resize → candidate detection

    /// Ensures the AX observation service is watching every available window
    /// for move/resize/destroy events, so manual user gestures on arbitrary
    /// windows can be detected (not just on existing group members or pending
    /// candidates). The service deduplicates per CGWindowID so repeated calls
    /// are cheap.
    func ensureAllAvailableWindowsObservedForManualMove() {
        guard accessibilityGranted else { return }
        guard let service = windowObservationService else { return }
        var seen: Set<CGWindowID> = []
        let lists: [[WindowTarget]] = [availableWindowTargets, cachedWindowTargets]
        for list in lists {
            for target in list where target.cgWindowID != 0 {
                if !seen.insert(target.cgWindowID).inserted { continue }
                service.observe(target: target)
            }
        }
    }

    /// (Re)starts a short debounce timer that calls
    /// `processManuallyMovedWindows()` once movement settles. A separate
    /// mouse-up trigger calls the same method with no delay so the badge
    /// appears immediately on release.
    func scheduleManualMoveSettle() {
        manualMoveSettleTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // 250 ms after the last move/resize event — long enough to coalesce a
        // burst, short enough to feel responsive when the user releases.
        timer.schedule(deadline: .now() + .milliseconds(250))
        timer.setEventHandler { [weak self] in
            self?.processManuallyMovedWindows()
        }
        timer.resume()
        manualMoveSettleTimer = timer
    }

    /// Drains `manuallyMovedWindowIDs`, runs adjacency detection across all
    /// visible window frames, and surfaces newly-touching pairs (involving at
    /// least one moved window) as pending candidate badges.
    func processManuallyMovedWindows() {
        manualMoveSettleTimer?.cancel()
        manualMoveSettleTimer = nil
        let movedIDs = manuallyMovedWindowIDs
        manuallyMovedWindowIDs.removeAll()
        guard !movedIDs.isEmpty else { return }
        guard accessibilityGranted else { return }
        // Avoid running while Tiley itself is mid-transform or showing the
        // overlay — those flows manage their own candidate refresh.
        if isApplyingGroupTransform { return }
        if isShowingLayoutGrid { return }

        let frames = allAvailableFrames()
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
        let allDetected = WindowAdjacencyDetector.detect(frames: frames, edgeEpsilon: epsilon)
        // Keep only adjacencies involving at least one window the user just moved.
        let detected = allDetected.filter {
            movedIDs.contains($0.windowA) || movedIDs.contains($0.windowB)
        }
        debugLog("WindowGrouping: manual-move settle — moved=\(movedIDs.count) detected=\(detected.count) (epsilon=\(epsilon))")

        var merged: [AdjacencyKey: WindowAdjacency] = [:]
        for adj in pendingGroupCandidates {
            merged[adj.unorderedKey] = adj
        }
        for adj in detected {
            // Skip pairs already inside the same existing group.
            if let a = groupIndexByWindow[adj.windowA],
               let b = groupIndexByWindow[adj.windowB], a == b {
                continue
            }
            merged[adj.unorderedKey] = adj
        }
        pendingGroupCandidates = Array(merged.values)

        let now = CFAbsoluteTimeGetCurrent()
        for adj in pendingGroupCandidates {
            let key = adj.unorderedKey
            if pendingCandidateTimestamps[key] == nil {
                pendingCandidateTimestamps[key] = now
                let work = DispatchWorkItem { [weak self] in
                    self?.expirePendingCandidate(key: key)
                }
                pendingCandidateFadeItems[key] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: work)
            }
            observeWindowForCandidate(cgWindowID: adj.windowA)
            observeWindowForCandidate(cgWindowID: adj.windowB)
        }

        refreshBadgeOverlays()
    }

    /// Removes the given candidate, e.g. on timeout or when adjacency is lost.
    func expirePendingCandidate(key: AdjacencyKey) {
        let before = pendingGroupCandidates.count
        pendingGroupCandidates.removeAll { $0.unorderedKey == key }
        pendingCandidateTimestamps.removeValue(forKey: key)
        pendingCandidateFadeItems.removeValue(forKey: key)
        if pendingGroupCandidates.count != before {
            refreshBadgeOverlays()
        }
    }

    // MARK: - Link / Unlink

    /// Called when the user taps an unlinked badge.
    /// Transitively merges with existing groups (merge-on-link).
    func linkAdjacency(_ adj: WindowAdjacency) {
        let existingA = groupIndexByWindow[adj.windowA]
        let existingB = groupIndexByWindow[adj.windowB]

        let frames = allAvailableFrames()
        let memberMetaA = memberMeta(for: adj.windowA)
        let memberMetaB = memberMeta(for: adj.windowB)
        guard let metaA = memberMetaA, let metaB = memberMetaB else { return }

        switch (existingA, existingB) {
        case (nil, nil):
            // Create a brand-new group.
            let group = WindowGroup(
                members: [adj.windowA, adj.windowB],
                adjacencies: [adj],
                memberMeta: [adj.windowA: metaA, adj.windowB: metaB],
                lastKnownFrames: frameSnapshot(for: [adj.windowA, adj.windowB])
            )
            _ = frames  // reserved for future use
            windowGroups[group.id] = group
            groupIndexByWindow[adj.windowA] = group.id
            groupIndexByWindow[adj.windowB] = group.id
            observeGroupMembers(group)
            debugLog("WindowGrouping: group formed id=\(group.id) edge=\(adj.edgeOfA.rawValue) members=\(describeMembers(group.members))")

        case (let gid?, nil):
            windowGroups[gid]?.members.insert(adj.windowB)
            windowGroups[gid]?.adjacencies.append(adj)
            windowGroups[gid]?.memberMeta[adj.windowB] = metaB
            if let frame = frames[adj.windowB] {
                windowGroups[gid]?.lastKnownFrames[adj.windowB] = frame
            }
            groupIndexByWindow[adj.windowB] = gid
            if let group = windowGroups[gid] {
                observeGroupMembers(group)
                debugLog("WindowGrouping: group \(gid) gained member — added=\(describeMember(adj.windowB)) members=\(describeMembers(group.members))")
            }

        case (nil, let gid?):
            windowGroups[gid]?.members.insert(adj.windowA)
            windowGroups[gid]?.adjacencies.append(adj)
            windowGroups[gid]?.memberMeta[adj.windowA] = metaA
            if let frame = frames[adj.windowA] {
                windowGroups[gid]?.lastKnownFrames[adj.windowA] = frame
            }
            groupIndexByWindow[adj.windowA] = gid
            if let group = windowGroups[gid] {
                observeGroupMembers(group)
                debugLog("WindowGrouping: group \(gid) gained member — added=\(describeMember(adj.windowA)) members=\(describeMembers(group.members))")
            }

        case (let gidA?, let gidB?):
            if gidA == gidB {
                // Already in the same group — just record the extra adjacency.
                windowGroups[gidA]?.adjacencies.append(adj)
            } else {
                // Merge the two groups.
                mergeGroups(into: gidA, from: gidB, bridgingAdjacency: adj)
            }
        }

        pendingGroupCandidates.removeAll {
            $0.unorderedKey == adj.unorderedKey
        }
        startGroupSpaceMonitorTimer()
        refreshBadgeOverlays()
    }

    /// Renders a single CGWindowID as `id [App: Title]` for log lines, falling
    /// back to just the numeric id when no live target is known.
    private func describeMember(_ id: CGWindowID) -> String {
        if let t = availableWindowTargets.first(where: { $0.cgWindowID == id }) {
            let raw = t.windowTitle ?? ""
            let title = raw.isEmpty ? "-" : raw
            return "\(id) [\(t.appName): \(title)]"
        }
        return "\(id)"
    }

    /// Compact, ordered rendering of a member set for log lines.
    private func describeMembers(_ ids: Set<CGWindowID>) -> String {
        let parts = ids.sorted().map { describeMember($0) }
        return "[\(parts.joined(separator: ", "))]"
    }

    /// Dissolves any group whose members are no longer all on the same macOS
    /// Space. Fires when the user sends only one member to another Space via
    /// Mission Control, a keyboard shortcut, a drag, etc. — the partner can't
    /// cross Spaces via AX, so the two end up on different desktops and the
    /// link no longer makes sense.
    ///
    /// Queries CGS directly for fresh Space IDs so the result does not depend
    /// on the window-list cache, which can lag (or skip refreshes during
    /// Mission Control).
    func dissolveGroupsWithSplitSpaces() {
        guard !windowGroups.isEmpty else { return }

        let allMemberIDs = Array(Set(windowGroups.values.flatMap { $0.members }))
        guard !allMemberIDs.isEmpty else { return }
        let spaceByWID = AccessibilityService.buildWindowSpaceMap(windowIDs: allMemberIDs)

        for (gid, group) in windowGroups {
            let known = group.members.compactMap { spaceByWID[$0] }
            // Skip if any member has no reported Space; a closed window or
            // transient CGS state shouldn't trigger a false dissolve.
            guard known.count == group.members.count else { continue }
            let distinct = Set(known)
            if distinct.count > 1 {
                debugLog("WindowGrouping: group \(gid) members spread across spaces \(distinct) — dissolving")
                dissolveGroup(gid)
            }
        }
    }

    // MARK: - Periodic Space monitoring
    //
    // macOS does not fire an AX event when a window is sent to another Space
    // via keyboard shortcut or Mission Control drag, and the active-Space
    // notification fires only when the *viewer's* Space changes. A lightweight
    // periodic check is the most reliable way to catch "member moved to
    // another Space while the other stayed behind".

    /// Starts a ~1 s interval timer that runs `dissolveGroupsWithSplitSpaces`.
    /// Idempotent — safe to call whenever a group is created/linked.
    func startGroupSpaceMonitorTimer() {
        guard groupSpaceMonitorTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0, leeway: .milliseconds(200))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.windowGroups.isEmpty {
                self.stopGroupSpaceMonitorTimer()
                return
            }
            self.dissolveGroupsWithSplitSpaces()
        }
        timer.resume()
        groupSpaceMonitorTimer = timer
    }

    func stopGroupSpaceMonitorTimer() {
        groupSpaceMonitorTimer?.cancel()
        groupSpaceMonitorTimer = nil
    }

    /// Called when the user taps the `x` on a badge, or when a window is closed.
    func dissolveGroup(_ groupID: UUID) {
        guard let group = windowGroups.removeValue(forKey: groupID) else { return }
        debugLog("WindowGrouping: group dissolved id=\(groupID) members=\(describeMembers(group.members))")
        for id in group.members {
            groupIndexByWindow.removeValue(forKey: id)
            windowObservationService?.stopObserving(cgWindowID: id)
        }
        // After dissolving, any remaining windows that still touch become
        // candidates again.
        recomputeGroupsAndCandidates()
    }

    private func mergeGroups(into keepID: UUID, from removeID: UUID, bridgingAdjacency: WindowAdjacency) {
        guard var keep = windowGroups[keepID], let remove = windowGroups[removeID] else { return }
        keep.members.formUnion(remove.members)
        keep.adjacencies.append(contentsOf: remove.adjacencies)
        keep.adjacencies.append(bridgingAdjacency)
        for (k, v) in remove.memberMeta { keep.memberMeta[k] = v }
        for (k, v) in remove.lastKnownFrames { keep.lastKnownFrames[k] = v }
        windowGroups[keepID] = keep
        windowGroups.removeValue(forKey: removeID)
        for id in remove.members { groupIndexByWindow[id] = keepID }
        debugLog("WindowGrouping: groups merged \(removeID) into \(keepID) members=\(describeMembers(keep.members))")
    }

    private func observeGroupMembers(_ group: WindowGroup) {
        guard let service = windowObservationService else { return }
        for id in group.members {
            if let target = availableWindowTargets.first(where: { $0.cgWindowID == id }) {
                service.observe(target: target)
            }
        }
    }

    /// Start observing a window that is a pending (unlinked) candidate.
    /// Lets us detect adjacency loss on move/resize and fade the badge out
    /// immediately.
    private func observeWindowForCandidate(cgWindowID: CGWindowID) {
        guard let service = windowObservationService else { return }
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }) else { return }
        service.observe(target: target)
    }

    private func memberMeta(for cgWindowID: CGWindowID) -> WindowGroupMember? {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }) else { return nil }
        return WindowGroupMember(cgWindowID: cgWindowID, processIdentifier: target.processIdentifier)
    }

    // MARK: - Badge overlays

    /// Computes the set of badges to show and updates the overlay.
    /// Each badge has its own small NSWindow — no fullscreen transparent overlay.
    ///
    /// A group's / candidate's badges are hidden unless the frontmost app owns
    /// at least one of the involved windows. In other words, when the related
    /// windows are buried behind other windows the badges vanish with them.
    /// Unlinked candidates also auto-expire after 5 seconds and disappear
    /// immediately when the pair no longer touches. Linked badges are hidden
    /// while a drag/resize is in progress.
    /// `fastHide = true` shortens the fade-out duration (used at the moment a
    /// drag/resize starts so badges disappear quickly).
    func refreshBadgeOverlays(fastHide: Bool = false) {
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let now = CFAbsoluteTimeGetCurrent()
        var badges: [GroupLinkBadge] = []

        // Hide linked badges while a drag/resize is in progress
        // (i.e. while the polling timer is running).
        let isInteracting = groupPollingTimer != nil

        // Fetch live frames for adjacency checks.
        let liveFrames = allAvailableFrames()
        let epsilon = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)
        // Hidden windows (fully covered by another window above them in
        // Z-order) shouldn't surface grouping badges — the user can't see
        // them, so they aren't candidates for grouping.
        let occludedIDs = occludedWindowIDsForBadges()

        // Unlinked candidates.
        var expiredKeys: [AdjacencyKey] = []
        for adj in pendingGroupCandidates {
            // Timeout check.
            if let ts = pendingCandidateTimestamps[adj.unorderedKey], now - ts > 5.0 {
                expiredKeys.append(adj.unorderedKey)
                continue
            }
            // Revalidate adjacency: are the edges still touching?
            if let fA = liveFrames[adj.windowA], let fB = liveFrames[adj.windowB] {
                if WindowAdjacencyDetector.adjacency(a: adj.windowA, frameA: fA, b: adj.windowB, frameB: fB, edgeEpsilon: epsilon) == nil {
                    expiredKeys.append(adj.unorderedKey)
                    continue
                }
            }
            // Frontmost-app gating.
            guard isAdjacencyInFrontmostApp(adj, frontmostPID: frontmostPID) else { continue }
            // Suppress badges for pairs where either side is hidden behind
            // another window.
            if occludedIDs.contains(adj.windowA) || occludedIDs.contains(adj.windowB) { continue }
            badges.append(GroupLinkBadge(
                id: adj.unorderedKey,
                state: .unlinked,
                center: adj.midpoint,
                adjacency: adj,
                titleA: badgeWindowTitle(for: adj.windowA),
                titleB: badgeWindowTitle(for: adj.windowB),
                // Unlinked badges have no hover menu, so these flags are
                // irrelevant; pass false to keep the panel size minimal.
                canMatchExtents: false,
                canFillScreenWidth: false,
                canFillScreenHeight: false
            ))
        }
        // Drop expired / adjacency-lost candidates.
        for key in expiredKeys {
            pendingGroupCandidates.removeAll { $0.unorderedKey == key }
            pendingCandidateTimestamps.removeValue(forKey: key)
            pendingCandidateFadeItems.removeValue(forKey: key)?.cancel()
        }

        // Linked badges (members of an existing group): shown when any member
        // belongs to the frontmost PID. Hidden while a drag/resize is active.
        if !isInteracting {
            for group in windowGroups.values {
                let groupIsActive = group.members.contains { cgWindowID in
                    availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID })?.processIdentifier == frontmostPID
                }
                guard groupIsActive else { continue }
                for adj in group.adjacencies {
                    if occludedIDs.contains(adj.windowA) || occludedIDs.contains(adj.windowB) { continue }
                    let fill = canFillScreen(adj: adj, frames: liveFrames)
                    badges.append(GroupLinkBadge(
                        id: adj.unorderedKey,
                        state: .linked,
                        center: adj.midpoint,
                        adjacency: adj,
                        titleA: badgeWindowTitle(for: adj.windowA),
                        titleB: badgeWindowTitle(for: adj.windowB),
                        canMatchExtents: canMatchExtents(adj: adj, frames: liveFrames),
                        canFillScreenWidth: fill.width,
                        canFillScreenHeight: fill.height
                    ))
                }
            }
        }
        debugLog("WindowGrouping: refreshBadgeOverlays total badges=\(badges.count) frontmostPID=\(frontmostPID ?? -1) isInteracting=\(isInteracting)")

        if groupLinkBadgeController == nil {
            let controller = GroupLinkBadgeController()
            controller.onBadgeAction = { [weak self] badge, action in
                self?.handleBadgeAction(badge, action: action)
            }
            groupLinkBadgeController = controller
        }
        groupLinkBadgeController?.update(badges: badges, fadeOutDuration: fastHide ? 0.15 : nil)
    }

    /// True when the two windows of `adj` differ on the axis perpendicular to
    /// their shared edge — i.e. the "match window heights/widths" action would
    /// actually grow at least one window. Returns false (button hidden) when
    /// the outer envelope already lines up on both sides, or when live frames
    /// can't be read.
    private func canMatchExtents(adj: WindowAdjacency, frames: [CGWindowID: CGRect]) -> Bool {
        guard let fA = frames[adj.windowA], let fB = frames[adj.windowB] else { return false }
        let tol: CGFloat = 1
        if adj.edgeOfA.isHorizontal {
            // Side-by-side pair → check vertical extent.
            return abs(fA.minY - fB.minY) > tol || abs(fA.maxY - fB.maxY) > tol
        } else {
            // Stacked pair → check horizontal extent.
            return abs(fA.minX - fB.minX) > tol || abs(fA.maxX - fB.maxX) > tol
        }
    }

    /// Returns `(canFillWidth, canFillHeight)` for the group containing `adj`,
    /// based on whether the group's bounding box already spans the visible
    /// width / height of its screen (Dock and menu bar excluded). False on
    /// either axis means the corresponding hover-menu button is hidden because
    /// the group already fills the screen on that axis.
    private func canFillScreen(adj: WindowAdjacency, frames: [CGWindowID: CGRect])
        -> (width: Bool, height: Bool)
    {
        guard let gid = groupIndexByWindow[adj.windowA] ?? groupIndexByWindow[adj.windowB],
              let group = windowGroups[gid] else { return (false, false) }
        let memberFrames = group.members.compactMap { frames[$0] }
        guard memberFrames.count >= 2 else { return (false, false) }
        guard let bounds = groupBoundingRect(frames: memberFrames) else { return (false, false) }
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return (false, false) }
        let tol: CGFloat = 2
        let alreadyFillsWidth = abs(bounds.minX - visible.minX) <= tol
            && abs(bounds.maxX - visible.maxX) <= tol
        let alreadyFillsHeight = abs(bounds.minY - visible.minY) <= tol
            && abs(bounds.maxY - visible.maxY) <= tol
        return (width: !alreadyFillsWidth, height: !alreadyFillsHeight)
    }

    /// Returns the set of CGWindowIDs whose entire frame is covered by some
    /// other window above them in Z-order — i.e. windows the user can't see.
    /// Used to suppress group link badges for hidden windows.
    ///
    /// On query failure or when a window isn't in the on-screen list, the
    /// window is treated as visible (returned set excludes it) so we err on
    /// the side of showing badges.
    private func occludedWindowIDsForBadges() -> Set<CGWindowID> {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        // Z-order-sorted (front → back) list of normal-layer windows.
        var entries: [(CGWindowID, CGRect)] = []
        for info in infoList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            guard let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            entries.append((wid, rect))
        }

        var occluded: Set<CGWindowID> = []
        for idx in 0..<entries.count {
            let (wid, rect) = entries[idx]
            if rect.isEmpty { continue }
            for i in 0..<idx {
                if entries[i].1.contains(rect) {
                    occluded.insert(wid)
                    break
                }
            }
        }
        return occluded
    }

    /// Returns a display-friendly title for the given window ID, used in badge tooltips.
    /// Prefers the AX window title and falls back to the owning app name.
    private func badgeWindowTitle(for cgWindowID: CGWindowID) -> String {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }) else {
            return ""
        }
        if let title = target.windowTitle, !title.isEmpty {
            return title
        }
        return target.appName
    }

    private func isAdjacencyInFrontmostApp(_ adj: WindowAdjacency, frontmostPID: pid_t?) -> Bool {
        guard let frontmostPID else { return false }
        let pidA = availableWindowTargets.first(where: { $0.cgWindowID == adj.windowA })?.processIdentifier
        let pidB = availableWindowTargets.first(where: { $0.cgWindowID == adj.windowB })?.processIdentifier
        return pidA == frontmostPID || pidB == frontmostPID
    }

    private func handleBadgeAction(_ badge: GroupLinkBadge, action: BadgeAction) {
        switch action {
        case .toggleLink:
            // The badge itself only fires this when unlinked → user wants to link.
            if case .unlinked = badge.state {
                linkAdjacency(badge.adjacency)
            }
        case .ungroup:
            unlinkAdjacency(badge.adjacency)
        case .swap:
            swapAdjacency(badge.adjacency)
        case .matchExtents:
            matchExtentsAdjacency(badge.adjacency)
        case .fillScreenWidth:
            fillGroupToScreen(adj: badge.adjacency, axis: .horizontal)
        case .fillScreenHeight:
            fillGroupToScreen(adj: badge.adjacency, axis: .vertical)
        }
    }

    /// Whether to fill horizontally (X axis, screen width) or vertically
    /// (Y axis, screen height).
    enum FillAxis {
        case horizontal
        case vertical
    }

    /// Proportionally rescales every window in the group containing `adj`
    /// along `axis` so the group's bounding box matches the visible frame
    /// of its screen on that axis. The visible frame excludes the Dock and
    /// menu bar (`NSScreen.visibleFrame`). Relative spacing between members
    /// is preserved by linearly mapping each member's local span on that
    /// axis from `groupBounds` to `visibleFrame`.
    func fillGroupToScreen(adj: WindowAdjacency, axis: FillAxis) {
        guard let gid = groupIndexByWindow[adj.windowA] ?? groupIndexByWindow[adj.windowB],
              var group = windowGroups[gid] else {
            debugLog("WindowGrouping: fillGroupToScreen aborted — no group for adjacency")
            return
        }
        let liveFrames = allAvailableFrames()
        var memberFrames: [(CGWindowID, CGRect)] = []
        for id in group.members {
            if let f = liveFrames[id] { memberFrames.append((id, f)) }
        }
        guard memberFrames.count >= 2 else { return }
        guard let bounds = groupBoundingRect(frames: memberFrames.map(\.1)) else { return }
        // Pick the screen the group sits on. Use the screen that contains the
        // bounding-box centre, falling back to the primary screen.
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: bounds.midX, y: bounds.midY)) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return }

        // Map [bounds.minAxis, bounds.maxAxis] → [visible.minAxis, visible.maxAxis]
        // with a single linear scale so spacing/proportions are preserved.
        var newFrames: [(CGWindowID, CGRect)] = []
        switch axis {
        case .horizontal:
            guard bounds.width > 0, abs(visible.width - bounds.width) > 1 || abs(visible.minX - bounds.minX) > 1 else { return }
            let scale = visible.width / bounds.width
            for (id, f) in memberFrames {
                let newMinX = visible.minX + (f.minX - bounds.minX) * scale
                let newMaxX = visible.minX + (f.maxX - bounds.minX) * scale
                let newRect = CGRect(x: newMinX, y: f.minY, width: newMaxX - newMinX, height: f.height)
                newFrames.append((id, newRect))
            }
        case .vertical:
            guard bounds.height > 0, abs(visible.height - bounds.height) > 1 || abs(visible.minY - bounds.minY) > 1 else { return }
            let scale = visible.height / bounds.height
            for (id, f) in memberFrames {
                let newMinY = visible.minY + (f.minY - bounds.minY) * scale
                let newMaxY = visible.minY + (f.maxY - bounds.minY) * scale
                let newRect = CGRect(x: f.minX, y: newMinY, width: f.width, height: newMaxY - newMinY)
                newFrames.append((id, newRect))
            }
        }

        // Apply all moves under the group-transform suppression flag so the
        // polling follower doesn't fight us.
        isApplyingGroupTransform = true
        for (id, newRect) in newFrames {
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == id }),
                  let window = target.windowElement else { continue }
            _ = try? accessibilityService.setFrame(newRect, on: target.screenFrame, for: window)
            recentlySetFrames[id] = (newRect, CFAbsoluteTimeGetCurrent())
            group.lastKnownFrames[id] = newRect
        }
        // Recompute every adjacency in the group from the new frames so badge
        // midpoints jump to the new shared edges right away.
        var rebuilt: [WindowAdjacency] = []
        for old in group.adjacencies {
            guard let fA = group.lastKnownFrames[old.windowA] ?? liveFrames[old.windowA],
                  let fB = group.lastKnownFrames[old.windowB] ?? liveFrames[old.windowB] else { continue }
            if let updated = WindowAdjacencyDetector.adjacency(a: old.windowA, frameA: fA, b: old.windowB, frameB: fB) {
                rebuilt.append(updated)
            } else {
                rebuilt.append(old)
            }
        }
        group.adjacencies = rebuilt
        windowGroups[gid] = group

        refreshBadgeOverlays()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.isApplyingGroupTransform = false
            self.refreshBadgeOverlays()
        }
    }

    /// Bounding rect of a non-empty array of frames. Returns nil for empty input.
    private func groupBoundingRect(frames: [CGRect]) -> CGRect? {
        guard let first = frames.first else { return nil }
        var minX = first.minX, minY = first.minY, maxX = first.maxX, maxY = first.maxY
        for f in frames.dropFirst() {
            if f.minX < minX { minX = f.minX }
            if f.minY < minY { minY = f.minY }
            if f.maxX > maxX { maxX = f.maxX }
            if f.maxY > maxY { maxY = f.maxY }
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Equalises the perpendicular extent of the two windows that share `adj`.
    ///
    /// For a horizontal-edge pair (windows arranged left/right) both windows'
    /// vertical span is set to the union: top = max(maxY of A, maxY of B),
    /// bottom = min(minY of A, minY of B). The shorter window grows to match
    /// the outer top and outer bottom edges — if one side already extends
    /// further on that axis, the other side stretches out to it.
    ///
    /// For a vertical-edge pair (windows arranged top/bottom) the same is done
    /// along the horizontal axis (minX / maxX).
    ///
    /// The contact edge between the two windows is preserved; only the
    /// perpendicular dimension changes.
    func matchExtentsAdjacency(_ adj: WindowAdjacency) {
        let idA = adj.windowA
        let idB = adj.windowB

        guard let frameA = liveFrame(of: idA), let frameB = liveFrame(of: idB) else {
            debugLog("WindowGrouping: matchExtentsAdjacency aborted — could not read live frames for A=\(idA) B=\(idB)")
            return
        }

        let newFrameA: CGRect
        let newFrameB: CGRect
        if adj.edgeOfA.isHorizontal {
            // Side-by-side pair → unify vertical extent.
            let outerMinY = min(frameA.minY, frameB.minY)
            let outerMaxY = max(frameA.maxY, frameB.maxY)
            let height = outerMaxY - outerMinY
            newFrameA = CGRect(x: frameA.minX, y: outerMinY, width: frameA.width, height: height)
            newFrameB = CGRect(x: frameB.minX, y: outerMinY, width: frameB.width, height: height)
        } else {
            // Stacked pair → unify horizontal extent.
            let outerMinX = min(frameA.minX, frameB.minX)
            let outerMaxX = max(frameA.maxX, frameB.maxX)
            let width = outerMaxX - outerMinX
            newFrameA = CGRect(x: outerMinX, y: frameA.minY, width: width, height: frameA.height)
            newFrameB = CGRect(x: outerMinX, y: frameB.minY, width: width, height: frameB.height)
        }

        // No-op fast path: nothing to grow.
        if Self.framesMatch(newFrameA, frameA, tolerance: 1) &&
           Self.framesMatch(newFrameB, frameB, tolerance: 1) {
            debugLog("WindowGrouping: matchExtentsAdjacency no-op — both windows already span the outer envelope")
            return
        }

        // Suppress group transform reactions while both windows are being
        // resized; we are explicitly choreographing both moves.
        isApplyingGroupTransform = true

        if let target = availableWindowTargets.first(where: { $0.cgWindowID == idA }),
           let window = target.windowElement {
            _ = try? accessibilityService.setFrame(newFrameA, on: target.screenFrame, for: window)
            recentlySetFrames[idA] = (newFrameA, CFAbsoluteTimeGetCurrent())
        }
        if let target = availableWindowTargets.first(where: { $0.cgWindowID == idB }),
           let window = target.windowElement {
            _ = try? accessibilityService.setFrame(newFrameB, on: target.screenFrame, for: window)
            recentlySetFrames[idB] = (newFrameB, CFAbsoluteTimeGetCurrent())
        }

        // Update cached state and recompute the adjacency from the new frames
        // so the badge's position reflects the new shared-edge midpoint right
        // away (same pattern as `swapAdjacency`).
        if let gid = groupIndexByWindow[idA] ?? groupIndexByWindow[idB],
           var group = windowGroups[gid] {
            group.lastKnownFrames[idA] = newFrameA
            group.lastKnownFrames[idB] = newFrameB
            if let idx = group.adjacencies.firstIndex(where: { $0.unorderedKey == adj.unorderedKey }),
               let recomputed = WindowAdjacencyDetector.adjacency(
                a: idA, frameA: newFrameA, b: idB, frameB: newFrameB
               ) {
                group.adjacencies[idx] = recomputed
            }
            windowGroups[gid] = group
        }

        refreshBadgeOverlays()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.isApplyingGroupTransform = false
            self.refreshBadgeOverlays()
        }
    }

    /// Swaps the positions of the two windows that share `adj`. Each window
    /// takes over the other's frame (size and origin), so the union of their
    /// occupied area stays the same and their shared edge keeps touching.
    ///
    /// Per the user-facing contract: any *other* adjacencies (links to a third
    /// window) involving either of the two swapped windows are released — only
    /// the direct A↔B link is preserved.
    func swapAdjacency(_ adj: WindowAdjacency) {
        let idA = adj.windowA
        let idB = adj.windowB

        // Read live frames before mutating anything.
        guard let frameA = liveFrame(of: idA), let frameB = liveFrame(of: idB) else {
            debugLog("WindowGrouping: swapAdjacency aborted — could not read live frames for A=\(idA) B=\(idB)")
            return
        }

        // Drop other adjacencies that involve A or B (but not the A↔B pair
        // itself). Each unlinkAdjacency call recomputes connected components
        // and may split the group; collect the targets up front before any
        // group state changes.
        if let gid = groupIndexByWindow[idA] ?? groupIndexByWindow[idB],
           let group = windowGroups[gid] {
            let preservedKey = adj.unorderedKey
            let toUnlink = group.adjacencies.filter { other in
                guard other.unorderedKey != preservedKey else { return false }
                let touchesA = other.windowA == idA || other.windowB == idA
                let touchesB = other.windowA == idB || other.windowB == idB
                return touchesA || touchesB
            }
            for other in toUnlink {
                unlinkAdjacency(other)
            }
        }

        // Compute the swapped frames. Each window keeps its own size — only
        // the position along the adjacency axis changes, so a 1:2 pair
        // becomes a 2:1 pair instead of becoming 1:2 with the bigger window's
        // size assigned to the originally-smaller window.
        let (newFrameA, newFrameB) = swappedFrames(frameA: frameA, frameB: frameB, axisIsHorizontal: adj.edgeOfA.isHorizontal)

        // Suppress group transform reactions while the two windows move into
        // their swapped positions; we are explicitly choreographing both moves.
        isApplyingGroupTransform = true

        if let target = availableWindowTargets.first(where: { $0.cgWindowID == idA }),
           let window = target.windowElement {
            _ = try? accessibilityService.setFrame(newFrameA, on: target.screenFrame, for: window)
            recentlySetFrames[idA] = (newFrameA, CFAbsoluteTimeGetCurrent())
        }
        if let target = availableWindowTargets.first(where: { $0.cgWindowID == idB }),
           let window = target.windowElement {
            _ = try? accessibilityService.setFrame(newFrameB, on: target.screenFrame, for: window)
            recentlySetFrames[idB] = (newFrameB, CFAbsoluteTimeGetCurrent())
        }

        // Update cached group state so the displacement detector and the
        // badge overlay see the swap as the new ground truth — otherwise the
        // detector compares the post-swap live frames against the *pre-swap*
        // cached frames and tries to drag the windows back to where they
        // were. The adjacency itself also needs to flip: A and B traded sides,
        // so `edgeOfA` becomes its opposite, and the contact coordinate +
        // overlap interval must be recomputed for the new shared edge.
        if let gid = groupIndexByWindow[idA] ?? groupIndexByWindow[idB],
           var group = windowGroups[gid] {
            group.lastKnownFrames[idA] = newFrameA
            group.lastKnownFrames[idB] = newFrameB
            if let idx = group.adjacencies.firstIndex(where: { $0.unorderedKey == adj.unorderedKey }) {
                group.adjacencies[idx] = swappedAdjacency(
                    original: group.adjacencies[idx],
                    newFrameA: newFrameA,
                    newFrameB: newFrameB
                )
            }
            windowGroups[gid] = group
        }

        // Refresh the badge overlay immediately so the link badge jumps to
        // the new shared-edge midpoint instead of staying at the old contact
        // point until the next event tick.
        refreshBadgeOverlays()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.isApplyingGroupTransform = false
            self.refreshBadgeOverlays()
        }
    }

    /// Builds a new `WindowAdjacency` for the given pair after a swap. The
    /// edge stored on A flips to its opposite (A and B traded sides), and
    /// the contact coordinate / overlap interval are recomputed from the new
    /// frames. The window IDs and adjacency-key ordering are preserved so
    /// existing references stay valid.
    private func swappedAdjacency(original: WindowAdjacency, newFrameA: CGRect, newFrameB: CGRect) -> WindowAdjacency {
        let newEdge = original.edgeOfA.opposite
        let contact: CGFloat
        let overlapStart: CGFloat
        let overlapEnd: CGFloat
        switch newEdge {
        case .right:
            contact = (newFrameA.maxX + newFrameB.minX) / 2
            overlapStart = max(newFrameA.minY, newFrameB.minY)
            overlapEnd = min(newFrameA.maxY, newFrameB.maxY)
        case .left:
            contact = (newFrameB.maxX + newFrameA.minX) / 2
            overlapStart = max(newFrameA.minY, newFrameB.minY)
            overlapEnd = min(newFrameA.maxY, newFrameB.maxY)
        case .top:
            contact = (newFrameA.maxY + newFrameB.minY) / 2
            overlapStart = max(newFrameA.minX, newFrameB.minX)
            overlapEnd = min(newFrameA.maxX, newFrameB.maxX)
        case .bottom:
            contact = (newFrameB.maxY + newFrameA.minY) / 2
            overlapStart = max(newFrameA.minX, newFrameB.minX)
            overlapEnd = min(newFrameA.maxX, newFrameB.maxX)
        }
        return WindowAdjacency(
            windowA: original.windowA,
            windowB: original.windowB,
            edgeOfA: newEdge,
            overlapStart: overlapStart,
            overlapEnd: overlapEnd,
            contactCoordinate: contact
        )
    }

    /// Computes the post-swap frames for a touching pair. Each window keeps
    /// its own size; only its position along the adjacency axis flips so the
    /// "left" and "right" (or "bottom" and "top") roles trade places. Any gap
    /// between the original frames is preserved at the new shared edge.
    ///
    /// Example (horizontal): A at x=0..1, B at x=1+g..3+g (gap g).
    /// After swap: B at x=0..2, A at x=2+g..3+g — combined span and gap unchanged.
    private func swappedFrames(frameA: CGRect, frameB: CGRect, axisIsHorizontal: Bool) -> (CGRect, CGRect) {
        if axisIsHorizontal {
            let combinedMinX = min(frameA.minX, frameB.minX)
            let combinedMaxX = max(frameA.maxX, frameB.maxX)
            let aWasLeft = frameA.minX <= frameB.minX
            let newA: CGRect
            let newB: CGRect
            if aWasLeft {
                // A was on the left → moves to the right (right-aligned to combinedMaxX).
                newA = CGRect(x: combinedMaxX - frameA.width, y: frameA.minY,
                              width: frameA.width, height: frameA.height)
                newB = CGRect(x: combinedMinX, y: frameB.minY,
                              width: frameB.width, height: frameB.height)
            } else {
                newA = CGRect(x: combinedMinX, y: frameA.minY,
                              width: frameA.width, height: frameA.height)
                newB = CGRect(x: combinedMaxX - frameB.width, y: frameB.minY,
                              width: frameB.width, height: frameB.height)
            }
            return (newA, newB)
        } else {
            let combinedMinY = min(frameA.minY, frameB.minY)
            let combinedMaxY = max(frameA.maxY, frameB.maxY)
            let aWasBottom = frameA.minY <= frameB.minY
            let newA: CGRect
            let newB: CGRect
            if aWasBottom {
                // A was at the bottom → moves to the top (top-aligned to combinedMaxY).
                newA = CGRect(x: frameA.minX, y: combinedMaxY - frameA.height,
                              width: frameA.width, height: frameA.height)
                newB = CGRect(x: frameB.minX, y: combinedMinY,
                              width: frameB.width, height: frameB.height)
            } else {
                newA = CGRect(x: frameA.minX, y: combinedMinY,
                              width: frameA.width, height: frameA.height)
                newB = CGRect(x: frameB.minX, y: combinedMaxY - frameB.height,
                              width: frameB.width, height: frameB.height)
            }
            return (newA, newB)
        }
    }

    /// Removes only the given adjacency from its group.
    /// If the group becomes disconnected as a result, split it along its
    /// connected components. Components with a single member (i.e. isolated
    /// windows) are detached from any group entirely.
    ///
    /// This is the user's explicit "ungroup" action (from the unlink
    /// badge), so we also clear the app-slot satellite link for this pair
    /// — otherwise the raise linkage would keep firing even after the user
    /// explicitly decoupled the two windows.
    func unlinkAdjacency(_ adj: WindowAdjacency) {
        // Explicit unlink → drop the satellite + frame memory for whichever
        // direction of the pair is an app-anchor/satellite binding.
        unlinkAppSlotSatellitePair(windowA: adj.windowA, windowB: adj.windowB)

        guard let gid = groupIndexByWindow[adj.windowA] ?? groupIndexByWindow[adj.windowB] else { return }
        guard var group = windowGroups[gid] else { return }

        // Drop the matching adjacency.
        group.adjacencies.removeAll { $0.unorderedKey == adj.unorderedKey }

        // Recompute connected components over the remaining adjacencies.
        let components = connectedComponents(members: group.members, adjacencies: group.adjacencies)

        if components.count == 1 {
            // Still fully connected → keep the group as-is.
            windowGroups[gid] = group
        } else {
            // Split into multiple components → rebuild the group(s).
            windowGroups.removeValue(forKey: gid)
            for id in group.members {
                groupIndexByWindow.removeValue(forKey: id)
            }
            for component in components {
                let componentAdjacencies = group.adjacencies.filter {
                    component.contains($0.windowA) && component.contains($0.windowB)
                }
                if component.count >= 2 && !componentAdjacencies.isEmpty {
                    // Build a new group for this component.
                    let newGroup = WindowGroup(
                        id: UUID(),
                        members: component,
                        adjacencies: componentAdjacencies,
                        memberMeta: group.memberMeta.filter { component.contains($0.key) },
                        lastKnownFrames: group.lastKnownFrames.filter { component.contains($0.key) }
                    )
                    windowGroups[newGroup.id] = newGroup
                    for id in component {
                        groupIndexByWindow[id] = newGroup.id
                    }
                } else {
                    // Isolated member → detach and stop observing.
                    for id in component {
                        windowObservationService?.stopObserving(cgWindowID: id)
                    }
                }
            }
        }
        refreshBadgeOverlays()
    }

    /// Given a set of members and a list of adjacencies, returns each connected
    /// component (the subsets that are mutually linked through adjacencies).
    private func connectedComponents(members: Set<CGWindowID>, adjacencies: [WindowAdjacency]) -> [Set<CGWindowID>] {
        var visited: Set<CGWindowID> = []
        var components: [Set<CGWindowID>] = []
        for start in members {
            if visited.contains(start) { continue }
            var component: Set<CGWindowID> = []
            var stack: [CGWindowID] = [start]
            while let current = stack.popLast() {
                if visited.contains(current) { continue }
                visited.insert(current)
                component.insert(current)
                for adj in adjacencies {
                    if adj.windowA == current && !visited.contains(adj.windowB) {
                        stack.append(adj.windowB)
                    } else if adj.windowB == current && !visited.contains(adj.windowA) {
                        stack.append(adj.windowA)
                    }
                }
            }
            components.append(component)
        }
        return components
    }

    // MARK: - AX Event handling

    /// Routes events from `WindowObservationService`.
    ///
    /// Move/resize events are used **only as a trigger for polling**; the real
    /// linkage work happens in `pollGroupSource()` at ~120 Hz. AX notifications
    /// arrive at coarse intervals (100–400 ms) which is not enough for smooth
    /// follow-along during drags.
    ///
    /// If an unlinked candidate window (pendingGroupCandidates) moves, we call
    /// `refreshBadgeOverlays()` to re-check adjacency and drop the candidate
    /// (fading the badge) if it no longer applies.
    func handleGroupObservationEvent(_ event: WindowObservationService.Event) {
        switch event {
        case .moved(let id, _), .resized(let id, _):
            if isApplyingGroupTransform { return }
            // While the Tiley overlay is showing, suppress all group-linkage
            // side-effects of move/resize events. Tiley displaces the
            // frontmost window temporarily to reveal a back window the user
            // clicked in the sidebar — that internal shuffling must not
            // cascade into group followers being dragged along.
            if isShowingLayoutGrid {
                if groupPollingTimer != nil {
                    stopGroupPollingTimer()
                }
                return
            }
            // AX-echo detection: if an event fires for a window we recently set
            // via setFrame, and the live frame matches what we set, it's our
            // echo — skip it. If it doesn't match (user moved it afterwards),
            // drop the entry and process normally.
            if let entry = recentlySetFrames[id], CFAbsoluteTimeGetCurrent() - entry.time < 2.0 {
                if let live = liveFrame(of: id), Self.framesMatch(live, entry.frame, tolerance: 2) {
                    return  // echo
                }
                // Mismatch means the user overwrote our position. Clear and fall through.
                recentlySetFrames.removeValue(forKey: id)
            }
            // Keep the saved-pair-frames memory fresh so that switching back
            // to this pair later restores its last-known position.
            updateSavedFramesIfActivePair(movedWID: id)

            let isGroupMember = groupIndexByWindow[id] != nil
            let isPendingCandidate = pendingGroupCandidates.contains { $0.windowA == id || $0.windowB == id }

            if isGroupMember {
                // If the member just entered native macOS fullscreen, dissolve
                // the group — fullscreen windows live on their own Space and
                // can no longer participate in a tiled layout.
                if isMemberFullScreen(cgWindowID: id), let gid = groupIndexByWindow[id] {
                    debugLog("WindowGrouping: member \(id) entered fullscreen — dissolving group \(gid)")
                    stopGroupPollingTimer()
                    dissolveGroup(gid)
                    return
                }
                // At session start, pin the intended source (doesn't change mid-session).
                if groupPollingTimer == nil {
                    groupPollingIntendedSourceID = id
                }
                groupPollingSourceID = id
                startOrResetGroupPollingTimer()
            } else if isPendingCandidate {
                // One side of a candidate moved — revalidate adjacency, drop
                // the candidate if it is no longer adjacent.
                refreshBadgeOverlays()
                // The user may also be moving the candidate window into contact
                // with a *different* window. Track it for the manual-move pass
                // so newly touching edges with other windows are detected too.
                manuallyMovedWindowIDs.insert(id)
                scheduleManualMoveSettle()
            } else {
                // Non-group, non-candidate window moved/resized manually.
                // Record it; on settle (mouse-up or short idle) we'll check
                // whether its edges now touch any other visible window and
                // surface a "form group" candidate badge.
                manuallyMovedWindowIDs.insert(id)
                scheduleManualMoveSettle()
            }
        case .destroyed(let id):
            // Cleanup: the destroyed window could be a member or a candidate.
            if groupIndexByWindow[id] != nil {
                handleMemberDestroyed(id: id)
            }
            let removedAny = pendingGroupCandidates.contains { $0.windowA == id || $0.windowB == id }
            if removedAny {
                pendingGroupCandidates.removeAll { $0.windowA == id || $0.windowB == id }
                refreshBadgeOverlays()
            }
            manuallyMovedWindowIDs.remove(id)
            // Also drop any app-slot satellite references to this window.
            removeDestroyedWindowFromSatellites(id)
            removeFrameMemory(for: id)
        case .raised(let id):
            handleGroupMemberRaised(id: id)
            // Also route through the satellite linkage so Cmd+Tab /
            // application switcher activations (which don't fire a mouse
            // event) can trigger the anchor-or-satellite raise.
            handleAppSlotSatelliteRaise(focusedID: id)
        }
    }

    // MARK: - Polling-based linkage

    private func startOrResetGroupPollingTimer() {
        groupPollingLastChangeAt = CFAbsoluteTimeGetCurrent()
        if groupPollingTimer != nil { return }
        groupPollingTickCount = 0
        let timer = DispatchSource.makeTimerSource(queue: .main)
        // Poll at ~120 Hz (8 ms). Keep per-tick work minimal by skipping badge updates.
        timer.schedule(deadline: .now(), repeating: .milliseconds(8), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            self?.pollGroupSource()
        }
        timer.resume()
        groupPollingTimer = timer
        // When interaction starts, hide linked badges with a **fast** fade.
        refreshBadgeOverlays(fastHide: true)
    }

    private func stopGroupPollingTimer() {
        // Use the **true drag source** (the intended source) for the release
        // correction. groupPollingSourceID can flip to a follower mid-session
        // via AX echo, but intendedSourceID is locked in at session start and
        // reliably points to the window the user is actually dragging.
        let lastSourceID = groupPollingIntendedSourceID ?? groupPollingSourceID
        groupPollingTimer?.cancel()
        groupPollingTimer = nil
        groupPollingSourceID = nil
        groupPollingIntendedSourceID = nil

        // If, during the drag, the source pushed past a follower's min width/
        // height and the two visually overlap, shrink the source back to the
        // contact point on release.
        if let lastSourceID {
            resolveAdjacencyOverlapsOnRelease(lastSourceID: lastSourceID)
        }

        // **Important**: leave the follower caches at their "ideal" values
        // (don't sync to live). Even if the app rejected a size, having the
        // cache track the source's movement keeps the perpendicular-linkage
        // "shares top/bottom" checks correct on the next drag. Previously we
        // synced to live, which caused the follower cache and source cache to
        // diverge after an app reject → sharesTop/sharesBottom flipped to
        // false → the height linkage broke.

        // After interaction, recompute each group's adjacency coordinates from
        // the current frames before re-showing the linked badges, so the badge
        // positions track the new edge locations.
        for gid in windowGroups.keys {
            recomputeAdjacenciesForGroup(gid)
        }
        refreshBadgeOverlays()
    }

    /// Two patterns of correction applied on drag release:
    ///
    /// **A. Source pushed into follower (overlap)** — follower hit its min size
    ///    and the source was pushed further through the contact edge.
    ///    → Pull the source back to the contact point.
    ///
    /// **B. Expanding source forced follower to its min size, and the app
    ///    shifted the follower's non-contact edge** (maxX/minX/maxY/minY) off
    ///    its original position. Example: growing the left window's right edge
    ///    shrinks the right window to its min width, then the app enforces the
    ///    min width by pushing the right edge outward.
    ///    → Shift the follower so its non-contact edge returns to its cached
    ///       position, and align the source's contact edge with the follower's
    ///       new contact edge.
    private func resolveAdjacencyOverlapsOnRelease(lastSourceID: CGWindowID) {
        guard let gid = groupIndexByWindow[lastSourceID],
              var group = windowGroups[gid] else { return }

        var didFix = false
        for adj in group.adjacencies {
            guard adj.windowA == lastSourceID || adj.windowB == lastSourceID else { continue }
            let otherID = (adj.windowA == lastSourceID) ? adj.windowB : adj.windowA
            let sourceEdge: WindowAdjacency.Edge = (adj.windowA == lastSourceID) ? adj.edgeOfA : adj.edgeOfA.opposite

            guard let sourceFrame = liveFrame(of: lastSourceID),
                  let otherFrame = liveFrame(of: otherID),
                  let otherCached = group.lastKnownFrames[otherID] else { continue }

            // === Pattern B: follower overshot its non-contact edge ===
            // If the follower's "supposed-to-be-fixed" edge (the side away from
            // the source) has drifted off the cached position, shift the
            // follower back so that edge returns to where it was.
            var followerFixed = otherFrame
            var followerShifted = false
            switch sourceEdge {
            case .right:
                // Follower is on the right — its maxX should stay fixed.
                // An app's min-width enforcement can push maxX outward, giving
                // otherFrame.maxX > otherCached.maxX.
                if otherFrame.maxX > otherCached.maxX + 1 {
                    followerFixed.origin.x = otherCached.maxX - otherFrame.width
                    followerShifted = true
                }
            case .left:
                // Follower is on the left — its minX should stay fixed.
                if otherFrame.minX < otherCached.minX - 1 {
                    followerFixed.origin.x = otherCached.minX
                    // If the follower was pushed left, restoring origin also
                    // pulls maxX back into place.
                    followerShifted = true
                }
            case .top:
                // Follower is above — its maxY should stay fixed.
                if otherFrame.maxY > otherCached.maxY + 1 {
                    followerFixed.origin.y = otherCached.maxY - otherFrame.height
                    followerShifted = true
                }
            case .bottom:
                // Follower is below — its minY should stay fixed.
                if otherFrame.minY < otherCached.minY - 1 {
                    followerFixed.origin.y = otherCached.minY
                    followerShifted = true
                }
            }

            if followerShifted {
                debugLog("WindowGrouping: follower overshoot — shifting \(otherID) to \(followerFixed)")
                isApplyingGroupTransform = true
                moveMemberWindow(cgWindowID: otherID, to: followerFixed)
                group.lastKnownFrames[otherID] = followerFixed
                didFix = true
            }

            // === Merge point of A + B: fix contact-edge mismatch ===
            // Two cases to distinguish:
            //   - **Overlap**: source's contact edge is inside the follower's
            //     territory → shrink the source.
            //   - **Gap**: there is a gap between source and follower → grow
            //     the follower (do *not* grow the source).
            let targetFollower = followerShifted ? followerFixed : otherFrame

            // Contact-edge correction: retry up to 3 times, re-reading the
            // follower live each pass to recompute the contact (handles apps
            // that continue to nudge their layout dynamically).
            let tol: CGFloat = 0.5
            for retry in 0..<3 {
                guard let liveFollower = liveFrame(of: otherID),
                      let liveSource = liveFrame(of: lastSourceID) else { break }
                let liveTarget = followerShifted ? followerFixed : liveFollower

                var srcCorr: CGRect? = nil
                var followerCorr: CGRect? = nil

                switch sourceEdge {
                case .right:
                    let sourceContact = liveSource.maxX
                    let followerContact = liveTarget.minX
                    if sourceContact > followerContact + tol {
                        var c = liveSource
                        c.size.width = max(50, followerContact - liveSource.minX)
                        srcCorr = c
                    } else if sourceContact < followerContact - tol {
                        var c = liveTarget
                        c.origin.x = sourceContact
                        c.size.width = max(50, liveTarget.maxX - sourceContact)
                        followerCorr = c
                    }
                case .left:
                    let sourceContact = liveSource.minX
                    let followerContact = liveTarget.maxX
                    if sourceContact < followerContact - tol {
                        var c = liveSource
                        c.origin.x = followerContact
                        c.size.width = max(50, liveSource.maxX - followerContact)
                        srcCorr = c
                    } else if sourceContact > followerContact + tol {
                        var c = liveTarget
                        c.size.width = max(50, sourceContact - liveTarget.minX)
                        followerCorr = c
                    }
                case .top:
                    let sourceContact = liveSource.maxY
                    let followerContact = liveTarget.minY
                    if sourceContact > followerContact + tol {
                        var c = liveSource
                        c.size.height = max(50, followerContact - liveSource.minY)
                        srcCorr = c
                    } else if sourceContact < followerContact - tol {
                        var c = liveTarget
                        c.origin.y = sourceContact
                        c.size.height = max(50, liveTarget.maxY - sourceContact)
                        followerCorr = c
                    }
                case .bottom:
                    let sourceContact = liveSource.minY
                    let followerContact = liveTarget.maxY
                    if sourceContact < followerContact - tol {
                        var c = liveSource
                        c.origin.y = followerContact
                        c.size.height = max(50, liveSource.maxY - followerContact)
                        srcCorr = c
                    } else if sourceContact > followerContact + tol {
                        var c = liveTarget
                        c.size.height = max(50, sourceContact - liveTarget.minY)
                        followerCorr = c
                    }
                }

                if srcCorr == nil && followerCorr == nil {
                    debugLog("WindowGrouping: resolve stable after retry=\(retry)")
                    break  // already consistent
                }
                isApplyingGroupTransform = true
                if let c = srcCorr {
                    debugLog("WindowGrouping: resolve overlap (\(sourceEdge.rawValue)) retry=\(retry) source=\(lastSourceID) corrected=\(c)")
                    robustMoveWindow(cgWindowID: lastSourceID, to: c)
                    group.lastKnownFrames[lastSourceID] = c
                }
                if let c = followerCorr {
                    debugLog("WindowGrouping: resolve gap (\(sourceEdge.rawValue)) retry=\(retry) follower=\(otherID) corrected=\(c)")
                    robustMoveWindow(cgWindowID: otherID, to: c)
                    group.lastKnownFrames[otherID] = c
                }
                didFix = true
            }
        }
        windowGroups[gid] = group

        // Keep the "applying" flag up for 300 ms so we absorb the AX echo.
        if didFix {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.isApplyingGroupTransform = false
            }
        }
    }

    /// Called at ~60 Hz. Reads the source window's live frame and, if it has
    /// moved since the last tick, propagates the change to the followers.
    private func pollGroupSource() {
        guard let sourceID = groupPollingSourceID else {
            stopGroupPollingTimer()
            return
        }
        guard let gid = groupIndexByWindow[sourceID],
              var group = windowGroups[gid] else {
            stopGroupPollingTimer()
            return
        }
        if isApplyingGroupTransform { return }
        // Stop polling if the Tiley overlay came up mid-session — its
        // internal displacement moves must not drag group followers along.
        if isShowingLayoutGrid {
            stopGroupPollingTimer()
            return
        }
        guard let newFrame = liveFrame(of: sourceID) else { return }
        guard let oldFrame = group.lastKnownFrames[sourceID] else {
            group.lastKnownFrames[sourceID] = newFrame
            windowGroups[gid] = group
            return
        }

        let originChanged = abs(oldFrame.origin.x - newFrame.origin.x) > 0.5
            || abs(oldFrame.origin.y - newFrame.origin.y) > 0.5
        let sizeChanged = abs(oldFrame.size.width - newFrame.size.width) > 0.5
            || abs(oldFrame.size.height - newFrame.size.height) > 0.5

        if !originChanged && !sizeChanged {
            // Idle. Stop once we've been idle for > 200 ms.
            if CFAbsoluteTimeGetCurrent() - groupPollingLastChangeAt > 0.2 {
                stopGroupPollingTimer()
            }
            return
        }

        groupPollingLastChangeAt = CFAbsoluteTimeGetCurrent()
        groupPollingTickCount += 1
        isApplyingGroupTransform = true
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.isApplyingGroupTransform = false
            }
        }

        if sizeChanged {
            applyGroupResize(&group, sourceID: sourceID, oldFrame: oldFrame, newFrame: newFrame)
        } else {
            let delta = CGSize(
                width: newFrame.origin.x - oldFrame.origin.x,
                height: newFrame.origin.y - oldFrame.origin.y
            )
            applyGroupTranslation(&group, sourceID: sourceID, delta: delta)
        }

        // Update the source's cached frame with the live value (it's a direct
        // result of user input).
        group.lastKnownFrames[sourceID] = newFrame
        windowGroups[gid] = group

        // Badges are hidden during interaction, so skip coordinate recomputation
        // and badge refresh here (keeps the tick cheap). They are recomputed in
        // `stopGroupPollingTimer` when interaction ends.
    }

    /// Returns whether the given window is currently in native macOS fullscreen.
    private func isMemberFullScreen(cgWindowID: CGWindowID) -> Bool {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return false }
        return accessibilityService.isFullScreen(window)
    }

    /// Returns the window's current frame (AppKit coordinates, read live from AX).
    func liveFrame(of cgWindowID: CGWindowID) -> CGRect? {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return nil }
        let (axPos, size) = accessibilityService.readPositionAndSize(of: window)
        guard size.width > 0, size.height > 0 else { return nil }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: axPos.x,
            y: primaryMaxY - axPos.y - size.height,
            width: size.width,
            height: size.height
        )
    }

    private func applyGroupTranslation(_ group: inout WindowGroup, sourceID: CGWindowID, delta: CGSize) {
        for member in group.members where member != sourceID {
            guard let oldFrame = group.lastKnownFrames[member] else { continue }
            let newFrame = oldFrame.offsetBy(dx: delta.width, dy: delta.height)
            moveMemberWindow(cgWindowID: member, to: newFrame)
            // Immediately write the applied frame back into our cache. Reading
            // live AX values is slightly delayed, so relying on them would
            // accumulate errors.
            group.lastKnownFrames[member] = newFrame
        }
        // Run the Z-order touch-up once every 4 ticks to stay cheap (4 × 8 ms = 32 ms ≈ 30 Hz).
        if groupPollingTickCount % 4 == 0 {
            for member in group.members where member != sourceID {
                orderFollowerBelowSource(followerID: member, sourceID: sourceID)
            }
            raiseSourceWindow(sourceID: sourceID)
        }
    }

    private func applyGroupResize(_ group: inout WindowGroup, sourceID: CGWindowID, oldFrame sourceOld: CGRect, newFrame sourceNew: CGRect) {
        let dLeft = sourceNew.minX - sourceOld.minX
        let dRight = sourceNew.maxX - sourceOld.maxX
        let dTop = sourceNew.maxY - sourceOld.maxY
        let dBottom = sourceNew.minY - sourceOld.minY
        debugLog("WindowGrouping:   resize deltas dLeft=\(dLeft) dRight=\(dRight) dTop=\(dTop) dBottom=\(dBottom)")

        // Tolerance for deciding whether two parallel edges "match length".
        let parallelMatchTolerance: CGFloat = max(WindowAdjacencyDetector.defaultEdgeEpsilon, gap + 4.0)

        // Handle adjacencies that touch the source first.
        for adj in group.adjacencies {
            let (otherID, sourceEdge): (CGWindowID, WindowAdjacency.Edge)
            if adj.windowA == sourceID {
                otherID = adj.windowB
                sourceEdge = adj.edgeOfA
            } else if adj.windowB == sourceID {
                otherID = adj.windowA
                sourceEdge = adj.edgeOfA.opposite
            } else {
                continue
            }
            guard let otherOld = group.lastKnownFrames[otherID] else { continue }

            var newMinX = otherOld.minX
            var newMaxX = otherOld.maxX
            var newMinY = otherOld.minY
            var newMaxY = otherOld.maxY

            // 1. Contact-edge linkage.
            switch sourceEdge {
            case .right:
                newMinX = otherOld.minX + dRight
            case .left:
                newMaxX = otherOld.maxX + dLeft
            case .top:
                newMinY = otherOld.minY + dTop
            case .bottom:
                newMaxY = otherOld.maxY + dBottom
            }

            // 2. Perpendicular-edge linkage (when both edges "match length").
            switch sourceEdge {
            case .right, .left:
                let sharesBottom = abs(sourceOld.minY - otherOld.minY) <= parallelMatchTolerance
                let sharesTop = abs(sourceOld.maxY - otherOld.maxY) <= parallelMatchTolerance
                if sharesBottom { newMinY = otherOld.minY + dBottom }
                if sharesTop { newMaxY = otherOld.maxY + dTop }
            case .top, .bottom:
                let sharesLeft = abs(sourceOld.minX - otherOld.minX) <= parallelMatchTolerance
                let sharesRight = abs(sourceOld.maxX - otherOld.maxX) <= parallelMatchTolerance
                if sharesLeft { newMinX = otherOld.minX + dLeft }
                if sharesRight { newMaxX = otherOld.maxX + dRight }
            }

            // Rebuild the frame from the four edges. Clamp the applied value to
            // 50 pt minimum but cache the pre-clamp ideal (avoids accumulated
            // error when the user reverses the drag).
            let idealWidth = newMaxX - newMinX
            let idealHeight = newMaxY - newMinY
            let idealFrame = CGRect(x: newMinX, y: newMinY, width: idealWidth, height: idealHeight)

            let applyWidth = max(50, idealWidth)
            let applyHeight = max(50, idealHeight)
            let desiredFrame = CGRect(x: newMinX, y: newMinY, width: applyWidth, height: applyHeight)

            // Use the "preserve non-contact edge" setter:
            // set size first → read the size the app actually accepted → compute
            // position so the non-contact edge stays fixed at that size.
            // This keeps the follower's fixed edge from drifting even when the
            // app enforces a min size.
            let preservedEdgeValue: CGFloat
            switch sourceEdge {
            case .right:  preservedEdgeValue = otherOld.maxX
            case .left:   preservedEdgeValue = otherOld.minX
            case .top:    preservedEdgeValue = otherOld.maxY
            case .bottom: preservedEdgeValue = otherOld.minY
            }
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == otherID }),
                  let window = target.windowElement else { continue }
            let actualSize = accessibilityService.setFrameLightweightPreservingEdge(
                desiredFrame,
                preservingEdge: sourceEdge,
                edgeValue: preservedEdgeValue,
                on: target.screenFrame,
                for: window
            )
            debugLog("WindowGrouping:   apply follower=\(otherID) desired=\(desiredFrame.size) actual=\(actualSize) preservedEdge=\(sourceEdge.rawValue) edgeValue=\(preservedEdgeValue)")
            // Record the frame we last applied for AX-echo suppression.
            // Since setFrameLightweightPreservingEdge sets the size first then
            // derives position from the actual size, the final frame can't be
            // recovered exactly from (preservedEdge - actualSize). Recording
            // desiredFrame is good enough — the echo check tolerates a few pts.
            recentlySetFrames[otherID] = (desiredFrame, CFAbsoluteTimeGetCurrent())
            group.lastKnownFrames[otherID] = idealFrame

            // Verify & correct pass: even with the size-first approach, some
            // apps don't propagate the new AX values immediately. Read live
            // afterwards and, if the non-contact edge has drifted, force it
            // back with a shift. Retry up to 3 times to settle.
            for _ in 0..<3 {
                guard let live = liveFrame(of: otherID) else { break }
                let actualEdge: CGFloat
                switch sourceEdge {
                case .right:  actualEdge = live.maxX
                case .left:   actualEdge = live.minX
                case .top:    actualEdge = live.maxY
                case .bottom: actualEdge = live.minY
                }
                if abs(actualEdge - preservedEdgeValue) <= 0.5 { break }  // stable
                var c = live
                switch sourceEdge {
                case .right:  c.origin.x = preservedEdgeValue - live.width
                case .left:   c.origin.x = preservedEdgeValue
                case .top:    c.origin.y = preservedEdgeValue - live.height
                case .bottom: c.origin.y = preservedEdgeValue
                }
                accessibilityService.setFrameLightweight(c, on: target.screenFrame, for: window)
            }
        }
        // Source over-drag (cutting into follower territory) is NOT corrected
        // per-tick. It is resolved in one pass on drag release via
        // `resolveAdjacencyOverlapsOnRelease`.
        // Per-tick correction would cause:
        //   - a fight between the source and the user's mouse input,
        //   - cache-source to be overwritten so the source's delta carries error,
        //   - and downstream errors in the follower correction.

        // Z-order touch-up + raise once every 4 ticks (keeps the tick cheap).
        if groupPollingTickCount % 4 == 0 {
            for adj in group.adjacencies {
                let otherID = (adj.windowA == sourceID) ? adj.windowB : adj.windowA
                if otherID != sourceID {
                    orderFollowerBelowSource(followerID: otherID, sourceID: sourceID)
                }
            }
            raiseSourceWindow(sourceID: sourceID)
        }
    }

    /// Keeps the source window in front via AXRaise.
    /// Called during move/resize polling. The source's app is already active,
    /// so no cross-app switching occurs and no flicker is introduced.
    private func raiseSourceWindow(sourceID: CGWindowID) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == sourceID }) else { return }
        guard let window = target.windowElement else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Setter used when we **really need** the app to accept the frame — e.g.
    /// the drag-release correction. Uses the full `setFrame` dance (pre-nudge
    /// + bounce + position fixup), then verifies against the live frame and
    /// retries on mismatch.
    private func robustMoveWindow(cgWindowID: CGWindowID, to frame: CGRect) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return }
        // Retry up to 3 times so the app actually accepts the frame.
        for attempt in 0..<3 {
            do {
                try accessibilityService.setFrame(frame, on: target.screenFrame, for: window)
            } catch {
                debugLog("robustMoveWindow attempt=\(attempt) error: \(error)")
            }
            // verify
            if let live = liveFrame(of: cgWindowID) {
                let match = Self.framesMatch(live, frame, tolerance: 2)
                debugLog("robustMoveWindow attempt=\(attempt) target=\(frame) live=\(live) match=\(match)")
                if match { break }
            }
        }
        recentlySetFrames[cgWindowID] = (frame, CFAbsoluteTimeGetCurrent())
    }

    private func moveMemberWindow(cgWindowID: CGWindowID, to frame: CGRect) {
        guard let target = availableWindowTargets.first(where: { $0.cgWindowID == cgWindowID }),
              let window = target.windowElement else { return }
        // Use the lightweight setter for the high-frequency drag loop.
        // The full `setFrame` does a lot of AX calls (pre-nudge, bounce, etc.)
        // which causes visible follower flicker if repeated at 60 Hz+.
        accessibilityService.setFrameLightweight(frame, on: target.screenFrame, for: window)
        // Record what we set so handleGroupObservationEvent can detect the
        // AX echo via frame comparison.
        recentlySetFrames[cgWindowID] = (frame, CFAbsoluteTimeGetCurrent())
    }

    /// Returns true iff the two frames match within the given tolerance.
    /// Used for AX-echo detection.
    static func framesMatch(_ a: CGRect, _ b: CGRect, tolerance: CGFloat) -> Bool {
        return abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    /// After moving a follower, re-seat its Z-order just below the source.
    /// Some apps auto-raise a window when it is moved via AX; correcting this
    /// immediately keeps the user's drag target visually in front without flicker.
    private func orderFollowerBelowSource(followerID: CGWindowID, sourceID: CGWindowID) {
        guard CGSPrivate.isOrderWindowAvailable else { return }
        CGSPrivate.orderWindow(followerID, mode: CGSPrivate.kCGSOrderBelow, relativeTo: sourceID)
    }

    private func recomputeAdjacenciesForGroup(_ groupID: UUID) {
        guard var group = windowGroups[groupID] else { return }
        let frames = frameSnapshot(for: group.members)
        var updated: [WindowAdjacency] = []
        // Existing adjacencies are **not dropped**. During a resize the
        // follower's AX propagation can lag, so the edges may temporarily look
        // detached — but we want to preserve the link relationship.
        // Recompute each adjacency's contactCoordinate / overlap from the
        // current frames so the badges follow along. Even if the detector
        // would no longer consider the pair "touching", we keep the edge
        // relationship (edgeOfA) and only approximate the coordinates.
        for adj in group.adjacencies {
            guard let fA = frames[adj.windowA], let fB = frames[adj.windowB] else {
                updated.append(adj)
                continue
            }
            updated.append(recomputedCoordinate(for: adj, frameA: fA, frameB: fB))
        }
        group.adjacencies = updated
        windowGroups[groupID] = group
    }

    /// Returns a new `WindowAdjacency` that preserves the existing edge
    /// relationship (edgeOfA) and updates `contactCoordinate` and
    /// `overlapStart/End` from the given frames.
    private func recomputedCoordinate(for adj: WindowAdjacency, frameA: CGRect, frameB: CGRect) -> WindowAdjacency {
        let contact: CGFloat
        let overlapStart: CGFloat
        let overlapEnd: CGFloat

        switch adj.edgeOfA {
        case .right:
            contact = (frameA.maxX + frameB.minX) / 2
            overlapStart = max(frameA.minY, frameB.minY)
            overlapEnd = min(frameA.maxY, frameB.maxY)
        case .left:
            contact = (frameB.maxX + frameA.minX) / 2
            overlapStart = max(frameA.minY, frameB.minY)
            overlapEnd = min(frameA.maxY, frameB.maxY)
        case .top:
            contact = (frameA.maxY + frameB.minY) / 2
            overlapStart = max(frameA.minX, frameB.minX)
            overlapEnd = min(frameA.maxX, frameB.maxX)
        case .bottom:
            contact = (frameB.maxY + frameA.minY) / 2
            overlapStart = max(frameA.minX, frameB.minX)
            overlapEnd = min(frameA.maxX, frameB.maxX)
        }

        return WindowAdjacency(
            windowA: adj.windowA,
            windowB: adj.windowB,
            edgeOfA: adj.edgeOfA,
            overlapStart: overlapStart,
            overlapEnd: overlapEnd,
            contactCoordinate: contact
        )
    }

    private func handleMemberDestroyed(id: CGWindowID) {
        guard let gid = groupIndexByWindow[id] else { return }
        guard var group = windowGroups[gid] else { return }
        group.members.remove(id)
        group.adjacencies.removeAll { $0.windowA == id || $0.windowB == id }
        group.memberMeta.removeValue(forKey: id)
        group.lastKnownFrames.removeValue(forKey: id)
        groupIndexByWindow.removeValue(forKey: id)
        windowObservationService?.stopObserving(cgWindowID: id)

        if group.members.count < 2 {
            // Dissolve once the group has fewer than 2 members.
            for remaining in group.members {
                groupIndexByWindow.removeValue(forKey: remaining)
                windowObservationService?.stopObserving(cgWindowID: remaining)
            }
            windowGroups.removeValue(forKey: gid)
        } else {
            windowGroups[gid] = group
        }
        refreshBadgeOverlays()
    }

    /// Returns the CGWindowID of the currently-focused window for the given PID.
    /// Reads directly from AX instead of relying on the cache order of
    /// availableWindowTargets.
    func resolveFocusedWindowID(for pid: pid_t) -> CGWindowID? {
        let appElement = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focused)
        guard err == .success,
              let focusedCF = focused,
              CFGetTypeID(focusedCF) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedWindow = focusedCF as! AXUIElement
        // Find the availableWindowTargets entry whose AXUIElement matches.
        for target in availableWindowTargets where target.processIdentifier == pid {
            if let te = target.windowElement, CFEqual(te, focusedWindow) {
                return target.cgWindowID
            }
        }
        return nil
    }

    // MARK: - Z-order linkage

    /// When a group member is raised, also raise the other members to the
    /// layer right below it.
    /// Strictly follows the Z-order knowledge in CLAUDE.md:
    ///   activate → AXRaise every member → activate raised app → CGSOrderWindow.
    func handleGroupMemberRaised(id: CGWindowID) {
        if isApplyingGroupRaise {
            debugLog("WindowGrouping: raise short-circuit (isApplyingGroupRaise=true) id=\(id)")
            return
        }
        // Do not trigger the Z-order linkage during a drag/resize:
        // our follower moves can fire didActivate and cascade recursively.
        if isApplyingGroupTransform {
            debugLog("WindowGrouping: raise short-circuit (isApplyingGroupTransform=true) id=\(id)")
            return
        }
        // While the Tiley overlay is showing, the user is browsing/selecting
        // grid cells — suppress group raise so hovering presets or clicking
        // Tiley's UI doesn't cascade into background window activations.
        if isShowingLayoutGrid {
            debugLog("WindowGrouping: raise short-circuit (isShowingLayoutGrid=true) id=\(id)")
            return
        }
        guard let gid = groupIndexByWindow[id] else {
            debugLog("WindowGrouping: raise id=\(id) not in any group")
            return
        }
        guard let group = windowGroups[gid] else {
            debugLog("WindowGrouping: raise group \(gid) not found for id=\(id)")
            return
        }
        guard group.members.count >= 2 else {
            debugLog("WindowGrouping: raise group has < 2 members")
            return
        }
        // If every other member is already visible (not occluded by any other
        // window), there is nothing to raise — skip to avoid focus flicker.
        if areAllOtherMembersVisible(group: group, sourceID: id) {
            debugLog("WindowGrouping: raise skipped — all other members already visible")
            return
        }
        debugLog("WindowGrouping: raise triggered for id=\(id), group members=\(group.members.count)")

        isApplyingGroupRaise = true
        // Keep the flag up long enough. activate() is async and can fire
        // multiple didActivate events; a shorter hold lets us cascade recursively.
        defer {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.isApplyingGroupRaise = false
            }
        }

        // Hybrid approach:
        //   - **Same-app** members: the raised app is already active, so
        //     AXRaise doesn't flicker. Needed to break up any interleaved
        //     non-member windows that split the app's block.
        //   - **Different-app** members: this always takes focus, so AXRaise
        //     is followed by a focus write-back.
        //
        // Sequence:
        //   1) AXRaise every other member (same- or different-app).
        //   2) AXRaise the raised window itself (last-raised wins → frontmost).
        //   3) Write focus back for different-app members.
        //   4) **Finally**, in one batch, use CGSOrderWindow to seat all other
        //      members directly below the raised window.
        //
        // Applying CGSOrderWindow in one final pass deterministically fixes
        // whatever non-deterministic ordering AXRaise/activate left behind.
        // This prevents the "the last-AXRaised member ends up on top" failure
        // when there are 3+ members.
        let raisedTarget = availableWindowTargets.first(where: { $0.cgWindowID == id })
        let raisedPID = raisedTarget?.processIdentifier
        let raisedWindow = raisedTarget?.windowElement

        var sameAppMembers: [CGWindowID] = []
        var diffAppMembers: [(cgID: CGWindowID, target: WindowTarget)] = []
        for member in group.members where member != id {
            guard let t = availableWindowTargets.first(where: { $0.cgWindowID == member }) else {
                debugLog("WindowGrouping:   member \(member) not in availableWindowTargets")
                continue
            }
            if t.processIdentifier == raisedPID {
                sameAppMembers.append(member)
            } else {
                diffAppMembers.append((member, t))
            }
        }
        debugLog("WindowGrouping:   sameApp=\(sameAppMembers.count) diffApp=\(diffAppMembers.count)")

        // 1. AXRaise the same-app other members (pulls them to the frontmost
        //    layer and repairs the app's window block).
        for member in sameAppMembers {
            guard let target = availableWindowTargets.first(where: { $0.cgWindowID == member }),
                  let window = target.windowElement else { continue }
            let axResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            debugLog("WindowGrouping:   [sameApp] AXRaise(\(member)) → \(axResult.rawValue)")
        }
        // 2. For different-app other members, activate + AXRaise.
        //    Without activate(), AXRaise reports success but the window server
        //    does not actually bring the window forward when its app is inactive.
        //    Cross-app focus flicker is unavoidable here.
        for entry in diffAppMembers {
            if let app = NSRunningApplication(processIdentifier: entry.target.processIdentifier) {
                let result = app.activate(options: [])
                debugLog("WindowGrouping:   [diffApp] activate(pid=\(entry.target.processIdentifier)) → \(result)")
            }
            guard let window = entry.target.windowElement else { continue }
            let axResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            debugLog("WindowGrouping:   [diffApp] AXRaise(\(entry.cgID)) → \(axResult.rawValue)")
        }
        // 3. AXRaise the raised window itself to the top (fixes ordering
        //    that the other AXRaises may have disturbed).
        if let rw = raisedWindow {
            AXUIElementPerformAction(rw, kAXRaiseAction as CFString)
        }
        // 4. If any different-app members were involved, reassert focus on
        //    the raised window.
        if !diffAppMembers.isEmpty, let rw = raisedWindow {
            AXUIElementSetAttributeValue(rw, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementSetAttributeValue(rw, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        }
        // 5. Finally, in one batch, use CGSOrderWindow to seat all other
        //    members just below the raised window.
        //    This deterministically overrides the non-deterministic ordering
        //    effects of the AXRaises above.
        if CGSPrivate.isOrderWindowAvailable {
            let allOthers = sameAppMembers + diffAppMembers.map { $0.cgID }
            for member in allOthers {
                let ok = CGSPrivate.orderWindow(member, mode: CGSPrivate.kCGSOrderBelow, relativeTo: id)
                debugLog("WindowGrouping:   CGSOrderWindow(\(member), below, \(id)) → \(ok)")
            }
            // 6. A **non-member** window from the same app as a member can be
            //    sandwiched between group members, visually hiding one of them.
            //    Example: App A has winA1 and winA2; App B has winB1. After
            //    grouping winA1 + winB1, winA2 can sit in front of winB1 and
            //    hide it.
            //    Fix: any non-member window that sits ahead of at least one
            //    member is pushed below the deepest member.
            pushNonMemberSameAppWindowsBelowDeepestMember(group: group)
        }
    }

    /// Returns true iff every group member other than `sourceID` is currently
    /// fully visible (not occluded by any other window).
    /// When true, there's nothing to raise — the linkage can be skipped.
    private func areAllOtherMembersVisible(group: WindowGroup, sourceID: CGWindowID) -> Bool {
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return false }

        // Build a Z-order-sorted list of (cgWindowID, frame) for layer-0 windows.
        var entries: [(CGWindowID, CGRect)] = []
        for info in infoList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any] else { continue }
            guard let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            entries.append((wid, rect))
        }

        // For every non-source member, check whether any **non-member** window
        // above it in Z-order intersects its frame. Other group members don't
        // count as occluders — they're the windows we'd be raising, so pixel-
        // level overlap between members (e.g. from rounding on tiled edges)
        // must not flip this check to false.
        let memberSet = Set(group.members)
        for member in group.members where member != sourceID {
            guard let memberIdx = entries.firstIndex(where: { $0.0 == member }) else {
                debugLog("WindowGrouping: areAllOtherMembersVisible → false (member \(member) not in entries)")
                return false
            }
            let memberRect = entries[memberIdx].1
            for i in 0..<memberIdx {
                let (aboveID, aboveRect) = entries[i]
                if memberSet.contains(aboveID) { continue }
                if aboveRect.intersects(memberRect) {
                    debugLog("WindowGrouping: areAllOtherMembersVisible → false (non-member \(aboveID) rect=\(aboveRect) occludes member \(member) rect=\(memberRect))")
                    return false
                }
            }
        }
        debugLog("WindowGrouping: areAllOtherMembersVisible → true")
        return true
    }

    /// Any non-member window belonging to the same PID as a group member that
    /// is currently sandwiched between members gets pushed below the deepest
    /// member.
    private func pushNonMemberSameAppWindowsBelowDeepestMember(group: WindowGroup) {
        guard CGSPrivate.isOrderWindowAvailable else { return }
        guard let infoList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // Collect each window's Z-order index and owning PID.
        var positions: [CGWindowID: Int] = [:]
        var owners: [CGWindowID: pid_t] = [:]
        for (idx, info) in infoList.enumerated() {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32 else { continue }
            positions[wid] = idx
            owners[wid] = pid_t(pid)
        }

        // Collect the PIDs of group members and their Z-order positions.
        var memberPIDs: Set<pid_t> = []
        var memberPositions: [Int] = []
        for memberID in group.members {
            if let pid = owners[memberID] { memberPIDs.insert(pid) }
            if let pos = positions[memberID] { memberPositions.append(pos) }
        }
        guard let shallowestMemberPos = memberPositions.min(),
              let deepestMemberPos = memberPositions.max() else { return }

        // Find the CGWindowID of the deepest member — used as the reference
        // for the CGSOrderWindow call.
        guard let deepestMemberID = group.members.first(where: { positions[$0] == deepestMemberPos }) else { return }

        debugLog("WindowGrouping:   push-down scan: shallow=\(shallowestMemberPos) deep=\(deepestMemberPos) deepestMemberID=\(deepestMemberID) memberPIDs=\(memberPIDs)")
        // Debug detail: emit (position, ID, PID) for the top 20 windows.
        for (idx, info) in infoList.prefix(20).enumerated() {
            let wid = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let pid = info[kCGWindowOwnerPID as String] as? Int32 ?? 0
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            let isMember = group.members.contains(wid) ? " [MEMBER]" : ""
            debugLog("WindowGrouping:     z[\(idx)] wid=\(wid) pid=\(pid) layer=\(layer) name=\(name)\(isMember)")
        }

        // Walk non-member windows; push any that are owned by a member's PID
        // and sit between two members down below the deepest member.
        for (wid, pos) in positions {
            if group.members.contains(wid) { continue }  // skip members
            guard let pid = owners[wid], memberPIDs.contains(pid) else { continue }  // same app only
            // Deeper than shallowestMember, shallower than deepestMember → sandwiched.
            guard pos > shallowestMemberPos && pos < deepestMemberPos else { continue }
            // First, push below the deepest member.
            let ok1 = CGSPrivate.orderWindow(wid, mode: CGSPrivate.kCGSOrderBelow, relativeTo: deepestMemberID)
            debugLog("WindowGrouping:   push non-member \(wid) (pid=\(pid), pos=\(pos)) below deepest member \(deepestMemberID) → \(ok1)")
            // Belt-and-suspenders: also send to the very back, in case the
            // relative-to form of CGSOrderWindow is ignored across apps.
            let ok2 = CGSPrivate.orderWindow(wid, mode: CGSPrivate.kCGSOrderBelow, relativeTo: 0)
            debugLog("WindowGrouping:   push non-member \(wid) to very back → \(ok2)")
        }
    }
}
