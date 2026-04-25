import SwiftUI

struct LayoutGridWorkspaceView: View {
    let rows: Int
    let columns: Int
    let gap: CGFloat
    var highlightSelection: GridSelection?
    /// Multiple highlight selections for preset hover/keyboard preview (no index labels, no delete buttons).
    var highlightSelections: [GridSelection] = []
    /// Pairs of highlight-selection indices that are marked as grouped in the
    /// preset currently being hovered/previewed. Rendered as read-only link
    /// badges so the user can see which regions will be grouped on apply.
    var highlightGroupedPairs: Set<PresetGroupPair> = []
    /// Window info to display as title bars on highlight selections during preset hover.
    var highlightWindowInfo: [AppState.PresetHoverWindowInfo] = []
    /// App assignments parallel to `highlightSelections`. Assigned slots show
    /// the bound app's icon/name during hover and have no index label; the
    /// remaining unassigned slots are color-cycled by their display-only
    /// (unassigned-among-unassigned) position.
    var highlightAppAssignments: [String?] = []
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
    /// Pairs of committed-selection indices that are marked as grouped in the
    /// preset being edited. Only used in edit mode.
    var groupedPairs: Set<PresetGroupPair> = []
    /// Called when the user toggles grouping between two committed selections
    /// (by clicking a `link.badge.plus` or `xmark` badge between them).
    var onToggleGrouping: ((Int, Int) -> Void)?
    /// Parallel to `committedSelections`. Each entry is a bound bundle
    /// identifier or `nil` for an unassigned rectangle. Only used in edit mode.
    var committedAppAssignments: [String?] = []
    /// 1-based display number to show inside unassigned rectangles. Parallel
    /// to `committedSelections`. `nil` for assigned rectangles (they show an
    /// app icon instead). When empty the view falls back to `index + 1`.
    var committedDisplayIndices: [Int?] = []
    /// Called when the user clicks the `macwindow.badge.plus` badge. The
    /// receiver is expected to pop up the app-picker `NSMenu` anchored to the
    /// provided view + point (in the view's coordinate space).
    var onRequestAppPicker: ((_ selectionIndex: Int, _ sourceView: NSView, _ atPoint: NSPoint) -> Void)?
    /// Called when the user clicks the unassign "x" that appears over an
    /// assigned slot on hover.
    var onUnassignApp: ((_ selectionIndex: Int) -> Void)?
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
    /// When the user clicks/drags starting on a cell already covered by a
    /// committed selection (in edit mode), we ignore the entire gesture so it
    /// has no visual effect. The X/app-assignment buttons remain interactive
    /// because they consume their own taps above this gesture.
    @State private var isInvalidDrag = false

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
                    let bundleID: String? = index < committedAppAssignments.count
                        ? committedAppAssignments[index]
                        : nil
                    let displayIndex: Int? = {
                        if index < committedDisplayIndices.count {
                            return committedDisplayIndices[index]
                        }
                        return bundleID == nil ? index + 1 : nil
                    }()
                    // Color tracks the displayed number (1-based) so unassigned
                    // slots cycle through blue/green/orange/purple independent
                    // of how many assigned slots sit in the array before them.
                    let colorIndex = (displayIndex ?? (index + 1)) - 1
                    let fill = ThemeColors.indexedSelectionFill(index: colorIndex, for: colorScheme)
                    let border = ThemeColors.indexedSelectionBorder(index: colorIndex, for: colorScheme)
                    if let bundleID {
                        assignedCommittedRectangle(
                            index: index,
                            bundleID: bundleID,
                            sel: norm,
                            selRect: selRect,
                            cornerRadius: cellCornerRadius,
                            totalHeight: geometry.size.height,
                            showDelete: onDeleteSelection != nil
                        )
                    } else {
                        committedSelectionRectangle(
                            index: index,
                            displayIndex: displayIndex,
                            sel: norm, selRect: selRect,
                            cellWidth: cellWidth, cellHeight: cellHeight,
                            cornerRadius: cellCornerRadius,
                            fill: fill, border: border,
                            divider: border.opacity(0.3),
                            showDelete: onDeleteSelection != nil,
                            showAssignBadge: onRequestAppPicker != nil
                        )
                    }
                }

                // Grouping badges at edges shared between committed selections
                // (preset edit mode only, requires ≥2 selections and a toggle handler).
                if onDeleteSelection != nil, onToggleGrouping != nil, committedSelections.count >= 2 {
                    let adjacencies = SelectionAdjacencyDetector.detect(selections: committedSelections)
                    ForEach(adjacencies, id: \.self) { adj in
                        let center = badgeCenter(for: adj, inSelections: committedSelections, cellWidth: cellWidth, cellHeight: cellHeight)
                        let isLinked = groupedPairs.contains(PresetGroupPair(adj.indexA, adj.indexB))
                        PresetGroupingBadgeView(isLinked: isLinked) {
                            onToggleGrouping?(adj.indexA, adj.indexB)
                        }
                        .position(x: center.x, y: center.y)
                    }
                }

                // Multiple highlight selections (preset hover with secondary selections)
                if !highlightSelections.isEmpty, activeSelection == nil, committedSelections.isEmpty {
                    let showHighlightIndex = highlightSelections.count > 1
                    let multiInset: CGFloat = highlightSelections.count > 1 ? 1 : 0

                    // Color index for unassigned slots — 0-based position
                    // among *unassigned* entries only, so the first remaining
                    // slot is blue regardless of how many assigned slots
                    // precede it in the array.
                    let paddedApps: [String?] = {
                        if highlightAppAssignments.count >= highlightSelections.count {
                            return Array(highlightAppAssignments.prefix(highlightSelections.count))
                        }
                        return highlightAppAssignments
                            + Array(repeating: nil, count: highlightSelections.count - highlightAppAssignments.count)
                    }()
                    let unassignedColorIndex: [Int: Int] = {
                        var result: [Int: Int] = [:]
                        var cursor = 0
                        for (idx, app) in paddedApps.enumerated() where app == nil {
                            result[idx] = cursor
                            cursor += 1
                        }
                        return result
                    }()

                    ForEach(Array(highlightSelections.enumerated()), id: \.offset) { index, sel in
                        let norm = sel.normalized
                        let selRect = rectForSelection(norm, cellWidth: cellWidth, cellHeight: cellHeight)
                            .insetBy(dx: multiInset, dy: multiInset)
                        let bundleID = index < paddedApps.count ? paddedApps[index] : nil
                        let colorIndex = unassignedColorIndex[index] ?? index
                        let tint = ThemeColors.indexedSelectionFill(index: colorIndex, for: colorScheme)

                        if let bid = bundleID {
                            let menuBarFraction = windowFrameRelative?.menuBarHeightFraction ?? 0.03
                            let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                            let appIcon = AppIconLookup.icon(forBundleID: bid)
                            let appName = AppIconLookup.localizedName(forBundleID: bid) ?? bid
                            MiniatureWindowView(
                                titleBarHeight: titleBarPx,
                                appIcon: appIcon,
                                appName: appName,
                                windowTitle: nil,
                                cornerRadiusOverride: cellCornerRadius
                            )
                            .frame(width: selRect.width, height: selRect.height)
                            .position(x: selRect.midX, y: selRect.midY)
                            .allowsHitTesting(false)
                        } else if index < highlightWindowInfo.count {
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
                                    Text("\(colorIndex + 1)")
                                        .font(.system(size: min(selRect.width, selRect.height) * 0.35, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                                        .frame(width: selRect.width, height: selRect.height)
                                        .position(x: selRect.midX, y: selRect.midY)
                                }
                            }
                        } else {
                            // Fallback: no window info available, show colored rectangle.
                            let border = ThemeColors.indexedSelectionBorder(index: colorIndex, for: colorScheme)
                            committedSelectionRectangle(
                                index: index,
                                displayIndex: colorIndex + 1,
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

                    // Read-only grouping indicators on preset hover.
                    if !highlightGroupedPairs.isEmpty, highlightSelections.count >= 2 {
                        let adjacencies = SelectionAdjacencyDetector.detect(selections: highlightSelections)
                        ForEach(adjacencies, id: \.self) { adj in
                            let pair = PresetGroupPair(adj.indexA, adj.indexB)
                            if highlightGroupedPairs.contains(pair) {
                                let center = badgeCenter(for: adj, inSelections: highlightSelections, cellWidth: cellWidth, cellHeight: cellHeight)
                                PresetGroupingBadgeView(isLinked: true, isReadOnly: true) {}
                                    .position(x: center.x, y: center.y)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                }

                // Unified highlight (from highlightSelection, single)
                if let hl = highlightSelection?.normalized, activeSelection == nil, committedSelections.isEmpty, highlightSelections.isEmpty {
                    let selRect = rectForSelection(hl, cellWidth: cellWidth, cellHeight: cellHeight)
                        .insetBy(dx: 1, dy: 1)
                    let tint = ThemeColors.gridCellHighlightFill(for: colorScheme)
                    let singleBundleID = highlightAppAssignments.first.flatMap { $0 }

                    if let bid = singleBundleID {
                        let menuBarFraction = windowFrameRelative?.menuBarHeightFraction ?? 0.03
                        let titleBarPx = max(4, menuBarFraction * geometry.size.height * 1.5)
                        let appIcon = AppIconLookup.icon(forBundleID: bid)
                        let appName = AppIconLookup.localizedName(forBundleID: bid) ?? bid
                        MiniatureWindowView(
                            titleBarHeight: titleBarPx,
                            appIcon: appIcon,
                            appName: appName,
                            windowTitle: nil,
                            cornerRadiusOverride: cellCornerRadius
                        )
                        .frame(width: selRect.width, height: selRect.height)
                        .position(x: selRect.midX, y: selRect.midY)
                        .allowsHitTesting(false)
                    } else if let info = highlightWindowInfo.first {
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
                        let hoverSelection: GridSelection
                        if let committed = committedSelectionAt(row: hoveredCell.row, column: hoveredCell.column) {
                            hoverSelection = committed.normalized
                        } else {
                            hoverSelection = GridSelection(
                                startColumn: hoveredCell.column,
                                startRow: hoveredCell.row,
                                endColumn: hoveredCell.column,
                                endRow: hoveredCell.row
                            )
                        }
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
                        if isInvalidDrag { return }
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
                            let isEditMode = onDeleteSelection != nil
                            if isEditMode && cellIsOccupied(row: cell.row, column: cell.column) {
                                isInvalidDrag = true
                                isDragging = false
                                return
                            }
                            dragStart = cell
                        }
                        updateSelection(row: cell.row, column: cell.column)
                    }
                    .onEnded { value in
                        guard !isDragDisabled else { return }
                        if isInvalidDrag {
                            isInvalidDrag = false
                            isDragging = false
                            return
                        }
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

    /// Whether the given cell is covered by any committed selection.
    private func cellIsOccupied(row: Int, column: Int) -> Bool {
        committedSelectionAt(row: row, column: column) != nil
    }

    /// The committed selection covering the given cell, if any.
    private func committedSelectionAt(row: Int, column: Int) -> GridSelection? {
        let point = GridSelection(startColumn: column, startRow: row, endColumn: column, endRow: row)
        return committedSelections.first { point.overlaps($0) }
    }

    /// Draws a committed selection rectangle with index label and optional delete button.
    @ViewBuilder
    private func committedSelectionRectangle(
        index: Int,
        displayIndex: Int? = nil,
        sel: GridSelection,
        selRect: CGRect,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        cornerRadius: CGFloat,
        fill: Color,
        border: Color,
        divider: Color,
        showIndex: Bool = true,
        showDelete: Bool,
        showAssignBadge: Bool = false
    ) -> some View {
        let spanCols = sel.endColumn - sel.startColumn + 1
        let spanRows = sel.endRow - sel.startRow + 1
        let labelNumber = displayIndex ?? (index + 1)

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
                    Text("\(labelNumber)")
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
                    .hoverScale()
                    .padding(4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showAssignBadge {
                    assignAppBadge(selectionIndex: index, diameter: min(22, min(selRect.width, selRect.height) * 0.24))
                        .padding(4)
                }
            }
            .frame(width: selRect.width, height: selRect.height)
            .position(x: selRect.midX, y: selRect.midY)
    }

    /// Draws an assigned committed rectangle — a miniature window with the
    /// app's icon and localized name. Hovering shows an "unassign" overlay.
    @ViewBuilder
    private func assignedCommittedRectangle(
        index: Int,
        bundleID: String,
        sel: GridSelection,
        selRect: CGRect,
        cornerRadius: CGFloat,
        totalHeight: CGFloat,
        showDelete: Bool
    ) -> some View {
        let menuBarFraction = windowFrameRelative?.menuBarHeightFraction ?? 0.03
        let titleBarPx = max(4, menuBarFraction * totalHeight * 1.5)
        let appIcon = AppIconLookup.icon(forBundleID: bundleID)
        let appName = AppIconLookup.localizedName(forBundleID: bundleID) ?? bundleID

        AssignedRectangleView(
            selectionIndex: index,
            appIcon: appIcon,
            appName: appName,
            titleBarHeight: titleBarPx,
            cornerRadiusOverride: cornerRadius,
            showDelete: showDelete,
            selRect: selRect,
            onDelete: { onDeleteSelection?(index) },
            onUnassign: { onUnassignApp?(index) }
        )
        .frame(width: selRect.width, height: selRect.height)
        .position(x: selRect.midX, y: selRect.midY)
    }

    /// Clickable `macwindow.badge.plus` badge that requests the app-picker
    /// `NSMenu` for the given committed-selection index. The badge is an
    /// NSViewRepresentable-backed `NSButton` so the menu can pop up anchored
    /// to the real view.
    @ViewBuilder
    private func assignAppBadge(selectionIndex: Int, diameter: CGFloat) -> some View {
        AssignAppBadgeButton(diameter: diameter) { sourceView, point in
            onRequestAppPicker?(selectionIndex, sourceView, point)
        }
        .frame(width: diameter, height: diameter)
        .hoverScale()
        .instantTooltip(NSLocalizedString("Assign Application to Region", comment: "Tooltip for the macwindow.badge.plus button inside a preset rectangle"))
    }

    /// Pixel center of the shared edge between two committed selections.
    /// Returned in the grid view's local coordinate space.
    private func badgeCenter(for adj: SelectionAdjacency, inSelections selections: [GridSelection], cellWidth: CGFloat, cellHeight: CGFloat) -> CGPoint {
        let a = selections[adj.indexA].normalized
        switch adj.edgeOfA {
        case .right:
            let x = CGFloat(a.endColumn + 1) * (cellWidth + gap) - gap / 2
            let overlapMid = (CGFloat(adj.overlapStart) + CGFloat(adj.overlapEnd + 1)) / 2
            let y = overlapMid * (cellHeight + gap) - gap / 2
            return CGPoint(x: x, y: y)
        case .left:
            let x = CGFloat(a.startColumn) * (cellWidth + gap) - gap / 2
            let overlapMid = (CGFloat(adj.overlapStart) + CGFloat(adj.overlapEnd + 1)) / 2
            let y = overlapMid * (cellHeight + gap) - gap / 2
            return CGPoint(x: x, y: y)
        case .bottom:
            let y = CGFloat(a.endRow + 1) * (cellHeight + gap) - gap / 2
            let overlapMid = (CGFloat(adj.overlapStart) + CGFloat(adj.overlapEnd + 1)) / 2
            let x = overlapMid * (cellWidth + gap) - gap / 2
            return CGPoint(x: x, y: y)
        case .top:
            let y = CGFloat(a.startRow) * (cellHeight + gap) - gap / 2
            let overlapMid = (CGFloat(adj.overlapStart) + CGFloat(adj.overlapEnd + 1)) / 2
            let x = overlapMid * (cellWidth + gap) - gap / 2
            return CGPoint(x: x, y: y)
        }
    }
}

/// Small circular badge rendered at the shared edge between two preset
/// regions. Unlinked: `link.badge.plus` (accent colour). Linked: subdued
/// `link` glyph that flips to `xmark` on hover (red) to preview unlinking.
private struct PresetGroupingBadgeView: View {
    let isLinked: Bool
    /// When true, the badge is a static indicator (no hover → `xmark`, no tap,
    /// no tooltip). Used on preset hover/preview to show which regions will be
    /// grouped on apply without offering a toggle.
    var isReadOnly: Bool = false
    let onTap: () -> Void

    @State private var isHovering = false

    private var showHoverAffordance: Bool {
        isHovering && !isReadOnly
    }

    private var symbolName: String {
        if isLinked {
            return showHoverAffordance ? "xmark" : "link"
        }
        return "link.badge.plus"
    }

    private var backgroundColor: Color {
        if isLinked {
            if showHoverAffordance {
                return Color.red.opacity(0.9)
            }
            return Color.black.opacity(0.65)
        }
        return isHovering ? Color.accentColor.opacity(0.98) : Color.accentColor.opacity(0.92)
    }

    private var foregroundColor: Color {
        if isLinked && !showHoverAffordance {
            return Color.white.opacity(0.95)
        }
        return .white
    }

    private var strokeColor: Color {
        if isLinked && !showHoverAffordance {
            return Color.white.opacity(0.7)
        }
        return Color.white.opacity(0.9)
    }

    private var tooltip: String {
        if isLinked {
            return NSLocalizedString("Remove grouping", comment: "Tooltip for removing grouping between two preset regions")
        }
        return NSLocalizedString("Group these regions", comment: "Tooltip for grouping two preset regions")
    }

    var body: some View {
        Group {
            if isReadOnly {
                badgeContent
            } else {
                Button(action: onTap) {
                    badgeContent
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovering = hovering
                }
                .instantTooltip(tooltip)
            }
        }
    }

    private var badgeContent: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .overlay(Circle().stroke(strokeColor, lineWidth: 1))
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            Image(systemName: symbolName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(foregroundColor)
        }
        .frame(width: 28, height: 28)
        .contentShape(Circle())
        .scaleEffect(showHoverAffordance ? 1.12 : 1.0)
        .animation(.easeOut(duration: 0.12), value: showHoverAffordance)
        .opacity(showHoverAffordance ? 1.0 : 0.95)
    }
}

/// `NSButton`-backed `macwindow.badge.plus` badge. Calls `onClick` with the
/// underlying `NSView` and a point centered on its bounds so the caller can
/// pop up an `NSMenu` anchored to the real AppKit view.
private struct AssignAppBadgeButton: NSViewRepresentable {
    let diameter: CGFloat
    let onClick: (_ sourceView: NSView, _ atPoint: NSPoint) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.wantsLayer = true
        button.layer?.cornerRadius = diameter / 2
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        button.target = context.coordinator
        button.action = #selector(Coordinator.pressed(_:))
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyUpOrDown

        let config = NSImage.SymbolConfiguration(pointSize: diameter * 0.58, weight: .semibold)
        if let image = NSImage(systemSymbolName: "macwindow.badge.plus",
                               accessibilityDescription: "Assign Application")?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.contentTintColor = NSColor.white.withAlphaComponent(0.95)
        }

        context.coordinator.onClick = onClick
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        nsView.layer?.cornerRadius = diameter / 2
        let config = NSImage.SymbolConfiguration(pointSize: diameter * 0.58, weight: .semibold)
        nsView.image = nsView.image?.withSymbolConfiguration(config)
        context.coordinator.onClick = onClick
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        var onClick: ((NSView, NSPoint) -> Void)?

        @objc func pressed(_ sender: NSButton) {
            let center = NSPoint(x: sender.bounds.midX, y: sender.bounds.maxY)
            onClick?(sender, center)
        }
    }
}

/// Adds a subtle scale-up animation when the pointer hovers the view.
/// Used on small action buttons (delete x, unassign x, assign app badge)
/// inside preset rectangles to give visual feedback on hover.
private struct HoverScaleModifier: ViewModifier {
    var scale: CGFloat = 1.2
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovered = hovering
                }
            }
    }
}

