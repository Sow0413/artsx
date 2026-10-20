import Foundation

/// iPhone を持つ高さ。外部 GNSS のポール高とは別。
public enum HoldStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case chest
    case eye
    case ground
    case cab
    case manual

    public var title: String {
        switch self {
        case .chest: return "胸の前"
        case .eye: return "目の高さ"
        case .ground: return "地面に置く"
        case .cab: return "重機運転席"
        case .manual: return "手入力"
        }
    }
}

/// 胸の前は身長×係数、目の高さは身長から一定を引く、運転席は既存の 2m。
public struct StatureCoefficients: Codable, Sendable, Equatable {
    public static let standard = StatureCoefficients(chestFactor: 0.72, eyeDropMeters: 0.10, cabMeters: 2)

    public var chestFactor: Double
    public var eyeDropMeters: Double
    public var cabMeters: Double

    public init(chestFactor: Double, eyeDropMeters: Double, cabMeters: Double) {
        self.chestFactor = chestFactor
        self.eyeDropMeters = eyeDropMeters
        self.cabMeters = cabMeters
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
        style: HoldStyle = .chest,
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
    public var chestFactor: Double
    public var eyeDropMeters: Double
    public var cabMeters: Double
    public var groundHeightMeters: Double?

    public init(
        style: HoldStyle,
        offsetMeters: Double,
        holdMeters: Double,
        statureMeters: Double?,
        chestFactor: Double,
        eyeDropMeters: Double,
        cabMeters: Double,
        groundHeightMeters: Double?
    ) {
        self.style = style
        self.offsetMeters = offsetMeters
        self.holdMeters = holdMeters
        self.statureMeters = statureMeters
        self.chestFactor = chestFactor
        self.eyeDropMeters = eyeDropMeters
        self.cabMeters = cabMeters
        self.groundHeightMeters = groundHeightMeters
    }

    public var screenLabel: String { StatureMath.screenLabel(offsetMeters: offsetMeters) }
}

public enum StatureMath {
    /// 段階0かつ iPhone 単体のときだけ。
    public static func applies(stage: PositionStage, receiver: ReceiverKind) -> Bool {
        stage == .iphone && receiver == .iphoneGPS
    }

    /// 画面の「身長補正 −1.23m」。符号は常に引き算。
    public static func screenLabel(offsetMeters: Double) -> String {
        let body = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), abs(offsetMeters))
        return "身長補正 −\(body)m"
    }

    /// 端末を地面からどれだけ上げているか。身長が要る持ち方で未登録なら nil。
    public static func holdMeters(profile: StatureProfile) -> Double? {
        switch profile.style {
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
