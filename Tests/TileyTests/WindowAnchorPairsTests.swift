import Testing
import AppKit
import ApplicationServices
import CoreGraphics
@testable import Tiley

/// Tests for the window-anchor satellite pair mechanism added so that applying
/// a preset's grouped pair to a window already in another group produces an
/// independent pair (instead of merging into one larger group).
///
/// Per project guidance, these exercise the bookkeeping path with **real**
/// on-screen windows (NSWindow instances created in the test process) so the
/// CGWindowID-keyed state mirrors what would happen at runtime. Move and AX
/// raise side effects are not asserted — they require Accessibility permission
/// for the test runner — but every assertion below verifies the pure
/// bookkeeping outcome that the runtime depends on.
@MainActor
@Suite("WindowAnchorPairs")
final class WindowAnchorPairsTests {

    let state: AppState
    var openedWindows: [NSWindow] = []

    init() {
        state = AppState()
    }

    deinit {
        let toClose = openedWindows
        Task { @MainActor in
            for w in toClose { w.orderOut(nil); w.close() }
        }
    }

    // MARK: - Helpers

    /// Opens a borderless NSWindow so the window server hands back a real
    /// CGWindowID that can drive the bookkeeping under test. The returned
    /// `WindowTarget` uses the exact `frame` the test asks for (not the
    /// position macOS may have constrained the window to) — the bookkeeping
    /// only cares about the values inside `WindowTarget`, and we want
    /// deterministic adjacency math regardless of where macOS actually
    /// placed the window.
    ///
    /// `windowElement` is set to the app's AXUIElement (non-nil) so guards
    /// like `guard let satWindow = satTarget.windowElement` pass; the
    /// downstream AX raise calls become harmless no-ops without
    /// Accessibility permission.
    private func makeRealWindow(_ frame: CGRect, title: String) -> WindowTarget {
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.makeKeyAndOrderFront(nil)
        // Pump the run loop so the window server registers the window and a
        // valid CGWindowID is assigned.
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        openedWindows.append(win)

        let pid = getpid()
        let appEl = AXUIElementCreateApplication(pid)
        return WindowTarget(
            appElement: appEl,
            windowElement: appEl,
            processIdentifier: pid,
            appName: "TileyTests",
            windowTitle: title,
            frame: frame,
            visibleFrame: NSScreen.main?.visibleFrame ?? .zero,
            screenFrame: NSScreen.main?.frame ?? .zero,
            isHidden: false,
            cgWindowID: CGWindowID(win.windowNumber)
        )
    }

    private func register(_ targets: [WindowTarget]) {
        state.availableWindowTargets.append(contentsOf: targets)
    }

    @discardableResult
    private func injectPrimaryGroup(
        members: [CGWindowID],
        adjacencies: [WindowAdjacency],
        frames: [CGWindowID: CGRect]
    ) -> UUID {
        let meta: [CGWindowID: WindowGroupMember] = members.reduce(into: [:]) { dict, id in
            dict[id] = WindowGroupMember(cgWindowID: id, processIdentifier: getpid())
        }
        let group = WindowGroup(
            members: Set(members),
            adjacencies: adjacencies,
            memberMeta: meta,
            lastKnownFrames: frames
        )
        state.windowGroups[group.id] = group
        for m in members { state.groupIndexByWindow[m] = group.id }
        return group.id
    }

    private func zeroFrames() -> AppState.SatellitePairFrames {
        AppState.SatellitePairFrames(
            anchor: .zero, satellite: .zero, screenFrame: .zero, visibleFrame: .zero
        )
    }

    // MARK: - detectWindowAnchorConflict

    @Test("no conflict when neither window is in a group")
    func noConflictWhenNoExistingGroups() {
        #expect(state.detectWindowAnchorConflict(widA: 1, widB: 2) == nil)
    }

    @Test("no conflict when the pair already IS the entire existing 2-member group")
    func noConflictWhenPairIsTheWholeExistingGroup() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        register([a, b])
        let adj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [adj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        #expect(state.detectWindowAnchorConflict(widA: a.cgWindowID, widB: b.cgWindowID) == nil)
        #expect(state.detectWindowAnchorConflict(widA: b.cgWindowID, widB: a.cgWindowID) == nil)
    }

