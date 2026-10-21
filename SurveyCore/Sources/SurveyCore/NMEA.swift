import Foundation

/// 受信機からの NMEA と、VRS へ返す GGA。パスワードは扱わない。
public enum NMEA {
    public struct Sentence: Equatable, Sendable {
        public var kind: String
        public var fields: [String]

        public init(kind: String, fields: [String]) {
            self.kind = kind
            self.fields = fields
        }
    }

    public static func checksum(_ body: String) -> String {
        var value: UInt8 = 0
        for byte in body.utf8 {
            value ^= byte
        }
        return String(format: "%02X", value)
    }

    public static func parse(_ line: String) -> Sentence? {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("$") {
            text.removeFirst()
        }
        let parts = text.split(separator: "*", maxSplits: 1, omittingEmptySubsequences: false)
        let body = String(parts[0])
        guard body.count >= 6 else { return nil }
        if parts.count == 2 {
            let given = String(parts[1].prefix(2)).uppercased()
            guard given == checksum(body) else { return nil }
        } else {
            return nil
        }
        let columns = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let head = columns.first, head.count >= 5 else { return nil }
        let kind = String(head.suffix(3)).uppercased()
        return Sentence(kind: kind, fields: Array(columns.dropFirst()))
    }

    /// 受信機の GGA。直交高さと分離の和が楕円体高。標高は受信機の分離では作らない。
    public static func position(from lines: [String], at date: Date = Date()) -> GeodeticPosition? {
        var gga: Sentence?
        var rmc: Sentence?
        var gst: Sentence?
        var gns: Sentence?
        for line in lines {
            guard let sentence = parse(line) else { continue }
            switch sentence.kind {
            case "GGA": gga = sentence
            case "RMC": rmc = sentence
            case "GST": gst = sentence
            case "GNS": gns = sentence
            default: break
            }
        }
        guard let gga else { return nil }
        return position(gga: gga, rmc: rmc, gst: gst, gns: gns, at: date)
    }

    public static func gga(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        quality: Int,
        satellites: Int,
        hdop: Double,
        orthometricMeters: Double?,
        geoidSeparationMeters: Double?,
        ageSeconds: Double?,
        station: String,
        at date: Date
    ) -> String {
        let clock = Self.clock(date)
        let lat = coordinate(latitudeDegrees, latitude: true)
        let lon = coordinate(longitudeDegrees, latitude: false)
        let alt = orthometricMeters.map { String(format: "%.2f", locale: posix, $0) } ?? ""
        let sep = geoidSeparationMeters.map { String(format: "%.2f", locale: posix, $0) } ?? ""
        let age = ageSeconds.map { String(format: "%.1f", locale: posix, $0) } ?? ""
        let hdopText = String(format: "%.1f", locale: posix, hdop)
        let body = "GNGGA,\(clock),\(lat.0),\(lat.1),\(lon.0),\(lon.1),\(quality),\(satellites),\(hdopText),\(alt),M,\(sep),M,\(age),\(station)"
        return "$\(body)*\(checksum(body))"
    }

    static func position(gga: Sentence, rmc: Sentence?, gst: Sentence?, gns: Sentence? = nil, at date: Date) -> GeodeticPosition? {
        let fields = gga.fields
        guard fields.count > 5,
              let latitude = degrees(fields[1], hemisphere: fields.count > 2 ? fields[2] : ""),
              let longitude = degrees(fields[3], hemisphere: fields.count > 4 ? fields[4] : ""),
              let quality = Int(fields[5]) else { return nil }
        var fix = fixQuality(quality)
        guard fix != .none else { return nil }
        if reportsCLAS(gns) || reportsCLAS(rmcMode: rmc) {
            fix = .clas
        }
        let satellites = fields.count > 6 ? Int(fields[6]) : nil
        let hdop = fields.count > 7 ? Double(fields[7]) : nil
        let orthometric = fields.count > 8 ? Double(fields[8]) : nil
        let separation = fields.count > 10 ? Double(fields[10]) : nil
        let age = fields.count > 12 ? Double(fields[12]) : nil
        let station = fields.count > 13 ? fields[13] : ""
        let ellipsoidal: Double?
        if let orthometric, let separation {
            ellipsoidal = orthometric + separation
        } else {
            ellipsoidal = nil
        }
        let gstHorizontal = horizontalAccuracy(gst)
        let horizontal = gstHorizontal ?? assumedHorizontal(fix: fix, hdop: hdop)
        let vertical = altitudeAccuracy(gst) ?? (horizontal * 1.5)
        let course = courseDegrees(rmc)
        let stage: PositionStage = fix == .clas ? .clas : ((fix == .rtkFix || fix == .float) ? .rtk : .iphone)
        let receiver: ReceiverKind = fix == .clas ? .clas : .rtk
        return GeodeticPosition(
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            ellipsoidalHeightMeters: ellipsoidal,
            horizontalAccuracyMeters: horizontal,
            verticalAccuracyMeters: vertical,
            timestamp: date,
            stage: stage,
            fixQuality: fix,
            receiver: receiver,
            satelliteCount: satellites,
            pdop: hdop,
            correctionAgeSeconds: age,
            correctionSource: station.isEmpty ? nil : station,
            courseDegrees: course,
            meanSeaLevelMeters: orthometric
        )
    }

