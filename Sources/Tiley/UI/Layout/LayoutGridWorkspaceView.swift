import SwiftUI

struct LayoutGridWorkspaceView: View {
    let rows: Int
    let columns: Int
    let gap: CGFloat
    var highlightSelection: GridSelection?
    var desktopPictureURL: URL?
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
            ZStack(alignment: .topLeading) {
                if let url = desktopPictureURL,
                   let nsImage = NSImage(contentsOf: url) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(0.5)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let frame = rectForCell(row: row, column: column, width: cellWidth, height: cellHeight)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(fillColor(forRow: row, column: column))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(borderColor(forRow: row, column: column), lineWidth: 1.5)
                            )
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
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



    private func isHovered(row: Int, column: Int) -> Bool {
        guard let hover = hoverCell, !isDragging else { return false }
        return hover.row == row && hover.column == column
    }

    private func isHighlighted(row: Int, column: Int) -> Bool {
        guard let hl = highlightSelection?.normalized, activeSelection == nil else { return false }
        return hl.startRow...hl.endRow ~= row && hl.startColumn...hl.endColumn ~= column
    }

    private func fillColor(forRow row: Int, column: Int) -> Color {
        if let selection = activeSelection?.normalized,
           selection.startRow...selection.endRow ~= row,
           selection.startColumn...selection.endColumn ~= column {
            return ThemeColors.gridCellSelectedFill(for: colorScheme)
        }
        if isHovered(row: row, column: column) {
            return ThemeColors.gridCellHoverFill(for: colorScheme)
        }
        if isHighlighted(row: row, column: column) {
            return ThemeColors.gridCellHighlightFill(for: colorScheme)
        }
        return ThemeColors.gridCellFill(for: colorScheme)
    }

    private func borderColor(forRow row: Int, column: Int) -> Color {
        if let selection = activeSelection?.normalized,
           selection.startRow...selection.endRow ~= row,
           selection.startColumn...selection.endColumn ~= column {
            return ThemeColors.gridCellSelectedBorder(for: colorScheme)
        }
        if isHovered(row: row, column: column) {
            return ThemeColors.gridCellHoverBorder(for: colorScheme)
        }
        if isHighlighted(row: row, column: column) {
            return ThemeColors.gridCellHighlightBorder(for: colorScheme)
        }
        return ThemeColors.gridCellBorder(for: colorScheme)
    }
}
