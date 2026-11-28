import Foundation

public struct IMUVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public init(_ values: [Double]) {
        self.x = values.count > 0 ? values[0] : 0
        self.y = values.count > 1 ? values[1] : 0
        self.z = values.count > 2 ? values[2] : 0
    }

    public var magnitude: Double { (x * x + y * y + z * z).squareRoot() }

    public func unit() -> IMUVector {
        let length = magnitude
        guard length > 0 else { return self }
        return IMUVector(x / length, y / length, z / length)
    }

    public func dot(_ other: IMUVector) -> Double { x * other.x + y * other.y + z * other.z }

    public func cross(_ other: IMUVector) -> IMUVector {
        IMUVector(
            y * other.z - z * other.y,
            z * other.x - x * other.z,
            x * other.y - y * other.x
        )
    }

    public static func + (lhs: IMUVector, rhs: IMUVector) -> IMUVector {
        IMUVector(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z)
    }

    public static func - (lhs: IMUVector, rhs: IMUVector) -> IMUVector {
        IMUVector(lhs.x - rhs.x, lhs.y - rhs.y, lhs.z - rhs.z)
    }

    public static func * (lhs: IMUVector, rhs: Double) -> IMUVector {
        IMUVector(lhs.x * rhs, lhs.y * rhs, lhs.z * rhs)
    }

    public static func / (lhs: IMUVector, rhs: Double) -> IMUVector {
        IMUVector(lhs.x / rhs, lhs.y / rhs, lhs.z / rhs)
    }
}

public enum IMUCalib {
    /// 国土地理院 2020.0 の近似。西偏を度で返す。
    public static func declinationWestDegrees(latitude: Double, longitude: Double) -> Double {
        let dphi = latitude - 37
        let dlam = longitude - 138
        let minutes = 8 * 60 + 15.822
            + 18.462 * dphi
            - 7.726 * dlam
            + 0.007 * dphi * dphi
            - 0.007 * dphi * dlam
            - 0.655 * dlam * dlam
        return minutes / 60
    }

    /// ベクトル法。軸の方位（度、北から東、0…360）。真北は西偏を引いた値。
    public static func azimuthDegrees(
        acceleration: IMUVector,
        magnetic: IMUVector,
        hardIron: IMUVector,
        declinationWestDegrees declination: Double,
        axis: IMUVector
    ) -> Double? {
        let length = acceleration.magnitude
        guard length > 0 else { return nil }
        let down = acceleration * (-1 / length)
        let corrected = magnetic - hardIron
        let eastRaw = down.cross(corrected)
        guard eastRaw.magnitude > 1e-12 else { return nil }
        let east = eastRaw.unit()
        let north = east.cross(down)
        var degrees = atan2(axis.dot(east), axis.dot(north)) * 180 / .pi - declination
        degrees = degrees.truncatingRemainder(dividingBy: 360)
        if degrees < 0 { degrees += 360 }
        return degrees
    }

    public static func tiltDegrees(acceleration: IMUVector) -> Double? {
        let length = acceleration.magnitude
        guard length > 0 else { return nil }
        let up = acceleration / length
        let cosine = min(1, max(-1, up.z))
        return acos(cosine) * 180 / .pi
    }

    /// ポールの天が傾く方位。0.2° 未満は出さない。
    public static func leanAzimuthDegrees(
        acceleration: IMUVector,
        magnetic: IMUVector,
        hardIron: IMUVector,
        declinationWestDegrees declination: Double = 0
    ) -> Double? {
        guard let tilt = tiltDegrees(acceleration: acceleration), tilt >= 0.2 else { return nil }
        return azimuthDegrees(
            acceleration: acceleration,
            magnetic: magnetic,
            hardIron: hardIron,
            declinationWestDegrees: declination,
            axis: IMUVector(0, 0, 1)
        )
    }

    public struct Reversal: Equatable, Sendable {
        public var biasPitch: Double
        public var biasRoll: Double
        public var surfacePitch: Double
        public var surfaceRoll: Double
        public var missMillimetresAtTwoMeters: Double
    }

    public static func reversal(aPitch: Double, aRoll: Double, bPitch: Double, bRoll: Double) -> Reversal {
        let biasPitch = (aPitch + bPitch) / 2
        let biasRoll = (aRoll + bRoll) / 2
        let surfacePitch = (aPitch - bPitch) / 2
        let surfaceRoll = (aRoll - bRoll) / 2
        let bias = (biasPitch * biasPitch + biasRoll * biasRoll).squareRoot() * .pi / 180
        return Reversal(
            biasPitch: biasPitch,
            biasRoll: biasRoll,
            surfacePitch: surfacePitch,
            surfaceRoll: surfaceRoll,
            missMillimetresAtTwoMeters: 2_000 * tan(bias)
        )
    }

