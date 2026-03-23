import AppKit

// MARK: - Debug log helper

/// Appends a timestamped line to ~/tiley.log when the debug-log setting is on.
/// Replaces the `NSLog("[Tiley:perf] …")` calls so that performance traces are
/// only emitted when the user has explicitly opted in.
func debugLog(_ message: String) {
    guard UserDefaults.standard.bool(forKey: "enableDebugLog") else { return }
    let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("tiley.log")
    let timestamp = ISO8601DateFormatter.shared.string(from: Date())
    let line = "[\(timestamp)] [Tiley:perf] \(message)\n"
    guard let data = line.data(using: .utf8) else { return }
    if FileManager.default.fileExists(atPath: logURL.path) {
        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    } else {
        try? data.write(to: logURL)
    }
}

private extension ISO8601DateFormatter {
    static let shared: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

// MARK: -

final class WindowManager {
    private let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    func captureFocusedWindow(preferredPID: pid_t? = nil) -> WindowTarget? {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let result = try? accessibilityService.focusedWindowTarget(preferredPID: preferredPID)
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("captureFocusedWindow done (\(String(format: "%.1f", elapsed))ms)")
        return result
    }

    func captureAllWindows() -> [WindowTarget] {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let result = accessibilityService.allWindowTargets()
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("captureAllWindows done (\(result.count) windows) (\(String(format: "%.1f", elapsed))ms)")
        return result
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

    /// Moves/resizes a window using the AX API and writes debug info
    /// to `~/tiley.log` when logging is enabled.
    func moveWithLog(target: WindowTarget, to frame: CGRect, on screenFrame: CGRect) throws {
        guard let window = target.windowElement else { return }

        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        let axX = frame.minX
        let axY = primaryMaxY - frame.maxY
        let targetSize = frame.size

        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("tiley.log")

        func log(_ message: String) {
            let line = message + "\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logURL.path) {
                    if let handle = try? FileHandle(forWritingTo: logURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        handle.closeFile()
                    }
                } else {
                    try? data.write(to: logURL)
                }
            }
        }

        func readPosAndSize() -> (pos: CGPoint, size: CGSize) {
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

        func logState(_ label: String) {
            let (pos, sz) = readPosAndSize()
            log("\(label): pos=(\(pos.x), \(pos.y)) size=\(sz.width)x\(sz.height)")
        }

        // Header
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        log("\n=== Tiley resize \(formatter.string(from: Date())) ===")
        log("Target: \(target.appName) (pid \(target.processIdentifier))")
        log("Target AX: pos=(\(axX), \(axY)) size=\(targetSize.width)x\(targetSize.height)")
        log("AppKit frame: \(frame)")
        log("screenFrame: \(screenFrame)  primaryMaxY: \(primaryMaxY)")

        for (i, screen) in NSScreen.screens.enumerated() {
            let f = screen.frame
            let v = screen.visibleFrame
            let primary = (i == 0) ? " [PRIMARY]" : ""
            log("Screen \(i)\(primary): \"\(screen.localizedName)\" frame=(\(f.origin.x),\(f.origin.y),\(f.width),\(f.height)) visible=(\(v.origin.x),\(v.origin.y),\(v.width),\(v.height)) scale=\(screen.backingScaleFactor)")
        }

        logState("[before]")

        // Perform the actual resize
        try accessibilityService.setFrame(frame, on: screenFrame, for: window)

        logState("[after]")

        // Check result
        let (finalPos, finalSz) = readPosAndSize()
        let posMismatch = abs(finalPos.x - axX) > 4 || abs(finalPos.y - axY) > 4
        let sizeMismatch = abs(finalSz.width - targetSize.width) > 4 || abs(finalSz.height - targetSize.height) > 4
        if posMismatch {
            log("POSITION MISMATCH: expected=(\(axX), \(axY)) actual=(\(finalPos.x), \(finalPos.y))")
        }
        if sizeMismatch {
            log("SIZE MISMATCH: expected=\(targetSize.width)x\(targetSize.height) actual=\(finalSz.width)x\(finalSz.height)")
        }
        if !posMismatch && !sizeMismatch {
            log("OK")
        }
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
