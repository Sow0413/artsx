import Foundation

/// 取った点。下見の座標は捨てず、あとから測量点の座標に乗せ替えられる。
public struct FieldObservation: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var workID: String
    /// 取ったときの位置と精度。乗せ替えても変えない。
    public var captured: GeodeticPosition
    /// トラバー点など、あとから採用した座標。
    public var adopted: GeodeticPosition?

    public init(id: UUID = UUID(), name: String, workID: String, captured: GeodeticPosition, adopted: GeodeticPosition? = nil) {
        self.id = id
        self.name = name
        self.workID = workID
        self.captured = captured
        self.adopted = adopted
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
