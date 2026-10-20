import Foundation

/// 身長の1回入力で、持ち高さと初期歩幅を同時に置く。値は端末の中だけ。
public enum PersonalProfile {
    public static let title = "自分の校正"
    /// この二つのキー以外へは書かない。プロジェクトにも、位置の共有にも出さない。
    public static let deviceKeys = [StatureProfile.storageKey, PaceProfile.storageKey]

    /// 身長を一度入れる。目の高さと持ち高さは身長から出る。歩いた校正が無ければ、歩幅は身長×0.45。
    public static func adopt(
        statureMeters: Double,
        stature: StatureProfile,
        pace: PaceProfile,
        at: Date
    ) -> (stature: StatureProfile, pace: PaceProfile)? {
        guard statureMeters.isFinite, statureMeters > 0, statureMeters <= 3 else { return nil }
        var nextStature = stature
        nextStature.statureMeters = statureMeters
        var nextPace = pace
        if !nextPace.keepsWalkedStride, let stride = PaceMath.initialStride(statureMeters: statureMeters) {
            let unchanged = nextPace.strideOrigin == .stature
                && nextPace.strideMeters.map { abs($0 - stride) < 1e-6 } == true
                && nextPace.strideSetAt != nil
            nextPace.strideMeters = stride
            nextPace.strideOrigin = .stature
            if !unchanged { nextPace.strideSetAt = at }
            nextPace.calibratedDistanceMeters = nil
            nextPace.calibratedSteps = nil
        }
        return (nextStature, nextPace)
    }

    public static func dayText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// 校正した日と値。共有の文面には使わない。
    public static func recordLines(stature: StatureProfile, pace: PaceProfile) -> [String] {
        var lines: [String] = []
        if let hold = stature.holdCalibration {
            let day = hold.at.map(dayText) ?? "日付なし"
            lines.append("持ち高さ　\(day)　\(StatureMath.factorText(hold.holdMeters))m（係数 \(StatureMath.factorText(hold.elbowFactor))）")
        } else {
            lines.append("持ち高さの校正は、まだありません。")
        }
        lines.append(strideLine(pace))
        return lines
    }

    public static func strideLine(_ pace: PaceProfile) -> String {
        guard let stride = pace.strideMeters else { return "歩幅は、まだありません。" }
        let length = StatureMath.factorText(stride)
        let day = pace.strideSetAt.map(dayText)
        switch pace.strideOrigin {
        case .walked:
            let walked = [day, "\(length)m", pace.calibratedDistanceMeters.map { PaceMath.distanceText($0) }, pace.calibratedSteps.map { "\($0)歩" }]
                .compactMap { $0 }
                .joined(separator: "　")
            return "歩幅　\(walked)"
        case .stature:
            let when = day.map { "\($0)　" } ?? ""
            return "歩幅　\(when)\(length)m（身長×0.45）"
        case nil:
            return "歩幅　\(length)m"
        }
    }
}
