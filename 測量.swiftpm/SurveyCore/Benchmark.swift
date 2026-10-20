import Foundation

public struct BenchmarkPlan: Equatable, Sendable {
    public var durationSeconds: TimeInterval
    public var intervalSeconds: TimeInterval

    public static let defaultDurationSeconds: TimeInterval = 600
    public static let durationChoices: [TimeInterval] = [60, 600, 1_800]

    public init(durationSeconds: TimeInterval, intervalSeconds: TimeInterval = 1) {
        self.durationSeconds = durationSeconds
        self.intervalSeconds = intervalSeconds
    }

    public var expectedCount: Int {
        guard intervalSeconds > 0, durationSeconds > 0 else { return 0 }
        return Int((durationSeconds / intervalSeconds).rounded(.down))
    }

    public static func durationTitle(_ seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes >= 1, minutes.rounded() == minutes {
            return "\(Int(minutes))分"
        }
        return "\(Int(seconds.rounded(.down)))秒"
    }
}

public struct BenchmarkSample: Equatable, Sendable {
    public var loggedAt: Date
    public var position: GeodeticPosition

    public init(loggedAt: Date, position: GeodeticPosition) {
        self.loggedAt = loggedAt
        self.position = position
    }
}

/// 1秒に1点。位置が無い秒は飛ばし、終わった後は足さない。
public struct BenchmarkRecorder: Equatable, Sendable {
    public let point: ControlPoint
    public let plan: BenchmarkPlan
    public let startedAt: Date
    public private(set) var samples: [BenchmarkSample]
    private var nextDue: Date

    public init(point: ControlPoint, plan: BenchmarkPlan, startedAt: Date, samples: [BenchmarkSample] = []) {
        self.point = point
        self.plan = plan
        self.startedAt = startedAt
        self.samples = samples
        self.nextDue = startedAt
    }

    public func isFinished(at now: Date) -> Bool {
        now >= startedAt.addingTimeInterval(plan.durationSeconds)
    }

    public mutating func tick(reading: PositionReading, now: Date) {
        guard !isFinished(at: now), now >= nextDue else { return }
        guard let position = reading.position, position.isPlottable else { return }
        samples.append(BenchmarkSample(loggedAt: now, position: position))
        nextDue = now.addingTimeInterval(plan.intervalSeconds)
    }
}

public enum VerticalComparison: String, Equatable, Sendable {
    /// 既知の高さも楕円体高。差を精度の判定に使ってよい。
    case ellipsoidal
    /// 成果は標高。差にはジオイドが含まれる。
    case orthometricUncorrected
    case unavailable
}

public struct BenchmarkStatistics: Equatable, Sendable {
    public var sampleCount: Int
    public var meanLatitudeDegrees: Double
    public var meanLongitudeDegrees: Double
    public var meanEllipsoidalHeightMeters: Double?
    /// 平均位置と既知点の測地線距離。
    public var horizontalDifferenceMeters: Double
    /// 平均楕円体高から既知の高さを引いた値。上向きが正。
    public var verticalDifferenceMeters: Double?
    public var verticalComparison: VerticalComparison
    /// 平均位置からの東西・南北の標本標準偏差を合成した距離。
    public var horizontalStdMeters: Double
    /// 平均位置からの水平距離の95%。
    public var horizontal95Meters: Double
    public var verticalStdMeters: Double?
    public var vertical95Meters: Double?
    public var meanReportedHorizontalMeters: Double?
    public var meanReportedVerticalMeters: Double?
    /// 報告の平均が、平均位置の実際のずれより小さい。
    public var horizontalOptimistic: Bool?
    /// 楕円体高どうしのときだけ。標高との差では判定しない。
    public var verticalOptimistic: Bool?
    public var horizontalEpochs: Int
    public var horizontalEpochsOutside: Int
    /// 68%の円の外が32%を超えた。
    public var horizontal68Optimistic: Bool?
    public var verticalEpochs: Int
    public var verticalEpochsOutside: Int
    public var vertical68Optimistic: Bool?

