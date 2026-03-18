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
    let windowElement: AXUIElement
    let processIdentifier: pid_t
    let appName: String
    let windowTitle: String?
    let frame: CGRect
    let visibleFrame: CGRect
    let screenFrame: CGRect
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
            screenFrame: screenFrame
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

    /// Moves and resizes the given window, returning `true` when the window's
    /// actual post-move size differs from the requested size (i.e. the app
    /// applied its own constraints).
    @discardableResult
    func setFrame(_ frame: CGRect, on screenFrame: CGRect, for window: AXUIElement) throws -> Bool {
        // AX coordinates have their origin at the top-left of the primary
        // screen, so use the primary screen's maxY for the conversion from
        // AppKit's bottom-left coordinate system.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screenFrame.maxY
        var origin = CGPoint(x: frame.minX, y: primaryMaxY - frame.maxY)
        var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &origin) else {
            throw WindowAccessError.positionSetFailed
        }
        guard let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw WindowAccessError.sizeSetFailed
        }

        // When moving a window across screens of different sizes, some apps
        // constrain the window size based on the screen it currently occupies.
        // To work around this we apply the geometry in multiple passes:
        // 1. Set position to move the window onto the destination screen.
        // 2. Set size — the app now accepts the larger dimensions.
        // 3. Re-apply position to correct any drift from the resize.
        // 4. Re-apply size once more in case the first resize was still
        //    constrained by the old screen (belt-and-suspenders).
        let positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        guard positionResult == .success else {
            throw WindowAccessError.positionSetFailed
        }

        let sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        guard sizeResult == .success else {
            throw WindowAccessError.sizeSetFailed
        }

        // Re-apply position then size to handle apps that need a second pass.
        AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)

        // Give the app a moment to apply its own constraints before reading
        // back the actual size.  A short run-loop spin is enough for most apps.
        usleep(50_000) // 50 ms

        // Read back the actual size to detect if the app constrained it.
        let constrained: Bool
        if let actualSize = try? copyAXValueAttribute(window, attribute: kAXSizeAttribute) {
            var actualCGSize = CGSize.zero
            if AXValueGetValue(actualSize, .cgSize, &actualCGSize) {
                constrained = abs(actualCGSize.width - size.width) > 1
                    || abs(actualCGSize.height - size.height) > 1
            } else {
                constrained = false
            }
        } else {
            constrained = false
        }
        return constrained
    }

    /// Raises a window to the front of its application's window stack.
    func raiseWindow(_ window: AXUIElement) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    /// Checks whether the given window would be substantially occluded by
    /// other windows of the **same** application after being moved to `newFrame`.
    ///
    /// Because `CGWindowListCopyWindowInfo` may not yet reflect the post-move
    /// position, this method identifies the target window by its **pre-move**
    /// frame (`oldFrame`) and then tests the new frame against same-app windows
    /// that are in front of it in z-order.
    ///
    /// - Parameters:
    ///   - pid: The process identifier of the window's owning application.
    ///   - oldFrame: The window's frame *before* the move (CG top-left coordinates).
    ///   - newFrame: The window's frame *after* the move (CG top-left coordinates).
    /// - Returns: `true` when the window would be mostly hidden behind same-app windows.
    func isWindowOccludedBySameApp(pid: pid_t, oldFrame: CGRect, newFrame: CGRect) -> Bool {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[CFString: Any]] else { return false }

        let selfPID = getpid()

        // Walk the z-ordered window list (front to back).
        // Collect frames of same-app windows that appear *before* the target window.
        var sameAppFramesInFront: [CGRect] = []
        var foundTarget = false

        for info in windowList {
            guard let ownerPID = info[kCGWindowOwnerPID] as? pid_t else { continue }
            if ownerPID == selfPID { continue }
            let layer = info[kCGWindowLayer] as? Int ?? -1
            guard layer == 0 else { continue }
            guard let boundsRef = info[kCGWindowBounds],
                  let bounds = CGRect(dictionaryRepresentation: boundsRef as! CFDictionary) else { continue }
            guard bounds.width > 0, bounds.height > 0 else { continue }

            if ownerPID == pid {
                // Match the target by its pre-move frame (which CGWindowList still has)
                // or its post-move frame (in case the CG server already updated).
                let tolerance: CGFloat = 10
                let matchesOld = abs(bounds.origin.x - oldFrame.origin.x) < tolerance
                    && abs(bounds.origin.y - oldFrame.origin.y) < tolerance
                    && abs(bounds.width - oldFrame.width) < tolerance
                    && abs(bounds.height - oldFrame.height) < tolerance
                let matchesNew = abs(bounds.origin.x - newFrame.origin.x) < tolerance
                    && abs(bounds.origin.y - newFrame.origin.y) < tolerance
                    && abs(bounds.width - newFrame.width) < tolerance
                    && abs(bounds.height - newFrame.height) < tolerance
                if matchesOld || matchesNew {
                    foundTarget = true
                    break
                }
                // Same-app window that is in front of our target.
                sameAppFramesInFront.append(bounds)
            }
        }

        guard foundTarget, !sameAppFramesInFront.isEmpty else { return false }

        // Calculate how much of newFrame is covered by same-app windows in front.
        let targetArea = newFrame.width * newFrame.height
        guard targetArea > 0 else { return false }

        var coveredArea: CGFloat = 0
        for frontFrame in sameAppFramesInFront {
            let intersection = newFrame.intersection(frontFrame)
            if !intersection.isNull {
                coveredArea += intersection.width * intersection.height
            }
        }

        // Consider the window "occluded" if more than 5% is covered.
        return coveredArea / targetArea > 0.05
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
        var seenPIDs = Set<pid_t>()
        var orderedPIDs: [pid_t] = []
        for entry in cgEntries {
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
                screenFrame: screenFrame
            )
            results.append(target)
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
