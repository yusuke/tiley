import AppKit
import SwiftUI

final class LayoutPreviewOverlayController: NSWindowController {
    let screenFrame: CGRect
    let visibleFrame: CGRect
    private weak var attachedParentWindow: NSWindow?

    init(screenFrame: CGRect, visibleFrame: CGRect) {
        self.screenFrame = screenFrame
        self.visibleFrame = visibleFrame

        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .normal
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSelection(_ selection: GridSelection, rows: Int, columns: Int, gap: CGFloat, behind parentWindow: NSWindow?, resizability: WindowResizability = .both, windowSize: CGSize? = nil) {
        let frame = GridCalculator.frame(for: selection, in: visibleFrame, rows: rows, columns: columns, gap: gap)
        let rootView = SelectionPreviewOverlayView(
            frame: frame,
            resizability: resizability,
            windowSize: windowSize,
            screenFrame: screenFrame
        )
        window?.contentView = NSHostingView(rootView: rootView)
        window?.level = .normal
        present(behind: parentWindow)
    }

    func showGrid(rows: Int, columns: Int, gap: CGFloat, behind parentWindow: NSWindow?) {
        let rootView = GridPreviewOverlayView(
            screenFrame: screenFrame,
            visibleFrame: visibleFrame,
            rows: rows,
            columns: columns,
            gap: gap
        )
        window?.contentView = NSHostingView(rootView: rootView)
        window?.level = .normal
        present(behind: parentWindow)
    }

    func hide() {
        guard let window else {
            attachedParentWindow = nil
            return
        }
        if let parentWindow = attachedParentWindow {
            parentWindow.removeChildWindow(window)
        }
        attachedParentWindow = nil
        window.contentView = nil
        window.orderOut(nil)
    }

    private func present(behind parentWindow: NSWindow?) {
        guard let window else { return }
        guard let parentWindow else {
            if let attachedParentWindow {
                attachedParentWindow.removeChildWindow(window)
                self.attachedParentWindow = nil
            }
            window.orderOut(nil)
            return
        }

        if attachedParentWindow !== parentWindow {
            if let attachedParentWindow {
                attachedParentWindow.removeChildWindow(window)
            }
            parentWindow.addChildWindow(window, ordered: .below)
            attachedParentWindow = parentWindow
        }
        window.orderFront(nil)
    }
}

private struct SelectionPreviewOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let frame: CGRect
    let resizability: WindowResizability
    /// Current window size — used to compute the accepted region on locked axes.
    let windowSize: CGSize?
    let screenFrame: CGRect

    var body: some View {
        // Full requested frame in screen-local coordinates (top-left origin).
        let localFrame = CGRect(
            x: frame.minX - screenFrame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )

        let hasConstraint = !resizability.horizontal || !resizability.vertical

        // On locked axes the window keeps its current size.
        // If selection > windowSize → red overflow (can't expand).
        // If selection < windowSize → yellow underflow (can't shrink).
        let lockedWidth = windowSize?.width ?? localFrame.width
        let lockedHeight = windowSize?.height ?? localFrame.height
        let effectiveWidth = resizability.horizontal ? localFrame.width : lockedWidth
        let effectiveHeight = resizability.vertical ? localFrame.height : lockedHeight

        ZStack(alignment: .topLeading) {
            if hasConstraint, let _ = windowSize {
                // The region the window will actually occupy (clamped to selection bounds for display).
                let displayWidth = min(effectiveWidth, localFrame.width)
                let displayHeight = min(effectiveHeight, localFrame.height)

                // Accepted region at the top-left.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ThemeColors.overlaySelectionFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ThemeColors.overlaySelectionBorder(for: colorScheme), lineWidth: 2)
                    )
                    .frame(width: displayWidth, height: displayHeight)
                    .position(x: localFrame.minX + displayWidth / 2, y: localFrame.minY + displayHeight / 2)

                // --- Red: selection is wider than the window can expand ---
                let widthOverflow = localFrame.width - effectiveWidth
                if widthOverflow > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                        )
                        .frame(width: widthOverflow, height: localFrame.height)
                        .position(x: localFrame.minX + effectiveWidth + widthOverflow / 2, y: localFrame.midY)
                }

                // --- Red: selection is taller than the window can expand ---
                let heightOverflow = localFrame.height - effectiveHeight
                if heightOverflow > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.red.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                        )
                        .frame(width: min(effectiveWidth, localFrame.width), height: heightOverflow)
                        .position(x: localFrame.minX + min(effectiveWidth, localFrame.width) / 2, y: localFrame.minY + min(effectiveHeight, localFrame.height) + heightOverflow / 2)
                }

                // --- Yellow: window is wider than the selection (can't shrink) ---
                let widthUnderflow = effectiveWidth - localFrame.width
                if widthUnderflow > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.yellow.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                        )
                        .frame(width: widthUnderflow, height: localFrame.height)
                        .position(x: localFrame.maxX + widthUnderflow / 2, y: localFrame.midY)
                }

                // --- Yellow: window is taller than the selection (can't shrink) ---
                let heightUnderflow = effectiveHeight - localFrame.height
                if heightUnderflow > 1 {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.yellow.opacity(0.35))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                        )
                        .frame(width: localFrame.width, height: heightUnderflow)
                        .position(x: localFrame.midX, y: localFrame.maxY + heightUnderflow / 2)
                }
            } else {
                // Fully resizable — normal display.
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(ThemeColors.overlaySelectionFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(ThemeColors.overlaySelectionBorder(for: colorScheme), lineWidth: 2)
                    )
                    .frame(width: localFrame.width, height: localFrame.height)
                    .position(x: localFrame.midX, y: localFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}

private struct GridPreviewOverlayView: View {
    @Environment(\.colorScheme) private var colorScheme
    let screenFrame: CGRect
    let visibleFrame: CGRect
    let rows: Int
    let columns: Int
    let gap: CGFloat

    var body: some View {
        let canvas = CGRect(
            x: visibleFrame.minX - screenFrame.minX,
            y: screenFrame.maxY - visibleFrame.maxY,
            width: visibleFrame.width,
            height: visibleFrame.height
        )
        let totalHorizontalGap = gap * CGFloat(max(0, columns - 1))
        let totalVerticalGap = gap * CGFloat(max(0, rows - 1))
        let cellWidth = (canvas.width - totalHorizontalGap) / CGFloat(columns)
        let cellHeight = (canvas.height - totalVerticalGap) / CGFloat(rows)

        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(ThemeColors.overlayBackground(for: colorScheme))
                .frame(width: canvas.width, height: canvas.height)
                .position(x: canvas.midX, y: canvas.midY)

            ForEach(0..<rows, id: \.self) { row in
                ForEach(0..<columns, id: \.self) { column in
                    let rect = CGRect(
                        x: canvas.minX + CGFloat(column) * (cellWidth + gap),
                        y: canvas.minY + CGFloat(row) * (cellHeight + gap),
                        width: cellWidth,
                        height: cellHeight
                    )
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ThemeColors.overlayCellFill(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(ThemeColors.overlayCellBorder(for: colorScheme), lineWidth: 1.25)
                        )
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}
