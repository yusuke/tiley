import AppKit

/// A window the user pinned to all Spaces. It lives on one space at a time;
/// Tiley carries it to whichever desktop its display switches to.
struct PinnedWindow {
    let windowID: CGWindowID
    let pid: pid_t
    let windowElement: AXUIElement?
    let appName: String
    /// The space a follow last failed to bring the window to. Not retried
    /// until the user switches somewhere else, so a stuck window can't loop.
    var failedSpaceID: UInt64?
}

extension AppState {

    // MARK: - Pin to All Spaces
    //
    // macOS no longer lets an app mark another app's window as "on all
    // desktops" (the sticky tag and SLSAddWindowsToSpaces are silently ignored
    // for foreign windows), so a pinned window follows the user instead:
    //
    // - Keyboard switches (the system "Move left/right a space" and "Switch to
    //   Desktop N" shortcuts) are swallowed by an event tap and replayed while
    //   Tiley holds the pinned window, so it rides along in the same animation.
    // - Any other switch (trackpad swipe, Mission Control, Dock) leaves the
    //   window behind; after the switch settles, Tiley fetches it with the
    //   Move to Space drag and gives focus back to the app that had it.

    /// Pins the window, or unpins it when it is already pinned.
    func togglePinToAllSpaces(_ target: WindowTarget) {
        guard target.cgWindowID != 0 else {
            debugLog("togglePinToAllSpaces: no CG window ID for \(target.appName)")
            NSSound.beep()
            return
        }
        let pinned: Bool
        if pinnedWindows.removeValue(forKey: target.cgWindowID) != nil {
            pinned = false
        } else {
            pinnedWindows[target.cgWindowID] = PinnedWindow(
                windowID: target.cgWindowID,
                pid: target.processIdentifier,
                windowElement: target.windowElement,
                appName: target.appName
            )
            pinned = true
        }
        debugLog("togglePinToAllSpaces: \(target.appName) wid=\(target.cgWindowID) pinned=\(pinned) total=\(pinnedWindows.count)")
        updateSpaceSwitchTap()
        showPinFeedback(pinned: pinned, target: target)
    }

    /// Unpins the given windows (from the picker's pinned list).
    func unpinWindows(_ windowIDs: [CGWindowID]) {
        let removed = windowIDs.compactMap { pinnedWindows.removeValue(forKey: $0) }
        guard !removed.isEmpty else { return }
        debugLog("unpinWindows: \(removed.map { "\($0.appName) wid=\($0.windowID)" }) total=\(pinnedWindows.count)")
        updateSpaceSwitchTap()

        pinHUD?.dismiss()
        let subtitle = removed.count == 1
            ? pinnedWindowLabel(removed[0])
            : String(format: NSLocalizedString("%d windows", comment: "HUD subtitle when several windows were unpinned"), removed.count)
        let hud = PinHUDController(
            title: NSLocalizedString("Unpinned from All Spaces", comment: "HUD shown when a window is unpinned from all spaces"),
            subtitle: subtitle,
            systemImage: "pin.slash",
            icon: removed.count == 1 ? NSRunningApplication(processIdentifier: removed[0].pid)?.icon : nil
        )
        pinHUD = hud
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main {
            hud.show(on: screen)
        }
    }

    /// Pinned windows other than `windowID`, for the picker's list. Windows
    /// that have closed are dropped.
    func pinnedWindowItems(excluding windowID: CGWindowID) -> [PinnedWindowItem] {
        for id in pinnedWindows.keys where !windowExists(id) {
            pinnedWindows.removeValue(forKey: id)
        }
        updateSpaceSwitchTap()
        return pinnedWindows.values
            .filter { $0.windowID != windowID }
            .sorted { $0.windowID < $1.windowID }
            .map { pinned in
                PinnedWindowItem(
                    id: pinned.windowID,
                    appIcon: NSRunningApplication(processIdentifier: pinned.pid)?.icon,
                    label: pinnedWindowLabel(pinned)
                )
            }
    }

