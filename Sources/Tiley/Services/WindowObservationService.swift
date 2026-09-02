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
        /// The window moved / resized. No frame is carried: reading it back
        /// costs two synchronous Accessibility round-trips into the app that
        /// is busy dragging, for every event, and consumers that need the
        /// live frame read it themselves (only on the rare paths that do).
        case moved(CGWindowID)
        case resized(CGWindowID)
        case destroyed(CGWindowID)
        case raised(CGWindowID)
        /// The focused/main window of the given app changed. Fires regardless
        /// of whether the new focused window is in our observed map — used to
        /// react to sheets/dialogs appearing or being dismissed.
        case focusChanged(pid_t)
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
    /// Last `.raised` dispatch, used to collapse the focused-window and
    /// main-window notifications that macOS fires together for one click.
    private var lastRaiseDispatch: (pid: pid_t, time: CFAbsoluteTime)?
    private static let raiseCoalesceWindow: CFAbsoluteTime = 0.05

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

        // refcon points to self so the C callback can dispatch back.
        let refcon = Unmanaged.passUnretained(self).toOpaque()

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

            // Focus/Main-window-change notifications are attached to the app
            // element, so register them once per observer (i.e. per app) —
            // registering per window only produced
            // `kAXErrorNotificationAlreadyRegistered` round-trips for every
            // additional window of the same app.
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

        let entry = ObservedEntry(cgWindowID: cgID, pid: pid, appElement: target.appElement, windowElement: window)
        entriesByWindowID[cgID] = entry
        windowIDByAXElement[AXUIElementBox(element: window)] = cgID
        observerRefCount[pid, default: 0] += 1

        // Window-level notifications are attached to the window element.
        let windowNotifications: [CFString] = [
            kAXWindowMovedNotification as CFString,
            kAXWindowResizedNotification as CFString,
            kAXUIElementDestroyedNotification as CFString,
        ]
        for note in windowNotifications {
            AXObserverAddNotification(observer, window, note, refcon)
        }
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
            // `element` here is the app element.
            var pid: pid_t = 0
            let havePID = AXUIElementGetPid(element, &pid) == .success

            // One click fires both the focused-window and the main-window
            // notification. If a `.raised` was just dispatched for this app,
            // skip the second attribute read (a synchronous round-trip into
            // the app that is mid-activation) and the duplicate dispatch,
            // which otherwise ran the whole raise linkage twice.
            let now = CFAbsoluteTimeGetCurrent()
            let isDuplicateRaise = havePID
                && lastRaiseDispatch.map { $0.pid == pid && now - $0.time < Self.raiseCoalesceWindow } == true
            if !isDuplicateRaise {
                // Fetch the current main/focused window. Prefer Main for
                // intra-app clicks (fires even when app was already active),
                // fallback to Focused.
                let attr: CFString = (note == kAXMainWindowChangedNotification as String)
                    ? (kAXMainWindowAttribute as CFString)
                    : (kAXFocusedWindowAttribute as CFString)
                var target: CFTypeRef?
                let err = AXUIElementCopyAttributeValue(element, attr, &target)
                if err == .success, let targetCF = target, CFGetTypeID(targetCF) == AXUIElementGetTypeID() {
                    let windowElement = targetCF as! AXUIElement
                    if let cgID = windowIDByAXElement[AXUIElementBox(element: windowElement)] {
                        if havePID { lastRaiseDispatch = (pid, now) }
                        onEvent?(.raised(cgID))
                    }
                }
            }
            // Always fire a generic focus-changed event so listeners can react
            // even when the new focused element isn't a window we observe
            // (notably: sheets and modal dialogs the app just presented).
            if havePID {
                onEvent?(.focusChanged(pid))
            }
            return
        }

        guard let cgID = windowIDByAXElement[AXUIElementBox(element: element)] else { return }

        switch note {
        case kAXWindowMovedNotification as String, kAXWindowResizedNotification as String:
            guard entriesByWindowID[cgID] != nil else { return }
            if note == kAXWindowMovedNotification as String {
                onEvent?(.moved(cgID))
            } else {
                onEvent?(.resized(cgID))
            }
        case kAXUIElementDestroyedNotification as String:
            onEvent?(.destroyed(cgID))
            stopObserving(cgWindowID: cgID)
        default:
            break
        }
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
