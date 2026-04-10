import AppKit
import CoreGraphics
import Foundation

// MARK: - Private CoreGraphics (CGS) & SkyLight (SLS) API wrappers
//
// Used for Mission Control space detection: which space each window belongs to,
// and the ordered list of all spaces. Loaded via dlsym so the app degrades
// gracefully if symbols become unavailable in a future OS.

/// CGS connection ID — signed 32-bit int matching the private framework ABI
/// (yabai and other tiling WMs also use `int` / `Int32`).
typealias CGSConnectionID = Int32

// Function pointer types.
private typealias MainConnectionIDFunc = @convention(c) () -> CGSConnectionID
private typealias CopySpacesForWindowsFunc = @convention(c) (CGSConnectionID, UInt32, CFArray) -> CFArray?
private typealias CopyManagedDisplaySpacesFunc = @convention(c) (CGSConnectionID) -> CFArray?
/// CGSOrderWindow(cid, windowID, orderingMode, relativeToWindowID) -> CGError
/// orderingMode: kCGSOrderAbove = 1, kCGSOrderBelow = -1, kCGSOrderOut = 0
private typealias OrderWindowFunc = @convention(c) (CGSConnectionID, CGWindowID, Int32, CGWindowID) -> CGError

enum CGSPrivate {
    static let kCGSSpaceAll: UInt32 = 0x7
    static let kCGSSpaceTypeNormal: Int = 0
    static let kCGSSpaceTypeFullScreen: Int = 4

    // MARK: - Lazy symbol resolution

