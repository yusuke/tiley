import AppKit
import Carbon
import Observation
import SwiftUI

@Observable
final class ScreenState {
    var context: ScreenContext
    var role: ScreenRole

    init(context: ScreenContext, role: ScreenRole) {
        self.context = context
        self.role = role
    }
}

private struct MainWindowRootView: View {
    let appState: AppState
    var screenState: ScreenState

    var body: some View {
        MainWindowView(appState: appState, screenRole: screenState.role)
            .environment(\.screenContext, screenState.context)
    }
}

final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let windowWidth: CGFloat = 570
    static let sidebarWidth: CGFloat = 220
    private static let minimumWindowHeight: CGFloat = 780
    private static let extraWindowHeight: CGFloat = 55
    private static let visibleFrameInset: CGFloat = 16
    private static let layoutPanelHorizontalPadding: CGFloat = 28
    private static let layoutGridAspectHeightRatio: CGFloat = 0.75
    private static let layoutPresetsHeaderHeight: CGFloat = 42
    private static let layoutPresetRowHeight: CGFloat = 44
    private static let layoutPresetRowSpacing: CGFloat = 8
    private static let footerHeight: CGFloat = 44
    private static let contentVerticalPadding: CGFloat = 102
    private static let layoutModeWindowAlpha: CGFloat = 0.99
    private static let fadeDuration: CFTimeInterval = 0.18

    private weak var appState: AppState?
    private(set) var screenRole: ScreenRole
    private(set) var targetScreen: NSScreen
    private let screenState: ScreenState
    private let onHide: () -> Void
    private let onEscape: () -> Bool
    private let onLocalShortcut: (HotKeyShortcut) -> Bool
    private let onKeyCommand: (NSEvent) -> Bool
    private var screenParameterTask: Task<Void, Never>?
    private var isHidingWindow = false
    private static let fadeInKey = "tileyFadeIn"
    private static let fadeOutKey = "tileyFadeOut"
    private var fadeOutGeneration: UInt = 0

    init(appState: AppState, screenRole: ScreenRole = .target, targetScreen: NSScreen? = nil, onHide: @escaping () -> Void, onEscape: @escaping () -> Bool, onLocalShortcut: @escaping (HotKeyShortcut) -> Bool, onKeyCommand: @escaping (NSEvent) -> Bool) {
        let perfStart = CFAbsoluteTimeGetCurrent()
        func perfLog(_ label: String) {
            let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
            debugLog("MainWindowController.init: \(label) (t=\(String(format: "%.1f", elapsed))ms)")
        }
        self.appState = appState
        self.screenRole = screenRole
        self.targetScreen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first!
        self.onHide = onHide
        self.onEscape = onEscape
        self.onLocalShortcut = onLocalShortcut
        self.onKeyCommand = onKeyCommand
        let initialVisibleFrame = self.targetScreen.visibleFrame
        let initialScreenFrame = self.targetScreen.frame
        let initialSize = Self.windowSize(for: appState, visibleFrame: initialVisibleFrame, screenFrame: initialScreenFrame, screenRole: screenRole)
        let screenContext = ScreenContext(
            visibleFrame: self.targetScreen.visibleFrame,
            screenFrame: self.targetScreen.frame,
            notchWidth: Self.notchWidth(for: self.targetScreen)
        )
        self.screenState = ScreenState(context: screenContext, role: screenRole)
        perfLog("windowSize + screenContext")
        let view = MainWindowRootView(appState: appState, screenState: screenState)
        perfLog("MainWindowRootView created")
        let hostingView = FirstMouseHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]
        perfLog("NSHostingView created")

        let window = MainAppWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        perfLog("MainAppWindow created")
        window.title = "Tiley"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = Self.layoutModeWindowAlpha
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.isMovable = false
        // Start at normal level; AppState promotes to .floating via applyWindowLevel().
        window.level = .normal
        let displayID = self.targetScreen.displayID
        window.identifier = NSUserInterfaceItemIdentifier("main-window-\(displayID)")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = false
        hostingView.wantsLayer = true
        window.contentView = hostingView
        perfLog("contentView set")
        // Only use autosave for the target window to avoid position conflicts
        if screenRole.isTarget {
            window.setFrameAutosaveName("TileyMainWindow")
        }
        window.hideHandler = onHide
        window.escapeHandler = onEscape
        window.localShortcutHandler = onLocalShortcut
        window.keyCommandHandler = onKeyCommand
        window.cmdFHandler = { [weak appState] _ in
            appState?.windowSearchFocusRequestVersion += 1
        }

        super.init(window: window)
        window.delegate = self
        perfLog("super.init done")
        bindWindowMode(to: appState)
        perfLog("bindWindowMode done")
        bindScreenParameterChanges()
        perfLog("bindScreenParameterChanges done")
        applyWindowMode(animated: false)
        perfLog("applyWindowMode done")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(asKey: Bool = true) {
        let perfStart = CFAbsoluteTimeGetCurrent()
        let destinationScreen = preferredDisplayScreen(for: window)
        applyWindowMode(animated: false, preferredScreen: destinationScreen)
        positionWindow(preferredScreen: destinationScreen)
        window?.ignoresMouseEvents = false
        window?.alphaValue = Self.layoutModeWindowAlpha
        // Invalidate any in-progress fade-out so its completion won't reset state.
        fadeOutGeneration &+= 1
        isHidingWindow = false
        if window?.isVisible == true {
            if asKey {
                window?.makeKey()
            }
        } else {
            if asKey {
                window?.makeKeyAndOrderFront(nil)
            } else {
                window?.orderFront(nil)
            }
        }
        // GPU-accelerated fade-in via Core Animation on the content view layer.
        startLayerFadeIn(duration: Self.fadeDuration)
        // Prevent the search field from auto-focusing when the window opens.
        window?.makeFirstResponder(window?.contentView)
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("MainWindowController.show done asKey=\(asKey ? 1 : 0) preRendered=\(window?.isVisible == true ? 1 : 0) (\(String(format: "%.1f", elapsed))ms)")
    }

    func hide() {
        guard !isHidingWindow else { return }
        isHidingWindow = true
        window?.ignoresMouseEvents = true
        // GPU-accelerated fade-out, then finalize state cleanup.
        // All state changes (hidePreviewOverlay, onHide, level demotion)
        // are deferred to the completion so the UI stays intact during fade.
        fadeOutGeneration &+= 1
        let gen = fadeOutGeneration
        startLayerFadeOut(duration: Self.fadeDuration) { [weak self] in
            guard let self, self.fadeOutGeneration == gen else { return }
            self.appState?.hidePreviewOverlay()
            self.window?.level = .normal
            self.onHide()
            self.isHidingWindow = false
        }
    }

    // MARK: - Fade-in animation

    private func startLayerFadeIn(duration: CFTimeInterval) {
        guard let layer = window?.contentView?.layer else { return }
        layer.removeAnimation(forKey: Self.fadeInKey)
        layer.removeAnimation(forKey: Self.fadeOutKey)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = Float(0)
        anim.toValue = Float(1)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = true
        layer.opacity = 1
        layer.add(anim, forKey: Self.fadeInKey)
    }

    private func startLayerFadeOut(duration: CFTimeInterval, completion: @escaping () -> Void) {
        guard let layer = window?.contentView?.layer else {
            completion()
            return
        }
        layer.removeAnimation(forKey: Self.fadeInKey)
        layer.removeAnimation(forKey: Self.fadeOutKey)
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = layer.presentation()?.opacity ?? layer.opacity
        anim.toValue = Float(0)
        anim.duration = duration
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.opacity = 0
        layer.add(anim, forKey: Self.fadeOutKey)
        CATransaction.commit()
    }

    /// Update the controller's screen state for reuse without recreating the
    /// window or hosting view.  SwiftUI picks up the `ScreenState` changes via
    /// `@Observable` and performs a lightweight diff instead of a full init.
    func prepareForReuse(screenRole: ScreenRole, targetScreen: NSScreen) {
        let perfStart = CFAbsoluteTimeGetCurrent()
        self.screenRole = screenRole
        self.targetScreen = targetScreen
        let newContext = ScreenContext(
            visibleFrame: targetScreen.visibleFrame,
            screenFrame: targetScreen.frame,
            notchWidth: Self.notchWidth(for: targetScreen)
        )
        screenState.context = newContext
        screenState.role = screenRole
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("MainWindowController.prepareForReuse (\(String(format: "%.1f", elapsed))ms)")
    }

    /// Dismiss the window without firing the onHide callback.
    /// Used when recreating window controllers to avoid triggering state resets.
    /// Keeps the window on screen (layer opacity=0) for instant re-show.
    func dismissSilently() {
        window?.contentView?.layer?.removeAnimation(forKey: Self.fadeInKey)
        window?.contentView?.layer?.opacity = 0
        window?.ignoresMouseEvents = true
        window?.level = .normal
    }

    /// Fully remove the window from screen. Use when the controller is about
    /// to be discarded (e.g. screen configuration change).
    func teardown() {
        window?.orderOut(nil)
    }

    /// Whether the window is logically visible to the user.
    /// Note: after hide()/dismissSilently() the window remains on screen
    /// with ignoresMouseEvents=true, so NSWindow.isVisible alone is unreliable.
    var isVisible: Bool {
        guard let window else { return false }
        return window.isVisible && !window.ignoresMouseEvents
    }

    var nsWindow: NSWindow? {
        window
    }

    func windowWillClose(_ notification: Notification) {
        onHide()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep the main window visible when focus moves to another Tiley-owned
        // window (e.g. a secondary-screen MainWindow or the About dialog).
        guard !NSApp.isActive else { return }
        // During window controller recreation (e.g. switching from layout grid
        // to settings mode), the old key window is ordered out which triggers
        // this callback. Suppress state resets so the new mode is preserved.
        guard appState?.isRecreatingWindows != true else { return }
        // During activation-policy switches (e.g. toggling the Dock icon),
        // macOS deactivates the app and fires this callback. Don't hide
        // windows — they will be restored after the switch completes.
        guard appState?.isSwitchingActivationPolicy != true else { return }
        // Hide all Tiley windows when the app loses focus, not just this one.
        // Don't call hidePreviewOverlay() here — hide() defers all state
        // cleanup to its fade-out completion so the UI stays intact.
        appState?.hideMainWindow()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        applyWindowMode(animated: false)
        positionWindow()
    }

    private func bindWindowMode(to appState: AppState) {
        observeWindowModeChanges(appState)
    }

    private func observeWindowModeChanges(_ appState: AppState) {
        withObservationTracking {
            _ = appState.layoutPresets
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.applyWindowMode(animated: true)
                if let appState = self?.appState {
                    self?.observeWindowModeChanges(appState)
                }
            }
        }
    }

    private func bindScreenParameterChanges() {
        screenParameterTask = Task { [weak self] in
            let notifications = NotificationCenter.default.notifications(
                named: NSApplication.didChangeScreenParametersNotification
            )
            for await _ in notifications {
                guard !Task.isCancelled else { break }
                await MainActor.run { self?.relayoutForScreenConfigurationChange() }
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { break }
                await MainActor.run { self?.relayoutForScreenConfigurationChange() }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { break }
                await MainActor.run { self?.relayoutForScreenConfigurationChange() }
            }
        }
    }

    deinit {
        screenParameterTask?.cancel()
    }

    private func relayoutForScreenConfigurationChange() {
        guard let window else { return }
        let resolvedScreen = screenContainingWindowCenter(window) ?? window.screen
        applyWindowMode(animated: false, preferredScreen: resolvedScreen)
        positionWindow(preferredScreen: resolvedScreen)
    }

    private func applyWindowMode(animated: Bool, preferredScreen: NSScreen? = nil) {
        guard let window else { return }
        let visibleFrame = currentVisibleFrame(for: window, preferredScreen: preferredScreen)
        let screenFrame = currentScreenFrame(for: window, preferredScreen: preferredScreen)
        let targetSize = Self.windowSize(for: appState, visibleFrame: visibleFrame, screenFrame: screenFrame, screenRole: screenRole)

        var frame = window.frame
        frame.size = targetSize
        // Preserve the current origin so icon-anchored positioning isn't lost when
        // the size changes (e.g. on layoutPresets edits). Callers that need fresh
        // positioning invoke positionWindow() afterwards. Clamp to the visible frame
        // so a size increase doesn't push the window off-screen.
        let maxOriginX = max(visibleFrame.minX, visibleFrame.maxX - targetSize.width)
        let maxOriginY = max(visibleFrame.minY, visibleFrame.maxY - targetSize.height)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX), maxOriginX)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY), maxOriginY)

        let sizeChanged = window.minSize != targetSize || window.maxSize != targetSize
        let frameChanged = !window.frame.equalTo(frame)

        guard sizeChanged || frameChanged else { return }

        window.minSize = targetSize
        window.maxSize = targetSize
        if frameChanged {
            window.setFrame(frame, display: true, animate: animated)
        }
    }

    private func positionWindow(preferredScreen: NSScreen? = nil) {
        guard let window else { return }
        let visibleFrame = currentVisibleFrame(for: window, preferredScreen: preferredScreen)
        guard !visibleFrame.equalTo(.zero) else { return }
        let screenFrame = currentScreenFrame(for: window, preferredScreen: preferredScreen)
        let targetSize = Self.windowSize(for: appState, visibleFrame: visibleFrame, screenFrame: screenFrame, screenRole: screenRole)

        let screen = preferredScreen ?? window.screen ?? NSScreen.main
        if let appState, appState.showNearIcon,
           let iconCenter = appState.triggerIconCenter,
           let iconDisplayID = appState.triggerIconDisplayID,
           screen?.displayID == iconDisplayID {
            let origin = iconAnchoredOrigin(for: targetSize, iconCenter: iconCenter, visibleFrame: visibleFrame, screenFrame: screenFrame)
            window.setFrameOrigin(origin)
            // Compute bubble arrow edge and fraction for the SwiftUI clip shape.
            computeBubbleArrow(origin: origin, size: targetSize, iconCenter: iconCenter, visibleFrame: visibleFrame)
            appState.triggerIconCenter = nil
            appState.triggerIconDisplayID = nil
        } else {
            // Do NOT clear appState.bubbleArrowEdge here — with multiple displays,
            // another controller (the one on the icon's display) may have just
            // set it. AppState.toggleOverlay() resets it at the start of each
            // open cycle, so we only need to set it in the if-branch above.
            let origin = calculatedOrigin(for: targetSize, visibleFrame: visibleFrame, screenFrame: screenFrame)
            window.setFrameOrigin(origin)
        }
    }

    /// Compute window origin anchored near a trigger icon (menu bar or Dock).
    /// The icon position relative to the visible frame determines the edge:
    /// - Above visibleFrame → menu bar icon → window hangs below icon
    /// - Below visibleFrame → Dock at bottom → window sits above Dock
    /// - Left/right of visibleFrame → Dock on side → window beside Dock
    private func iconAnchoredOrigin(for size: NSSize, iconCenter: NSPoint, visibleFrame: CGRect, screenFrame: CGRect) -> NSPoint {
        let margin: CGFloat = 4
        var originX: CGFloat
        var originY: CGFloat

        if iconCenter.y >= visibleFrame.maxY {
            // Menu bar icon (above visible frame) — window hangs below icon.
            // Shift left so the miniature screen (right panel) is centered
            // on the icon, not the whole window. The bubble-arrow triangle
            // still lands directly below the icon because computeBubbleArrow
            // derives its fraction from (iconCenter.x - origin.x).
            let contentOffset = (Self.sidebarWidth + 1) / 2
            originX = iconCenter.x - size.width / 2 - contentOffset
            originY = visibleFrame.maxY - size.height - margin
        } else if iconCenter.y <= visibleFrame.minY {
            // Dock at bottom — window sits just above Dock
            originX = iconCenter.x - size.width / 2
            originY = visibleFrame.minY + margin
        } else if iconCenter.x >= visibleFrame.maxX {
            // Dock on right — window to the left of Dock
            originX = visibleFrame.maxX - size.width - margin
            originY = iconCenter.y - size.height / 2
        } else {
            // Dock on left — window to the right of Dock
            originX = visibleFrame.minX + margin
            originY = iconCenter.y - size.height / 2
        }

        // Clamp to visible frame
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - size.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - size.height
        originX = min(max(originX, minX), maxX)
        originY = min(max(originY, minY), maxY)
        return NSPoint(x: originX, y: originY)
    }

    /// Determine which edge the bubble arrow should appear on and where along that edge,
    /// based on the final window origin and the icon center in screen coordinates.
    /// AppKit Y is bottom-up; SwiftUI Y is top-down, so vertical fractions are flipped.
    private func computeBubbleArrow(origin: NSPoint, size: NSSize, iconCenter: NSPoint, visibleFrame: CGRect) {
        guard let appState else { return }
        let edge: BubbleArrowEdge
        var fraction: CGFloat

        if iconCenter.y >= visibleFrame.maxY {
            // Menu bar — arrow on the top edge (SwiftUI top = AppKit maxY)
            edge = .top
            fraction = (iconCenter.x - origin.x) / size.width
        } else if iconCenter.y <= visibleFrame.minY {
            // Dock at bottom — arrow on the bottom edge
            edge = .bottom
            fraction = (iconCenter.x - origin.x) / size.width
        } else if iconCenter.x >= visibleFrame.maxX {
            // Dock on right — arrow on the trailing edge
            edge = .trailing
            // AppKit Y is bottom-up; SwiftUI fraction from top
            fraction = 1.0 - (iconCenter.y - origin.y) / size.height
        } else {
            // Dock on left — arrow on the leading edge
            edge = .leading
            fraction = 1.0 - (iconCenter.y - origin.y) / size.height
        }
        fraction = min(max(fraction, 0.1), 0.9)
        appState.bubbleArrowEdge = edge
        appState.bubbleArrowFraction = fraction
        appState.bubbleArrowDisplayID = targetScreen.displayID
    }

    private func currentVisibleFrame(for window: NSWindow, preferredScreen: NSScreen? = nil) -> CGRect {
        // Secondary screens always use their assigned screen's visible frame.
        if !screenRole.isTarget {
            let frame = targetScreen.visibleFrame
            if !frame.equalTo(.zero) { return frame }
        }
        if let targetVisibleFrame = appState?.preferredMainWindowVisibleFrame,
           !targetVisibleFrame.equalTo(.zero) {
            return targetVisibleFrame
        }
        if let preferredScreen {
            let screenFrame = preferredScreen.visibleFrame
            if !screenFrame.equalTo(.zero) {
                return screenFrame
            }
        }
        if let screenFrame = window.screen?.visibleFrame, !screenFrame.equalTo(.zero) {
            return screenFrame
        }
        if let mainFrame = NSScreen.main?.visibleFrame, !mainFrame.equalTo(.zero) {
            return mainFrame
        }
        if let anyFrame = NSScreen.screens.first?.visibleFrame, !anyFrame.equalTo(.zero) {
            return anyFrame
        }
        return .zero
    }

    /// Returns the notch width for the given screen (0 if no notch).
    /// On notched Macs, auxiliaryTopLeftArea and auxiliaryTopRightArea are non-nil;
    /// the notch occupies the space between them.
    private static func notchWidth(for screen: NSScreen) -> CGFloat {
        guard let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            return 0
        }
        // notch spans from the right edge of the left auxiliary area
        // to the left edge of the right auxiliary area
        let notchLeft = leftArea.maxX
        let notchRight = rightArea.minX
        return max(0, notchRight - notchLeft)
    }

    /// Returns the full screen frame (including menu bar and Dock) for the window's screen.
    private func currentScreenFrame(for window: NSWindow, preferredScreen: NSScreen? = nil) -> CGRect {
        if !screenRole.isTarget {
            let frame = targetScreen.frame
            if !frame.equalTo(.zero) { return frame }
        }
        if let preferredScreen {
            let frame = preferredScreen.frame
            if !frame.equalTo(.zero) { return frame }
        }
        if let frame = window.screen?.frame, !frame.equalTo(.zero) {
            return frame
        }
        if let frame = NSScreen.main?.frame, !frame.equalTo(.zero) {
            return frame
        }
        if let frame = NSScreen.screens.first?.frame, !frame.equalTo(.zero) {
            return frame
        }
        return .zero
    }

    private func preferredDisplayScreen(for window: NSWindow?) -> NSScreen? {
        // Secondary screens always display on their assigned screen.
        if !screenRole.isTarget {
            return targetScreen
        }
        guard let window else { return NSScreen.main ?? NSScreen.screens.first }
        if let targetScreenFrame = appState?.preferredMainWindowScreenFrame,
           let targetScreen = NSScreen.screen(containing: targetScreenFrame) {
            return targetScreen
        }

        if let screen = window.screen {
            return screen
        }

        let windowCenter = NSPoint(x: window.frame.midX, y: window.frame.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(windowCenter) }) {
            return containingScreen
        }

        let mouseLocation = NSEvent.mouseLocation
        if let mouseScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return mouseScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func screenContainingWindowCenter(_ window: NSWindow) -> NSScreen? {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private static func windowSize(for appState: AppState?, visibleFrame: CGRect?, screenFrame: CGRect? = nil, screenRole: ScreenRole = .target) -> NSSize {
        let totalWidth = windowWidth + sidebarWidth + 1
        let presetCount = CGFloat(appState?.displayedLayoutPresets.count ?? 0)
        let maxHeight = maxAllowedHeight(in: visibleFrame)

        // Use the full screen frame aspect ratio so the composite area (menu bar + grid + Dock)
        // matches the screen's proportions. Falls back to visibleFrame or default.
        let aspectRatio: CGFloat
        if let sf = screenFrame, sf.width > 0 {
            aspectRatio = sf.height / sf.width
        } else if let vf = visibleFrame, vf.width > 0 {
            aspectRatio = vf.height / vf.width
        } else {
            aspectRatio = layoutGridAspectHeightRatio
        }

        // Minimum height needed to show at least 4 preset rows plus all chrome.
        let minPresetCount: CGFloat = min(presetCount, 4)
        let minPresetsHeight = minPresetCount * layoutPresetRowHeight
            + max(0, minPresetCount - 1) * layoutPresetRowSpacing
        let minNonGridHeight = contentVerticalPadding + footerHeight + layoutPresetsHeaderHeight + minPresetsHeight

        // Maximum grid height that still leaves room for 4 presets within maxHeight.
        let maxGridHeight = maxHeight - extraWindowHeight - minNonGridHeight
        let fullGridWidth = windowWidth - (layoutPanelHorizontalPadding * 2)
        let fullGridHeight = fullGridWidth * aspectRatio
        // If grid would be too tall, shrink width to fit (keeping aspect ratio).
        let gridHeight = min(fullGridHeight, max(0, maxGridHeight))

        let layoutRowsHeight = presetCount * layoutPresetRowHeight
        let layoutSpacingHeight = max(0, presetCount - 1) * layoutPresetRowSpacing
        let layoutHeight = contentVerticalPadding
            + gridHeight
            + footerHeight
            + layoutPresetsHeaderHeight
            + layoutRowsHeight
            + layoutSpacingHeight
        let idealHeight = max(minimumWindowHeight, layoutHeight) + extraWindowHeight
        let height = min(idealHeight, maxHeight)
        return NSSize(width: totalWidth, height: height)
    }

    /// Returns the size that the main (grid) window would use for the given frames.
    static func mainWindowSize(for appState: AppState, visibleFrame: CGRect, screenFrame: CGRect) -> NSSize {
        windowSize(for: appState, visibleFrame: visibleFrame, screenFrame: screenFrame)
    }

    private static func maxAllowedHeight(in visibleFrame: CGRect?) -> CGFloat {
        guard let visibleFrame else { return minimumWindowHeight + extraWindowHeight }
        guard !visibleFrame.equalTo(.zero) else { return minimumWindowHeight + extraWindowHeight }
        return max(1, visibleFrame.height - visibleFrameInset)
    }

    private func calculatedOrigin(for size: NSSize, visibleFrame: CGRect, screenFrame: CGRect) -> NSPoint {
        // Shift left so the miniature screen (right panel) center aligns with
        // the display center, instead of the whole window center.
        // Use screenFrame (not visibleFrame) as the reference so the miniature
        // — which represents the full screen including menu bar/Dock chrome —
        // is centered on the actual display, not on the Dock-excluded area.
        let referenceFrame = screenFrame.equalTo(.zero) ? visibleFrame : screenFrame
        let contentOffset = (Self.sidebarWidth + 1) / 2
        let originX = referenceFrame.midX - size.width / 2 - contentOffset
        let originY = visibleFrame.midY - size.height / 2
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - size.width
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - size.height

        let clampedX = min(max(originX, minX), maxX)
        let clampedY = min(max(originY, minY), maxY)
        return NSPoint(x: clampedX, y: clampedY)
    }
}

