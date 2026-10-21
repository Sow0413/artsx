import Foundation

/// 取った点。下見の座標は捨てず、あとから測量点の座標に乗せ替えられる。
public struct FieldObservation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var workID: String
    /// 取ったときの位置と精度。乗せ替えても、補正を引いても変えない。
    public var captured: GeodeticPosition
    /// トラバー点など、あとから採用した座標。
    public var adopted: GeodeticPosition?
    /// 取得時に三角点補正を引いた座標。captured は残す。
    public var corrected: GeodeticPosition?
    public var appliedCorrectionID: UUID?
    /// 戻り点検で時刻比例に割り振った座標。
    public var closureAdjustment: ClosureAdjustment?
    /// 戻り点検で付けた要再測。座標は消さない。
    public var needsResurvey: Bool
    /// 基準点として、RTK FIX が切れずに続いていた秒数。普通の観測は nil。
    public var fixDurationSeconds: TimeInterval?
    /// その点の観測状況。古い記録には無い。
    public var condition: ObservationCondition?
    /// 取った現場。古い記録には無い。
    public var projectID: String?
    /// 水準器の簡易ターゲットは level。測量の一覧には出さない。
    public var origin: String?
    /// iPhone の平均。RTK ではない。
    public var phoneAverage: PhoneAverageStamp?
    /// この点に引いた iPhone の既知点合わせ。
    public var knownShift: KnownShiftStamp?

    public init(
        id: UUID = UUID(),
        name: String,
        workID: String,
        captured: GeodeticPosition,
        adopted: GeodeticPosition? = nil,
        corrected: GeodeticPosition? = nil,
        appliedCorrectionID: UUID? = nil,
        closureAdjustment: ClosureAdjustment? = nil,
        needsResurvey: Bool = false,
        fixDurationSeconds: TimeInterval? = nil,
        condition: ObservationCondition? = nil,
        projectID: String? = nil,
        origin: String? = nil,
        phoneAverage: PhoneAverageStamp? = nil,
        knownShift: KnownShiftStamp? = nil
    ) {
        self.id = id
        self.name = name
        self.workID = workID
        self.captured = captured
        self.adopted = adopted
        self.corrected = corrected
        self.appliedCorrectionID = appliedCorrectionID
        self.closureAdjustment = closureAdjustment
        self.needsResurvey = needsResurvey
        self.fixDurationSeconds = fixDurationSeconds
        self.condition = condition
        self.projectID = projectID
        self.origin = origin
        self.phoneAverage = phoneAverage
        self.knownShift = knownShift
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, workID, captured, adopted, corrected, appliedCorrectionID, closureAdjustment, needsResurvey, fixDurationSeconds, condition, projectID, origin, phoneAverage, knownShift
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        workID = try container.decode(String.self, forKey: .workID)
        captured = try container.decode(GeodeticPosition.self, forKey: .captured)
        adopted = try container.decodeIfPresent(GeodeticPosition.self, forKey: .adopted)
        corrected = try container.decodeIfPresent(GeodeticPosition.self, forKey: .corrected)
        appliedCorrectionID = try container.decodeIfPresent(UUID.self, forKey: .appliedCorrectionID)
        closureAdjustment = try container.decodeIfPresent(ClosureAdjustment.self, forKey: .closureAdjustment)
        needsResurvey = try container.decodeIfPresent(Bool.self, forKey: .needsResurvey) ?? false
        fixDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .fixDurationSeconds)
        condition = try container.decodeIfPresent(ObservationCondition.self, forKey: .condition)
        projectID = try container.decodeIfPresent(String.self, forKey: .projectID)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        phoneAverage = try container.decodeIfPresent(PhoneAverageStamp.self, forKey: .phoneAverage)
        knownShift = try container.decodeIfPresent(KnownShiftStamp.self, forKey: .knownShift)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(workID, forKey: .workID)
        try container.encode(captured, forKey: .captured)
        try container.encodeIfPresent(adopted, forKey: .adopted)
        try container.encodeIfPresent(corrected, forKey: .corrected)
        try container.encodeIfPresent(appliedCorrectionID, forKey: .appliedCorrectionID)
        try container.encodeIfPresent(closureAdjustment, forKey: .closureAdjustment)
        try container.encode(needsResurvey, forKey: .needsResurvey)
        try container.encodeIfPresent(fixDurationSeconds, forKey: .fixDurationSeconds)
        try container.encodeIfPresent(condition, forKey: .condition)
        try container.encodeIfPresent(projectID, forKey: .projectID)
        try container.encodeIfPresent(origin, forKey: .origin)
        try container.encodeIfPresent(phoneAverage, forKey: .phoneAverage)
        try container.encodeIfPresent(knownShift, forKey: .knownShift)
    }

    public var horizontalAccuracyAtCapture: Double { captured.horizontalAccuracyMeters }
    public var verticalAccuracyAtCapture: Double? { captured.verticalAccuracyMeters }

    public func rebase(onto traverse: GeodeticPosition) -> FieldObservation {
        var copy = self
        copy.adopted = traverse
        return copy
    }
}

public struct FieldObservationLog: Codable, Equatable, Sendable {
    public static let fileName = "field-observations.json"
    public var observations: [FieldObservation]

    public init(observations: [FieldObservation] = []) {
        self.observations = observations
    }

    public func appending(_ observation: FieldObservation) -> FieldObservationLog {
        var copy = self
        copy.observations.append(observation)
        return copy
    }

    public func replacing(_ observation: FieldObservation) -> FieldObservationLog {
        var copy = self
        guard let index = copy.observations.firstIndex(where: { $0.id == observation.id }) else { return copy }
        copy.observations[index] = observation
        return copy
    }

    public static func load(from directory: URL) -> FieldObservationLog {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(FieldObservationLog.self, from: data) else {
            return FieldObservationLog()
        }
        return saved
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}
