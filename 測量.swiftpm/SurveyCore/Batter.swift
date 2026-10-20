import Foundation

/// 丁張で読む高さ。ポール先端か、十字線が水平のときの器械高。
public enum BatterSource: String, Codable, Sendable, Equatable {
    case poleTip
    case crosshair
    case relative

    public var label: String {
        switch self {
        case .poleTip: return "ポール先端"
        case .crosshair: return "十字線"
        case .relative: return "相対"
        }
    }
}

/// 測定高 − 目標高。正は高すぎるので下げる。
public enum BatterMove: String, Sendable, Equatable {
    case raise
    case lower
    case within
}

/// ゲージの色。上げは青、下げは赤、許容内は緑。
public enum BatterInk: String, Sendable, Equatable {
    case blue
    case red
    case green
}

/// 残した丁張。高さは決めた測定高。身長補正は掛けない。
public struct BatterRecord: Equatable, Sendable {
    public var heightMeters: Double
    public var kind: String
    public var stage: PositionStage
    public var receiver: ReceiverKind
    public var guide: Bool

    public init(heightMeters: Double, kind: String, stage: PositionStage, receiver: ReceiverKind, guide: Bool) {
        self.heightMeters = heightMeters
        self.kind = kind
        self.stage = stage
        self.receiver = receiver
        self.guide = guide
    }
}

/// 計画高からのオフセット、勾配、許容。図面の計画高とは別の置き場。
public struct BatterSettings: Codable, Sendable, Equatable {
    public static let storageKey = "survey.batter"

    public var offsetMeters: Double
    public var slope: Double
    /// 北から時計回り。無いときは勾配を足さない。
    public var slopeAzimuthDegrees: Double?
    public var toleranceMeters: Double
    public var source: BatterSource

    public init(
        offsetMeters: Double = 0,
        slope: Double = 0,
        slopeAzimuthDegrees: Double? = nil,
        toleranceMeters: Double = BatterMath.defaultToleranceMeters,
        source: BatterSource = .poleTip
    ) {
        self.offsetMeters = offsetMeters
        self.slope = slope
        self.slopeAzimuthDegrees = slopeAzimuthDegrees
        self.toleranceMeters = toleranceMeters
        self.source = source
    }

    public func sanitized() -> BatterSettings {
        var copy = self
        copy.offsetMeters = copy.offsetMeters.isFinite ? copy.offsetMeters : 0
        copy.slope = copy.slope.isFinite ? copy.slope : 0
        if let azimuth = copy.slopeAzimuthDegrees, !azimuth.isFinite {
            copy.slopeAzimuthDegrees = nil
        }
        if !copy.toleranceMeters.isFinite || copy.toleranceMeters < 0 {
            copy.toleranceMeters = BatterMath.defaultToleranceMeters
        }
        copy.toleranceMeters = min(copy.toleranceMeters, 1)
        return copy
    }

