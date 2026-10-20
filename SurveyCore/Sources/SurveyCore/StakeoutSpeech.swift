import Foundation

/// 位置出しの声。既定は方向だけ。数値も読むかは端末の中だけ。
public enum StakeoutSpeechStyle: String, Codable, Sendable, Equatable, CaseIterable {
    case direction
    case numbers

    public var label: String {
        switch self {
        case .direction: return "方向だけ"
        case .numbers: return "数値も読む"
        }
    }
}

public struct StakeoutSpeechPreference: Codable, Sendable, Equatable {
    public static let storageKey = "survey.stakeout.speech"
    public var style: StakeoutSpeechStyle

    public init(style: StakeoutSpeechStyle = .direction) {
        self.style = style
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    public static func load(from defaults: UserDefaults = .standard) -> StakeoutSpeechPreference {
        guard let data = defaults.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode(StakeoutSpeechPreference.self, from: data) else {
            return StakeoutSpeechPreference()
        }
        return stored
    }
}

public struct StakeoutUtterance: Equatable, Sendable {
    public var speech: String
    /// 方向が同じなら、歩数が変わっても話さない。
    public var directionKey: String
    public var mode: ARGuidanceMode

    public init(speech: String, directionKey: String, mode: ARGuidanceMode) {
        self.speech = speech
        self.directionKey = directionKey
        self.mode = mode
    }
}

/// 画面を見ている人への声。画面の上を前にする。重機の進行方向は使わない。
public enum StakeoutSpeech {
    /// この距離以内は「そこです」。
    public static let arrivedMeters = 0.05

    /// 端末の方位。画面上方。進行方向は前にしない。
    public static func screenForward(headingDegrees: Double?) -> Double? {
        guard let headingDegrees, headingDegrees.isFinite else { return nil }
        var degrees = headingDegrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    /// 「右前」「後ろ」。画面の8方位。
    public static func word(relativeDegrees: Double) -> String {
        switch ThreatBearing.sector(relativeDegrees: relativeDegrees) {
        case "前": return "前"
        case "うしろ": return "後ろ"
        case "右まえ": return "右前"
        case "左まえ": return "左前"
        case "右うしろ": return "右後ろ"
        case "左うしろ": return "左後ろ"
        case "右": return "右"
        case "左": return "左"
        default: return "前"
        }
    }

    public static func utterance(
        distanceMeters: Double,
        azimuthDegrees: Double,
        headingDegrees: Double?,
        style: StakeoutSpeechStyle,
        strideMeters: Double?,
        unit: StakeoutUnit,
        current: ARGuidanceMode,
        switchMeters: Double,
        precision: StakeoutPrecision = .meters
    ) -> StakeoutUtterance? {
        guard distanceMeters.isFinite, distanceMeters >= 0, azimuthDegrees.isFinite else { return nil }
        guard let heading = screenForward(headingDegrees: headingDegrees) else { return nil }
        let mode = ARStakeoutMath.mode(distanceMeters: distanceMeters, current: current, switchMeters: switchMeters)
        if distanceMeters <= arrivedMeters {
            return StakeoutUtterance(speech: "そこです", directionKey: "そこです", mode: mode)
        }
        let relative = ThreatBearing.relative(targetAzimuthDegrees: azimuthDegrees, facingDegrees: heading)
        let word = word(relativeDegrees: relative)
        let close = mode == .numeric
        let key = close ? "もう少し\(word)" : "\(word)です"
        var speech = key
        if style == .numbers, let number = numberText(
            distanceMeters: distanceMeters,
            azimuthDegrees: azimuthDegrees,
            headingDegrees: heading,
            strideMeters: strideMeters,
            unit: unit,
            close: close,
            precision: precision
        ) {
            speech = "\(key)、\(number)"
        }
        return StakeoutUtterance(speech: speech, directionKey: key, mode: mode)
    }

    private static func numberText(
        distanceMeters: Double,
        azimuthDegrees: Double,
        headingDegrees: Double,
        strideMeters: Double?,
        unit: StakeoutUnit,
        close: Bool,
        precision: StakeoutPrecision
    ) -> String? {
        if close {
            guard let axes = StakeoutPace.axes(
                distanceMeters: distanceMeters,
                azimuthDegrees: azimuthDegrees,
                facingDegrees: headingDegrees
            ) else { return nil }
            let cm = max(abs(axes.alongCentimeters), abs(axes.acrossCentimeters))
            guard cm >= 1 else { return nil }
            return "\(cm)cm"
        }
        if unit == .meters || strideMeters == nil || (strideMeters ?? 0) <= 0 {
            return StakeoutText.meters(distanceMeters, precision: precision)
        }
        let stride = strideMeters ?? 1
        let steps = max(1, Int((distanceMeters / stride).rounded()))
        return "\(steps)歩"
    }
}
