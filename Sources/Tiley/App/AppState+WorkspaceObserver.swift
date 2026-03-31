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
                    self?.lastTargetPID = app.processIdentifier
                    self?.refreshAccessibilityState()
                    self?.updateStatusMenu()
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