    public static func make(point: ControlPoint, samples: [BenchmarkSample]) -> BenchmarkStatistics? {
        let usable = samples.filter { $0.position.isPlottable }
        guard !usable.isEmpty else { return nil }
        var east: [Double] = []
        var north: [Double] = []
        east.reserveCapacity(usable.count)
        north.reserveCapacity(usable.count)
        for sample in usable {
            guard let geodesic = GRS80Geodesic.inverse(
                latitude1: point.latitudeDegrees,
                longitude1: point.longitudeDegrees,
                latitude2: sample.position.latitudeDegrees,
                longitude2: sample.position.longitudeDegrees
            ) else { continue }
            east.append(geodesic.eastMeters)
            north.append(geodesic.northMeters)
        }
        guard east.count == usable.count, !east.isEmpty else { return nil }
        let meanEast = mean(east)
        let meanNorth = mean(north)
        let horizontalDifference = GeoMath.hypotenuse(meanEast, meanNorth)
        let meanCoordinate: (latitude: Double, longitude: Double)
        if horizontalDifference == 0 {
            meanCoordinate = (point.latitudeDegrees, point.longitudeDegrees)
        } else if let moved = GRS80Geodesic.direct(
            latitude: point.latitudeDegrees,
            longitude: point.longitudeDegrees,
            azimuthDegrees: GeoMath.degrees(fromRadians: GeoMath.arctangent(meanEast, meanNorth)),
            distanceMeters: horizontalDifference
        ) {
            meanCoordinate = moved
        } else {
            return nil
        }

        let heights = usable.compactMap { $0.position.ellipsoidalHeightMeters }.filter(\.isFinite)
        let meanHeight = heights.isEmpty ? nil : mean(heights)
        let knownEllipsoidal = point.comparableEllipsoidalHeightMeters
        let verticalComparison: VerticalComparison
        let verticalDifference: Double?
        if let meanHeight, let knownEllipsoidal {
            verticalComparison = .ellipsoidal
            verticalDifference = meanHeight - knownEllipsoidal
        } else if let meanHeight, point.heightKind == .orthometric, let known = point.heightMeters, known.isFinite {
            verticalComparison = .orthometricUncorrected
            verticalDifference = meanHeight - known
        } else {
            verticalComparison = .unavailable
            verticalDifference = nil
        }

        let eastResidual = east.map { $0 - meanEast }
        let northResidual = north.map { $0 - meanNorth }
        let radial = zip(eastResidual, northResidual).map { GeoMath.hypotenuse($0, $1) }
        let horizontalStd = GeoMath.hypotenuse(sampleStd(east), sampleStd(north))
        let horizontal95 = percentile95(radial)

        let verticalStd: Double?
        let vertical95: Double?
        if let meanHeight, heights.count == usable.count {
            let residual = heights.map { abs($0 - meanHeight) }
            verticalStd = sampleStd(heights)
            vertical95 = percentile95(residual)
        } else {
            verticalStd = nil
            vertical95 = nil
        }

        let reportedHorizontal = usable.map(\.position.horizontalAccuracyMeters).filter { $0.isFinite && $0 >= 0 }
        let meanReportedHorizontal = reportedHorizontal.isEmpty ? nil : mean(reportedHorizontal)
        let horizontalOptimistic = meanReportedHorizontal.map { $0 < horizontalDifference }

        var horizontalEpochs = 0
        var horizontalOutside = 0
        for (index, sample) in usable.enumerated() {
            let accuracy = sample.position.horizontalAccuracyMeters
            guard accuracy.isFinite, accuracy >= 0 else { continue }
            horizontalEpochs += 1
            if GeoMath.hypotenuse(east[index], north[index]) > accuracy {
                horizontalOutside += 1
            }
        }
        let horizontal68 = fractionOptimistic(outside: horizontalOutside, epochs: horizontalEpochs)

        let reportedVertical = usable.compactMap(\.position.verticalAccuracyMeters).filter { $0.isFinite && $0 >= 0 }
        let meanReportedVertical = reportedVertical.isEmpty ? nil : mean(reportedVertical)
        let verticalOptimistic: Bool?
        if verticalComparison == .ellipsoidal, let verticalDifference, let meanReportedVertical {
            verticalOptimistic = meanReportedVertical < abs(verticalDifference)
        } else {
            verticalOptimistic = nil
        }

        var verticalEpochs = 0
        var verticalOutside = 0
        if let knownEllipsoidal {
            for sample in usable {
                guard let height = sample.position.ellipsoidalHeightMeters, height.isFinite,
                      let accuracy = sample.position.verticalAccuracyMeters, accuracy.isFinite, accuracy >= 0 else {
                    continue
                }
                verticalEpochs += 1
                if abs(height - knownEllipsoidal) > accuracy {
                    verticalOutside += 1
                }
            }
        }
        let vertical68 = verticalComparison == .ellipsoidal
            ? fractionOptimistic(outside: verticalOutside, epochs: verticalEpochs)
            : nil

        return BenchmarkStatistics(
            sampleCount: usable.count,
            meanLatitudeDegrees: meanCoordinate.latitude,
            meanLongitudeDegrees: meanCoordinate.longitude,
            meanEllipsoidalHeightMeters: meanHeight,
            horizontalDifferenceMeters: horizontalDifference,
            verticalDifferenceMeters: verticalDifference,
            verticalComparison: verticalComparison,
            horizontalStdMeters: horizontalStd,
            horizontal95Meters: horizontal95,
            verticalStdMeters: verticalStd,
            vertical95Meters: vertical95,
            meanReportedHorizontalMeters: meanReportedHorizontal,
            meanReportedVerticalMeters: meanReportedVertical,
            horizontalOptimistic: horizontalOptimistic,
            verticalOptimistic: verticalOptimistic,
            horizontalEpochs: horizontalEpochs,
            horizontalEpochsOutside: horizontalOutside,
            horizontal68Optimistic: horizontal68,
            verticalEpochs: verticalEpochs,
            verticalEpochsOutside: verticalOutside,
            vertical68Optimistic: vertical68
        )
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

    static func percentile95(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    private static func fractionOptimistic(outside: Int, epochs: Int) -> Bool? {
        guard epochs > 0 else { return nil }
        return Double(outside) / Double(epochs) > 0.32
    }
}

public enum BenchmarkText {
    public static func meters(_ value: Double) -> String {
        "\(FixedNumber.string(value, fractionDigits: 2))m"
    }

    public static func signedMeters(_ value: Double) -> String {
        let body = FixedNumber.string(abs(value), fractionDigits: 2)
        if value > 0 { return "+\(body)m" }
        if value < 0 { return "−\(body)m" }
        return "\(body)m"
    }

    public static func spread(std: Double, percentile95: Double) -> String {
        "ばらつき \(meters(std)) / 95% \(meters(percentile95))"
    }

    public static func horizontalOptimism(_ statistics: BenchmarkStatistics) -> String {
        guard let reported = statistics.meanReportedHorizontalMeters else {
            return "水平の報告精度が無いので、楽観かどうかは出せません。"
        }
        let claim = "報告した水平精度の平均は \(meters(reported))。"
        switch statistics.horizontalOptimistic {
        case true:
            return claim + "実際のずれより楽観的です。"
        case false:
            return claim + "実際のずれを包んでいます。"
        case nil:
            return claim
        }
    }

    public static func verticalNote(_ statistics: BenchmarkStatistics) -> String {
        switch statistics.verticalComparison {
        case .ellipsoidal:
            guard let difference = statistics.verticalDifferenceMeters else { return "高さの差は出せません。" }
            var text = "高さの差 \(signedMeters(difference))（楕円体高どうし）。"
            if let optimistic = statistics.verticalOptimistic {
                text += optimistic ? "報告は楽観的です。" : "報告は差を包んでいます。"
            }
            return text
        case .orthometricUncorrected:
            guard let difference = statistics.verticalDifferenceMeters else { return "高さの差は出せません。" }
            return "高さの差 \(signedMeters(difference))。楕円体高から成果の標高を引いた値で、ジオイドを含むので精度の判定には使いません。"
        case .unavailable:
            return "既知の高さが無いので、高さの差は出せません。"
        }
    }

    public static func coverage68(outside: Int, epochs: Int) -> String {
        guard epochs > 0 else { return "68%の円は比べられません。" }
        return "68%の円の外 \(outside)/\(epochs)。"
    }
}

public enum BenchmarkCSV {
    public static func render(recorder: BenchmarkRecorder, statistics: BenchmarkStatistics) -> String {
        var lines = [
            "kind,point_id,point_name,time_utc,fix_time_utc,latitude_deg,longitude_deg,ellipsoidal_height_m,horizontal_accuracy_m,vertical_accuracy_m,horizontal_error_m,vertical_error_m,note"
        ]
        let knownEllipsoidal = recorder.point.comparableEllipsoidalHeightMeters
        let summaryNote = summaryNote(statistics)
        lines.append([
            "summary",
            csv(recorder.point.id),
            csv(recorder.point.name),
            csv(iso8601(recorder.startedAt)),
            "",
            csv(number(statistics.meanLatitudeDegrees, digits: 8)),
            csv(number(statistics.meanLongitudeDegrees, digits: 8)),
            csv(statistics.meanEllipsoidalHeightMeters.map { number($0, digits: 3) } ?? ""),
            csv(statistics.meanReportedHorizontalMeters.map { number($0, digits: 3) } ?? ""),
            csv(statistics.meanReportedVerticalMeters.map { number($0, digits: 3) } ?? ""),
            csv(number(statistics.horizontalDifferenceMeters, digits: 3)),
            csv(statistics.verticalDifferenceMeters.map { number($0, digits: 3) } ?? ""),
            csv(summaryNote)
        ].joined(separator: ","))
        for sample in recorder.samples {
            let geodesic = GRS80Geodesic.inverse(
                latitude1: recorder.point.latitudeDegrees,
                longitude1: recorder.point.longitudeDegrees,
                latitude2: sample.position.latitudeDegrees,
                longitude2: sample.position.longitudeDegrees
            )
            let vertical: String
            if let height = sample.position.ellipsoidalHeightMeters {
                if let knownEllipsoidal {
                    vertical = number(height - knownEllipsoidal, digits: 3)
                } else if recorder.point.heightKind == .orthometric, let known = recorder.point.heightMeters {
                    vertical = number(height - known, digits: 3)
                } else {
                    vertical = ""
                }
            } else {
                vertical = ""
            }
            lines.append([
                "sample",
                csv(recorder.point.id),
                csv(recorder.point.name),
                csv(iso8601(sample.loggedAt)),
                csv(iso8601(sample.position.timestamp)),
                csv(number(sample.position.latitudeDegrees, digits: 8)),
                csv(number(sample.position.longitudeDegrees, digits: 8)),
                csv(sample.position.ellipsoidalHeightMeters.map { number($0, digits: 3) } ?? ""),
                csv(sample.position.hasValidHorizontalAccuracy ? number(sample.position.horizontalAccuracyMeters, digits: 3) : ""),
                csv(sample.position.verticalAccuracyMeters.map { number($0, digits: 3) } ?? ""),
                csv(geodesic.map { number($0.distanceMeters, digits: 3) } ?? ""),
                csv(vertical),
                ""
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func summaryNote(_ statistics: BenchmarkStatistics) -> String {
        let optimism: String
        switch statistics.horizontalOptimistic {
        case true: optimism = "horizontal_optimistic"
        case false: optimism = "horizontal_covers"
        case nil: optimism = "horizontal_unknown"
        }
        return "\(optimism); std=\(number(statistics.horizontalStdMeters, digits: 3)); p95=\(number(statistics.horizontal95Meters, digits: 3))"
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func number(_ value: Double, digits: Int) -> String {
        FixedNumber.string(value, fractionDigits: digits)
    }

    private static func csv(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return value
    }
}
