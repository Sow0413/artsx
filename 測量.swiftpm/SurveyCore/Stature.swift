import Foundation

/// iPhone を持つ高さ。外部 GNSS のポール高とは別。
public enum HoldStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case sight
    case elbow
    case chest
    case eye
    case ground
    case cab
    case manual

    public var title: String {
        switch self {
        case .sight: return "画面の角度"
        case .elbow: return "肘より上"
        case .chest: return "胸の前"
        case .eye: return "目の高さ"
        case .ground: return "地面に置く"
        case .cab: return "重機運転席"
        case .manual: return "手入力"
        }
    }

    public func menuTitle(coefficients: StatureCoefficients) -> String {
        switch self {
        case .sight:
            return "画面の角度（目の高さ−距離×sinθ）"
        case .elbow:
            return "肘より上（身長×\(StatureMath.factorText(coefficients.elbowFactor))）"
        case .chest:
            return "胸の前（身長×\(StatureMath.factorText(coefficients.chestFactor))）"
        case .eye:
            return "目の高さ（身長−\(StatureMath.factorText(coefficients.eyeDropMeters))m）"
        case .ground:
            return "地面に置く"
        case .cab:
            return "重機運転席（\(StatureMath.factorText(coefficients.cabMeters))m）"
        case .manual:
            return "手入力"
        }
    }
}

/// 肘より上は身長×0.70、胸の前は身長×0.72、目の高さは身長から一定を引く、運転席は既存の 2m。
public struct StatureCoefficients: Codable, Sendable, Equatable {
    public static let standard = StatureCoefficients(elbowFactor: 0.70, chestFactor: 0.72, eyeDropMeters: 0.10, cabMeters: 2)

    public var elbowFactor: Double
    public var chestFactor: Double
    public var eyeDropMeters: Double
    public var cabMeters: Double

    public init(elbowFactor: Double = 0.70, chestFactor: Double, eyeDropMeters: Double, cabMeters: Double) {
        self.elbowFactor = elbowFactor
        self.chestFactor = chestFactor
        self.eyeDropMeters = eyeDropMeters
        self.cabMeters = cabMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        elbowFactor = try container.decodeIfPresent(Double.self, forKey: .elbowFactor) ?? 0.70
        chestFactor = try container.decode(Double.self, forKey: .chestFactor)
        eyeDropMeters = try container.decode(Double.self, forKey: .eyeDropMeters)
        cabMeters = try container.decode(Double.self, forKey: .cabMeters)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(elbowFactor, forKey: .elbowFactor)
        try container.encode(chestFactor, forKey: .chestFactor)
        try container.encode(eyeDropMeters, forKey: .eyeDropMeters)
        try container.encode(cabMeters, forKey: .cabMeters)
    }

    private enum CodingKeys: String, CodingKey {
        case elbowFactor, chestFactor, eyeDropMeters, cabMeters
    }
}

/// 利用者の身長と、今の持ち方。端末に残す。現場の座標とは別。
public struct StatureProfile: Codable, Sendable, Equatable {
    public static let storageKey = "survey.stature"

    public var statureMeters: Double?
    public var style: HoldStyle
    public var manualMeters: Double
    public var coefficients: StatureCoefficients

    public init(
        statureMeters: Double? = nil,
        style: HoldStyle = .sight,
        manualMeters: Double = 1.2,
        coefficients: StatureCoefficients = .standard
    ) {
        self.statureMeters = statureMeters
        self.style = style
        self.manualMeters = manualMeters
        self.coefficients = coefficients
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> StatureProfile {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StatureProfile.self, from: data) else {
            return StatureProfile()
        }
        return stored
    }
}

/// 外部受信機のポール高。身長補正はこれを読まない。
public struct PoleHeight: Codable, Sendable, Equatable {
    public static let storageKey = "survey.poleHeight"
    public var meters: Double?

