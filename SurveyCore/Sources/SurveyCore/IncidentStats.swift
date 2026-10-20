import Foundation

/// P510 で全プロジェクトを足すときの1行。アプリの件数表と、集計スクリプトが同じ列を読む。
public struct IncidentStatRow: Codable, Equatable, Sendable {
    public static let schema = "incident-stat/1"
    public static let columns = [
        "schema", "source", "record_id", "project_id", "project_name", "occurred_at",
        "work_kind", "time_band", "weather", "distance_m", "machine_kind", "role",
        "latitude", "longitude", "level", "party"
    ]

    public var schema: String
    public var source: String
    public var recordID: String
    public var projectID: String
    public var projectName: String
    public var occurredAt: Date
    public var workKind: String
    public var timeBand: String
    public var weather: String
    public var distanceMeters: Double?
    public var machineKind: String
    public var role: String
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var level: String
    /// 匿名化するときは役割だけ。個人名は入れない。
    public var party: String

    public init(
        schema: String = IncidentStatRow.schema,
        source: String,
        recordID: String,
        projectID: String,
        projectName: String,
        occurredAt: Date,
        workKind: String,
        timeBand: String,
        weather: String,
        distanceMeters: Double?,
        machineKind: String,
        role: String,
        latitudeDegrees: Double?,
        longitudeDegrees: Double?,
        level: String,
        party: String
    ) {
        self.schema = schema
        self.source = source
        self.recordID = recordID
        self.projectID = projectID
        self.projectName = projectName
        self.occurredAt = occurredAt
        self.workKind = workKind
        self.timeBand = timeBand
        self.weather = weather
        self.distanceMeters = distanceMeters
        self.machineKind = machineKind
        self.role = role
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.level = level
        self.party = party
    }
}

public struct IncidentStatCount: Equatable, Sendable {
    public var key: String
    public var count: Int

    public init(key: String, count: Int) {
        self.key = key
        self.count = count
    }
}

public struct IncidentHeatCell: Equatable, Sendable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var count: Int
    public var radiusMeters: Double

    public init(latitudeDegrees: Double, longitudeDegrees: Double, count: Int, radiusMeters: Double) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.count = count
        self.radiusMeters = radiusMeters
    }
}

public enum IncidentWeather: String, CaseIterable, Sendable {
    case clear = "晴れ"
    case cloud = "曇り"
    case rain = "雨"
    case snow = "雪"
    case unknown = "不明"
}

public enum IncidentTimeBand: String, CaseIterable, Sendable {
    case lateNight = "深夜"
    case early = "早朝"
    case morning = "午前"
    case afternoon = "午後"
    case evening = "夕方"
    case night = "夜間"

    public static func of(_ date: Date, timeZone: TimeZone = IncidentStats.tokyo) -> IncidentTimeBand {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<8: return .early
        case 8..<12: return .morning
        case 12..<17: return .afternoon
        case 17..<19: return .evening
        case 19..<24: return .night
        default: return .lateNight
        }
    }
}

public enum IncidentStats {
    public static let anonymizeByDefault = true
    public static let heatCellMeters = 25.0
    public static let fileName = "統計.csv"
    public static let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? TimeZone(secondsFromGMT: 9 * 3600)!

    public static func machineKind(preset: String?, radiusMeters: Double?) -> String {
        if let preset, let named = MachineCatalog.named(preset) { return named.label }
        if let preset, !preset.isEmpty { return preset }
        if let radiusMeters, radiusMeters > 0 {
            return "半径\(String(format: "%.1f", MachineReach.roundTenths(radiusMeters)))m"
        }
        return "不明"
    }