    private static let skyLightHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)
    }()

    private static let cgHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    }()

    private static func resolve<T>(_ name: String, slsName: String? = nil) -> T? {
        let primary = slsName ?? name
        if let h = skyLightHandle, let sym = dlsym(h, primary) {
            return unsafeBitCast(sym, to: T.self)
        }
        if let h = cgHandle, let sym = dlsym(h, name) {
            return unsafeBitCast(sym, to: T.self)
        }
        if let sym = dlsym(nil, name) {
            return unsafeBitCast(sym, to: T.self)
        }
        return nil
    }

    private static let _mainConnectionID: MainConnectionIDFunc? = resolve("CGSMainConnectionID", slsName: "SLSMainConnectionID")
    private static let _copySpacesForWindows: CopySpacesForWindowsFunc? = resolve("CGSCopySpacesForWindows", slsName: "SLSCopySpacesForWindows")
    private static let _copyManagedDisplaySpaces: CopyManagedDisplaySpacesFunc? = resolve("CGSCopyManagedDisplaySpaces", slsName: "SLSCopyManagedDisplaySpaces")
    private static let _orderWindow: OrderWindowFunc? = resolve("CGSOrderWindow", slsName: "SLSOrderWindow")

    // MARK: - Public interface

    /// Whether all required private APIs are resolved.
    static var isAvailable: Bool {
        _mainConnectionID != nil
            && _copySpacesForWindows != nil
            && _copyManagedDisplaySpaces != nil
    }

    /// Returns the connection ID for the current session's window server.
    static func mainConnectionID() -> CGSConnectionID? {
        _mainConnectionID?()
    }

    /// Returns space IDs that contain the given CG window IDs.
    static func spacesForWindows(_ cid: CGSConnectionID, mask: UInt32, windowIDs: [CGWindowID]) -> CFArray? {
        guard let fn = _copySpacesForWindows else { return nil }
        let cfArray = windowIDs.map { NSNumber(value: $0) } as CFArray
        return fn(cid, mask, cfArray)
    }

    /// Returns all managed display spaces.
    static func managedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray? {
        guard let fn = _copyManagedDisplaySpaces else { return nil }
        return fn(cid)
    }

    // MARK: - Window ordering

    static let kCGSOrderAbove: Int32 = 1
    static let kCGSOrderBelow: Int32 = -1

    /// Whether `CGSOrderWindow` is available.
    static var isOrderWindowAvailable: Bool { _orderWindow != nil && _mainConnectionID != nil }

    /// Place `windowID` directly above `relativeToWindowID` in the global
    /// window stacking order.  Pass 0 for `relativeToWindowID` to move the
    /// window to the very front (kCGSOrderAbove) or very back (kCGSOrderBelow).
    @discardableResult
    static func orderWindow(_ windowID: CGWindowID, mode: Int32, relativeTo relativeToWindowID: CGWindowID = 0) -> Bool {
        guard let fn = _orderWindow, let cid = _mainConnectionID?() else { return false }
        return fn(cid, windowID, mode, relativeToWindowID) == .success
    }

    // MARK: - Show Desktop dismissal

    /// `RTLD_DEFAULT` — searches all loaded dylibs (macOS defines it as `(void*)-2`).
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)

    private typealias CoreDockSendNotificationFunc = @convention(c) (CFString, Int32) -> Void

    private static let _coreDockSendNotification: CoreDockSendNotificationFunc? = {
        guard let sym = dlsym(rtldDefault, "CoreDockSendNotification") else { return nil }
        return unsafeBitCast(sym, to: CoreDockSendNotificationFunc.self)
    }()

    /// Heuristic: returns `true` when "Show Desktop" is likely active.
    ///
    /// During Show Desktop, macOS pushes all normal windows far off-screen.
    /// We detect this by checking if the majority of layer-0 windows have
    /// their centre point well outside all display bounds.
    static func isShowDesktopLikelyActive() -> Bool {
        let myPID = getpid()
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return false }

        // Build union of all screen frames in CG coordinate space (origin at
        // top-left of primary display). NSScreen uses bottom-left origin.
        let primaryHeight = screens[0].frame.height
        var totalBounds = CGRect.null
        for screen in screens {
            let cgOriginY = primaryHeight - screen.frame.maxY
            let cgFrame = CGRect(x: screen.frame.origin.x, y: cgOriginY,
                                 width: screen.frame.width, height: screen.frame.height)
            totalBounds = totalBounds.union(cgFrame)
        }
        // Small margin — only consider windows whose centre is clearly
        // outside all screens. During Show Desktop windows are pushed
        // hundreds of pixels beyond the edge.
        let expandedBounds = totalBounds.insetBy(dx: -50, dy: -50)

        let options = CGWindowListOption([.optionOnScreenOnly, .excludeDesktopElements])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        var normalCount = 0
        var offScreenCount = 0

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != myPID else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let w = bounds["Width"] ?? 0
            let h = bounds["Height"] ?? 0
            // Skip tiny windows (status items, invisible helpers, etc.)
            guard w > 100 && h > 100 else { continue }

            normalCount += 1
            let center = CGPoint(x: (bounds["X"] ?? 0) + w / 2,
                                 y: (bounds["Y"] ?? 0) + h / 2)
            if !expandedBounds.contains(center) {
                offScreenCount += 1
            }
        }

        let onScreenCount = normalCount - offScreenCount
        debugLog("isShowDesktopLikelyActive: normalCount=\(normalCount) offScreenCount=\(offScreenCount) onScreenCount=\(onScreenCount) expandedBounds=\(expandedBounds)")
        // Show Desktop pushes ALL windows off-screen. If even one sizeable
        // window remains on-screen, we are NOT in Show Desktop mode.
        // Require at least 3 off-screen windows to avoid false positives
        // from single-window edge cases.
        return offScreenCount >= 3 && onScreenCount == 0
    }

    /// Heuristic: returns `true` when Mission Control is likely active.
    ///
    /// During Mission Control the Dock (or WindowManager) creates many
    /// overlay windows at non-standard layers. In normal operation the Dock
    /// has only a handful of windows.
    static func isMissionControlLikelyActive() -> Bool {
        let options = CGWindowListOption([.optionOnScreenOnly])
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        var dockOverlayCount = 0
        for info in list {
            guard let owner = info[kCGWindowOwnerName as String] as? String,
                  owner == "Dock" || owner == "WindowManager" else { continue }
            guard let layer = info[kCGWindowLayer as String] as? Int else { continue }
            // Count Dock/WM windows at non-standard layers (> 0) which appear
            // during Mission Control but not during normal operation.
            if layer > 0 && layer < 1000 {
                dockOverlayCount += 1
            }
        }
        debugLog("isMissionControlLikelyActive: dockOverlayCount=\(dockOverlayCount)")
        return dockOverlayCount > 5
    }

    /// Log the frontmost app state for Show Desktop debugging.
    private static func logFrontmostState() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        let bid = frontmost?.bundleIdentifier ?? "?"
        let name = frontmost?.localizedName ?? "?"
        let pid = frontmost?.processIdentifier ?? 0
        debugLog("dismissDesktopExpose: frontmost=\(name) (\(bid)) pid=\(pid) myPID=\(getpid())")
    }

    /// Dismiss "Show Desktop" and/or Mission Control if either is active.
    /// On macOS 26 `CoreDockSendNotification` toggles the state, so we only
    /// send the notification when the corresponding state is detected.
    static func dismissDesktopExpose() {
        dismissDesktopExpose(
            showDesktop: isShowDesktopLikelyActive(),
            missionControl: isMissionControlLikelyActive()
        )
    }

    /// Dismiss Show Desktop / Mission Control using pre-computed detection results
    /// to avoid redundant CGWindowList queries.
    static func dismissDesktopExpose(showDesktop: Bool, missionControl: Bool) {
        logFrontmostState()
        debugLog("dismissDesktopExpose: showDesktop=\(showDesktop) missionControl=\(missionControl)")
        if showDesktop {
            _coreDockSendNotification?("com.apple.showdesktop.awake" as CFString, 0)
            debugLog("dismissDesktopExpose: sent showdesktop.awake")
        }
        if missionControl {
            _coreDockSendNotification?("com.apple.expose.awake" as CFString, 0)
            debugLog("dismissDesktopExpose: sent expose.awake")
        }
    }
}
