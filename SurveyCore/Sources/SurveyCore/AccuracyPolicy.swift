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
    /// FIX / FLOAT / 単独 / CLAS。位置が無いときは「—」。
    public var solutionLabel: String
    /// 常時出す1行。iPhone は「単独 推定±2m」。足りない長さは guidance に残し、画面ではタップで出す。
    public var compactText: String
    /// iPhone の horizontalAccuracy。68% 半径の自己推定で、既知点で確かめた誤差ではない。
    public var isPhoneSelfEstimate: Bool

    public init(
        tone: AccuracyTone,
        text: String,
        accessibilityText: String,
        isStakeoutGrade: Bool,
        guidance: String = "",
        caution: String = "",
        solutionLabel: String = "—",
        compactText: String = "",
        isPhoneSelfEstimate: Bool = false
    ) {
        self.tone = tone
        self.text = text
        self.accessibilityText = accessibilityText
        self.isStakeoutGrade = isStakeoutGrade
        self.guidance = guidance
        self.caution = caution
        self.solutionLabel = solutionLabel
        self.compactText = compactText.isEmpty ? text : compactText
        self.isPhoneSelfEstimate = isPhoneSelfEstimate
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

    /// iPhone の ± は端末の見積もり。測位シートにこの1行を出す。
    public static let phoneEstimateNote = "iPhoneの自己推定。実際の誤差は既知点で確認"

    /// 既知点に立って測った水平のずれ。1m 以上は小数1桁。
    public static func knownOffsetLine(meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "既知点差 —" }
        if meters >= 1 {
            let text = String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), meters)
            return "既知点差 \(text)m"
        }
        var centimeters = Int((meters * 100).rounded(.toNearestOrAwayFromZero))
        if centimeters == 0, meters > 0 { centimeters = 1 }
        return "既知点差 \(centimeters)cm"
    }

    /// 常時バナー用。約は付けず、±で幅だけ出す。
    public static func plusMinus(meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "±—m" }
        if meters >= 1 {
            let rounded = Int(meters.rounded(.toNearestOrAwayFromZero))
            return "±\(rounded)m"
        }
        var centimeters = Int((meters * 100).rounded(.toNearestOrAwayFromZero))
        if centimeters == 0, meters > 0 {
            centimeters = 1
        }
        return "±\(centimeters)cm"
    }

    /// 常時の1行。外部受信機は補正の古さと衛星数も付ける。
    public static func statusLine(for position: GeodeticPosition) -> String {
        let span = plusMinus(meters: position.horizontalAccuracyMeters)
        let accuracy = position.receiver == .iphoneGPS ? "推定\(span)" : span
        var parts = [position.solutionLabel, accuracy]
        if position.receiver != .iphoneGPS {
            if let age = position.correctionAgeSeconds, age.isFinite, age >= 0 {
                parts.append("補正\(max(0, Int(age.rounded())))秒")
            }
            if let count = position.satelliteCount, count >= 0 {
                parts.append("衛星\(count)")
            }
        }
        return parts.joined(separator: " ")
    }
}

public enum AccuracyPolicy {
    public static func tone(
        for position: GeodeticPosition,
        work: WorkRequirement = WorkCatalog.provisional.selected,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor,
        correction: ControlCorrection? = nil,
        now: Date = Date()
    ) -> AccuracyTone {
        judgment(for: position, work: work, trust: trust, safetyFactor: safetyFactor, correction: correction, now: now).tone
    }

    public static func badge(
        for reading: PositionReading,
        work: WorkRequirement = WorkCatalog.provisional.selected,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor,
        correction: ControlCorrection? = nil,
        now: Date = Date(),
        operatingStage: PositionStage? = nil,
        stageNotice: String = "",
        demoteForStageDrop: Bool = false
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
                    isStakeoutGrade: false,
                    solutionLabel: position.solutionLabel,
                    compactText: "\(position.solutionLabel) 精度不明",
                    isPhoneSelfEstimate: position.receiver == .iphoneGPS
                )
            }
            let judged = judgment(
                for: position,
                work: work,
                trust: trust,
                safetyFactor: safetyFactor,
                correction: correction,
                now: now
            )
            var tone = judged.tone
            var guidance = judged.guidance
            if demoteForStageDrop {
                if tone == .green { tone = .yellow }
                guidance = [stageNotice, guidance].filter { !$0.isEmpty }.joined(separator: " ")
            } else if !stageNotice.isEmpty {
                guidance = [stageNotice, guidance].filter { !$0.isEmpty }.joined(separator: " ")
            }
            let text = "\(position.solutionLabel)　\(detail(for: position))"
            let compactText = AccuracyFormat.statusLine(for: position)
            let phoneEstimate = position.receiver == .iphoneGPS
            let stage = operatingStage ?? position.stage
            let spoken = phoneEstimate
                ? "\(compactText)。\(AccuracyFormat.phoneEstimateNote)"
                : "段階\(stage.rawValue)。\(text)"
            let accessibility = [
                work.shortTitle,
                spoken,
                guidance,
                judged.caution
            ].filter { !$0.isEmpty }.joined(separator: "。")
            return AccuracyBadgeModel(
                tone: tone,
                text: text,
                accessibilityText: accessibility,
                isStakeoutGrade: position.isTrustedRTKFix && tone == .green,
                guidance: guidance,
                caution: judged.caution,
                solutionLabel: position.solutionLabel,
                compactText: compactText,
                isPhoneSelfEstimate: phoneEstimate
            )
        }
    }

    public static func judgment(
        for position: GeodeticPosition,
        work: WorkRequirement,
        trust: InstrumentTrust = InstrumentTrust(),
        safetyFactor: Double = WorkCatalog.defaultSafetyFactor,
        correction: ControlCorrection? = nil,
        now: Date = Date()
    ) -> (tone: AccuracyTone, guidance: String, caution: String) {
        guard position.isPlottable, position.hasValidHorizontalAccuracy else {
            return (.grey, "", "")
        }
        let adjusted = correction?.judgmentMeters(for: position, now: now)
        let factor = adjusted == nil ? trust.factor(for: position, safetyFactor: safetyFactor) : 1
        let reportedHorizontal = adjusted?.horizontal ?? position.horizontalAccuracyMeters
        let reportedVertical = adjusted?.vertical ?? position.verticalAccuracyMeters
        let horizontal = WorkJudgment.axis(
            reported: reportedHorizontal,
            requirement: work.horizontalMeters,
            factor: factor
        )
        let vertical = reportedVertical.flatMap { value -> AxisJudgment? in
            guard value.isFinite, value >= 0 else { return nil }
            return WorkJudgment.axis(reported: value, requirement: work.verticalMeters, factor: factor)
        }
        let verticalMissing = vertical == nil
        let tone = WorkJudgment.tone(horizontal: horizontal, vertical: vertical, verticalMissing: verticalMissing)
        let caution = adjusted?.note ?? WorkJudgment.caution(factor: factor)
        return (
            tone,
            WorkJudgment.guidance(work: work, horizontal: horizontal, vertical: vertical, verticalMissing: verticalMissing && horizontal != nil),
            caution
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

    private static func detail(for position: GeodeticPosition) -> String {
        let magnitude = AccuracyFormat.label(
            meters: position.horizontalAccuracyMeters,
            approximate: !position.isTrustedRTKFix
        )
        if position.receiver == .iphoneGPS {
            return "iPhone GPS \(magnitude)"
        }
        if position.stage == .hybrid, position.fixQuality != .rtkFix {
            return "併用 \(magnitude)"
        }
        return magnitude
    }
}
