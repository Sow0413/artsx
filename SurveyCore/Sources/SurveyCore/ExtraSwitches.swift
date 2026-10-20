import Foundation

/// 測量本体以外。全部オフが既定で、そのあいだは測量の画面に出さない。
public struct ExtraSwitches: Codable, Equatable, Sendable {
    public var pushToTalk: Bool
    public var proximity: Bool
    public var fall: Bool
    public var sos: Bool
    public var firstResponse: Bool
    public var accidentReport: Bool
    public var disaster: Bool
    public var mesh: Bool
    public var stats: Bool

    public init(
        pushToTalk: Bool = false,
        proximity: Bool = false,
        fall: Bool = false,
        sos: Bool = false,
        firstResponse: Bool = false,
        accidentReport: Bool = false,
        disaster: Bool = false,
        mesh: Bool = false,
        stats: Bool = false
    ) {
        self.pushToTalk = pushToTalk
        self.proximity = proximity
        self.fall = fall
        self.sos = sos
        self.firstResponse = firstResponse
        self.accidentReport = accidentReport
        self.disaster = disaster
        self.mesh = mesh
        self.stats = stats
    }

    public static let quiet = ExtraSwitches()

    /// 位置を近くへ出してよいのは、接近か災害をオンにしたときだけ。
    public var sharesLocation: Bool { proximity || disaster }

    /// 近くのセッションが要る機能。オフのあいだはセッションを始めない。
    public var usesNearby: Bool { pushToTalk || proximity || fall || sos || disaster || mesh }

    /// ヒヤリの記録を始める機能。オフなら軌跡の輪も回さない。
    public var recordsIncidents: Bool { proximity || fall || sos }

    /// どれか一つでもオンなら、測量画面は静かではない。
    public var quietScreen: Bool {
        !pushToTalk && !proximity && !fall && !sos && !firstResponse
            && !accidentReport && !disaster && !mesh && !stats
    }

    private enum CodingKeys: String, CodingKey {
        case pushToTalk, proximity, fall, sos, firstResponse, accidentReport, disaster, mesh, stats
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pushToTalk = try container.decodeIfPresent(Bool.self, forKey: .pushToTalk) ?? false
        proximity = try container.decodeIfPresent(Bool.self, forKey: .proximity) ?? false
        fall = try container.decodeIfPresent(Bool.self, forKey: .fall) ?? false
        sos = try container.decodeIfPresent(Bool.self, forKey: .sos) ?? false
        firstResponse = try container.decodeIfPresent(Bool.self, forKey: .firstResponse) ?? false
        accidentReport = try container.decodeIfPresent(Bool.self, forKey: .accidentReport) ?? false
        disaster = try container.decodeIfPresent(Bool.self, forKey: .disaster) ?? false
        mesh = try container.decodeIfPresent(Bool.self, forKey: .mesh) ?? false
        stats = try container.decodeIfPresent(Bool.self, forKey: .stats) ?? false
    }
}

public enum ExtraSwitchStore {
    public static let fileName = "おまけ.json"

    public static func load(from root: URL) -> ExtraSwitches {
        let url = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return .quiet }
        let decoder = JSONDecoder()
        return (try? decoder.decode(ExtraSwitches.self, from: data)) ?? .quiet
    }

    public static func save(_ switches: ExtraSwitches, to root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(switches)
        try data.write(to: root.appendingPathComponent(fileName), options: .atomic)
    }
}
