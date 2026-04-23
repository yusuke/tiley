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
                    // Immediately realign the existing cache against the live
                    // CG z-order so that, until the debounced background
                    // refresh completes, the sidebar reflects the current
                    // ordering across all apps (not just the newly-frontmost).
                    self.realignCacheWithLiveZOrder()
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
                    for await _ in notifications {
                        guard !Task.isCancelled else { break }
                        await MainActor.run { [weak self] in
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
        guard isShowingLayoutGrid, !isEditingSettings else { return }
        openAllScreenWindows()
    }

    func handleAppDidResignActive() {
        guard !isSwitchingActivationPolicy else { return }
        guard !isRecreatingWindows else { return }
        // Don't hide windows if the permissions or settings window is open —
        // the user may be switching to System Settings or another app briefly.
        guard permissionsWindowController == nil else { return }
        guard settingsWindowController == nil else { return }
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
            }
        }
    }

    func handleAppDidBecomeActive() {
        guard permissionsWindowController != nil else { return }
        refreshAccessibilityState()
        guard accessibilityGranted else { return }
        dismissPermissionsOnly()
        activeLayoutTarget = initialLayoutTarget()
        if let activeLayoutTarget {
            isShowingLayoutGrid = true
            launchMessage = String(
                format: NSLocalizedString("Select a layout region for %@.", comment: "Prompt to select region for app"),
                activeLayoutTarget.appName
            )
        } else {
            launchMessage = NSLocalizedString("Activate the window you want to arrange, then choose Show Layout Grid.", comment: "Prompt to activate target window")
        }
        openMainWindow()
    }
}
