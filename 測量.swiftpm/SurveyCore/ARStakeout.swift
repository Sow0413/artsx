import Foundation

/// 画面でタップしたARの点と、座標簿の既知点。
public struct ARStakeoutPair: Equatable, Sendable {
    public var name: String
    public var arX: Double
    public var arZ: Double
    public var eastingMeters: Double
    public var northingMeters: Double

    public init(name: String, arX: Double, arZ: Double, eastingMeters: Double, northingMeters: Double) {
        self.name = name
        self.arX = arX
        self.arZ = arZ
        self.eastingMeters = eastingMeters
        self.northingMeters = northingMeters
    }
}

public enum ARStakeoutMethod: String, Codable, Sendable, Equatable {
    case knownPoints
    case walk
    case rtk

    public var label: String {
        switch self {
        case .knownPoints: return "既知点"
        case .walk: return "歩行"
        case .rtk: return "RTK"
        }
    }
}

/// ARの水平（x, z）を、平面直角の東・北へ写す。縮尺は1。
public struct ARStakeoutAlignment: Equatable, Sendable {
    public var method: ARStakeoutMethod
    public var transform: Similarity2D
    public var residualsMeters: [Double]
    public var rmsMeters: Double
    public var alignedAt: Date

    public init(method: ARStakeoutMethod, transform: Similarity2D, residualsMeters: [Double], rmsMeters: Double, alignedAt: Date) {
        self.method = method
        self.transform = transform
        self.residualsMeters = residualsMeters
        self.rmsMeters = rmsMeters
        self.alignedAt = alignedAt
    }
}

public struct ARStakeoutTarget: Equatable, Sendable, Identifiable {
    public var name: String
    public var eastingMeters: Double
    public var northingMeters: Double

    public var id: String { name }

    public init(name: String, eastingMeters: Double, northingMeters: Double) {
        self.name = name
        self.eastingMeters = eastingMeters
        self.northingMeters = northingMeters
    }
}

public struct ARStaff: Equatable, Sendable {
    public var name: String
    public var arX: Double
    public var groundY: Double
    public var arZ: Double
    public var heightMeters: Double
    public var label: String
    public var primary: Bool

    public init(name: String, arX: Double, groundY: Double, arZ: Double, heightMeters: Double, label: String, primary: Bool) {
        self.name = name
        self.arX = arX
        self.groundY = groundY
        self.arZ = arZ
        self.heightMeters = heightMeters
        self.label = label
        self.primary = primary
    }
}

public struct ARStakeoutPicture: Equatable, Sendable {
    public var staffs: [ARStaff]
    public var errorMeters: Double
    public var errorText: String
    public var realign: Bool
    public var numeric: Bool
    public var speech: String?
    public var methodLabel: String
    public var residualText: String?

    public init(
        staffs: [ARStaff],
        errorMeters: Double,
        errorText: String,
        realign: Bool,
        numeric: Bool,
        speech: String?,
        methodLabel: String,
        residualText: String?
    ) {
        self.staffs = staffs
        self.errorMeters = errorMeters
        self.errorText = errorText
        self.realign = realign
        self.numeric = numeric
        self.speech = speech
        self.methodLabel = methodLabel
        self.residualText = residualText
    }
}

public struct ARScreenPoint: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var visible: Bool

    public init(x: Double, y: Double, visible: Bool) {
        self.x = x
        self.y = y
        self.visible = visible
    }
}

/// 位置出しのAR。杖の位置、合わせ、ドリフト、最後の数cmの切替。実機のARKitは未確認。
public enum ARStakeoutMath {
    /// これより近い目標は、数値の誘導に切り替える。
    public static let handoffMeters = 0.05
    /// これを超えたら、もう一度合わせる。設計値。
    public static let realignMeters = 0.10
    public static let driftMetersPerSecond = 0.005
    public static let driftMetersPerMeter = 0.01
    public static let minimumTrackMeters = 2.0
    public static let staffHeightMeters = 1.5

