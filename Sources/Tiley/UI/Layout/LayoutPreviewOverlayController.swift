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

    func showSelection(_ selection: GridSelection, rows: Int, columns: Int, gap: CGFloat, behind parentWindow: NSWindow?, resizability: WindowResizability = .both, windowSize: CGSize? = nil, appIcon: NSImage? = nil, windowTitle: String? = nil, appName: String? = nil) {
        let frame = GridCalculator.frame(for: selection, in: visibleFrame, rows: rows, columns: columns, gap: gap)
        let rootView = SelectionPreviewOverlayView(
            frame: frame,
            resizability: resizability,
            windowSize: windowSize,
            screenFrame: screenFrame,
            appIcon: appIcon,
            windowTitle: windowTitle,
            appName: appName
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
    let appIcon: NSImage?
    let windowTitle: String?
    let appName: String?

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
                previewRect(width: displayWidth, height: displayHeight)
                    .position(x: localFrame.minX + displayWidth / 2, y: localFrame.minY + displayHeight / 2)

                // --- Red: unified overflow region (selection larger than window can expand) ---
                let widthOverflow = localFrame.width - effectiveWidth
                let heightOverflow = localFrame.height - effectiveHeight
                if widthOverflow > 1 || heightOverflow > 1 {
                    let outerRect = CGRect(
                        x: localFrame.minX,
                        y: localFrame.minY,
                        width: localFrame.width,
                        height: localFrame.height
                    )
                    let innerRect = CGRect(
                        x: localFrame.minX,
                        y: localFrame.minY,
                        width: displayWidth,
                        height: displayHeight
                    )
                    Path { path in
                        path.addRoundedRect(in: outerRect, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        path.addRoundedRect(in: innerRect, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                    }
                    .fill(Color.red.opacity(0.35), style: FillStyle(eoFill: true))
                    .overlay(
                        Path { path in
                            path.addRoundedRect(in: outerRect, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        }
                        .stroke(Color.red.opacity(0.7), lineWidth: 1.5)
                    )
                }

                // --- Yellow: unified underflow region (window larger than selection, can't shrink) ---
                let widthUnderflow = effectiveWidth - localFrame.width
                let heightUnderflow = effectiveHeight - localFrame.height
                if widthUnderflow > 1 || heightUnderflow > 1 {
                    let outerRect = CGRect(
                        x: localFrame.minX,
                        y: localFrame.minY,
                        width: localFrame.width + max(0, widthUnderflow),
                        height: localFrame.height + max(0, heightUnderflow)
                    )
                    Path { path in
                        path.addRoundedRect(in: outerRect, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        path.addRoundedRect(in: localFrame, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                    }
                    .fill(Color.yellow.opacity(0.35), style: FillStyle(eoFill: true))
                    .overlay(
                        Path { path in
                            path.addRoundedRect(in: outerRect, cornerSize: CGSize(width: 6, height: 6), style: .continuous)
                        }
                        .stroke(Color.yellow.opacity(0.7), lineWidth: 1.5)
                    )
                }
            } else {
                // Fully resizable — normal display.
                previewRect(width: localFrame.width, height: localFrame.height)
                    .position(x: localFrame.midX, y: localFrame.midY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.clear)
    }

    /// Builds the preview rectangle with an optional title bar (matching MiniatureWindowView style).
    @ViewBuilder
    private func previewRect(width: CGFloat, height: CGFloat) -> some View {
        let cornerRadius: CGFloat = 10
        // Use the actual system title bar height for a standard titled window.
        let titleBarHeight = NSWindow.frameRect(
            forContentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable]
        ).height
        let showTitleBar = height > titleBarHeight * 2 && width > 60

        ZStack(alignment: .top) {
            // Base fill + border
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ThemeColors.overlaySelectionFill(for: colorScheme))

            if showTitleBar {
                // Title bar background
                VStack(spacing: 0) {
                    ZStack {
                        Rectangle()
                            .fill(titleBarFill)
                        titleBarContent(height: titleBarHeight, totalWidth: width)
                    }
                    .frame(height: titleBarHeight)
                    Rectangle()
                        .fill(titleBarDividerColor)
                        .frame(height: 0.5)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                // Traffic light buttons
                trafficLightButtons(titleBarHeight: titleBarHeight)
            }

            // Border stroke on top of everything
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(ThemeColors.overlaySelectionBorder(for: colorScheme), lineWidth: 2)
        }
        .frame(width: width, height: height)
    }

    @ViewBuilder
    private func titleBarContent(height: CGFloat, totalWidth: CGFloat) -> some View {
        let fontSize: CGFloat = max(8, height * 0.48)
        let buttonDiameter = height * 0.38
        let buttonsTrailingEdge = buttonDiameter * 0.8 + buttonDiameter * 3 + buttonDiameter * 0.55 * 2 + buttonDiameter * 0.5
        let titleText: String? = {
            let t = (windowTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
            let a = (appName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !a.isEmpty { return a }
            return nil
        }()

        HStack(spacing: fontSize * 0.4) {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: height * 0.55, height: height * 0.55)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            }
            if let titleText {
                Text(titleText)
                    .font(.system(size: fontSize))
                    .foregroundStyle(titleBarTextColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, buttonsTrailingEdge)
    }

    @ViewBuilder
    private func trafficLightButtons(titleBarHeight: CGFloat) -> some View {
        let buttonDiameter = titleBarHeight * 0.38
        let buttonSpacing = buttonDiameter * 0.55
        let buttonLeftPadding = buttonDiameter * 0.8

        HStack(spacing: buttonSpacing) {
            Circle()
                .fill(Color(red: 1.0, green: 0.373, blue: 0.341))
            Circle()
                .fill(Color(red: 0.996, green: 0.737, blue: 0.180))
            Circle()
                .fill(Color(red: 0.157, green: 0.784, blue: 0.251))
        }
        .frame(height: buttonDiameter)
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.leading, buttonLeftPadding)
        .padding(.top, (titleBarHeight - buttonDiameter) / 2)
    }

    // MARK: - Title bar colors

    private var titleBarFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.14)
            : Color.white.opacity(0.65)
    }

    private var titleBarDividerColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.12)
            : Color.black.opacity(0.10)
    }

    private var titleBarTextColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.70)
            : Color.black.opacity(0.55)
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ThemeColors.overlayCellFill(for: colorScheme))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
