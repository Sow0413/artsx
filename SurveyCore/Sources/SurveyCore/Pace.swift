import Foundation

/// 歩測と、GNSS が弱いあいだの歩行推測。段階は 0。測設の合格にはしない。
public enum WalkMode: String, Sendable, Equatable {
    case gnss
    case bridge
}

public struct PaceProfile: Codable, Sendable, Equatable {
    public static let storageKey = "survey.pace"

    public var strideMeters: Double?
    /// 歩きながら登る勾配。1m あたりの高低。0 は平ら。
    public var slope: Double
    /// 空なら勾配から係数を出す。
    public var factorOverride: Double?
    public var calibratedDistanceMeters: Double?
    public var calibratedSteps: Int?

    public init(
        strideMeters: Double? = nil,
        slope: Double = 0,
        factorOverride: Double? = nil,
        calibratedDistanceMeters: Double? = nil,
        calibratedSteps: Int? = nil
    ) {
        self.strideMeters = strideMeters
        self.slope = slope
        self.factorOverride = factorOverride
        self.calibratedDistanceMeters = calibratedDistanceMeters
        self.calibratedSteps = calibratedSteps
    }

    public func sanitized() -> PaceProfile {
        var copy = self
        if let stride = copy.strideMeters, !stride.isFinite || stride < 0.3 || stride > 1.5 {
            copy.strideMeters = nil
        }
        if !copy.slope.isFinite { copy.slope = 0 }
        if let factor = copy.factorOverride, !factor.isFinite || factor <= 0 || factor > 2 {
            copy.factorOverride = nil
        }
        return copy
    }

    public func save(to defaults: UserDefaults = .standard) {
        let clean = sanitized()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> PaceProfile {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(PaceProfile.self, from: data) else {
            return PaceProfile()
        }
        return stored.sanitized()
    }
}

public struct PaceBadge: Equatable, Sendable {
    public static let label = "歩測"
    public var text: String
    public var accessibilityText: String
    public var isStakeoutGrade: Bool

    public init(text: String, accessibilityText: String, isStakeoutGrade: Bool) {
        self.text = text
        self.accessibilityText = accessibilityText
        self.isStakeoutGrade = isStakeoutGrade
    }
}

public struct WalkFix: Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var pathMeters: Double
    public var sigmaMeters: Double
    public var steps: Int
    public var usedVisual: Bool

    public init(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        pathMeters: Double,
        sigmaMeters: Double,
        steps: Int,
        usedVisual: Bool
    ) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.pathMeters = pathMeters
        self.sigmaMeters = sigmaMeters
        self.steps = steps
        self.usedVisual = usedVisual
    }
}

/// 開始点から、歩数と方位、あれば視覚慣性の水平移動を足す。
public struct WalkBridge: Equatable, Sendable {
    public var originLatitude: Double
    public var originLongitude: Double
    public var strideMeters: Double
    public var slope: Double
    public var factorOverride: Double?
    public private(set) var steps: Int
    public private(set) var pathMeters: Double
    public private(set) var eastMeters: Double
    public private(set) var northMeters: Double
    private var lastSteps: Int
    private var visualEast: Double?
    private var visualNorth: Double?

    public init(
        originLatitude: Double,
        originLongitude: Double,
        strideMeters: Double,
        slope: Double = 0,
        factorOverride: Double? = nil
    ) {
        self.originLatitude = originLatitude
        self.originLongitude = originLongitude
        self.strideMeters = strideMeters
        self.slope = slope
        self.factorOverride = factorOverride
        self.steps = 0
        self.pathMeters = 0
        self.eastMeters = 0
        self.northMeters = 0
        self.lastSteps = 0
    }

    public static func == (lhs: WalkBridge, rhs: WalkBridge) -> Bool {
        lhs.originLatitude == rhs.originLatitude
            && lhs.originLongitude == rhs.originLongitude
            && lhs.strideMeters == rhs.strideMeters
            && lhs.slope == rhs.slope
            && lhs.factorOverride == rhs.factorOverride
            && lhs.steps == rhs.steps
            && lhs.pathMeters == rhs.pathMeters
            && lhs.eastMeters == rhs.eastMeters
            && lhs.northMeters == rhs.northMeters
            && lhs.lastSteps == rhs.lastSteps
            && lhs.visualEast == rhs.visualEast
            && lhs.visualNorth == rhs.visualNorth
    }

