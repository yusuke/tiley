import AppKit

extension AppState {

    // MARK: - Display movement shortcuts

    func displayShortcutLocalAction(for shortcut: HotKeyShortcut) -> DisplayHotKeyAction? {
        // Display movement shortcuts are global-only; local shortcuts are not used.
        return nil
    }

    /// Executes a display movement action using the frontmost window (global shortcut path).
    func executeDisplayShortcutGlobal(_ action: DisplayHotKeyAction) {
        guard accessibilityGranted else { return }
        if case .moveToOther = action {
            guard let target = windowManager?.captureFocusedWindow() else { return }
            showDisplayPickerMenu(for: target, isLocal: false)
            return
        }
        guard let target = windowManager?.captureFocusedWindow() else { return }
        moveWindowToDisplay(target: target, action: action)
    }

    /// Executes a display movement action using the overlay's active target (local shortcut path).
    func executeDisplayShortcutLocal(_ action: DisplayHotKeyAction) {
        if case .moveToOther = action {
            // Signal the action bar on the mouse cursor's display to show the popup.
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
                moveToOtherDisplayTargetID = screen.displayID
            }
            moveToOtherDisplayRequestVersion += 1
            return
        }
        guard let target = activeLayoutTarget else { return }
        dismissOverlayImmediately()
        moveWindowToDisplay(target: target, action: action)
    }

    func moveWindowToDisplay(target: WindowTarget, action: DisplayHotKeyAction) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard !screens.isEmpty else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]
        let currentIndex = screens.firstIndex(where: { $0.displayID == currentScreen.displayID }) ?? 0

        let destinationScreen: NSScreen
        switch action {
        case .moveToPrimary:
            guard let primary = NSScreen.screens.first,
                  primary.displayID != currentScreen.displayID else { return }
            destinationScreen = primary

        case .moveToNext:
            guard screens.count > 1 else { return }
            destinationScreen = screens[(currentIndex + 1) % screens.count]

        case .moveToPrevious:
            guard screens.count > 1 else { return }
            destinationScreen = screens[(currentIndex - 1 + screens.count) % screens.count]

        case .moveToOther:
            return // handled separately via popup menu

        case .moveToDisplay(let targetDisplayID):
            guard screens.count > 1,
                  let target = screens.first(where: { $0.displayID == targetDisplayID }),
                  target.displayID != currentScreen.displayID else { return }
            destinationScreen = target
        }

        moveWindowProportionally(target: target, from: currentScreen, to: destinationScreen)
    }

    /// Moves a window to a specific display index (used by the display picker menu).
    func moveWindowToDisplayIndex(_ displayIndex: Int, target: WindowTarget, dismissOverlay: Bool) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard displayIndex < screens.count else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]

        let destinationScreen = screens[displayIndex]
        guard destinationScreen.displayID != currentScreen.displayID else { return }

        if dismissOverlay {
            dismissOverlayImmediately()
        }
        moveWindowProportionally(target: target, from: currentScreen, to: destinationScreen)
    }

    func moveWindowProportionally(target: WindowTarget, from srcScreen: NSScreen, to dstScreen: NSScreen) {
        let srcVisible = srcScreen.visibleFrame
        let dstVisible = dstScreen.visibleFrame

        let relX = srcVisible.width > 0 ? (target.frame.minX - srcVisible.minX) / srcVisible.width : 0
        let relY = srcVisible.height > 0 ? (target.frame.minY - srcVisible.minY) / srcVisible.height : 0
        let relW = srcVisible.width > 0 ? target.frame.width / srcVisible.width : 1
        let relH = srcVisible.height > 0 ? target.frame.height / srcVisible.height : 1

        let newFrame = CGRect(
            x: (dstVisible.minX + relX * dstVisible.width).rounded(),
            y: (dstVisible.minY + relY * dstVisible.height).rounded(),
            width: (relW * dstVisible.width).rounded(),
            height: (relH * dstVisible.height).rounded()
        )

        do {
            try windowManager?.move(target: target, to: newFrame, onScreenFrame: dstScreen.frame)
        } catch {
            debugLog("moveWindowToDisplay error: \(error)")
        }
    }

    /// Shows a popup menu listing available displays for the "Move to Other Display" action.
    func showDisplayPickerMenu(for target: WindowTarget, isLocal: Bool) {
        let screens = NSScreen.screens.sorted { $0.displayID < $1.displayID }
        guard screens.count > 1 else { return }

        let currentScreen = screens.max(by: { a, b in
            a.frame.intersection(target.frame).area < b.frame.intersection(target.frame).area
        }) ?? screens[0]

        let menu = NSMenu()

        // Header
        let header = NSMenuItem(title: NSLocalizedString("Move to Other Display", comment: "Display picker menu header"), action: nil, keyEquivalent: "")
        header.isEnabled = false
        let headerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
        ]
        header.attributedTitle = NSAttributedString(string: header.title, attributes: headerAttrs)
        menu.addItem(header)
        menu.addItem(.separator())

        for (index, screen) in screens.enumerated() {
            let name = screen.localizedName
            let title: String
            if screen.displayID == NSScreen.screens.first?.displayID {
                title = "\(name) (\(NSLocalizedString("Primary", comment: "Primary display label")))"
            } else {
                title = name
            }
            let item = NSMenuItem(title: title, action: #selector(AppState.displayPickerMenuAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.representedObject = DisplayPickerContext(target: target, isLocal: isLocal)
            item.image = Self.screenArrangementImage(highlightDisplayID: screen.displayID, size: 16)
            if screen.displayID == currentScreen.displayID {
                item.state = .on
            }
            menu.addItem(item)
        }

        // Show menu at the mouse cursor location using a temporary transparent window,
        // so the menu works even when Tiley has no visible windows (global shortcut).
        let mouseLocation = NSEvent.mouseLocation
        let menuWindow = NSWindow(
            contentRect: NSRect(x: mouseLocation.x - 1, y: mouseLocation.y - 1, width: 2, height: 2),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        menuWindow.level = .popUpMenu
        menuWindow.backgroundColor = .clear
        menuWindow.isOpaque = false
        menuWindow.orderFront(nil)
        menu.popUp(positioning: nil, at: NSPoint(x: 1, y: 1), in: menuWindow.contentView)
        menuWindow.orderOut(nil)
    }

    /// Renders a ScreenArrangementIcon as an NSImage for use in NSMenu items.
    static func screenArrangementImage(highlightDisplayID: CGDirectDisplayID, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            let screens = NSScreen.screens
            guard !screens.isEmpty else { return true }

            var union = CGRect.null
            for screen in screens { union = union.union(screen.frame) }
            guard union.width > 0, union.height > 0 else { return true }

            let inset: CGFloat = 0.5
            let available = CGSize(width: rect.width - inset * 2, height: rect.height - inset * 2)
            let scale = min(available.width / union.width, available.height / union.height)
            let scaledWidth = union.width * scale
            let scaledHeight = union.height * scale
            let offsetX = (rect.width - scaledWidth) / 2
            let offsetY = (rect.height - scaledHeight) / 2
            let gap: CGFloat = 0.5

            for screen in screens {
                let f = screen.frame
                let x = (f.minX - union.minX) * scale + offsetX + gap
                let y = (union.maxY - f.maxY) * scale + offsetY + gap
                let w = f.width * scale - gap * 2
                let h = f.height * scale - gap * 2
                let screenRect = NSRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                let cornerRadius: CGFloat = 1
                let path = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)
                if screen.displayID == highlightDisplayID {
                    NSColor.labelColor.setFill()
                    path.fill()
                } else {
                    NSColor.tertiaryLabelColor.setFill()
                    path.fill()
                }
            }
            return true
        }
        img.isTemplate = true
        return img
    }

    @objc func displayPickerMenuAction(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? DisplayPickerContext else { return }
        moveWindowToDisplayIndex(sender.tag, target: context.target, dismissOverlay: context.isLocal)
    }

    // MARK: - Display highlight overlay

    /// Shows a red border on the screen matching the given displayID.
    func showDisplayHighlight(displayID: CGDirectDisplayID) {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            hideDisplayHighlight()
            return
        }
        var frame = screen.frame
        // 内蔵ディスプレイはノッチ・角丸を避けるためメニューバー下に描画
        if CGDisplayIsBuiltin(displayID) != 0 {
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            frame.size.height -= menuBarHeight
        }
        if let existing = displayHighlightWindow {
            existing.setFrame(frame, display: false)
            (existing.contentView as? DisplayHighlightView)?.frame = NSRect(origin: .zero, size: frame.size)
            existing.orderFront(nil)
            return
        }
        let window = DisplayHighlightWindow(frame: frame)
        window.orderFront(nil)
        displayHighlightWindow = window
    }

    /// Hides the display highlight overlay.
    func hideDisplayHighlight() {
        displayHighlightWindow?.orderOut(nil)
        displayHighlightWindow = nil
    }
}

// MARK: - Helper Classes

final class DisplayPickerContext: NSObject {
    let target: WindowTarget
    let isLocal: Bool
    init(target: WindowTarget, isLocal: Bool) {
        self.target = target
        self.isLocal = isLocal
    }
}

extension CGRect {
    var area: CGFloat { width * height }
}

final class DisplayHighlightWindow: NSWindow {
    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = DisplayHighlightView(frame: NSRect(origin: .zero, size: frame.size))
        contentView = view
    }
}

final class DisplayHighlightView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.setStroke()
        let borderWidth: CGFloat = 4
        let path = NSBezierPath(rect: bounds.insetBy(dx: borderWidth / 2, dy: borderWidth / 2))
        path.lineWidth = borderWidth
        path.stroke()
    }
}

final class TaggableView: NSView {
    var assignedTag: Int = 0
    override var tag: Int { assignedTag }
}
