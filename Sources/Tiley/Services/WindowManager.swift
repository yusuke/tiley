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

    /// After a move/resize, raises the window to the front if it is substantially
    /// occluded by other windows of the same application.
    func raiseWindowIfOccluded(target: WindowTarget, newFrame: CGRect, screenFrame: CGRect) {
        // Convert both old and new frames from AppKit coordinates (bottom-left origin)
        // to CG/AX coordinates (top-left origin) for CGWindowListCopyWindowInfo comparison.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        let oldCGFrame = CGRect(
            x: target.frame.minX,
            y: primaryMaxY - target.frame.maxY,
            width: target.frame.width,
            height: target.frame.height
        )
        let newCGFrame = CGRect(
            x: newFrame.minX,
            y: primaryMaxY - newFrame.maxY,
            width: newFrame.width,
            height: newFrame.height
        )
        if accessibilityService.isWindowOccludedBySameApp(
            pid: target.processIdentifier,
            oldFrame: oldCGFrame,
            newFrame: newCGFrame
        ) {
            accessibilityService.raiseWindow(target.windowElement)
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