    public init(meters: Double? = nil) {
        self.meters = meters
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> PoleHeight {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(PoleHeight.self, from: data) else {
            return PoleHeight()
        }
        return stored
    }
}

/// 点を取ったときに掛けた身長補正。あとから同じ端末高で掛け直せる。
public struct StatureRecord: Codable, Sendable, Equatable {
    public var style: HoldStyle
    public var offsetMeters: Double
    public var holdMeters: Double
    public var statureMeters: Double?
    public var elbowFactor: Double
    public var chestFactor: Double
    public var eyeDropMeters: Double
    public var cabMeters: Double
    public var groundHeightMeters: Double?
    /// 鉛直からの後傾。画面の角度のときだけ。
    public var tiltRadians: Double?
    /// 目までの距離。測れないときは 0.35。
    public var eyeDistanceMeters: Double?
    public var distanceMeasured: Bool?
    /// 端末中心から GNSS アンテナへ、portrait 上方向の定数。
    public var antennaAlongUpMeters: Double?

    public init(
        style: HoldStyle,
        offsetMeters: Double,
        holdMeters: Double,
        statureMeters: Double?,
        elbowFactor: Double = 0.70,
        chestFactor: Double,
        eyeDropMeters: Double,
        cabMeters: Double,
        groundHeightMeters: Double?,
        tiltRadians: Double? = nil,
        eyeDistanceMeters: Double? = nil,
        distanceMeasured: Bool? = nil,
        antennaAlongUpMeters: Double? = nil
    ) {
        self.style = style
        self.offsetMeters = offsetMeters
        self.holdMeters = holdMeters
        self.statureMeters = statureMeters
        self.elbowFactor = elbowFactor
        self.chestFactor = chestFactor
        self.eyeDropMeters = eyeDropMeters
        self.cabMeters = cabMeters
        self.groundHeightMeters = groundHeightMeters
        self.tiltRadians = tiltRadians
        self.eyeDistanceMeters = eyeDistanceMeters
        self.distanceMeasured = distanceMeasured
        self.antennaAlongUpMeters = antennaAlongUpMeters
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        style = try container.decode(HoldStyle.self, forKey: .style)
        offsetMeters = try container.decode(Double.self, forKey: .offsetMeters)
        holdMeters = try container.decode(Double.self, forKey: .holdMeters)
        statureMeters = try container.decodeIfPresent(Double.self, forKey: .statureMeters)
        elbowFactor = try container.decodeIfPresent(Double.self, forKey: .elbowFactor) ?? 0.70
        chestFactor = try container.decode(Double.self, forKey: .chestFactor)
        eyeDropMeters = try container.decode(Double.self, forKey: .eyeDropMeters)
        cabMeters = try container.decode(Double.self, forKey: .cabMeters)
        groundHeightMeters = try container.decodeIfPresent(Double.self, forKey: .groundHeightMeters)
        tiltRadians = try container.decodeIfPresent(Double.self, forKey: .tiltRadians)
        eyeDistanceMeters = try container.decodeIfPresent(Double.self, forKey: .eyeDistanceMeters)
        distanceMeasured = try container.decodeIfPresent(Bool.self, forKey: .distanceMeasured)
        antennaAlongUpMeters = try container.decodeIfPresent(Double.self, forKey: .antennaAlongUpMeters)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(style, forKey: .style)
        try container.encode(offsetMeters, forKey: .offsetMeters)
        try container.encode(holdMeters, forKey: .holdMeters)
        try container.encodeIfPresent(statureMeters, forKey: .statureMeters)
        try container.encode(elbowFactor, forKey: .elbowFactor)
        try container.encode(chestFactor, forKey: .chestFactor)
        try container.encode(eyeDropMeters, forKey: .eyeDropMeters)
        try container.encode(cabMeters, forKey: .cabMeters)
        try container.encodeIfPresent(groundHeightMeters, forKey: .groundHeightMeters)
        try container.encodeIfPresent(tiltRadians, forKey: .tiltRadians)
        try container.encodeIfPresent(eyeDistanceMeters, forKey: .eyeDistanceMeters)
        try container.encodeIfPresent(distanceMeasured, forKey: .distanceMeasured)
        try container.encodeIfPresent(antennaAlongUpMeters, forKey: .antennaAlongUpMeters)
    }

    private enum CodingKeys: String, CodingKey {
        case style, offsetMeters, holdMeters, statureMeters
        case elbowFactor, chestFactor, eyeDropMeters, cabMeters, groundHeightMeters
        case tiltRadians, eyeDistanceMeters, distanceMeasured, antennaAlongUpMeters
    }

