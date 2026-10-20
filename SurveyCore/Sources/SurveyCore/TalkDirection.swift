import Foundation

/// 受信中の無線を、どの向きから測るか。
public enum TalkFacing: Sendable, Equatable {
    /// 動いていれば進行、止まっていれば方位。
    case own
    /// 重機の向き。方位を先に使い、無ければ進行。
    case machine
}

/// 話者の方向。位置が古いか取れなければ known は false。
public struct TalkPointer: Equatable, Sendable {
    public var speaker: String
    public var text: String
    public var relativeDegrees: Double?
    public var distanceMeters: Double?
    public var known: Bool
    /// 「重機」か「進行」か「方位」。方向不明のときは空。
    public var reference: String

    public init(
        speaker: String,
        text: String,
        relativeDegrees: Double?,
        distanceMeters: Double?,
        known: Bool,
        reference: String
    ) {
        self.speaker = speaker
        self.text = text
        self.relativeDegrees = relativeDegrees
        self.distanceMeters = distanceMeters
        self.known = known
        self.reference = reference
    }
}

/// AVAudioEnvironmentNode に渡す位置。右が +x、上が +y、前が -z。
public struct TalkPoint: Equatable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float

    public init(x: Float, y: Float, z: Float) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public enum TalkDirection {
    /// 共有位置を古いとみなす秒。位置共有が相手を落とすのと同じ。
    public static let staleSeconds: TimeInterval = CrewDesk.staleSeconds

    public static func pointer(
        speaker: String,
        fixes: [CrewFix],
        selfLatitude: Double?,
        selfLongitude: Double?,
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing,
        now: Date,
        staleSeconds: TimeInterval = TalkDirection.staleSeconds
    ) -> TalkPointer {
        let name = speaker.trimmingCharacters(in: .whitespacesAndNewlines)
        let unknown = TalkPointer(
            speaker: name,
            text: name.isEmpty ? "方向不明" : "方向不明 \(name)",
            relativeDegrees: nil,
            distanceMeters: nil,
            known: false,
            reference: ""
        )
        guard !name.isEmpty,
              let fix = latest(named: name, in: fixes),
              now.timeIntervalSince(fix.sentAt) <= staleSeconds,
              let selfLatitude, let selfLongitude,
              valid(selfLatitude, selfLongitude),
              valid(fix.latitudeDegrees, fix.longitudeDegrees),
              let inverse = GRS80Geodesic.inverse(
                latitude1: selfLatitude,
                longitude1: selfLongitude,
                latitude2: fix.latitudeDegrees,
                longitude2: fix.longitudeDegrees
              ),
              let aim = aim(courseDegrees: courseDegrees, headingDegrees: headingDegrees, facing: facing)
        else { return unknown }
        let turn = ThreatBearing.relative(targetAzimuthDegrees: inverse.azimuthDegrees, facingDegrees: aim.degrees)
        let meters = max(0, Int(inverse.distanceMeters.rounded()))
        let sector = ThreatBearing.sector(relativeDegrees: turn)
        return TalkPointer(
            speaker: name,
            text: "\(sector) \(meters)m \(name)",
            relativeDegrees: turn,
            distanceMeters: inverse.distanceMeters,
            known: true,
            reference: aim.source
        )
    }

    /// 近いほど原点に寄せ、遠いほど 8m まで離す。方向は残す。
    public static func space(relativeDegrees: Double, distanceMeters: Double) -> TalkPoint {
        let turn = ThreatBearing.relative(targetAzimuthDegrees: relativeDegrees, facingDegrees: 0)
        let radians = GeoMath.radians(fromDegrees: turn)
        let clamped = min(max(distanceMeters.isFinite ? distanceMeters : 0, 0), 500)
        let radius = Float(1 + (clamped / 500) * 7)
        return TalkPoint(
            x: radius * Float(GeoMath.sine(radians)),
            y: 0,
            z: -radius * Float(GeoMath.cosine(radians))
        )
    }

    private static func latest(named name: String, in fixes: [CrewFix]) -> CrewFix? {
        fixes.filter { $0.name == name }.max { $0.sentAt < $1.sentAt }
    }

    private static func valid(_ latitude: Double, _ longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180
    }

    private static func aim(
        courseDegrees: Double?,
        headingDegrees: Double?,
        facing: TalkFacing
    ) -> (degrees: Double, source: String)? {
        switch facing {
        case .own:
            return ThreatBearing.facing(courseDegrees: courseDegrees, headingDegrees: headingDegrees)
        case .machine:
            if let headingDegrees, headingDegrees.isFinite {
                return (headingDegrees, "重機")
            }
            if let courseDegrees, courseDegrees.isFinite {
                return (courseDegrees, "進行")
            }
            return nil
        }
    }
}
