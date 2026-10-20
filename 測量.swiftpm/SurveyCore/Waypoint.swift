import Foundation

/// 地点。ジオグラフィカのウェイポイントに当たる。記録の画面は次のスライス。
/// 段階0の地点は下見であり、測設の基準にはしない。
public struct Waypoint: Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var position: GeodeticPosition
    public var note: String

    public init(id: UUID = UUID(), name: String, position: GeodeticPosition, note: String = "") {
        self.id = id
        self.name = name
        self.position = position
        self.note = note
    }

    public var isStakeoutGrade: Bool {
        position.isTrustedRTKFix
    }
}

/// 軌跡。点ごとに出どころと精度を残す。記録の画面は次のスライス。
public struct Track: Equatable, Sendable, Codable {
    public var id: UUID
    public var name: String
    public var points: [GeodeticPosition]

    public init(id: UUID = UUID(), name: String, points: [GeodeticPosition] = []) {
        self.id = id
        self.name = name
        self.points = points
    }

    public var lengthMeters: Double {
        guard points.count >= 2 else { return 0 }
        var total = 0.0
        for index in 1..<points.count {
            total += GeoDistance.meters(
                latitude1: points[index - 1].latitudeDegrees,
                longitude1: points[index - 1].longitudeDegrees,
                latitude2: points[index].latitudeDegrees,
                longitude2: points[index].longitudeDegrees
            )
        }
        return total
    }

    public func appending(_ position: GeodeticPosition) -> Track {
        var copy = self
        copy.points.append(position)
        return copy
    }
}
