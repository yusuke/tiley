import SwiftUI

struct LayoutGridWorkspaceView: View {
    let rows: Int
    let columns: Int
    let gap: CGFloat
    var highlightSelection: GridSelection?
    var desktopPictureInfo: MainWindowView.DesktopPictureInfo?
    /// When false, wallpaper background is not rendered (used when the parent
    /// composite view renders the wallpaper at a larger scale).
    var showDesktopPicture: Bool = true
    var windowFrameRelative: WindowFrameRelative?
    let onSelectionChange: (GridSelection?) -> Void
    let onHoverChange: ((GridSelection?) -> Void)?
    let onSelectionCommit: (GridSelection) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var dragSelection: GridSelection?
    @State private var dragStart: (row: Int, column: Int)?
    @State private var isDragging = false
    @State private var isOutsideGrid = false
    @State private var hoverCell: (row: Int, column: Int)?

    var body: some View {
        GeometryReader { geometry in
            let cellWidth = (geometry.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
            let cellHeight = (geometry.size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
            let cellCornerRadius = max(2, min(cellWidth, cellHeight) * 0.02)
            ZStack(alignment: .topLeading) {
                if showDesktopPicture,
                   let info = desktopPictureInfo,
                   let nsImage = NSImage(contentsOf: info.url) {
                    DesktopPictureBackgroundView(nsImage: nsImage, info: info, size: geometry.size)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous))
                }

                // Miniature window showing current window position
                if let wf = windowFrameRelative, wf.width > 0, wf.height > 0 {
                    let winW = wf.width * geometry.size.width
                    let winH = wf.height * geometry.size.height
                    let winX = wf.x * geometry.size.width + winW / 2
                    let winY = wf.y * geometry.size.height + winH / 2
                    let titleBarPx = max(4, wf.menuBarHeightFraction * geometry.size.height)
                    MiniatureWindowView(
                        titleBarHeight: titleBarPx,
                        appIcon: wf.appIcon,
                        windowTitle: wf.windowTitle,
                        appName: wf.appName
                    )
                    .frame(width: winW, height: winH)
                    .position(x: winX, y: winY)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .allowsHitTesting(false)
                }

                // Base grid cells (non-selected appearance only)
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let frame = rectForCell(row: row, column: column, width: cellWidth, height: cellHeight)
                        let isInSelection = isSelected(row: row, column: column)
                        let isInHighlight = isHighlighted(row: row, column: column)
                        if !isInSelection && !isInHighlight {
                            RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                .fill(isHovered(row: row, column: column)
                                      ? ThemeColors.gridCellHoverFill(for: colorScheme)
                                      : ThemeColors.gridCellFill(for: colorScheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                        .stroke(isHovered(row: row, column: column)
                                                ? ThemeColors.gridCellHoverBorder(for: colorScheme)
                                                : ThemeColors.gridCellBorder(for: colorScheme), lineWidth: 1.5)
                                )
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        } else {
                            // Transparent placeholder so the grid spacing is preserved
                            Color.clear
                                .frame(width: frame.width, height: frame.height)
                                .position(x: frame.midX, y: frame.midY)
                        }
                    }
                }

                // Unified highlight rectangle (from highlightSelection)
                if let hl = highlightSelection?.normalized, activeSelection == nil {
                    let selRect = rectForSelection(hl, cellWidth: cellWidth, cellHeight: cellHeight)
                    selectionRectangle(
                        sel: hl, selRect: selRect,
                        cellWidth: cellWidth, cellHeight: cellHeight,
                        cornerRadius: cellCornerRadius,
                        fill: ThemeColors.gridCellHighlightFill(for: colorScheme),
                        border: ThemeColors.gridCellHighlightBorder(for: colorScheme),
                        divider: ThemeColors.gridCellHighlightBorder(for: colorScheme).opacity(0.3)
                    )
                }

                // Unified drag selection rectangle
                if let sel = activeSelection?.normalized {
                    let selRect = rectForSelection(sel, cellWidth: cellWidth, cellHeight: cellHeight)
                    selectionRectangle(
                        sel: sel, selRect: selRect,
                        cellWidth: cellWidth, cellHeight: cellHeight,
                        cornerRadius: cellCornerRadius,
                        fill: ThemeColors.gridCellSelectedFill(for: colorScheme),
                        border: ThemeColors.gridCellSelectedBorder(for: colorScheme),
                        divider: ThemeColors.gridCellSelectedBorder(for: colorScheme).opacity(0.3)
                    )
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !isDragging else { return }
                switch phase {
                case .active(let location):
                    let hoveredCell = cell(at: location, cellWidth: cellWidth, cellHeight: cellHeight)
                    if hoverCell?.row != hoveredCell.row || hoverCell?.column != hoveredCell.column {
                        hoverCell = hoveredCell
                        let hoverSelection = GridSelection(
                            startColumn: hoveredCell.column,
                            startRow: hoveredCell.row,
                            endColumn: hoveredCell.column,
                            endRow: hoveredCell.row
                        )
                        onHoverChange?(hoverSelection)
                    }
                case .ended:
                    hoverCell = nil
                    onHoverChange?(nil)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        hoverCell = nil
                        onHoverChange?(nil)
                        guard isInsideGrid(value.location, in: geometry.size) else {
                            isOutsideGrid = true
                            dragSelection = nil
                            onSelectionChange(nil)
                            return
                        }
                        isOutsideGrid = false
                        let cell = cell(at: value.location, cellWidth: cellWidth, cellHeight: cellHeight)
                        if dragStart == nil {
                            dragStart = cell
                        }
                        updateSelection(row: cell.row, column: cell.column)
                    }
                    .onEnded { value in
                        isDragging = false
                        isOutsideGrid = false
                        guard isInsideGrid(value.location, in: geometry.size),
                              let _ = dragStart else {
                            dragSelection = nil
                            dragStart = nil
                            onSelectionChange(nil)
                            return
                        }
                        let cell = cell(at: value.location, cellWidth: cellWidth, cellHeight: cellHeight)
                        let selection = updateSelection(row: cell.row, column: cell.column)
                        dragSelection = nil
                        dragStart = nil
                        onSelectionChange(nil)
                        onSelectionCommit(selection)
                    }
            )
        }
    }

