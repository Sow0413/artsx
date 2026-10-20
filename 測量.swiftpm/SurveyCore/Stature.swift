import Foundation

/// iPhone を持つ高さ。外部 GNSS のポール高とは別。
public enum HoldStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case elbow
    case chest
    case eye
    case ground
    case cab
    case manual

    public var title: String {
        switch self {
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
        style: HoldStyle = .elbow,
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

    public init(
        style: HoldStyle,
        offsetMeters: Double,
        holdMeters: Double,
        statureMeters: Double?,
        elbowFactor: Double = 0.70,
        chestFactor: Double,
        eyeDropMeters: Double,
        cabMeters: Double,
        groundHeightMeters: Double?
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
    }

    private enum CodingKeys: String, CodingKey {
        case style, offsetMeters, holdMeters, statureMeters
        case elbowFactor, chestFactor, eyeDropMeters, cabMeters, groundHeightMeters
    }

    public var screenLabel: String { StatureMath.screenLabel(offsetMeters: offsetMeters) }
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

    /// 端末を地面からどれだけ上げているか。身長が要る持ち方で未登録なら nil。
    public static func holdMeters(profile: StatureProfile) -> Double? {
        switch profile.style {
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

    public static func correction(for profile: StatureProfile, stage: PositionStage, receiver: ReceiverKind) -> StatureRecord? {
        guard applies(stage: stage, receiver: receiver) else { return nil }
        return record(profile: profile, deviceHeight: nil)
    }

    public static func record(profile: StatureProfile, deviceHeight: Double?) -> StatureRecord? {
        guard let hold = holdMeters(profile: profile) else { return nil }
        let offset = -hold
        let ground = deviceHeight.flatMap { height -> Double? in
            guard height.isFinite else { return nil }
            return height + offset
        }
        return StatureRecord(
            style: profile.style,
            offsetMeters: offset,
            holdMeters: hold,
            statureMeters: profile.statureMeters,
            elbowFactor: profile.coefficients.elbowFactor,
            chestFactor: profile.coefficients.chestFactor,
            eyeDropMeters: profile.coefficients.eyeDropMeters,
            cabMeters: profile.coefficients.cabMeters,
            groundHeightMeters: ground
        )
    }

    public static func notice(profile: StatureProfile, stage: PositionStage, receiver: ReceiverKind) -> String? {
        guard applies(stage: stage, receiver: receiver) else { return nil }
        if let record = correction(for: profile, stage: stage, receiver: receiver) {
            return record.screenLabel
        }
        return "身長が未登録です"
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
        guard let record = StatureMath.record(profile: profile, deviceHeight: captured.ellipsoidalHeightMeters) else {
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
