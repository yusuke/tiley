import AppKit
import Carbon
import Observation
import SwiftUI

final class MainWindowController: NSWindowController, NSWindowDelegate {
    private static let windowWidth: CGFloat = 559
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
    private static let settingsHeight: CGFloat = 620
    private static let permissionsOnlyHeight: CGFloat = 750
    // Keep layout mode slightly translucent while keeping settings mode fully opaque for readability.
    private static let layoutModeWindowAlpha: CGFloat = 0.99
    private static let settingsModeWindowAlpha: CGFloat = 1.0

    private weak var appState: AppState?
    private let screenRole: ScreenRole
    private let targetScreen: NSScreen
    private let onHide: () -> Void
    private let onEscape: () -> Bool
    private let onLocalShortcut: (HotKeyShortcut) -> Bool
    private let onKeyCommand: (NSEvent) -> Bool
    private var screenParameterTask: Task<Void, Never>?
    private var isHidingWindow = false

    init(appState: AppState, screenRole: ScreenRole = .target, targetScreen: NSScreen? = nil, onHide: @escaping () -> Void, onEscape: @escaping () -> Bool, onLocalShortcut: @escaping (HotKeyShortcut) -> Bool, onKeyCommand: @escaping (NSEvent) -> Bool) {
        self.appState = appState
        self.screenRole = screenRole
        self.targetScreen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first!
        self.onHide = onHide
        self.onEscape = onEscape
        self.onLocalShortcut = onLocalShortcut
        self.onKeyCommand = onKeyCommand
        let initialVisibleFrame = self.targetScreen.visibleFrame
        let initialSize = Self.windowSize(for: appState, visibleFrame: initialVisibleFrame)
        let screenContext = ScreenContext(
            visibleFrame: self.targetScreen.visibleFrame,
            screenFrame: self.targetScreen.frame
        )
        let view = MainWindowView(appState: appState, screenRole: screenRole)
            .environment(\.screenContext, screenContext)
        let hostingView = ZeroInsetHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: initialSize)
        hostingView.autoresizingMask = [.width, .height]

        let window = MainAppWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tiley"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = Self.layoutModeWindowAlpha
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        let displayID = self.targetScreen.displayID
        window.identifier = NSUserInterfaceItemIdentifier("main-window-\(displayID)")
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        // Only use autosave for the target window to avoid position conflicts
        if screenRole.isTarget {
            window.setFrameAutosaveName("TileyMainWindow")
        }
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.hideHandler = onHide
        window.escapeHandler = onEscape
        window.localShortcutHandler = onLocalShortcut
        window.keyCommandHandler = onKeyCommand

        super.init(window: window)
        window.delegate = self
        bindWindowMode(to: appState)
        bindScreenParameterChanges()
        applyWindowMode(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(asKey: Bool = true) {
        let destinationScreen = preferredDisplayScreen(for: window)
        applyWindowMode(animated: false, preferredScreen: destinationScreen)
        positionWindow(preferredScreen: destinationScreen)
        if asKey {
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderFront(nil)
        }
    }

    func hide() {
        guard !isHidingWindow else { return }
        isHidingWindow = true
        appState?.hidePreviewOverlay()
        window?.orderOut(nil)
        onHide()
        isHidingWindow = false
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
        // Keep the permissions-only panel visible so the user can grant access
        // in System Settings and return to Tiley.
        guard appState?.isShowingPermissionsOnly != true else { return }
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
            _ = appState.isEditingSettings
            _ = appState.isShowingPermissionsOnly
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
        let targetSize = Self.windowSize(for: appState, visibleFrame: visibleFrame)
        window.minSize = targetSize
        window.maxSize = targetSize
        window.alphaValue = (appState?.isEditingSettings == true || appState?.isShowingPermissionsOnly == true) ? Self.settingsModeWindowAlpha : Self.layoutModeWindowAlpha

        var frame = window.frame
        frame.size = targetSize
        frame.origin = calculatedOrigin(for: targetSize, visibleFrame: visibleFrame)
        window.setFrame(frame, display: true, animate: animated)
    }

    private func positionWindow(preferredScreen: NSScreen? = nil) {
        guard let window else { return }
        let visibleFrame = currentVisibleFrame(for: window, preferredScreen: preferredScreen)
        guard !visibleFrame.equalTo(.zero) else { return }
        let targetSize = Self.windowSize(for: appState, visibleFrame: visibleFrame)
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

    private func preferredScreen(for window: NSWindow) -> NSScreen? {
        if let containingScreen = screenContainingWindowCenter(window) {
            return containingScreen
        }
        if let screen = window.screen {
            return screen
        }
        return preferredDisplayScreen(for: window)
    }

    private func screenContainingWindowCenter(_ window: NSWindow) -> NSScreen? {
        let center = NSPoint(x: window.frame.midX, y: window.frame.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private static func windowSize(for appState: AppState?, visibleFrame: CGRect?) -> NSSize {
        if appState?.isShowingPermissionsOnly == true {
            return NSSize(width: windowWidth, height: permissionsOnlyHeight)
        }
        let presetCount = CGFloat(appState?.displayedLayoutPresets.count ?? 0)
        let gridWidth = windowWidth - (layoutPanelHorizontalPadding * 2)
        let layoutGridHeight = gridWidth * layoutGridAspectHeightRatio
        let layoutRowsHeight = presetCount * layoutPresetRowHeight
        let layoutSpacingHeight = max(0, presetCount - 1) * layoutPresetRowSpacing
        let layoutHeight = contentVerticalPadding
            + layoutGridHeight
            + footerHeight
            + layoutPresetsHeaderHeight
            + layoutRowsHeight
            + layoutSpacingHeight
        let idealHeight = max(minimumWindowHeight, settingsHeight, layoutHeight) + extraWindowHeight
        let maxHeight = maxAllowedHeight(in: visibleFrame)
        let height = min(idealHeight, maxHeight)
        return NSSize(width: windowWidth, height: height)
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

    private var shouldHandleWindowKeyEvents: Bool {
        guard let responder = firstResponder else { return true }
        if responder is NSTextView || responder is NSTextField { return false }
        if responder is NSTextInputClient { return false }
        return true
    }
}

private final class ZeroInsetHostingView<Content: View>: NSHostingView<Content> {
    override var safeAreaInsets: NSEdgeInsets {
        NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    }

    override var additionalSafeAreaInsets: NSEdgeInsets {
        get { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
        set { }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.titlebarAppearsTransparent = true
    }
}