    public static func rows(
        project: SurveyProject,
        incidents: [IncidentRecord],
        proximity: [ProximityEvent],
        anonymize: Bool,
        timeZone: TimeZone = tokyo
    ) -> [IncidentStatRow] {
        let machine = machineKind(preset: project.machinePreset, radiusMeters: project.machineRadiusMeters)
        let fallbackWeather = nonempty(project.weather) ?? "不明"
        var rows = incidents.map { incidentRow($0, machine: machine, fallbackWeather: fallbackWeather, anonymize: anonymize, timeZone: timeZone) }
        rows += proximity.compactMap { proximityRow($0, project: project, machine: machine, fallbackWeather: fallbackWeather, anonymize: anonymize, timeZone: timeZone) }
        return rows.sorted { $0.occurredAt < $1.occurredAt }
    }

    public static func load(project: SurveyProject, at root: URL, anonymize: Bool) -> [IncidentStatRow] {
        rows(
            project: project,
            incidents: IncidentBook.sealed(projectName: project.name, at: root),
            proximity: ProximityLog.load(projectName: project.name, at: root),
            anonymize: anonymize
        )
    }

    public static func counts(_ rows: [IncidentStatRow], by key: (IncidentStatRow) -> String) -> [IncidentStatCount] {
        var totals: [String: Int] = [:]
        for row in rows {
            let name = key(row)
            totals[name, default: 0] += 1
        }
        return totals.map { IncidentStatCount(key: $0.key, count: $0.value) }.sorted { $0.key < $1.key }
    }

    public static func countsByWork(_ rows: [IncidentStatRow]) -> [IncidentStatCount] {
        counts(rows) { $0.workKind }
    }

    public static func countsByTime(_ rows: [IncidentStatRow]) -> [IncidentStatCount] {
        let order = IncidentTimeBand.allCases.map(\.rawValue)
        return counts(rows) { $0.timeBand }.sorted { lhs, rhs in
            (order.firstIndex(of: lhs.key) ?? 0) < (order.firstIndex(of: rhs.key) ?? 0)
        }
    }

    /// 約25mの升にまとめる。座標の無い行は地図に出さない。
    public static func heat(_ rows: [IncidentStatRow], cellMeters: Double = heatCellMeters) -> [IncidentHeatCell] {
        let placed = rows.filter { row in
            guard let latitude = row.latitudeDegrees, let longitude = row.longitudeDegrees else { return false }
            return latitude.isFinite && longitude.isFinite
        }
        guard let origin = placed.first?.latitudeDegrees, cellMeters > 0 else { return [] }
        let latStep = cellMeters / 111_320
        let cosine = max(0.2, abs(GeoMath.cosine(origin * .pi / 180)))
        let lonStep = cellMeters / (111_320 * cosine)
        var buckets: [String: (lat: Double, lon: Double, count: Int)] = [:]
        for row in placed {
            let latitude = row.latitudeDegrees ?? 0
            let longitude = row.longitudeDegrees ?? 0
            let latIndex = Int((latitude / latStep).rounded())
            let lonIndex = Int((longitude / lonStep).rounded())
            let key = "\(latIndex),\(lonIndex)"
            if var bucket = buckets[key] {
                bucket.count += 1
                buckets[key] = bucket
            } else {
                buckets[key] = (Double(latIndex) * latStep, Double(lonIndex) * lonStep, 1)
            }
        }
        return buckets.values.map {
            IncidentHeatCell(
                latitudeDegrees: $0.lat,
                longitudeDegrees: $0.lon,
                count: $0.count,
                radiusMeters: cellMeters * 0.55
            )
        }.sorted { $0.count > $1.count }
    }