    public func save(to defaults: UserDefaults = .standard) {
        let clean = sanitized()
        guard let data = try? JSONEncoder().encode(clean) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> BatterSettings {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(BatterSettings.self, from: data) else {
            return BatterSettings()
        }
        return stored.sanitized()
    }

    private enum CodingKeys: String, CodingKey {
        case offsetMeters, slope, slopeAzimuthDegrees, toleranceMeters, source
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        offsetMeters = try container.decodeIfPresent(Double.self, forKey: .offsetMeters) ?? 0
        slope = try container.decodeIfPresent(Double.self, forKey: .slope) ?? 0
        slopeAzimuthDegrees = try container.decodeIfPresent(Double.self, forKey: .slopeAzimuthDegrees)
        toleranceMeters = try container.decodeIfPresent(Double.self, forKey: .toleranceMeters) ?? BatterMath.defaultToleranceMeters
        source = try container.decodeIfPresent(BatterSource.self, forKey: .source) ?? .poleTip
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(offsetMeters, forKey: .offsetMeters)
        try container.encode(slope, forKey: .slope)
        try container.encodeIfPresent(slopeAzimuthDegrees, forKey: .slopeAzimuthDegrees)
        try container.encode(toleranceMeters, forKey: .toleranceMeters)
        try container.encode(source, forKey: .source)
    }
}

public enum BatterMath {
    public static let kind = "丁張"
    public static let guideWord = "目安"
    /// 作業の「丁張・測設」1cm とは別。ゲージの既定は ±5mm。
    public static let defaultToleranceMeters = 0.005
    public static let nearSpeechSeconds = 0.45
    public static let farSpeechSeconds = 4.0
    public static let speechSpanMeters = 1.0
    /// ゲージの振り幅。これより大きい差は端に止める。数字は実数のまま。
    public static let gaugeSpanMeters = 0.20

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    /// 目標 = 計画高 + オフセット + 勾配 × 向き方向の距離。
    public static func targetHeight(design: Double, offset: Double, slope: Double, alongMeters: Double) -> Double? {
        guard design.isFinite, offset.isFinite, slope.isFinite, alongMeters.isFinite else { return nil }
        let height = design + offset + slope * alongMeters
        return height.isFinite ? height : nil
    }

    /// 受信機の楕円体高からポール高を引いた先端。ポール高が無いときは nil。
    public static func poleTip(deviceEllipsoidal: Double, poleMeters: Double?) -> Double? {
        guard let poleMeters, deviceEllipsoidal.isFinite, poleMeters.isFinite, poleMeters > 0, poleMeters <= 10 else { return nil }
        let tip = deviceEllipsoidal - poleMeters
        return tip.isFinite ? tip : nil
    }

    /// 十字線が水平のときの高さ。器械高 = 地盤高 + 目の高さ。ポール高は使わない。
    public static func crosshairLine(ground: Double, eye: Double) -> Double? {
        guard ground.isFinite, eye.isFinite, eye > 0, eye <= 3 else { return nil }
        let line = ground + eye
        return line.isFinite ? line : nil
    }

    /// 傾きが水平（±0.1°）と分かっているときだけ、十字線を高さに使う。
    public static func acceptsCrosshair(isLevel: Bool?) -> Bool {
        isLevel == true
    }

    public static func delta(measured: Double, target: Double) -> Double? {
        guard measured.isFinite, target.isFinite else { return nil }
        let value = measured - target
        return value.isFinite ? value : nil
    }

    /// 正の差は高すぎるので下げ。許容は両側を含む。
    public static func move(deltaMeters: Double, toleranceMeters: Double) -> BatterMove? {
        guard deltaMeters.isFinite, toleranceMeters.isFinite, toleranceMeters >= 0 else { return nil }
        if abs(deltaMeters) <= toleranceMeters + 1e-12 { return .within }
        return deltaMeters > 0 ? .lower : .raise
    }

    public static func ink(_ move: BatterMove) -> BatterInk {
        switch move {
        case .raise: return .blue
        case .lower: return .red
        case .within: return .green
        }
    }

    public static func arrow(_ move: BatterMove) -> String {
        switch move {
        case .raise: return "↑"
        case .lower: return "↓"
        case .within: return "●"
        }
    }

    public static func phrase(deltaMeters: Double, toleranceMeters: Double) -> String? {
        guard let move = move(deltaMeters: deltaMeters, toleranceMeters: toleranceMeters) else { return nil }
        switch move {
        case .within: return "許容内"
        case .raise: return "あと\(amountText(deltaMeters))上げ"
        case .lower: return "あと\(amountText(deltaMeters))下げ"
        }
    }

    public static func amountText(_ meters: Double) -> String {
        let value = abs(meters)
        guard value.isFinite else { return "—" }
        if value >= 1 {
            return String(format: "%.2fm", locale: posix, value)
        }
        if value >= 0.01 {
            return "\(Int((value * 100).rounded()))cm"
        }
        return "\(Int((value * 1000).rounded()))mm"
    }