    /// 歩数計の累計。方位が無い歩は、次に方位が付くまで保留する。
    public mutating func add(totalSteps: Int, headingDegrees: Double?) {
        guard totalSteps >= lastSteps else { return }
        let delta = totalSteps - lastSteps
        guard delta > 0, let headingDegrees, headingDegrees.isFinite,
              let length = PaceMath.distance(steps: delta, strideMeters: strideMeters, slope: slope, factorOverride: factorOverride)
        else { return }
        let radians = GeoMath.radians(fromDegrees: headingDegrees)
        eastMeters += length * GeoMath.sine(radians)
        northMeters += length * GeoMath.cosine(radians)
        pathMeters += length
        steps = totalSteps
        lastSteps = totalSteps
    }

    public mutating func setVisual(east: Double, north: Double) {
        guard east.isFinite, north.isFinite else { return }
        visualEast = east
        visualNorth = north
    }

    public func place() -> WalkFix? {
        guard steps > 0, pathMeters > 0, originLatitude.isFinite, originLongitude.isFinite else { return nil }
        let fused = PaceMath.fuse(
            stepEast: eastMeters,
            stepNorth: northMeters,
            visualEast: visualEast,
            visualNorth: visualNorth
        )
        let distance = GeoMath.hypotenuse(fused.east, fused.north)
        guard distance.isFinite, distance > 0 else { return nil }
        let azimuth = GeoMath.degrees(fromRadians: GeoMath.arctangent(fused.east, fused.north))
        guard let moved = GRS80Geodesic.direct(
            latitude: originLatitude,
            longitude: originLongitude,
            azimuthDegrees: azimuth,
            distanceMeters: distance
        ) else { return nil }
        return WalkFix(
            latitudeDegrees: moved.latitude,
            longitudeDegrees: moved.longitude,
            pathMeters: pathMeters,
            sigmaMeters: PaceMath.bridgeSigma(pathMeters: pathMeters, disagreementMeters: fused.disagreement),
            steps: steps,
            usedVisual: fused.usedVisual
        )
    }
}

public enum PaceMath {
    public static let kind = "歩測"
    public static let exampleDistanceMeters = 50.0
    /// これより粗い GNSS は歩行推測に切り替える。
    public static let weakMeters = 15.0
    /// これ以内に戻ったら GNSS に戻す。あいだは今のモードを保つ。
    public static let restoredMeters = 8.0
    public static let paceFraction = 0.02
    public static let paceFloorMeters = 0.5
    public static let bridgeFraction = 0.03
    public static let bridgeFloorMeters = 1.0

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    /// 校正走路の道のり ÷ 歩数。平らな所で測った歩幅。
    public static func stride(distanceMeters: Double, steps: Int) -> Double? {
        guard distanceMeters.isFinite, distanceMeters >= 5, distanceMeters <= 500, steps >= 5 else { return nil }
        let value = distanceMeters / Double(steps)
        guard value.isFinite, value >= 0.3, value <= 1.5 else { return nil }
        return value
    }

    /// 斜面の道のりを水平に直す係数。勾配 0 なら 1。
    public static func slopeFactor(_ slope: Double) -> Double? {
        guard slope.isFinite, abs(slope) <= 2 else { return nil }
        let factor = 1 / GeoMath.squareRoot(1 + slope * slope)
        return factor.isFinite && factor > 0 ? factor : nil
    }

    public static func factor(slope: Double, override: Double?) -> Double? {
        if let override, override.isFinite, override > 0, override <= 2 { return override }
        return slopeFactor(slope)
    }

    public static func distance(steps: Int, strideMeters: Double, slope: Double, factorOverride: Double? = nil) -> Double? {
        guard steps >= 0, strideMeters.isFinite, strideMeters > 0, let factor = factor(slope: slope, override: factorOverride) else { return nil }
        let length = Double(steps) * strideMeters * factor
        return length.isFinite ? length : nil
    }

    public static func paceSigma(distanceMeters: Double) -> Double {
        guard distanceMeters.isFinite, distanceMeters >= 0 else { return paceFloorMeters }
        return paceFloorMeters + paceFraction * distanceMeters
    }

    public static func bridgeSigma(pathMeters: Double, disagreementMeters: Double) -> Double {
        let path = pathMeters.isFinite ? max(0, pathMeters) : 0
        let gap = disagreementMeters.isFinite ? max(0, disagreementMeters) : 0
        return GeoMath.hypotenuse(bridgeFloorMeters + bridgeFraction * path, gap)
    }

