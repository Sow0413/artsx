import Foundation

/// 座標簿の CSV / SIMA を読み戻す。書き出しと同じ列を受け取る。
public enum CoordinateExchange {
    public static func parse(data: Data, filename: String, zone: Int) -> [CoordinateBookEntry] {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return [] }
        if filename.lowercased().hasSuffix("sima") || text.contains("A01,") {
            return parseSIMA(text, zone: zone)
        }
        return parseCSV(text, zone: zone)
    }

    public static func parseCSV(_ text: String, zone: Int) -> [CoordinateBookEntry] {
        let rows = text.split(whereSeparator: \.isNewline).map { String($0) }.filter { !$0.isEmpty }
        guard let header = rows.first else { return [] }
        let columns = split(header)
        let index = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        return rows.dropFirst().compactMap { row in
            let fields = split(row)
            func field(_ name: String) -> String {
                guard let offset = index[name], offset < fields.count else { return "" }
                return fields[offset]
            }
            let name = field("点名")
            guard !name.isEmpty else { return nil }
            let latitude = Double(field("緯度"))
            let longitude = Double(field("経度"))
            let north = Double(field("北"))
            let east = Double(field("東"))
            let geo: (latitudeDegrees: Double, longitudeDegrees: Double)?
            if let latitude, let longitude {
                geo = (latitude, longitude)
            } else if let north, let east {
                geo = PlaneRectangular.inverse(northingMeters: north, eastingMeters: east, zone: zone)
            } else {
                geo = nil
            }
            guard let geo else { return nil }
            return CoordinateBookEntry(
                name: name,
                latitudeDegrees: geo.latitudeDegrees,
                longitudeDegrees: geo.longitudeDegrees,
                ellipsoidalHeightMeters: Double(field("楕円体高")),
                horizontalAccuracyMeters: Double(field("水平精度m")) ?? 0,
                verticalAccuracyMeters: Double(field("高さ精度m")),
                satelliteCount: nil,
                fixDurationSeconds: Double(field("秒数")) ?? 0,
                recordedAt: ObservationCondition.stamp.date(from: field("観測時刻")) ?? Date(),
                kind: field("種類").nilIfEmpty,
                source: field("出典").nilIfEmpty,
                solution: solution(field("解")),
                receiverLabel: field("機器").nilIfEmpty,
                satelliteNote: field("衛星").nilIfEmpty
            )
        }
    }

    /// 最初の平面点。緯度経度だけの CSV は nil。
    public static func firstPlane(data: Data, filename: String) -> (northing: Double, easting: Double)? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else { return nil }
        if text.contains("latitude_deg") { return nil }
        if filename.lowercased().hasSuffix("sima") || text.contains("A01,") {
            for raw in text.split(whereSeparator: \.isNewline) {
                let fields = split(String(raw))
                guard fields.first == "A01", fields.count >= 5,
                      let north = Double(fields[3]), let east = Double(fields[4]) else { continue }
                return (north, east)
            }
            return nil
        }
        let rows = text.split(whereSeparator: \.isNewline).map(String.init).filter { !$0.isEmpty }
        guard let header = rows.first else { return nil }
        let columns = split(header)
        let index = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        guard let northIndex = index["北"], let eastIndex = index["東"] else { return nil }
        for row in rows.dropFirst() {
            let fields = split(row)
            guard northIndex < fields.count, eastIndex < fields.count,
                  let north = Double(fields[northIndex]), let east = Double(fields[eastIndex]) else { continue }
            return (north, east)
        }
        return nil
    }

    public static func parseSIMA(_ text: String, zone: Int) -> [CoordinateBookEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let fields = split(String(raw))
            guard fields.first == "A01", fields.count >= 6 else { return nil }
            let name = fields[2]
            guard !name.isEmpty, let north = Double(fields[3]), let east = Double(fields[4]) else { return nil }
            guard let geo = PlaneRectangular.inverse(northingMeters: north, eastingMeters: east, zone: zone) else { return nil }
            return CoordinateBookEntry(
                name: name,
                latitudeDegrees: geo.latitudeDegrees,
                longitudeDegrees: geo.longitudeDegrees,
                ellipsoidalHeightMeters: nil,
                horizontalAccuracyMeters: 0,
                verticalAccuracyMeters: nil,
                satelliteCount: nil,
                fixDurationSeconds: 0,
                recordedAt: Date(),
                kind: "取込",
                source: "SIMA"
            )
        }
    }

    private static func split(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private static func solution(_ label: String) -> FixQuality? {
        switch label {
        case "FIX": return .rtkFix
        case "FLOAT": return .float
        case "DGPS": return .dgps
        case "CLAS": return .clas
        case "単独": return .standalone
        default: return nil
        }
    }
}

