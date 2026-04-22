import AppKit
import ApplicationServices

/// Wraps `AXObserver` to detect window move / resize / destroy / focus-change events
/// for specific windows and deliver them via a closure.
///
/// Only windows passed to `observe(target:)` are observed. They can be released
/// via `stopObserving(cgWindowID:)` or `stopAll()`.
///
/// The `onEvent` callback is always invoked on the main thread, because the
/// AXObserver's run-loop source is attached to the main runloop.
@MainActor
final class WindowObservationService {
    enum Event {
        case moved(CGWindowID, CGRect)
        case resized(CGWindowID, CGRect)
        case destroyed(CGWindowID)
        case raised(CGWindowID)
    }

    var onEvent: ((Event) -> Void)?

    private struct ObservedEntry {
        let cgWindowID: CGWindowID
        let pid: pid_t
        let appElement: AXUIElement
        let windowElement: AXUIElement
    }

    /// One AXObserver is shared per PID (all windows of the same app share an observer).
    private var observersByPID: [pid_t: AXObserver] = [:]
    /// Number of observed windows per PID. When it drops to 0 the observer is torn down.
    private var observerRefCount: [pid_t: Int] = [:]
    /// Reverse lookup: CGWindowID → observed entry.
    private var entriesByWindowID: [CGWindowID: ObservedEntry] = [:]
    /// Reverse lookup: AXUIElement → CGWindowID (used inside the C callback to
    /// identify which window fired the event).
    private var windowIDByAXElement: [AXUIElementBox: CGWindowID] = [:]

    /// Wrapper that lets an AXUIElement be used as a Hashable dictionary key.
    private struct AXUIElementBox: Hashable {
        let element: AXUIElement
        func hash(into hasher: inout Hasher) {
            hasher.combine(CFHash(element))
        }
        static func == (lhs: AXUIElementBox, rhs: AXUIElementBox) -> Bool {
            CFEqual(lhs.element, rhs.element)
        }
    }

    // MARK: - Public API

    func observe(target: WindowTarget) {
        guard let window = target.windowElement else { return }
        let pid = target.processIdentifier
        let cgID = target.cgWindowID

        if entriesByWindowID[cgID] != nil { return }  // already observing

        // Create or reuse observer for this PID.
        let observer: AXObserver
        if let existing = observersByPID[pid] {
            observer = existing
        } else {
            var newObserver: AXObserver?
            let err = AXObserverCreate(pid, Self.observerCallback, &newObserver)
            guard err == .success, let created = newObserver else {
                debugLog("WindowObservationService: AXObserverCreate failed for pid=\(pid) err=\(err.rawValue)")
                return
            }
            observer = created
            observersByPID[pid] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }

        let entry = ObservedEntry(cgWindowID: cgID, pid: pid, appElement: target.appElement, windowElement: window)
        entriesByWindowID[cgID] = entry
        windowIDByAXElement[AXUIElementBox(element: window)] = cgID
        observerRefCount[pid, default: 0] += 1

        // refcon points to self so the C callback can dispatch back.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // Window-level notifications are attached to the window element.
        let windowNotifications: [CFString] = [
            kAXWindowMovedNotification as CFString,
            kAXWindowResizedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
        ]
        for note in windowNotifications {
            AXObserverAddNotification(observer, window, note, refcon)
        }

        // Focus/Main-window-change notifications are attached to the app element.
        // Both are needed to cover different scenarios:
        //   - kAXFocusedWindowChangedNotification: window focus changes (app activation)
        //   - kAXMainWindowChangedNotification: main window changes (intra-app clicks when
        //     app is already active — e.g., clicking another window of the same app)
        AXObserverAddNotification(
            observer,
            target.appElement,
            kAXFocusedWindowChangedNotification as CFString,
            refcon
        )
        AXObserverAddNotification(
            observer,
            target.appElement,
            kAXMainWindowChangedNotification as CFString,
            refcon
        )
    }

