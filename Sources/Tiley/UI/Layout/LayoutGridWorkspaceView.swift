import SwiftUI

struct LayoutGridWorkspaceView: View {
    let rows: Int
    let columns: Int
    let gap: CGFloat
    var highlightSelection: GridSelection?
    /// Multiple highlight selections for preset hover/keyboard preview (no index labels, no delete buttons).
    var highlightSelections: [GridSelection] = []
    /// Window info to display as title bars on highlight selections during preset hover.
    var highlightWindowInfo: [AppState.PresetHoverWindowInfo] = []
    var desktopPictureInfo: MainWindowView.DesktopPictureInfo?
    /// When false, wallpaper background is not rendered (used when the parent
    /// composite view renders the wallpaper at a larger scale).
    var showDesktopPicture: Bool = true
    var windowFrameRelative: WindowFrameRelative?
    /// When false, the static miniature window showing the current window position is hidden.
    var showStaticWindowPreview: Bool = true
    /// Resize preview frame shown during resize menu hover.
    var resizePreviewRelativeFrame: WindowFrameRelative?
    /// Insets from grid edges that correspond to physical screen edges (not menu bar/Dock).
    var screenEdgeInsets: EdgeInsets = EdgeInsets()
    /// Committed selections displayed in edit mode (indexed from 0).
    var committedSelections: [GridSelection] = []
    /// Called when the user clicks the "x" button on a committed selection.
    var onDeleteSelection: ((Int) -> Void)?
    /// When true, drag interactions are disabled and a "No windows" message is shown.
    var isDragDisabled: Bool = false
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

