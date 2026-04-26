import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    private weak var appState: AppState?
    private let mainWindowFrame: NSRect?

    init(appState: AppState, mainWindowFrame: NSRect? = nil) {
        self.appState = appState
        self.mainWindowFrame = mainWindowFrame

        let height: CGFloat
        if let mainWindowFrame {
            height = mainWindowFrame.size.height
        } else {
            let screen = Self.screenUnderMouse()
            height = MainWindowController.mainWindowSize(
                for: appState,
                visibleFrame: screen.visibleFrame,
                screenFrame: screen.frame
            ).height
        }
        let size = NSSize(width: 560, height: height)

        let settingsView = SettingsView(appState: appState)
        let hostingView = NSHostingView(rootView: settingsView)
        hostingView.autoresizingMask = [.width, .height]
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = "Tiley Settings"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = 1.0
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = false
        window.level = .normal
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.animationBehavior = .none
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
        let screen = Self.screenUnderMouse()
        let screenFrame = screen.frame
        let windowSize = window.frame.size
        let origin = NSPoint(
            x: screenFrame.midX - windowSize.width / 2,
            y: screenFrame.midY - windowSize.height / 2
        )
        window.setFrameOrigin(origin)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        window?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // When the user clicks another app, dismiss the settings window
        // so Tiley fully hides and the global shortcut can reopen it.
        guard !NSApp.isActive else { return }
        appState?.handleSettingsWindowDeactivated()
    }

    func windowWillClose(_ notification: Notification) {
        appState?.handleSettingsWindowClosed()
    }

    private static func screenUnderMouse() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) })
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }
}
