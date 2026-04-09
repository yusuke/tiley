import AppKit
import SwiftUI

// MARK: - Tahoe Settings Section

struct TahoeSettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            content()
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .modifier(SettingsSectionBackground(cornerRadius: 10))
        }
    }
}

struct SettingsSectionBackground: ViewModifier {
    let cornerRadius: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(settingsCardFill)
            )
    }

    private var settingsCardFill: Color {
        switch colorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color(white: 0.98)
        }
    }

}

// MARK: - Tahoe Settings Row

let shortcutIconColumnWidth: CGFloat = 24

struct TahoeSettingsRow<Trailing: View>: View {
    let label: String
    var systemImage: String? = nil
    var systemImageWeight: Font.Weight = .regular
    var iconAlignment: Alignment = .trailing
    var iconContent: AnyView? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Group {
                if let iconContent {
                    iconContent
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: systemImageWeight))
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear
                }
            }
            .frame(width: shortcutIconColumnWidth, alignment: iconAlignment)
            Text(label)
            Spacer()
            trailing()
        }
    }
}

// MARK: - SidebarGlassBackground

/// Applies Liquid Glass (macOS 26+) or falls back to NSVisualEffectView.
struct SidebarGlassBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(
                    VisualEffectFallbackBackground(cornerRadius: cornerRadius)
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

/// Fallback for macOS < 26.
struct VisualEffectFallbackBackground: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .withinWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.layer?.cornerRadius = cornerRadius
    }
}

// MARK: - Interactive Glass Background (for NSViewRepresentable buttons)

/// Applies .interactive() glass on macOS 26+; no-op on earlier versions.
struct InteractiveGlassBackground: ViewModifier {
    let cornerRadius: CGFloat
    var useCapsule: Bool = false

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if useCapsule {
                content
                    .glassEffect(.regular.interactive(), in: Capsule())
            } else {
                content
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius))
            }
        } else {
            content
        }
    }
}

// MARK: - Tahoe-style Toolbar Button

struct TahoeQuitButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var normalFill: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color.white
    }
    private var hoverFill: Color {
        colorScheme == .dark ? Color(white: 0.26) : Color(white: 0.92)
    }
    private var pressFill: Color {
        colorScheme == .dark ? Color(white: 0.32) : Color(white: 0.76)
    }

    func makeBody(configuration: Configuration) -> some View {
        let shadowOpacity: Double = colorScheme == .dark ? 0.5 : 0.12
        configuration.label
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? pressFill : isHovered ? hoverFill : normalFill)
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 1.5, y: 0.5)
            }
            .contentShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - TahoeActionBarMenuButton

/// Finder-style dropdown menu button: rounded background, hover highlight,
/// stays highlighted while the popup menu is open.
struct TahoeActionBarMenuButton: NSViewRepresentable {
    let symbolName: String
    let disabled: Bool
    let colorScheme: ColorScheme
    var showChevron: Bool = true
    /// The screen where the window/app currently resides (used for arrow direction in menu items).
    var currentScreen: NSScreen? = nil
    let menuItems: [(title: String, screen: NSScreen)]
    let onSelect: (NSScreen) -> Void
    /// When changed, programmatically opens the popup menu.
    var triggerVersion: Int = 0

