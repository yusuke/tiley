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
}
