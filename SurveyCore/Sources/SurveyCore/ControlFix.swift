import Foundation

public struct ControlObservation: Sendable, Equatable {
    public var position: GeodeticPosition
    public var fixDurationSeconds: TimeInterval
    public var horizontalAccuracyMeters: Double
    public var verticalAccuracyMeters: Double?
    public var satelliteCount: Int?
    public var epochCount: Int

    public init(
        position: GeodeticPosition,
        fixDurationSeconds: TimeInterval,
        horizontalAccuracyMeters: Double,
        verticalAccuracyMeters: Double?,
        satelliteCount: Int?,
        epochCount: Int = 0
    ) {
        self.position = position
        self.fixDurationSeconds = fixDurationSeconds
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
        self.satelliteCount = satelliteCount
        self.epochCount = epochCount
    }
}

/// 基準点は RTK FIX が続いているあいだだけ記録できる。FLOAT と単独は始められない。
/// 観測の途中で FIX が切れたら、それまでの秒数は捨ててやり直す。
public struct ControlFixSession: Sendable, Equatable {
    public private(set) var fixBeganAt: Date?
    public private(set) var latest: GeodeticPosition?
    public private(set) var restarted = false
    public private(set) var epochCount = 0

    public init() {}

    /// 強制終了の直前まで続いていた FIX。秒数は開始時刻から数え直す。
    public init(restoring began: Date?, latest: GeodeticPosition?, epochCount: Int, restarted: Bool) {
        fixBeganAt = began
        self.latest = latest
        self.epochCount = epochCount
        self.restarted = restarted
    }

    public mutating func observe(_ position: GeodeticPosition, at time: Date) {
        latest = position
        if position.isTrustedRTKFix {
            if fixBeganAt == nil {
                fixBeganAt = time
                epochCount = 1
            } else {
                epochCount += 1
            }
            restarted = false
            return
        }
        if fixBeganAt != nil {
            fixBeganAt = nil
            epochCount = 0
            restarted = true
        }
    }

    /// 段階が下がったとき、続いている FIX の秒数を捨てる。測位そのものは止めない。
    public mutating func abort() {
        guard fixBeganAt != nil else { return }
        fixBeganAt = nil
        epochCount = 0
        restarted = true
    }

    public var canRecord: Bool {
        fixBeganAt != nil && latest?.isTrustedRTKFix == true
    }

    public func continuousSeconds(at now: Date) -> TimeInterval? {
        guard let began = fixBeganAt, latest?.isTrustedRTKFix == true else { return nil }
        return max(0, now.timeIntervalSince(began))
    }

    /// FIX が続いていないときは nil。切れたあとは、新しい FIX が付くまで nil。
    public func record(at now: Date) -> ControlObservation? {
        guard let latest, latest.isTrustedRTKFix, let seconds = continuousSeconds(at: now) else { return nil }
        return ControlObservation(
            position: latest,
            fixDurationSeconds: seconds,
            horizontalAccuracyMeters: latest.horizontalAccuracyMeters,
            verticalAccuracyMeters: latest.verticalAccuracyMeters,
            satelliteCount: latest.satelliteCount,
            epochCount: epochCount
        )
    }
}

public enum PointNamer {
    /// 半角アルファベットだけ。記録する名前は大文字。
    public static func normalizePrefix(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return trimmed.uppercased()
    }

    /// いちばん小さい空き番号。T1 と T3 があるときは T2。座標簿にある名前は使わない。
    public static func nextName(prefix raw: String, existing: Set<String>) -> String? {
        guard let prefix = normalizePrefix(raw) else { return nil }
        let used = Set(existing.map { $0.uppercased() })
        var number = 1
        while used.contains("\(prefix)\(number)") {
            number += 1
            if number > 100_000 { return nil }
        }
        return "\(prefix)\(number)"
    }
}

/// 点名の頭文字。記録が無いときは「共通」。記録ごとに別の頭文字を覚えておく。
public struct PointPrefixStore: Codable, Equatable, Sendable {
    public static let sharedKey = "共通"
    public static let fileName = "point-prefixes.json"
    public var activeKey: String
    public var prefixes: [String: String]

    public init(activeKey: String = PointPrefixStore.sharedKey, prefixes: [String: String] = [:]) {
        self.activeKey = activeKey
        self.prefixes = prefixes
    }

    public func prefix(for key: String?) -> String {
        prefixes[key ?? activeKey] ?? prefixes[activeKey] ?? ""
    }

    public static func load(from directory: URL) -> PointPrefixStore {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(PointPrefixStore.self, from: data) else {
            return PointPrefixStore()
        }
        return stored
    }

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// プロジェクトを開いていないときも、点名が飛ばせるように現場フォルダへ残す。
public enum SiteCoordinateBook {
    public static let fileName = "座標簿.json"

    public static func load(from directory: URL) -> [CoordinateBookEntry] {
        if FieldJournal.exists(in: directory) {
            let stored = FieldJournal(directory: directory).bookEntries()
            if !stored.isEmpty { return stored }
        }
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([CoordinateBookEntry].self, from: data)) ?? []
    }

    public static func append(_ entry: CoordinateBookEntry, to directory: URL) throws {
        try FieldJournal(directory: directory).upsertBook(entry)
    }
}
