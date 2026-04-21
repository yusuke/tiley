import ApplicationServices
import AppKit

struct WindowResizability {
    let horizontal: Bool
    let vertical: Bool

    static let both = WindowResizability(horizontal: true, vertical: true)
    static let none = WindowResizability(horizontal: false, vertical: false)
}

struct WindowTarget {
    let appElement: AXUIElement
    /// `nil` for hidden-app placeholders whose AX windows couldn't be queried.
    let windowElement: AXUIElement?
    let processIdentifier: pid_t
    let appName: String
    let windowTitle: String?
    let frame: CGRect
    let visibleFrame: CGRect
    let screenFrame: CGRect
    /// True when the owning application is hidden (Cmd-H).
    let isHidden: Bool
    /// The Mission Control space ID this window belongs to (`nil` when detection is unavailable).
    let spaceID: UInt64?
    /// True when the window resides on a non-current Mission Control space.
    let isOnOtherSpace: Bool
    /// The CoreGraphics window ID, used for space-movement operations.
    let cgWindowID: CGWindowID

    init(
        appElement: AXUIElement,
        windowElement: AXUIElement?,
        processIdentifier: pid_t,
        appName: String,
        windowTitle: String?,
        frame: CGRect,
        visibleFrame: CGRect,
        screenFrame: CGRect,
        isHidden: Bool,
        spaceID: UInt64? = nil,
        isOnOtherSpace: Bool = false,
        cgWindowID: CGWindowID = 0
    ) {
        self.appElement = appElement
        self.windowElement = windowElement
        self.processIdentifier = processIdentifier
        self.appName = appName
        self.windowTitle = windowTitle
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.screenFrame = screenFrame
        self.isHidden = isHidden
        self.spaceID = spaceID
        self.isOnOtherSpace = isOnOtherSpace
        self.cgWindowID = cgWindowID
    }
}

/// Represents a Mission Control space (desktop).
struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    /// 1-based index within its display (for "Desktop 1", "Desktop 2"). 0 for full-screen spaces.
    let index: Int
    let displayUUID: String
    let isCurrent: Bool
    let isFullScreen: Bool
}

/// Result of parsing CGSCopyManagedDisplaySpaces.
struct SpaceMapResult {
    let spaceList: [SpaceInfo]
    /// Active space IDs across all displays (one per display).
    let activeSpaceIDs: Set<UInt64>
    let isAvailable: Bool

    /// Convenience: first active space ID (for single-display setups).
    var activeSpaceID: UInt64? { activeSpaceIDs.first }

    static let empty = SpaceMapResult(spaceList: [], activeSpaceIDs: [], isAvailable: false)
}

enum WindowAccessError: LocalizedError {
    case accessibilityDenied
    case focusedAppUnavailable
    case focusedWindowUnavailable
    case unsupportedWindow
    case positionSetFailed
    case sizeSetFailed

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return NSLocalizedString("Accessibility access is required. Enable Tiley in System Settings > Privacy & Security > Accessibility.", comment: "Accessibility denied error")
        case .focusedAppUnavailable:
            return NSLocalizedString("The frontmost application could not be identified.", comment: "Focused app unavailable error")
        case .focusedWindowUnavailable:
            return NSLocalizedString("The frontmost window could not be identified.", comment: "Focused window unavailable error")
        case .unsupportedWindow:
            return NSLocalizedString("The focused window does not expose a standard AX position and size.", comment: "Unsupported AX window error")
        case .positionSetFailed:
            return NSLocalizedString("Failed to set the window position.", comment: "Set window position failed error")
        case .sizeSetFailed:
            return NSLocalizedString("Failed to set the window size.", comment: "Set window size failed error")
        }
    }
}

