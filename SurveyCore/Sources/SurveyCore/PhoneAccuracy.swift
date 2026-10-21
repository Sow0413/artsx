import Foundation

/// iPhone だけで点をならす。RTK にはしない。
public enum PhoneAccuracyLabel {
    public static let average = "iPhoneの平均です。RTKではありません。丁張はFIXが必要です。"
    public static let shift = "iPhoneのずれです。RTKではありません。丁張はFIXが必要です。"
}

public enum PhoneAverageSpan: String, Codable, CaseIterable, Identifiable, Sendable {
    case halfMinute
    case oneMinute
    case threeMinutes
    case manual

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .halfMinute: return 30
        case .oneMinute: return 60
        case .threeMinutes: return 180
        case .manual: return nil
        }
    }

    public var title: String {
        switch self {
        case .halfMinute: return "30秒"
        case .oneMinute: return "1分"
        case .threeMinutes: return "3分"
        case .manual: return "手動"
        }
    }
}

public struct PhoneFixSample: Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var ellipsoidalHeightMeters: Double?
    public var orthometricHeightMeters: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double?
    public var timestamp: Date

    public init(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        ellipsoidalHeightMeters: Double?,
        orthometricHeightMeters: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        timestamp: Date
    ) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.orthometricHeightMeters = orthometricHeightMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.timestamp = timestamp
    }

    var isPlottable: Bool {
        latitudeDegrees.isFinite && longitudeDegrees.isFinite
            && abs(latitudeDegrees) <= 90 && abs(longitudeDegrees) <= 180
    }
}

public struct PhoneAverageResult: Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var ellipsoidalHeightMeters: Double?
    public var orthometricHeightMeters: Double?
    public var meanHorizontalAccuracyMeters: Double
    public var sampleCount: Int
    public var discardedCount: Int
    public var horizontalStdMeters: Double
    public var verticalStdMeters: Double?
    public var durationSeconds: TimeInterval

    public var stamp: PhoneAverageStamp {
        PhoneAverageStamp(
            sampleCount: sampleCount,
            discardedCount: discardedCount,
            horizontalStdMeters: horizontalStdMeters,
            verticalStdMeters: verticalStdMeters,
            durationSeconds: durationSeconds,
            label: PhoneAccuracyLabel.average
        )
    }
}

public struct PhoneAverageStamp: Codable, Equatable, Sendable {
    public var sampleCount: Int
    public var discardedCount: Int
    public var horizontalStdMeters: Double
    public var verticalStdMeters: Double?
    public var durationSeconds: TimeInterval
    public var label: String

    public init(
        sampleCount: Int,
        discardedCount: Int,
        horizontalStdMeters: Double,
        verticalStdMeters: Double?,
        durationSeconds: TimeInterval,
        label: String = PhoneAccuracyLabel.average
    ) {
        self.sampleCount = sampleCount
        self.discardedCount = discardedCount
        self.horizontalStdMeters = horizontalStdMeters
        self.verticalStdMeters = verticalStdMeters
        self.durationSeconds = durationSeconds
        self.label = label
    }

    public var line: String {
        "平均 \(sampleCount)点  ばらつき \(PhoneAverage.spread(horizontalStdMeters))  \(Int(durationSeconds.rounded()))秒  \(label)"
    }
}

public struct KnownAnchor: Equatable, Sendable {
    public var id: String
    public var name: String
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var heightMeters: Double?

    public init(id: String, name: String, latitudeDegrees: Double, longitudeDegrees: Double, heightMeters: Double?) {
        self.id = id
        self.name = name
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.heightMeters = heightMeters
    }
}

public enum PhoneAveragePurpose: Equatable, Sendable {
    case record
    case knownPoint(KnownAnchor)
}

public struct PhoneAverageRun: Equatable, Sendable {
    public var startedAt: Date
    public var limit: TimeInterval?
    public var samples: [PhoneFixSample]
    public var purpose: PhoneAveragePurpose

    public init(startedAt: Date, limit: TimeInterval?, samples: [PhoneFixSample] = [], purpose: PhoneAveragePurpose) {
        self.startedAt = startedAt
        self.limit = limit
        self.samples = samples
        self.purpose = purpose
    }

    public func adding(_ sample: PhoneFixSample) -> PhoneAverageRun {
        var copy = self
        if let last = copy.samples.last, last.timestamp == sample.timestamp { return copy }
        copy.samples.append(sample)
        return copy
    }

    public func isFinished(at now: Date) -> Bool {
        guard let limit else { return false }
        return now.timeIntervalSince(startedAt) >= limit
    }

