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

    func showSelection(_ selection: GridSelection, rows: Int, columns: Int, gap: CGFloat, behind parentWindow: NSWindow?) {
        let rootView = SelectionPreviewOverlayView(
            frame: GridCalculator.frame(for: selection, in: visibleFrame, rows: rows, columns: columns, gap: gap),
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
        if let parentWindow = attachedParentWindow, let window {
            parentWindow.removeChildWindow(window)
        }
        attachedParentWindow = nil
        window?.orderOut(nil)
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
    let frame: CGRect
    let screenFrame: CGRect

    var body: some View {
        let localFrame = CGRect(
            x: frame.minX - screenFrame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(red: 0.16, green: 0.49, blue: 0.93).opacity(0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.88), lineWidth: 2)
                )
                .frame(width: localFrame.width, height: localFrame.height)
                .position(x: localFrame.midX, y: localFrame.midY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }
}

private struct GridPreviewOverlayView: View {
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
                .fill(Color.black.opacity(0.06))
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
                        .fill(Color(red: 0.16, green: 0.49, blue: 0.93).opacity(0.18))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.55), lineWidth: 1.25)
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
