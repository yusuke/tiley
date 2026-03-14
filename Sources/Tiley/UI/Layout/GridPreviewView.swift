import SwiftUI

struct GridPreviewView: View {
    @Environment(\.colorScheme) private var colorScheme
    let rows: Int
    let columns: Int
    let gap: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let inset: CGFloat = 28
            let canvas = CGRect(x: inset, y: inset, width: max(220, size.width - inset * 2), height: max(220, size.height - inset * 2))
            let visibleFrame = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
            let selection = sampleSelection
            let ghost = GridCalculator.frame(for: selection, in: visibleFrame, rows: rows, columns: columns, gap: gap)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [ThemeColors.previewGradientStart(for: colorScheme), ThemeColors.previewGradientEnd(for: colorScheme)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(ThemeColors.previewBorder(for: colorScheme), lineWidth: 1)
                    )
                    .frame(width: canvas.width, height: canvas.height)
                    .position(x: canvas.midX, y: canvas.midY)

                ForEach(0..<rows, id: \.self) { row in
                    ForEach(0..<columns, id: \.self) { column in
                        let rect = cellRect(row: row, column: column, in: canvas)
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ThemeColors.previewCellFill(for: colorScheme))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(ThemeColors.previewCellBorder(for: colorScheme), lineWidth: 1.5)
                            )
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                    }
                }

                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ThemeColors.previewSelectionFill(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(ThemeColors.previewSelectionBorder(for: colorScheme), lineWidth: 2)
                    )
                    .frame(width: ghost.width, height: ghost.height)
                    .position(x: canvas.minX + ghost.midX, y: canvas.maxY - ghost.midY)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Sample placement")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(selection.description)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(18)
            }
        }
    }

    private var sampleSelection: GridSelection {
        let endColumn = min(columns - 1, max(0, columns / 2))
        let endRow = min(rows - 1, max(0, rows / 2))
        return GridSelection(startColumn: 0, startRow: 0, endColumn: endColumn, endRow: endRow)
    }

    private func cellRect(row: Int, column: Int, in canvas: CGRect) -> CGRect {
        let totalHorizontalGap = gap * CGFloat(max(0, columns - 1))
        let totalVerticalGap = gap * CGFloat(max(0, rows - 1))
        let cellWidth = (canvas.width - totalHorizontalGap) / CGFloat(columns)
        let cellHeight = (canvas.height - totalVerticalGap) / CGFloat(rows)
        return CGRect(
            x: canvas.minX + CGFloat(column) * (cellWidth + gap),
            y: canvas.minY + CGFloat(row) * (cellHeight + gap),
            width: cellWidth,
            height: cellHeight
        )
    }
}
