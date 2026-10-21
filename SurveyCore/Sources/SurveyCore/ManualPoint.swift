import Foundation

/// 手入力の1点。緯度経度と、その現場の系の平面直角を両方持つ。
public struct ManualPointFix: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case geographic
        case plane
    }

    public var kind: Kind
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var northingMeters: Double
    public var eastingMeters: Double
    public var zone: Int

    public init(
        kind: Kind,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        northingMeters: Double,
        eastingMeters: Double,
        zone: Int
    ) {
        self.kind = kind
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.northingMeters = northingMeters
        self.eastingMeters = eastingMeters
        self.zone = zone
    }

    /// 入れた方と逆の読み。緯度経度なら平面直角、平面直角なら緯度経度。
    public var counterpart: String {
        switch kind {
        case .geographic:
            let roman = PlaneRectangular.zone(zone)?.romanLabel ?? "\(zone)系"
            return "\(roman)  X \(Self.meters(northingMeters))  Y \(Self.meters(eastingMeters))"
        case .plane:
            return "\(Self.degrees(latitudeDegrees)), \(Self.degrees(longitudeDegrees))"
        }
    }

    public static func meters(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    public static func degrees(_ value: Double) -> String {
        String(format: "%.8f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
}

/// 貼り付けの「緯度, 経度」、度分秒、または平面直角の X Y。
public enum ManualPoint {
    public static func decimalPair(latitude: Double, longitude: Double) -> String {
        "\(ManualPointFix.degrees(latitude)), \(ManualPointFix.degrees(longitude))"
    }

    public static func parse(_ raw: String, zone: Int) -> ManualPointFix? {
        let text = normalize(raw)
        if text.isEmpty { return nil }
        if let labeled = labeledPlane(text) {
            return plane(northing: labeled.northing, easting: labeled.easting, zone: zone)
        }
        let tokens = coordinateTokens(text)
        guard tokens.count >= 2, let first = angle(tokens[0]), let second = angle(tokens[1]) else { return nil }
        if abs(first) > 90 || abs(second) > 180 {
            return plane(northing: first, easting: second, zone: zone)
        }
        return geographic(latitude: first, longitude: second, zone: zone)
    }

    public static func geographic(latitude: Double, longitude: Double, zone: Int) -> ManualPointFix? {
        guard latitude.isFinite, longitude.isFinite, abs(latitude) <= 90, abs(longitude) <= 180 else { return nil }
        guard let plane = PlaneRectangular.forward(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            zone: zone
        ) else { return nil }
        return ManualPointFix(
            kind: .geographic,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            northingMeters: plane.northingMeters,
            eastingMeters: plane.eastingMeters,
            zone: zone
        )
    }

    public static func plane(northing: Double, easting: Double, zone: Int) -> ManualPointFix? {
        guard northing.isFinite, easting.isFinite, abs(northing) <= 500_000, abs(easting) <= 500_000 else { return nil }
        guard let geo = PlaneRectangular.inverse(
            northingMeters: northing,
            eastingMeters: easting,
            zone: zone
        ) else { return nil }
        guard abs(geo.latitudeDegrees) <= 90, abs(geo.longitudeDegrees) <= 180 else { return nil }
        return ManualPointFix(
            kind: .plane,
            latitudeDegrees: geo.latitudeDegrees,
            longitudeDegrees: geo.longitudeDegrees,
            northingMeters: northing,
            eastingMeters: easting,
            zone: zone
        )
    }

    public static func height(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let cleaned = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "m", with: "").replacingOccurrences(of: "ｍ", with: "")
        guard let value = Double(cleaned), value.isFinite, abs(value) < 10_000 else { return nil }
        return value
    }

    private static func normalize(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let swaps: [(String, String)] = [
            ("，", ","), ("、", ","), ("；", ","), (";", ","),
            ("度", "°"), ("分", "'"), ("秒", "\""),
            ("′", "'"), ("’", "'"), ("´", "'"),
            ("″", "\""), ("”", "\""), ("“", "\"")
        ]
        for swap in swaps {
            text = text.replacingOccurrences(of: swap.0, with: swap.1)
        }
        text = text.replacingOccurrences(of: "°", with: "°")
        while text.contains("° ") { text = text.replacingOccurrences(of: "° ", with: "°") }
        while text.contains(" '") { text = text.replacingOccurrences(of: " '", with: "'") }
        while text.contains("' ") { text = text.replacingOccurrences(of: "' ", with: "'") }
        while text.contains(" \"") { text = text.replacingOccurrences(of: " \"", with: "\"") }
        return text
    }

    private static func coordinateTokens(_ text: String) -> [String] {
        if text.contains(",") {
            return text.split(separator: ",", omittingEmptySubsequences: true).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        return text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func labeledPlane(_ text: String) -> (northing: Double, easting: Double)? {
        let pattern = #"(?i)(?:X|北)\s*[:=]?\s*([+-]?\d+(?:\.\d+)?)\s*[, ]\s*(?:Y|東)\s*[:=]?\s*([+-]?\d+(?:\.\d+)?)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges == 3,
              let northing = capture(text, match, 1),
              let easting = capture(text, match, 2) else { return nil }
        return (northing, easting)
    }

    private static func angle(_ token: String) -> Double? {
        let raw = token.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }
        let upper = raw.uppercased()
        var sign = 1.0
        if upper.hasPrefix("S") || upper.hasPrefix("W") || upper.hasSuffix("S") || upper.hasSuffix("W") {
            sign = -1
        }
        let stripped = upper
            .replacingOccurrences(of: "N", with: "")
            .replacingOccurrences(of: "S", with: "")
            .replacingOccurrences(of: "E", with: "")
            .replacingOccurrences(of: "W", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let value = Double(stripped) { return sign * value }
        let pattern = #"^([+-]?\d+(?:\.\d+)?)°(?:(\d+(?:\.\d+)?)')?(?:(\d+(?:\.\d+)?)"?)?$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
              match.numberOfRanges == 4,
              let degrees = capture(stripped, match, 1) else { return nil }
        let minutes = capture(stripped, match, 2) ?? 0
        let seconds = capture(stripped, match, 3) ?? 0
        return sign * (degrees + minutes / 60 + seconds / 3600)
    }

    private static func capture(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> Double? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return nil }
        return Double(text[swift])
    }
}
