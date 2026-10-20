import Foundation

/// 画面の色。緑は外部受信機の RTK Fix だけ。段階0は琥珀か灰色。
public enum AccuracyTone: String, Sendable, Codable, Equatable {
    case grey
    case amber
    case green
}

public struct AccuracyBadgeModel: Equatable, Sendable {
    public var tone: AccuracyTone
    public var text: String
    public var accessibilityText: String
    /// 測設の合否を緑にしてよいか。バッジが緑のときだけ真。
    public var isStakeoutGrade: Bool

    public init(tone: AccuracyTone, text: String, accessibilityText: String, isStakeoutGrade: Bool) {
        self.tone = tone
        self.text = text
        self.accessibilityText = accessibilityText
        self.isStakeoutGrade = isStakeoutGrade
    }
}

public enum AccuracyFormat {
    /// 1m 以上はメートル、未満はセンチ。`approximate` のとき「約」を付ける。
    public static func label(meters: Double, approximate: Bool) -> String {
        guard meters.isFinite else { return approximate ? "約—m" : "—m" }
        let value = abs(meters)
        let prefix = approximate ? "約" : ""
        if value >= 1 {
            let rounded = Int(value.rounded(.toNearestOrAwayFromZero))
            return "\(prefix)\(rounded)m"
        }
        var centimeters = Int((value * 100).rounded(.toNearestOrAwayFromZero))
        if centimeters == 0, value > 0 {
            centimeters = 1
        }
        return "\(prefix)\(centimeters)cm"
    }
}

public enum AccuracyPolicy {
    public static func tone(for position: GeodeticPosition) -> AccuracyTone {
        guard position.isPlottable, position.hasValidHorizontalAccuracy else { return .grey }
        return position.isTrustedRTKFix ? .green : .amber
    }

    public static func badge(for reading: PositionReading) -> AccuracyBadgeModel {
        switch reading.availability {
        case .denied:
            return idle(text: "位置情報を許可してください")
        case .unavailable:
            return idle(text: "位置を取得できません")
        case .waiting, .available:
            guard let position = reading.position, position.isPlottable else {
                return idle(text: "位置を取得中")
            }
            guard position.hasValidHorizontalAccuracy else {
                return AccuracyBadgeModel(
                    tone: .grey,
                    text: "精度不明",
                    accessibilityText: "段階\(position.stage.rawValue)。精度不明",
                    isStakeoutGrade: false
                )
            }
            if position.isTrustedRTKFix {
                let text = "RTK Fix \(AccuracyFormat.label(meters: position.horizontalAccuracyMeters, approximate: false))"
                return AccuracyBadgeModel(
                    tone: .green,
                    text: text,
                    accessibilityText: "段階\(position.stage.rawValue)。\(text)",
                    isStakeoutGrade: true
                )
            }
            let text = approximateTitle(for: position)
            return AccuracyBadgeModel(
                tone: .amber,
                text: text,
                accessibilityText: "段階\(position.stage.rawValue)。\(text)",
                isStakeoutGrade: false
            )
        }
    }

    private static func idle(text: String) -> AccuracyBadgeModel {
        AccuracyBadgeModel(
            tone: .grey,
            text: text,
            accessibilityText: "段階なし。\(text)",
            isStakeoutGrade: false
        )
    }

    private static func approximateTitle(for position: GeodeticPosition) -> String {
        let magnitude = AccuracyFormat.label(meters: position.horizontalAccuracyMeters, approximate: true)
        if position.receiver == .iphoneGPS || position.stage == .iphone {
            return "iPhone GPS \(magnitude)"
        }
        if position.fixQuality == .float, position.stage == .rtk || position.stage == .hybrid {
            return "RTK Float \(magnitude)"
        }
        if position.fixQuality == .dgps {
            return "DGPS \(magnitude)"
        }
        if position.stage == .clas || position.fixQuality == .clas {
            return "CLAS \(magnitude)"
        }
        if position.stage == .hybrid {
            return "併用 \(magnitude)"
        }
        if position.fixQuality == .standalone, position.stage == .rtk {
            return "RTK 単独 \(magnitude)"
        }
        return "RTK \(magnitude)"
    }
}
