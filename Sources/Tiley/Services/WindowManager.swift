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
        return try accessibilityService.setFrame(frame, on: target.screenFrame, for: window)
    }

    @discardableResult
    func move(target: WindowTarget, to frame: CGRect, onScreenFrame screenFrame: CGRect) throws -> Bool {
        guard let window = target.windowElement else { return false }
        return try accessibilityService.setFrame(frame, on: screenFrame, for: window)
    }

    /// Moves/resizes a window using the AX API and saves a reproducible
    /// Swift script to `~/tileyScripts/` for debugging.
    func moveViaScript(target: WindowTarget, to frame: CGRect, on screenFrame: CGRect) throws {
        guard let window = target.windowElement else { return }

        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        let axX = Int(frame.minX)
        let axY = Int(primaryMaxY - frame.maxY)
        let width = Int(frame.width)
        let height = Int(frame.height)

        // Collect screen info for the script header
        var screenInfoLines: [String] = []
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            let v = screen.visibleFrame
            let isPrimary = (i == 0) ? " [PRIMARY]" : ""
            let name = screen.localizedName
            screenInfoLines.append(
                "//   Screen \(i)\(isPrimary): \"\(name)\" frame=(\(Int(f.origin.x)),\(Int(f.origin.y)),\(Int(f.width)),\(Int(f.height))) visible=(\(Int(v.origin.x)),\(Int(v.origin.y)),\(Int(v.width)),\(Int(v.height)))"
            )
        }
        let screenInfoComment = screenInfoLines.joined(separator: "\n")

        // Save a standalone Swift script for manual reproduction
        let script = """
        #!/usr/bin/env swift
        // Tiley AX debug script — run with: swift \(target.appName)_<timestamp>.swift
        // Target: \(target.appName) (pid \(target.processIdentifier))
        // Expected position: (\(axX), \(axY))  Expected size: \(width)x\(height)
        // AppKit target frame: (\(Int(frame.origin.x)),\(Int(frame.origin.y)),\(Int(frame.width)),\(Int(frame.height)))
        // screenFrame: (\(Int(screenFrame.origin.x)),\(Int(screenFrame.origin.y)),\(Int(screenFrame.width)),\(Int(screenFrame.height)))
        // primaryMaxY: \(Int(primaryMaxY))
        // Screens at generation time:
        \(screenInfoComment)
        import ApplicationServices
        import AppKit
        import Foundation

        let trusted = AXIsProcessTrusted()
        if !trusted {
            print("ERROR: Accessibility permission not granted.")
            print("Grant permission to your terminal app in:")
            print("  System Settings > Privacy & Security > Accessibility")
            exit(1)
        }

        // Print current screen configuration
        print("=== Screen Configuration ===")
        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            let v = screen.visibleFrame
            let primary = (i == 0) ? " [PRIMARY]" : ""
            print("  Screen \\(i)\\(primary): \\\"\\(screen.localizedName)\\\" frame=(\\(f.origin.x),\\(f.origin.y),\\(f.width),\\(f.height)) visible=(\\(v.origin.x),\\(v.origin.y),\\(v.width),\\(v.height)) backingScale=\\(screen.backingScaleFactor)")
        }
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        print("  primaryMaxY: \\(primaryMaxY)")
        print("")

        func readPosAndSize(_ window: AXUIElement) -> (pos: CGPoint, size: CGSize) {
            var posRef: CFTypeRef?
            var szRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &szRef)
            var pos = CGPoint.zero
            var sz = CGSize.zero
            if let p = posRef { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
            if let s = szRef { AXValueGetValue(s as! AXValue, .cgSize, &sz) }
            return (pos, sz)
        }

        func printState(_ label: String, _ window: AXUIElement) {
            let (pos, sz) = readPosAndSize(window)
            print("\\(label): pos=(\\(pos.x), \\(pos.y)) size=\\(sz.width)x\\(sz.height)")
        }

        let pid: pid_t = \(target.processIdentifier)
        let app = AXUIElementCreateApplication(pid)

        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement],
              let window = windows.first else {
            print("ERROR: Could not get window for pid \\(pid)")
            exit(1)
        }

        let targetPos = CGPoint(x: \(axX), y: \(axY))
        let targetSize = CGSize(width: \(width), height: \(height))
        print("=== AX Operations (size-first + nudge strategy) ===")
        print("Target: pos=(\\(targetPos.x), \\(targetPos.y)) size=\\(targetSize.width)x\\(targetSize.height)")

        printState("[0] Before", window)

        // Step 1: Set size first
        var sz1 = targetSize
        if let v = AXValueCreate(.cgSize, &sz1) {
            let r = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, v)
            print("[1] Set size: \\(r == .success ? "OK" : "FAILED (\\(r.rawValue))")")
        }
        printState("[1] After set size", window)

        // Step 2: Nudge position 1px off-target (to defeat AX de-duplication)
        var nudged = CGPoint(x: targetPos.x, y: targetPos.y + 1)
        if let v = AXValueCreate(.cgPoint, &nudged) {
            let r = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            print("[2] Nudge position (+1px y): \\(r == .success ? "OK" : "FAILED (\\(r.rawValue))")")
        }
        printState("[2] After nudge", window)

        // Step 3: Set final position
        var pos3 = targetPos
        if let v = AXValueCreate(.cgPoint, &pos3) {
            let r = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            print("[3] Set final position: \\(r == .success ? "OK" : "FAILED (\\(r.rawValue))")")
        }
        printState("[3] After set final position", window)

        // Step 4: Wait 200ms, then check again
        usleep(200_000)
        printState("[4] After 200ms wait", window)

        // Step 5: Wait another 500ms to catch slow DisplayLink/USB screens
        usleep(500_000)
        printState("[5] After 700ms total wait", window)

        // Final verdict
        print("")
        print("=== Result ===")
        let (finalPos, finalSz) = readPosAndSize(window)
        if abs(finalPos.x - targetPos.x) > 4 || abs(finalPos.y - targetPos.y) > 4 {
            print("\\u{26A0}\\u{FE0F}  POSITION MISMATCH: expected=(\\(targetPos.x), \\(targetPos.y)) actual=(\\(finalPos.x), \\(finalPos.y)) delta=(\\(finalPos.x - targetPos.x), \\(finalPos.y - targetPos.y))")
        }
        if abs(finalSz.width - targetSize.width) > 4 || abs(finalSz.height - targetSize.height) > 4 {
            print("\\u{26A0}\\u{FE0F}  SIZE MISMATCH: expected=\\(targetSize.width)x\\(targetSize.height) actual=\\(finalSz.width)x\\(finalSz.height) delta=(\\(finalSz.width - targetSize.width), \\(finalSz.height - targetSize.height))")
        }
        if abs(finalPos.x - targetPos.x) <= 4 && abs(finalPos.y - targetPos.y) <= 4
            && abs(finalSz.width - targetSize.width) <= 4 && abs(finalSz.height - targetSize.height) <= 4 {
            print("\\u{2705} All OK")
        }
        """

        let scriptsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tileyScripts")
        try FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "\(target.appName)_\(formatter.string(from: Date())).swift"
        let scriptURL = scriptsDir.appendingPathComponent(filename)
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        NSLog("[Tiley] AX debug script saved: %@", scriptURL.path)

        // Perform the actual resize via AX API
        try accessibilityService.setFrame(frame, on: screenFrame, for: window)
    }

    /// After a move/resize, always raises the window to the front.
    func raiseWindow(target: WindowTarget) {
        guard let window = target.windowElement else { return }
        accessibilityService.raiseWindow(window)
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
