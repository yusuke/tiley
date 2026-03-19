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
        guard let window = target.windowElement else { return false }
        let constrained = try accessibilityService.setFrame(frame, on: target.screenFrame, for: window)
        scheduleFrameVerification(frame: frame, screenFrame: target.screenFrame, window: window)
        return constrained
    }

    @discardableResult
    func move(target: WindowTarget, to frame: CGRect, onScreenFrame screenFrame: CGRect) throws -> Bool {
        guard let window = target.windowElement else { return false }
        let constrained = try accessibilityService.setFrame(frame, on: screenFrame, for: window)
        scheduleFrameVerification(frame: frame, screenFrame: screenFrame, window: window)
        return constrained
    }

    /// After a move/resize, always raises the window to the front.
    func raiseWindow(target: WindowTarget) {
        guard let window = target.windowElement else { return }
        accessibilityService.raiseWindow(window)
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
