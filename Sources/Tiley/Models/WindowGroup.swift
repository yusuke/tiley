import AppKit
import ApplicationServices

/// 2つのウインドウが隣接する辺を表現する。
/// `edgeOfA` は `windowA` のどの辺が `windowB` と接しているかを示す。
/// 反対辺は一意に決まるので保持しない（`edgeOfA == .right` なら `edgeOfB == .left`）。
struct WindowAdjacency: Hashable {
    enum Edge: String {
        case left, right, top, bottom

        /// 反対辺。
        var opposite: Edge {
            switch self {
            case .left: return .right
            case .right: return .left
            case .top: return .bottom
            case .bottom: return .top
            }
        }

        /// 水平方向（left/right）か垂直方向（top/bottom）か。
        var isHorizontal: Bool {
            switch self {
            case .left, .right: return true
            case .top, .bottom: return false
            }
        }
    }

    let windowA: CGWindowID
    let windowB: CGWindowID
    let edgeOfA: Edge
    /// 接している区間の AppKit 座標（overlap の中点を含む）。
    /// 水平接触 (edgeOfA が left/right) の場合は y 区間、垂直接触の場合は x 区間。
    let overlapStart: CGFloat
    let overlapEnd: CGFloat

    /// 接する辺の中央点（AppKit 座標）。バッジ位置計算に使用。
    var midpoint: CGPoint {
        let mid = (overlapStart + overlapEnd) / 2
        switch edgeOfA {
        case .left, .right:
            // 水平接触：接する x は edgeOfA から取れないので別途保持
            return CGPoint(x: contactCoordinate, y: mid)
        case .top, .bottom:
            return CGPoint(x: mid, y: contactCoordinate)
        }
    }

    /// 接する辺の座標（水平接触なら共通 x、垂直接触なら共通 y）。
    let contactCoordinate: CGFloat

    /// ペアを順序無依存にハッシュ化するためのキー。
    var unorderedKey: AdjacencyKey {
        AdjacencyKey(windowA: min(windowA, windowB), windowB: max(windowA, windowB))
    }
}

/// `WindowAdjacency` をペア単位で一意に識別するキー。
struct AdjacencyKey: Hashable {
    let windowA: CGWindowID
    let windowB: CGWindowID
}

struct WindowGroupMember: Hashable {
    let cgWindowID: CGWindowID
    let processIdentifier: pid_t
}

struct WindowGroup: Identifiable {
    let id: UUID
    var members: Set<CGWindowID>
    var adjacencies: [WindowAdjacency]
    var memberMeta: [CGWindowID: WindowGroupMember]
    /// 変位検出用。連動処理後に必ず更新する。
    var lastKnownFrames: [CGWindowID: CGRect]

    init(
        id: UUID = UUID(),
        members: Set<CGWindowID>,
        adjacencies: [WindowAdjacency],
        memberMeta: [CGWindowID: WindowGroupMember],
        lastKnownFrames: [CGWindowID: CGRect]
    ) {
        self.id = id
        self.members = members
        self.adjacencies = adjacencies
        self.memberMeta = memberMeta
        self.lastKnownFrames = lastKnownFrames
    }
}

/// 複数ウインドウのフレームから接する辺のペアを検出する純粋関数群。
enum WindowAdjacencyDetector {
    /// デフォルトの許容誤差（ポイント単位）。これ以内の差は「一致」とみなす。
    /// ユーザーが gap を設定している場合は `detect(frames:edgeEpsilon:)` に
    /// `gap + 2` 程度を渡して許容幅を広げる。
    static let defaultEdgeEpsilon: CGFloat = 2.0
    /// 重なり区間の最小長。これ未満の接触はバッジ描画が困難なので無視。
    static let minOverlap: CGFloat = 16.0

    /// 指定された複数ウインドウのフレーム（AppKit 座標、bottom-left 原点）から、
    /// 辺が接する（もしくは指定した epsilon 以内に並ぶ）ペアを列挙する。
    /// 各ペアは `WindowAdjacency` としてただ1つ返る（A→B と B→A の重複は返さない）。
    static func detect(frames: [CGWindowID: CGRect], edgeEpsilon: CGFloat = defaultEdgeEpsilon) -> [WindowAdjacency] {
        let ids = frames.keys.sorted()
        var result: [WindowAdjacency] = []

        for i in 0..<ids.count {
            for j in (i + 1)..<ids.count {
                let a = ids[i]
                let b = ids[j]
                guard let frameA = frames[a], let frameB = frames[b] else { continue }
                if let adj = adjacency(a: a, frameA: frameA, b: b, frameB: frameB, edgeEpsilon: edgeEpsilon) {
                    result.append(adj)
                }
            }
        }
        return result
    }

    /// 2つのウインドウが接しているかを判定し、接していれば `WindowAdjacency` を返す。
    static func adjacency(a: CGWindowID, frameA: CGRect, b: CGWindowID, frameB: CGRect, edgeEpsilon: CGFloat = defaultEdgeEpsilon) -> WindowAdjacency? {
        // 水平接触：A の右辺 = B の左辺（A の left edge = B の right edge は対称）
        if abs(frameA.maxX - frameB.minX) <= edgeEpsilon {
            let overlapStart = max(frameA.minY, frameB.minY)
            let overlapEnd = min(frameA.maxY, frameB.maxY)
            if overlapEnd - overlapStart >= minOverlap {
                return WindowAdjacency(
                    windowA: a, windowB: b, edgeOfA: .right,
                    overlapStart: overlapStart, overlapEnd: overlapEnd,
                    contactCoordinate: (frameA.maxX + frameB.minX) / 2
                )
            }
        }
        if abs(frameB.maxX - frameA.minX) <= edgeEpsilon {
            let overlapStart = max(frameA.minY, frameB.minY)
            let overlapEnd = min(frameA.maxY, frameB.maxY)
            if overlapEnd - overlapStart >= minOverlap {
                return WindowAdjacency(
                    windowA: a, windowB: b, edgeOfA: .left,
                    overlapStart: overlapStart, overlapEnd: overlapEnd,
                    contactCoordinate: (frameB.maxX + frameA.minX) / 2
                )
            }
        }
        // 垂直接触：A の上辺 = B の下辺
        if abs(frameA.maxY - frameB.minY) <= edgeEpsilon {
            let overlapStart = max(frameA.minX, frameB.minX)
            let overlapEnd = min(frameA.maxX, frameB.maxX)
            if overlapEnd - overlapStart >= minOverlap {
                return WindowAdjacency(
                    windowA: a, windowB: b, edgeOfA: .top,
                    overlapStart: overlapStart, overlapEnd: overlapEnd,
                    contactCoordinate: (frameA.maxY + frameB.minY) / 2
                )
            }
        }
        if abs(frameB.maxY - frameA.minY) <= edgeEpsilon {
            let overlapStart = max(frameA.minX, frameB.minX)
            let overlapEnd = min(frameA.maxX, frameB.maxX)
            if overlapEnd - overlapStart >= minOverlap {
                return WindowAdjacency(
                    windowA: a, windowB: b, edgeOfA: .bottom,
                    overlapStart: overlapStart, overlapEnd: overlapEnd,
                    contactCoordinate: (frameB.maxY + frameA.minY) / 2
                )
            }
        }
        return nil
    }
}