    public static func csv(_ rows: [IncidentStatRow]) -> String {
        var lines = [IncidentStatRow.columns.joined(separator: ",")]
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for row in rows {
            let distance = row.distanceMeters.map { String(format: "%.1f", MachineReach.roundTenths($0)) } ?? ""
            let latitude = row.latitudeDegrees.map { String(format: "%.8f", $0) } ?? ""
            let longitude = row.longitudeDegrees.map { String(format: "%.8f", $0) } ?? ""
            let fields = [
                row.schema, row.source, row.recordID, row.projectID, row.projectName,
                formatter.string(from: row.occurredAt), row.workKind, row.timeBand, row.weather,
                distance, row.machineKind, row.role, latitude, longitude, row.level, row.party
            ]
            lines.append(fields.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// 派生ファイル。インシデント本体は書き換えない。
    public static func writeCSV(_ rows: [IncidentStatRow], projectName: String, at root: URL) throws -> URL {
        let project = try ProjectStore.projectDirectory(projectName, at: root)
        let folder = project.appendingPathComponent("記録簿", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try Data(csv(rows).utf8).write(to: url)
        return url
    }

    public static func roleLabel(selfRole: CrewRole, other: CrewRole?) -> String {
        guard let other, other != selfRole else { return selfRole.label }
        return "\(selfRole.label)×\(other.label)"
    }

    private static func incidentRow(
        _ record: IncidentRecord,
        machine: String,
        fallbackWeather: String,
        anonymize: Bool,
        timeZone: TimeZone
    ) -> IncidentStatRow {
        let selfParty = record.parties.first
        let others = record.parties.dropFirst()
        let closest = others.min { ($0.distanceMeters ?? .greatestFiniteMagnitude) < ($1.distanceMeters ?? .greatestFiniteMagnitude) }
        let role = roleLabel(selfRole: selfParty?.role ?? .worker, other: closest?.role)
        let names = record.parties.map(\.name).filter { !$0.isEmpty }.joined(separator: " ")
        return IncidentStatRow(
            source: "incident",
            recordID: record.id.uuidString,
            projectID: record.projectID,
            projectName: record.projectName,
            occurredAt: record.occurredAt,
            workKind: nonempty(record.work.kind) ?? "不明",
            timeBand: IncidentTimeBand.of(record.occurredAt, timeZone: timeZone).rawValue,
            weather: nonempty(record.weather) ?? fallbackWeather,
            distanceMeters: closest?.distanceMeters,
            machineKind: machine,
            role: role,
            latitudeDegrees: selfParty?.latitudeDegrees,
            longitudeDegrees: selfParty?.longitudeDegrees,
            level: record.trigger.label,
            party: anonymize ? role : (names.isEmpty ? role : names)
        )
    }

    private static func proximityRow(
        _ event: ProximityEvent,
        project: SurveyProject,
        machine: String,
        fallbackWeather: String,
        anonymize: Bool,
        timeZone: TimeZone
    ) -> IncidentStatRow? {
        guard event.level == .alarm || event.level == .caution else { return nil }
        let role = roleLabel(selfRole: event.selfRole, other: event.otherRole)
        let party = anonymize ? role : event.otherName
        return IncidentStatRow(
            source: "proximity",
            recordID: event.id.uuidString,
            projectID: event.projectID.isEmpty ? project.id : event.projectID,
            projectName: project.name,
            occurredAt: event.startedAt,
            workKind: "不明",
            timeBand: IncidentTimeBand.of(event.startedAt, timeZone: timeZone).rawValue,
            weather: fallbackWeather,
            distanceMeters: event.closestMeters,
            machineKind: machine,
            role: role,
            latitudeDegrees: event.latitudeDegrees,
            longitudeDegrees: event.longitudeDegrees,
            level: event.level == .alarm ? "警報" : "注意",
            party: party.isEmpty ? role : party
        )
    }

    private static func nonempty(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func csvField(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") || text.contains("\n") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }
}

/// 集計CSVをP510へ渡す口。サーバーは動かさない。
public final class IncidentStatsRelayStub {
    public var isReachable: Bool
    public private(set) var received: [String] = []

    public init(reachable: Bool) {
        self.isReachable = reachable
    }

    public func submit(csv: String) -> IncidentDelivery {
        guard isReachable else { return .pending }
        received.append(csv)
        return .sent
    }
}