    private var activeSelection: GridSelection? {
        dragSelection
    }

    private func rectForCell(row: Int, column: Int, width: CGFloat, height: CGFloat) -> CGRect {
        CGRect(
            x: CGFloat(column) * (width + gap),
            y: CGFloat(row) * (height + gap),
            width: width,
            height: height
        )
    }

    /// Returns a single rectangle spanning from the top-left of the start cell
    /// to the bottom-right of the end cell (inclusive of gaps between cells).
    private func rectForSelection(_ sel: GridSelection, cellWidth: CGFloat, cellHeight: CGFloat) -> CGRect {
        let topLeft = rectForCell(row: sel.startRow, column: sel.startColumn, width: cellWidth, height: cellHeight)
        let bottomRight = rectForCell(row: sel.endRow, column: sel.endColumn, width: cellWidth, height: cellHeight)
        return CGRect(
            x: topLeft.minX,
            y: topLeft.minY,
            width: bottomRight.maxX - topLeft.minX,
            height: bottomRight.maxY - topLeft.minY
        )
    }

    private func cell(at location: CGPoint, cellWidth: CGFloat, cellHeight: CGFloat) -> (row: Int, column: Int) {
        let column = min(columns - 1, max(0, Int(location.x / (cellWidth + gap))))
        let row = min(rows - 1, max(0, Int(location.y / (cellHeight + gap))))
        return (row: row, column: column)
    }

    private func isInsideGrid(_ location: CGPoint, in size: CGSize) -> Bool {
        location.x >= 0 && location.y >= 0 && location.x <= size.width && location.y <= size.height
    }

    @discardableResult
    private func updateSelection(row: Int, column: Int) -> GridSelection {
        let start = dragStart ?? (row: row, column: column)
        let selection = GridSelection(
            startColumn: start.column,
            startRow: start.row,
            endColumn: column,
            endRow: row
        ).normalized
        dragSelection = selection
        onSelectionChange(selection)
        return selection
    }



    /// Draws a unified selection rectangle with thin internal cell divider lines.
    @ViewBuilder
    private func selectionRectangle(
        sel: GridSelection,
        selRect: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        cornerRadius: CGFloat,
        fill: Color,
        border: Color,
        divider: Color
    ) -> some View {
        let spanCols = sel.endColumn - sel.startColumn + 1
        let spanRows = sel.endRow - sel.startRow + 1

        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                // Internal cell divider lines (clipped to the rounded rect)
                Canvas { context, size in
                    // Vertical dividers
                    for i in 1..<spanCols {
                        let x = CGFloat(i) * (cellWidth + gap) - gap / 2
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(divider), lineWidth: 0.5)
                    }
                    // Horizontal dividers
                    for i in 1..<spanRows {
                        let y = CGFloat(i) * (cellHeight + gap) - gap / 2
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                        context.stroke(path, with: .color(divider), lineWidth: 0.5)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(border, lineWidth: 1.5)
            )
            .frame(width: selRect.width, height: selRect.height)
            .position(x: selRect.midX, y: selRect.midY)
    }

    private func isSelected(row: Int, column: Int) -> Bool {
        guard let sel = activeSelection?.normalized else { return false }
        return sel.startRow...sel.endRow ~= row && sel.startColumn...sel.endColumn ~= column
    }

    private func isHovered(row: Int, column: Int) -> Bool {
        guard let hover = hoverCell, !isDragging else { return false }
        return hover.row == row && hover.column == column
    }

    private func isHighlighted(row: Int, column: Int) -> Bool {
        guard let hl = highlightSelection?.normalized, activeSelection == nil else { return false }
        return hl.startRow...hl.endRow ~= row && hl.startColumn...hl.endColumn ~= column
    }

}

