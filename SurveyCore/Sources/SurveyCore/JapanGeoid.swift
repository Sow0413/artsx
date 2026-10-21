import Foundation

/// 標高 = 楕円体高 − ジオイド高。格子は国土地理院「日本のジオイド2011（Ver.2.2）」。
/// 出典: 国土地理院。格子外は CLLocation.altitude（平均海水面）を代わりに使う。
public enum JapanGeoid {
    public static let modelName = "日本のジオイド2011 Ver.2.2"
    public static let fallbackModelName = "CLLocation.altitude"

    public static func undulationMeters(latitudeDegrees: Double, longitudeDegrees: Double) -> Double? {
        GeoidGrid.shared.undulation(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees)
    }
}

/// アンテナ補正のあとの楕円体高を、標高へ直す。補正そのものはここで足さない。
public struct SurveyHeight: Equatable, Sendable {
    public var orthometricMeters: Double?
    public var ellipsoidalMeters: Double?
    public var geoidMeters: Double?
    public var model: String?

    public var primaryLine: String {
        if let orthometricMeters {
            return "標高 \(SurveyHeight.meters(orthometricMeters))m"
        }
        guard let ellipsoidalMeters else { return "標高 —" }
        return "楕円体高 \(SurveyHeight.meters(ellipsoidalMeters))m"
    }

    public var detailLines: [String] {
        var lines: [String] = []
        if let ellipsoidalMeters {
            lines.append("楕円体高 \(SurveyHeight.meters(ellipsoidalMeters))m")
        }
        if let model {
            lines.append(model)
        }
        return lines
    }

    public static func resolve(
        ellipsoidalMeters: Double?,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        meanSeaLevelMeters: Double? = nil,
        deviceEllipsoidalMeters: Double? = nil
    ) -> SurveyHeight {
        let ellipsoidal = finite(ellipsoidalMeters)
        if let ellipsoidal,
           let undulation = JapanGeoid.undulationMeters(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees) {
            return SurveyHeight(
                orthometricMeters: ellipsoidal - undulation,
                ellipsoidalMeters: ellipsoidal,
                geoidMeters: undulation,
                model: JapanGeoid.modelName
            )
        }
        if let sea = finite(meanSeaLevelMeters) {
            let shifted: Double
            if let ellipsoidal, let device = finite(deviceEllipsoidalMeters) {
                shifted = ellipsoidal - device + sea
            } else {
                shifted = sea
            }
            return SurveyHeight(
                orthometricMeters: shifted,
                ellipsoidalMeters: ellipsoidal,
                geoidMeters: nil,
                model: JapanGeoid.fallbackModelName
            )
        }
        return SurveyHeight(orthometricMeters: nil, ellipsoidalMeters: ellipsoidal, geoidMeters: nil, model: nil)
    }

    public static func meters(_ value: Double) -> String {
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    private static func finite(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }
}

extension FieldObservation {
    /// 記録の詳細。標高を先に出し、楕円体高とジオイドモデルを残す。
    public func fieldReportLines() -> [String] {
        var lines = condition?.reportLines ?? []
        let height = storedElevation
        if !lines.contains(where: { $0.hasPrefix("標高") }), let orthometric = height.orthometricMeters {
            lines.append("標高 \(SurveyHeight.meters(orthometric))m")
        }
        if !lines.contains(where: { $0.hasPrefix("楕円体高") }), let ellipsoidal = height.ellipsoidalMeters {
            lines.append("楕円体高 \(SurveyHeight.meters(ellipsoidal))m")
        }
        if let model = height.model, !lines.contains(model) {
            lines.append(model)
        }
        return lines
    }