    public var screenLabel: String { StatureMath.screenLabel(offsetMeters: offsetMeters) }

    public var sightSample: SightSample? {
        guard let tiltRadians, let eyeDistanceMeters, let antennaAlongUpMeters else { return nil }
        return SightSample(
            tiltRadians: tiltRadians,
            eyeDistanceMeters: eyeDistanceMeters,
            distanceMeasured: distanceMeasured ?? false,
            antennaAlongUpMeters: antennaAlongUpMeters
        )
    }

    public var sightNote: String? {
        guard style == .sight, let tiltRadians, let eyeDistanceMeters, let antennaAlongUpMeters else { return nil }
        let source = distanceMeasured == true ? "" : "（既定）"
        return "傾き \(StatureMath.degreeText(tiltRadians))°、目までの距離 \(StatureMath.factorText(eyeDistanceMeters))m\(source)、アンテナ差 \(StatureMath.factorText(antennaAlongUpMeters))m"
    }
}

/// 観測を確定した瞬間の、画面の角度。
public struct SightSample: Equatable, Sendable {
    public static let defaultEyeDistance = 0.35
    public static let minimumEyeDistance = 0.15
    public static let maximumEyeDistance = 1.0

    public var tiltRadians: Double
    public var eyeDistanceMeters: Double
    public var distanceMeasured: Bool
    public var antennaAlongUpMeters: Double

    public init(tiltRadians: Double, eyeDistanceMeters: Double, distanceMeasured: Bool, antennaAlongUpMeters: Double) {
        self.tiltRadians = tiltRadians
        self.eyeDistanceMeters = eyeDistanceMeters
        self.distanceMeasured = distanceMeasured
        self.antennaAlongUpMeters = antennaAlongUpMeters
    }

    /// 距離が無い、または 15cm 未満か 1m を超えるときは 35cm。
    public static func resolved(tiltRadians: Double, measuredDistance: Double?, antennaAlongUpMeters: Double) -> SightSample? {
        guard tiltRadians.isFinite, antennaAlongUpMeters.isFinite else { return nil }
        let measured = measuredDistance.flatMap { distance -> Double? in
            guard distance.isFinite, distance >= minimumEyeDistance, distance <= maximumEyeDistance else { return nil }
            return distance
        }
        return SightSample(
            tiltRadians: tiltRadians,
            eyeDistanceMeters: measured ?? defaultEyeDistance,
            distanceMeasured: measured != nil,
            antennaAlongUpMeters: antennaAlongUpMeters
        )
    }
}

/// 機種ごとの、端末中心から GNSS アンテナまでの portrait 上方向。上端から 15mm と仮定し、表に無い機種は 0.060m。実機のアンテナ位置は未確認。
public enum AntennaCatalog {
    public static let insetFromTopMeters = 0.015
    public static let unknownAlongUpMeters = 0.060

    public static func alongUpMeters(model: String) -> Double {
        guard let height = bodyHeightMeters[model] else { return unknownAlongUpMeters }
        return height / 2 - insetFromTopMeters
    }

    /// Apple 公表の本体高さ（m）。識別子は hw.machine。
    static let bodyHeightMeters: [String: Double] = [
        "iPhone10,3": 0.1436, "iPhone10,6": 0.1436,
        "iPhone11,2": 0.1436, "iPhone11,4": 0.1575, "iPhone11,6": 0.1575, "iPhone11,8": 0.1509,
        "iPhone12,1": 0.1509, "iPhone12,3": 0.1440, "iPhone12,5": 0.1580, "iPhone12,8": 0.1384,
        "iPhone13,1": 0.1315, "iPhone13,2": 0.1467, "iPhone13,3": 0.1467, "iPhone13,4": 0.1608,
        "iPhone14,2": 0.1467, "iPhone14,3": 0.1608, "iPhone14,4": 0.1315, "iPhone14,5": 0.1467,
        "iPhone14,6": 0.1384, "iPhone14,7": 0.1467, "iPhone14,8": 0.1608,
        "iPhone15,2": 0.1475, "iPhone15,3": 0.1607, "iPhone15,4": 0.1476, "iPhone15,5": 0.1609,
        "iPhone16,1": 0.1466, "iPhone16,2": 0.1599,
        "iPhone17,1": 0.1496, "iPhone17,2": 0.1630, "iPhone17,3": 0.1476, "iPhone17,4": 0.1609, "iPhone17,5": 0.1467,
        "iPhone18,1": 0.1500, "iPhone18,2": 0.1634, "iPhone18,3": 0.1496, "iPhone18,4": 0.1562, "iPhone18,5": 0.1467
    ]
}

/// 既知の楕円体高で1回観測した、その人の持ち高さ。
public struct HoldCalibration: Equatable, Sendable {
    public var deviceHeightMeters: Double
    public var knownGroundMeters: Double
    public var holdMeters: Double
    public var elbowFactor: Double

