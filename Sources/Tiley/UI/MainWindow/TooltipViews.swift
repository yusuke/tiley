import AppKit
import SwiftUI

struct EditingTooltipModifier: ViewModifier {
    let isEditing: Bool
    let shortcutName: String

    func body(content: Content) -> some View {
        if isEditing {
            content.instantTooltip(String(format: NSLocalizedString("Click to change \"%@\"", comment: "Tooltip for clicking shortcut badge to edit with name"), shortcutName))
        } else {
            content
        }
    }
}

struct InstantBubbleTooltip: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .background(TooltipTriggerView(text: text))
    }
}

struct TooltipTriggerView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TooltipHoverView {
        let view = TooltipHoverView()
        view.tooltipText = text
        return view
    }

    func updateNSView(_ nsView: TooltipHoverView, context: Context) {
        nsView.tooltipText = text
    }
}

final class TooltipHoverView: NSView {
    var tooltipText = ""
    private var popover: NSPopover?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        showTooltip()
    }

    override func mouseExited(with event: NSEvent) {
        dismissTooltip()
    }

    override func removeFromSuperview() {
        dismissTooltip()
        super.removeFromSuperview()
    }

    private func showTooltip() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .semitransient
        p.animates = false
        let hostingController = NSHostingController(rootView:
            Text(tooltipText)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .fixedSize()
        )
        hostingController.view.setFrameSize(hostingController.view.fittingSize)
        p.contentSize = hostingController.view.fittingSize
        p.contentViewController = hostingController
        p.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        popover = p
    }

    private func dismissTooltip() {
        popover?.close()
        popover = nil
    }
}

extension View {
    func instantTooltip(_ text: String) -> some View {
        modifier(InstantBubbleTooltip(text: text))
    }

    func instantTooltipView<V: View>(@ViewBuilder _ content: @escaping () -> V) -> some View {
        modifier(InstantBubbleTooltipView(tooltipContent: AnyView(content())))
    }
}

struct InstantBubbleTooltipView: ViewModifier {
    let tooltipContent: AnyView

    func body(content: Content) -> some View {
        content
            .background(RichTooltipTriggerView(tooltipContent: tooltipContent))
    }
}

struct RichTooltipTriggerView: NSViewRepresentable {
    let tooltipContent: AnyView

    func makeNSView(context: Context) -> RichTooltipHoverView {
        let view = RichTooltipHoverView()
        view.tooltipContent = tooltipContent
        return view
    }

    func updateNSView(_ nsView: RichTooltipHoverView, context: Context) {
        nsView.tooltipContent = tooltipContent
    }
}

final class RichTooltipHoverView: NSView {
    var tooltipContent: AnyView = AnyView(EmptyView())
    private var popover: NSPopover?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { showTooltip() }
    override func mouseExited(with event: NSEvent) { dismissTooltip() }
    override func removeFromSuperview() { dismissTooltip(); super.removeFromSuperview() }

    private func showTooltip() {
        guard popover == nil else { return }
        let p = NSPopover()
        p.behavior = .semitransient
        p.animates = false
        let hostingController = NSHostingController(rootView: tooltipContent)
        hostingController.view.setFrameSize(hostingController.view.fittingSize)
        p.contentSize = hostingController.view.fittingSize
        p.contentViewController = hostingController
        p.show(relativeTo: bounds, of: self, preferredEdge: .minY)
        popover = p
    }

    private func dismissTooltip() {
        popover?.close()
        popover = nil
    }
}