    public func line(at now: Date) -> String {
        let clock: String
        if let limit {
            let remain = max(0, limit - now.timeIntervalSince(startedAt))
            clock = "残り\(PhoneAverage.clock(remain))"
        } else {
            clock = PhoneAverage.clock(now.timeIntervalSince(startedAt))
        }
        let live = PhoneAverage.summarize(samples, startedAt: startedAt, endedAt: now)
        let spread = live.map { PhoneAverage.spread($0.horizontalStdMeters) } ?? "—"
        let count = live?.sampleCount ?? 0
        let dropped = live?.discardedCount ?? 0
        let extra = dropped > 0 ? "（除外\(dropped)）" : ""
        return "平均 \(clock)  ばらつき \(spread)  \(count)点\(extra)"
    }
}

public enum PhoneAverage {
    /// 水平精度が中央値のこの倍より悪いサンプルは捨てる。
    public static let outlierFactor = 2.0

    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public static func spread(_ meters: Double) -> String {
        String(format: "±%.1fm", locale: Locale(identifier: "en_US_POSIX"), meters)
    }

    public static func kept(_ samples: [PhoneFixSample], factor: Double = outlierFactor) -> [PhoneFixSample] {
        let valid = samples.filter {
            $0.isPlottable && $0.horizontalAccuracyMeters.isFinite && $0.horizontalAccuracyMeters >= 0
        }
        guard !valid.isEmpty else { return [] }
        let limit = factor * median(valid.map(\.horizontalAccuracyMeters))
        return valid.filter { $0.horizontalAccuracyMeters <= limit }
    }

    public static func summarize(_ samples: [PhoneFixSample], startedAt: Date, endedAt: Date) -> PhoneAverageResult? {
        let kept = kept(samples)
        guard let origin = kept.first else { return nil }
        var east: [Double] = []
        var north: [Double] = []
        east.reserveCapacity(kept.count)
        north.reserveCapacity(kept.count)
        for sample in kept {
            guard let step = PhoneOffset.meters(
                fromLatitude: origin.latitudeDegrees,
                fromLongitude: origin.longitudeDegrees,
                toLatitude: sample.latitudeDegrees,
                toLongitude: sample.longitudeDegrees
            ) else { continue }
            east.append(step.east)
            north.append(step.north)
        }
        guard east.count == kept.count, !east.isEmpty else { return nil }
        let meanEast = mean(east)
        let meanNorth = mean(north)
        guard let center = PhoneOffset.moved(
            latitude: origin.latitudeDegrees,
            longitude: origin.longitudeDegrees,
            east: meanEast,
            north: meanNorth
        ) else { return nil }
        let ellipsoidal = finite(kept.compactMap(\.ellipsoidalHeightMeters))
        let orthometric = finite(kept.compactMap(\.orthometricHeightMeters))
        let verticalValues = orthometric.count >= 2 ? orthometric : (ellipsoidal.count >= 2 ? ellipsoidal : [])
        return PhoneAverageResult(
            latitudeDegrees: center.latitude,
            longitudeDegrees: center.longitude,
            ellipsoidalHeightMeters: ellipsoidal.isEmpty ? nil : mean(ellipsoidal),
            orthometricHeightMeters: orthometric.isEmpty ? nil : mean(orthometric),
            meanHorizontalAccuracyMeters: mean(kept.map(\.horizontalAccuracyMeters)),
            sampleCount: kept.count,
            discardedCount: samples.count - kept.count,
            horizontalStdMeters: GeoMath.hypotenuse(sampleStd(east), sampleStd(north)),
            verticalStdMeters: verticalValues.isEmpty ? nil : sampleStd(verticalValues),
            durationSeconds: max(0, endedAt.timeIntervalSince(startedAt))
        )
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    static func mean(_ values: [Double]) -> Double {
        values.reduce(0, +) / Double(values.count)
    }

    static func sampleStd(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let center = mean(values)
        let sum = values.reduce(0) { $0 + ($1 - center) * ($1 - center) }
        return GeoMath.squareRoot(sum / Double(values.count - 1))
    }

    static func finite(_ values: [Double]) -> [Double] {
        values.filter(\.isFinite)
    }
}

enum PhoneOffset {
    static func meters(
        fromLatitude: Double,
        fromLongitude: Double,
        toLatitude: Double,
        toLongitude: Double
    ) -> (east: Double, north: Double)? {
        guard let geodesic = GRS80Geodesic.inverse(
            latitude1: fromLatitude,
            longitude1: fromLongitude,
            latitude2: toLatitude,
            longitude2: toLongitude
        ) else { return nil }
        return (geodesic.eastMeters, geodesic.northMeters)
    }

