import Foundation

/// 61-2。準拠モードは現場ごとに切り替え、既定はオフ。記録は仮置きのまま。
public struct SiteInstrument: Codable, Equatable, Sendable {
    public var complianceEnabled: Bool
    public var cameraKind: String
    public var cameraX: Double
    public var cameraY: Double
    public var cameraZ: Double
    public var antennaMethod: String
    public var poleMeters: Double
    public var laserMeters: Double?
    public var kbmSource: String
    public var kbmVersion: String
    public var kbmDate: String
    public var kbmH: Double?
    public var kbmFirstN: Double?
    public var kbmFirstAt: Date?
    public var kbmSecondN: Double?
    public var kbmSecondAt: Date?

    public init(
        complianceEnabled: Bool = false,
        cameraKind: String = "spcPlus",
        cameraX: Double = CameraOffset.spcPlus15ProMax.x,
        cameraY: Double = CameraOffset.spcPlus15ProMax.y,
        cameraZ: Double = CameraOffset.spcPlus15ProMax.z,
        antennaMethod: String = "pole",
        poleMeters: Double = 2,
        laserMeters: Double? = nil,
        kbmSource: String = "",
        kbmVersion: String = "",
        kbmDate: String = "",
        kbmH: Double? = nil,
        kbmFirstN: Double? = nil,
        kbmFirstAt: Date? = nil,
        kbmSecondN: Double? = nil,
        kbmSecondAt: Date? = nil
    ) {
        self.complianceEnabled = complianceEnabled
        self.cameraKind = cameraKind
        self.cameraX = cameraX
        self.cameraY = cameraY
        self.cameraZ = cameraZ
        self.antennaMethod = antennaMethod
        self.poleMeters = poleMeters
        self.laserMeters = laserMeters
        self.kbmSource = kbmSource
        self.kbmVersion = kbmVersion
        self.kbmDate = kbmDate
        self.kbmH = kbmH
        self.kbmFirstN = kbmFirstN
        self.kbmFirstAt = kbmFirstAt
        self.kbmSecondN = kbmSecondN
        self.kbmSecondAt = kbmSecondAt
    }

    public var antennaToGroundMeters: Double? {
        if antennaMethod == "laser" {
            guard let laserMeters else { return nil }
            return AntennaHeight.lowerLaserHousingMeters + laserMeters
        }
        return poleMeters
    }

    public var antennaMethodLabel: String {
        antennaMethod == "laser" ? "下レーザー" : "ポール高"
    }

    public func groundMarkMeters(ellipsoidal: Double) -> Double? {
        guard let drop = antennaToGroundMeters else { return nil }
        return ellipsoidal - drop
    }
}

public enum CameraOffset {
    public static let spcPlus15ProMax = (x: 0.022, y: 0.056, z: 0.017)

    public static func displayName(_ kind: String) -> String {
        switch kind {
        case "spcPlus": return "SPC+"
        case "spc": return "SPC"
        case "custom": return "Custom"
        default: return kind
        }
    }

    /// iPhone 17 Pro / Pro Max は SPC+ の公開値が無い。Custom だけ。
    /// hw.machine の iPhone17,1 は 16 Pro なので、ここには入れない。
    public static func customOnly(machine: String) -> Bool {
        let folded = machine.lowercased().replacingOccurrences(of: " ", with: "")
        if folded.contains("iphone17pro") { return true }
        return folded == "iphone18,1" || folded == "iphone18,2"
    }
}

public enum AntennaHeight {
    public static let lowerLaserHousingMeters = 0.1877
}

public enum KBMCorrection {
    public static let title = "現場高さ補正（KBM 1点）"
    public static let limitMeters = 0.02

    public static func n(ellipsoidal h: Double, orthometric H: Double) -> Double { h - H }

    public static func accepted(first: Double?, firstAt: Date?, second: Double?, secondAt: Date?) -> Bool {
        guard let first, let second, let firstAt, let secondAt, firstAt != secondAt else { return false }
        return abs(first - second) <= limitMeters
    }
}

public enum PrecisionGate {
    public static let minimumFixSeconds: TimeInterval = 10
    public static let maximumTiltDegrees = 0.5
    public static let planeLimitMeters = 0.020
    public static let verticalLimitMeters = 0.030
    public static let minimumKnownPoints = 3

