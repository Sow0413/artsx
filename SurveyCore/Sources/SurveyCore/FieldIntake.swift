import Foundation

public enum IntakeKind: String, Equatable, Sendable {
    case drawing
    case pdf
    case sima
    case list
    case unknown
}

/// 高さの列が2つあって札がないとき、どちらが GL / FH か。0 始まり。
public struct HeightColumnMap: Equatable, Sendable {
    public var groundColumn: Int?
    public var formationColumn: Int?

    public init(groundColumn: Int?, formationColumn: Int?) {
        self.groundColumn = groundColumn
        self.formationColumn = formationColumn
    }
}

public struct IntakeResult: Equatable, Sendable {
    public var kind: IntakeKind
    public var needsHeightMap: Bool
    public var columnCount: Int
    public var points: [FieldPoint]
    public var note: String
    public var text: String

    public init(
        kind: IntakeKind,
        needsHeightMap: Bool,
        columnCount: Int,
        points: [FieldPoint],
        note: String,
        text: String
    ) {
        self.kind = kind
        self.needsHeightMap = needsHeightMap
        self.columnCount = columnCount
        self.points = points
        self.note = note
        self.text = text
    }
}

public enum FieldIntake {
    public static let defaultZone = 7

    public static func detect(data: Data, fileName: String) -> IntakeKind {
        let ext = fileExtension(fileName)
        if ext == "pdf" || data.starts(with: Data("%PDF".utf8)) { return .pdf }
        if ext == "dxf" || ext == "sfc" { return .drawing }
        guard let text = decode(data) else { return .unknown }
        if isSIMA(text) { return .sima }
        if isDXF(text) { return .drawing }
        if coordinateRowCount(text) > 0 { return .list }
        return .unknown
    }

    public static func read(data: Data, fileName: String, zone: Int, heightMap: HeightColumnMap?) -> IntakeResult {
        let kind = detect(data: data, fileName: fileName)
        let text = decode(data) ?? ""
        switch kind {
        case .sima:
            return finish(parseSIMA(text), kind: .sima, zone: zone, heightMap: heightMap, text: text, anchor: .grid, origin: .sima)
        case .list:
            return finish(parseList(text), kind: .list, zone: zone, heightMap: heightMap, text: text, anchor: .geographic, origin: .list)
        default:
            return IntakeResult(kind: kind, needsHeightMap: false, columnCount: 0, points: [], note: "", text: text)
        }
    }

    static func decode(_ data: Data) -> String? {
        if let text = String(data: data, encoding: .utf8) { return text }
        #if os(Linux)
        return nil
        #else
        return String(data: data, encoding: .shiftJIS)
        #endif
    }

    private struct Draft {
        var name: String
        var base: String
        var northing: Double
        var easting: Double
        var latitude: Double?
        var longitude: Double?
        var ground: Double?
        var formation: Double?
        var plain: Double?
        var unlabeled: [Double]
        var ambiguous: Bool
    }

    private static func finish(
        _ drafts: [Draft],
        kind: IntakeKind,
        zone: Int,
        heightMap: HeightColumnMap?,
        text: String,
        anchor: PlaneAnchor,
        origin: FieldPointOrigin
    ) -> IntakeResult {
        var rows = drafts
        if let heightMap {
            for index in rows.indices where rows[index].ambiguous {
                apply(heightMap, to: &rows[index])
            }
        }
        let needs = rows.contains { $0.ambiguous }
        let columns = rows.map { $0.unlabeled.count }.max() ?? 0
        if needs {
            return IntakeResult(
                kind: kind,
                needsHeightMap: true,
                columnCount: max(columns, 2),
                points: [],
                note: "GL と FH を選んでください。",
                text: text
            )
        }
        let merged = mergeRoles(rows)
        let points = locate(merged, zone: zone, anchor: anchor, origin: origin)
        let note = points.isEmpty ? "点を読めませんでした。" : "\(points.count)点"
        return IntakeResult(kind: kind, needsHeightMap: false, columnCount: 0, points: points, note: note, text: text)
    }

    private static func apply(_ map: HeightColumnMap, to draft: inout Draft) {
        if let column = map.groundColumn, draft.unlabeled.indices.contains(column) {
            draft.ground = draft.unlabeled[column]
        }
        if let column = map.formationColumn, column != map.groundColumn, draft.unlabeled.indices.contains(column) {
            draft.formation = draft.unlabeled[column]
        }
        var leftover: [Double] = []
        for (index, value) in draft.unlabeled.enumerated() where index != map.groundColumn && index != map.formationColumn {
            leftover.append(value)
        }
        if leftover.count == 1, draft.plain == nil { draft.plain = leftover[0] }
        draft.unlabeled = []
        draft.ambiguous = false
    }

