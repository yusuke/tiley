import AppKit

final class WindowManager {
    private let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    func captureFocusedWindow(preferredPID: pid_t? = nil) -> WindowTarget? {
        try? accessibilityService.focusedWindowTarget(preferredPID: preferredPID)
    }

    func move(target: WindowTarget, to frame: CGRect) throws {
        try accessibilityService.setFrame(frame, on: target.screenFrame, for: target.windowElement)
    }
}

extension NSScreen {
    static func screen(containing frame: CGRect) -> NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(frame) }
    }
}