private final class MainAppWindow: NSWindow {
    /// Width of the edge zone that allows window dragging.
    private static let edgeDragInset: CGFloat = 6

    var hideHandler: (() -> Void)?
    var escapeHandler: (() -> Bool)?
    var localShortcutHandler: ((HotKeyShortcut) -> Bool)?
    var keyCommandHandler: ((NSEvent) -> Bool)?
    /// Called when Cmd+F is pressed. Bool parameter: true if a text field is focused.
    var cmdFHandler: ((_ textFieldFocused: Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Custom window dragging

    /// Manually track the mouse to drag the window.  This bypasses
    /// `isMovable` / `isMovableByWindowBackground` entirely, so it works
    /// even when both are `false`.
    func beginManualDrag(with event: NSEvent) {
        let initialMouseScreen = NSEvent.mouseLocation
        let initialOrigin = frame.origin

        while true {
            guard let next = nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else { break }
            if next.type == .leftMouseUp { break }
            let currentMouseScreen = NSEvent.mouseLocation
            let dx = currentMouseScreen.x - initialMouseScreen.x
            let dy = currentMouseScreen.y - initialMouseScreen.y
            setFrameOrigin(NSPoint(x: initialOrigin.x + dx, y: initialOrigin.y + dy))
        }
    }

    /// When no other view consumed the event and it falls through to the
    /// window, allow dragging only from the thin edge zone.
    override func mouseDown(with event: NSEvent) {
        let loc = event.locationInWindow
        let size = frame.size
        let d = Self.edgeDragInset
        let nearEdge = loc.x < d || loc.x > size.width - d
            || loc.y < d || loc.y > size.height - d
        if nearEdge {
            beginManualDrag(with: event)
        }
        // Don't call super — prevents any built-in window drag.
    }

    override func cancelOperation(_ sender: Any?) {
        if escapeHandler?() == true {
            return
        }
        orderOut(nil)
        hideHandler?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else {
            return super.performKeyEquivalent(with: event)
        }
        // Cmd+F: check first responder to decide focus-search vs hide-sidebar.
        if isReservedKeyCommand(event) {
            cmdFHandler?(!shouldHandleWindowKeyEvents)
            return true
        }
        // Let text fields handle their own input.
        if !shouldHandleWindowKeyEvents {
            return super.performKeyEquivalent(with: event)
        }
        if keyCommandHandler?(event) == true {
            return true
        }
        if let shortcut = HotKeyShortcut.from(event: event, requireModifiers: false),
           localShortcutHandler?(shortcut) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // performKeyEquivalent handles shortcuts; keyDown is a fallback for
        // events that were not consumed there (e.g. when a text field is focused).
        if shouldHandleWindowKeyEvents,
           keyCommandHandler?(event) == true {
            return
        }
        if let shortcut = HotKeyShortcut.from(event: event, requireModifiers: false),
           localShortcutHandler?(shortcut) == true {
            return
        }
        super.keyDown(with: event)
    }

    private func isReservedKeyCommand(_ event: NSEvent) -> Bool {
        Int(event.keyCode) == kVK_ANSI_F
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
    }

    private var shouldHandleWindowKeyEvents: Bool {
        guard let responder = firstResponder else { return true }
        if responder is NSTextView || responder is NSTextField { return false }
        if responder is NSTextInputClient { return false }
        return true
    }
}

/// NSHostingView subclass that accepts the first mouse click without requiring
/// the window to be focused first. This allows grid drag interactions on
/// secondary display windows to start immediately.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
