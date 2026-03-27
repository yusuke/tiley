import AppKit

/// Displays a colored border around a window's frame to highlight
/// the currently selected target in the sidebar.
final class WindowHighlightController {
    private var window: NSWindow?

    /// Shows (or updates) the highlight border overlapping the given frame.
    /// The frame uses AppKit coordinates (origin at bottom-left).
    func show(around frame: CGRect, borderWidth: CGFloat = 5, color: NSColor = .controlAccentColor) {
        if let window {
            window.setFrame(frame, display: false)
            if let view = window.contentView?.subviews.first as? HighlightBorderView {
                view.borderWidth = borderWidth
                view.color = color
                view.frame = window.contentView!.bounds
                view.needsDisplay = true
            }
            window.orderFront(nil)
            return
        }

        let panel = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // Place above normal windows but below Tiley's floating panels.
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.alphaValue = 0.6
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none

        let borderView = HighlightBorderView(frame: panel.contentView!.bounds)
        borderView.autoresizingMask = [.width, .height]
        borderView.borderWidth = borderWidth
        borderView.color = color
        panel.contentView?.addSubview(borderView)

        panel.orderFront(nil)
        self.window = panel
    }

    func hide() {
        window?.orderOut(nil)
        window = nil
    }
}

private final class HighlightBorderView: NSView {
    var borderWidth: CGFloat = 5
    var color: NSColor = .controlAccentColor

    override func draw(_ dirtyRect: NSRect) {
        let cornerRadius: CGFloat = 10
        let inset = borderWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect,
                                xRadius: cornerRadius, yRadius: cornerRadius)

        // Fill with a light tint of the accent color.
        color.withAlphaComponent(0.08).setFill()
        path.fill()

        // Stroke the border.
        color.setStroke()
        path.lineWidth = borderWidth
        path.stroke()
    }
}