/// プロジェクトと座標簿だけを1ファイルにする。再インストールのあとは、このファイルから戻す。
public struct BasicBackup: Codable, Equatable, Sendable {
    public static let format = "artsx-basic-1"
    public var format: String
    public var projects: [Item]

    public struct Item: Codable, Equatable, Sendable {
        public var project: SurveyProject
        public var points: [CoordinateBookEntry]

        public init(project: SurveyProject, points: [CoordinateBookEntry]) {
            self.project = project
            self.points = points
        }
    }

    public init(format: String = BasicBackup.format, projects: [Item]) {
        self.format = format
        self.projects = projects
    }

    public static func capture(at root: URL) -> BasicBackup {
        let projects = (try? ProjectStore.list(at: root)) ?? []
        let items = projects.map { project in
            Item(project: project, points: ProjectStore.coordinateBookEntries(projectName: project.name, at: root))
        }
        return BasicBackup(projects: items)
    }

    public func data() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }

    public static func load(_ data: Data) -> BasicBackup? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BasicBackup.self, from: data)
    }

    @discardableResult
    public func restore(at root: URL) throws -> Int {
        guard format == Self.format else { throw ProjectStoreError.unreadable }
        var count = 0
        for item in projects {
            if (try? ProjectStore.projectDirectory(item.project.name, at: root)) == nil {
                _ = try ProjectStore.create(name: item.project.name, at: root, now: item.project.createdAt)
            }
            try ProjectStore.save(item.project, at: root)
            if !item.points.isEmpty {
                try ProjectStore.saveCoordinates(item.points, projectName: item.project.name, at: root)
            }
            count += item.points.count
        }
        return count
    }
}

/// 今の RTK 位置から、座標簿の点または入力した座標までの案内。姿勢センサは使わない。
public struct BasicStakeoutGuide: Equatable, Sendable {
    public var distanceMeters: Double
    public var azimuthDegrees: Double
    public var northMeters: Double
    public var eastMeters: Double
    public var heightMeters: Double?
    public var solution: FixQuality

    public var line: String {
        let height: String
        if let heightMeters {
            height = String(format: " 高 %+.2fm", heightMeters)
        } else {
            height = " 高さは比較しません"
        }
        let quality: String
        switch solution {
        case .rtkFix: quality = "FIX"
        case .float: quality = "FLOAT"
        case .dgps: quality = "DGPS"
        case .clas: quality = "CLAS"
        case .standalone, .none: quality = "単独"
        }
        return String(
            format: "%.2fm 方位 %.1f° 北 %+.2fm 東 %+.2fm%@ %@",
            distanceMeters, azimuthDegrees, northMeters, eastMeters, height, quality
        )
    }
}

public enum BasicStakeout {
    public static func guide(from position: GeodeticPosition, to target: CoordinateBookEntry, zone: Int) -> BasicStakeoutGuide? {
        guard let inverse = GRS80Geodesic.inverse(
            latitude1: position.latitudeDegrees,
            longitude1: position.longitudeDegrees,
            latitude2: target.latitudeDegrees,
            longitude2: target.longitudeDegrees
        ) else { return nil }
        guard let here = PlaneRectangular.forward(
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            zone: zone
        ), let there = PlaneRectangular.forward(
            latitudeDegrees: target.latitudeDegrees,
            longitudeDegrees: target.longitudeDegrees,
            zone: zone
        ) else { return nil }
        let height = position.ellipsoidalHeightMeters.flatMap { current in
            target.ellipsoidalHeightMeters.map { current - $0 }
        }
        return BasicStakeoutGuide(
            distanceMeters: inverse.distanceMeters,
            azimuthDegrees: inverse.azimuthDegrees,
            northMeters: there.northingMeters - here.northingMeters,
            eastMeters: there.eastingMeters - here.eastingMeters,
            heightMeters: height,
            solution: position.fixQuality
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