private extension View {
    func hoverScale(_ scale: CGFloat = 1.2) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
}

/// Renders an assigned committed rectangle: a regular miniature window with
/// the app's icon and localized name. Hovering the rectangle reveals an
/// "unassign" button centered over the content.
private struct AssignedRectangleView: View {
    let selectionIndex: Int
    let appIcon: NSImage?
    let appName: String
    let titleBarHeight: CGFloat
    let cornerRadiusOverride: CGFloat
    let showDelete: Bool
    let selRect: CGRect
    let onDelete: () -> Void
    let onUnassign: () -> Void

    @State private var isIconHovered = false
    @State private var isUnassignHovered = false

    private var showUnassign: Bool { isIconHovered || isUnassignHovered }

    var body: some View {
        ZStack {
            MiniatureWindowView(
                titleBarHeight: titleBarHeight,
                appIcon: appIcon,
                appName: appName,
                windowTitle: nil,
                cornerRadiusOverride: cornerRadiusOverride
            )

            if let icon = appIcon {
                let iconSide = max(16, min(selRect.width, selRect.height) * 0.45)
                let xSize = min(14, min(selRect.width, selRect.height) * 0.22)
                ZStack(alignment: .topLeading) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSide, height: iconSide)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.12)) {
                                isIconHovered = hovering
                            }
                        }

                    if showUnassign {
                        Button(action: onUnassign) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: xSize))
                                .foregroundStyle(.white.opacity(0.85))
                                .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                        }
                        .buttonStyle(.plain)
                        .scaleEffect(isUnassignHovered ? 1.2 : 1.0)
                        .instantTooltip(NSLocalizedString("Unassign Application", comment: "Tooltip shown when hovering the unassign button on an assigned preset rectangle"))
                        .padding(max(2, xSize * 0.8))
                        .onHover { hovering in
                            withAnimation(.easeOut(duration: 0.12)) {
                                isUnassignHovered = hovering
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: iconSide, height: iconSide)
            }
        }
        .overlay(alignment: .topLeading) {
            if showDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: min(14, min(selRect.width, selRect.height) * 0.22)))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 0.5)
                }
                .buttonStyle(.plain)
                .hoverScale()
                .padding(4)
            }
        }
    }
}
