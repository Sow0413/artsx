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
    /// 段階0の iPhone だけで付く。ポール高ではない。
    public var stature: StatureRecord?
    /// アンテナ補正のあとの楕円体高。詳細記録に残す。
    public var surveyEllipsoidalMeters: Double?
    /// 標高。楕円体高からジオイド高を引いた値。
    public var orthometricHeightMeters: Double?
    public var geoidUndulationMeters: Double?
    public var geoidModel: String?

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
        stage: PositionStage,
        stature: StatureRecord? = nil,
        surveyEllipsoidalMeters: Double? = nil,
        orthometricHeightMeters: Double? = nil,
        geoidUndulationMeters: Double? = nil,
        geoidModel: String? = nil
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
        self.stature = stature
        self.surveyEllipsoidalMeters = surveyEllipsoidalMeters
        self.orthometricHeightMeters = orthometricHeightMeters
        self.geoidUndulationMeters = geoidUndulationMeters
        self.geoidModel = geoidModel
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        solution = try container.decode(FixQuality.self, forKey: .solution)
        solutionLabel = try container.decode(String.self, forKey: .solutionLabel)
        satellites = try container.decodeIfPresent([SatelliteCount].self, forKey: .satellites) ?? []
        satelliteCount = try container.decodeIfPresent(Int.self, forKey: .satelliteCount)
        pdop = try container.decodeIfPresent(Double.self, forKey: .pdop)
        horizontalAccuracyMeters = try container.decode(Double.self, forKey: .horizontalAccuracyMeters)
        verticalAccuracyMeters = try container.decodeIfPresent(Double.self, forKey: .verticalAccuracyMeters)
        correctionAgeSeconds = try container.decodeIfPresent(Double.self, forKey: .correctionAgeSeconds)
        correctionSource = try container.decodeIfPresent(String.self, forKey: .correctionSource)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        durationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .durationSeconds)
        epochCount = try container.decodeIfPresent(Int.self, forKey: .epochCount)
        receiver = try container.decode(ReceiverKind.self, forKey: .receiver)
        stage = try container.decode(PositionStage.self, forKey: .stage)
        stature = try container.decodeIfPresent(StatureRecord.self, forKey: .stature)
        surveyEllipsoidalMeters = try container.decodeIfPresent(Double.self, forKey: .surveyEllipsoidalMeters)
        orthometricHeightMeters = try container.decodeIfPresent(Double.self, forKey: .orthometricHeightMeters)
        geoidUndulationMeters = try container.decodeIfPresent(Double.self, forKey: .geoidUndulationMeters)
        geoidModel = try container.decodeIfPresent(String.self, forKey: .geoidModel)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(solution, forKey: .solution)
        try container.encode(solutionLabel, forKey: .solutionLabel)
        try container.encode(satellites, forKey: .satellites)
        try container.encodeIfPresent(satelliteCount, forKey: .satelliteCount)
        try container.encodeIfPresent(pdop, forKey: .pdop)
        try container.encode(horizontalAccuracyMeters, forKey: .horizontalAccuracyMeters)
        try container.encodeIfPresent(verticalAccuracyMeters, forKey: .verticalAccuracyMeters)
        try container.encodeIfPresent(correctionAgeSeconds, forKey: .correctionAgeSeconds)
        try container.encodeIfPresent(correctionSource, forKey: .correctionSource)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(epochCount, forKey: .epochCount)
        try container.encode(receiver, forKey: .receiver)
        try container.encode(stage, forKey: .stage)
        try container.encodeIfPresent(stature, forKey: .stature)
        try container.encodeIfPresent(surveyEllipsoidalMeters, forKey: .surveyEllipsoidalMeters)
        try container.encodeIfPresent(orthometricHeightMeters, forKey: .orthometricHeightMeters)
        try container.encodeIfPresent(geoidUndulationMeters, forKey: .geoidUndulationMeters)
        try container.encodeIfPresent(geoidModel, forKey: .geoidModel)
    }

    private enum CodingKeys: String, CodingKey {
        case solution, solutionLabel, satellites, satelliteCount, pdop
        case horizontalAccuracyMeters, verticalAccuracyMeters, correctionAgeSeconds, correctionSource
        case observedAt, durationSeconds, epochCount, receiver, stage, stature
        case surveyEllipsoidalMeters, orthometricHeightMeters, geoidUndulationMeters, geoidModel
    }

    public static func snapshot(
        position: GeodeticPosition,
        stage: PositionStage,
        durationSeconds: TimeInterval?,
        epochCount: Int?,
        stature profile: StatureProfile? = nil,
        sight: SightSample? = nil
    ) -> ObservationCondition {
        let record = profile.flatMap { StatureMath.record(profile: $0, deviceHeight: position.ellipsoidalHeightMeters, sight: sight) }
            .flatMap { StatureMath.applies(stage: stage, receiver: position.receiver) ? $0 : nil }
        let base = record?.groundHeightMeters ?? position.ellipsoidalHeightMeters
        let height = SurveyHeight.resolve(
            ellipsoidalMeters: base,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            meanSeaLevelMeters: position.meanSeaLevelMeters,
            deviceEllipsoidalMeters: position.ellipsoidalHeightMeters
        )
        return ObservationCondition(
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
            stage: stage,
            stature: record,
            surveyEllipsoidalMeters: height.ellipsoidalMeters,
            orthometricHeightMeters: height.orthometricMeters,
            geoidUndulationMeters: height.geoidMeters,
            geoidModel: height.model
        )
    }

    public mutating func setElevation(from position: GeodeticPosition, baseEllipsoidal: Double?) {
        let height = SurveyHeight.resolve(
            ellipsoidalMeters: baseEllipsoidal,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            meanSeaLevelMeters: position.meanSeaLevelMeters,
            deviceEllipsoidalMeters: position.ellipsoidalHeightMeters
        )
        surveyEllipsoidalMeters = height.ellipsoidalMeters
        orthometricHeightMeters = height.orthometricMeters
        geoidUndulationMeters = height.geoidMeters
        geoidModel = height.model
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
        var lines = [
            "解 \(solutionLabel)",
            "衛星 \(satelliteNote)",
            "PDOP \(pdopText)",
            "水平 \(CoordinateText.accuracyMeters(horizontalAccuracyMeters))、高さ \(vertical)",
            "補正の遅れ \(age)、補正元 \(source)",
            "観測 \(Self.stamp.string(from: observedAt))、\(seconds)、\(epochs)",
            "機器 \(receiver.label)、段階\(stage.rawValue)"
        ]
        if let stature {
            lines.append("\(stature.screenLabel)（\(stature.holdTitle)）")
            if let note = stature.sightNote {
                lines.append(note)
            }
        }
        if let orthometric = orthometricHeightMeters {
            lines.append("標高 \(SurveyHeight.meters(orthometric))m")
        }
        if let ellipsoidal = surveyEllipsoidalMeters ?? stature?.groundHeightMeters {
            lines.append("楕円体高 \(SurveyHeight.meters(ellipsoidal))m")
        }
        if let geoidModel {
            lines.append(geoidModel)
        }
        return lines
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