    /// 差は地理院の標高 − 受信機の直交高さ。受信機の数は標高にしない。
    public static func receiverGapLine(receiverOrthometricMeters: Double, gsiOrthometricMeters: Double) -> String? {
        guard receiverOrthometricMeters.isFinite, gsiOrthometricMeters.isFinite else { return nil }
        let receiverShown = (receiverOrthometricMeters * 10).rounded() / 10
        let gsiShown = (gsiOrthometricMeters * 10).rounded() / 10
        let diff = gsiShown - receiverShown
        let signed = String(format: "%+.1f", locale: posix, diff)
        return "受信機との差 \(signed)m"
    }

    /// GNS のモードに P があり、RTK の R / F が無いとき、受信機は CLAS と報告している。
    static func reportsCLAS(_ gns: Sentence?) -> Bool {
        guard let mode = gns.flatMap({ $0.fields.count > 5 ? $0.fields[5] : nil }) else { return false }
        return precise(mode)
    }

    static func reportsCLAS(rmcMode rmc: Sentence?) -> Bool {
        guard let rmc, rmc.fields.count > 11 else { return false }
        return precise(rmc.fields[11])
    }

    private static func precise(_ mode: String) -> Bool {
        let letters = mode.uppercased()
        guard letters.contains("P") else { return false }
        return !letters.contains("R") && !letters.contains("F")
    }

    static func fixQuality(_ quality: Int) -> FixQuality {
        switch quality {
        case 4: return .rtkFix
        case 5: return .float
        case 2, 9: return .dgps
        case 1, 3, 6: return .standalone
        default: return .none
        }
    }

    static func degrees(_ raw: String, hemisphere: String) -> Double? {
        guard let value = Double(raw), value.isFinite else { return nil }
        let degrees = (value / 100).rounded(.towardZero)
        let minutes = value - degrees * 100
        guard abs(minutes) < 60 else { return nil }
        let sign: Double = (hemisphere == "S" || hemisphere == "W") ? -1 : 1
        let result = sign * (degrees + minutes / 60)
        guard result.isFinite else { return nil }
        return result
    }

    private static func horizontalAccuracy(_ gst: Sentence?) -> Double? {
        guard let gst, gst.fields.count > 6,
              let lat = Double(gst.fields[5]),
              let lon = Double(gst.fields[6]),
              lat.isFinite, lon.isFinite, lat >= 0, lon >= 0 else { return nil }
        return (lat * lat + lon * lon).squareRoot()
    }

    private static func altitudeAccuracy(_ gst: Sentence?) -> Double? {
        guard let gst, gst.fields.count > 7, let alt = Double(gst.fields[7]), alt.isFinite, alt >= 0 else { return nil }
        return alt
    }

    private static func assumedHorizontal(fix: FixQuality, hdop: Double?) -> Double {
        let base: Double
        switch fix {
        case .rtkFix: base = 0.02
        case .float: base = 0.20
        case .dgps: base = 0.50
        case .standalone, .clas, .none: base = 3
        }
        guard let hdop, hdop.isFinite, hdop > 0 else { return base }
        return max(base, base * hdop)
    }

    private static func courseDegrees(_ rmc: Sentence?) -> Double? {
        guard let rmc, rmc.fields.count > 7, rmc.fields[1] == "A",
              let course = Double(rmc.fields[7]), course.isFinite, course >= 0 else { return nil }
        return course
    }

    private static func coordinate(_ degrees: Double, latitude: Bool) -> (String, String) {
        let sign = degrees < 0
        let absolute = abs(degrees)
        let whole = Int(absolute.rounded(.towardZero))
        let minutes = (absolute - Double(whole)) * 60
        let width = latitude ? 2 : 3
        let text = String(format: "%0\(width)d%07.4f", locale: posix, whole, minutes)
        let hemisphere = latitude ? (sign ? "S" : "N") : (sign ? "W" : "E")
        return (text, hemisphere)
    }

    private static func clock(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d%02d%02d.00", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }

    private static let posix = Locale(identifier: "en_US_POSIX")
}