    public static func align(pairs: [ARStakeoutPair], at date: Date) -> ARStakeoutAlignment? {
        let mapped = pairs.map { pair in
            (source: PlanarPoint(x: pair.arX, y: pair.arZ), target: PlanarPoint(x: pair.eastingMeters, y: pair.northingMeters))
        }
        guard let fit = SimilaritySolver.fit(mapped, lockScale: true) else { return nil }
        return ARStakeoutAlignment(
            method: .knownPoints,
            transform: fit.transform,
            residualsMeters: fit.residualsMeters,
            rmsMeters: fit.rmsMeters,
            alignedAt: date
        )
    }

    /// 歩いた平面位置の方位。北から時計回り。2m 未満は nil。
    public static func trackAzimuth(fromEasting: Double, fromNorthing: Double, toEasting: Double, toNorthing: Double) -> Double? {
        let east = toEasting - fromEasting
        let north = toNorthing - fromNorthing
        guard east.isFinite, north.isFinite else { return nil }
        guard (east * east + north * north).squareRoot() >= minimumTrackMeters else { return nil }
        var degrees = GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north))
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// GNSSの今の位置と、歩行方位でARを仮に置く。縮尺は1。
    public static func alignWalk(
        cameraX: Double,
        cameraZ: Double,
        forwardX: Double,
        forwardZ: Double,
        eastingMeters: Double,
        northingMeters: Double,
        azimuthDegrees: Double,
        at date: Date
    ) -> ARStakeoutAlignment? {
        guard [cameraX, cameraZ, forwardX, forwardZ, eastingMeters, northingMeters, azimuthDegrees].allSatisfy(\.isFinite) else { return nil }
        let length = (forwardX * forwardX + forwardZ * forwardZ).squareRoot()
        guard length > 0.2 else { return nil }
        let ux = forwardX / length
        let uz = forwardZ / length
        let radians = GeoMath.radians(fromDegrees: azimuthDegrees)
        let targetEast = GeoMath.sine(radians)
        let targetNorth = GeoMath.cosine(radians)
        let dot = ux * targetEast + uz * targetNorth
        let cross = ux * targetNorth - uz * targetEast
        let rotation = GeoMath.degrees(fromRadians: GeoMath.arctangent(cross, dot))
        let turned = Similarity2D(scale: 1, rotationDegrees: rotation, translationEasting: 0, translationNorthing: 0)
        let mapped = turned.apply(PlanarPoint(x: cameraX, y: cameraZ))
        let transform = Similarity2D(
            scale: 1,
            rotationDegrees: rotation,
            translationEasting: eastingMeters - mapped.x,
            translationNorthing: northingMeters - mapped.y
        )
        return ARStakeoutAlignment(method: .walk, transform: transform, residualsMeters: [], rmsMeters: 0, alignedAt: date)
    }

    /// RTK FIXの位置へ、向きは保ったまま平行移動する。
    public static func correct(
        _ alignment: ARStakeoutAlignment,
        cameraX: Double,
        cameraZ: Double,
        eastingMeters: Double,
        northingMeters: Double,
        gnssMeters: Double,
        at date: Date
    ) -> ARStakeoutAlignment? {
        guard [cameraX, cameraZ, eastingMeters, northingMeters, gnssMeters].allSatisfy(\.isFinite), gnssMeters >= 0 else { return nil }
        let mapped = alignment.transform.apply(PlanarPoint(x: cameraX, y: cameraZ))
        let transform = Similarity2D(
            scale: alignment.transform.scale,
            rotationDegrees: alignment.transform.rotationDegrees,
            translationEasting: alignment.transform.translationEasting + (eastingMeters - mapped.x),
            translationNorthing: alignment.transform.translationNorthing + (northingMeters - mapped.y)
        )
        return ARStakeoutAlignment(
            method: .rtk,
            transform: transform,
            residualsMeters: [],
            rmsMeters: gnssMeters,
            alignedAt: date
        )
    }

    public static func drift(seconds: TimeInterval, walkedMeters: Double) -> Double {
        let time = seconds.isFinite ? max(0, seconds) : 0
        let walked = walkedMeters.isFinite ? max(0, walkedMeters) : 0
        return driftMetersPerSecond * time + driftMetersPerMeter * walked
    }

    public static func errorMeters(drift: Double, rms: Double) -> Double {
        let driftPart = drift.isFinite ? max(0, drift) : 0
        let fit = rms.isFinite ? max(0, rms) : 0
        return (driftPart * driftPart + fit * fit).squareRoot()
    }

    public static func shouldRealign(_ error: Double) -> Bool {
        error.isFinite && error > realignMeters
    }

    /// LiDAR、無ければ検出した平面、無ければ高さ0の仮定。
    public static func ground(lidarY: Double?, planeY: Double?) -> (y: Double, source: String) {
        if let lidarY, lidarY.isFinite { return (lidarY, "LiDAR") }
        if let planeY, planeY.isFinite { return (planeY, "平面") }
        return (0, "仮定")
    }

    public static func residualText(_ residuals: [Double]) -> String? {
        let shown = residuals.filter(\.isFinite).map { centimeters($0) }
        guard !shown.isEmpty else { return nil }
        let list = shown.map { "\($0)cm" }.joined(separator: "　")
        let mean = shown.reduce(0, +) / shown.count
        return "残差 \(list)　平均 \(mean)cm"
    }

    public static func picture(
        alignment: ARStakeoutAlignment,
        targets: [ARStakeoutTarget],
        currentIndex: Int,
        groundY: Double,
        hereEasting: Double,
        hereNorthing: Double,
        facingDegrees: Double?,
        strideMeters: Double?,
        unit: StakeoutUnit,
        seconds: TimeInterval,
        walkedMeters: Double
    ) -> ARStakeoutPicture? {
        guard targets.indices.contains(currentIndex) else { return nil }
        guard hereEasting.isFinite, hereNorthing.isFinite, groundY.isFinite else { return nil }
        let current = targets[currentIndex]
        let here = PlanarPoint(x: hereEasting, y: hereNorthing)
        let target = PlanarPoint(x: current.eastingMeters, y: current.northingMeters)
        let distance = here.distance(to: target)
        let azimuth = GeoMath.degrees(fromRadians: GeoMath.arctangent(target.x - here.x, target.y - here.y))
        let guide = StakeoutPace.guide(
            distanceMeters: distance,
            azimuthDegrees: azimuth < 0 ? azimuth + 360 : azimuth,
            facingDegrees: facingDegrees,
            strideMeters: strideMeters,
            unit: unit
        )
        let numeric = distance < handoffMeters
        var staffs: [ARStaff] = []
        if let staff = staff(current, alignment: alignment, groundY: groundY, label: guide?.speech ?? current.name, primary: true), !numeric {
            staffs.append(staff)
        }
        if currentIndex + 1 < targets.count {
            let next = targets[currentIndex + 1]
            if let staff = staff(next, alignment: alignment, groundY: groundY, label: next.name, primary: false) {
                staffs.append(staff)
            }
        }
        let error = errorMeters(drift: drift(seconds: seconds, walkedMeters: walkedMeters), rms: alignment.rmsMeters)
        let realign = shouldRealign(error)
        var errorText = "推定誤差 \(centimeters(error))cm（\(alignment.method.label)）"
        if realign {
            errorText += "。既知点でもう一度合わせてください。"
        }
        return ARStakeoutPicture(
            staffs: staffs,
            errorMeters: error,
            errorText: errorText,
            realign: realign,
            numeric: numeric,
            speech: guide?.speech,
            methodLabel: alignment.method.label,
            residualText: alignment.method == .knownPoints ? residualText(alignment.residualsMeters) : nil
        )
    }

    /// カメラ行列は列優先の16個。画像のyは下向き。手前だけ visible。
    public static func project(
        camera: [Double],
        fx: Double,
        fy: Double,
        cx: Double,
        cy: Double,
        imageWidth: Double,
        imageHeight: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        worldX: Double,
        worldY: Double,
        worldZ: Double
    ) -> ARScreenPoint? {
        guard camera.count == 16, fx > 1, fy > 1, imageWidth > 1, imageHeight > 1, viewportWidth > 1, viewportHeight > 1 else { return nil }
        guard [worldX, worldY, worldZ].allSatisfy(\.isFinite) else { return nil }
        let right = (camera[0], camera[1], camera[2])
        let up = (camera[4], camera[5], camera[6])
        let back = (camera[8], camera[9], camera[10])
        let origin = (camera[12], camera[13], camera[14])
        let dx = worldX - origin.0
        let dy = worldY - origin.1
        let dz = worldZ - origin.2
        let cameraX = right.0 * dx + right.1 * dy + right.2 * dz
        let cameraY = up.0 * dx + up.1 * dy + up.2 * dz
        let cameraZ = back.0 * dx + back.1 * dy + back.2 * dz
        let depth = -cameraZ
        guard depth > 0.05 else {
            return ARScreenPoint(x: 0, y: 0, visible: false)
        }
        let imageX = fx * (cameraX / depth) + cx
        let imageY = cy - fy * (cameraY / depth)
        return ARScreenPoint(
            x: imageX / imageWidth * viewportWidth,
            y: imageY / imageHeight * viewportHeight,
            visible: true
        )
    }

    /// 画面のタップを、地面の高さの平面へ落とす。当たればARの x, z。
    public static func groundHit(
        tapX: Double,
        tapY: Double,
        viewportWidth: Double,
        viewportHeight: Double,
        camera: [Double],
        fx: Double,
        fy: Double,
        cx: Double,
        cy: Double,
        imageWidth: Double,
        imageHeight: Double,
        groundY: Double
    ) -> (x: Double, z: Double)? {
        guard camera.count == 16, fx > 1, fy > 1, imageWidth > 1, imageHeight > 1, viewportWidth > 1, viewportHeight > 1 else { return nil }
        guard groundY.isFinite else { return nil }
        let imageX = tapX / viewportWidth * imageWidth
        let imageY = tapY / viewportHeight * imageHeight
        let cameraX = (imageX - cx) / fx
        let cameraY = -(imageY - cy) / fy
        let right = (camera[0], camera[1], camera[2])
        let up = (camera[4], camera[5], camera[6])
        let back = (camera[8], camera[9], camera[10])
        let origin = (camera[12], camera[13], camera[14])
        let dir = (
            right.0 * cameraX + up.0 * cameraY - back.0,
            right.1 * cameraX + up.1 * cameraY - back.1,
            right.2 * cameraX + up.2 * cameraY - back.2
        )
        guard abs(dir.1) > 1e-8 else { return nil }
        let travel = (groundY - origin.1) / dir.1
        guard travel > 0 else { return nil }
        return (origin.0 + travel * dir.0, origin.2 + travel * dir.2)
    }

    private static func staff(
        _ target: ARStakeoutTarget,
        alignment: ARStakeoutAlignment,
        groundY: Double,
        label: String,
        primary: Bool
    ) -> ARStaff? {
        guard let ar = alignment.transform.inverse(PlanarPoint(x: target.eastingMeters, y: target.northingMeters)) else { return nil }
        return ARStaff(
            name: target.name,
            arX: ar.x,
            groundY: groundY,
            arZ: ar.y,
            heightMeters: staffHeightMeters,
            label: label,
            primary: primary
        )
    }

    private static func centimeters(_ meters: Double) -> Int {
        Int((abs(meters) * 100).rounded())
    }
}