    @Test("conflict: shared window in group with a third member becomes anchor, the other side is the partner")
    func conflictWhenSharedWindowIsInGroupWithThirdMember() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 300, width: 200, height: 200), title: "C")
        register([a, b, c])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        // Linking C-A: A is in group with B (third member) → anchor = A, partner = C.
        let result = state.detectWindowAnchorConflict(widA: c.cgWindowID, widB: a.cgWindowID)
        #expect(result?.anchor == a.cgWindowID)
        #expect(result?.partner == c.cgWindowID)
    }

    @Test("conflict when both sides already belong to different primary groups")
    func conflictWhenBothInDifferentGroups() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 600, y: 100, width: 200, height: 200), title: "C")
        let d = makeRealWindow(CGRect(x: 800, y: 100, width: 200, height: 200), title: "D")
        register([a, b, c, d])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        let cdAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: c.cgWindowID, frameA: c.frame, b: d.cgWindowID, frameB: d.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        injectPrimaryGroup(
            members: [c.cgWindowID, d.cgWindowID],
            adjacencies: [cdAdj],
            frames: [c.cgWindowID: c.frame, d.cgWindowID: d.frame]
        )
        let result = state.detectWindowAnchorConflict(widA: a.cgWindowID, widB: c.cgWindowID)
        #expect(result != nil)
    }

    // MARK: - registerWindowAnchorPair

    @Test("registerWindowAnchorPair converts existing A-B group into A-anchor + B-satellite and adds new partner C as a satellite too")
    func registerConvertsExistingGroupAndAddsNewSatellite() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 300, width: 200, height: 200), title: "C")
        register([a, b, c])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        let abGID = injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )

        state.registerWindowAnchorPair(anchorWID: a.cgWindowID, partnerWID: c.cgWindowID)

        // The original A-B primary group has been dissolved.
        #expect(state.windowGroups[abGID] == nil)
        // Both B (former partner) and C (new partner) are satellites of A.
        let satellites = state.windowAnchorSatellites[a.cgWindowID] ?? []
        #expect(satellites.contains(b.cgWindowID))
        #expect(satellites.contains(c.cgWindowID))
        // Saved frames exist for both pairs.
        #expect(state.savedWindowPairFrames[a.cgWindowID]?[b.cgWindowID] != nil)
        #expect(state.savedWindowPairFrames[a.cgWindowID]?[c.cgWindowID] != nil)
        // The just-registered partner is the active satellite.
        #expect(state.activeSatellitePerWindowAnchor[a.cgWindowID] == c.cgWindowID)
    }

    @Test("old A-B layout is captured from the dissolving group's lastKnownFrames so the original arrangement survives a preset that just moved A")
    func preservesOldLayoutFromLastKnownFrames() throws {
        // Construct a scenario where the WindowTarget's frame reflects the
        // POST-preset position of A (because the preset has just moved it),
        // while the pre-preset A position lives in the existing primary
        // group's `lastKnownFrames`. registerWindowAnchorPair should pull
        // from lastKnownFrames so future B-clicks restore the original
        // layout instead of the post-preset position.
        let aOldFrame = CGRect(x: 0, y: 100, width: 200, height: 200)
        let bOldFrame = CGRect(x: 200, y: 100, width: 200, height: 200)
        let aNewFrame = CGRect(x: 600, y: 500, width: 200, height: 200)
        let cNewFrame = CGRect(x: 400, y: 500, width: 200, height: 200)

        // The NSWindow exists at the new frame (post-preset).
        let aTarget = makeRealWindow(aNewFrame, title: "A")
        let bTarget = makeRealWindow(bOldFrame, title: "B")
        let cTarget = makeRealWindow(cNewFrame, title: "C")
        register([aTarget, bTarget, cTarget])

        // Old A-B primary group's lastKnownFrames remembers the OLD layout.
        let oldAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: aTarget.cgWindowID, frameA: aOldFrame, b: bTarget.cgWindowID, frameB: bOldFrame
        ))
        injectPrimaryGroup(
            members: [aTarget.cgWindowID, bTarget.cgWindowID],
            adjacencies: [oldAdj],
            frames: [aTarget.cgWindowID: aOldFrame, bTarget.cgWindowID: bOldFrame]
        )

        state.registerWindowAnchorPair(anchorWID: aTarget.cgWindowID, partnerWID: cTarget.cgWindowID)

        let savedAB = try #require(state.savedWindowPairFrames[aTarget.cgWindowID]?[bTarget.cgWindowID])
        // Saved offset (anchor.origin - satellite.origin) should derive from
        // the OLD frames, not the new ones. Allow a small tolerance because
        // saveCurrentWindowPairFrames snaps the anchor onto the satellite's
        // adjacent edge.
        let savedOffsetX = savedAB.anchor.origin.x - savedAB.satellite.origin.x
        let expectedOffsetX = aOldFrame.origin.x - bOldFrame.origin.x
        #expect(abs(savedOffsetX - expectedOffsetX) <= 4)
        // The new pair's saved frames reflect the post-preset layout (this
        // is the desired arrangement going forward).
        let savedAC = try #require(state.savedWindowPairFrames[aTarget.cgWindowID]?[cTarget.cgWindowID])
        let savedAcOffsetX = savedAC.anchor.origin.x - savedAC.satellite.origin.x
        let expectedAcOffsetX = aNewFrame.origin.x - cNewFrame.origin.x
        #expect(abs(savedAcOffsetX - expectedAcOffsetX) <= 4)
    }

    // MARK: - handleWindowAnchorSatelliteRaise

    @Test("Case C: clicking a satellite updates activeSatellitePerWindowAnchor")
    func raiseSatelliteUpdatesActive() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 300, width: 200, height: 200), title: "C")
        register([a, b, c])

        // Two satellites of A; C is the active one to start.
        state.windowAnchorSatellites[a.cgWindowID] = [b.cgWindowID, c.cgWindowID]
        state.savedWindowPairFrames[a.cgWindowID] = [
            b.cgWindowID: AppState.SatellitePairFrames(
                anchor: a.frame, satellite: b.frame,
                screenFrame: a.screenFrame, visibleFrame: a.visibleFrame
            ),
            c.cgWindowID: AppState.SatellitePairFrames(
                anchor: a.frame, satellite: c.frame,
                screenFrame: a.screenFrame, visibleFrame: a.visibleFrame
            ),
        ]
        state.activeSatellitePerWindowAnchor[a.cgWindowID] = c.cgWindowID

        // Click on B → switch active to B.
        state.handleWindowAnchorSatelliteRaise(focusedID: b.cgWindowID)

        #expect(state.activeSatellitePerWindowAnchor[a.cgWindowID] == b.cgWindowID)
    }

    @Test("Case C: re-clicking the same satellite is idempotent — active stays the same and no restore is needed")
    func raiseSameSatelliteIsIdempotent() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        register([a, b])

        state.windowAnchorSatellites[a.cgWindowID] = [b.cgWindowID]
        state.savedWindowPairFrames[a.cgWindowID] = [
            b.cgWindowID: AppState.SatellitePairFrames(
                anchor: a.frame, satellite: b.frame,
                screenFrame: a.screenFrame, visibleFrame: a.visibleFrame
            )
        ]
        state.activeSatellitePerWindowAnchor[a.cgWindowID] = b.cgWindowID

        state.handleWindowAnchorSatelliteRaise(focusedID: b.cgWindowID)

        #expect(state.activeSatellitePerWindowAnchor[a.cgWindowID] == b.cgWindowID)
    }

    @Test("Case D: clicking the anchor picks the frontmost satellite as active")
    func raiseAnchorPicksFrontmostSatellite() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        register([a, b])

        state.windowAnchorSatellites[a.cgWindowID] = [b.cgWindowID]
        state.savedWindowPairFrames[a.cgWindowID] = [
            b.cgWindowID: AppState.SatellitePairFrames(
                anchor: a.frame, satellite: b.frame,
                screenFrame: a.screenFrame, visibleFrame: a.visibleFrame
            )
        ]

        state.handleWindowAnchorSatelliteRaise(focusedID: a.cgWindowID)

        // With only one satellite, it must be picked as active.
        #expect(state.activeSatellitePerWindowAnchor[a.cgWindowID] == b.cgWindowID)
    }

    @Test("handleWindowAnchorSatelliteRaise is a no-op when nothing is registered")
    func raiseWithNoRegistrationsIsNoOp() {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        register([a])
        state.handleWindowAnchorSatelliteRaise(focusedID: a.cgWindowID)
        #expect(state.activeSatellitePerWindowAnchor.isEmpty)
        #expect(state.windowAnchorSatellites.isEmpty)
    }

    // MARK: - removeDestroyedWindowFromWindowAnchorPairs

    @Test("destroying the anchor clears all of its satellites and saved frames")
    func destroyAnchorClearsEverything() {
        let anchor: CGWindowID = 100
        let satA: CGWindowID = 101
        let satB: CGWindowID = 102
        state.windowAnchorSatellites[anchor] = [satA, satB]
        state.savedWindowPairFrames[anchor] = [satA: zeroFrames(), satB: zeroFrames()]
        state.activeSatellitePerWindowAnchor[anchor] = satA

        state.removeDestroyedWindowFromWindowAnchorPairs(anchor)

        #expect(state.windowAnchorSatellites[anchor] == nil)
        #expect(state.savedWindowPairFrames[anchor] == nil)
        #expect(state.activeSatellitePerWindowAnchor[anchor] == nil)
    }

    @Test("destroying one satellite removes it from the anchor but leaves the other satellites in place")
    func destroySatelliteKeepsOthers() {
        let anchor: CGWindowID = 100
        let satA: CGWindowID = 101
        let satB: CGWindowID = 102
        state.windowAnchorSatellites[anchor] = [satA, satB]
        state.savedWindowPairFrames[anchor] = [satA: zeroFrames(), satB: zeroFrames()]
        state.activeSatellitePerWindowAnchor[anchor] = satA

        state.removeDestroyedWindowFromWindowAnchorPairs(satA)

        #expect(state.windowAnchorSatellites[anchor] == [satB])
        #expect(state.savedWindowPairFrames[anchor]?[satA] == nil)
        #expect(state.savedWindowPairFrames[anchor]?[satB] != nil)
        // The active satellite was the destroyed one → cleared.
        #expect(state.activeSatellitePerWindowAnchor[anchor] == nil)
    }

    @Test("destroying the last satellite also removes the anchor entry itself")
    func destroyLastSatelliteRemovesAnchor() {
        let anchor: CGWindowID = 100
        let satA: CGWindowID = 101
        state.windowAnchorSatellites[anchor] = [satA]
        state.savedWindowPairFrames[anchor] = [satA: zeroFrames()]

        state.removeDestroyedWindowFromWindowAnchorPairs(satA)

        #expect(state.windowAnchorSatellites[anchor] == nil)
        #expect(state.savedWindowPairFrames[anchor] == nil)
    }

    // MARK: - unlinkWindowAnchorPair

    @Test("unlinkWindowAnchorPair removes only the targeted single link")
    func unlinkRemovesSingleSatellite() {
        let anchor: CGWindowID = 100
        let satA: CGWindowID = 101
        let satB: CGWindowID = 102
        state.windowAnchorSatellites[anchor] = [satA, satB]
        state.savedWindowPairFrames[anchor] = [satA: zeroFrames(), satB: zeroFrames()]
        state.activeSatellitePerWindowAnchor[anchor] = satA

        state.unlinkWindowAnchorPair(windowA: anchor, windowB: satA)

        #expect(state.windowAnchorSatellites[anchor] == [satB])
        #expect(state.savedWindowPairFrames[anchor]?[satA] == nil)
        #expect(state.savedWindowPairFrames[anchor]?[satB] != nil)
        #expect(state.activeSatellitePerWindowAnchor[anchor] == nil)
    }

    @Test("unlinkWindowAnchorPair works regardless of argument order")
    func unlinkWorksRegardlessOfArgumentOrder() {
        let anchor: CGWindowID = 100
        let sat: CGWindowID = 101
        state.windowAnchorSatellites[anchor] = [sat]
        state.savedWindowPairFrames[anchor] = [sat: zeroFrames()]

        state.unlinkWindowAnchorPair(windowA: sat, windowB: anchor)

        #expect(state.windowAnchorSatellites[anchor] == nil)
    }

    // MARK: - isSatellitePair / candidate suppression

    @Test("isSatellitePair returns true for a pair linked via the window-anchor mechanism")
    func isSatellitePairDetectsWindowAnchor() {
        let anchor: CGWindowID = 100
        let sat: CGWindowID = 101
        state.windowAnchorSatellites[anchor] = [sat]
        #expect(state.isSatellitePair(anchor, sat) == true)
        #expect(state.isSatellitePair(sat, anchor) == true)
        #expect(state.isSatellitePair(anchor, 999) == false)
        #expect(state.isSatellitePair(999, sat) == false)
    }

    @Test("processManuallyMovedWindows re-validates existing pendings: a pair already in the same primary group does not survive the merge")
    func processManuallyMovedDropsStaleSameGroupPending() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        register([a, b])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        // A-B already in the same primary group AND a stale pending entry
        // for the same pair (mimics the carry-over the user observed: drag
        // moves A, follower B catches up, settle pass runs, and the older
        // pending must be dropped).
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        state.pendingGroupCandidates = [abAdj]
        // Prime the move-detection state so processManuallyMovedWindows
        // believes a manual move just settled. Accessibility is granted in
        // the test process so the early-exit guard passes.
        state.manuallyMovedWindowIDs = [a.cgWindowID]
        state.accessibilityGranted = true

        state.processManuallyMovedWindows()

        let stillPending = state.pendingGroupCandidates.contains { adj in
            Set([adj.windowA, adj.windowB]) == Set([a.cgWindowID, b.cgWindowID])
        }
        #expect(stillPending == false)
    }

    @Test("shouldSuppressGroupingCandidate: two windows in different primary groups suppress the cross-group form-group candidate")
    func suppressesCandidateBetweenTwoDistinctGroups() throws {
        // Mirrors the user-reported bug: apply preset to (WinA, WinB), then
        // (WinC, WinD); drag WinC down so it's now edge-adjacent to WinB.
        // Both WinB and WinC are already in (different) primary groups —
        // surfacing a "form group" badge between them would invite a
        // cross-group merge that is almost never wanted.
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 300, width: 200, height: 200), title: "C")
        let d = makeRealWindow(CGRect(x: 200, y: 300, width: 200, height: 200), title: "D")
        register([a, b, c, d])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        let cdAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: c.cgWindowID, frameA: c.frame, b: d.cgWindowID, frameB: d.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        injectPrimaryGroup(
            members: [c.cgWindowID, d.cgWindowID],
            adjacencies: [cdAdj],
            frames: [c.cgWindowID: c.frame, d.cgWindowID: d.frame]
        )
        // Synthesize the cross-group adjacency the drag would expose
        // (WinB top edge ↔ WinD bottom edge, since the y-stack puts D above B).
        let crossAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: b.cgWindowID, frameA: b.frame, b: d.cgWindowID, frameB: d.frame
        ))
        #expect(state.shouldSuppressGroupingCandidate(crossAdj) == true)
    }

    @Test("shouldSuppressGroupingCandidate: an ungrouped window adjacent to a grouped window is NOT suppressed (lets the user join the group)")
    func keepsCandidateBetweenUngroupedAndGroupedWindow() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let stray = makeRealWindow(CGRect(x: 400, y: 100, width: 200, height: 200), title: "Stray")
        register([a, b, stray])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        // Stray is ungrouped and now adjacent to B's right edge — must
        // remain a candidate so the user can join Stray to the A-B group.
        let bStrayAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: b.cgWindowID, frameA: b.frame, b: stray.cgWindowID, frameB: stray.frame
        ))
        #expect(state.shouldSuppressGroupingCandidate(bStrayAdj) == false)
    }

    // MARK: - windowsConnectedToFrontmost

    @Test("windowsConnectedToFrontmost: empty set when there is no frontmost window")
    func connectedSetEmptyWithoutFrontmost() {
        #expect(state.windowsConnectedToFrontmost(frontmostWID: nil).isEmpty)
    }

    @Test("windowsConnectedToFrontmost: frontmost in primary group reaches every other member of that group")
    func connectedSetIncludesPrimaryGroupMembers() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        register([a, b])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        let connected = state.windowsConnectedToFrontmost(frontmostWID: a.cgWindowID)
        #expect(connected.contains(a.cgWindowID))
        #expect(connected.contains(b.cgWindowID))
    }

    @Test("windowsConnectedToFrontmost: an unrelated background group is NOT reachable from the frontmost window")
    func connectedSetExcludesUnrelatedGroup() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 400, width: 200, height: 200), title: "C")
        let d = makeRealWindow(CGRect(x: 200, y: 400, width: 200, height: 200), title: "D")
        register([a, b, c, d])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        let cdAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: c.cgWindowID, frameA: c.frame, b: d.cgWindowID, frameB: d.frame
        ))
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        injectPrimaryGroup(
            members: [c.cgWindowID, d.cgWindowID],
            adjacencies: [cdAdj],
            frames: [c.cgWindowID: c.frame, d.cgWindowID: d.frame]
        )
        let connectedFromC = state.windowsConnectedToFrontmost(frontmostWID: c.cgWindowID)
        #expect(connectedFromC.contains(c.cgWindowID))
        #expect(connectedFromC.contains(d.cgWindowID))
        #expect(!connectedFromC.contains(a.cgWindowID))
        #expect(!connectedFromC.contains(b.cgWindowID))
    }

    @Test("windowsConnectedToFrontmost: window-anchor satellites are reachable transitively from the anchor")
    func connectedSetTraversesWindowAnchorPool() {
        let anchor: CGWindowID = 100
        let satA: CGWindowID = 101
        let satB: CGWindowID = 102
        state.windowAnchorSatellites[anchor] = [satA, satB]
        let connectedFromAnchor = state.windowsConnectedToFrontmost(frontmostWID: anchor)
        #expect(connectedFromAnchor == [anchor, satA, satB])
        // From a satellite: anchor and sibling satellite both reachable.
        let connectedFromSat = state.windowsConnectedToFrontmost(frontmostWID: satA)
        #expect(connectedFromSat == [anchor, satA, satB])
    }

    @Test("registerWindowAnchorPair drops any stale pending candidate for the same anchor-satellite pair")
    func registerWindowAnchorPairDropsStalePendingCandidates() throws {
        let a = makeRealWindow(CGRect(x: 0, y: 100, width: 200, height: 200), title: "A")
        let b = makeRealWindow(CGRect(x: 200, y: 100, width: 200, height: 200), title: "B")
        let c = makeRealWindow(CGRect(x: 0, y: 300, width: 200, height: 200), title: "C")
        register([a, b, c])
        let abAdj = try #require(WindowAdjacencyDetector.adjacency(
            a: a.cgWindowID, frameA: a.frame, b: b.cgWindowID, frameB: b.frame
        ))
        // Set up: A-B in primary group, AND a stale pending candidate for A-B
        // (mimics the case where the candidate badge was already in flight
        // when the preset apply triggers).
        injectPrimaryGroup(
            members: [a.cgWindowID, b.cgWindowID],
            adjacencies: [abAdj],
            frames: [a.cgWindowID: a.frame, b.cgWindowID: b.frame]
        )
        state.pendingGroupCandidates = [abAdj]

        state.registerWindowAnchorPair(anchorWID: a.cgWindowID, partnerWID: c.cgWindowID)

        // After registration B is a satellite of A; the stale A-B pending
        // candidate must be gone (otherwise the "form group" badge resurfaces).
        let stillPendingForAB = state.pendingGroupCandidates.contains { adj in
            Set([adj.windowA, adj.windowB]) == Set([a.cgWindowID, b.cgWindowID])
        }
        #expect(stillPendingForAB == false)
    }
}
