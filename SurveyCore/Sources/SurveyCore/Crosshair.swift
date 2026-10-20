import Foundation

/// 背面カメラの十字線。水平なら目の高さの水準、傾ければ簡易ターゲット。段階は 0。
public enum CrosshairRange: String, Sendable, Equatable {
    case lidar
    case arkit
    case manual

    public var label: String {
        switch self {
        case .lidar: return "LiDAR"
        case .arkit: return "ARKit"
        case .manual: return "手入力"
        }
    }
}

/// 反転法で合わせた、仰角のゼロ点。
public struct TiltZero: Codable, Sendable, Equatable {
    public static let storageKey = "survey.crosshair.bias"

    public var biasRadians: Double
    public var calibrated: Bool

    public init(biasRadians: Double = 0, calibrated: Bool = false) {
        self.biasRadians = biasRadians
        self.calibrated = calibrated
    }

    /// 同じ傾きを、180°回してもう一度読む。ゼロ点はその平均。
    public static func reversal(firstRadians: Double, reversedRadians: Double) -> Double? {
        guard firstRadians.isFinite, reversedRadians.isFinite else { return nil }
        let bias = (firstRadians + reversedRadians) / 2
        guard bias.isFinite else { return nil }
        return bias
    }

    public func corrected(_ rawRadians: Double) -> Double? {
        guard rawRadians.isFinite, biasRadians.isFinite else { return nil }
        return rawRadians - biasRadians
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> TiltZero {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(TiltZero.self, from: data) else {
            return TiltZero()
        }
        return stored
    }
}

public struct LevelResult: Equatable, Sendable {
    public var instrumentHeightMeters: Double
    public var heightDifferenceMeters: Double
    public var targetHeightMeters: Double

    public init(instrumentHeightMeters: Double, heightDifferenceMeters: Double, targetHeightMeters: Double) {
        self.instrumentHeightMeters = instrumentHeightMeters
        self.heightDifferenceMeters = heightDifferenceMeters
        self.targetHeightMeters = targetHeightMeters
    }
}

public struct TargetResult: Equatable, Sendable {
    public var heightDifferenceMeters: Double
    public var horizontalMeters: Double
    public var heightSigmaMeters: Double
    public var horizontalSigmaMeters: Double
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var targetHeightMeters: Double
    public var azimuthDegrees: Double?

    public init(
        heightDifferenceMeters: Double,
        horizontalMeters: Double,
        heightSigmaMeters: Double,
        horizontalSigmaMeters: Double,
        latitudeDegrees: Double?,
        longitudeDegrees: Double?,
        targetHeightMeters: Double,
        azimuthDegrees: Double?
    ) {
        self.heightDifferenceMeters = heightDifferenceMeters
        self.horizontalMeters = horizontalMeters
        self.heightSigmaMeters = heightSigmaMeters
        self.horizontalSigmaMeters = horizontalSigmaMeters
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.targetHeightMeters = targetHeightMeters
        self.azimuthDegrees = azimuthDegrees
    }
}

public enum CrosshairMath {
    public static let kind = "簡易ターゲット"
    /// 視線が水平とみなす幅。鉛直の端末で、仰角 ±0.1°。
    public static let levelToleranceDegrees = 0.1
    public static let rawAngleSigmaDegrees = 1.0
    public static let calibratedAngleSigmaDegrees = 0.1
    public static let exampleDistanceMeters = 20.0
    public static let lidarSigmaMeters = 0.01
    public static let lidarReachMeters = 5.0

    public static var levelToleranceRadians: Double { levelToleranceDegrees * .pi / 180 }

    public static func isLevel(_ elevationRadians: Double) -> Bool {
        guard elevationRadians.isFinite else { return false }
        return abs(elevationRadians) <= levelToleranceRadians + 1e-12
    }

    public static func angleSigmaRadians(calibrated: Bool) -> Double {
        (calibrated ? calibratedAngleSigmaDegrees : rawAngleSigmaDegrees) * .pi / 180
    }

    /// LiDAR は 5m まで 1cm、それ以遠は距離に比例。ARKit と手入力は距離の 2%、下限 5cm。
    public static func distanceSigma(range: CrosshairRange, distance: Double) -> Double {
        guard distance.isFinite, distance >= 0 else { return 0 }
        switch range {
        case .lidar:
            if distance <= lidarReachMeters { return lidarSigmaMeters }
            return lidarSigmaMeters + 0.01 * (distance - lidarReachMeters)
        case .arkit, .manual:
            return max(0.05, 0.02 * distance)
        }
    }

    /// 高低差の推定誤差。∂(D·sinα)/∂D と ∂(D·sinα)/∂α。
    public static func heightSigma(distance: Double, elevationRadians: Double, angleSigmaRadians: Double, distanceSigma: Double) -> Double {
        guard distance.isFinite, elevationRadians.isFinite, angleSigmaRadians.isFinite, distanceSigma.isFinite else { return 0 }
        let fromDistance = GeoMath.sine(elevationRadians) * distanceSigma
        let fromAngle = distance * GeoMath.cosine(elevationRadians) * angleSigmaRadians
        return GeoMath.hypotenuse(fromDistance, fromAngle)
    }

