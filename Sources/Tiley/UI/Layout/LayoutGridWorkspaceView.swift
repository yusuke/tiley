import SwiftUI

struct LayoutGridWorkspaceView: View {
    let rows: Int
    let columns: Int
    let gap: CGFloat
    var highlightSelection: GridSelection?
    var desktopPictureInfo: MainWindowView.DesktopPictureInfo?
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
                if let info = desktopPictureInfo,
                   let nsImage = NSImage(contentsOf: info.url) {
                    desktopPictureView(nsImage: nsImage, info: info, size: geometry.size)
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

    /// Returns the frame size for a Fill-mode image that fully covers `grid` with no gaps.
    /// Scales the image uniformly so both dimensions are >= the grid dimensions.
    private func fillFrameSize(image: CGSize, grid: CGSize) -> CGSize {
        let imgW = image.width
        let imgH = max(1, image.height)
        let scaleX = grid.width / imgW
        let scaleY = grid.height / imgH
        let scale = max(scaleX, scaleY)
        return CGSize(width: imgW * scale, height: imgH * scale)
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

    // MARK: - Desktop picture rendering

    @ViewBuilder
    private func desktopPictureView(nsImage: NSImage, info: MainWindowView.DesktopPictureInfo, size: CGSize) -> some View {
        let scalingValue = info.scaling
        let allowClipping = info.allowClipping
        let bg = info.fillColor ?? Color.black
        let _ = MainWindowView.tileyLog("desktopPictureView: gridSize=\(size) nsImage.size=\(nsImage.size) isTiled=\(info.isTiled) allowClipping=\(allowClipping) scalingValue=\(scalingValue) originalImageSize=\(String(describing: info.originalImageSize))")

        // Tile: both imageScaling and allowClipping keys are absent in desktopImageOptions.
        // macOS renders tiles at 1 image pixel = 1 physical pixel, so the tile's point size on
        // screen is (imagePixels / backingScaleFactor). We then scale that point size down by the
        // ratio of the grid width to the screen point width to match the visual density.
        if info.isTiled {
            // Use the original wallpaper pixel size if available (e.g. when a thumbnail is used
            // as a proxy for a system wallpaper). Falls back to the image's own reported size.
            let imagePixelSize = info.originalImageSize ?? nsImage.size
            // Point size of one tile on the real screen
            let tilePtOnScreen = CGSize(
                width: imagePixelSize.width / info.screenScale,
                height: imagePixelSize.height / info.screenScale
            )
            // Ratio of grid to screen in points
            let gridScale = info.screenSize.width > 0 ? size.width / info.screenSize.width : 1.0
            let tileSize = CGSize(
                width: tilePtOnScreen.width * gridScale,
                height: tilePtOnScreen.height * gridScale
            )
            Canvas { ctx, canvasSize in
                guard let resolvedImage = ctx.resolveSymbol(id: 0) else { return }
                // macOS tiles from the bottom-left corner, so anchor the grid at the bottom.
                // Start Y at the largest multiple of tileHeight that is <= canvasHeight,
                // measured from the bottom (i.e. the first tile row's top edge in SwiftUI coords).
                let startY = canvasSize.height.truncatingRemainder(dividingBy: tileSize.height)
                var x: CGFloat = 0
                while x < canvasSize.width {
                    var y: CGFloat = startY - tileSize.height
                    while y < canvasSize.height {
                        ctx.draw(resolvedImage, in: CGRect(origin: CGPoint(x: x, y: y), size: tileSize))
                        y += tileSize.height
                    }
                    x += tileSize.width
                }
            } symbols: {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: tileSize.width, height: tileSize.height)
                    .tag(0)
            }
            .frame(width: size.width, height: size.height)

        // scaleAxesIndependently (= 1): stretch to fill
        } else if scalingValue == NSImageScaling.scaleAxesIndependently.rawValue {
            Image(nsImage: nsImage)
                .resizable(resizingMode: .stretch)
                .frame(width: size.width, height: size.height)

        // scaleNone (= 2): center at 1:1 physical pixel ratio, with fill color background
        } else if scalingValue == NSImageScaling.scaleNone.rawValue {
            let gridScale = info.screenSize.width > 0 ? size.width / info.screenSize.width : 1.0
            // Use the original wallpaper pixel size when available (thumbnail proxy case)
            let imagePixelSize = info.originalImageSize ?? nsImage.size
            let displaySize = CGSize(
                width: imagePixelSize.width / info.screenScale * gridScale,
                height: imagePixelSize.height / info.screenScale * gridScale
            )
            ZStack {
                bg.frame(width: size.width, height: size.height)
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: displaySize.width, height: displaySize.height)
            }
            .frame(width: size.width, height: size.height)

        // scaleProportionallyUpOrDown (= 3): fill (clipping=true) or fit (clipping=false)
        } else if allowClipping {
            // Fill: scale to cover the grid with no gaps, regardless of image orientation.
            // Pick the axis that requires the larger scale factor so the image fully covers.
            let fillSize = fillFrameSize(image: nsImage.size, grid: size)
            let _ = MainWindowView.tileyLog("FILL path: nsImage.size=\(nsImage.size) fillSize=\(fillSize) gridSize=\(size)")
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: fillSize.width, height: fillSize.height)
                .frame(width: size.width, height: size.height, alignment: .center)
                .clipped()
        } else {
            // Fit: scale to fit entirely within the grid, letterboxing as needed.
            let imageSize = info.originalImageSize ?? nsImage.size
            let imageAspect = imageSize.width / max(1, imageSize.height)
            let gridAspect = size.width / max(1, size.height)
            if imageAspect >= gridAspect {
                let fitHeight = size.width / imageAspect
                ZStack {
                    bg.frame(width: size.width, height: size.height)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: size.width, height: fitHeight)
                }
            } else {
                let fitWidth = size.height * imageAspect
                ZStack {
                    bg.frame(width: size.width, height: size.height)
                    Image(nsImage: nsImage)
                        .resizable()
                        .frame(width: fitWidth, height: size.height)
                }
            }
        }
    }
}
