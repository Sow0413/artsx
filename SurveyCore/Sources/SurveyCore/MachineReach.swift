import Foundation

/// 重機の作業半径。腕の長さで目測するための目安で、マシンガイダンスではない。
public struct MachinePreset: Sendable, Equatable, Identifiable {
    public var id: String
    public var label: String
    /// 最大作業半径の目安。メートル。
    public var radiusMeters: Double

    public init(id: String, label: String, radiusMeters: Double) {
        self.id = id
        self.label = label
        self.radiusMeters = radiusMeters
    }
}

public enum MachineCatalog {
    /// 20t 級の目安。captain の「20t≒9m」。
    public static let twentyTon = MachinePreset(id: "20t", label: "20t", radiusMeters: 9)

    /// 機種の目安。カタログ値ではなく、腕の長さで見るための丸めた半径。
    public static let presets: [MachinePreset] = [
        MachinePreset(id: "3t", label: "3t", radiusMeters: 5),
        MachinePreset(id: "5t", label: "5t", radiusMeters: 6),
        MachinePreset(id: "8t", label: "8t", radiusMeters: 7),
        MachinePreset(id: "13t", label: "13t", radiusMeters: 8),
        twentyTon,
        MachinePreset(id: "30t", label: "30t", radiusMeters: 10),
        MachinePreset(id: "40t", label: "40t", radiusMeters: 11)
    ]

    public static func named(_ id: String) -> MachinePreset? {
        presets.first { $0.id == id }
    }
}

/// 作業半径に対する内外。半径上は届くものとして内側に寄せる。
public enum ReachCoverage: String, Sendable, Equatable {
    case inside
    case onRadius
    case outside
    case partial
}

public struct ReachCall: Sendable, Equatable {
    /// 表示に使った距離。0.1m 単位。
    public var distanceMeters: Double
    /// 半径との差。外が正、内が負。0.1m 単位。
    public var gapMeters: Double
    public var coverage: ReachCoverage
    public var text: String

    public init(distanceMeters: Double, gapMeters: Double, coverage: ReachCoverage, text: String) {
        self.distanceMeters = distanceMeters
        self.gapMeters = gapMeters
        self.coverage = coverage
        self.text = text
    }
}

public struct ReachRange: Sendable, Equatable {
    public var points: [PlanarPoint]
    public var coverage: ReachCoverage

    public init(points: [PlanarPoint], coverage: ReachCoverage) {
        self.points = points
        self.coverage = coverage
    }
}

public struct ReachRing: Sendable, Equatable {
    public var coordinates: [GeoCoord]
    public var coverage: ReachCoverage
    public var closed: Bool

    public init(coordinates: [GeoCoord], coverage: ReachCoverage, closed: Bool) {
        self.coordinates = coordinates
        self.coverage = coverage
        self.closed = closed
    }
}

/// 現在地を中心にした作業半径。距離は 0.1m 単位。
public enum MachineReach {
    public static func roundTenths(_ meters: Double) -> Double {
        (meters * 10).rounded() / 10
    }

    /// `目標まで 12.3m（半径外 3.3m）`。半径内は残りの届く長さ。
    public static func call(distanceMeters: Double, radiusMeters: Double) -> ReachCall? {
        guard distanceMeters.isFinite, distanceMeters >= 0, radiusMeters.isFinite, radiusMeters > 0 else { return nil }
        let distance = roundTenths(distanceMeters)
        let gap = roundTenths(distance - radiusMeters)
        let coverage: ReachCoverage
        let text: String
        if gap > 0 {
            coverage = .outside
            text = "目標まで \(format(distance))（半径外 \(format(gap))）"
        } else if gap < 0 {
            coverage = .inside
            text = "目標まで \(format(distance))（半径内 \(format(-gap))）"
        } else {
            coverage = .onRadius
            text = "目標まで \(format(distance))（半径上）"
        }
        return ReachCall(distanceMeters: distance, gapMeters: gap, coverage: coverage, text: text)
    }

    public static func geodesic(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double,
        radiusMeters: Double
    ) -> ReachCall? {
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: fromLatitude,
            longitude1: fromLongitude,
            latitude2: toLatitude,
            longitude2: toLongitude
        ) else { return nil }
        return call(distanceMeters: inverse.distanceMeters, radiusMeters: radiusMeters)
    }

    /// 円は凸なので、線分が半径に掛かるかは端と、中心から線分への距離で足りる。
    public static func coverage(of points: [PlanarPoint], closed: Bool, center: PlanarPoint, radius: Double) -> ReachCoverage {
        guard radius > 0, radius.isFinite, points.count >= 2 else { return .outside }
        let segmentCount = closed ? points.count : points.count - 1
        guard segmentCount >= 1 else { return .outside }
        var sawInside = false
        var sawOutside = false
        for index in 0..<segmentCount {
            let start = points[index]
            let end = points[(index + 1) % points.count]
            switch segmentCoverage(start, end, center: center, radius: radius) {
            case .inside, .onRadius:
                sawInside = true
            case .outside:
                sawOutside = true
            case .partial:
                sawInside = true
                sawOutside = true
            }
        }
        if sawInside && sawOutside { return .partial }
        if sawInside { return .inside }
        return .outside
    }

    public static func worst(_ coverages: [ReachCoverage]) -> ReachCoverage? {
        if coverages.contains(.outside) { return .outside }
        if coverages.contains(.partial) { return .partial }
        if coverages.contains(.onRadius) { return .onRadius }
        if coverages.contains(.inside) { return .inside }
        return nil
    }

    private static func segmentCoverage(
        _ start: PlanarPoint,
        _ end: PlanarPoint,
        center: PlanarPoint,
        radius: Double
    ) -> ReachCoverage {
        let startInside = start.distance(to: center) <= radius
        let endInside = end.distance(to: center) <= radius
        if startInside && endInside { return .inside }
        if distanceToSegment(center, start, end) <= radius { return .partial }
        return .outside
    }

    private static func distanceToSegment(_ point: PlanarPoint, _ start: PlanarPoint, _ end: PlanarPoint) -> Double {
        let vx = end.x - start.x
        let vy = end.y - start.y
        let lengthSquared = vx * vx + vy * vy
        if lengthSquared < 1e-12 { return point.distance(to: start) }
        var t = ((point.x - start.x) * vx + (point.y - start.y) * vy) / lengthSquared
        if t < 0 { t = 0 }
        if t > 1 { t = 1 }
        return point.distance(to: PlanarPoint(x: start.x + t * vx, y: start.y + t * vy))
    }

    private static func format(_ meters: Double) -> String {
        String(format: "%.1fm", meters)
    }
}
