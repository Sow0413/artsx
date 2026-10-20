import Foundation

/// 点を取ったときの観測状況。帳票にそのまま出す。
public struct ObservationCondition: Codable, Sendable, Equatable {
    public var solution: FixQuality
    public var solutionLabel: String
    public var satellites: [SatelliteCount]
    public var satelliteCount: Int?
    public var pdop: Double?
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double?
    public var correctionAgeSeconds: Double?
    public var correctionSource: String?
    public var observedAt: Date
    public var durationSeconds: TimeInterval?
    public var epochCount: Int?
    public var receiver: ReceiverKind
    public var stage: PositionStage

    public init(
        solution: FixQuality,
        solutionLabel: String,
        satellites: [SatelliteCount],
        satelliteCount: Int?,
        pdop: Double?,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        correctionAgeSeconds: Double?,
        correctionSource: String?,
        observedAt: Date,
        durationSeconds: TimeInterval?,
        epochCount: Int?,
        receiver: ReceiverKind,
        stage: PositionStage
    ) {
        self.solution = solution
        self.solutionLabel = solutionLabel
        self.satellites = satellites
        self.satelliteCount = satelliteCount
        self.pdop = pdop
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.correctionAgeSeconds = correctionAgeSeconds
        self.correctionSource = correctionSource
        self.observedAt = observedAt
        self.durationSeconds = durationSeconds
        self.epochCount = epochCount
        self.receiver = receiver
        self.stage = stage
    }

    public static func snapshot(
        position: GeodeticPosition,
        stage: PositionStage,
        durationSeconds: TimeInterval?,
        epochCount: Int?
    ) -> ObservationCondition {
        ObservationCondition(
            solution: position.fixQuality,
            solutionLabel: position.solutionLabel,
            satellites: position.satellites ?? [],
            satelliteCount: position.satelliteCount,
            pdop: position.pdop,
            horizontalAccuracyMeters: position.horizontalAccuracyMeters,
            verticalAccuracyMeters: position.verticalAccuracyMeters,
            correctionAgeSeconds: position.correctionAgeSeconds,
            correctionSource: position.correctionSource,
            observedAt: position.timestamp,
            durationSeconds: durationSeconds,
            epochCount: epochCount,
            receiver: position.receiver,
            stage: stage
        )
    }

    public var satelliteNote: String {
        if satellites.isEmpty {
            return satelliteCount.map { "\($0)" } ?? "—"
        }
        let parts = satellites.map { "\($0.system.label) \($0.count)" }.joined(separator: "、")
        let total = satelliteCount ?? satellites.reduce(0) { $0 + $1.count }
        return "\(total)（\(parts)）"
    }

    public var reportLines: [String] {
        let vertical = verticalAccuracyMeters.map { CoordinateText.accuracyMeters($0) } ?? "—"
        let age = correctionAgeSeconds.map { String(format: "%.1f秒", $0) } ?? "—"
        let source = correctionSource ?? "—"
        let seconds = durationSeconds.map { "\(Int($0.rounded()))秒" } ?? "—"
        let epochs = epochCount.map { "\($0)エポック" } ?? "—"
        let pdopText = pdop.map { String(format: "%.1f", $0) } ?? "—"
        return [
            "解 \(solutionLabel)",
            "衛星 \(satelliteNote)",
            "PDOP \(pdopText)",
            "水平 \(CoordinateText.accuracyMeters(horizontalAccuracyMeters))、高さ \(vertical)",
            "補正の遅れ \(age)、補正元 \(source)",
            "観測 \(Self.stamp.string(from: observedAt))、\(seconds)、\(epochs)",
            "機器 \(receiver.label)、段階\(stage.rawValue)"
        ]
    }

    static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

/// 同じ解が続いているあいだの秒数とエポック数。解が変わると数え直す。
public struct EpochWatch: Sendable, Equatable {
    public private(set) var quality: FixQuality?
    public private(set) var beganAt: Date?
    public private(set) var count = 0

    public init() {}

    public mutating func observe(_ position: GeodeticPosition) {
        if quality != position.fixQuality || beganAt == nil {
            quality = position.fixQuality
            beganAt = position.timestamp
            count = 1
            return
        }
        count += 1
    }

    public func duration(at time: Date) -> TimeInterval? {
        guard let beganAt else { return nil }
        return max(0, time.timeIntervalSince(beganAt))
    }
}
