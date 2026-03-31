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
        let hostingView = NSHostingView(rootView: view)
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
        // Start at normal level; AppState promotes to .floating via applyWindowLevel().
        window.level = .normal
        let displayID = self.targetScreen.displayID
        window.identifier = NSUserInterfaceItemIdentifier("main-window-\(displayID)")
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.autorecalculatesKeyViewLoop = false
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
        if asKey {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
        // Prevent the search field from auto-focusing when the window opens.
        window?.makeFirstResponder(window?.contentView)
        let elapsed = (CFAbsoluteTimeGetCurrent() - perfStart) * 1000
        debugLog("MainWindowController.show done asKey=\(asKey ? 1 : 0) (\(String(format: "%.1f", elapsed))ms)")
    }

    func hide() {
        guard !isHidingWindow else { return }
        isHidingWindow = true
        appState?.hidePreviewOverlay()
        window?.orderOut(nil)
        onHide()
        isHidingWindow = false
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
    func dismissSilently() {
        window?.orderOut(nil)
    }

    var isVisible: Bool {
        window?.isVisible ?? false
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
        appState?.hidePreviewOverlay()
        // Hide all Tiley windows when the app loses focus, not just this one.
        // Secondary windows don't receive windowDidResignKey because they
        // were never the key window.
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
        let targetAlpha = Self.layoutModeWindowAlpha

        var frame = window.frame
        frame.size = targetSize
        frame.origin = calculatedOrigin(for: targetSize, visibleFrame: visibleFrame)

        let sizeChanged = window.minSize != targetSize || window.maxSize != targetSize
        let frameChanged = !window.frame.equalTo(frame)
        let alphaChanged = window.alphaValue != targetAlpha

        guard sizeChanged || frameChanged || alphaChanged else { return }

        window.minSize = targetSize
        window.maxSize = targetSize
        window.alphaValue = targetAlpha
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
        let origin = calculatedOrigin(for: targetSize, visibleFrame: visibleFrame)
        window.setFrameOrigin(origin)
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

    private func calculatedOrigin(for size: NSSize, visibleFrame: CGRect) -> NSPoint {
        let originX = visibleFrame.midX - size.width / 2
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
    var hideHandler: (() -> Void)?
    var escapeHandler: (() -> Bool)?
    var localShortcutHandler: ((HotKeyShortcut) -> Bool)?
    var keyCommandHandler: ((NSEvent) -> Bool)?
    /// Called when Cmd+F is pressed. Bool parameter: true if a text field is focused.
    var cmdFHandler: ((_ textFieldFocused: Bool) -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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