    public static func horizontalSigma(distance: Double, elevationRadians: Double, angleSigmaRadians: Double, distanceSigma: Double) -> Double {
        guard distance.isFinite, elevationRadians.isFinite, angleSigmaRadians.isFinite, distanceSigma.isFinite else { return 0 }
        let fromDistance = GeoMath.cosine(elevationRadians) * distanceSigma
        let fromAngle = distance * GeoMath.sine(elevationRadians) * angleSigmaRadians
        return GeoMath.hypotenuse(fromDistance, fromAngle)
    }

    public static func centimeterText(_ meters: Double) -> String {
        let centimeters = abs(meters) * 100
        return String(format: "±%.1fcm", locale: Locale(identifier: "en_US_POSIX"), centimeters)
    }

    /// 校正後、水平、20m なら角度 0.1° 分。距離の誤差は水平視線では高低差に出ない。
    public static func exampleLabel(calibrated: Bool) -> String {
        let sigma = heightSigma(
            distance: exampleDistanceMeters,
            elevationRadians: 0,
            angleSigmaRadians: angleSigmaRadians(calibrated: calibrated),
            distanceSigma: 0
        )
        return "20mで \(centimeterText(sigma))"
    }

    public static func angleText(_ radians: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), radians * 180 / .pi)
    }

    public static func meterText(_ meters: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), meters)
    }

    /// 器械高 = 自分の地盤高 + 目の高さ。高低差 = 目の高さ − スタッフ読値。
    public static func level(ground: Double, eye: Double, staff: Double) -> LevelResult? {
        guard ground.isFinite, eye.isFinite, eye > 0, eye <= 3, staff.isFinite, staff >= 0, staff <= 10 else { return nil }
        let instrument = ground + eye
        let difference = eye - staff
        return LevelResult(
            instrumentHeightMeters: instrument,
            heightDifferenceMeters: difference,
            targetHeightMeters: instrument - staff
        )
    }

    /// 高低差 = D·sinα。水平距離 = D·cosα。方位があれば座標にする。
    public static func target(
        originLatitude: Double?,
        originLongitude: Double?,
        originHeight: Double,
        distance: Double,
        elevationRadians: Double,
        azimuthDegrees: Double?,
        angleSigmaRadians: Double,
        distanceSigma: Double
    ) -> TargetResult? {
        guard originHeight.isFinite, distance.isFinite, distance >= 0, distance <= 500 else { return nil }
        guard elevationRadians.isFinite, angleSigmaRadians.isFinite, distanceSigma.isFinite else { return nil }
        let difference = distance * GeoMath.sine(elevationRadians)
        let horizontal = distance * GeoMath.cosine(elevationRadians)
        guard difference.isFinite, horizontal.isFinite, horizontal >= -1e-9 else { return nil }
        let flat = max(0, horizontal)
        var latitude: Double?
        var longitude: Double?
        if let originLatitude, let originLongitude, let azimuthDegrees,
           let place = GRS80Geodesic.direct(
            latitude: originLatitude,
            longitude: originLongitude,
            azimuthDegrees: azimuthDegrees,
            distanceMeters: flat
           ) {
            latitude = place.latitude
            longitude = place.longitude
        }
        return TargetResult(
            heightDifferenceMeters: difference,
            horizontalMeters: flat,
            heightSigmaMeters: heightSigma(
                distance: distance,
                elevationRadians: elevationRadians,
                angleSigmaRadians: angleSigmaRadians,
                distanceSigma: distanceSigma
            ),
            horizontalSigmaMeters: horizontalSigma(
                distance: distance,
                elevationRadians: elevationRadians,
                angleSigmaRadians: angleSigmaRadians,
                distanceSigma: distanceSigma
            ),
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            targetHeightMeters: originHeight + difference,
            azimuthDegrees: azimuthDegrees
        )
    }

    /// 端末の GNSS 精度と、狙いの誤差を合わせる。段階0の数値より良く見せない。
    public static func storedAccuracy(
        originHorizontal: Double,
        originVertical: Double?,
        aimHorizontal: Double,
        aimVertical: Double
    ) -> (horizontal: Double, vertical: Double) {
        let horizontal = GeoMath.hypotenuse(max(0, originHorizontal), max(0, aimHorizontal))
        let vertical = GeoMath.hypotenuse(max(0, originVertical ?? 0), max(0, aimVertical))
        return (horizontal, vertical)
    }

    /// 座標簿に置く点。受信機は iPhone、段階は 0、解は単独。
    public static func position(
        latitude: Double,
        longitude: Double,
        height: Double,
        horizontalAccuracy: Double,
        verticalAccuracy: Double,
        at date: Date
    ) -> GeodeticPosition {
        IPhonePosition.make(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            ellipsoidalHeightMeters: height,
            horizontalAccuracyMeters: horizontalAccuracy,
            verticalAccuracyMeters: verticalAccuracy,
            timestamp: date
        )
    }
}
