import Testing
import CoreGraphics
@testable import Tiley

@Suite("GridSelection")
struct GridSelectionTests {

    // MARK: - normalized

    @Test("reversed start/end are swapped")
    func normalizedSwapsReversed() {
        let selection = GridSelection(startColumn: 3, startRow: 4, endColumn: 1, endRow: 2)
        let n = selection.normalized
        #expect(n.startColumn == 1)
        #expect(n.startRow == 2)
        #expect(n.endColumn == 3)
        #expect(n.endRow == 4)
    }

    @Test("already-normal selection is unchanged")
    func normalizedPreservesNormal() {
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 3, endRow: 3)
        #expect(selection == selection.normalized)
    }

    // MARK: - description

    @Test("description uses 1-based indices")
    func descriptionFormat() {
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 5, endRow: 5)
        #expect(selection.description == "c1-6, r1-6")
    }

    @Test("description normalizes before formatting")
    func descriptionNormalizes() {
        let reversed = GridSelection(startColumn: 3, startRow: 2, endColumn: 1, endRow: 0)
        #expect(reversed.description == "c2-4, r1-3")
    }

    // MARK: - scaled

    @Test("full span is preserved when scaling down")
    func scalingPreservesFullSpan() {
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 5, endRow: 5)
        let scaled = selection.scaled(fromRows: 6, columns: 6, toRows: 4, columns: 4)
        #expect(scaled == GridSelection(startColumn: 0, startRow: 0, endColumn: 3, endRow: 3))
    }

    @Test("scaling to same dimensions is identity")
    func scalingIdentity() {
        let selection = GridSelection(startColumn: 1, startRow: 2, endColumn: 3, endRow: 4)
        let scaled = selection.scaled(fromRows: 6, columns: 6, toRows: 6, columns: 6)
        #expect(scaled == selection.normalized)
    }

    @Test("scaling up preserves proportions")
    func scalingUpPreservesProportions() {
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 1, endRow: 3)
        let scaled = selection.scaled(fromRows: 4, columns: 4, toRows: 8, columns: 8)
        #expect(scaled.startColumn == 0)
        #expect(scaled.endColumn == 3)
        #expect(scaled.startRow == 0)
        #expect(scaled.endRow == 7)
    }

    @Test("down then up round-trip preserves full-span selection")
    func scalingDownThenUpRoundTrip() {
        let original = GridSelection(startColumn: 0, startRow: 0, endColumn: 2, endRow: 5)
        let down = original.scaled(fromRows: 6, columns: 6, toRows: 4, columns: 4)
        let back = down.scaled(fromRows: 4, columns: 4, toRows: 6, columns: 6)
        #expect(back == original.normalized)
    }

    @Test("zero source dimensions produce zero result")
    func scalingWithZeroSource() {
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 2, endRow: 2)
        let scaled = selection.scaled(fromRows: 0, columns: 0, toRows: 6, columns: 6)
        #expect(scaled.startColumn == 0)
        #expect(scaled.startRow == 0)
        #expect(scaled.endColumn == 0)
        #expect(scaled.endRow == 0)
    }
}

@Suite("GridCalculator")
struct GridCalculatorTests {

    @Test("full selection covers entire visible frame")
    func fullSelectionCoversVisibleFrame() {
        let visibleFrame = CGRect(x: 100, y: 50, width: 1200, height: 700)
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 5, endRow: 5)
        let frame = GridCalculator.frame(for: selection, in: visibleFrame, rows: 6, columns: 6, gap: 0)
        #expect(frame == visibleFrame)
    }

    @Test("single cell produces correct size")
    func singleCell() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 600, height: 600)
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 0, endRow: 0)
        let frame = GridCalculator.frame(for: selection, in: visibleFrame, rows: 6, columns: 6, gap: 0)
        #expect(frame.width == 100)
        #expect(frame.height == 100)
    }

    @Test("gap reduces individual cell size")
    func gapReducesCellSize() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 610, height: 610)
        let selection = GridSelection(startColumn: 0, startRow: 0, endColumn: 0, endRow: 0)

        let frameNoGap = GridCalculator.frame(for: selection, in: visibleFrame, rows: 6, columns: 6, gap: 0)
        let frameWithGap = GridCalculator.frame(for: selection, in: visibleFrame, rows: 6, columns: 6, gap: 2)

        #expect(frameNoGap.width > frameWithGap.width)
        #expect(frameNoGap.height > frameWithGap.height)
    }

    @Test("gap creates space between adjacent cells")
    func gapBetweenAdjacentCells() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 620, height: 620)
        let gap: CGFloat = 10

        let cell0 = GridCalculator.frame(
            for: GridSelection(startColumn: 0, startRow: 0, endColumn: 0, endRow: 0),
            in: visibleFrame, rows: 6, columns: 6, gap: gap
        )
        let cell1 = GridCalculator.frame(
            for: GridSelection(startColumn: 1, startRow: 0, endColumn: 1, endRow: 0),
            in: visibleFrame, rows: 6, columns: 6, gap: gap
        )

        let actualGap = cell1.minX - cell0.maxX
        #expect(abs(actualGap - gap) <= 1.0)
    }

    @Test("reversed selection produces same frame as normalized")
    func reversedSelectionNormalizes() {
        let visibleFrame = CGRect(x: 0, y: 0, width: 600, height: 600)
        let reversed = GridSelection(startColumn: 2, startRow: 2, endColumn: 0, endRow: 0)
        let normal = reversed.normalized
        let frameReversed = GridCalculator.frame(for: reversed, in: visibleFrame, rows: 6, columns: 6, gap: 0)
        let frameNormal = GridCalculator.frame(for: normal, in: visibleFrame, rows: 6, columns: 6, gap: 0)
        #expect(frameReversed == frameNormal)
    }
}