    public init(deviceHeightMeters: Double, knownGroundMeters: Double, holdMeters: Double, elbowFactor: Double) {
        self.deviceHeightMeters = deviceHeightMeters
        self.knownGroundMeters = knownGroundMeters
        self.holdMeters = holdMeters
        self.elbowFactor = elbowFactor
    }
}

public enum StatureMath {
    /// 段階0かつ iPhone 単体のときだけ。
    public static func applies(stage: PositionStage, receiver: ReceiverKind) -> Bool {
        stage == .iphone && receiver == .iphoneGPS
    }

    /// 画面の「身長補正 −1.23m」。符号は常に引き算。
    public static func screenLabel(offsetMeters: Double) -> String {
        "身長補正 −\(factorText(abs(offsetMeters)))m"
    }

    public static func factorText(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public static func degreeText(_ radians: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), radians * 180 / .pi)
    }

    /// CoreMotion の pitch。0 は画面を上に向けて水平、+π/2 は端末の上が真上。θ は鉛直からの後傾。
    public static func tiltFromVertical(pitchRadians: Double) -> Double? {
        guard pitchRadians.isFinite else { return nil }
        return (.pi / 2) - pitchRadians
    }

    /// 目の高さから、距離と後傾とアンテナ差で、GNSS アンテナの地面からの高さ。
    public static func holdMeters(eyeHeight: Double, sight: SightSample) -> Double? {
        guard eyeHeight.isFinite, sight.tiltRadians.isFinite, sight.eyeDistanceMeters.isFinite, sight.antennaAlongUpMeters.isFinite else {
            return nil
        }
        let center = eyeHeight - sight.eyeDistanceMeters * GeoMath.sine(sight.tiltRadians)
        let antenna = center + sight.antennaAlongUpMeters * GeoMath.cosine(sight.tiltRadians)
        guard antenna.isFinite else { return nil }
        return max(0, antenna)
    }

    /// 端末を地面からどれだけ上げているか。身長が要る持ち方で未登録なら nil。
    public static func holdMeters(profile: StatureProfile, sight: SightSample? = nil) -> Double? {
        switch profile.style {
        case .sight:
            guard let eye = eyeHeight(profile), let sight else { return nil }
            return holdMeters(eyeHeight: eye, sight: sight)
        case .elbow:
            guard let stature = usableStature(profile.statureMeters) else { return nil }
            return max(0, stature * profile.coefficients.elbowFactor)
        case .chest:
            guard let stature = usableStature(profile.statureMeters) else { return nil }
            return max(0, stature * profile.coefficients.chestFactor)
        case .eye:
            guard let stature = usableStature(profile.statureMeters) else { return nil }
            return max(0, stature - profile.coefficients.eyeDropMeters)
        case .ground:
            return 0
        case .cab:
            return max(0, profile.coefficients.cabMeters)
        case .manual:
            guard profile.manualMeters.isFinite, profile.manualMeters >= 0 else { return nil }
            return profile.manualMeters
        }
    }

    public static func correction(
        for profile: StatureProfile,
        stage: PositionStage,
        receiver: ReceiverKind,
        sight: SightSample? = nil
    ) -> StatureRecord? {
        guard applies(stage: stage, receiver: receiver) else { return nil }
        return record(profile: profile, deviceHeight: nil, sight: sight)
    }