    public static func gnssWeak(accuracyMeters: Double?) -> Bool {
        guard let accuracyMeters, accuracyMeters.isFinite, accuracyMeters >= 0 else { return true }
        return accuracyMeters > weakMeters
    }

    public static func gnssRestored(accuracyMeters: Double?) -> Bool {
        guard let accuracyMeters, accuracyMeters.isFinite, accuracyMeters >= 0 else { return false }
        return accuracyMeters <= restoredMeters
    }

    public static func nextMode(current: WalkMode, accuracyMeters: Double?) -> WalkMode {
        if gnssRestored(accuracyMeters: accuracyMeters) { return .gnss }
        if gnssWeak(accuracyMeters: accuracyMeters) { return .bridge }
        return current
    }

    /// 共有する精度。歩行推測中は GNSS の数値を使わない。
    public static func sharedAccuracy(gnssMeters: Double?, bridgeSigmaMeters: Double?, mode: WalkMode) -> Double? {
        if mode == .bridge, let bridgeSigmaMeters, bridgeSigmaMeters.isFinite { return bridgeSigmaMeters }
        return gnssMeters
    }

    public static func fuse(
        stepEast: Double,
        stepNorth: Double,
        visualEast: Double?,
        visualNorth: Double?
    ) -> (east: Double, north: Double, disagreement: Double, usedVisual: Bool) {
        guard stepEast.isFinite, stepNorth.isFinite else {
            return (0, 0, 0, false)
        }
        guard let visualEast, let visualNorth, visualEast.isFinite, visualNorth.isFinite else {
            return (stepEast, stepNorth, 0, false)
        }
        let disagreement = GeoMath.hypotenuse(stepEast - visualEast, stepNorth - visualNorth)
        return ((stepEast + visualEast) / 2, (stepNorth + visualNorth) / 2, disagreement, true)
    }

    /// ARKit の +Z が向く方位。視線の方位から、視線が +Z から何度ずれているかを引く。
    public static func yawOfPlusZ(headingDegrees: Double, forwardFromPlusZDegrees: Double) -> Double? {
        guard headingDegrees.isFinite, forwardFromPlusZDegrees.isFinite else { return nil }
        return headingDegrees - forwardFromPlusZDegrees
    }

    public static func forwardFromPlusZ(x: Double, z: Double) -> Double? {
        guard x.isFinite, z.isFinite, GeoMath.hypotenuse(x, z) > 0.2 else { return nil }
        return GeoMath.degrees(fromRadians: GeoMath.arctangent(x, z))
    }

    /// yaw は、AR の +Z が北から時計回りに何度か。
    public static func horizontal(dx: Double, dz: Double, yawDegrees: Double) -> (east: Double, north: Double)? {
        guard dx.isFinite, dz.isFinite, yawDegrees.isFinite else { return nil }
        let yaw = GeoMath.radians(fromDegrees: yawDegrees)
        let east = dx * GeoMath.cosine(yaw) + dz * GeoMath.sine(yaw)
        let north = -dx * GeoMath.sine(yaw) + dz * GeoMath.cosine(yaw)
        guard east.isFinite, north.isFinite else { return nil }
        return (east, north)
    }

    public static func distanceText(_ meters: Double) -> String {
        guard meters.isFinite else { return "—" }
        return String(format: "%.1fm", locale: posix, meters)
    }

    public static func estimateText(_ meters: Double) -> String {
        guard meters.isFinite else { return "推定 —" }
        if abs(meters) >= 1 {
            return String(format: "推定 ±%.1fm", locale: posix, meters)
        }
        return String(format: "推定 ±%.0fcm", locale: posix, abs(meters) * 100)
    }

    public static func badge(distanceMeters: Double?, sigmaMeters: Double?) -> PaceBadge {
        var parts = ["段階0"]
        if let distanceMeters, distanceMeters.isFinite { parts.append(distanceText(distanceMeters)) }
        if let sigmaMeters, sigmaMeters.isFinite { parts.append(estimateText(sigmaMeters)) }
        let text = parts.joined(separator: "　")
        return PaceBadge(
            text: text,
            accessibilityText: "歩測。段階0。\(text)。測設の合格にはしません。",
            isStakeoutGrade: false
        )
    }
}