    func stopObserving(cgWindowID: CGWindowID) {
        guard let entry = entriesByWindowID.removeValue(forKey: cgWindowID) else { return }
        windowIDByAXElement.removeValue(forKey: AXUIElementBox(element: entry.windowElement))

        if let observer = observersByPID[entry.pid] {
            AXObserverRemoveNotification(observer, entry.windowElement, kAXWindowMovedNotification as CFString)
            AXObserverRemoveNotification(observer, entry.windowElement, kAXWindowResizedNotification as CFString)
            AXObserverRemoveNotification(observer, entry.windowElement, kAXUIElementDestroyedNotification as CFString)

            observerRefCount[entry.pid, default: 0] -= 1
            if observerRefCount[entry.pid, default: 0] <= 0 {
                AXObserverRemoveNotification(observer, entry.appElement, kAXFocusedWindowChangedNotification as CFString)
                AXObserverRemoveNotification(observer, entry.appElement, kAXMainWindowChangedNotification as CFString)
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
                observersByPID.removeValue(forKey: entry.pid)
                observerRefCount.removeValue(forKey: entry.pid)
            }
        }
    }

    func stopAll() {
        for id in Array(entriesByWindowID.keys) {
            stopObserving(cgWindowID: id)
        }
    }

    // MARK: - Callback dispatch

    /// Called from the C trampoline on the main runloop.
    fileprivate func handleCallback(element: AXUIElement, notification: CFString) {
        let note = notification as String

        if note == kAXFocusedWindowChangedNotification as String
            || note == kAXMainWindowChangedNotification as String {
            // `element` here is the app element. Fetch the current main/focused window.
            // Prefer Main for intra-app clicks (fires even when app was already active),
            // fallback to Focused.
            let attr: CFString = (note == kAXMainWindowChangedNotification as String)
                ? (kAXMainWindowAttribute as CFString)
                : (kAXFocusedWindowAttribute as CFString)
            var target: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(element, attr, &target)
            if err == .success, let targetCF = target, CFGetTypeID(targetCF) == AXUIElementGetTypeID() {
                let windowElement = targetCF as! AXUIElement
                if let cgID = windowIDByAXElement[AXUIElementBox(element: windowElement)] {
                    onEvent?(.raised(cgID))
                }
            }
            return
        }

        guard let cgID = windowIDByAXElement[AXUIElementBox(element: element)] else { return }

        switch note {
        case kAXWindowMovedNotification as String, kAXWindowResizedNotification as String:
            guard let entry = entriesByWindowID[cgID] else { return }
            let frame = currentFrame(of: entry.windowElement)
            if note == kAXWindowMovedNotification as String {
                onEvent?(.moved(cgID, frame))
            } else {
                onEvent?(.resized(cgID, frame))
            }
        case kAXUIElementDestroyedNotification as String:
            onEvent?(.destroyed(cgID))
            stopObserving(cgWindowID: cgID)
        default:
            break
        }
    }

    /// Returns the current frame of the window in AppKit coordinates (bottom-left origin).
    private func currentFrame(of window: AXUIElement) -> CGRect {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
        var axPos = CGPoint.zero
        var axSize = CGSize.zero
        if let posVal = posRef, CFGetTypeID(posVal) == AXValueGetTypeID() {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &axPos)
        }
        if let sizeVal = sizeRef, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &axSize)
        }
        // Convert AX (top-left origin, primary screen) to AppKit (bottom-left).
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(
            x: axPos.x,
            y: primaryMaxY - axPos.y - axSize.height,
            width: axSize.width,
            height: axSize.height
        )
    }

    // MARK: - C callback trampoline

    /// Must be a free @convention(c) function (no captures).
    private static let observerCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon = refcon else { return }
        let service = Unmanaged<WindowObservationService>.fromOpaque(refcon).takeUnretainedValue()
        MainActor.assumeIsolated {
            service.handleCallback(element: element, notification: notification)
        }
    }
}