    static func moved(
        latitude: Double,
        longitude: Double,
        east: Double,
        north: Double
    ) -> (latitude: Double, longitude: Double)? {
        let distance = GeoMath.hypotenuse(east, north)
        if distance < 1e-6 { return (latitude, longitude) }
        let azimuth = GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north))
        return GRS80Geodesic.direct(
            latitude: latitude,
            longitude: longitude,
            azimuthDegrees: azimuth,
            distanceMeters: distance
        )
    }
}

/// 既知点に立って出した iPhone のずれ。あとから iPhone の点にだけ引く。
public struct KnownPointShift: Codable, Equatable, Sendable {
    public static let warnAfterSeconds: TimeInterval = 30 * 60
    public static let warnDistanceMeters = 200.0

    public var id: UUID
    public var projectID: String
    public var sourceName: String
    public var sourceLatitude: Double
    public var sourceLongitude: Double
    public var sourceHeightMeters: Double?
    public var eastMeters: Double
    public var northMeters: Double
    public var heightMeters: Double?
    public var calibratedAt: Date
    public var sampleCount: Int
    public var horizontalStdMeters: Double
    public var durationSeconds: TimeInterval
    public var enabled: Bool

    public init(
        id: UUID = UUID(),
        projectID: String,
        sourceName: String,
        sourceLatitude: Double,
        sourceLongitude: Double,
        sourceHeightMeters: Double?,
        eastMeters: Double,
        northMeters: Double,
        heightMeters: Double?,
        calibratedAt: Date,
        sampleCount: Int,
        horizontalStdMeters: Double,
        durationSeconds: TimeInterval,
        enabled: Bool = true
    ) {
        self.id = id
        self.projectID = projectID
        self.sourceName = sourceName
        self.sourceLatitude = sourceLatitude
        self.sourceLongitude = sourceLongitude
        self.sourceHeightMeters = sourceHeightMeters
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.heightMeters = heightMeters
        self.calibratedAt = calibratedAt
        self.sampleCount = sampleCount
        self.horizontalStdMeters = horizontalStdMeters
        self.durationSeconds = durationSeconds
        self.enabled = enabled
    }

    public static func calibrate(
        projectID: String,
        anchor: KnownAnchor,
        mean: PhoneAverageResult,
        at: Date
    ) -> KnownPointShift? {
        guard let step = PhoneOffset.meters(
            fromLatitude: anchor.latitudeDegrees,
            fromLongitude: anchor.longitudeDegrees,
            toLatitude: mean.latitudeDegrees,
            toLongitude: mean.longitudeDegrees
        ) else { return nil }
        let height: Double?
        if let known = anchor.heightMeters, let measured = mean.orthometricHeightMeters, known.isFinite, measured.isFinite {
            height = measured - known
        } else {
            height = nil
        }
        return KnownPointShift(
            projectID: projectID,
            sourceName: anchor.name,
            sourceLatitude: anchor.latitudeDegrees,
            sourceLongitude: anchor.longitudeDegrees,
            sourceHeightMeters: anchor.heightMeters,
            eastMeters: step.east,
            northMeters: step.north,
            heightMeters: height,
            calibratedAt: at,
            sampleCount: mean.sampleCount,
            horizontalStdMeters: mean.horizontalStdMeters,
            durationSeconds: mean.durationSeconds
        )
    }