    func makeNSView(context: Context) -> TahoeMenuButtonView {
        let view = TahoeMenuButtonView()
        view.coordinator = context.coordinator
        view.showChevron = showChevron
        view.translatesAutoresizingMaskIntoConstraints = false
        let width: CGFloat = showChevron ? 38 : 28
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: width),
            view.heightAnchor.constraint(equalToConstant: 24),
        ])
        return view
    }

    func updateNSView(_ nsView: TahoeMenuButtonView, context: Context) {
        let coord = context.coordinator
        coord.symbolName = symbolName
        coord.disabled = disabled
        coord.colorScheme = colorScheme
        coord.currentScreen = currentScreen
        coord.menuItems = menuItems
        coord.onSelect = onSelect
        nsView.showChevron = showChevron
        nsView.isEnabled = !disabled
        nsView.needsDisplay = true
        if triggerVersion != coord.lastTriggerVersion {
            coord.lastTriggerVersion = triggerVersion
            if triggerVersion > 0 && !disabled {
                DispatchQueue.main.async {
                    nsView.showMenuProgrammatically()
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(symbolName: symbolName, disabled: disabled, colorScheme: colorScheme,
                    currentScreen: currentScreen, menuItems: menuItems, onSelect: onSelect)
    }

    final class TahoeMenuButtonView: NSView {
        weak var coordinator: Coordinator?
        private var isHovered = false
        private var isMenuOpen = false
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }
        var isEnabled: Bool = true
        var showChevron: Bool = true

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
            addTrackingArea(ta)
            trackingArea = ta
        }

        override func mouseEntered(with event: NSEvent) {
            guard isEnabled else { return }
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            showMenuProgrammatically()
        }

        func showMenuProgrammatically() {
            guard isEnabled, let coord = coordinator else { return }
            isMenuOpen = true
            needsDisplay = true

            let menu = NSMenu()
            for item in coord.menuItems {
                let mi = NSMenuItem(title: item.title, action: #selector(Coordinator.menuAction(_:)), keyEquivalent: "")
                mi.target = coord
                mi.representedObject = item.screen
                if let fromScreen = coord.currentScreen {
                    mi.image = Self.arrowWithScreenArrangementImage(
                        from: fromScreen, to: item.screen, size: 16
                    )
                } else {
                    mi.image = Self.screenArrangementImage(highlightDisplayID: item.screen.displayID, size: 16)
                }
                menu.addItem(mi)
            }

            // Show below the button, aligned to leading edge
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)

            // Menu closed
            isMenuOpen = false
            isHovered = false
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let cornerRadius = bounds.height / 2  // Capsule
            let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            // Background fill (Xcode/Finder-like: white on hover, transparent normally)
            if isMenuOpen {
                let labelColor = NSColor.labelColor.cgColor
                ctx.addPath(path)
                ctx.setFillColor(labelColor.copy(alpha: 0.12) ?? CGColor(gray: 0, alpha: 0.12))
                ctx.fillPath()
            } else if isHovered {
                let controlColor = NSColor.controlColor.cgColor
                ctx.addPath(path)
                ctx.setFillColor(controlColor)
                ctx.fillPath()
            }
            // Normal state: no fill (transparent)

            // Tint color: always full opacity (primary), dimmed only when disabled
            let tintColor: NSColor
            if !isEnabled {
                tintColor = .tertiaryLabelColor
            } else {
                tintColor = .labelColor
            }

            // Main icon
            let symbolName = coordinator?.symbolName ?? "rectangle.portrait.and.arrow.right"
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tinted = image.tinted(with: tintColor)
                let imageSize = tinted.size
                if showChevron {
                    // Shift icon left to make room for chevron
                    let chevronSpace: CGFloat = 10
                    let x = (bounds.width - chevronSpace - imageSize.width) / 2
                    let y = (bounds.height - imageSize.height) / 2
                    tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
                } else {
                    let x = (bounds.width - imageSize.width) / 2
                    let y = (bounds.height - imageSize.height) / 2
                    tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
                }
            }

            // Chevron down (right side, only for dropdown mode)
            if showChevron {
                let chevronConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
                if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                    .withSymbolConfiguration(chevronConfig) {
                    let tintedChevron = chevron.tinted(with: tintColor)
                    let chevronSize = tintedChevron.size
                    let cx = bounds.width - chevronSize.width - 5
                    let cy = (bounds.height - chevronSize.height) / 2
                    tintedChevron.draw(in: NSRect(x: cx, y: cy, width: chevronSize.width, height: chevronSize.height))
                }
            }
        }

        /// Renders an arrow + screen arrangement icon as a combined NSImage for NSMenu items.
        static func arrowWithScreenArrangementImage(from fromScreen: NSScreen, to toScreen: NSScreen, size: CGFloat) -> NSImage {
            let arrowName = directionArrowSymbol(from: fromScreen, to: toScreen)
            let arrowConfig = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .bold)
            let arrowImage = NSImage(systemSymbolName: arrowName, accessibilityDescription: nil)?
                .withSymbolConfiguration(arrowConfig)
            let displayImage = screenArrangementImage(highlightDisplayID: toScreen.displayID, size: size)

            let arrowSize = arrowImage?.size ?? .zero
            let spacing: CGFloat = 2
            let totalWidth = arrowSize.width + spacing + size
            let totalHeight = max(arrowSize.height, size)

            let combined = NSImage(size: NSSize(width: totalWidth, height: totalHeight), flipped: false) { rect in
                // Draw arrow on the left, vertically centred
                let arrowY = (totalHeight - arrowSize.height) / 2
                arrowImage?.draw(in: NSRect(x: 0, y: arrowY, width: arrowSize.width, height: arrowSize.height))
                // Draw display icon on the right, vertically centred
                let iconY = (totalHeight - size) / 2
                displayImage.draw(in: NSRect(x: arrowSize.width + spacing, y: iconY, width: size, height: size))
                return true
            }
            combined.isTemplate = true
            return combined
        }

        /// Renders a ScreenArrangementIcon-equivalent as an NSImage for use in NSMenu items.
        static func screenArrangementImage(highlightDisplayID: CGDirectDisplayID, size: CGFloat) -> NSImage {
            let img = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
                let screens = NSScreen.screens
                guard !screens.isEmpty else { return true }

                var union = CGRect.null
                for screen in screens {
                    union = union.union(screen.frame)
                }
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
                    // Flip Y: NSScreen is bottom-left, drawing context is top-left (flipped)
                    let y = (union.maxY - f.maxY) * scale + offsetY + gap
                    let w = f.width * scale - gap * 2
                    let h = f.height * scale - gap * 2
                    let screenRect = NSRect(x: x, y: y, width: max(w, 1), height: max(h, 1))
                    let cornerRadius: CGFloat = 1.5
                    let path = NSBezierPath(roundedRect: screenRect, xRadius: cornerRadius, yRadius: cornerRadius)

                    let isHighlight = screen.displayID == highlightDisplayID
                    if isHighlight {
                        NSColor.secondaryLabelColor.setFill()
                        path.fill()
                    } else {
                        NSColor.secondaryLabelColor.setStroke()
                        path.lineWidth = 0.75
                        path.stroke()
                    }
                }
                return true
            }
            img.isTemplate = true
            return img
        }
    }

    class Coordinator: NSObject {
        var symbolName: String
        var disabled: Bool
        var colorScheme: ColorScheme
        var currentScreen: NSScreen?
        var menuItems: [(title: String, screen: NSScreen)]
        var onSelect: (NSScreen) -> Void
        var lastTriggerVersion: Int = 0

        init(symbolName: String, disabled: Bool, colorScheme: ColorScheme,
             currentScreen: NSScreen?, menuItems: [(title: String, screen: NSScreen)], onSelect: @escaping (NSScreen) -> Void) {
            self.symbolName = symbolName
            self.disabled = disabled
            self.colorScheme = colorScheme
            self.currentScreen = currentScreen
            self.menuItems = menuItems
            self.onSelect = onSelect
        }

        @objc func menuAction(_ sender: NSMenuItem) {
            guard let screen = sender.representedObject as? NSScreen else { return }
            onSelect(screen)
        }
    }
}