final class AccessibilityService {
    func checkAccess(prompt: Bool) -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func frontmostApplicationPID() throws -> pid_t {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw WindowAccessError.focusedAppUnavailable
        }
        return app.processIdentifier
    }

    /// Returns the PID of the application currently focused according to
    /// the Accessibility layer's system-wide element.  Prefer this over
    /// `NSWorkspace.shared.frontmostApplication` when responding to a
    /// synchronous event (e.g. a Carbon global hotkey): `NSWorkspace` is
    /// updated via asynchronous AppKit notifications and can briefly lag
    /// behind WindowServer, whereas AX reflects the WindowServer state
    /// more promptly.  Returns nil if AX refuses the query.
    static func focusedApplicationPID() -> pid_t? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &value
        )
        guard result == .success, let element = value else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element as! AXUIElement, &pid) == .success else { return nil }
        return pid
    }

    /// Returns PIDs of layer-0 on-screen windows in their current CG z-order
    /// (front-to-back), excluding Tiley's own PID.  This is a cheap CG-only
    /// query (typically 1–5 ms) that reflects the authoritative z-order
    /// maintained by WindowServer, with no Accessibility-layer round-trips.
    /// Use this to cheaply realign a stale cached window list against the
    /// current frontmost ordering before showing the UI.
    static func currentZOrderedPIDs() -> [pid_t] {
        let selfPID = getpid()
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }
        var seen = Set<pid_t>()
        var ordered: [pid_t] = []
        for info in list {
            guard let layer = info[kCGWindowLayer] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, pid != selfPID else { continue }
            if seen.insert(pid).inserted {
                ordered.append(pid)
            }
        }
        return ordered
    }

    /// Returns CGWindowIDs of layer-0 on-screen windows in their current CG
    /// z-order (front-to-back), excluding Tiley's own windows.  Unlike
    /// `currentZOrderedPIDs`, this preserves intra-app z-order — necessary
    /// when the user raises a non-top window within the same application
    /// (no `didActivateApplicationNotification` fires, but CG z-order does
    /// change).
    static func currentZOrderedWindowIDs() -> [CGWindowID] {
        let selfPID = getpid()
        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }
        var ordered: [CGWindowID] = []
        for info in list {
            guard let layer = info[kCGWindowLayer] as? Int, layer == 0 else { continue }
            guard let pid = info[kCGWindowOwnerPID] as? pid_t, pid != selfPID else { continue }
            guard let wid = info[kCGWindowNumber] as? CGWindowID else { continue }
            ordered.append(wid)
        }
        return ordered
    }

    func focusedWindowTarget(preferredPID: pid_t? = nil) throws -> WindowTarget {
        let perfStart = CFAbsoluteTimeGetCurrent()
        guard checkAccess(prompt: false) else {
            throw WindowAccessError.accessibilityDenied
        }

        if let preferredPID, preferredPID != getpid() {
            do {
                let target = try windowTarget(for: preferredPID)
                let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
                debugLog("focusedWindowTarget done (preferred pid=\(preferredPID)) (\(String(format: "%.1f", elapsed))ms)")
                return target
            } catch {
                // Fall back to the current frontmost app if the preferred app no longer has a usable window.
            }
        }

        let frontmostPID = try frontmostApplicationPID()
        if frontmostPID == getpid() {
            // Tiley is frontmost — never target our own window.
            throw WindowAccessError.focusedWindowUnavailable
        }
        let target = try windowTarget(for: frontmostPID)
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("focusedWindowTarget done (frontmost pid=\(frontmostPID)) (\(String(format: "%.1f", elapsed))ms)")
        return target
    }

    func windowTarget(for pid: pid_t) throws -> WindowTarget {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let appElement = AXUIElementCreateApplication(pid)
        let windowElement = try copyWindowElement(from: appElement)
        let position = try copyAXValueAttribute(windowElement, attribute: kAXPositionAttribute)
        let size = try copyAXValueAttribute(windowElement, attribute: kAXSizeAttribute)

        var origin = CGPoint.zero
        var sizeRect = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(size, .cgSize, &sizeRect) else {
            throw WindowAccessError.unsupportedWindow
        }

        let screen = resolveScreen(forAXOrigin: origin, size: sizeRect)
        let frame = frameForAXOrigin(origin, size: sizeRect, on: screen)
        let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? frame
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
        let appName = NSRunningApplication(processIdentifier: pid)?.localizedName ?? NSLocalizedString("App", comment: "Generic app name fallback")
        let windowTitle = try? copyStringAttribute(windowElement, attribute: kAXTitleAttribute)

        let result = WindowTarget(
            appElement: appElement,
            windowElement: windowElement,
            processIdentifier: pid,
            appName: appName,
            windowTitle: windowTitle,
            frame: frame,
            visibleFrame: visibleFrame,
            screenFrame: screenFrame,
            isHidden: NSRunningApplication(processIdentifier: pid)?.isHidden ?? false
        )
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("windowTarget(for: \(pid)) done (\(String(format: "%.1f", elapsed))ms)")
        return result
    }

    /// Detects per-axis resize capability of a window using non-destructive
    /// AX attribute checks.  Falls back to a 1px probe only for ambiguous
    /// windows (e.g. System Settings — size attribute reports settable but
    /// the full-screen button is absent).
    ///
    /// - Fully non-resizable windows (Calculator): `kAXSizeAttribute` is
    ///   not settable → `.none` immediately.
    /// - Fully resizable windows (Finder, Safari, Xcode): `kAXSizeAttribute`
    ///   is settable **and** `AXFullScreenButton` is present → `.both`.
    /// - Partially constrained windows (System Settings): settable but no
    ///   full-screen button → probe each axis with a 1px nudge.
    func detectResizability(of window: AXUIElement) -> WindowResizability {
        // Fast path: if the size attribute is not settable at all, the
        // window cannot be resized on either axis.
        var settable: DarwinBoolean = false
        let settableResult = AXUIElementIsAttributeSettable(window, kAXSizeAttribute as CFString, &settable)
        if settableResult != .success || !settable.boolValue {
            return .none
        }

        // Check for the full-screen button. Fully resizable standard
        // windows expose this button; constrained windows (like System
        // Settings) do not.
        var fsButton: CFTypeRef?
        let hasFSButton = AXUIElementCopyAttributeValue(
            window,
            "AXFullScreenButton" as CFString,
            &fsButton
        ) == .success && fsButton != nil

        if hasFSButton {
            return .both
        }

        // Ambiguous case: settable but no full-screen button.
        // Probe each axis with a 1px nudge to determine which axes
        // actually accept size changes.
        return probeResizabilityPerAxis(window)
    }

    /// Probes each axis individually by nudging the window size 1px and
    /// checking whether the size actually changed. Restores the original
    /// size immediately after each probe.
    private func probeResizabilityPerAxis(_ window: AXUIElement) -> WindowResizability {
        guard let currentValue = try? copyAXValueAttribute(window, attribute: kAXSizeAttribute) else {
            return .none
        }
        var currentSize = CGSize.zero
        guard AXValueGetValue(currentValue, .cgSize, &currentSize) else { return .none }
        guard currentSize.width > 1, currentSize.height > 1 else { return .none }

        let horizontalChanged = probeSingleAxis(window, currentSize: currentSize,
                                                 probeSize: CGSize(width: currentSize.width + 1, height: currentSize.height),
                                                 checkAxis: \.width)
        let verticalChanged = probeSingleAxis(window, currentSize: currentSize,
                                               probeSize: CGSize(width: currentSize.width, height: currentSize.height + 1),
                                               checkAxis: \.height)

        return WindowResizability(horizontal: horizontalChanged, vertical: verticalChanged)
    }

    private func probeSingleAxis(_ window: AXUIElement, currentSize: CGSize, probeSize: CGSize, checkAxis: KeyPath<CGSize, CGFloat>) -> Bool {
        var probe = probeSize
        guard let probeValue = AXValueCreate(.cgSize, &probe) else { return false }
        let setResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, probeValue)
        let changed: Bool
        if setResult == .success,
           let afterValue = try? copyAXValueAttribute(window, attribute: kAXSizeAttribute) {
            var afterSize = CGSize.zero
            AXValueGetValue(afterValue, .cgSize, &afterSize)
            changed = abs(afterSize[keyPath: checkAxis] - currentSize[keyPath: checkAxis]) > 0.5
        } else {
            changed = false
        }
        // Restore original size.
        var restore = currentSize
        if let rv = AXValueCreate(.cgSize, &restore) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, rv)
        }
        return changed
    }

    /// Returns `true` when the window is in native macOS fullscreen mode.
    func isFullScreen(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        guard result == .success, let fs = value as? Bool else { return false }
        return fs
    }

    /// Checks whether the window is in native macOS fullscreen mode and,
    /// if so, exits fullscreen.  Tries setting the AXFullScreen attribute
    /// directly, then falls back to pressing AXFullScreenButton.  Waits
    /// up to ~2 s for the transition animation to finish before returning.
    func exitFullScreenIfNeeded(_ window: AXUIElement) {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value)
        guard result == .success,
              let isFullScreen = value as? Bool,
              isFullScreen else { return }

        // Preferred: set the attribute directly.
        let setResult = AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, kCFBooleanFalse)

        // Fallback: press the fullscreen button if direct set failed.
        if setResult != .success {
            var fsButton: CFTypeRef?
            if AXUIElementCopyAttributeValue(window, "AXFullScreenButton" as CFString, &fsButton) == .success,
               let button = fsButton {
                AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
            }
        }

        // Wait for the fullscreen exit animation to complete (up to ~2s).
        for _ in 0..<40 {
            usleep(50_000) // 50 ms
            var newValue: CFTypeRef?
            let r = AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &newValue)
            if r == .success, let stillFS = newValue as? Bool, !stillFS {
                break
            }
        }
    }

    /// Moves a window to the given AX position (top-left origin, y-down)
    /// without changing its size.
    func setPosition(_ position: CGPoint, for window: AXUIElement) {
        var pos = position
        guard let value = AXValueCreate(.cgPoint, &pos) else { return }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    /// 軽量な position+size セット。ドラッグ中の連続適用向け。
    /// `setFrame` のような pre-nudge/bounce/位置補正は行わず、AX に直接書き込むだけ。
    /// グループ連動でフォロワーを 60Hz で動かす際のチラつきを避けるために使う。
    func setFrameLightweight(_ frame: CGRect, on screenFrame: CGRect, for window: AXUIElement) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        var origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        var size = frame.size
        if let posValue = AXValueCreate(.cgPoint, &origin) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    /// Moves and resizes the given window synchronously, then returns.
    /// Call ``verifyAndCorrectFrame(_:for:)`` afterwards (on a background
    /// thread) to handle apps that asynchronously revert position or size.
    @discardableResult
    func setFrame(_ frame: CGRect, on screenFrame: CGRect, for window: AXUIElement) throws -> Bool {
        // Exit native fullscreen before resizing — fullscreen windows
        // cannot be moved or resized via the Accessibility API.
        exitFullScreenIfNeeded(window)

        let (targetOrigin, targetSize) = axOriginAndSize(for: frame, screenFrame: screenFrame)

        try applyPositionAndSize(targetOrigin, targetSize, for: window)

        // If the app constrained the size (e.g. minimum window size),
        // recalculate the position so the window stays within the
        // target screen's visible area.
        let (actualPos, actualSize) = readPositionAndSize(of: window)
        let constrained = abs(actualSize.width - targetSize.width) > 2
                       || abs(actualSize.height - targetSize.height) > 2
        if constrained {
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
            // Compute the AX bounds of the target screen's visible frame.
            let targetScreen = NSScreen.screens.first { $0.frame == screenFrame }
            let visibleFrame = targetScreen?.visibleFrame ?? screenFrame
            let visibleAXTop = primaryMaxY - visibleFrame.maxY
            let visibleAXBottom = primaryMaxY - visibleFrame.minY

            // Clamp the position so the window fits within the visible area.
            var adjusted = actualPos
            // Right edge
            if adjusted.x + actualSize.width > visibleFrame.maxX {
                adjusted.x = visibleFrame.maxX - actualSize.width
            }
            // Left edge
            adjusted.x = max(adjusted.x, visibleFrame.minX)
            // Bottom edge (AX y increases downward)
            if adjusted.y + actualSize.height > visibleAXBottom {
                adjusted.y = visibleAXBottom - actualSize.height
            }
            // Top edge
            adjusted.y = max(adjusted.y, visibleAXTop)

            if abs(adjusted.x - actualPos.x) > 1 || abs(adjusted.y - actualPos.y) > 1 {
                var adj = adjusted
                if let val = AXValueCreate(.cgPoint, &adj) {
                    AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, val)
                }
            }
        }

        return constrained
    }

    /// Reads the current AX position and size of a window.
    func readPositionAndSize(of window: AXUIElement) -> (pos: CGPoint, size: CGSize) {
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let posVal = try? copyAXValueAttribute(window, attribute: kAXPositionAttribute) {
            AXValueGetValue(posVal, .cgPoint, &pos)
        }
        if let szVal = try? copyAXValueAttribute(window, attribute: kAXSizeAttribute) {
            AXValueGetValue(szVal, .cgSize, &size)
        }
        return (pos, size)
    }

    /// Converts an AppKit frame to AX origin + size.
    private func axOriginAndSize(for frame: CGRect, screenFrame: CGRect) -> (origin: CGPoint, size: CGSize) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        let origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        return (origin, frame.size)
    }

    /// Moves and resizes a window robustly.
    ///
    /// Some apps revert the window position when a size change arrives, and
    /// then silently ignore subsequent position-set calls for the same
    /// coordinates (AX de-duplication).  The strategy:
    ///   1. Set position first — so the window is at the target origin before
    ///      resizing.  This prevents size from being constrained by the
    ///      screen edge (critical for maximise).
    ///   2. Set size — the window is now at the correct origin so it has room
    ///      to expand.  Some apps may revert the position here.
    ///   3. Nudge position 1px off-target — defeats AX de-duplication.
    ///   4. Set final position — always accepted because it differs from the
    ///      nudge.
    ///
    /// On non-primary screens (especially mixed-DPI setups), AX size changes
    /// may silently fail.  In that case we "bounce" the window: move it to
    /// the primary screen, resize there, then move to the final position.
    private func applyPositionAndSize(_ origin: CGPoint, _ size: CGSize, for window: AXUIElement) throws {
        var org = origin
        var sz = size
        guard let position = AXValueCreate(.cgPoint, &org) else {
            throw WindowAccessError.positionSetFailed
        }
        guard let sizeValue = AXValueCreate(.cgSize, &sz) else {
            throw WindowAccessError.sizeSetFailed
        }

        // Check if the target is on a non-primary screen.
        let primaryScreen = NSScreen.screens.first
        let isTargetOnPrimary: Bool = {
            guard let primary = primaryScreen else { return true }
            // AX origin is in the primary screen's coordinate space.
            // If the target origin falls within the primary screen's
            // AX bounds, it's on the primary.
            let primaryAXRect = CGRect(x: primary.frame.minX, y: 0,
                                        width: primary.frame.width,
                                        height: primary.frame.height)
            return primaryAXRect.contains(origin)
        }()

        if isTargetOnPrimary {
            try applyOnCurrentScreen(origin, size, position: position, sizeValue: sizeValue, for: window)
        } else {
            try applyViaPrimaryBounce(origin, size, position: position, sizeValue: sizeValue, for: window)
        }
    }

    /// Standard apply for windows on the primary screen.
    ///
    /// Key lessons from past bugs:
    /// - Some apps (Conductor, Ghostty) reject the AX size change but
    ///   asynchronously reposition the window as a side-effect — typically
    ///   snapping to Y = screenHeight − windowHeight (bottom-aligned).
    ///   Without waiting for this async adjustment to settle (step 3),
    ///   the subsequent position sets race against the app and lose.
    /// - The fallback bounce in step 2b was originally placed at the
    ///   *bottom* of the primary screen (y ≈ primaryHeight − 1).  For a
    ///   window that needs the full screen height this left zero room to
    ///   expand, and the app bottom-aligned the window there, leaving it
    ///   stranded at the wrong position.  Moving the bounce to the
    ///   *top* of the visible area gives maximum vertical room.
    private func applyOnCurrentScreen(_ origin: CGPoint, _ size: CGSize,
                                       position: AXValue, sizeValue: AXValue,
                                       for window: AXUIElement) throws {
        // 0. If the window is already at the target position, pre-nudge
        //    so that step 1 is not de-duplicated by AX.  Without this,
        //    apps that revert position on a size change (step 2) leave
        //    the window stuck at the reverted position because AX thinks
        //    steps 3–4 are no-ops.
        let (currentPos, _) = readPositionAndSize(of: window)
        if abs(currentPos.x - origin.x) <= 1 && abs(currentPos.y - origin.y) <= 1 {
            var preNudge = origin
            preNudge.y += 1
            if let v = AXValueCreate(.cgPoint, &preNudge) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
        }

        // 1. Move to target position first so the subsequent resize has
        //    room to expand (e.g. maximise from a centred window).
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        guard positionResult == .success else {
            throw WindowAccessError.positionSetFailed
        }

        // 2. Set target size.
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else {
            throw WindowAccessError.sizeSetFailed
        }

        // 2b. Verify that the size actually changed.  Some apps (e.g. Chrome)
        //     return .success but silently ignore the size change.  In that
        //     case, bounce the window to the top-left of the visible area
        //     (giving maximum room to expand), resize there, then continue
        //     to position correction below.
        let (_, afterSize) = readPositionAndSize(of: window)
        let sizeUnchanged = abs(afterSize.width - size.width) > 2
                         || abs(afterSize.height - size.height) > 2
        if sizeUnchanged {
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 1200
            let visibleMaxY = NSScreen.screens.first?.visibleFrame.maxY ?? primaryMaxY
            var topOfVisible = CGPoint(x: 0, y: primaryMaxY - visibleMaxY)
            if let v = AXValueCreate(.cgPoint, &topOfVisible) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // 3. Wait for apps that asynchronously adjust position in
        //    response to the size change (even when they reject it).
        //    Without this pause the position sets below race against the
        //    app's own adjustment and lose.
        usleep(50_000) // 50 ms

        // 4. Nudge position 1px off-target so the AX subsystem won't
        //    de-duplicate the real set in step 5.
        var nudged = origin
        nudged.y += 1
        if let nudgeVal = AXValueCreate(.cgPoint, &nudged) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, nudgeVal)
        }

        // 5. Set final position — always treated as a change because it
        //    differs from the nudged value.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)

        // 6. Verify position stuck — some apps asynchronously revert
        //    position after a size change even on the primary screen.
        for attempt in 0..<3 {
            let (afterPos, _) = readPositionAndSize(of: window)
            let posOK = abs(afterPos.x - origin.x) <= 4
                     && abs(afterPos.y - origin.y) <= 4
            guard !posOK else { break }
            usleep(attempt == 0 ? 50_000 : 100_000)
            var retryNudge = origin
            retryNudge.y += 1
            if let v = AXValueCreate(.cgPoint, &retryNudge) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    /// For non-primary screens: first try to resize directly on the
    /// target screen.  If that fails and the target size fits on the
    /// primary screen, bounce the window there to resize (AX size
    /// changes are more reliable on the primary screen), then move to
    /// the final position.
    ///
    /// Key lessons from past bugs:
    /// - Despite the method name, the original implementation never
    ///   actually bounced via the primary screen — it just moved to the
    ///   target position and retried the size set there.  For some apps
    ///   (e.g. Claude/Electron) AX size changes on non-primary screens
    ///   are silently ignored regardless of retries.  Step 2c now
    ///   performs a real bounce to the primary screen where AX is more
    ///   reliable, then moves back.
    /// - Step 3 shares the same async-position-adjustment concern as
    ///   ``applyOnCurrentScreen``: apps may reposition the window after
    ///   a size change, so we must wait before setting the final
    ///   position.
    /// - Step 5 handles the case where an app re-constrains its size
    ///   after being moved from primary back to the target screen.
    private func applyViaPrimaryBounce(_ origin: CGPoint, _ size: CGSize,
                                        position: AXValue, sizeValue: AXValue,
                                        for window: AXUIElement) throws {
        // 0. Pre-nudge if already at target position to defeat AX
        //    de-duplication (same logic as applyOnCurrentScreen).
        let (currentPos, _) = readPositionAndSize(of: window)
        if abs(currentPos.x - origin.x) <= 1 && abs(currentPos.y - origin.y) <= 1 {
            var preNudge = origin
            preNudge.y += 1
            if let v = AXValueCreate(.cgPoint, &preNudge) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
        }

        // 1. Move to target position first so the window is on the
        //    correct screen before resizing.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)

        // 2. Set size — the window is now on the target screen so the
        //    app can use the full screen dimensions for constraints.
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        // 2b. If the size doesn't match the target (e.g. the app still
        //     uses the old screen's constraints after a cross-screen
        //     move), wait briefly and retry up to 2 times.
        for _ in 0..<2 {
            let (_, afterSize) = readPositionAndSize(of: window)
            let sizeMismatch = abs(afterSize.width - size.width) > 2
                            || abs(afterSize.height - size.height) > 2
            guard sizeMismatch else { break }
            usleep(50_000) // 50 ms
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // 2c. If size is still wrong and fits on the primary screen,
        //     bounce there to resize — AX is more reliable on primary.
        do {
            let (_, sz) = readPositionAndSize(of: window)
            let stillWrong = abs(sz.width - size.width) > 2
                          || abs(sz.height - size.height) > 2
            if stillWrong, let primary = NSScreen.screens.first {
                let fitsOnPrimary = size.width <= primary.visibleFrame.width
                                 && size.height <= primary.visibleFrame.height
                if fitsOnPrimary {
                    let visibleAXTop = primary.frame.maxY - primary.visibleFrame.maxY
                    var bouncePos = CGPoint(x: 0, y: visibleAXTop)
                    if let v = AXValueCreate(.cgPoint, &bouncePos) {
                        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
                    }
                    usleep(50_000)
                    AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
                    usleep(50_000)
                }
            }
        }

        // 3. Wait for apps that asynchronously adjust position in
        //    response to the size change.
        usleep(50_000)

        // 4. Nudge + final position to defeat AX de-duplication.
        var nudged = origin
        nudged.y += 1
        if let nudgeVal = AXValueCreate(.cgPoint, &nudged) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, nudgeVal)
        }
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)

        // 5. Final size correction — some apps re-constrain size after
        //    moving to a different screen.
        let (_, finalSize) = readPositionAndSize(of: window)
        if abs(finalSize.width - size.width) > 2 || abs(finalSize.height - size.height) > 2 {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // 6. Verify position stuck — some apps (e.g. Electron/Notion)
        //    asynchronously revert position after a size change, and the
        //    revert can take longer than the 50 ms wait in step 3.
        //    Retry up to 3 times with increasing waits.
        for attempt in 0..<3 {
            let (afterPos, _) = readPositionAndSize(of: window)
            let posOK = abs(afterPos.x - origin.x) <= 4
                     && abs(afterPos.y - origin.y) <= 4
            guard !posOK else { break }
            usleep(attempt == 0 ? 50_000 : 100_000) // 50 ms, then 100 ms
            var retryNudge = origin
            retryNudge.y += 1
            if let v = AXValueCreate(.cgPoint, &retryNudge) {
                AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, v)
            }
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }

        // 7. Re-raise in case the bounce changed z-order.
        raiseWindow(window)
    }

    /// Raises a window to the front of its application's window stack.
    func raiseWindow(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Closes a window by pressing its close button via the Accessibility API.
    /// Returns `true` if the close action was successfully performed.
    @discardableResult
    func closeWindow(_ window: AXUIElement) -> Bool {
        var closeButton: AnyObject?
        let result = AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &closeButton)
        guard result == .success, let button = closeButton else { return false }
        let actionResult = AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString)
        return actionResult == .success
    }

    /// Returns all on-screen standard windows (excluding Tiley) in z-order (front to back).
    /// When `includeOtherSpaces` is true and private CGS APIs are available, also returns
    /// windows from non-current Mission Control spaces with `isOnOtherSpace` set.
    func allWindowTargets(includeOtherSpaces: Bool = false) -> (targets: [WindowTarget], spaceList: [SpaceInfo], activeSpaceIDs: Set<UInt64>) {
        let perfStart = CFAbsoluteTimeGetCurrent()
        func perfLog(_ label: String) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
            debugLog("allWindowTargets: \(label) (t=\(String(format: "%.1f", elapsed))ms)")
        }
        guard checkAccess(prompt: false) else { return ([], [], []) }

        // Build space map first (before window list) so we know current space.
        let spaceMap = includeOtherSpaces ? Self.buildSpaceMap() : SpaceMapResult.empty
        perfLog("buildSpaceMap done (spaces=\(spaceMap.spaceList.count), available=\(spaceMap.isAvailable))")

        // When space detection is available, fetch all windows (including other spaces).
        // Otherwise, stick with on-screen-only.
        let cgOptions: CGWindowListOption = spaceMap.isAvailable
            ? [.optionAll, .excludeDesktopElements]
            : [.optionOnScreenOnly, .excludeDesktopElements]

        guard let windowList = CGWindowListCopyWindowInfo(
            cgOptions,
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return ([], spaceMap.spaceList, spaceMap.activeSpaceIDs) }
        perfLog("CGWindowListCopyWindowInfo done (\(windowList.count) entries)")

        // Build a Z-order lookup from an on-screen-only query (guaranteed front-to-back).
        // The .optionAll query used above may not preserve Z-order reliably.
        var zOrderByWindowID: [CGWindowID: Int] = [:]
        if spaceMap.isAvailable,
           let onScreenList = CGWindowListCopyWindowInfo(
               [.optionOnScreenOnly, .excludeDesktopElements],
               kCGNullWindowID
           ) as? [[CFString: Any]] {
            for (zIndex, info) in onScreenList.enumerated() {
                if let wid = info[kCGWindowNumber] as? CGWindowID {
                    zOrderByWindowID[wid] = zIndex
                }
            }
            perfLog("zOrderByWindowID built (\(zOrderByWindowID.count) entries)")
        }

        let selfPID = getpid()

        // Collect CGWindow entries for standard windows (layer 0), grouped by PID, preserving z-order.
        struct CGWindowEntry {
            let pid: pid_t
            let bounds: CGRect  // Top-left origin (AX/CG coordinate space)
            let ownerName: String?
            let windowID: CGWindowID
            let isOnScreen: Bool
        }

        var cgEntries: [CGWindowEntry] = []
        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t,
                  ownerPID != selfPID else { continue }
            let layer = info[kCGWindowLayer] as? Int ?? -1
            guard layer == 0 else { continue }
            guard let boundsRef = info[kCGWindowBounds],
                  let bounds = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary) else { continue }
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let ownerName = info[kCGWindowOwnerName] as? String
            let windowID = info[kCGWindowNumber] as? CGWindowID ?? 0
            let isOnScreen = info[kCGWindowIsOnscreen] as? Bool ?? false
            cgEntries.append(CGWindowEntry(pid: ownerPID, bounds: bounds, ownerName: ownerName, windowID: windowID, isOnScreen: isOnScreen))
        }

        // Build per-window space mapping when available.
        var windowSpaceMap: [CGWindowID: UInt64] = [:]
        if spaceMap.isAvailable {
            let allWindowIDs = cgEntries.map(\.windowID).filter { $0 != 0 }
            windowSpaceMap = Self.buildWindowSpaceMap(windowIDs: allWindowIDs)
            perfLog("windowSpaceMap built (\(windowSpaceMap.count) entries)")
        }

        // Separate current-space and other-space CG entries.
        // On-screen entries from CGWindowListCopyWindowInfo are guaranteed to be
        // in front-to-back Z-order.  Off-screen entries (e.g. minimised windows
        // confirmed to be on the current space via the space map) have an
        // undefined position in the CG list and would disrupt Z-order if mixed
        // in.  We therefore collect them separately and append after the
        // on-screen entries so the Z-order of visible windows is preserved.
        let currentSpaceIDs = Set(spaceMap.spaceList.filter(\.isCurrent).map(\.id))
        var currentSpaceEntries: [CGWindowEntry] = []
        var offScreenCurrentSpaceEntries: [CGWindowEntry] = []
        var otherSpaceEntries: [CGWindowEntry] = []

        if spaceMap.isAvailable {
            for entry in cgEntries {
                let wSpaceID = windowSpaceMap[entry.windowID]
                if let sid = wSpaceID, !currentSpaceIDs.contains(sid) {
                    // Window is on a different space.
                    otherSpaceEntries.append(entry)
                } else if entry.isOnScreen {
                    // Visible on current space — Z-order is reliable.
                    currentSpaceEntries.append(entry)
                } else if wSpaceID != nil {
                    // On current space but not on-screen (minimised, etc.) —
                    // Z-order position in the CG list is undefined.
                    offScreenCurrentSpaceEntries.append(entry)
                }
                // else: drop windows that are off-screen with no space info.
            }
            // Sort on-screen entries by the guaranteed Z-order from the
            // separate on-screen-only query (front-to-back).
            if !zOrderByWindowID.isEmpty {
                currentSpaceEntries.sort { a, b in
                    let za = zOrderByWindowID[a.windowID] ?? Int.max
                    let zb = zOrderByWindowID[b.windowID] ?? Int.max
                    return za < zb
                }
            }
            currentSpaceEntries.append(contentsOf: offScreenCurrentSpaceEntries)
        } else {
            currentSpaceEntries = cgEntries
        }
        perfLog("space filtering done: currentSpace=\(currentSpaceEntries.count) offScreenCurrent=\(offScreenCurrentSpaceEntries.count) otherSpace=\(otherSpaceEntries.count)")

        // Collect unique PIDs preserving first-seen order.
        // Exclude PIDs of hidden apps so they are handled in the hidden-apps section below.
        let hiddenPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.isHidden }
                .map(\.processIdentifier)
        )
        var seenPIDs = Set<pid_t>()
        var orderedPIDs: [pid_t] = []
        for entry in currentSpaceEntries {
            guard !hiddenPIDs.contains(entry.pid) else { continue }
            if seenPIDs.insert(entry.pid).inserted {
                orderedPIDs.append(entry.pid)
            }
        }

        // For each PID, enumerate AX windows and build WindowTarget list.
        struct AXWindowInfo {
            let element: AXUIElement
            let origin: CGPoint   // AX/CG top-left coordinates
            let size: CGSize
        }

        perfLog("cgEntries filtered (\(cgEntries.count) entries, \(orderedPIDs.count) unique PIDs)")

        var axWindowsByPID: [pid_t: [AXWindowInfo]] = [:]
        for pid in orderedPIDs {
            let appElement = AXUIElementCreateApplication(pid)
            guard let axWindows = try? copyAllWindowElements(from: appElement) else { continue }
            var infos: [AXWindowInfo] = []
            for w in axWindows {
                // Only include standard windows (skip palettes, toolbars, dialogs, etc.)
                let subrole = try? copyStringAttribute(w, attribute: kAXSubroleAttribute)
                guard subrole == "AXStandardWindow" else { continue }
                guard let pos = try? copyAXValueAttribute(w, attribute: kAXPositionAttribute),
                      let sz = try? copyAXValueAttribute(w, attribute: kAXSizeAttribute) else { continue }
                var origin = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(pos, .cgPoint, &origin),
                      AXValueGetValue(sz, .cgSize, &size) else { continue }
                guard size.width > 0, size.height > 0 else { continue }
                infos.append(AXWindowInfo(element: w, origin: origin, size: size))
            }
            axWindowsByPID[pid] = infos
        }
        perfLog("AX window enumeration done (\(axWindowsByPID.values.reduce(0) { $0 + $1.count }) AX windows)")

        // Match CGWindow entries to AX windows and build results in z-order.
        var results: [WindowTarget] = []
        var usedAXWindows = Set<ObjectIdentifier>()  // Track used AXUIElement refs

        for cgEntry in currentSpaceEntries {
            guard !hiddenPIDs.contains(cgEntry.pid) else { continue }
            guard let axInfos = axWindowsByPID[cgEntry.pid] else { continue }
            // Find matching AX window by position/size comparison.
            let tolerance: CGFloat = 5
            var matchedIndex: Int?
            for (i, axInfo) in axInfos.enumerated() {
                let id = ObjectIdentifier(axInfo.element)
                guard !usedAXWindows.contains(id) else { continue }
                if abs(axInfo.origin.x - cgEntry.bounds.origin.x) < tolerance
                    && abs(axInfo.origin.y - cgEntry.bounds.origin.y) < tolerance
                    && abs(axInfo.size.width - cgEntry.bounds.width) < tolerance
                    && abs(axInfo.size.height - cgEntry.bounds.height) < tolerance {
                    matchedIndex = i
                    break
                }
            }

            // If no exact match and only one unmatched AX window left, use it.
            if matchedIndex == nil {
                let unusedIndices = axInfos.indices.filter { !usedAXWindows.contains(ObjectIdentifier(axInfos[$0].element)) }
                if unusedIndices.count == 1 {
                    matchedIndex = unusedIndices[0]
                }
            }

            // Fallback: match by size alone when positions don't match (e.g.
            // during Show Desktop dismissal animation where CG reports
            // transitioning positions but AX reports final resting positions).
            // Only use this when the size uniquely identifies one unused window.
            if matchedIndex == nil {
                let unusedIndices = axInfos.indices.filter { !usedAXWindows.contains(ObjectIdentifier(axInfos[$0].element)) }
                let sizeTolerance: CGFloat = 5
                let sizeMatches = unusedIndices.filter { i in
                    abs(axInfos[i].size.width - cgEntry.bounds.width) < sizeTolerance
                    && abs(axInfos[i].size.height - cgEntry.bounds.height) < sizeTolerance
                }
                if sizeMatches.count == 1 {
                    matchedIndex = sizeMatches[0]
                }
            }

            guard let idx = matchedIndex else { continue }
            let axInfo = axInfos[idx]
            usedAXWindows.insert(ObjectIdentifier(axInfo.element))

            let screen = resolveScreen(forAXOrigin: axInfo.origin, size: axInfo.size)
            let frame = frameForAXOrigin(axInfo.origin, size: axInfo.size, on: screen)
            let screenFrame = screen?.frame ?? NSScreen.main?.frame ?? frame
            let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? frame
            let appName = NSRunningApplication(processIdentifier: cgEntry.pid)?.localizedName
                ?? cgEntry.ownerName
                ?? NSLocalizedString("App", comment: "Generic app name fallback")
            let windowTitle = try? copyStringAttribute(axInfo.element, attribute: kAXTitleAttribute)

            let target = WindowTarget(
                appElement: AXUIElementCreateApplication(cgEntry.pid),
                windowElement: axInfo.element,
                processIdentifier: cgEntry.pid,
                appName: appName,
                windowTitle: windowTitle,
                frame: frame,
                visibleFrame: visibleFrame,
                screenFrame: screenFrame,
                isHidden: false,
                spaceID: windowSpaceMap[cgEntry.windowID],
                cgWindowID: cgEntry.windowID
            )
            results.append(target)
        }

        perfLog("CG→AX matching done (\(results.count) matched)")

        // Append windows from other spaces (display-only, no AX element).
        if spaceMap.isAvailable && !otherSpaceEntries.isEmpty {
            let defaultScreen = NSScreen.main?.frame ?? .zero
            let defaultVisible = NSScreen.main?.visibleFrame ?? .zero
            for cgEntry in otherSpaceEntries {
                guard !hiddenPIDs.contains(cgEntry.pid) else { continue }
                let app = NSRunningApplication(processIdentifier: cgEntry.pid)
                // Skip apps that aren't regular (no dock icon).
                guard app?.activationPolicy == .regular else { continue }
                let appName = app?.localizedName
                    ?? cgEntry.ownerName
                    ?? NSLocalizedString("App", comment: "Generic app name fallback")
                // Use CG bounds for frame (CG coordinate space = top-left origin).
                // Convert to AppKit coordinate space (bottom-left origin).
                let screen = NSScreen.screens.first { $0.frame.contains(cgEntry.bounds.origin) }
                    ?? NSScreen.main
                let screenFrame = screen?.frame ?? defaultScreen
                let visibleFrame = screen?.visibleFrame ?? defaultVisible
                let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
                let appKitFrame = CGRect(
                    x: cgEntry.bounds.origin.x,
                    y: primaryMaxY - cgEntry.bounds.origin.y - cgEntry.bounds.height,
                    width: cgEntry.bounds.width,
                    height: cgEntry.bounds.height
                )
                results.append(WindowTarget(
                    appElement: AXUIElementCreateApplication(cgEntry.pid),
                    windowElement: nil,
                    processIdentifier: cgEntry.pid,
                    appName: appName,
                    windowTitle: cgEntry.ownerName,  // CG doesn't provide window titles
                    frame: appKitFrame,
                    visibleFrame: visibleFrame,
                    screenFrame: screenFrame,
                    isHidden: false,
                    spaceID: windowSpaceMap[cgEntry.windowID],
                    isOnOtherSpace: true,
                    cgWindowID: cgEntry.windowID
                ))
            }
            perfLog("other-space windows appended (\(otherSpaceEntries.count) entries)")
        }

        // Append entries for hidden applications.
        // Hidden apps don't appear in CGWindowListCopyWindowInfo(.optionOnScreenOnly).
        // AX queries often fail with kAXErrorCannotComplete for hidden apps, so
        // if we can't enumerate individual windows, we add a single placeholder
        // entry (with a nil windowElement) showing just the app name.
        let hiddenApps = NSWorkspace.shared.runningApplications.filter {
            $0.isHidden && $0.activationPolicy == .regular && $0.processIdentifier != selfPID
        }
        let defaultScreen = NSScreen.main?.frame ?? .zero
        let defaultVisible = NSScreen.main?.visibleFrame ?? .zero
        for app in hiddenApps {
            let pid = app.processIdentifier
            guard !seenPIDs.contains(pid) else { continue }
            let appElement = AXUIElementCreateApplication(pid)
            let appName = app.localizedName
                ?? NSLocalizedString("App", comment: "Generic app name fallback")

            let axWindows = (try? copyAllWindowElements(from: appElement)) ?? []
            var addedAny = false
            for w in axWindows {
                let subrole = try? copyStringAttribute(w, attribute: kAXSubroleAttribute)
                guard subrole == "AXStandardWindow" else { continue }
                guard let pos = try? copyAXValueAttribute(w, attribute: kAXPositionAttribute),
                      let sz = try? copyAXValueAttribute(w, attribute: kAXSizeAttribute) else { continue }
                var origin = CGPoint.zero
                var size = CGSize.zero
                guard AXValueGetValue(pos, .cgPoint, &origin),
                      AXValueGetValue(sz, .cgSize, &size) else { continue }
                guard size.width > 0, size.height > 0 else { continue }

                let screen = resolveScreen(forAXOrigin: origin, size: size)
                let frame = frameForAXOrigin(origin, size: size, on: screen)
                let screenFrame = screen?.frame ?? defaultScreen
                let visibleFrame = screen?.visibleFrame ?? defaultVisible
                let windowTitle = try? copyStringAttribute(w, attribute: kAXTitleAttribute)

                results.append(WindowTarget(
                    appElement: appElement,
                    windowElement: w,
                    processIdentifier: pid,
                    appName: appName,
                    windowTitle: windowTitle,
                    frame: frame,
                    visibleFrame: visibleFrame,
                    screenFrame: screenFrame,
                    isHidden: true
                ))
                addedAny = true
            }

            // If AX query failed or returned no standard windows, add a placeholder
            // so the hidden app still appears in the sidebar.
            if !addedAny {
                results.append(WindowTarget(
                    appElement: appElement,
                    windowElement: nil,
                    processIdentifier: pid,
                    appName: appName,
                    windowTitle: nil,
                    frame: defaultVisible,
                    visibleFrame: defaultVisible,
                    screenFrame: defaultScreen,
                    isHidden: true
                ))
            }
        }

        perfLog("hidden apps done (total \(results.count) windows)")
        return (results, spaceMap.spaceList, spaceMap.activeSpaceIDs)
    }

    // MARK: - Space detection helpers

    /// Builds a mapping from CGWindowID to the space ID it belongs to.
    static func buildWindowSpaceMap(windowIDs: [CGWindowID]) -> [CGWindowID: UInt64] {
        guard !windowIDs.isEmpty,
              let cid = CGSPrivate.mainConnectionID() else { return [:] }
        var result: [CGWindowID: UInt64] = [:]
        // Query one window at a time for reliable 1:1 mapping.
        for wid in windowIDs {
            guard let spacesArray = CGSPrivate.spacesForWindows(cid, mask: CGSPrivate.kCGSSpaceAll, windowIDs: [wid]) as? [NSNumber],
                  let firstSpace = spacesArray.first else { continue }
            result[wid] = firstSpace.uint64Value
        }
        return result
    }

    /// Parses the CGSCopyManagedDisplaySpaces output into ordered SpaceInfo structs.
    static func buildSpaceMap() -> SpaceMapResult {
        guard CGSPrivate.isAvailable,
              let cid = CGSPrivate.mainConnectionID(),
              let displaysArray = CGSPrivate.managedDisplaySpaces(cid) as? [[String: Any]] else {
            return .empty
        }

        var spaceList: [SpaceInfo] = []
        var activeSpaceIDs = Set<UInt64>()

        for displayDict in displaysArray {
            let displayUUID = displayDict["Display Identifier"] as? String ?? ""
            guard let spaces = displayDict["Spaces"] as? [[String: Any]] else { continue }

            // Current space for this display.
            let currentSpaceDict = displayDict["Current Space"] as? [String: Any]
            let currentID = (currentSpaceDict?["id64"] as? NSNumber)?.uint64Value

            // Normal-space index counter (for "Desktop N" labeling).
            var desktopIndex = 0

            for spaceDict in spaces {
                guard let id64 = (spaceDict["id64"] as? NSNumber)?.uint64Value else { continue }
                let type = spaceDict["type"] as? Int ?? 0
                let isFullScreen = (type == CGSPrivate.kCGSSpaceTypeFullScreen)
                let isCurrent = (id64 == currentID)

                if isCurrent {
                    activeSpaceIDs.insert(id64)
                }

                if !isFullScreen {
                    desktopIndex += 1
                }

                spaceList.append(SpaceInfo(
                    id: id64,
                    index: isFullScreen ? 0 : desktopIndex,
                    displayUUID: displayUUID,
                    isCurrent: isCurrent,
                    isFullScreen: isFullScreen
                ))
            }
        }

        return SpaceMapResult(
            spaceList: spaceList,
            activeSpaceIDs: activeSpaceIDs,
            isAvailable: true
        )
    }

    private func copyAllWindowElements(from appElement: AXUIElement) throws -> [AXUIElement] {
        guard let value = try copyAttribute(appElement, attribute: kAXWindowsAttribute) else {
            return []
        }
        let windows = unsafeBitCast(value, to: CFArray.self) as [AnyObject]
        return windows.map { unsafeBitCast($0, to: AXUIElement.self) }
    }

    private func copyAttribute(_ element: AXUIElement, attribute: String) throws -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else {
            if attribute == kAXFocusedWindowAttribute {
                throw WindowAccessError.focusedWindowUnavailable
            } else if attribute == kAXPositionAttribute || attribute == kAXSizeAttribute {
                throw WindowAccessError.unsupportedWindow
            } else {
                throw WindowAccessError.focusedAppUnavailable
            }
        }
        return value
    }

    private func copyElementAttribute(_ element: AXUIElement, attribute: String) throws -> AXUIElement {
        guard let value = try copyAttribute(element, attribute: attribute) else {
            throw WindowAccessError.focusedWindowUnavailable
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private func copyWindowElement(from appElement: AXUIElement) throws -> AXUIElement {
        do {
            return try copyElementAttribute(appElement, attribute: kAXFocusedWindowAttribute)
        } catch {
            do {
                return try copyElementAttribute(appElement, attribute: kAXMainWindowAttribute)
            } catch {
                return try copyFirstWindowElement(from: appElement)
            }
        }
    }

    private func copyFirstWindowElement(from appElement: AXUIElement) throws -> AXUIElement {
        guard let value = try copyAttribute(appElement, attribute: kAXWindowsAttribute) else {
            throw WindowAccessError.focusedWindowUnavailable
        }

        let windows = unsafeBitCast(value, to: CFArray.self) as [AnyObject]
        guard let firstWindow = windows.first else {
            throw WindowAccessError.focusedWindowUnavailable
        }
        return unsafeBitCast(firstWindow, to: AXUIElement.self)
    }

    private func copyAXValueAttribute(_ element: AXUIElement, attribute: String) throws -> AXValue {
        guard let value = try copyAttribute(element, attribute: attribute) else {
            throw WindowAccessError.unsupportedWindow
        }
        return unsafeBitCast(value, to: AXValue.self)
    }

    private func copyStringAttribute(_ element: AXUIElement, attribute: String) throws -> String? {
        try copyAttribute(element, attribute: attribute) as? String
    }

    private func resolveScreen(forAXOrigin origin: CGPoint, size: CGSize) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }

        var bestScreen: NSScreen?
        var bestIntersectionArea: CGFloat = 0

        for screen in screens {
            let candidateFrame = frameForAXOrigin(origin, size: size, on: screen)
            let intersection = candidateFrame.intersection(screen.frame)
            let intersectionArea = intersection.isNull ? 0 : (intersection.width * intersection.height)
            if intersectionArea > bestIntersectionArea {
                bestIntersectionArea = intersectionArea
                bestScreen = screen
            }
        }

        if let bestScreen, bestIntersectionArea > 0 {
            return bestScreen
        }

        if let byOriginX = screens.first(where: { screen in
            screen.frame.minX ... screen.frame.maxX ~= origin.x
        }) {
            return byOriginX
        }

        return NSScreen.main ?? screens.first
    }

    private func frameForAXOrigin(_ origin: CGPoint, size: CGSize, on screen: NSScreen?) -> CGRect {
        // AX coordinates have their origin at the top-left of the primary
        // screen, so use the primary screen's maxY for the conversion.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen?.frame.maxY ?? (origin.y + size.height)
        return CGRect(
            x: origin.x,
            y: primaryMaxY - origin.y - size.height,
            width: size.width,
            height: size.height
        )
    }
}
