import Foundation

/// 重機の運転席向け。基準線に沿った測点と、左右の離れ。
public struct OperatorGuide: Sendable, Equatable {
    /// `No.23+5m 左3m` のような1行。
    public var line: String
    /// 起点からの距離。手前は負。
    public var alongMeters: Double
    /// 進行方向に対して左が正。
    public var offsetMeters: Double
    /// 基準線の進行方向。北から時計回り。
    public var forwardAzimuthDegrees: Double

    public init(line: String, alongMeters: Double, offsetMeters: Double, forwardAzimuthDegrees: Double) {
        self.line = line
        self.alongMeters = alongMeters
        self.offsetMeters = offsetMeters
        self.forwardAzimuthDegrees = forwardAzimuthDegrees
    }
}

public struct OperatorArrow: Sendable, Equatable {
    /// 基準線の進行方向を上にしたとき、端末の向き。右が正。
    public var relativeDegrees: Double
    /// 進行方向が取れれば「進行」、なければコンパスの「方位」。
    public var source: String

    public init(relativeDegrees: Double, source: String) {
        self.relativeDegrees = relativeDegrees
        self.source = source
    }
}

/// 視線高を足す基準。端末をその高さに置いたときだけ使う。
public enum SightDatum: String, Codable, Sendable, CaseIterable {
    case ground
    case machine

    public var label: String {
        switch self {
        case .ground: return "地盤"
        case .machine: return "機体"
        }
    }
}

public struct OperatorHeight: Sendable, Equatable {
    /// 特大文字。0.1m。`下がり 1.8m` のように、参考の文字は入れない。
    public var text: String
    /// 小さく添える注記。iPhone の高さなら「参考」。
    public var note: String
    public var isReference: Bool
    /// 計画が視線より下なら正。
    public var meters: Double?

    public init(text: String, note: String, isReference: Bool, meters: Double?) {
        self.text = text
        self.note = note
        self.isReference = isReference
        self.meters = meters
    }
}

public enum OperatorStation {
    /// 日本の道路でよく使う測点間隔。No.1 は 20m。
    public static let intervalMeters = 20.0

    /// 点と折れ線は同じ平面。x は東、y は北。
    public static func guide(
        point: PlanarPoint,
        alignment: [PlanarPoint],
        interval: Double = intervalMeters
    ) -> OperatorGuide? {
        guard alignment.count >= 2, interval > 0 else { return nil }
        guard let hit = project(point, onto: alignment) else { return nil }
        return OperatorGuide(
            line: format(along: hit.along, offset: hit.offset, total: hit.total, interval: interval),
            alongMeters: hit.along,
            offsetMeters: hit.offset,
            forwardAzimuthDegrees: hit.azimuth
        )
    }

    /// 動いていれば進行方向、止まっていれば端末の方位。基準線の進行を上にした角度を返す。
    public static func arrow(courseDegrees: Double?, headingDegrees: Double?, centerlineAzimuth: Double) -> OperatorArrow? {
        let chosen: (degrees: Double, source: String)?
        if let courseDegrees, courseDegrees.isFinite {
            chosen = (courseDegrees, "進行")
        } else if let headingDegrees, headingDegrees.isFinite {
            chosen = (headingDegrees, "方位")
        } else {
            chosen = nil
        }
        guard let chosen else { return nil }
        return OperatorArrow(
            relativeDegrees: relative(device: chosen.degrees, centerline: centerlineAzimuth),
            source: chosen.source
        )
    }

