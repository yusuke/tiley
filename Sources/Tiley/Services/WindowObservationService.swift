import AppKit
import ApplicationServices

/// AXObserver をラップして、特定ウインドウの移動・リサイズ・破棄・フォーカス変更を
/// 検知し、closure 形式でイベントを配信するサービス。
///
/// 観察対象は `observe(target:)` で指定されたウインドウのみ。
/// `stopObserving(cgWindowID:)` または `stopAll()` で解除できる。
///
/// `onEvent` コールバックは常にメインスレッドで呼ばれる（AXObserver の runloop は
/// main runloop に追加されているため）。
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

    /// PID ごとに 1 つの AXObserver を共有する（同一アプリの複数ウインドウは同じ observer）。
    private var observersByPID: [pid_t: AXObserver] = [:]
    /// PID ごとの観察対象ウインドウ数（0 になったら observer を破棄）。
    private var observerRefCount: [pid_t: Int] = [:]
    /// CGWindowID → 観察エントリの逆引き。
    private var entriesByWindowID: [CGWindowID: ObservedEntry] = [:]
    /// AXUIElement → CGWindowID の逆引き（コールバック内で CGWindowID を特定するため）。
    private var windowIDByAXElement: [AXUIElementBox: CGWindowID] = [:]

    /// AXUIElement を Hashable なキーとして扱うためのラッパ。
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

        if entriesByWindowID[cgID] != nil { return }  // 既に観察中

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

    /// AppKit 座標（bottom-left 原点）でウインドウの現フレームを返す。
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