    public static func tiltAllowsStart(degrees: Double?) -> Bool {
        guard let degrees else { return true }
        return abs(degrees) <= maximumTiltDegrees
    }

    public static func complianceAllowsStart(fix: Bool, durationSeconds: TimeInterval) -> Bool {
        fix && durationSeconds >= minimumFixSeconds
    }

    public static func localizeAllows(knownPoints: Int) -> Bool {
        knownPoints >= minimumKnownPoints
    }
}

public struct PrecisionTrial: Equatable, Sendable {
    public var name: String
    public var planeErrorMeters: Double
    public var verticalErrorMeters: Double?
    public var isKBM: Bool

    public init(name: String, planeErrorMeters: Double, verticalErrorMeters: Double?, isKBM: Bool = false) {
        self.name = name
        self.planeErrorMeters = planeErrorMeters
        self.verticalErrorMeters = verticalErrorMeters
        self.isKBM = isKBM
    }
}

public enum PrecisionReport {
    /// 監督・検査要領（令和7年3月）。2セット較差の欄は無い。KBM は点検点にしない。
    public static func text(trials: [PrecisionTrial], antennaNote: String, geoidNote: String) -> String {
        var lines = [
            "精度確認試験報告書",
            "準拠: 監督・検査要領（令和7年3月）",
            "許容 平面 ±20mm 鉛直 ±30mm",
            "2セット較差: 使わない",
            "アンテナ: \(antennaNote)",
            "ジオイド: \(geoidNote)"
        ]
        for trial in trials where !trial.isKBM && !trial.name.contains("KBM") {
            let plane = abs(trial.planeErrorMeters) <= PrecisionGate.planeLimitMeters ? "合格" : "不合格"
            let vertical: String
            if let error = trial.verticalErrorMeters {
                vertical = abs(error) <= PrecisionGate.verticalLimitMeters ? "合格" : "不合格"
            } else {
                vertical = "高さは未判定"
            }
            lines.append("\(trial.name) 平面\(plane) 鉛直\(vertical)")
        }
        return lines.joined(separator: "\n")
    }
}

public struct GeoidGrid2024: Sendable {
    public var samples: [(latitude: Double, longitude: Double, separation: Double)]

    public init(samples: [(latitude: Double, longitude: Double, separation: Double)]) {
        self.samples = samples
    }

    public static func parse(_ text: String) -> GeoidGrid2024 {
        let samples = text.split(whereSeparator: \.isNewline).compactMap { line -> (Double, Double, Double)? in
            let raw = line.trimmingCharacters(in: .whitespaces)
            if raw.isEmpty || raw.hasPrefix("#") { return nil }
            let parts = raw.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3,
                  let lat = Double(parts[0]),
                  let lon = Double(parts[1]),
                  let n = Double(parts[2]) else { return nil }
            return (lat, lon, n)
        }
        return GeoidGrid2024(samples: samples)
    }

    /// 近い格子のジオイド高。空なら nil。受信機のジオイド高では代用しない。
    public func separation(latitude: Double, longitude: Double) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.min { lhs, rhs in
            let dl = (lhs.latitude - latitude) * (lhs.latitude - latitude) + (lhs.longitude - longitude) * (lhs.longitude - longitude)
            let dr = (rhs.latitude - latitude) * (rhs.latitude - latitude) + (rhs.longitude - longitude) * (rhs.longitude - longitude)
            return dl < dr
        }?.separation
    }
}

public enum SiteDXF {
    public static let zone = 16
    public static let epsg = 6684
    public static let controlLayer = "測設_基準点"

    /// JGD2011 の平面直角。EPSG:6669 が 1 系、6684 が 16 系。
    public static func zone(forEPSG epsg: Int) -> Int? {
        let number = epsg - 6668
        guard (1...19).contains(number) else { return nil }
        return number
    }

    public static func prefersUTF8(acadVersion: String?) -> Bool {
        guard let acadVersion else { return false }
        let digits = acadVersion.filter(\.isNumber)
        return (Int(digits) ?? 0) >= 1021
    }

    public static func controlNames(in document: DrawingDocument) -> [String] {
        document.entities.compactMap { entity in
            guard entity.layer == controlLayer else { return nil }
            if case let .text(_, string, _, _) = entity.primitive {
                let name = string.trimmingCharacters(in: .whitespaces)
                return name.isEmpty ? nil : name
            }
            return nil
        }
    }

