import AppKit

extension AppState {

    // MARK: - Move to Space

    /// Shows the space picker for `target`, listing the desktops of the
    /// display the window is on.
    func showSpacePicker(for target: WindowTarget) {
        spacePickerController?.cancel()

        guard target.cgWindowID != 0 else {
            debugLog("showSpacePicker: no CG window ID for \(target.appName)")
            NSSound.beep()
            return
        }
        let screen = NSScreen.screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? NSScreen.main
        guard let screen, let display = SpaceMover.spaces(forDisplayID: screen.displayID) else {
            debugLog("showSpacePicker: spaces unavailable")
            NSSound.beep()
            return
        }

        let windowSpace = SpaceMover.spaceID(ofWindow: target.cgWindowID) ?? display.currentSpaceID
        let desktops = display.desktops
        let appsBySpace = SpaceMover.appsBySpace(spaceIDs: Set(desktops.map(\.id)))
        let items = desktops.map { space in
            SpacePickerItem(
                id: space.id,
                desktopNumber: space.index,
                isWindowSpace: space.id == windowSpace,
                appIcons: (appsBySpace[space.id] ?? []).compactMap(\.icon)
            )
        }

        let warning: String? = SpaceMover.canSwitchSpaces ? nil : NSLocalizedString(
            "Turn on “Move left a space” and “Move right a space” in System Settings › Keyboard › Keyboard Shortcuts › Mission Control to move windows between spaces.",
            comment: "Space picker warning when the Mission Control shortcuts are disabled"
        )

        let content = SpacePickerContent(
            appIcon: NSRunningApplication(processIdentifier: target.processIdentifier)?.icon,
            windowLabel: target.windowTitle.flatMap { $0.isEmpty ? nil : "\(target.appName) — \($0)" } ?? target.appName,
            displayName: screen.localizedName,
            items: items,
            warning: warning
        )

        let displayID = screen.displayID
        let controller = SpacePickerController(
            content: content,
            on: screen,
            onPick: { [weak self] spaceID in
                self?.spacePickerController = nil
                self?.moveWindow(target, toSpace: spaceID, displayID: displayID)
            },
            onCancel: { [weak self] in
                self?.spacePickerController = nil
            }
        )
        spacePickerController = controller
        controller.show()
    }

    /// Sends `target` to the given space; the user follows it there.
    func moveWindow(_ target: WindowTarget, toSpace spaceID: UInt64, displayID: CGDirectDisplayID) {
        Task { @MainActor in
            // Let the picker's key-up and fade-out finish before driving input.
            try? await Task.sleep(nanoseconds: 120_000_000)
            let result = await SpaceMover.moveWindow(
                windowID: target.cgWindowID,
                pid: target.processIdentifier,
                windowElement: target.windowElement,
                toSpace: spaceID,
                displayID: displayID
            )
            if case .failure(let error) = result {
                debugLog("moveWindow(toSpace:) failed: \(error)")
                NSSound.beep()
            }
        }
    }
}
