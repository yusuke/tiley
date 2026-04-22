import AppKit
import ApplicationServices

/// Represents a touching edge between two windows.
/// `edgeOfA` indicates which side of `windowA` is in contact with `windowB`.
/// The opposite edge is uniquely determined, so it is not stored
/// (if `edgeOfA == .right`, then `edgeOfB == .left`).
struct WindowAdjacency: Hashable {
    enum Edge: String {
        case left, right, top, bottom

        /// The opposite edge.
        var opposite: Edge {
            switch self {
            case .left: return .right
            case .right: return .left
            case .top: return .bottom
            case .bottom: return .top
            }
        }

        /// Whether the edge is horizontal (left/right) or vertical (top/bottom).
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
    /// The touching interval in AppKit coordinates (contains the midpoint of the overlap).
    /// For horizontal contact (edgeOfA is left/right) this is a y interval;
    /// for vertical contact this is an x interval.
    let overlapStart: CGFloat
    let overlapEnd: CGFloat

    /// The midpoint of the touching edge (AppKit coordinates). Used for badge placement.
    var midpoint: CGPoint {
        let mid = (overlapStart + overlapEnd) / 2
        switch edgeOfA {
        case .left, .right:
            // Horizontal contact: the shared x is not derivable from edgeOfA,
            // so it is stored separately.
            return CGPoint(x: contactCoordinate, y: mid)
        case .top, .bottom:
            return CGPoint(x: mid, y: contactCoordinate)
        }
    }

    /// Coordinate of the touching edge (shared x for horizontal contact, shared y for vertical).
    let contactCoordinate: CGFloat

    /// Key that identifies a pair regardless of ordering.
    var unorderedKey: AdjacencyKey {
        AdjacencyKey(windowA: min(windowA, windowB), windowB: max(windowA, windowB))
    }
}

/// Key that uniquely identifies a `WindowAdjacency` per pair.
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
    /// Used for displacement detection. Must be updated after every linkage operation.
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

/// Pure helpers that detect touching edges across multiple window frames.
enum WindowAdjacencyDetector {
    /// Default tolerance in points. Differences within this range are considered a match.
    /// When the user configures a gap, callers should pass roughly `gap + 2` to
    /// `detect(frames:edgeEpsilon:)` to widen the allowance.
    static let defaultEdgeEpsilon: CGFloat = 2.0
    /// Minimum overlap length. Contacts shorter than this are ignored because
    /// a badge cannot be drawn cleanly over them.
    static let minOverlap: CGFloat = 16.0

    /// From the given window frames (AppKit coordinates, bottom-left origin),
    /// enumerate all pairs whose edges touch (or line up within the given epsilon).
    /// Each pair is returned only once as a `WindowAdjacency` (no duplicate A→B / B→A).
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

    /// Check whether two windows touch; if so, return the corresponding `WindowAdjacency`.
    static func adjacency(a: CGWindowID, frameA: CGRect, b: CGWindowID, frameB: CGRect, edgeEpsilon: CGFloat = defaultEdgeEpsilon) -> WindowAdjacency? {
        // Horizontal contact: right edge of A meets left edge of B
        // (the symmetric case — A's left vs B's right — is handled below).
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
        // Vertical contact: top edge of A meets bottom edge of B.
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