// MARK: - TahoeResizeMenuButton

/// Finder-style dropdown menu button for window resize presets.
/// Grouped sections with aspect-ratio headers.
/// Shows on-screen overlay + mini screen preview on hover.
struct TahoeResizeMenuButton: NSViewRepresentable {
    let symbolName: String
    let disabled: Bool
    let colorScheme: ColorScheme
    let groupedPresets: [(ratio: String, presets: [WindowResizePreset])]
    let onSelect: (CGSize) -> Void
    /// Current window position in AX coordinates (top-left origin on primary screen).
    var windowAXPosition: CGPoint = .zero
    /// Screen the window resides on.
    var windowScreen: NSScreen? = nil
    /// Callbacks for showing/hiding preview via AppState.
    var onPreview: ((CGRect, NSScreen) -> Void)? = nil
    var onPreviewHide: (() -> Void)? = nil

    func makeNSView(context: Context) -> ResizeMenuButtonView {
        let view = ResizeMenuButtonView()
        view.coordinator = context.coordinator
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 38),
            view.heightAnchor.constraint(equalToConstant: 24),
        ])
        return view
    }

    func updateNSView(_ nsView: ResizeMenuButtonView, context: Context) {
        let coord = context.coordinator
        coord.symbolName = symbolName
        coord.disabled = disabled
        coord.colorScheme = colorScheme
        coord.groupedPresets = groupedPresets
        coord.onSelect = onSelect
        coord.windowAXPosition = windowAXPosition
        coord.windowScreen = windowScreen
        coord.onPreview = onPreview
        coord.onPreviewHide = onPreviewHide
        nsView.isEnabled = !disabled
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(symbolName: symbolName, disabled: disabled, colorScheme: colorScheme,
                    groupedPresets: groupedPresets, onSelect: onSelect)
    }

    final class ResizeMenuButtonView: NSView {
        weak var coordinator: Coordinator?
        private var isHovered = false
        private var isMenuOpen = false
        private var trackingArea: NSTrackingArea?

        override var isFlipped: Bool { true }
        var isEnabled: Bool = true

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
            addTrackingArea(ta)
            trackingArea = ta
        }

        override func mouseEntered(with event: NSEvent) {
            guard isEnabled else { return }
            isHovered = true
            needsDisplay = true
        }

        override func mouseExited(with event: NSEvent) {
            isHovered = false
            needsDisplay = true
        }

        override func mouseDown(with event: NSEvent) {
            guard isEnabled else { return }
            showMenuProgrammatically()
        }

        func showMenuProgrammatically() {
            guard isEnabled, let coord = coordinator else { return }
            isMenuOpen = true
            needsDisplay = true

            let menu = NSMenu()
            for (groupIndex, group) in coord.groupedPresets.enumerated() {
                if groupIndex > 0 {
                    menu.addItem(.separator())
                }
                // Section header
                let header = NSMenuItem(title: group.ratio, action: nil, keyEquivalent: "")
                header.isEnabled = false
                let headerAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]
                header.attributedTitle = NSAttributedString(string: group.ratio, attributes: headerAttrs)
                menu.addItem(header)

                for preset in group.presets {
                    let mi = NSMenuItem(title: preset.label, action: #selector(Coordinator.menuAction(_:)), keyEquivalent: "")
                    mi.target = coord
                    mi.representedObject = NSValue(size: preset.size)
                    menu.addItem(mi)
                }
            }

            // Use NSMenuDelegate to track highlighted item for live preview
            menu.delegate = coord

            coord.didSelectItem = false
            coord.selectedSize = nil
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)

            if coord.didSelectItem, let size = coord.selectedSize {
                // Item was selected: fire onSelect directly.
                // resizeWindow handles hideResizePreview + hideMainWindow before AX operations.
                coord.onSelect(size)
            } else {
                coord.hidePreview()
            }

            isMenuOpen = false
            isHovered = false
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let cornerRadius = bounds.height / 2
            let path = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

            if isMenuOpen || isHovered {
                let labelColor = NSColor.labelColor.cgColor
                ctx.addPath(path)
                ctx.setFillColor(labelColor.copy(alpha: 0.12) ?? CGColor(gray: 0, alpha: 0.12))
                ctx.fillPath()
            }

            let tintColor: NSColor = !isEnabled ? .tertiaryLabelColor : .labelColor

            // Main icon (shifted left to make room for chevron)
            let symbolName = coordinator?.symbolName ?? "arrow.up.left.and.arrow.down.right"
            let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                let tinted = image.tinted(with: tintColor)
                let imageSize = tinted.size
                let chevronSpace: CGFloat = 10
                let x = (bounds.width - chevronSpace - imageSize.width) / 2
                let y = (bounds.height - imageSize.height) / 2
                tinted.draw(in: NSRect(x: x, y: y, width: imageSize.width, height: imageSize.height))
            }

            // Chevron down (right side)
            let chevronConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
            if let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(chevronConfig) {
                let tintedChevron = chevron.tinted(with: tintColor)
                let chevronSize = tintedChevron.size
                let cx = bounds.width - chevronSize.width - 5
                let cy = (bounds.height - chevronSize.height) / 2
                tintedChevron.draw(in: NSRect(x: cx, y: cy, width: chevronSize.width, height: chevronSize.height))
            }
        }
    }

    class Coordinator: NSObject, NSMenuDelegate {
        var symbolName: String
        var disabled: Bool
        var colorScheme: ColorScheme
        var groupedPresets: [(ratio: String, presets: [WindowResizePreset])]
        var onSelect: (CGSize) -> Void
        var windowAXPosition: CGPoint = .zero
        var windowScreen: NSScreen? = nil
        var onPreview: ((CGRect, NSScreen) -> Void)? = nil
        var onPreviewHide: (() -> Void)? = nil
        var didSelectItem = false
        var selectedSize: CGSize?

        init(symbolName: String, disabled: Bool, colorScheme: ColorScheme,
             groupedPresets: [(ratio: String, presets: [WindowResizePreset])], onSelect: @escaping (CGSize) -> Void) {
            self.symbolName = symbolName
            self.disabled = disabled
            self.colorScheme = colorScheme
            self.groupedPresets = groupedPresets
            self.onSelect = onSelect
        }

        @objc func menuAction(_ sender: NSMenuItem) {
            guard let sizeValue = sender.representedObject as? NSValue else { return }
            didSelectItem = true
            selectedSize = CGSize(width: sizeValue.sizeValue.width, height: sizeValue.sizeValue.height)
        }

        // MARK: NSMenuDelegate

        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            debugLog("[resize] willHighlight: \(item?.title ?? "nil")")
            let menuWindow = NSApp.windows.first { String(describing: type(of: $0)).contains("MenuWindow") }
            handleHighlightChange(item, menuWindow: menuWindow)
        }

        func menuDidClose(_ menu: NSMenu) {
            // Skip hiding preview when an item was selected — resizeWindow handles dismissal.
            if !didSelectItem {
                hidePreview()
            }
            didSelectItem = false
        }

        private func handleHighlightChange(_ item: NSMenuItem?, menuWindow: NSWindow?) {
            guard let item, let sizeValue = item.representedObject as? NSValue else {
                // Don't hide on nil highlight — keep last preview visible.
                // Preview is cleaned up by menuDidClose or resizeWindow.
                return
            }
            let presetSize = CGSize(width: sizeValue.sizeValue.width, height: sizeValue.sizeValue.height)
            guard let screen = windowScreen else { return }

            // Compute preview frame in AppKit coordinates
            let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let destVisible = screen.visibleFrame
            let visibleAXTop = primaryMaxY - destVisible.maxY
            let visibleAXLeft = destVisible.minX
            let visibleAXRight = destVisible.maxX
            let visibleAXBottom = primaryMaxY - destVisible.minY

            var pos = windowAXPosition
            if pos.x + presetSize.width > visibleAXRight {
                pos.x = visibleAXRight - presetSize.width
            }
            pos.x = max(pos.x, visibleAXLeft)
            if pos.y + presetSize.height > visibleAXBottom {
                pos.y = visibleAXBottom - presetSize.height
            }
            pos.y = max(pos.y, visibleAXTop)

            // Convert AX coordinates to AppKit frame (bottom-left origin)
            let appKitY = primaryMaxY - pos.y - presetSize.height
            let previewFrame = CGRect(x: pos.x, y: appKitY, width: presetSize.width, height: presetSize.height)

            // Show both real-size overlay and grid preview via AppState
            onPreview?(previewFrame, screen)
        }

        func hidePreview() {
            onPreviewHide?()
        }
    }
}