    private static func mergeRoles(_ drafts: [Draft]) -> [Draft] {
        var merged: [Draft] = []
        for draft in drafts {
            let onlyGround = draft.ground != nil && draft.formation == nil && draft.plain == nil && draft.unlabeled.isEmpty
            let onlyFormation = draft.formation != nil && draft.ground == nil && draft.plain == nil && draft.unlabeled.isEmpty
            if onlyGround || onlyFormation,
               let index = merged.firstIndex(where: { other in
                   other.base == draft.base &&
                       GeoMath.hypotenuse(other.northing - draft.northing, other.easting - draft.easting) <= 0.05 &&
                       (onlyGround ? other.ground == nil : other.formation == nil)
               }) {
                if onlyGround { merged[index].ground = draft.ground }
                if onlyFormation { merged[index].formation = draft.formation }
                merged[index].name = draft.base
                continue
            }
            merged.append(draft)
        }
        return merged
    }

    private static func locate(_ drafts: [Draft], zone: Int, anchor: PlaneAnchor, origin: FieldPointOrigin) -> [FieldPoint] {
        var used: [String: Int] = [:]
        var points: [FieldPoint] = []
        for draft in drafts {
            let north: Double
            let east: Double
            let latitude: Double
            let longitude: Double
            switch anchor {
            case .grid:
                guard let geo = PlaneRectangular.inverse(
                    northingMeters: draft.northing,
                    eastingMeters: draft.easting,
                    zone: zone
                ) else { continue }
                north = draft.northing
                east = draft.easting
                latitude = geo.latitudeDegrees
                longitude = geo.longitudeDegrees
            case .geographic:
                guard let lat = draft.latitude, let lon = draft.longitude,
                      let plane = PlaneRectangular.forward(latitudeDegrees: lat, longitudeDegrees: lon, zone: zone) else { continue }
                north = plane.northingMeters
                east = plane.eastingMeters
                latitude = lat
                longitude = lon
            }
            let name = unique(draft.name.isEmpty ? draft.base : draft.name, used: &used)
            points.append(FieldPoint(
                id: name,
                name: name,
                northingMeters: north,
                eastingMeters: east,
                zone: zone,
                latitudeDegrees: latitude,
                longitudeDegrees: longitude,
                groundLevelMeters: draft.ground,
                formationHeightMeters: draft.formation,
                heightMeters: draft.plain,
                origin: origin,
                anchor: anchor
            ))
        }
        return points
    }

    private static func unique(_ name: String, used: inout [String: Int]) -> String {
        let base = name.isEmpty ? "点" : name
        let seen = used[base, default: 0]
        used[base] = seen + 1
        return seen == 0 ? base : "\(base)-\(seen + 1)"
    }

    private static func parseSIMA(_ text: String) -> [Draft] {
        var drafts: [Draft] = []
        for line in lines(text) {
            let cells = splitComma(line)
            guard let head = cells.first?.uppercased(), head == "A01", cells.count >= 5 else { continue }
            guard let northing = number(cells[3]), let easting = number(cells[4]) else { continue }
            let rawName = cells.count > 2 ? cells[2] : ""
            let named = splitName(rawName.isEmpty ? "\(drafts.count + 1)" : rawName)
            var draft = heights(Array(cells.dropFirst(5)), nameRole: named.role)
            draft.name = named.role == nil ? named.base : rawName
            draft.base = named.base
            draft.northing = northing
            draft.easting = easting
            if named.role != nil, draft.ground == nil, draft.formation == nil, draft.unlabeled.count == 1 {
                assign(named.role!, draft.unlabeled[0], to: &draft)
                draft.unlabeled = []
            }
            draft.ambiguous = draft.unlabeled.count >= 2 && draft.ground == nil && draft.formation == nil
            drafts.append(draft)
        }
        return drafts
    }

