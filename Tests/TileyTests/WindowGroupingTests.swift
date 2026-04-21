import Testing
import CoreGraphics
@testable import Tiley

@Suite("WindowAdjacencyDetector")
struct WindowAdjacencyDetectorTests {

    // MARK: - Horizontal contact (left/right)

    @Test("left-right split detects horizontal adjacency")
    func horizontalSplitDetected() {
        // A: 左半分, B: 右半分
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 500, y: 0, width: 500, height: 400),
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.count == 1)
        let adj = result[0]
        #expect(adj.edgeOfA == .right)
        #expect(adj.windowA == 1)
        #expect(adj.windowB == 2)
        #expect(adj.contactCoordinate == 500)
        #expect(adj.overlapStart == 0)
        #expect(adj.overlapEnd == 400)
    }

    @Test("gap larger than epsilon rejects adjacency")
    func gapRejectsAdjacency() {
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 510, y: 0, width: 500, height: 400),  // 10pt gap
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.isEmpty)
    }

    @Test("sub-epsilon gap still counts as adjacent")
    func subEpsilonGapAccepted() {
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 501, y: 0, width: 500, height: 400),  // 1pt gap, within epsilon=2
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.count == 1)
    }

    @Test("short vertical overlap rejects adjacency")
    func shortOverlapRejected() {
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 500, y: 390, width: 500, height: 400),  // overlap 10pt < 16pt
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.isEmpty)
    }

    // MARK: - Vertical contact (top/bottom)

    @Test("top-bottom split detects vertical adjacency")
    func verticalSplitDetected() {
        // AppKit 座標系は bottom-left 原点。B (上) の下辺 = A (下) の上辺
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 1000, height: 200),      // 下
            2: CGRect(x: 0, y: 200, width: 1000, height: 200),    // 上
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.count == 1)
        let adj = result[0]
        #expect(adj.edgeOfA == .top)
        #expect(adj.contactCoordinate == 200)
    }

    // MARK: - Three-window layout

    @Test("three-window L-shape detects two adjacencies")
    func threeWindowLayout() {
        // 左 (全高) + 右上 + 右下
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 800),        // 左
            2: CGRect(x: 500, y: 400, width: 500, height: 400),    // 右上
            3: CGRect(x: 500, y: 0, width: 500, height: 400),      // 右下
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        // 期待: 1-2, 1-3, 2-3 の3ペア
        #expect(result.count == 3)
        let pairs = Set(result.map { Set([$0.windowA, $0.windowB]) })
        #expect(pairs.contains(Set([1, 2])))
        #expect(pairs.contains(Set([1, 3])))
        #expect(pairs.contains(Set([2, 3])))
    }

    // MARK: - No contact

    @Test("non-touching windows produce no adjacencies")
    func nonTouchingNoAdjacency() {
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 200, height: 200),
            2: CGRect(x: 500, y: 500, width: 200, height: 200),
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.isEmpty)
    }

    @Test("overlapping windows produce no adjacency (edges don't align)")
    func overlappingNoAdjacency() {
        let frames: [CGWindowID: CGRect] = [
            1: CGRect(x: 0, y: 0, width: 500, height: 400),
            2: CGRect(x: 400, y: 0, width: 500, height: 400),  // 100pt 重なり
        ]
        let result = WindowAdjacencyDetector.detect(frames: frames)
        #expect(result.isEmpty)
    }

    // MARK: - edge.opposite

    @Test("edge.opposite returns the opposing edge")
    func edgeOppositeCorrect() {
        #expect(WindowAdjacency.Edge.left.opposite == .right)
        #expect(WindowAdjacency.Edge.right.opposite == .left)
        #expect(WindowAdjacency.Edge.top.opposite == .bottom)
        #expect(WindowAdjacency.Edge.bottom.opposite == .top)
    }

    @Test("edge.isHorizontal distinguishes axes")
    func edgeAxisCorrect() {
        #expect(WindowAdjacency.Edge.left.isHorizontal)
        #expect(WindowAdjacency.Edge.right.isHorizontal)
        #expect(!WindowAdjacency.Edge.top.isHorizontal)
        #expect(!WindowAdjacency.Edge.bottom.isHorizontal)
    }
}