    /// "App — window title", or just the app name when the title is unknown.
    private func pinnedWindowLabel(_ pinned: PinnedWindow) -> String {
        var value: CFTypeRef?
        if let element = pinned.windowElement,
           AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &value) == .success,
           let title = value as? String, !title.isEmpty {
            return "\(pinned.appName) — \(title)"
        }
        return pinned.appName
    }

    func unpinAllWindows() {
        pinnedWindows.removeAll()
        pinFollowTask?.cancel()
        pinFollowTask = nil
        updateSpaceSwitchTap()
    }

    private func showPinFeedback(pinned: Bool, target: WindowTarget) {
        let title = pinned
            ? NSLocalizedString("Pinned to All Spaces", comment: "HUD shown when a window is pinned to all spaces")
            : NSLocalizedString("Unpinned from All Spaces", comment: "HUD shown when a window is unpinned from all spaces")
        let screen = NSScreen.screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? NSScreen.main
        pinHUD?.dismiss()
        let hud = PinHUDController(
            title: title,
            subtitle: target.windowTitle.flatMap { $0.isEmpty ? nil : "\(target.appName) — \($0)" } ?? target.appName,
            systemImage: pinned ? "pin.fill" : "pin.slash",
            icon: NSRunningApplication(processIdentifier: target.processIdentifier)?.icon
        )
        pinHUD = hud
        if let screen { hud.show(on: screen) }
    }

    // MARK: Keyboard switches

    /// Installs the space-switch event tap while anything is pinned, and
    /// removes it once nothing is.
    func updateSpaceSwitchTap() {
        if pinnedWindows.isEmpty {
            uninstallSpaceSwitchTap()
        } else {
            spaceSwitchShortcuts = SpaceMover.activeSwitchShortcuts()
            installSpaceSwitchTap()
        }
    }

    private func installSpaceSwitchTap() {
        guard spaceSwitchEventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let appState = Unmanaged<AppState>.fromOpaque(refcon).takeUnretainedValue()
                // The tap's run-loop source is on the main run loop.
                let swallow = MainActor.assumeIsolated {
                    appState.handleSpaceSwitchTapEvent(type: type, event: event)
                }
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: refcon
        )
        guard let tap else {
            debugLog("PinnedWindows: CGEventTap creation failed (accessibility permission?)")
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        spaceSwitchEventTap = tap
        spaceSwitchEventTapSource = source
        debugLog("PinnedWindows: space-switch tap installed (\(spaceSwitchShortcuts.count) shortcuts)")
    }

    private func uninstallSpaceSwitchTap() {
        if let tap = spaceSwitchEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = spaceSwitchEventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        spaceSwitchEventTap = nil
        spaceSwitchEventTapSource = nil
    }

    /// Returns true to swallow the event. Must decide quickly: the system
    /// disables taps that stall.
    private func handleSpaceSwitchTapEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = spaceSwitchEventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type == .keyDown,
              event.getIntegerValueField(.eventSourceUserData) != SpaceMover.syntheticEventMarker,
              event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
              !spaceMoveInProgress else { return false }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard let match = spaceSwitchShortcuts.first(where: { $0.shortcut.matches(keyCode: keyCode, flags: event.flags) }),
              let plan = carryPlan(for: match.kind) else { return false }

        debugLog("PinnedWindows: carrying wid=\(plan.windowID) through \(match.kind)")
        spaceMoveInProgress = true
        Task { @MainActor in
            let result = await SpaceMover.carryWindow(
                windowID: plan.windowID,
                pid: plan.pid,
                windowElement: plan.windowElement,
                pressing: match.shortcut,
                displayID: plan.displayID
            )
            if case .failure(let error) = result {
                debugLog("PinnedWindows: carry failed: \(error)")
            }
            spaceMoveInProgress = false
            // Other pinned windows, or one the carry dropped, catch up now.
            schedulePinnedWindowFollow()
        }
        return true
    }

    /// The pinned window to carry for a switch, or nil to let the key through.
    private func carryPlan(for kind: SpaceSwitchKind) -> (windowID: CGWindowID, pid: pid_t, windowElement: AXUIElement?, displayID: CGDirectDisplayID)? {
        let displayID: CGDirectDisplayID
        let destination: SpaceInfo
        switch kind {
        case .step(let right):
            // The switch applies to the display under the cursor.
            let mouse = NSEvent.mouseLocation
            guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main,
                  let display = SpaceMover.spaces(forDisplayID: screen.displayID),
                  let index = display.spaces.firstIndex(where: { $0.id == display.currentSpaceID }) else { return nil }
            let next = index + (right ? 1 : -1)
            guard display.spaces.indices.contains(next) else { return nil } // already at the end
            displayID = screen.displayID
            destination = display.spaces[next]
        case .desktop(let number):
            let desktops = AccessibilityService.buildSpaceMap().spaceList.filter { !$0.isFullScreen }
            guard desktops.indices.contains(number - 1) else { return nil }
            let target = desktops[number - 1]
            guard let screen = NSScreen.screens.first(where: {
                SpaceMover.spaces(forDisplayID: $0.displayID)?.spaces.contains { $0.id == target.id } == true
            }) else { return nil }
            displayID = screen.displayID
            destination = target
        }
        // A window can't be dragged into a full-screen space.
        guard !destination.isFullScreen,
              let current = SpaceMover.spaces(forDisplayID: displayID)?.currentSpaceID,
              destination.id != current else { return nil }

        let onCurrent = pinnedWindows.values
            .filter { SpaceMover.spaceID(ofWindow: $0.windowID) == current && isFollowable($0) }
            .sorted { $0.windowID < $1.windowID }
        guard let pinned = onCurrent.first else { return nil }
        return (pinned.windowID, pinned.pid, pinned.windowElement, displayID)
    }

    // MARK: Catching up after other switches

    /// Called on every active-space change. Waits for switching to settle,
    /// then brings pinned windows to their display's current desktop.
    func schedulePinnedWindowFollow() {
        guard !pinnedWindows.isEmpty, !spaceMoveInProgress else { return }
        pinFollowTask?.cancel()
        pinFollowTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, !self.spaceMoveInProgress else { return }
            self.pinFollowTask = nil
            await self.followPinnedWindows()
        }
    }

    private func followPinnedWindows() async {
        spaceMoveInProgress = true

        // The app the user switched to, which should keep focus afterwards.
        let frontmost = NSWorkspace.shared.frontmostApplication
        var movedPIDs: Set<pid_t> = []

        for windowID in pinnedWindows.keys.sorted() {
            guard var pinned = pinnedWindows[windowID] else { continue }
            guard windowExists(windowID) else {
                debugLog("PinnedWindows: wid=\(windowID) (\(pinned.appName)) is gone; unpinning")
                pinnedWindows.removeValue(forKey: windowID)
                continue
            }
            guard isFollowable(pinned),
                  let windowSpace = SpaceMover.spaceID(ofWindow: windowID),
                  let (displayID, display) = displaySpaces(containing: windowSpace),
                  let current = display.currentSpaceID,
                  current != windowSpace,
                  display.spaces.first(where: { $0.id == current })?.isFullScreen == false,
                  pinned.failedSpaceID != current else { continue }

            debugLog("PinnedWindows: following wid=\(windowID) \(windowSpace) → \(current)")
            let result = await SpaceMover.moveWindow(
                windowID: windowID,
                pid: pinned.pid,
                windowElement: pinned.windowElement,
                toSpace: current,
                displayID: displayID
            )
            switch result {
            case .success:
                pinned.failedSpaceID = nil
                movedPIDs.insert(pinned.pid)
            case .failure(let error):
                debugLog("PinnedWindows: follow failed for wid=\(windowID): \(error)")
                pinned.failedSpaceID = current
            }
            if pinnedWindows[windowID] != nil { pinnedWindows[windowID] = pinned }
        }

        if !movedPIDs.isEmpty, let frontmost, !movedPIDs.contains(frontmost.processIdentifier) {
            frontmost.activate()
        }
        spaceMoveInProgress = false
        updateSpaceSwitchTap()
        // Switches the user made while windows were being fetched were
        // ignored; check once more. A no-op when everything is in place.
        if !movedPIDs.isEmpty { schedulePinnedWindowFollow() }
    }

    /// Minimized windows and hidden apps stay where they are.
    private func isFollowable(_ pinned: PinnedWindow) -> Bool {
        if NSRunningApplication(processIdentifier: pinned.pid)?.isHidden == true { return false }
        if let element = pinned.windowElement {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXMinimizedAttribute as CFString, &value) == .success,
               (value as? Bool) == true {
                return false
            }
        }
        return true
    }

    private func windowExists(_ windowID: CGWindowID) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]] else { return false }
        return list.contains { ($0[kCGWindowNumber as String] as? CGWindowID) == windowID }
    }

    private func displaySpaces(containing spaceID: UInt64) -> (CGDirectDisplayID, DisplaySpaces)? {
        for screen in NSScreen.screens {
            if let display = SpaceMover.spaces(forDisplayID: screen.displayID),
               display.spaces.contains(where: { $0.id == spaceID }) {
                return (screen.displayID, display)
            }
        }
        return nil
    }
}
