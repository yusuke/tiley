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
        let constrained = try accessibilityService.setFrame(frame, on: target.screenFrame, for: target.windowElement)
        scheduleFrameVerification(frame: frame, screenFrame: target.screenFrame, window: target.windowElement)
        return constrained
    }

    @discardableResult
    func move(target: WindowTarget, to frame: CGRect, onScreenFrame screenFrame: CGRect) throws -> Bool {
        let constrained = try accessibilityService.setFrame(frame, on: screenFrame, for: target.windowElement)
        scheduleFrameVerification(frame: frame, screenFrame: screenFrame, window: target.windowElement)
        return constrained
    }

    /// After a move/resize, always raises the window to the front.
    func raiseWindow(target: WindowTarget) {
        accessibilityService.raiseWindow(target.windowElement)
    }

    /// Schedules a background verify-and-correct pass so that the UI can
    /// dismiss immediately while we keep nudging the window into place.
    private func scheduleFrameVerification(frame: CGRect, screenFrame: CGRect, window: AXUIElement) {
        let service = accessibilityService
        DispatchQueue.global(qos: .userInitiated).async {
            service.verifyAndCorrectFrame(frame, on: screenFrame, for: window)
        }
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
