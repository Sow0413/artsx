import Foundation

/// 作業の要求に対する色。緑は要求以内、黄は2倍以内、赤はそれより粗い。灰は位置が無い。
public enum AccuracyTone: String, Sendable, Codable, Equatable {
    case grey
    case amber
    case yellow
    case red
    case green
}

public struct AccuracyBadgeModel: Equatable, Sendable {
    public var tone: AccuracyTone
    public var text: String
    public var accessibilityText: String
    /// 外部の RTK Fix で、かつ今の作業の要求を満たすときだけ真。
    public var isStakeoutGrade: Bool
    /// 足りない軸と、届く手段。足りていれば空。
    public var guidance: String
    /// 楽観的な機器に係数をかけたときの注記。かけていなければ空。
    public var caution: String

    public init(
        tone: AccuracyTone,
        text: String,
        accessibilityText: String,
        isStakeoutGrade: Bool,
        guidance: String = "",
        caution: String = ""
    ) {
        self.tone = tone
        self.text = text
        self.accessibilityText = accessibilityText
        self.isStakeoutGrade = isStakeoutGrade
        self.guidance = guidance
        self.caution = caution
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
    public static func tone(
        for position: GeodeticPosition,
        work: WorkRequirement = WorkCatalog.provisional.selected,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor
    ) -> AccuracyTone {
        judgment(for: position, work: work, trust: trust, safetyFactor: safetyFactor).tone
    }

    public static func badge(
        for reading: PositionReading,
        work: WorkRequirement = WorkCatalog.provisional.selected,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor
    ) -> AccuracyBadgeModel {
        switch reading.availability {
        case .denied:
            return idle(text: "位置情報を許可してください", work: work)
        case .unavailable:
            return idle(text: "位置を取得できません", work: work)
        case .waiting, .available:
            guard let position = reading.position, position.isPlottable else {
                return idle(text: "位置を取得中", work: work)
            }
            guard position.hasValidHorizontalAccuracy else {
                return AccuracyBadgeModel(
                    tone: .grey,
                    text: "精度不明",
                    accessibilityText: "\(work.shortTitle)。段階\(position.stage.rawValue)。精度不明",
                    isStakeoutGrade: false
                )
            }
            let judged = judgment(for: position, work: work, trust: trust, safetyFactor: safetyFactor)
            let text = position.isTrustedRTKFix
                ? "RTK Fix \(AccuracyFormat.label(meters: position.horizontalAccuracyMeters, approximate: false))"
                : approximateTitle(for: position)
            let accessibility = [
                work.shortTitle,
                "段階\(position.stage.rawValue)。\(text)",
                judged.guidance,
                judged.caution
            ].filter { !$0.isEmpty }.joined(separator: "。")
            return AccuracyBadgeModel(
                tone: judged.tone,
                text: text,
                accessibilityText: accessibility,
                isStakeoutGrade: position.isTrustedRTKFix && judged.tone == .green,
                guidance: judged.guidance,
                caution: judged.caution
            )
        }
    }

    public static func judgment(
        for position: GeodeticPosition,
        work: WorkRequirement,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor
    ) -> (tone: AccuracyTone, guidance: String, caution: String) {
        guard position.isPlottable, position.hasValidHorizontalAccuracy else {
            return (.grey, "", "")
        }
        let factor = trust.factor(for: position, safetyFactor: safetyFactor)
        let horizontal = WorkJudgment.axis(
            reported: position.horizontalAccuracyMeters,
            requirement: work.horizontalMeters,
            factor: factor
        )
        let vertical = position.verticalAccuracyMeters.flatMap { value -> AxisJudgment? in
            guard value.isFinite, value >= 0 else { return nil }
            return WorkJudgment.axis(reported: value, requirement: work.verticalMeters, factor: factor)
        }
        let verticalMissing = vertical == nil
        let tone = WorkJudgment.tone(horizontal: horizontal, vertical: vertical, verticalMissing: verticalMissing)
        return (
            tone,
            WorkJudgment.guidance(work: work, horizontal: horizontal, vertical: vertical, verticalMissing: verticalMissing && horizontal != nil),
            WorkJudgment.caution(factor: factor)
        )
    }

    private static func idle(text: String, work: WorkRequirement) -> AccuracyBadgeModel {
        AccuracyBadgeModel(
            tone: .grey,
            text: text,
            accessibilityText: "\(work.shortTitle)。段階なし。\(text)",
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
