import AppKit
import SwiftUI

@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {

    static let windowWidth: CGFloat = 559
    static let windowHeight: CGFloat = 750

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState

        let permissionsView = PermissionsView(appState: appState)
        let hostingView = NSHostingView(rootView: permissionsView)
        hostingView.autoresizingMask = [.width, .height]

        let size = NSSize(width: Self.windowWidth, height: Self.windowHeight)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Tiley Permissions"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.minSize = size
        window.maxSize = size
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - Self.windowWidth / 2,
            y: visibleFrame.midY - Self.windowHeight / 2
        )
        window.setFrameOrigin(origin)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    // Keep the permissions window visible when the user switches to System Settings
    // to grant accessibility permission.
    func windowDidResignKey(_ notification: Notification) {
        // Do nothing — stay visible so the user can return after granting permission.
    }
}