    public static func magnetometerSeparation(_ a: IMUVector, _ b: IMUVector) -> Double {
        (a - b).magnitude
    }

    public struct SixFace: Equatable, Sendable {
        public var offset: IMUVector
        public var scale: IMUVector
        public var weakAxes: [String]
    }

    public static func sixFace(positiveX: IMUVector, negativeX: IMUVector, positiveY: IMUVector, negativeY: IMUVector, positiveZ: IMUVector, negativeZ: IMUVector) -> SixFace {
        let offset = IMUVector(
            (positiveX.x + negativeX.x) / 2,
            (positiveY.y + negativeY.y) / 2,
            (positiveZ.z + negativeZ.z) / 2
        )
        let scale = IMUVector(
            (positiveX.x - negativeX.x) / 2,
            (positiveY.y - negativeY.y) / 2,
            (positiveZ.z - negativeZ.z) / 2
        )
        var weak: [String] = []
        if abs(scale.x) < 0.8 { weak.append("x") }
        if abs(scale.y) < 0.8 { weak.append("y") }
        if abs(scale.z) < 0.8 { weak.append("z") }
        return SixFace(offset: offset, scale: scale, weakAxes: weak)
    }

    public static func sphereFit(_ points: [IMUVector]) -> (center: IMUVector, radius: Double)? {
        guard points.count >= 4 else { return nil }
        var matrix = [[Double]](repeating: [Double](repeating: 0, count: 4), count: 4)
        var rhs = [Double](repeating: 0, count: 4)
        for point in points {
            let row = [2 * point.x, 2 * point.y, 2 * point.z, 1.0]
            let value = point.x * point.x + point.y * point.y + point.z * point.z
            for rowIndex in 0..<4 {
                rhs[rowIndex] += row[rowIndex] * value
                for column in 0..<4 {
                    matrix[rowIndex][column] += row[rowIndex] * row[column]
                }
            }
        }
        guard let solved = solve(matrix, rhs) else { return nil }
        let center = IMUVector(solved[0], solved[1], solved[2])
        let radiusSquared = center.x * center.x + center.y * center.y + center.z * center.z + solved[3]
        guard radiusSquared > 0 else { return nil }
        return (center, radiusSquared.squareRoot())
    }

    public struct RobustStats: Equatable, Sendable {
        public var mean: Double
        public var standardDeviation: Double
        public var kept: Int
        public var dropped: Int
    }

    /// 中央値 ± k×max(MAD, floor) の外を捨てる。
    public static func robustMean(_ values: [Double], k: Double, floor: Double) -> RobustStats? {
        guard let center = TiltMath.median(values) else { return nil }
        let mad = TiltMath.median(values.map { abs($0 - center) }) ?? 0
        let limit = k * max(mad, floor)
        let kept = values.filter { abs($0 - center) <= limit + 1e-15 }
        guard !kept.isEmpty else { return nil }
        let mean = kept.reduce(0, +) / Double(kept.count)
        let variance = kept.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(kept.count)
        return RobustStats(
            mean: mean,
            standardDeviation: variance.squareRoot(),
            kept: kept.count,
            dropped: values.count - kept.count
        )
    }

    private static func solve(_ matrixIn: [[Double]], _ rhsIn: [Double]) -> [Double]? {
        var matrix = matrixIn
        var rhs = rhsIn
        let n = rhs.count
        for column in 0..<n {
            var pivot = column
            for row in (column + 1)..<n where abs(matrix[row][column]) > abs(matrix[pivot][column]) {
                pivot = row
            }
            if abs(matrix[pivot][column]) < 1e-18 { return nil }
            if pivot != column {
                matrix.swapAt(pivot, column)
                rhs.swapAt(pivot, column)
            }
            let scale = matrix[column][column]
            for index in column..<n { matrix[column][index] /= scale }
            rhs[column] /= scale
            for row in 0..<n where row != column {
                let factor = matrix[row][column]
                if factor == 0 { continue }
                for index in column..<n { matrix[row][index] -= factor * matrix[column][index] }
                rhs[row] -= factor * rhs[column]
            }
        }
        return rhs
    }
}

