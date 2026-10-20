import Foundation

/// 位置出しの案内を、歩数で出すかメートルで出すか。既定は歩数。
public enum StakeoutUnit: String, Codable, Sendable, Equatable, CaseIterable {
    case steps
    case meters

    public var label: String {
        switch self {
        case .steps: return "歩数"
        case .meters: return "メートル"
        }
    }
}

/// 端末の中だけ。位置の共有には出さない。
public struct StakeoutPacePreference: Codable, Sendable, Equatable {
    public static let storageKey = "survey.stakeout.unit"
    public var unit: StakeoutUnit

    public init(unit: StakeoutUnit = .steps) {
        self.unit = unit
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> StakeoutPacePreference {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StakeoutPacePreference.self, from: data) else {
            return StakeoutPacePreference()
        }
        return stored
    }
}

public struct StakeoutPaceGuide: Equatable, Sendable {
    /// 画面の大きな文字と、読み上げる文。
    public var speech: String
    /// 近くに来たときの前後左右。遠いときは nil。
    public var detail: String?
    public var steps: Int?
    public var close: Bool

    public init(speech: String, detail: String?, steps: Int?, close: Bool) {
        self.speech = speech
        self.detail = detail
        self.steps = steps
        self.close = close
    }
}

/// 測設の目標までを、個人の歩幅と体の向きで案内する。重機の測点表示には使わない。
public enum StakeoutPace {
    /// これ未満はセンチ。ちょうどこの歩数は、まだ歩数。
    public static let closeSteps = 3.0

    private static var posix: Locale { Locale(identifier: "en_US_POSIX") }

    public static func guide(
        distanceMeters: Double,
        azimuthDegrees: Double,
        facingDegrees: Double?,
        strideMeters: Double?,
        unit: StakeoutUnit,
        precision: StakeoutPrecision = .meters
    ) -> StakeoutPaceGuide? {
        guard distanceMeters.isFinite, distanceMeters >= 0, azimuthDegrees.isFinite else { return nil }
        if unit == .meters || strideMeters == nil || (strideMeters ?? 0) <= 0 {
            var speech = meterSpeech(distanceMeters: distanceMeters, azimuthDegrees: azimuthDegrees, precision: precision)
            if unit == .steps {
                speech = "歩幅が無いので、メートルで出します。\(speech)"
            }
            return StakeoutPaceGuide(speech: speech, detail: nil, steps: nil, close: false)
        }
        let stride = strideMeters ?? 1
        let relative = facingDegrees.flatMap { facing -> Double? in
            guard facing.isFinite else { return nil }
            return ThreatBearing.relative(targetAzimuthDegrees: azimuthDegrees, facingDegrees: facing)
        }
        if distanceMeters / stride + 1e-9 < closeSteps {
            return closeGuide(distanceMeters: distanceMeters, relativeDegrees: relative)
        }
        let steps = max(1, Int((distanceMeters / stride).rounded()))
        guard let relative else {
            return StakeoutPaceGuide(
                speech: "\(steps)歩。向きが無いので、方向は出せません。",
                detail: nil,
                steps: steps,
                close: false
            )
        }
        let sector = ThreatBearing.sector(relativeDegrees: relative)
        return StakeoutPaceGuide(speech: "\(sector) \(steps)歩", detail: nil, steps: steps, close: false)
    }

    public static func meterSpeech(distanceMeters: Double, azimuthDegrees: Double, precision: StakeoutPrecision) -> String {
        let azimuth = String(format: "%.1f", locale: posix, azimuthDegrees)
        return "現在地から \(StakeoutText.meters(distanceMeters, precision: precision))、北から時計回り \(azimuth)°"
    }

    private static func closeGuide(distanceMeters: Double, relativeDegrees: Double?) -> StakeoutPaceGuide {
        if distanceMeters < 0.005 {
            return StakeoutPaceGuide(speech: "着きました", detail: nil, steps: 0, close: true)
        }
        guard let relativeDegrees else {
            let cm = centimeters(distanceMeters)
            return StakeoutPaceGuide(
                speech: "あと\(cm)cm。向きが無いので、方向は出せません。",
                detail: nil,
                steps: 0,
                close: true
            )
        }
        let radians = GeoMath.radians(fromDegrees: relativeDegrees)
        let along = distanceMeters * GeoMath.cosine(radians)
        let across = distanceMeters * GeoMath.sine(radians)
        let forward = component(along, positive: "前", negative: "うしろ")
        let sideways = component(across, positive: "右", negative: "左")
        let parts = [forward, sideways].compactMap { $0 }
        let detail = parts.isEmpty ? nil : parts.joined(separator: "　")
        let speech: String
        if abs(along) >= abs(across), let line = amount(along, positive: "前", negative: "うしろ") {
            speech = line
        } else if let line = amount(across, positive: "右", negative: "左") {
            speech = line
        } else {
            speech = "着きました"
        }
        return StakeoutPaceGuide(speech: speech, detail: detail, steps: 0, close: true)
    }

    /// 「あと35cm前」
    private static func amount(_ meters: Double, positive: String, negative: String) -> String? {
        let cm = centimeters(abs(meters))
        guard cm >= 1 else { return nil }
        let word = meters >= 0 ? positive : negative
        return "あと\(cm)cm\(word)"
    }

    /// 「前 35cm」。1cm 未満は出さない。
    private static func component(_ meters: Double, positive: String, negative: String) -> String? {
        let cm = centimeters(abs(meters))
        guard cm >= 1 else { return nil }
        let word = meters >= 0 ? positive : negative
        return "\(word) \(cm)cm"
    }

    private static func centimeters(_ meters: Double) -> Int {
        Int((abs(meters) * 100).rounded())
    }
}
