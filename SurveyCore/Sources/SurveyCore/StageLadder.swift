import Foundation

public struct StageTransition: Sendable, Equatable {
    public var stage: PositionStage
    /// 解が落ちて、止めずに1段下げた。
    public var steppedDown: Bool
    public var notice: String
    /// 測位そのものは止めない。
    public var continues: Bool

    public init(stage: PositionStage, steppedDown: Bool, notice: String, continues: Bool = true) {
        self.stage = stage
        self.steppedDown = steppedDown
        self.notice = notice
        self.continues = continues
    }

    public static let ground = StageTransition(stage: .iphone, steppedDown: false, notice: "")
}

/// 機器がつながると、その機器の段階まで上げる。解が落ちたら止めず、1段だけ下げる。
public enum StageLadder {
    public static func ceiling(for position: GeodeticPosition) -> PositionStage {
        switch position.receiver {
        case .totalStation, .level, .uwb: return .hybrid
        case .rtk: return .rtk
        case .clas: return .clas
        case .iphoneGPS: return .iphone
        }
    }

    /// 今の解が、正直に支えられる段階。
    public static func supported(by position: GeodeticPosition) -> PositionStage {
        let cap = ceiling(for: position)
        switch position.fixQuality {
        case .rtkFix:
            if position.receiver == .iphoneGPS || position.receiver == .clas { return cap }
            return cap
        case .float:
            return cap.rawValue >= PositionStage.clas.rawValue ? .clas : .iphone
        case .clas:
            return .clas
        case .dgps, .standalone, .none:
            return .iphone
        }
    }

    public static func step(held: PositionStage, reported: GeodeticPosition) -> StageTransition {
        let cap = ceiling(for: reported)
        let support = supported(by: reported)
        if cap.rawValue < held.rawValue {
            return StageTransition(
                stage: cap,
                steppedDown: true,
                notice: "つながっている機器に合わせ、段階\(cap.rawValue)に下げました。測位は続けます。"
            )
        }
        if support.rawValue > held.rawValue {
            return StageTransition(
                stage: support,
                steppedDown: false,
                notice: "段階\(support.rawValue)に上げました。"
            )
        }
        if support.rawValue < held.rawValue {
            let lowered = PositionStage(rawValue: held.rawValue - 1) ?? .iphone
            return StageTransition(
                stage: lowered,
                steppedDown: true,
                notice: "解が落ちたので段階\(lowered.rawValue)に下げました。測位は続けます。"
            )
        }
        return StageTransition(stage: held, steppedDown: false, notice: "")
    }
}

/// 基準点の記録を止めた帯。下がっているあいだだけ出し、FIX に戻ったら消す。
public enum StageDropNotice {
    public static let recordingStopped = "段階が下がったので、基準点の記録を止めました。測位は続けます。"

    public static func downgradeIsCurrent(stage: PositionStage, quality: FixQuality) -> Bool {
        quality != .rtkFix || !StageGate.allowsRecording(workID: "boundary", stage: stage)
    }

    /// 今の帯がこの文で、解が FIX かつ段階2以上なら空にする。ほかの文はそのまま。
    public static func resolve(current: String?, stage: PositionStage, quality: FixQuality) -> String? {
        guard current == recordingStopped else { return current }
        return downgradeIsCurrent(stage: stage, quality: quality) ? current : nil
    }
}

public enum StageGate {
    /// 基準点モードは段階2（RTK）が要る。ほかの作業は段階を必須にしない。
    public static func minimumStage(workID: String) -> PositionStage? {
        workID == "boundary" ? .rtk : nil
    }

    public static func allowsRecording(workID: String, stage: PositionStage) -> Bool {
        guard let minimum = minimumStage(workID: workID) else { return true }
        return stage.rawValue >= minimum.rawValue
    }
}
