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

    func focusedWindowTarget(preferredPID: pid_t? = nil) throws -> WindowTarget {
        guard checkAccess(prompt: false) else {
            throw WindowAccessError.accessibilityDenied
        }

        if let preferredPID, preferredPID != getpid() {
            do {
                return try windowTarget(for: preferredPID)
            } catch {
                // Fall back to the current frontmost app if the preferred app no longer has a usable window.
            }
        }

        let frontmostPID = try frontmostApplicationPID()
        if frontmostPID == getpid() {
            // Tiley is frontmost — never target our own window.
            throw WindowAccessError.focusedWindowUnavailable
        }
        return try windowTarget(for: frontmostPID)
    }

    func windowTarget(for pid: pid_t) throws -> WindowTarget {
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

        return WindowTarget(
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

    /// Moves and resizes the given window synchronously, then returns.
    /// Call ``verifyAndCorrectFrame(_:for:)`` afterwards (on a background
    /// thread) to handle apps that asynchronously revert position or size.
    @discardableResult
    func setFrame(_ frame: CGRect, on screenFrame: CGRect, for window: AXUIElement) throws -> Bool {
        let (targetOrigin, targetSize) = axOriginAndSize(for: frame, screenFrame: screenFrame)

        // Apply position first (for cross-screen moves), then size,
        // then re-apply both to handle apps that need a second pass.
        try applyPositionAndSize(targetOrigin, targetSize, for: window)

        return false
    }

    /// Converts an AppKit frame to AX origin + size.
    private func axOriginAndSize(for frame: CGRect, screenFrame: CGRect) -> (origin: CGPoint, size: CGSize) {
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        let origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        return (origin, frame.size)
    }

    /// Applies size then position.
    ///
    /// Some apps (notably Ghostty) revert the window position when a size
    /// change arrives, and then silently ignore subsequent position-set calls
    /// for the same coordinates (AX de-duplication).  To work around both
    /// issues we:
    ///   1. Set size first so the app's relayout happens in-place.
    ///   2. Nudge the position 1px away from the target so the AX subsystem
    ///      treats the *real* position set in step 3 as a genuine change.
    ///   3. Set the final position.
    ///
    /// For cross-screen moves the position must be set *before* the size so
    /// the window lands on the destination display first.  We detect this
    /// case by checking whether the window's current screen differs from the
    /// target origin.
    private func applyPositionAndSize(_ origin: CGPoint, _ size: CGSize, for window: AXUIElement) throws {
        var org = origin
        var sz = size
        guard let position = AXValueCreate(.cgPoint, &org) else {
            throw WindowAccessError.positionSetFailed
        }
        guard let sizeValue = AXValueCreate(.cgSize, &sz) else {
            throw WindowAccessError.sizeSetFailed
        }

        // Check if this is a cross-screen move by comparing the window's
        // current screen with the target origin.
        let isCrossScreen: Bool = {
            guard let posVal = try? copyAXValueAttribute(window, attribute: kAXPositionAttribute) else { return false }
            var currentOrigin = CGPoint.zero
            AXValueGetValue(posVal, .cgPoint, &currentOrigin)
            let currentScreen = NSScreen.screens.first { $0.frame.contains(currentOrigin) }
            let targetScreen = NSScreen.screens.first { $0.frame.contains(origin) }
            return currentScreen != nil && targetScreen != nil && currentScreen != targetScreen
        }()

        if isCrossScreen {
            // Cross-screen: position first so the window lands on the
            // destination display, then size.
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        // 1. Set size first — the app may relayout but position stays
        //    at its current (or original) location.
        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else {
            throw WindowAccessError.sizeSetFailed
        }

        // 2. Nudge position 1px off-target so the AX subsystem won't
        //    de-duplicate the real set in step 3.
        var nudged = origin
        nudged.y += 1
        if let nudgeVal = AXValueCreate(.cgPoint, &nudged) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, nudgeVal)
        }

        // 3. Set final position.
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        guard positionResult == .success else {
            throw WindowAccessError.positionSetFailed
        }
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
    func allWindowTargets() -> [WindowTarget] {
        guard checkAccess(prompt: false) else { return [] }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return [] }

        let selfPID = getpid()

        // Collect CGWindow entries for standard windows (layer 0), grouped by PID, preserving z-order.
        struct CGWindowEntry {
            let pid: pid_t
            let bounds: CGRect  // Top-left origin (AX/CG coordinate space)
            let ownerName: String?
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
            cgEntries.append(CGWindowEntry(pid: ownerPID, bounds: bounds, ownerName: ownerName))
        }

        // Collect unique PIDs preserving first-seen order.
        // Exclude PIDs of hidden apps so they are handled in the hidden-apps section below.
        let hiddenPIDs = Set(
            NSWorkspace.shared.runningApplications
                .filter { $0.isHidden }
                .map(\.processIdentifier)
        )
        var seenPIDs = Set<pid_t>()
        var orderedPIDs: [pid_t] = []
        for entry in cgEntries {
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

        // Match CGWindow entries to AX windows and build results in z-order.
        var results: [WindowTarget] = []
        var usedAXWindows = Set<ObjectIdentifier>()  // Track used AXUIElement refs

        for cgEntry in cgEntries {
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
                isHidden: false
            )
            results.append(target)
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

        return results
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
