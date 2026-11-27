import Foundation

public enum SnapKind: String, Sendable, Equatable {
    case endpoint
    case point
    case intersection

    public var label: String {
        switch self {
        case .endpoint: return "端点"
        case .point: return "点"
        case .intersection: return "交点"
        }
    }
}

public struct DrawingSnapHit: Sendable, Equatable {
    public var kind: SnapKind
    public var point: PlanarPoint
    public var distance: Double

    public init(kind: SnapKind, point: PlanarPoint, distance: Double) {
        self.kind = kind
        self.point = point
        self.distance = distance
    }
}

public enum DrawingSnap {
    /// タップ位置から、見えている図形の端点・点・交点のいちばん近いもの。交点と端点が重なるときは端点。
    public static func nearest(in document: DrawingDocument, to point: PlanarPoint, tolerance: Double) -> DrawingSnapHit? {
        guard tolerance > 0 else { return nil }
        let visible = Set(document.layers.filter(\.isVisible).map(\.name))
        let query = DrawingBounds(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y).padded(tolerance)
        let ids = document.index.entityIDs(in: query)
        var candidates: [DrawingSnapHit] = []
        var segments: [(entity: Int, segment: Segment2D)] = []
        for id in ids {
            guard document.entities.indices.contains(id), visible.contains(document.entities[id].layer) else { continue }
            let entity = document.entities[id]
            switch entity.primitive {
            case let .point(vertex):
                let distance = vertex.distance(to: point)
                if distance <= tolerance {
                    candidates.append(DrawingSnapHit(kind: .point, point: vertex, distance: distance))
                }
            case let .line(start, end):
                consider(start, as: .endpoint, near: point, tolerance: tolerance, into: &candidates)
                consider(end, as: .endpoint, near: point, tolerance: tolerance, into: &candidates)
                segments.append((id, Segment2D(start: start, end: end)))
            case let .polyline(vertices, _, _):
                for vertex in vertices {
                    consider(vertex, as: .endpoint, near: point, tolerance: tolerance, into: &candidates)
                }
                appendSegments(vertices, entity: id, into: &segments)
            case let .arc(_, _, _, _, display):
                if let first = display.first {
                    consider(first, as: .endpoint, near: point, tolerance: tolerance, into: &candidates)
                }
                if let last = display.last {
                    consider(last, as: .endpoint, near: point, tolerance: tolerance, into: &candidates)
                }
                appendSegments(display, entity: id, into: &segments)
            case let .circle(center, radius):
                let display = DrawingCurve.circle(center: center, radius: radius)
                appendSegments(display, entity: id, into: &segments)
            case .text:
                break
            }
        }
        let ranked = segments.sorted { lhs, rhs in
            midpoint(lhs.segment).distance(to: point) < midpoint(rhs.segment).distance(to: point)
        }
        let limited = Array(ranked.prefix(48))
        let limit = limited.count
        if limit > 1 {
            for left in 0..<limit {
                for right in (left + 1)..<limit where limited[left].entity != limited[right].entity {
                    guard let hit = intersection(limited[left].segment, limited[right].segment) else { continue }
                    if sharesEnd(limited[left].segment, limited[right].segment) { continue }
                    let distance = hit.distance(to: point)
                    if distance <= tolerance {
                        candidates.append(DrawingSnapHit(kind: .intersection, point: hit, distance: distance))
                    }
                }
            }
        }
        return candidates.min { lhs, rhs in
            if abs(lhs.distance - rhs.distance) <= 1e-3 {
                return rank(lhs.kind) < rank(rhs.kind)
            }
            return lhs.distance < rhs.distance
        }
    }

    private static func midpoint(_ segment: Segment2D) -> PlanarPoint {
        PlanarPoint(x: (segment.start.x + segment.end.x) / 2, y: (segment.start.y + segment.end.y) / 2)
    }

    private static func rank(_ kind: SnapKind) -> Int {
        switch kind {
        case .endpoint: return 0
        case .point: return 1
        case .intersection: return 2
        }
    }

    private static func consider(
        _ vertex: PlanarPoint,
        as kind: SnapKind,
        near point: PlanarPoint,
        tolerance: Double,
        into candidates: inout [DrawingSnapHit]
    ) {
        let distance = vertex.distance(to: point)
        if distance <= tolerance {
            candidates.append(DrawingSnapHit(kind: kind, point: vertex, distance: distance))
        }
    }

    private static func appendSegments(_ vertices: [PlanarPoint], entity: Int, into segments: inout [(entity: Int, segment: Segment2D)]) {
        guard vertices.count >= 2 else { return }
        let step = max(1, vertices.count / 24)
        var previous = vertices[0]
        for index in stride(from: step, to: vertices.count, by: step) {
            let point = vertices[index]
            segments.append((entity, Segment2D(start: previous, end: point)))
            previous = point
        }
        if let last = vertices.last, previous.distance(to: last) > 1e-9 {
            segments.append((entity, Segment2D(start: previous, end: last)))
        }
    }

    private static func sharesEnd(_ a: Segment2D, _ b: Segment2D) -> Bool {
        let points = [a.start, a.end]
        return points.contains { point in
            point.distance(to: b.start) < 1e-6 || point.distance(to: b.end) < 1e-6
        }
    }

    private static func intersection(_ a: Segment2D, _ b: Segment2D) -> PlanarPoint? {
        let rx = a.end.x - a.start.x
        let ry = a.end.y - a.start.y
        let sx = b.end.x - b.start.x
        let sy = b.end.y - b.start.y
        let denominator = rx * sy - ry * sx
        if abs(denominator) < 1e-12 { return nil }
        let qpx = b.start.x - a.start.x
        let qpy = b.start.y - a.start.y
        let t = (qpx * sy - qpy * sx) / denominator
        let u = (qpx * ry - qpy * rx) / denominator
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9 else { return nil }
        return PlanarPoint(x: a.start.x + t * rx, y: a.start.y + t * ry)
    }
}

/// 測設の目標にしてよい名前。標高のような数字だけの文字は名前にしない。
public enum StakeTargetNames {
    public static func isName(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let plain = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(plain) == nil
    }
}

public enum StakeoutPrecision: Sendable, Equatable {
    case centimeters
    case meters

    /// cm は、座標簿の点だけで合わせた図面のときだけ。地図並みや、そのまま載せた SFC はメートル。
    public static func decide(_ accuracy: AlignmentAccuracy?) -> StakeoutPrecision {
        accuracy == .coordinateBook ? .centimeters : .meters
    }
}

public enum StakeoutText {
    public static func meters(_ meters: Double, precision: StakeoutPrecision) -> String {
        let magnitude = abs(meters)
        if magnitude >= 1000 {
            switch precision {
            case .centimeters: return String(format: "%.2f km", meters / 1000)
            case .meters: return String(format: "%.1f km", meters / 1000)
            }
        }
        switch precision {
        case .centimeters: return String(format: "%.2f m", meters)
        case .meters: return String(format: "%.0f m", meters)
        }
    }
}
