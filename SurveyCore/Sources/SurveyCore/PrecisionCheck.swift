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

public enum ViDocLaser {
    /// cmd22 のバイト列はリポジトリに無い。送らない。mode 7 と認証の書き換えも送らない。
    public static let enabled = false
    public static let heldReason = "レーザー cmd22 のバイト列が無いので送りません。"
}

public enum ViDocFirmware {
    public static func version(in text: String) -> String? {
        let line = ViDocLink.normalized(text)
        guard let range = line.range(of: "Ver_") else { return nil }
        let version = line[range.upperBound...].prefix { $0.isNumber || $0 == "." }
        return version.isEmpty ? nil : String(version)
    }
}