    /// 下がりは 0.1m。端末を目の高さで持つときは楕円体高そのもの。地盤か機体に置くときは視線高を足す。
    /// iPhone の値をそのまま使い、RTK や既知点は前提にしない。
    public static func height(
        ellipsoidalMeters: Double?,
        designMeters: Double?,
        eyeHeightMeters: Double = 2,
        phoneAtEyes: Bool = true
    ) -> OperatorHeight {
        guard let ellipsoidalMeters, ellipsoidalMeters.isFinite else {
            return OperatorHeight(text: "—", note: "", isReference: false, meters: nil)
        }
        let eye = eyeHeightMeters.isFinite && eyeHeightMeters >= 0 ? eyeHeightMeters : 0
        guard let designMeters, designMeters.isFinite else {
            return OperatorHeight(
                text: String(format: "%.1fm", MachineReach.roundTenths(ellipsoidalMeters)),
                note: "参考",
                isReference: true,
                meters: nil
            )
        }
        let sight = phoneAtEyes ? ellipsoidalMeters : ellipsoidalMeters + eye
        let drop = MachineReach.roundTenths(sight - designMeters)
        let text: String
        if drop > 0 {
            text = "下がり \(String(format: "%.1fm", drop))"
        } else if drop < 0 {
            text = "上がり \(String(format: "%.1fm", -drop))"
        } else {
            text = "下がり 0.0m"
        }
        return OperatorHeight(text: text, note: "参考", isReference: true, meters: drop)
    }

    static func relative(device: Double, centerline: Double) -> Double {
        var delta = device - centerline
        while delta > 180 { delta -= 360 }
        while delta <= -180 { delta += 360 }
        return delta
    }

    public static func format(along: Double, offset: Double, total: Double, interval: Double = intervalMeters) -> String {
        let side = sideText(offset)
        let meters = Int(along.rounded())
        if meters < 0 {
            return "起点の手前\(abs(meters))m \(side)"
        }
        if Double(meters) > total + 0.5 {
            return "終点の先\(meters - Int(total.rounded()))m \(side)"
        }
        let step = max(1, Int(interval.rounded()))
        let number = meters / step
        let plus = meters % step
        return "No.\(number)+\(plus)m \(side)"
    }

    private static func sideText(_ offset: Double) -> String {
        let meters = Int(offset.rounded())
        if meters == 0 { return "中心" }
        if meters > 0 { return "左\(meters)m" }
        return "右\(abs(meters))m"
    }

    private static func project(_ point: PlanarPoint, onto alignment: [PlanarPoint]) -> (along: Double, offset: Double, total: Double, azimuth: Double)? {
        var chain = 0.0
        var total = 0.0
        for index in 0..<(alignment.count - 1) {
            total += alignment[index].distance(to: alignment[index + 1])
        }
        var bestDistance = Double.greatestFiniteMagnitude
        var bestAlong = 0.0
        var bestOffset = 0.0
        var bestAzimuth = 0.0
        var found = false
        for index in 0..<(alignment.count - 1) {
            let start = alignment[index]
            let end = alignment[index + 1]
            let vx = end.x - start.x
            let vy = end.y - start.y
            let length = GeoMath.hypotenuse(vx, vy)
            if length < 1e-8 {
                continue
            }
            let wx = point.x - start.x
            let wy = point.y - start.y
            var t = (wx * vx + wy * vy) / (length * length)
            if t < 0 { t = 0 }
            if t > 1 { t = 1 }
            let px = start.x + t * vx
            let py = start.y + t * vy
            let dx = point.x - px
            let dy = point.y - py
            let distance = GeoMath.hypotenuse(dx, dy)
            let cross = vx * dy - vy * dx
            var offset = (cross >= 0 ? 1.0 : -1.0) * distance
            var along = chain + t * length
            if index == 0, t == 0, wx * vx + wy * vy < 0 {
                along = (wx * vx + wy * vy) / length
                offset = (vx * wy - vy * wx) / length
            }
            if index == alignment.count - 2, t == 1, (point.x - end.x) * vx + (point.y - end.y) * vy > 0 {
                let aheadX = point.x - end.x
                let aheadY = point.y - end.y
                along = total + (aheadX * vx + aheadY * vy) / length
                offset = (vx * aheadY - vy * aheadX) / length
            }
            let azimuth = bearing(east: vx, north: vy)
            if distance < bestDistance {
                bestDistance = distance
                bestAlong = along
                bestOffset = offset
                bestAzimuth = azimuth
                found = true
            }
            chain += length
        }
        guard found else { return nil }
        return (bestAlong, bestOffset, total, bestAzimuth)
    }

    private static func bearing(east: Double, north: Double) -> Double {
        var degrees = GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north))
        while degrees < 0 { degrees += 360 }
        while degrees >= 360 { degrees -= 360 }
        return degrees
    }
}