    public func ageSeconds(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(calibratedAt))
    }

    public func distanceMeters(latitude: Double, longitude: Double) -> Double? {
        guard let step = PhoneOffset.meters(
            fromLatitude: sourceLatitude,
            fromLongitude: sourceLongitude,
            toLatitude: latitude,
            toLongitude: longitude
        ) else { return nil }
        return GeoMath.hypotenuse(step.east, step.north)
    }

    public func isStale(at now: Date, latitude: Double?, longitude: Double?) -> Bool {
        if ageSeconds(at: now) >= Self.warnAfterSeconds { return true }
        guard let latitude, let longitude, let distance = distanceMeters(latitude: latitude, longitude: longitude) else {
            return false
        }
        return distance >= Self.warnDistanceMeters
    }

    public var deltaText: String {
        let east = Self.signed(eastMeters)
        let north = Self.signed(northMeters)
        guard let heightMeters else { return "dE \(east) dN \(north)" }
        return "dE \(east) dN \(north) dH \(Self.signed(heightMeters))"
    }

    public func statusLine(at now: Date, latitude: Double?, longitude: Double?) -> String {
        let age = Self.ageText(ageSeconds(at: now))
        let distance = latitude.flatMap { lat in
            longitude.flatMap { lon in distanceMeters(latitude: lat, longitude: lon) }
        }
        let away = distance.map { "\(Int($0.rounded()))m" } ?? "—"
        let warn = isStale(at: now, latitude: latitude, longitude: longitude) ? "  確認" : ""
        return "既知点 \(sourceName)  \(age)  \(away)\(warn)"
    }

    /// iPhone の位置からずれを引く。受信機の解と、切った合わせはそのまま。
    public func applied(to position: GeodeticPosition, at now: Date) -> (position: GeodeticPosition, stamp: KnownShiftStamp)? {
        guard enabled, position.receiver == .iphoneGPS, position.isPlottable else { return nil }
        guard let moved = PhoneOffset.moved(
            latitude: position.latitudeDegrees,
            longitude: position.longitudeDegrees,
            east: -eastMeters,
            north: -northMeters
        ) else { return nil }
        var copy = position
        copy.latitudeDegrees = moved.latitude
        copy.longitudeDegrees = moved.longitude
        if let heightMeters {
            if let current = copy.ellipsoidalHeightMeters {
                copy.ellipsoidalHeightMeters = current - heightMeters
            }
            if let sea = copy.meanSeaLevelMeters {
                copy.meanSeaLevelMeters = sea - heightMeters
            }
        }
        let stamp = KnownShiftStamp(
            sourceName: sourceName,
            eastMeters: eastMeters,
            northMeters: northMeters,
            heightMeters: heightMeters,
            calibratedAt: calibratedAt,
            ageSeconds: ageSeconds(at: now),
            distanceMeters: distanceMeters(latitude: position.latitudeDegrees, longitude: position.longitudeDegrees) ?? 0,
            label: PhoneAccuracyLabel.shift,
            rawLatitudeDegrees: position.latitudeDegrees,
            rawLongitudeDegrees: position.longitudeDegrees
        )
        return (copy, stamp)
    }

    static func signed(_ value: Double) -> String {
        String(format: "%+.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    static func ageText(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds.rounded(.down)))秒" }
        return "\(Int((seconds / 60).rounded(.down)))分"
    }
}

public struct KnownShiftStamp: Codable, Equatable, Sendable {
    public var sourceName: String
    public var eastMeters: Double
    public var northMeters: Double
    public var heightMeters: Double?
    public var calibratedAt: Date
    public var ageSeconds: TimeInterval
    public var distanceMeters: Double
    public var label: String
    public var rawLatitudeDegrees: Double
    public var rawLongitudeDegrees: Double

    public init(
        sourceName: String,
        eastMeters: Double,
        northMeters: Double,
        heightMeters: Double?,
        calibratedAt: Date,
        ageSeconds: TimeInterval,
        distanceMeters: Double,
        label: String = PhoneAccuracyLabel.shift,
        rawLatitudeDegrees: Double,
        rawLongitudeDegrees: Double
    ) {
        self.sourceName = sourceName
        self.eastMeters = eastMeters
        self.northMeters = northMeters
        self.heightMeters = heightMeters
        self.calibratedAt = calibratedAt
        self.ageSeconds = ageSeconds
        self.distanceMeters = distanceMeters
        self.label = label
        self.rawLatitudeDegrees = rawLatitudeDegrees
        self.rawLongitudeDegrees = rawLongitudeDegrees
    }

    public var deltaText: String {
        let east = KnownPointShift.signed(eastMeters)
        let north = KnownPointShift.signed(northMeters)
        guard let heightMeters else { return "dE \(east) dN \(north)" }
        return "dE \(east) dN \(north) dH \(Self.signed(heightMeters))"
    }

    public var line: String {
        "既知点 \(sourceName)  \(deltaText)  \(label)"
    }

    private static func signed(_ value: Double) -> String {
        KnownPointShift.signed(value)
    }
}

public enum KnownShiftFile {
    public static let name = "known-shift.json"

    public static func load(projectName: String, root: URL) -> KnownPointShift? {
        guard let directory = try? ProjectStore.projectDirectory(projectName, at: root) else { return nil }
        let url = directory.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(KnownPointShift.self, from: data)
    }

    public static func save(_ shift: KnownPointShift, projectName: String, root: URL) throws {
        let directory = try ProjectStore.projectDirectory(projectName, at: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(shift)
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
