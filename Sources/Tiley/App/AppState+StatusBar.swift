import AppKit
import Sparkle

// MARK: - Status Bar & Dock Icon Management

extension AppState {

    // MARK: Visibility Setters

    func setMenuIconVisible(_ visible: Bool) {
        menuIconVisible = visible
        UserDefaults.standard.set(visible, forKey: UserDefaultsKey.menuIconVisible)
        applyStatusItemVisibility()
    }

    func setDockIconVisible(_ visible: Bool) {
        dockIconVisible = visible
        UserDefaults.standard.set(visible, forKey: UserDefaultsKey.dockIconVisible)
        applyDockIconVisibility()
    }

    // MARK: Status Item

    func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(handleStatusItemButtonClick)
            button.sendAction(on: [.leftMouseUp])
        }
        if let iconURL = resourceBundle.url(forResource: "menu-icon", withExtension: "pdf"),
           let icon = NSImage(contentsOf: iconURL),
           let button = item.button {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            originalMenuIcon = icon
            button.image = icon
            button.imagePosition = .imageOnly
            button.title = ""
        } else {
            item.button?.title = NSLocalizedString("Tiley", comment: "App name fallback title")
        }
        item.menu = nil
        // Show immediately — the template icon adapts to any appearance
        // automatically, so there is no black flash.
        statusItem = item
        // Observe effectiveAppearance changes to redraw badge overlays.
        // Skip .initial; instead delay the first badge application so the
        // button's effectiveAppearance has settled in the menu bar.
        appearanceObservation = item.button?.observe(\.effectiveAppearance, options: [.new]) { [weak self] button, _ in
            let newAppearance = button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight])
            DispatchQueue.main.async {
                guard let self, newAppearance != self.lastStatusIconAppearance else { return }
                self.applyStatusItemIcon()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.applyStatusItemIcon()
        }
    }

    func removeStatusItem() {
        guard let statusItem else { return }
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    func applyStatusItemVisibility() {
        if menuIconVisible {
            installStatusItem()
        } else {
            removeStatusItem()
        }
    }

    func setUpdateBadge(_ show: Bool) {
        hasUpdateBadge = show
        lastStatusIconAppearance = nil   // Force redraw on badge state change
        if show && statusItem == nil {
            // Menu icon is hidden — temporarily show it so the badge is visible.
            installStatusItem()
            menuIconTemporarilyShown = true
        }
        if !show && menuIconTemporarilyShown {
            // Restore the hidden state when the badge is cleared.
            menuIconTemporarilyShown = false
            if !menuIconVisible {
                removeStatusItem()
                return
            }
        }
        applyStatusItemIcon()
        applyDockIconBadge()
    }

    /// Updates the status item icon according to the current state.
    /// - Update badge or simulating update: overlay info.circle.fill (red)
    /// - DEBUG build (otherwise): overlay ladybug.fill (green)
    /// - Otherwise: use the original template icon as-is
    func applyStatusItemIcon() {
        guard !isApplyingStatusIcon else { return }
        isApplyingStatusIcon = true
        defer { isApplyingStatusIcon = false }

        guard let button = statusItem?.button,
              let baseIcon = originalMenuIcon else { return }

        // Determine which badge to display
        let badgeInfo: (symbolName: String, colors: [NSColor])?
        // Get the menu bar foreground color
        let currentAppearance = button.effectiveAppearance.bestMatch(from: [.vibrantDark, .vibrantLight])
        let menuBarForeground: NSColor
        if let appearance = currentAppearance {
            menuBarForeground = appearance == .vibrantDark ? .white : .black
        } else {
            menuBarForeground = .white
        }

        if hasUpdateBadge || debugSimulateUpdate {
            badgeInfo = ("exclamationmark.circle", [menuBarForeground])
        } else if enableDebugLog {
            badgeInfo = ("ladybug.fill", [.systemGreen, .white])
        } else {
            #if DEBUG
            badgeInfo = ("ladybug.fill", [.systemGreen, .white])
            #else
            badgeInfo = nil
            #endif
        }

        guard let badge = badgeInfo else {
            // No badge — restore the original template icon (template adapts automatically)
            if button.image !== baseIcon {
                baseIcon.isTemplate = true
                button.image = baseIcon
            }
            lastStatusIconAppearance = nil
            return
        }

        // Skip redundant badge redraws when appearance hasn't changed
        if currentAppearance == lastStatusIconAppearance {
            return
        }
        lastStatusIconAppearance = currentAppearance

        let iconSize = baseIcon.size          // 18×18
        let badgeSize: CGFloat = 16
        let margin: CGFloat = 0.5
        let clearDiameter = badgeSize + margin * 2  // 10pt

        guard let symbol = NSImage(systemSymbolName: badge.symbolName,
                                   accessibilityDescription: nil) else { return }
        let config = NSImage.SymbolConfiguration(paletteColors: badge.colors)
            .applying(NSImage.SymbolConfiguration(pointSize: badgeSize, weight: .heavy))
        let coloredSymbol = symbol.withSymbolConfiguration(config) ?? symbol

        // Tint the original icon with the menu bar color
        let tintedBase = NSImage(size: iconSize, flipped: false) { rect in
            baseIcon.draw(in: rect)
            menuBarForeground.set()
            rect.fill(using: .sourceAtop)
            return true
        }

        let composite = NSImage(size: iconSize, flipped: false) { drawRect in
            // 1) Draw the tinted original icon
            tintedBase.draw(in: drawRect)

            // Badge center (bottom-right, offset 3pt right to extend beyond icon edge)
            let centerX = iconSize.width - badgeSize / 2 + 1
            let centerY = badgeSize / 2 - 1

            // 2) Clear the original icon with a circle (slightly lower to match badge visual center)
            let clearRect = NSRect(
                x: centerX - clearDiameter / 2,
                y: centerY - clearDiameter / 2,
                width: clearDiameter,
                height: clearDiameter
            )
            let clearPath = NSBezierPath(ovalIn: clearRect)
            NSGraphicsContext.current?.compositingOperation = .clear
            clearPath.fill()

            // 3) Draw the badge symbol
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let symbolOffsetY: CGFloat = badge.symbolName.hasPrefix("ladybug") ? 1.0 : 0
            let badgeRect = NSRect(
                x: centerX - badgeSize / 2,
                y: centerY - badgeSize / 2 + symbolOffsetY,
                width: badgeSize,
                height: badgeSize
            )
            coloredSymbol.draw(in: badgeRect)

            return true
        }

        composite.isTemplate = false
        button.image = composite
    }

    func updateStatusMenu() {
        // Status item menu is intentionally disabled.
    }

    // MARK: Dock Icon

    func applyDockIconVisibility(isInitialStartup: Bool = false) {
        if dockIconVisible {
            _ = NSApp.setActivationPolicy(.regular)
            applyDockIconBadge()
        } else {
            if isInitialStartup {
                // Activation policy is already .accessory (set in
                // applicationWillFinishLaunching).  Skip the .prohibited
                // → .accessory dance to avoid a use-after-free crash
                // caused by rapid activation policy transitions during
                // early app startup.
                return
            }
            // Switching to .accessory causes macOS to hide all windows and
            // fire windowDidResignKey, which normally resets UI state via
            // handleMainWindowHidden(). Use a flag to suppress that reset.
            let anyVisible = mainWindowControllers.values.contains { $0.isVisible }
            isSwitchingActivationPolicy = true
            // Transition through .prohibited to force macOS to fully
            // de-register the Dock tile, then back to .accessory.
            _ = NSApp.setActivationPolicy(.prohibited)
            _ = NSApp.setActivationPolicy(.accessory)
            if anyVisible {
                // macOS hides windows asynchronously after the policy change.
                // A short delay ensures our restore happens after that.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    guard let self else { return }
                    self.isSwitchingActivationPolicy = false
                    for (displayID, controller) in self.mainWindowControllers {
                        if displayID != self.targetScreenDisplayID {
                            controller.show(asKey: true)
                        }
                    }
                    self.targetWindowController?.show(asKey: true)
                    NSApp.activate(ignoringOtherApps: true)
                }
            } else {
                isSwitchingActivationPolicy = false
            }
        }
    }

    /// Apply or remove a badge on the Dock icon.
    /// Uses NSDockTile.contentView so the shadow is not clipped even when the badge extends beyond the icon.
    /// The icon is drawn to fill the entire tile, and the badge extends beyond it.
    func applyDockIconBadge() {
        guard dockIconVisible else { return }
        let dockTile = NSApp.dockTile

        // Determine which badge to display (same priority as the menu icon)
        let badgeInfo: (symbolName: String, colors: [NSColor])?
        if showsUpdateIndicator {
            badgeInfo = ("exclamationmark.circle.fill", [.white, .systemRed])
        } else if enableDebugLog {
            badgeInfo = ("ladybug.circle.fill", [.white, .systemGreen])
        } else {
            #if DEBUG
            badgeInfo = ("ladybug.circle.fill", [.white, .systemGreen])
            #else
            badgeInfo = nil
            #endif
        }

        guard let badge = badgeInfo else {
            dockTile.contentView = nil
            dockTile.display()
            return
        }

        guard let appIcon = NSImage(named: NSImage.applicationIconName) else { return }
        guard let symbol = NSImage(systemSymbolName: badge.symbolName,
                                   accessibilityDescription: nil) else { return }

        let tileSize = dockTile.size
        let view = NSImageView(frame: NSRect(origin: .zero, size: tileSize))
        // Create a composite image with the icon filling the tile and the badge overlapping at the top-right
        let badgeDiameter = tileSize.width * 0.47
        let config = NSImage.SymbolConfiguration(paletteColors: badge.colors)
            .applying(NSImage.SymbolConfiguration(pointSize: badgeDiameter, weight: .bold))
        let coloredSymbol = symbol.withSymbolConfiguration(config) ?? symbol

        let composite = NSImage(size: tileSize, flipped: false) { _ in
            // Draw the icon to fill the entire tile
            appIcon.draw(in: NSRect(origin: .zero, size: tileSize))

            // Place the badge at the top-right (flush with the tile edge)
            let margin: CGFloat = 2
            let badgeRect = NSRect(
                x: tileSize.width - badgeDiameter - margin,
                y: tileSize.height - badgeDiameter - margin,
                width: badgeDiameter,
                height: badgeDiameter
            )

            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -2),
                blur: 4,
                color: NSColor.black.withAlphaComponent(0.4).cgColor
            )
            coloredSymbol.draw(in: badgeRect)
            ctx.restoreGState()

            return true
        }

        view.image = composite
        dockTile.contentView = view
        dockTile.display()
    }

    // MARK: NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refreshAccessibilityState()
        updateStatusMenu()
    }
}
