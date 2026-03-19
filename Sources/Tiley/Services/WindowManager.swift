import AppKit

final class WindowManager {
    private let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    func captureFocusedWindow(preferredPID: pid_t? = nil) -> WindowTarget? {
        try? accessibilityService.focusedWindowTarget(preferredPID: preferredPID)
    }

    func captureAllWindows() -> [WindowTarget] {
        accessibilityService.allWindowTargets()
    }

    @discardableResult
    func move(target: WindowTarget, to frame: CGRect) throws -> Bool {
        try accessibilityService.setFrame(frame, on: target.screenFrame, for: target.windowElement)
    }

    @discardableResult
    func move(target: WindowTarget, to frame: CGRect, onScreenFrame screenFrame: CGRect) throws -> Bool {
        try accessibilityService.setFrame(frame, on: screenFrame, for: target.windowElement)
    }

    /// After a move/resize, always raises the window to the front.
    func raiseWindow(target: WindowTarget) {
        accessibilityService.raiseWindow(target.windowElement)
    }

}

extension NSScreen {
    static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) }
    }

    /// Stable display identifier suitable for use as a dictionary key.
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