                // "No windows" overlay when drag is disabled (no target window)
                if isDragDisabled {
                    VStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.12))
                            .foregroundStyle(.primary)
                        Text(NSLocalizedString("No windows", comment: "Shown in the grid when there are no windows to arrange"))
                            .font(.system(size: min(geometry.size.width, geometry.size.height) * 0.06, weight: .medium))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .allowsHitTesting(false)
                }

                // Miniature window showing current window position
                // Hidden when highlight window info is shown or resize preview is active.
                if showStaticWindowPreview,
                   !isDragDisabled, highlightWindowInfo.isEmpty, resizePreviewRelativeFrame == nil,
                   let wf = windowFrameRelative, wf.width > 0, wf.height > 0 {
                    let winW = wf.width * geometry.size.width
                    let winH = wf.height * geometry.size.height
                    let winX = wf.x * geometry.size.width + winW / 2
                    let winY = wf.y * geometry.size.height + winH / 2
                    let titleBarPx = max(4, wf.menuBarHeightFraction * geometry.size.height * 1.5)
                    MiniatureWindowView(
                        titleBarHeight: titleBarPx,
                        appIcon: wf.appIcon,
                        appName: wf.appName,
                        windowTitle: wf.windowTitle
                    )
                    .frame(width: winW, height: winH)
                    .position(x: winX, y: winY)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .allowsHitTesting(false)
                }

                // Resize preview (shown during resize menu hover)
                if let rf = resizePreviewRelativeFrame, rf.width > 0, rf.height > 0 {
                    let rW = rf.width * geometry.size.width
                    let rH = rf.height * geometry.size.height
                    let rX = rf.x * geometry.size.width + rW / 2
                    let rY = rf.y * geometry.size.height + rH / 2
                    let titleBarPx = max(4, rf.menuBarHeightFraction * geometry.size.height * 1.5)
                    MiniatureWindowView(
                        titleBarHeight: titleBarPx,
                        appIcon: rf.appIcon,
                        appName: rf.appName,
                        windowTitle: rf.windowTitle
                    )
                    .frame(width: rW, height: rH)
                    .position(x: rX, y: rY)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .allowsHitTesting(false)
                }

                // Base grid cells (non-selected appearance only)
                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let frame = rectForCell(row: row, column: column, width: cellWidth, height: cellHeight)
                        // When a miniature window is overlaid, keep grid cells visible under the drag selection.
                        let isInSelection = windowFrameRelative == nil && isSelected(row: row, column: column)
                        let isInHighlight = isHighlighted(row: row, column: column)
                        let isInCommitted = isInCommittedSelection(row: row, column: column)
                        let isInMultiHighlight = isInHighlightSelections(row: row, column: column)
                        if !isInSelection && !isInHighlight && !isInCommitted && !isInMultiHighlight {
                            let hovered = isHovered(row: row, column: column)
                            // In edit mode, the hover preview is rendered as a dedicated
                            // committed-style rectangle overlay, so suppress the per-cell
                            // hover fill here. Also suppressed when a miniature window is
                            // overlaid.
                            let showHoverFill = hovered && windowFrameRelative == nil && onDeleteSelection == nil
                            RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                .fill(showHoverFill
                                      ? ThemeColors.gridCellHoverFill(for: colorScheme)
                                      : ThemeColors.gridCellFill(for: colorScheme))
                                .overlay(
                                    RoundedRectangle(cornerRadius: cellCornerRadius, style: .continuous)
                                        .stroke(showHoverFill
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

                // Single-cell hover preview during preset editing —
                // rendered as a committed-style rectangle (no delete button, no title bar)
                // tinted with the next index's color. Suppressed on cells that are already
                // part of a committed selection.
                if onDeleteSelection != nil,
                   let hover = hoverCell, !isDragging, activeSelection == nil,
                   highlightSelection == nil, highlightSelections.isEmpty,
                   !isInCommittedSelection(row: hover.row, column: hover.column) {
                    let nextIndex = committedSelections.count
                    let hoverSel = GridSelection(
                        startColumn: hover.column, startRow: hover.row,
                        endColumn: hover.column, endRow: hover.row
                    )
                    let inset: CGFloat = committedSelections.isEmpty ? 0 : 1
                    let hoverRect = rectForSelection(hoverSel, cellWidth: cellWidth, cellHeight: cellHeight)
                        .insetBy(dx: inset, dy: inset)
                    let fill = ThemeColors.indexedSelectionFill(index: nextIndex, for: colorScheme)
                    let border = ThemeColors.indexedSelectionBorder(index: nextIndex, for: colorScheme)
                    committedSelectionRectangle(
                        index: nextIndex,
                        sel: hoverSel, selRect: hoverRect,
                        cellWidth: cellWidth, cellHeight: cellHeight,
                        cornerRadius: cellCornerRadius,
                        fill: fill, border: border,
                        divider: border.opacity(0.3),
                        showDelete: false
                    )
                }

                // Miniature window overlay on single-cell hover (non-edit mode —
                // previewing window placement before drag).
                if onDeleteSelection == nil,
                   let hover = hoverCell, !isDragging, activeSelection == nil,
                   highlightSelection == nil, highlightSelections.isEmpty,
                   committedSelections.isEmpty,
                   let wf = windowFrameRelative {
                    let frame = rectForCell(row: hover.row, column: hover.column, width: cellWidth, height: cellHeight)
                        .insetBy(dx: 1, dy: 1)
                    let menuBarFraction = wf.menuBarHeightFraction
                    let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                    let staticW = wf.width * geometry.size.width
                    let staticH = wf.height * geometry.size.height
                    let matchedRadius = max(2, min(staticW, staticH) * MiniatureWindowView.cornerRadiusFraction)
                    MiniatureWindowView(
                        titleBarHeight: titleBarPx,
                        appIcon: wf.appIcon,
                        appName: wf.appName,
                        windowTitle: wf.windowTitle,
                        cornerRadiusOverride: matchedRadius,
                        tintColor: ThemeColors.indexedSelectionFill(index: 0, for: colorScheme)
                    )
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .allowsHitTesting(false)
                }

                // Committed selections (edit mode)
                ForEach(Array(committedSelections.enumerated()), id: \.offset) { index, sel in
                    let norm = sel.normalized
                    let selRect = rectForSelection(norm, cellWidth: cellWidth, cellHeight: cellHeight)
                        .insetBy(dx: committedSelections.count > 1 ? 1 : 0,
                                 dy: committedSelections.count > 1 ? 1 : 0)
                    let fill = ThemeColors.indexedSelectionFill(index: index, for: colorScheme)
                    let border = ThemeColors.indexedSelectionBorder(index: index, for: colorScheme)
                    committedSelectionRectangle(
                        index: index,
                        sel: norm, selRect: selRect,
                        cellWidth: cellWidth, cellHeight: cellHeight,
                        cornerRadius: cellCornerRadius,
                        fill: fill, border: border,
                        divider: border.opacity(0.3),
                        showDelete: onDeleteSelection != nil
                    )
                }

                // Multiple highlight selections (preset hover with secondary selections)
                if !highlightSelections.isEmpty, activeSelection == nil, committedSelections.isEmpty {
                    let showHighlightIndex = highlightSelections.count > 1
                    let multiInset: CGFloat = highlightSelections.count > 1 ? 1 : 0
                    ForEach(Array(highlightSelections.enumerated()), id: \.offset) { index, sel in
                        let norm = sel.normalized
                        let selRect = rectForSelection(norm, cellWidth: cellWidth, cellHeight: cellHeight)
                            .insetBy(dx: multiInset, dy: multiInset)
                        let tint = ThemeColors.indexedSelectionFill(index: index, for: colorScheme)

                        if index < highlightWindowInfo.count {
                            let info = highlightWindowInfo[index]
                            let menuBarFraction = windowFrameRelative?.menuBarHeightFraction ?? 0.03
                            let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                            MiniatureWindowView(
                                titleBarHeight: titleBarPx,
                                appIcon: info.appIcon,
                                appName: info.appName,
                                windowTitle: info.windowTitle.isEmpty ? nil : info.windowTitle,
                                tintColor: tint
                            )
                            .frame(width: selRect.width, height: selRect.height)
                            .position(x: selRect.midX, y: selRect.midY)
                            .allowsHitTesting(false)
                            .overlay {
                                if showHighlightIndex {
                                    Text("\(index + 1)")
                                        .font(.system(size: min(selRect.width, selRect.height) * 0.35, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                                        .frame(width: selRect.width, height: selRect.height)
                                        .position(x: selRect.midX, y: selRect.midY)
                                }
                            }
                        } else {
                            // Fallback: no window info available, show colored rectangle
                            let border = ThemeColors.indexedSelectionBorder(index: index, for: colorScheme)
                            committedSelectionRectangle(
                                index: index,
                                sel: norm, selRect: selRect,
                                cellWidth: cellWidth, cellHeight: cellHeight,
                                cornerRadius: cellCornerRadius,
                                fill: tint, border: border,
                                divider: border.opacity(0.3),
                                showIndex: showHighlightIndex,
                                showDelete: false
                            )
                        }
                    }
                }

                // Unified highlight (from highlightSelection, single)
                if let hl = highlightSelection?.normalized, activeSelection == nil, committedSelections.isEmpty, highlightSelections.isEmpty {
                    let selRect = rectForSelection(hl, cellWidth: cellWidth, cellHeight: cellHeight)
                        .insetBy(dx: 1, dy: 1)
                    let tint = ThemeColors.gridCellHighlightFill(for: colorScheme)

                    if let info = highlightWindowInfo.first {
                        let menuBarFraction = windowFrameRelative?.menuBarHeightFraction ?? 0.03
                        let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                        MiniatureWindowView(
                            titleBarHeight: titleBarPx,
                            appIcon: info.appIcon,
                            appName: info.appName,
                            windowTitle: info.windowTitle.isEmpty ? nil : info.windowTitle,
                            tintColor: tint
                        )
                        .frame(width: selRect.width, height: selRect.height)
                        .position(x: selRect.midX, y: selRect.midY)
                        .allowsHitTesting(false)
                    } else {
                        selectionRectangle(
                            sel: hl, selRect: selRect,
                            cellWidth: cellWidth, cellHeight: cellHeight,
                            cornerRadius: cellCornerRadius,
                            fill: tint,
                            border: ThemeColors.gridCellHighlightBorder(for: colorScheme),
                            divider: ThemeColors.gridCellHighlightBorder(for: colorScheme).opacity(0.3)
                        )
                    }
                }

                // Unified drag selection rectangle
                if let sel = activeSelection?.normalized {
                    let selRect = rectForSelection(sel, cellWidth: cellWidth, cellHeight: cellHeight)
                    let overlaps = dragOverlapsCommitted
                    let nextIndex = committedSelections.count
                    let isEditMode = onDeleteSelection != nil

                    if isEditMode {
                        // Edit mode: render a committed-style rectangle (no title bar,
                        // no delete button) with the next-index number centered. On
                        // overlap with an existing committed selection, fall back to the
                        // invalid-selection appearance.
                        let inset: CGFloat = committedSelections.isEmpty ? 0 : 1
                        let dragRect = selRect.insetBy(dx: inset, dy: inset)
                        if overlaps {
                            selectionRectangle(
                                sel: sel, selRect: dragRect,
                                cellWidth: cellWidth, cellHeight: cellHeight,
                                cornerRadius: cellCornerRadius,
                                fill: ThemeColors.invalidSelectionFill(for: colorScheme),
                                border: ThemeColors.invalidSelectionBorder(for: colorScheme),
                                divider: ThemeColors.invalidSelectionBorder(for: colorScheme).opacity(0.3)
                            )
                        } else {
                            let fill = ThemeColors.indexedSelectionFill(index: nextIndex, for: colorScheme)
                            let border = ThemeColors.indexedSelectionBorder(index: nextIndex, for: colorScheme)
                            committedSelectionRectangle(
                                index: nextIndex,
                                sel: sel, selRect: dragRect,
                                cellWidth: cellWidth, cellHeight: cellHeight,
                                cornerRadius: cellCornerRadius,
                                fill: fill, border: border,
                                divider: border.opacity(0.3),
                                showDelete: false
                            )
                        }
                    } else {
                        // Non-edit mode: preview where the target window will land, using
                        // a miniature window overlay (or a plain rectangle when no window
                        // frame is available).
                        let usesIndexedColor = !committedSelections.isEmpty
                        let fillColor = overlaps ? ThemeColors.invalidSelectionFill(for: colorScheme)
                            : usesIndexedColor ? ThemeColors.indexedSelectionFill(index: nextIndex, for: colorScheme)
                            : ThemeColors.gridCellSelectedFill(for: colorScheme)
                        let borderColor = overlaps ? ThemeColors.invalidSelectionBorder(for: colorScheme)
                            : usesIndexedColor ? ThemeColors.indexedSelectionBorder(index: nextIndex, for: colorScheme)
                            : ThemeColors.gridCellSelectedBorder(for: colorScheme)
                        if windowFrameRelative == nil {
                            selectionRectangle(
                                sel: sel, selRect: selRect,
                                cellWidth: cellWidth, cellHeight: cellHeight,
                                cornerRadius: cellCornerRadius,
                                fill: fillColor,
                                border: borderColor,
                                divider: borderColor.opacity(0.3)
                            )
                        } else if let wf = windowFrameRelative {
                            let insetRect = selRect.insetBy(dx: 1, dy: 1)
                            let menuBarFraction = wf.menuBarHeightFraction
                            let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                            let staticW = wf.width * geometry.size.width
                            let staticH = wf.height * geometry.size.height
                            let matchedRadius = max(2, min(staticW, staticH) * MiniatureWindowView.cornerRadiusFraction)
                            let tint: Color = overlaps
                                ? ThemeColors.invalidSelectionFill(for: colorScheme)
                                : ThemeColors.indexedSelectionFill(
                                    index: usesIndexedColor ? nextIndex : 0,
                                    for: colorScheme
                                )
                            MiniatureWindowView(
                                titleBarHeight: titleBarPx,
                                appIcon: wf.appIcon,
                                appName: wf.appName,
                                windowTitle: wf.windowTitle,
                                cornerRadiusOverride: matchedRadius,
                                tintColor: tint
                            )
                            .frame(width: insetRect.width, height: insetRect.height)
                            .position(x: insetRect.midX, y: insetRect.midY)
                            .allowsHitTesting(false)
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                guard !isDragging, !isDragDisabled else { return }
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
                        guard !isDragDisabled else { return }
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
                        guard !isDragDisabled else { return }
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
                        let overlaps = dragOverlapsCommitted
                        dragSelection = nil
                        dragStart = nil
                        onSelectionChange(nil)
                        if !overlaps {
                            onSelectionCommit(selection)
                        }
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
    /// Applies `screenEdgeInsets` when the selection touches a grid edge.
    private func rectForSelection(_ sel: GridSelection, cellWidth: CGFloat, cellHeight: CGFloat) -> CGRect {
        let topLeft = rectForCell(row: sel.startRow, column: sel.startColumn, width: cellWidth, height: cellHeight)
        let bottomRight = rectForCell(row: sel.endRow, column: sel.endColumn, width: cellWidth, height: cellHeight)
        var x = topLeft.minX
        var y = topLeft.minY
        var w = bottomRight.maxX - topLeft.minX
        var h = bottomRight.maxY - topLeft.minY
        if sel.startColumn == 0 { x += screenEdgeInsets.leading; w -= screenEdgeInsets.leading }
        if sel.endColumn == columns - 1 { w -= screenEdgeInsets.trailing }
        if sel.startRow == 0 { y += screenEdgeInsets.top; h -= screenEdgeInsets.top }
        if sel.endRow == rows - 1 { h -= screenEdgeInsets.bottom }
        return CGRect(x: x, y: y, width: w, height: h)
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
        guard let hl = highlightSelection?.normalized, activeSelection == nil, committedSelections.isEmpty else { return false }
        return hl.startRow...hl.endRow ~= row && hl.startColumn...hl.endColumn ~= column
    }

    private func isInCommittedSelection(row: Int, column: Int) -> Bool {
        committedSelections.contains { sel in
            let n = sel.normalized
            return n.startRow...n.endRow ~= row && n.startColumn...n.endColumn ~= column
        }
    }

    private func isInHighlightSelections(row: Int, column: Int) -> Bool {
        guard !highlightSelections.isEmpty, activeSelection == nil, committedSelections.isEmpty else { return false }
        return highlightSelections.contains { sel in
            let n = sel.normalized
            return n.startRow...n.endRow ~= row && n.startColumn...n.endColumn ~= column
        }
    }

    /// Whether the current drag selection overlaps any committed selection.
    private var dragOverlapsCommitted: Bool {
        guard let drag = activeSelection?.normalized else { return false }
        return committedSelections.contains { drag.overlaps($0) }
    }

    /// Draws a committed selection rectangle with index label and optional delete button.
    @ViewBuilder
    private func committedSelectionRectangle(
        index: Int,
        sel: GridSelection,
        selRect: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        cornerRadius: CGFloat,
        fill: Color,
        border: Color,
        divider: Color,
        showIndex: Bool = true,
        showDelete: Bool
    ) -> some View {
        let spanCols = sel.endColumn - sel.startColumn + 1
        let spanRows = sel.endRow - sel.startRow + 1

        // Anchor the fill to the rectangle (sized via .frame) and layer
        // dividers, border, label and delete button as overlays. This avoids
        // a ZStack-with-mixed-children sizing pitfall where the fill could
        // collapse and the rectangle would render invisible.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(fill)
            .overlay(
                Canvas { context, size in
                    for i in 1..<spanCols {
                        let x = CGFloat(i) * (cellWidth + gap) - gap / 2
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(divider), lineWidth: 0.5)
                    }
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
            .overlay(alignment: .center) {
                if showIndex {
                    Text("\(index + 1)")
                        .font(.system(size: min(selRect.width, selRect.height) * 0.35, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
            }
            .overlay(alignment: .topLeading) {
                if showDelete {
                    Button {
                        onDeleteSelection?(index)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: min(14, min(selRect.width, selRect.height) * 0.22)))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                }
            }
            .frame(width: selRect.width, height: selRect.height)
            .position(x: selRect.midX, y: selRect.midY)
    }

}