    /// 層の点名は IRB- で始まり、台帳にあるものだけ合う。
    public static func mismatches(drawing names: [String], ledger: [String]) -> [String] {
        let known = Set(ledger)
        return names.filter { !$0.hasPrefix("IRB-") || !known.contains($0) }
    }
}

/// 図面の隣に置く `.meta.json`。`図面.dxf.meta.json` が先、`図面.meta.json` がその次。
public struct DrawingSidecar: Equatable, Decodable, Sendable {
    public var epsg: Int
    public var axis: String
    public var unit: String
    public var transform: TransformNote?

    public struct TransformNote: Equatable, Decodable, Sendable {
        public var status: String?
        public var version: String?
        public var pairCount: Int?
        public var rmsMillimetres: Double?
        public var maxMillimetres: Double?

        enum CodingKeys: String, CodingKey {
            case status
            case version
            case pairCount = "対応点"
            case rmsMillimetres = "rms_mm"
            case maxMillimetres = "最大_mm"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            status = try container.decodeIfPresent(String.self, forKey: .status)
            if let number = try? container.decode(Int.self, forKey: .version) {
                version = String(number)
            } else if let number = try? container.decode(Double.self, forKey: .version) {
                version = String(number)
            } else {
                version = try container.decodeIfPresent(String.self, forKey: .version)
            }
            pairCount = try container.decodeIfPresent(Int.self, forKey: .pairCount)
            rmsMillimetres = try container.decodeIfPresent(Double.self, forKey: .rmsMillimetres)
            maxMillimetres = try container.decodeIfPresent(Double.self, forKey: .maxMillimetres)
        }
    }

    public init(epsg: Int, axis: String, unit: String, transform: TransformNote? = nil) {
        self.epsg = epsg
        self.axis = axis
        self.unit = unit
        self.transform = transform
    }

    public static func load(_ data: Data) -> DrawingSidecar? {
        var body = data
        if body.starts(with: Data([0xEF, 0xBB, 0xBF])) { body.removeFirst(3) }
        return try? JSONDecoder().decode(DrawingSidecar.self, from: body)
    }

    public var zone: Int? { SiteDXF.zone(forEPSG: epsg) }

    public var drawingAxis: DrawingAxis? {
        switch axis {
        case "EN": return .cadEastNorth
        case "NE": return .surveyNorthEast
        default: return nil
        }
    }
}

public enum DrawingSidecarNames {
    /// 先に `名前.dxf.meta.json`。次に `名前.meta.json`。
    public static func candidates(forDXF fileName: String) -> [String] {
        let full = fileName + ".meta.json"
        let stem = (fileName as NSString).deletingPathExtension + ".meta.json"
        if full.caseInsensitiveCompare(stem) == .orderedSame { return [full] }
        return [full, stem]
    }

    public static func match(dxfName: String, metaNames: [String]) -> String? {
        for wanted in candidates(forDXF: dxfName) {
            if let found = metaNames.first(where: { $0.caseInsensitiveCompare(wanted) == .orderedSame }) {
                return found
            }
        }
        return nil
    }

    public static func siblingURLs(for dxf: URL) -> [URL] {
        let full = dxf.appendingPathExtension("meta.json")
        let stem = dxf.deletingPathExtension().appendingPathExtension("meta.json")
        if full.path == stem.path { return [full] }
        return [full, stem]
    }
}

public enum PlaneZoneLabel {
    public static func button(_ zone: Int) -> String {
        zone == 6 ? "第VI系" : "\(zone)系"
    }

    /// 第VI系を先頭にする。meta が無いときのピッカー。
    public static func pickerZones() -> [Int] {
        [6] + (1...19).filter { $0 != 6 }
    }
}

public enum ViDocLaser {
    /// 測距と cmd 22 だけ送る。mode 7、ロック、認証の書き換えは送らない。
    public static let enabled = true
    public static let heldReason = "測距コマンドだけ送ります。リセットは送りません。"
}

public enum ViDocFirmware {
    public static func version(in text: String) -> String? {
        let line = ViDocLink.normalized(text)
        guard let range = line.range(of: "Ver_") else { return nil }
        let version = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }
}
