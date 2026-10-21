import Foundation

/// 2点合わせで、図面の距離と SIMA の距離が合うかの許容。絶対値（mm）と比 1/N。
public struct AlignmentTolerance: Equatable, Sendable, Codable {
    public static let defaultMillimeters = 20.0
    public static let defaultDenominator = 5000.0

    public var millimeters: Double
    public var denominator: Double

    public init(millimeters: Double, denominator: Double) {
        self.millimeters = millimeters
        self.denominator = denominator
    }

    public static func resolved(millimeters: Double?, denominator: Double?) -> AlignmentTolerance {
        let mm = millimeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } ?? defaultMillimeters
        let ratio = denominator.flatMap { $0.isFinite && $0 >= 1 ? $0 : nil } ?? defaultDenominator
        return AlignmentTolerance(millimeters: mm, denominator: ratio)
    }
}

public enum AlignmentVerdict: String, Equatable, Sendable {
    case ok = "OK"
    case review = "要確認"
}

/// 図面上の2点の距離と、同じ2点の平面距離。縮尺を掛ける前の値。
public struct AlignmentSpanCheck: Equatable, Sendable {
    public var leftLabel: String
    public var rightLabel: String
    public var cadMeters: Double
    public var simaMeters: Double
    /// SIMA − 図面。ミリ。
    public var differenceMillimeters: Double
    /// 長い方 / |差|。差がほぼ 0 のときは nil。
    public var ratioDenominator: Double?
    public var verdict: AlignmentVerdict

    public var ratioText: String {
        guard let ratioDenominator, ratioDenominator.isFinite, ratioDenominator > 0 else { return "—" }
        let shown = min(ratioDenominator, 9_999_999)
        return "1/\(Int(shown.rounded()))"
    }

    public var differenceText: String {
        String(format: "%+.1f", locale: Locale(identifier: "en_US_POSIX"), differenceMillimeters)
    }
}

public enum AlignmentSpan {
    /// 2組以上。組が3つ以上のときは、許容からいちばん外れている組。
    public static func check(pairs: [AlignmentPair], zone: Int, tolerance: AlignmentTolerance) -> AlignmentSpanCheck? {
        guard pairs.count >= 2 else { return nil }
        var worst: AlignmentSpanCheck?
        for left in 0..<pairs.count {
            for right in (left + 1)..<pairs.count {
                guard let span = compare(pairs[left], pairs[right], zone: zone, tolerance: tolerance) else { continue }
                if let current = worst {
                    if rank(span) > rank(current) { worst = span }
                } else {
                    worst = span
                }
            }
        }
        return worst
    }

    private static func rank(_ span: AlignmentSpanCheck) -> Double {
        let flag = span.verdict == .review ? 1_000_000_000.0 : 0
        return flag + abs(span.differenceMillimeters)
    }

    private static func compare(
        _ left: AlignmentPair,
        _ right: AlignmentPair,
        zone: Int,
        tolerance: AlignmentTolerance
    ) -> AlignmentSpanCheck? {
        guard let start = PlaneRectangular.forward(
            latitudeDegrees: left.latitudeDegrees,
            longitudeDegrees: left.longitudeDegrees,
            zone: zone
        ), let end = PlaneRectangular.forward(
            latitudeDegrees: right.latitudeDegrees,
            longitudeDegrees: right.longitudeDegrees,
            zone: zone
        ) else { return nil }
        let cad = left.drawingPoint.distance(to: right.drawingPoint)
        let sima = GeoMath.hypotenuse(
            start.northingMeters - end.northingMeters,
            start.eastingMeters - end.eastingMeters
        )
        let differenceMillimeters = (sima - cad) * 1000
        let longer = max(cad, sima)
        let ratio: Double?
        if abs(sima - cad) >= 5e-5, longer > 1e-6 {
            ratio = longer / abs(sima - cad)
        } else {
            ratio = nil
        }
        let verdict: AlignmentVerdict
        if cad < 1e-4 || sima < 1e-4 || !differenceMillimeters.isFinite {
            verdict = .review
        } else {
            let withinMillimeters = abs(differenceMillimeters) <= tolerance.millimeters + 1e-6
            let withinRatio = abs(sima - cad) / longer <= (1 / tolerance.denominator) + 1e-15
            verdict = withinMillimeters && withinRatio ? .ok : .review
        }
        return AlignmentSpanCheck(
            leftLabel: left.label,
            rightLabel: right.label,
            cadMeters: cad,
            simaMeters: sima,
            differenceMillimeters: differenceMillimeters,
            ratioDenominator: ratio,
            verdict: verdict
        )
    }
}