// MARK: - NSImage Tinting Extension

extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let img = self.copy() as! NSImage
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill(using: .sourceAtop)
        img.unlockFocus()
        img.isTemplate = false
        return img
    }
}

// MARK: - TahoeActionBarHoveredKey

struct TahoeActionBarHoveredKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var tahoeActionBarHovered: Bool {
        get { self[TahoeActionBarHoveredKey.self] }
        set { self[TahoeActionBarHoveredKey.self] = newValue }
    }
}

/// Tahoe-style action bar button: capsule shape, Xcode/Finder-like L&F.
/// Default: icon at full opacity, transparent background.
/// Hover: icon unchanged, white background (matches Finder/Xcode toolbar style).
struct TahoeActionBarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        let fgStyle: HierarchicalShapeStyle = !isEnabled ? .tertiary : .primary

        configuration.label
            .environment(\.tahoeActionBarHovered, isHovered || configuration.isPressed)
            .foregroundStyle(fgStyle)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        configuration.isPressed
                            ? Color(nsColor: .labelColor).opacity(0.22)
                            : isHovered
                                ? Color(nsColor: .labelColor).opacity(0.12)
                                : Color.clear
                    )
            )
            .contentShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct TahoeToolbarButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    private var normalFill: Color {
        colorScheme == .dark ? Color(white: 0.18) : Color.white
    }
    private var hoverFill: Color {
        colorScheme == .dark ? Color(white: 0.26) : Color(white: 0.92)
    }
    private var pressFill: Color {
        colorScheme == .dark ? Color(white: 0.32) : Color(white: 0.76)
    }

    func makeBody(configuration: Configuration) -> some View {
        let shadowOpacity: Double = colorScheme == .dark ? 0.5 : 0.12
        configuration.label
            .foregroundStyle(.primary)
            .frame(width: 30, height: 30)
            .background {
                Capsule(style: .continuous)
                    .fill(configuration.isPressed ? pressFill : isHovered ? hoverFill : normalFill)
                    .shadow(color: Color.black.opacity(shadowOpacity), radius: 1.5, y: 0.5)
            }
            .contentShape(Capsule())
            .onHover { hovering in
                isHovered = hovering
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - WindowDragArea

/// Transparent hit-target that initiates a manual window drag.
/// Use as `.background(WindowDragArea())` on toolbar / chrome regions.
/// Uses `.contentShape(Rectangle())` so the full frame participates in
/// SwiftUI hit-testing, then an `onChanged` DragGesture moves the window.
struct WindowDragArea: View {
    @State private var initialOrigin: CGPoint?
    @State private var initialMouse: CGPoint?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
                        // Use screen coordinates (NSEvent.mouseLocation) to avoid
                        // feedback caused by the window-relative SwiftUI coordinate space.
                        let mouse = NSEvent.mouseLocation
                        if initialOrigin == nil {
                            initialOrigin = CGPoint(x: window.frame.origin.x,
                                                    y: window.frame.origin.y)
                            initialMouse = mouse
                        }
                        guard let origin = initialOrigin, let start = initialMouse else { return }
                        window.setFrameOrigin(NSPoint(
                            x: origin.x + mouse.x - start.x,
                            y: origin.y + mouse.y - start.y
                        ))
                    }
                    .onEnded { _ in
                        initialOrigin = nil
                        initialMouse = nil
                    }
            )
    }
}

struct UpdateAvailableBadge: View {
    var body: some View {
        Text(NSLocalizedString("Update available", comment: "Badge shown when an update is available"))
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.red, in: Capsule())
            .fixedSize()
    }
}