    /// 残差が小さいほど短い。0 で 0.45 秒、1m 以上で 4 秒。
    public static func speechInterval(remainingMeters: Double) -> TimeInterval {
        guard remainingMeters.isFinite else { return farSpeechSeconds }
        let error = min(max(abs(remainingMeters), 0), speechSpanMeters)
        return nearSpeechSeconds + (farSpeechSeconds - nearSpeechSeconds) * (error / speechSpanMeters)
    }

    /// 0 が下、1 が上。正の差（高すぎ）は上へ。
    public static func gaugeFraction(deltaMeters: Double, spanMeters: Double = gaugeSpanMeters) -> Double {
        guard deltaMeters.isFinite, spanMeters.isFinite, spanMeters > 0 else { return 0.5 }
        let clamped = min(max(deltaMeters / spanMeters, -1), 1)
        return 0.5 + 0.5 * clamped
    }

    /// 目標点から今の位置へ、勾配の方位に沿った符号付き距離。
    public static func alongMeters(
        hereLatitude: Double,
        hereLongitude: Double,
        originLatitude: Double,
        originLongitude: Double,
        azimuthDegrees: Double
    ) -> Double? {
        guard azimuthDegrees.isFinite,
              let inverse = GRS80Geodesic.inverse(
                latitude1: originLatitude,
                longitude1: originLongitude,
                latitude2: hereLatitude,
                longitude2: hereLongitude
              ) else { return nil }
        let turn = GeoMath.radians(fromDegrees: inverse.azimuthDegrees - azimuthDegrees)
        let along = inverse.distanceMeters * GeoMath.cosine(turn)
        return along.isFinite ? along : nil
    }

    public static func plan(
        hereLatitude: Double,
        hereLongitude: Double,
        targetLatitude: Double,
        targetLongitude: Double
    ) -> (distanceMeters: Double, azimuthDegrees: Double)? {
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: hereLatitude,
            longitude1: hereLongitude,
            latitude2: targetLatitude,
            longitude2: targetLongitude
        ) else { return nil }
        return (inverse.distanceMeters, inverse.azimuthDegrees)
    }

    public static func planText(distanceMeters: Double?, azimuthDegrees: Double?, precision: StakeoutPrecision) -> String {
        guard let distanceMeters, let azimuthDegrees,
              distanceMeters.isFinite, azimuthDegrees.isFinite, distanceMeters >= 0 else {
            return "平面の目標が無いので、高さだけ出します。"
        }
        let azimuth = String(format: "%.1f", locale: posix, azimuthDegrees)
        return "現在地から \(StakeoutText.meters(distanceMeters, precision: precision))、北から時計回り \(azimuth)°"
    }

    public static func targetNote(design: Double, offset: Double, slope: Double, alongMeters: Double) -> String? {
        guard let target = targetHeight(design: design, offset: offset, slope: slope, alongMeters: alongMeters) else { return nil }
        return String(
            format: "目標 %.3fm（計画 %.3f、オフセット %+.3f、勾配 %+.3f）",
            locale: posix,
            target,
            design,
            offset,
            slope * alongMeters
        )
    }

    /// iPhone 単体（段階0）だけ目安。外部受信機が付いていれば、段階がまだ0でも目安とはしない。
    public static func showsGuide(stage: PositionStage, receiver: ReceiverKind) -> Bool {
        receiver == .iphoneGPS && stage == .iphone
    }

    public static func record(measured: Double, stage: PositionStage, receiver: ReceiverKind) -> BatterRecord? {
        guard measured.isFinite else { return nil }
        return BatterRecord(
            heightMeters: measured,
            kind: kind,
            stage: stage,
            receiver: receiver,
            guide: showsGuide(stage: stage, receiver: receiver)
        )
    }
}