    public static func record(profile: StatureProfile, deviceHeight: Double?, sight: SightSample? = nil) -> StatureRecord? {
        guard let hold = holdMeters(profile: profile, sight: sight) else { return nil }
        let offset = -hold
        let ground = deviceHeight.flatMap { height -> Double? in
            guard height.isFinite else { return nil }
            return height + offset
        }
        let automatic = profile.style == .sight ? sight : nil
        return StatureRecord(
            style: profile.style,
            offsetMeters: offset,
            holdMeters: hold,
            statureMeters: profile.statureMeters,
            elbowFactor: profile.coefficients.elbowFactor,
            chestFactor: profile.coefficients.chestFactor,
            eyeDropMeters: profile.coefficients.eyeDropMeters,
            cabMeters: profile.coefficients.cabMeters,
            groundHeightMeters: ground,
            tiltRadians: automatic?.tiltRadians,
            eyeDistanceMeters: automatic?.eyeDistanceMeters,
            distanceMeasured: automatic?.distanceMeasured,
            antennaAlongUpMeters: automatic?.antennaAlongUpMeters
        )
    }

    public static func notice(
        profile: StatureProfile,
        stage: PositionStage,
        receiver: ReceiverKind,
        sight: SightSample? = nil
    ) -> String? {
        guard applies(stage: stage, receiver: receiver) else { return nil }
        if profile.style == .sight, eyeHeight(profile) != nil, sight == nil {
            return "傾きを待っています"
        }
        if let record = correction(for: profile, stage: stage, receiver: receiver, sight: sight) {
            return record.screenLabel
        }
        return "身長が未登録です"
    }

    public static func eyeHeight(_ profile: StatureProfile) -> Double? {
        guard let stature = usableStature(profile.statureMeters) else { return nil }
        return max(0, stature - profile.coefficients.eyeDropMeters)
    }

    /// 既知の楕円体高で1回観測し、肘より上の係数をその人の持ち高さに合わせる。
    public static func calibrate(deviceHeight: Double, knownGround: Double, stature: Double) -> HoldCalibration? {
        guard deviceHeight.isFinite, knownGround.isFinite else { return nil }
        guard let stature = usableStature(stature), stature <= 3 else { return nil }
        let hold = deviceHeight - knownGround
        guard hold.isFinite, hold >= 0, hold <= 3 else { return nil }
        let factor = hold / stature
        guard factor.isFinite, factor >= 0, factor <= 1.5 else { return nil }
        return HoldCalibration(
            deviceHeightMeters: deviceHeight,
            knownGroundMeters: knownGround,
            holdMeters: hold,
            elbowFactor: factor
        )
    }

    public static func applying(_ calibration: HoldCalibration, to profile: StatureProfile) -> StatureProfile {
        var copy = profile
        copy.style = .elbow
        copy.coefficients.elbowFactor = calibration.elbowFactor
        return copy
    }

    private static func usableStature(_ meters: Double?) -> Double? {
        guard let meters, meters.isFinite, meters > 0 else { return nil }
        return meters
    }
}

extension FieldObservation {
    /// 端末の楕円体高は残す。地盤高は条件記録へ足す。段階0の iPhone 以外はそのまま。
    public func applying(_ profile: StatureProfile) -> FieldObservation {
        let stage = condition?.stage ?? captured.stage
        let receiver = condition?.receiver ?? captured.receiver
        guard StatureMath.applies(stage: stage, receiver: receiver) else { return self }
        let sight = condition?.stature?.sightSample
        if profile.style == .sight, sight == nil { return self }
        guard let record = StatureMath.record(profile: profile, deviceHeight: captured.ellipsoidalHeightMeters, sight: sight) else {
            guard condition?.stature != nil else { return self }
            var cleared = self
            cleared.condition?.stature = nil
            return cleared
        }
        var copy = self
        if copy.condition == nil {
            copy.condition = ObservationCondition.snapshot(
                position: captured,
                stage: stage,
                durationSeconds: fixDurationSeconds,
                epochCount: nil
            )
        }
        copy.condition?.stature = record
        return copy
    }
}