    private static func parseList(_ text: String) -> [Draft] {
        let rows = lines(text).map { splitRow($0) }.filter { !$0.isEmpty }
        guard let first = rows.first else { return [] }
        let header = headerMap(first)
        let body = header == nil ? rows : Array(rows.dropFirst())
        var drafts: [Draft] = []
        for (offset, row) in body.enumerated() {
            guard let located = latLon(row, header: header) else { continue }
            let rawName = header?.name.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? located.name
            let named = splitName(rawName.isEmpty ? "\(offset + 1)" : rawName)
            var draft = Draft(
                name: named.base,
                base: named.base,
                northing: 0,
                easting: 0,
                latitude: located.latitude,
                longitude: located.longitude,
                ground: nil,
                formation: nil,
                plain: nil,
                unlabeled: [],
                ambiguous: false
            )
            if let header {
                if let column = header.ground, row.indices.contains(column), let value = number(row[column]) {
                    draft.ground = value
                }
                if let column = header.formation, row.indices.contains(column), let value = number(row[column]) {
                    draft.formation = value
                }
                if let column = header.height, row.indices.contains(column), let value = number(row[column]) {
                    draft.plain = value
                }
            } else {
                draft.unlabeled = located.extra
                if located.extra.count == 1 { draft.plain = located.extra[0]; draft.unlabeled = [] }
                if located.extra.count >= 2 { draft.ambiguous = true }
            }
            if let role = named.role, draft.ground == nil, draft.formation == nil, let only = draft.plain {
                assign(role, only, to: &draft)
                draft.plain = nil
            }
            drafts.append(draft)
        }
        return drafts
    }

    private struct Header {
        var name: Int?
        var latitude: Int?
        var longitude: Int?
        var height: Int?
        var ground: Int?
        var formation: Int?
    }

    private struct Located {
        var name: String
        var latitude: Double
        var longitude: Double
        var extra: [Double]
    }

    private static func headerMap(_ cells: [String]) -> Header? {
        var header = Header()
        var known = false
        for (index, cell) in cells.enumerated() {
            let key = normalize(cell)
            switch key {
            case "点名", "名称", "NAME", "名":
                header.name = index; known = true
            case "緯度", "LAT", "LATITUDE":
                header.latitude = index; known = true
            case "経度", "LON", "LNG", "LONGITUDE":
                header.longitude = index; known = true
            case "高さ", "標高", "H", "Z", "HEIGHT":
                header.height = index; known = true
            case "GL", "地盤", "地盤高":
                header.ground = index; known = true
            case "FH", "計画", "計画高", "仕上", "仕上高", "仕上がり", "仕上がり高":
                header.formation = index; known = true
            default:
                break
            }
        }
        guard known, header.latitude != nil, header.longitude != nil else { return nil }
        return header
    }

    private static func latLon(_ row: [String], header: Header?) -> Located? {
        if let header, let latColumn = header.latitude, let lonColumn = header.longitude,
           row.indices.contains(latColumn), row.indices.contains(lonColumn),
           let latitude = angle(row[latColumn]), let longitude = angle(row[lonColumn]),
           abs(latitude) <= 90, abs(longitude) <= 180 {
            let name = header.name.flatMap { row.indices.contains($0) ? row[$0] : nil } ?? ""
            return Located(name: name, latitude: latitude, longitude: longitude, extra: [])
        }
        let angles = row.enumerated().compactMap { index, cell -> (Int, Double)? in
            guard let value = angle(cell) else { return nil }
            return (index, value)
        }
        guard angles.count >= 2 else { return nil }
        for left in 0..<(angles.count - 1) {
            let lat = angles[left].1
            let lon = angles[left + 1].1
            guard abs(lat) <= 90, abs(lon) <= 180 else { continue }
            let nameIndex = angles[left].0 > 0 ? 0 : nil
            let name = nameIndex.flatMap { row.indices.contains($0) && angle(row[$0]) == nil ? row[$0] : nil } ?? ""
            let used = Set([angles[left].0, angles[left + 1].0])
            let extra = row.enumerated().compactMap { index, cell -> Double? in
                guard !used.contains(index), index != (nameIndex ?? -1) || name.isEmpty else { return nil }
                guard index > angles[left + 1].0 else { return nil }
                return number(cell)
            }
            return Located(name: name, latitude: lat, longitude: lon, extra: extra)
        }
        return nil
    }

    private static func heights(_ tokens: [String], nameRole: HeightRole?) -> Draft {
        var draft = Draft(
            name: "",
            base: "",
            northing: 0,
            easting: 0,
            latitude: nil,
            longitude: nil,
            ground: nil,
            formation: nil,
            plain: nil,
            unlabeled: [],
            ambiguous: false
        )
        var pending: HeightRole?
        for token in tokens {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if let role = role(of: trimmed) {
                if pending == nil, let last = draft.unlabeled.last {
                    draft.unlabeled.removeLast()
                    assign(role, last, to: &draft)
                } else {
                    pending = role
                }
                continue
            }
            if let value = number(trimmed) {
                if let role = pending {
                    assign(role, value, to: &draft)
                    pending = nil
                } else {
                    draft.unlabeled.append(value)
                }
            }
        }
        if let role = nameRole, draft.ground == nil, draft.formation == nil, draft.unlabeled.count == 1, draft.plain == nil {
            assign(role, draft.unlabeled[0], to: &draft)
            draft.unlabeled = []
        }
        if draft.unlabeled.count == 1, draft.plain == nil, draft.ground == nil, draft.formation == nil {
            draft.plain = draft.unlabeled[0]
            draft.unlabeled = []
        }
        return draft
    }

