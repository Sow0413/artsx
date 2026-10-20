import Foundation

/// 成果の高さの種類。iPhone が出すのは楕円体高なので、標高とそのまま比べない。
public enum ControlHeightKind: String, Codable, Sendable, Equatable {
    case ellipsoidal
    case orthometric
    case unspecified
}

/// 三角点・水準点・電子基準点。現場パックの JSON も同じ形。
public struct ControlPoint: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var kind: String
    public var grade: String?
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double
    public var heightMeters: Double?
    /// 現場パックが楕円体高へ直した値。入っていれば高さの判定にこれを使う。
    public var ellipsoidalHeightMeters: Double?
    public var heightKind: ControlHeightKind
    public var sourceNote: String

    public init(
        id: String,
        name: String,
        kind: String,
        grade: String? = nil,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        heightMeters: Double? = nil,
        ellipsoidalHeightMeters: Double? = nil,
        heightKind: ControlHeightKind = .unspecified,
        sourceNote: String = ""
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.grade = grade
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.heightMeters = heightMeters
        self.ellipsoidalHeightMeters = ellipsoidalHeightMeters
        self.heightKind = heightKind
        self.sourceNote = sourceNote
    }

    /// 楕円体高として比べてよい高さ。標高だけしか無いときは nil。
    public var comparableEllipsoidalHeightMeters: Double? {
        if let ellipsoidalHeightMeters, ellipsoidalHeightMeters.isFinite {
            return ellipsoidalHeightMeters
        }
        if heightKind == .ellipsoidal, let heightMeters, heightMeters.isFinite {
            return heightMeters
        }
        return nil
    }
}

public struct ControlPointFile: Codable, Equatable, Sendable {
    public var source: String
    public var points: [ControlPoint]

    public init(source: String, points: [ControlPoint]) {
        self.source = source
        self.points = points
    }
}

public enum ControlPointError: Error, Equatable {
    case malformed
    case missingColumn(String)
}

public enum ControlPointCatalog {
    /// 現在地からこの距離以内も、画面の外でも地図に出す。
    public static let nearbyRadiusMeters = 50_000.0

    public static func loadJSON(_ data: Data) throws -> [ControlPoint] {
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(ControlPointFile.self, from: data) {
            return file.points
        }
        if let points = try? decoder.decode([ControlPoint].self, from: data) {
            return points
        }
        throw ControlPointError.malformed
    }

    /// 1行目は見出し。`id,name,kind,grade,latitude_deg,longitude_deg,height_m,height_kind,source_note`
    /// 任意列 `ellipsoidal_height_m`。
    public static func loadCSV(_ text: String) throws -> [ControlPoint] {
        let rows = CSVTable.rows(text).filter { row in
            row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        guard let header = rows.first else { return [] }
        let titles = header.map { $0.trimmingCharacters(in: .whitespaces) }
        func index(_ name: String) throws -> Int {
            guard let found = titles.firstIndex(of: name) else { throw ControlPointError.missingColumn(name) }
            return found
        }
        let idIndex = try index("id")
        let nameIndex = try index("name")
        let kindIndex = try index("kind")
        let latitudeIndex = try index("latitude_deg")
        let longitudeIndex = try index("longitude_deg")
        let gradeIndex = titles.firstIndex(of: "grade")
        let heightIndex = titles.firstIndex(of: "height_m")
        let kindHeightIndex = titles.firstIndex(of: "height_kind")
        let noteIndex = titles.firstIndex(of: "source_note")
        let ellipsoidalIndex = titles.firstIndex(of: "ellipsoidal_height_m")
        var points: [ControlPoint] = []
        for row in rows.dropFirst() {
            func field(_ index: Int?) -> String {
                guard let index, index < row.count else { return "" }
                return row[index].trimmingCharacters(in: .whitespaces)
            }
            guard idIndex < row.count, nameIndex < row.count, kindIndex < row.count else {
                throw ControlPointError.malformed
            }
            guard let latitude = Double(field(latitudeIndex)), let longitude = Double(field(longitudeIndex)) else {
                throw ControlPointError.malformed
            }
            let heightText = field(heightIndex)
            let ellipsoidalText = field(ellipsoidalIndex)
            let kindText = field(kindHeightIndex)
            let heightKind = kindText.isEmpty ? ControlHeightKind.unspecified : ControlHeightKind(rawValue: kindText)
            guard let heightKind else { throw ControlPointError.malformed }
            let grade = field(gradeIndex)
            points.append(ControlPoint(
                id: field(idIndex),
                name: field(nameIndex),
                kind: field(kindIndex),
                grade: grade.isEmpty ? nil : grade,
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                heightMeters: heightText.isEmpty ? nil : Double(heightText),
                ellipsoidalHeightMeters: ellipsoidalText.isEmpty ? nil : Double(ellipsoidalText),
                heightKind: heightKind,
                sourceNote: field(noteIndex)
            ))
        }
        return points
    }

    /// 画面に入っている点と、現在地から `radiusMeters` 以内の点。
    public static func visible(
        _ points: [ControlPoint],
        userLatitude: Double?,
        userLongitude: Double?,
        bounds: GeoBounds?,
        radiusMeters: Double = nearbyRadiusMeters
    ) -> [ControlPoint] {
        let hasUser = userLatitude != nil && userLongitude != nil
        let filtered = points.filter { point in
            if let bounds, bounds.contains(latitude: point.latitudeDegrees, longitude: point.longitudeDegrees) {
                return true
            }
            guard hasUser, let userLatitude, let userLongitude else { return false }
            guard let geodesic = GRS80Geodesic.inverse(
                latitude1: userLatitude,
                longitude1: userLongitude,
                latitude2: point.latitudeDegrees,
                longitude2: point.longitudeDegrees
            ) else { return false }
            return geodesic.distanceMeters <= radiusMeters
        }
        return filtered.sorted { lhs, rhs in
            guard hasUser, let userLatitude, let userLongitude else {
                return lhs.name < rhs.name
            }
            let left = GRS80Geodesic.inverse(
                latitude1: userLatitude,
                longitude1: userLongitude,
                latitude2: lhs.latitudeDegrees,
                longitude2: lhs.longitudeDegrees
            )?.distanceMeters ?? .greatestFiniteMagnitude
            let right = GRS80Geodesic.inverse(
                latitude1: userLatitude,
                longitude1: userLongitude,
                latitude2: rhs.latitudeDegrees,
                longitude2: rhs.longitudeDegrees
            )?.distanceMeters ?? .greatestFiniteMagnitude
            if left == right { return lhs.id < rhs.id }
            return left < right
        }
    }
}

enum CSVTable {
    static func rows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    let next = index + 1
                    if next < characters.count, characters[next] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    inQuotes = false
                    index += 1
                    continue
                }
                field.append(character)
                index += 1
                continue
            }
            if character == "\"", field.isEmpty {
                inQuotes = true
                index += 1
                continue
            }
            if character == "," {
                row.append(field)
                field = ""
                index += 1
                continue
            }
            if character == "\n" || character == "\r" {
                if character == "\r", index + 1 < characters.count, characters[index + 1] == "\n" {
                    index += 1
                }
                row.append(field)
                rows.append(row)
                row = []
                field = ""
                index += 1
                continue
            }
            field.append(character)
            index += 1
        }
        if inQuotes == false, !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}