public struct IMUCalibrationRecord: Codable, Equatable, Sendable {
    public var hardwareID: String
    public var bleName: String
    public var recordedAt: Date
    public var temperatureCelsius: Double?
    public var biasPitch: Double
    public var biasRoll: Double
    public var hardIronX: Double
    public var hardIronY: Double
    public var hardIronZ: Double
    public var residualRatio: Double?
    public var magneticPassed: Bool

    public init(
        hardwareID: String,
        bleName: String,
        recordedAt: Date,
        temperatureCelsius: Double?,
        biasPitch: Double,
        biasRoll: Double,
        hardIronX: Double,
        hardIronY: Double,
        hardIronZ: Double,
        residualRatio: Double?,
        magneticPassed: Bool
    ) {
        self.hardwareID = hardwareID
        self.bleName = bleName
        self.recordedAt = recordedAt
        self.temperatureCelsius = temperatureCelsius
        self.biasPitch = biasPitch
        self.biasRoll = biasRoll
        self.hardIronX = hardIronX
        self.hardIronY = hardIronY
        self.hardIronZ = hardIronZ
        self.residualRatio = residualRatio
        self.magneticPassed = magneticPassed
    }
}

public enum IMUCalibrationStore {
    public static func append(_ record: IMUCalibrationRecord, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("imu-calibration.json")
        var history = load(from: directory)
        history.append(record)
        let data = try JSONEncoder().encode(history)
        try data.write(to: url, options: .atomic)
    }

    public static func load(from directory: URL) -> [IMUCalibrationRecord] {
        let url = directory.appendingPathComponent("imu-calibration.json")
        guard let data = try? Data(contentsOf: url),
              let history = try? JSONDecoder().decode([IMUCalibrationRecord].self, from: data) else { return [] }
        return history
    }

    public static func latest(hardwareID: String, bleName: String, in directory: URL) -> IMUCalibrationRecord? {
        load(from: directory).last { $0.hardwareID == hardwareID && $0.bleName == bleName }
    }
}

public struct PPKSessionNote: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var endedAt: Date?
    public var deviceName: String
    public var antennaHeightMeters: Double?
    public var observationIDs: [String]
    public var rawxPresent: Bool
    public var note: String
}

public enum PPKLog {
    public static func directory(in documents: URL) -> URL {
        documents.appendingPathComponent("ppk", isDirectory: true)
    }

    public static func begin(deviceName: String, antennaHeightMeters: Double?, in documents: URL) throws -> URL {
        let folder = directory(in: documents)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
        let base = folder.appendingPathComponent("session-\(stamp)")
        let note = PPKSessionNote(
            startedAt: Date(),
            endedAt: nil,
            deviceName: deviceName,
            antennaHeightMeters: antennaHeightMeters,
            observationIDs: [],
            rawxPresent: false,
            note: "RAWX はまだ来ていません。CFG では要求しません。"
        )
        let data = try JSONEncoder().encode(note)
        try data.write(to: base.appendingPathExtension("json"), options: .atomic)
        FileManager.default.createFile(atPath: base.appendingPathExtension("ubx").path, contents: nil)
        return base
    }

    public static func appendUBX(_ frame: Data, classID: UInt8, messageID: UInt8, base: URL) {
        let ubx = base.appendingPathExtension("ubx")
        if let handle = try? FileHandle(forWritingTo: ubx) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: frame)
        }
        guard classID == 0x02, messageID == 0x15 || messageID == 0x13,
              var note = load(base) else { return }
        note.rawxPresent = true
        note.note = "RAWX または SFRBX が届いています。"
        if let data = try? JSONEncoder().encode(note) {
            try? data.write(to: base.appendingPathExtension("json"), options: .atomic)
        }
    }

    public static func noteObservation(_ name: String, base: URL) {
        guard var note = load(base) else { return }
        note.observationIDs.append(name)
        if let data = try? JSONEncoder().encode(note) {
            try? data.write(to: base.appendingPathExtension("json"), options: .atomic)
        }
    }

    public static func finish(base: URL, observationIDs: [String]) {
        guard var note = load(base) else { return }
        note.endedAt = Date()
        if !observationIDs.isEmpty { note.observationIDs = observationIDs }
        if !note.rawxPresent {
            note.note = "RAWX は来ていません。受信した UBX だけ残しています。"
        }
        if let data = try? JSONEncoder().encode(note) {
            try? data.write(to: base.appendingPathExtension("json"), options: .atomic)
        }
    }

    private static func load(_ base: URL) -> PPKSessionNote? {
        guard let data = try? Data(contentsOf: base.appendingPathExtension("json")) else { return nil }
        return try? JSONDecoder().decode(PPKSessionNote.self, from: data)
    }
}