    private static func assign(_ role: HeightRole, _ value: Double, to draft: inout Draft) {
        switch role {
        case .ground: draft.ground = value
        case .formation: draft.formation = value
        }
    }

    private enum HeightRole {
        case ground
        case formation
    }

    private static func role(of token: String) -> HeightRole? {
        switch normalize(token) {
        case "GL", "地盤", "地盤高", "現況", "現況高": return .ground
        case "FH", "計画", "計画高", "仕上", "仕上高", "仕上がり", "仕上がり高", "FL": return .formation
        default: return nil
        }
    }

    private static func splitName(_ name: String) -> (base: String, role: HeightRole?) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let japanese: [(String, HeightRole)] = [
            ("仕上がり高", .formation), ("計画高", .formation), ("仕上高", .formation),
            ("地盤高", .ground), ("仕上", .formation), ("地盤", .ground)
        ]
        for (suffix, role) in japanese where trimmed.hasSuffix(suffix) {
            let base = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "-_・ （()）"))
            if !base.isEmpty { return (base, role) }
        }
        let upper = trimmed.uppercased()
        for (suffix, role) in [("GL", HeightRole.ground), ("FH", HeightRole.formation)] where upper.hasSuffix(suffix) {
            let base = String(trimmed.dropLast(suffix.count))
            guard let last = base.last else { continue }
            let separated = "-_・ （()）".contains(last) || last.isNumber
            let cleaned = base.trimmingCharacters(in: CharacterSet(charactersIn: "-_・ （()）"))
            if separated, !cleaned.isEmpty { return (cleaned, role) }
        }
        return (trimmed, nil)
    }

    private static func isSIMA(_ text: String) -> Bool {
        lines(text).contains { line in
            let cells = splitComma(line)
            return cells.first?.uppercased() == "A01"
        }
    }

    private static func isDXF(_ text: String) -> Bool {
        text.contains("SECTION") && (text.contains("ENTITIES") || text.contains("HEADER"))
    }

    private static func coordinateRowCount(_ text: String) -> Int {
        parseList(text).count
    }

    private static func lines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "，", with: ",")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("*") }
    }

    private static func splitComma(_ line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func splitRow(_ line: String) -> [String] {
        if line.contains(",") || line.contains("\t") {
            let separator: Character = line.contains(",") ? "," : "\t"
            return line.split(separator: separator, omittingEmptySubsequences: false).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        }
        return line.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static func number(_ token: String) -> Double? {
        let cleaned = token.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    private static func angle(_ token: String) -> Double? {
        let raw = token.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty { return nil }
        let upper = raw.uppercased()
        var sign = 1.0
        if upper.hasPrefix("S") || upper.hasPrefix("W") || upper.hasSuffix("S") || upper.hasSuffix("W") {
            sign = -1
        }
        let stripped = upper
            .replacingOccurrences(of: "N", with: "")
            .replacingOccurrences(of: "S", with: "")
            .replacingOccurrences(of: "E", with: "")
            .replacingOccurrences(of: "W", with: "")
            .trimmingCharacters(in: .whitespaces)
        if let value = number(stripped) { return sign * value }
        let patterns = [
            #"([+-]?\d+(?:\.\d+)?)\s*[°度]\s*(\d+(?:\.\d+)?)\s*['′分]\s*(\d+(?:\.\d+)?)"#,
            #"([+-]?\d+(?:\.\d+)?)[:D](\d+(?:\.\d+)?)[:M'](\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
                  match.numberOfRanges == 4,
                  let degrees = capture(stripped, match, 1),
                  let minutes = capture(stripped, match, 2),
                  let seconds = capture(stripped, match, 3) else { continue }
            return sign * (degrees + minutes / 60 + seconds / 3600)
        }
        return nil
    }

    private static func capture(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> Double? {
        guard let range = Range(match.range(at: index), in: text) else { return nil }
        return Double(text[range])
    }

    private static func normalize(_ token: String) -> String {
        token.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "（", with: "")
            .replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .uppercased()
    }

    private static func fileExtension(_ fileName: String) -> String {
        (fileName as NSString).pathExtension.lowercased()
    }
}
