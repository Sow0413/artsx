import Foundation

public enum CoordinateText {
    /// モックと同じ注記。表示は下見であり、保存した JGD2024 の成果ではない。
    public static let previewNote = "JGD2024・下見／概略用"
    public static let storageNote = "保持は WGS84/ITRF。変換は出口で一回"

    public static func latitude(_ degrees: Double) -> String {
        FixedNumber.string(degrees, fractionDigits: 5)
    }

    public static func longitude(_ degrees: Double) -> String {
        FixedNumber.string(degrees, fractionDigits: 5)
    }

    public static func ellipsoidalHeight(_ meters: Double?) -> String {
        guard let meters, meters.isFinite else { return "楕円体高 —" }
        return "楕円体高 \(FixedNumber.string(meters, fractionDigits: 1))m"
    }

    public static func currentLocationLine(_ position: GeodeticPosition) -> String {
        let height = SurveyHeight.resolve(
            ellipsoidalMeters: position.ellipsoidalHeightMeters,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            meanSeaLevelMeters: position.receiver == .iphoneGPS ? position.meanSeaLevelMeters : nil
        )
        let place = "\(latitude(position.latitudeDegrees)), \(longitude(position.longitudeDegrees))"
        return ([place, height.primaryLine] + height.detailLines).joined(separator: "　")
    }

    /// 現在地の大きな数字の横に出す精度。1m 以上は小数1桁。
    public static func accuracyMeters(_ meters: Double) -> String {
        guard meters.isFinite, meters >= 0 else { return "精度不明" }
        if meters >= 1 {
            return "±\(FixedNumber.string(meters, fractionDigits: 1))m"
        }
        var centimeters = Int((meters * 100).rounded(.toNearestOrAwayFromZero))
        if centimeters == 0, meters > 0 {
            centimeters = 1
        }
        return "±\(centimeters)cm"
    }
}

public enum FixedNumber {
    public static func string(_ value: Double, fractionDigits: Int) -> String {
        let digits = max(fractionDigits, 0)
        return String(format: "%.\(digits)f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}
