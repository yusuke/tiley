import AppKit

extension AppState {
    func installWorkspaceObserver() {
        workspaceObserverTask = Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.didActivateApplicationNotification
            )
            for await notification in notifications {
                guard !Task.isCancelled else { break }
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.processIdentifier != getpid() else {
                    continue
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.lastTargetPID = app.processIdentifier
                    // No cache realign here: nothing renders the cache while
                    // the overlay is closed, and `toggleOverlay` realigns it
                    // against the live z-order the moment it opens. Doing it
                    // per activation was a WindowServer query + full re-sort
                    // whose result was always discarded.
                    self.refreshAccessibilityState()
                    self.updateStatusMenu()
                    self.scheduleWindowListCacheRefresh()
                    // Query AX for the actually-focused window and trigger the
                    // linkage only if that window is a group member.
                    // Using the first entry of availableWindowTargets can pick
                    // the wrong window (e.g. a different group member) when
                    // the cache is stale.
                    //
                    // The raise check is **deferred** by ~200 ms because the
                    // WindowServer's Z-order update lags behind the
                    // `didActivateApplicationNotification` delivery. On
                    // Cmd+Tab back to an app whose other group members were
                    // behind another app's window, macOS raises those members
                    // to the front over the next few frames. Querying
                    // immediately can see a stale order where a non-member
                    // still occludes a member, triggering an unnecessary
                    // AXRaise dance and visible flicker. Re-evaluating after
                    // a short delay lets the OS-level reorder settle so the
                    // `areAllOtherMembersVisible` short-circuit fires when it
                    // should.
                    let targetPID = app.processIdentifier
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        guard let self else { return }
                        // No groups → nothing to link. Check this *before*
                        // `resolveFocusedWindowID`, which is a synchronous
                        // Accessibility round-trip into the app that was just
                        // activated (and may be busy or hung).
                        guard !self.groupIndexByWindow.isEmpty else { return }
                        guard let focusedCGID = self.resolveFocusedWindowID(for: targetPID),
                              self.groupIndexByWindow[focusedCGID] != nil else { return }
                        // Re-confirm the app is still frontmost — user may
                        // have switched away during the delay.
                        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID else {
                            return
                        }
                        self.handleGroupMemberRaised(id: focusedCGID)
                    }
                    // Refresh badge visibility on front/back transitions.
                    // Z-order changes propagate with a slight delay, so
                    // re-evaluate 80 ms later.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
                        self?.refreshBadgeOverlays()
                    }
                }
            }
        }

        appActivationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didBecomeActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleAppDidBecomeActive()
                }
            }
        }

        appDeactivationTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didResignActiveNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleAppDidResignActive()
                }
            }
        }

        screenChangeTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.handleScreenConfigurationChange()
                }
            }
        }

        Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: Notification.Name("NSWorkspaceDidChangeDesktopImageNotification")
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    self?.desktopImageVersion += 1
                    // Redraw the badge icon tint color to match the light/dark appearance
                    self?.applyStatusItemIcon()
                }
            }
        }

        // On Space changes, directly query live Space IDs and dissolve any
        // group that now spans multiple Spaces. Doesn't wait for the window
        // list cache refresh, which can skip during Mission Control.
        Task { [weak self] in
            let notifications = NSWorkspace.shared.notificationCenter.notifications(
                named: NSWorkspace.activeSpaceDidChangeNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { [weak self] in
                    // Space layout just changed — drop the short-lived
                    // window→Space cache so the upcoming refresh re-queries.
                    AccessibilityService.invalidateWindowSpaceCache()
                    self?.dissolveGroupsWithSplitSpaces()
                    self?.scheduleWindowListCacheRefresh()
                }
            }
        }

        // Listen for app launches and terminations to pre-cache the window list.
        appLaunchTerminationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    let notifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didLaunchApplicationNotification
                    )
                    for await _ in notifications {
                        guard !Task.isCancelled else { break }
                        // Delay slightly so the new app's window has time to appear.
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { break }
                        await MainActor.run { [weak self] in
                            self?.scheduleWindowListCacheRefresh()
                        }
                    }
                }
                group.addTask {
                    let notifications = NSWorkspace.shared.notificationCenter.notifications(
                        named: NSWorkspace.didTerminateApplicationNotification
                    )
                    for await notification in notifications {
                        guard !Task.isCancelled else { break }
                        let terminatedPID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                            as? NSRunningApplication)?.processIdentifier
                        await MainActor.run { [weak self] in
                            if let terminatedPID {
                                self?.invalidateAppInfoCache(forPID: terminatedPID)
                            }
                            self?.scheduleWindowListCacheRefresh()
                        }
                    }
                }
            }
        }

        // Perform an initial cache so the window list is ready on first open.
        scheduleWindowListCacheRefresh()
    }

    func handleScreenConfigurationChange() {
        // Re-register display hotkeys so newly connected displays become active
        // and disconnected display hotkeys are cleaned up.
        registerDisplayHotKeys()
        // Drop wallpaper entries cached for screens that may have disconnected.
        invalidateWallpaperCache()
        // Also advance the wallpaper version so the per-screen
        // DesktopPictureInfo cache in MainWindowView (keyed on this version)
        // is rebuilt for the new screen arrangement.
        desktopImageVersion += 1
        // The preview window is sized to a specific screen; drop it so the
        // next preview is built against the new arrangement.
        releasePreviewOverlay()
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        openAllScreenWindows()
    }

    func handleAppDidResignActive() {
        guard !isSwitchingActivationPolicy else {
            debugLog("didResignActive ignored: isSwitchingActivationPolicy")
            return
        }
        guard !isRecreatingWindows else {
            debugLog("didResignActive ignored: isRecreatingWindows")
            return
        }
        // Don't hide windows if the permissions or settings window is open —
        // the user may be switching to System Settings or another app briefly.
        guard permissionsWindowController == nil else { return }
        guard settingsWindowController == nil else { return }
        if isShowingLayoutGrid {
            debugLog("didResignActive — hiding overlay")
        }
        hidePreviewOverlay()
        hideMainWindow()
    }

    /// Schedules a debounced background refresh of the window list cache.
    /// Multiple rapid calls cancel previous in-flight fetches so only the
    /// latest request completes. The overlay is not affected; when it opens
    /// it will use whatever cache is available at that moment.
    func scheduleWindowListCacheRefresh() {
        // Don't cache while the overlay is visible — refreshAvailableWindows
        // handles the live list and we don't want to interfere.
        guard !isShowingLayoutGrid else { return }
        guard let wm = windowManager else { return }
        // Without accessibility, captureAllWindows returns ([], [], []). Caching
        // that would set `hasWindowListCache = true` with empty data, and after
        // the user grants accessibility `initialLayoutTarget()` would trust the
        // cache and return nil — leaving the sidebar empty ("ウインドウなし").
        guard accessibilityGranted else { return }
        windowListCacheTask?.cancel()
        windowListCacheTask = Task.detached { [weak self] in
            // Small debounce so rapid events (e.g. several apps activating in
            // quick succession) coalesce into a single fetch.
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            // Skip caching while "Show Desktop" or Mission Control is active.
            // During these states windows are pushed off-screen and CG/AX
            // positions diverge, producing an unreliable window list.
            // The last good cache from before the state change is preserved.
            let showDesktop = CGSPrivate.isShowDesktopLikelyActive()
            let missionControl = CGSPrivate.isMissionControlLikelyActive()
            if showDesktop || missionControl {
                debugLog("Window list cache skipped (showDesktop=\(showDesktop) missionControl=\(missionControl))")
                return
            }
            let captured = wm.captureAllWindows(includeOtherSpaces: true)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                guard let self, !self.isShowingLayoutGrid else { return }
                self.cachedWindowTargets = captured.targets
                self.cachedSpaceList = captured.spaceList
                self.cachedActiveSpaceIDs = captured.activeSpaceIDs
                self.hasWindowListCache = true
                debugLog("Window list cache updated: \(captured.targets.count) windows")
                self.dissolveGroupsWithSplitSpaces()
                self.ensureAllAvailableWindowsObservedForManualMove()
            }
        }
    }

    func handleAppDidBecomeActive() {
        guard permissionsWindowController != nil else { return }
        refreshAccessibilityState()
        guard accessibilityGranted else { return }
        dismissPermissionsOnly()
        activeLayoutTarget = initialLayoutTarget()
        // Setting isShowingLayoutGrid = true here mirrors start()'s behavior
        // and is required so refreshAvailableWindows()'s async callback
        // applies the result (it bails out when isShowingLayoutGrid is false).
        isShowingLayoutGrid = true
        openMainWindow()
        // Mirror the start() Phase-2 sidebar bootstrap: populate from cache if
        // available, otherwise show the spinner; then kick off a fresh capture.
        // Without this the sidebar stays "ウインドウなし" after the user grants
        // accessibility and returns to Tiley, since start()'s window-list path
        // was skipped while accessibility was missing.
        if hasWindowListCache {
            realignCacheWithLiveZOrder()
            availableWindowTargets = cachedWindowTargets
            spaceList = cachedSpaceList
            activeSpaceIDs = cachedActiveSpaceIDs
            windowTargetListVersion += 1
            isLoadingWindowList = false
        } else {
            isLoadingWindowList = true
        }
        refreshAvailableWindows(snapToFreshTop: true)
    }
}
