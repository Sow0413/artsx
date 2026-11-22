import Foundation

/// ViDoc が出す NMEA の1エポック。GGA が来たときだけ作る。GST と GSA は次の GGA まで保持する。
public struct NMEAEpoch: Equatable, Sendable {
    public var sentence: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var ellipsoidalHeightMeters: Double?
    public var fixQuality: FixQuality
    public var satelliteCount: Int?
    public var hdop: Double?
    public var pdop: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double
    /// 文中の補正遅れ。空欄のときは nil。受信機へ流した時刻からの遅れは呼び出し側が足す。
    public var correctionAgeSeconds: Double?
    public var stationID: String
    public var stage: PositionStage

    public init(
        sentence: String,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        fixQuality: FixQuality,
        satelliteCount: Int?,
        hdop: Double?,
        pdop: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double,
        correctionAgeSeconds: Double?,
        stationID: String,
        stage: PositionStage
    ) {
        self.sentence = sentence
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.fixQuality = fixQuality
        self.satelliteCount = satelliteCount
        self.hdop = hdop
        self.pdop = pdop
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.correctionAgeSeconds = correctionAgeSeconds
        self.stationID = stationID
        self.stage = stage
    }
}

/// `$GNGGA` / `$GNGST` / `$GNGSA` だけを読む。チェックサムは検証せず、`*` 以降を捨てる。
public struct NMEAParser: Sendable {
    public private(set) var pdop: Double?
    private var horizontalStdDev: Double?
    private var verticalStdDev: Double?

    public init() {}

    /// GGA で位置が取れたときだけエポックを返す。GST と GSA は内部の誤差と PDOP を更新する。
    public mutating func consume(_ line: String) -> NMEAEpoch? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("$") else { return nil }
        let payload = trimmed.split(separator: "*", maxSplits: 1).first.map(String.init) ?? trimmed
        let fields = payload.components(separatedBy: ",")
        guard let head = fields.first, head.count >= 6 else { return nil }
        switch String(head.suffix(3)) {
        case "GST":
            parseGST(fields)
            return nil
        case "GSA":
            parseGSA(fields)
            return nil
        case "GGA":
            return parseGGA(fields, sentence: trimmed)
        default:
            return nil
        }
    }

    private mutating func parseGSA(_ fields: [String]) {
        // $xxGSA,mode,fix,sat×12,PDOP,HDOP,VDOP
        if fields.count >= 16 { pdop = Double(fields[15]) }
    }

    private mutating func parseGST(_ fields: [String]) {
        // $xxGST,time,rms,semiMajor,semiMinor,orientation,latStd,lonStd,altStd
        guard fields.count >= 9 else { return }
        if let latitude = Double(fields[6]), let longitude = Double(fields[7]) {
            horizontalStdDev = (latitude * latitude + longitude * longitude).squareRoot()
        }
        if let altitude = Double(fields[8]) { verticalStdDev = altitude }
    }

    private func parseGGA(_ fields: [String], sentence: String) -> NMEAEpoch? {
        // $xxGGA,time,lat,N/S,lon,E/W,quality,numSat,hdop,alt,M,geoid,M,age,station
        guard fields.count >= 14 else { return nil }
        guard let latitude = Self.degrees(from: fields[2], hemisphere: fields[3]),
              let longitude = Self.degrees(from: fields[4], hemisphere: fields[5]) else { return nil }
        let quality = fields[6]
        let fix: FixQuality
        switch quality {
        case "1": fix = .standalone
        case "2": fix = .dgps
        case "4": fix = .rtkFix
        case "5": fix = .float
        default: fix = (Int(quality) ?? 0) == 0 ? .none : .dgps
        }
        let satellites = Int(fields[7])
        let hdop = Double(fields[8])
        let orthometric = Double(fields[9])
        let geoid = Double(fields[11])
        let ellipsoidal: Double? = (orthometric != nil && geoid != nil) ? orthometric! + geoid! : orthometric
        let ageField = fields.count > 13 ? fields[13] : ""
        let age = ageField.isEmpty ? nil : Double(ageField)
        let station = fields.count > 14 ? fields[14].trimmingCharacters(in: .whitespaces) : ""
        let horizontal = horizontalStdDev ?? ((hdop ?? 1.0) * (fix == .rtkFix ? 0.01 : fix == .float ? 0.3 : 1.5))
        let vertical = verticalStdDev ?? (horizontal * 1.8)
        let stage: PositionStage = (fix == .rtkFix || fix == .float) ? .rtk : .iphone
        return NMEAEpoch(
            sentence: sentence,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude,
            ellipsoidalHeightMeters: ellipsoidal,
            fixQuality: fix,
            satelliteCount: satellites,
            hdop: hdop,
            pdop: pdop,
            horizontalAccuracyMeters: horizontal,
            verticalAccuracyMeters: vertical,
            correctionAgeSeconds: age,
            stationID: station,
            stage: stage
        )
    }

    /// NMEA の ddmm.mmmm / dddmm.mmmm を十進度にする。
    static func degrees(from field: String, hemisphere: String) -> Double? {
        guard let value = Double(field), !field.isEmpty else { return nil }
        let degrees = (value / 100).rounded(.towardZero)
        let minutes = value - degrees * 100
        var decimal = degrees + minutes / 60
        if hemisphere == "S" || hemisphere == "W" { decimal = -decimal }
        return decimal
    }
}