    private var storedElevation: SurveyHeight {
        if condition?.orthometricHeightMeters != nil || condition?.geoidModel != nil {
            return SurveyHeight(
                orthometricMeters: condition?.orthometricHeightMeters,
                ellipsoidalMeters: condition?.surveyEllipsoidalMeters ?? condition?.stature?.groundHeightMeters ?? captured.ellipsoidalHeightMeters,
                geoidMeters: condition?.geoidUndulationMeters,
                model: condition?.geoidModel
            )
        }
        let base = condition?.stature?.groundHeightMeters ?? captured.ellipsoidalHeightMeters
        return SurveyHeight.resolve(
            ellipsoidalMeters: base,
            latitudeDegrees: captured.latitudeDegrees,
            longitudeDegrees: captured.longitudeDegrees,
            meanSeaLevelMeters: captured.meanSeaLevelMeters,
            deviceEllipsoidalMeters: captured.ellipsoidalHeightMeters
        )
    }
}

private struct GeoidGrid {
    static let shared = GeoidGrid.load()

    var latitudeOrigin: Double
    var longitudeOrigin: Double
    var latitudeStep: Double
    var longitudeStep: Double
    var rows: Int
    var columns: Int
    var samples: [Int16]

    func undulation(latitudeDegrees: Double, longitudeDegrees: Double) -> Double? {
        guard rows > 1, columns > 1, latitudeStep > 0, longitudeStep > 0 else { return nil }
        guard latitudeDegrees.isFinite, longitudeDegrees.isFinite else { return nil }
        let x = (longitudeDegrees - longitudeOrigin) / longitudeStep
        let y = (latitudeDegrees - latitudeOrigin) / latitudeStep
        guard x >= 0, y >= 0 else { return nil }
        let i1 = Int(x)
        let j1 = Int(y)
        guard i1 < columns - 1, j1 < rows - 1 else { return nil }
        let fx = x - Double(i1)
        let fy = y - Double(j1)
        guard let z00 = meters(i1, j1),
              let z01 = meters(i1 + 1, j1),
              let z10 = meters(i1, j1 + 1),
              let z11 = meters(i1 + 1, j1 + 1) else { return nil }
        return z00 * (1 - fx) * (1 - fy) + z01 * fx * (1 - fy) + z10 * (1 - fx) * fy + z11 * fx * fy
    }

    private func meters(_ column: Int, _ row: Int) -> Double? {
        let sample = samples[row * columns + column]
        if sample == Self.missing { return nil }
        return Double(sample) / 100
    }

    private static let missing: Int16 = -32768

    private static func load() -> GeoidGrid {
        let empty = GeoidGrid(latitudeOrigin: 0, longitudeOrigin: 0, latitudeStep: 0, longitudeStep: 0, rows: 0, columns: 0, samples: [])
        guard let url = Bundle.module.url(forResource: "gsigeo2011", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              data.count > 48,
              data.prefix(8) == Data("GSIGEO11".utf8) else { return empty }
        let header = 48
        var originLat = 0.0
        var originLon = 0.0
        var stepLat = 0.0
        var stepLon = 0.0
        var rows = 0
        var columns = 0
        data.withUnsafeBytes { raw in
            originLat = raw.loadUnaligned(fromByteOffset: 8, as: Double.self)
            originLon = raw.loadUnaligned(fromByteOffset: 16, as: Double.self)
            stepLat = raw.loadUnaligned(fromByteOffset: 24, as: Double.self)
            stepLon = raw.loadUnaligned(fromByteOffset: 32, as: Double.self)
            rows = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 40, as: UInt32.self)))
            columns = Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 44, as: UInt32.self)))
        }
        let count = rows * columns
        guard rows > 1, columns > 1, data.count >= header + count * 2 else { return empty }
        var samples = [Int16](repeating: missing, count: count)
        data.withUnsafeBytes { raw in
            for index in 0..<count {
                let bits = UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: header + index * 2, as: UInt16.self))
                samples[index] = Int16(bitPattern: bits)
            }
        }
        return GeoidGrid(
            latitudeOrigin: originLat,
            longitudeOrigin: originLon,
            latitudeStep: stepLat,
            longitudeStep: stepLon,
            rows: rows,
            columns: columns,
            samples: samples
        )
    }
}
