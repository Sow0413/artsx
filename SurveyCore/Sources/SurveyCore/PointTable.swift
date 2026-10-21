import Foundation

/// 列の役割。測量の X は北、Y は東。
public enum PointColumnRole: String, Codable, CaseIterable, Sendable, Equatable {
    case name
    case northing
    case easting
    case latitude
    case longitude
    case height
    case ground
    case formation
    case note
    case ignore

    public var label: String {
        switch self {
        case .name: return "点名"
        case .northing: return "X(北)"
        case .easting: return "Y(東)"
        case .latitude: return "緯度"
        case .longitude: return "経度"
        case .height: return "標高"
        case .ground: return "GL"
        case .formation: return "FH"
        case .note: return "備考"
        case .ignore: return "無視"
        }
    }
}

public enum PointDelimiter: String, Codable, Sendable, Equatable {
    case comma
    case tab
    case space

    public var label: String {
        switch self {
        case .comma: return "カンマ"
        case .tab: return "タブ"
        case .space: return "空白"
        }
    }
}

public enum PointCoordinateKind: String, Codable, Sendable, Equatable {
    case geographic
    case plane
}

/// プロジェクトに覚えておく列の対応。列数が同じ次のファイルに使う。
public struct PointColumnMap: Codable, Equatable, Sendable {
    public var roles: [PointColumnRole]
    public var hasHeader: Bool

    public init(roles: [PointColumnRole], hasHeader: Bool) {
        self.roles = roles
        self.hasHeader = hasHeader
    }
}

public struct PointTableCell: Equatable, Sendable {
    public var text: String
    public var confidence: Double?

    public init(text: String, confidence: Double? = nil) {
        self.text = text
        self.confidence = confidence
    }

    public var isLowConfidence: Bool {
        guard let confidence else { return false }
        return confidence < PointTableReader.lowConfidence
    }
}

public struct PointRowIssue: Equatable, Sendable {
    /// `PointTable.rows` の番号。0 始まり。
    public var row: Int
    public var message: String

    public init(row: Int, message: String) {
        self.row = row
        self.message = message
    }
}

public struct PointTable: Equatable, Sendable {
    public var fileName: String
    public var encodingName: String
    public var delimiter: PointDelimiter
    public var hasHeader: Bool
    public var roles: [PointColumnRole]
    public var rows: [[PointTableCell]]
    public var kind: PointCoordinateKind
    public var axisWarning: String?
    public var issues: [PointRowIssue]

    public init(
        fileName: String,
        encodingName: String,
        delimiter: PointDelimiter,
        hasHeader: Bool,
        roles: [PointColumnRole],
        rows: [[PointTableCell]],
        kind: PointCoordinateKind = .geographic,
        axisWarning: String? = nil,
        issues: [PointRowIssue] = []
    ) {
        self.fileName = fileName
        self.encodingName = encodingName
        self.delimiter = delimiter
        self.hasHeader = hasHeader
        self.roles = roles
        self.rows = rows
        self.kind = kind
        self.axisWarning = axisWarning
        self.issues = issues
    }

    public var columnCount: Int {
        max(rows.map(\.count).max() ?? 0, roles.count)
    }
}

public struct PointTableOutcome: Equatable, Sendable {
    public var points: [FieldPoint]
    public var issues: [PointRowIssue]
    public var kind: PointCoordinateKind
    public var axisWarning: String?

    public init(points: [FieldPoint], issues: [PointRowIssue], kind: PointCoordinateKind, axisWarning: String?) {
        self.points = points
        self.issues = issues
        self.kind = kind
        self.axisWarning = axisWarning
    }
}

/// 用紙の1語。座標は Vision の正規化枠（下が 0）。
public struct PaperTextBox: Equatable, Sendable {
    public var text: String
    public var confidence: Double
    public var minX: Double
    public var maxX: Double
    public var midY: Double
    public var height: Double

    public init(text: String, confidence: Double, minX: Double, maxX: Double, midY: Double, height: Double) {
        self.text = text
        self.confidence = confidence
        self.minX = minX
        self.maxX = maxX
        self.midY = midY
        self.height = height
    }
}

/// 点名の末尾番号。K-1 の次は K-2。
public enum PointNameSequence {
    public static func next(after name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "1" }
        var digits = ""
        var index = trimmed.endIndex
        while index > trimmed.startIndex {
            let previous = trimmed.index(before: index)
            if trimmed[previous].isNumber {
                digits.insert(trimmed[previous], at: digits.startIndex)
                index = previous
            } else {
                break
            }
        }
        if digits.isEmpty { return trimmed + "2" }
        let prefix = String(trimmed[..<index])
        guard let value = Int(digits) else { return trimmed + "2" }
        let next = value + 1
        if String(next).count > digits.count { return prefix + String(next) }
        return prefix + String(format: "%0\(digits.count)d", next)
    }
}

/// OCR で崩れやすい数字。点名の文字は変えない。X と Y は入れ替えない。
public enum PointTextRepair {
    public static func repair(_ raw: String) -> String {
        var text = normalizeWidth(raw.trimmingCharacters(in: .whitespacesAndNewlines))
        let marks = ["−", "–", "—", "ー", "－"]
        for mark in marks {
            text = text.replacingOccurrences(of: mark, with: "-")
        }
        text = substituteLetters(text)
        if angle(text) != nil { return text }
        if looksLikeNumber(text) {
            let normalized = normalizeNumeric(text)
            if Double(normalized) != nil { return normalized }
        }
        return text
    }

    public static func number(_ raw: String) -> Double? {
        let text = repair(raw)
        if text.isEmpty { return nil }
        if let value = angle(text) { return value }
        guard let value = Double(text.replacingOccurrences(of: " ", with: "")), value.isFinite else { return nil }
        return value
    }

    static func normalizeWidth(_ raw: String) -> String {
        var result = ""
        for scalar in raw.unicodeScalars {
            switch scalar.value {
            case 0xFF10...0xFF19:
                if let ascii = Unicode.Scalar(scalar.value - 0xFF10 + 0x30) {
                    result.append(Character(ascii))
                }
            case 0xFF0E:
                result.append(".")
            case 0xFF0C:
                result.append(",")
            case 0xFF0B:
                result.append("+")
            case 0xFF0D:
                result.append("-")
            default:
                result.append(Character(scalar))
            }
        }
        return result
    }

    /// O と l は、数字以外の文字が無いときだけ直す。
    static func substituteLetters(_ text: String) -> String {
        let allowed: Set<Unicode.Scalar> = ["O", "o", "l", "I", "|"]
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard letters.allSatisfy({ allowed.contains($0) }) else { return text }
        var result = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "O", "o": result.append("0")
            case "l", "I", "|": result.append("1")
            default: result.append(Character(scalar))
            }
        }
        return result
    }

    static func looksLikeNumber(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789+-.,")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// 桁区切りのカンマは除く。3桁でないカンマは小数点にする。
    static func normalizeNumeric(_ token: String) -> String {
        let text = token.replacingOccurrences(of: " ", with: "")
        let commas = text.filter { $0 == "," }.count
        let dots = text.filter { $0 == "." }.count
        if commas > 0, dots > 0 {
            if let lastComma = text.lastIndex(of: ","), let lastDot = text.lastIndex(of: ".") {
                if lastComma > lastDot {
                    return text.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                }
                return text.replacingOccurrences(of: ",", with: "")
            }
        }
        if commas == 1, dots == 0 {
            let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            if parts.count == 2 {
                let whole = parts[0].replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "-", with: "")
                let fraction = parts[1]
                let thousands = fraction.count == 3 && (1...3).contains(whole.count) && fraction.allSatisfy(\.isNumber)
                if thousands { return text.replacingOccurrences(of: ",", with: "") }
                return text.replacingOccurrences(of: ",", with: ".")
            }
        }
        if commas > 1, dots == 0, text.range(of: #"^[+-]?\d{1,3}(,\d{3})+$"#, options: .regularExpression) != nil {
            return text.replacingOccurrences(of: ",", with: "")
        }
        return text.replacingOccurrences(of: ",", with: "")
    }

    static func angle(_ raw: String) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        let upper = trimmed.uppercased()
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
        if let value = Double(stripped) { return sign * value }
        let patterns = [
            #"([+-]?\d+(?:\.\d+)?)\s*[°度]\s*(\d+(?:\.\d+)?)?\s*['′分]?\s*(\d+(?:\.\d+)?)?"#,
            #"([+-]?\d+(?:\.\d+)?)[:D](\d+(?:\.\d+)?)[:M'](\d+(?:\.\d+)?)"#
        ]
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: stripped, range: NSRange(stripped.startIndex..., in: stripped)),
                  match.numberOfRanges >= 2,
                  let degrees = capture(stripped, match, 1) else { continue }
            let minutes = match.numberOfRanges > 2 ? (capture(stripped, match, 2) ?? 0) : 0
            let seconds = match.numberOfRanges > 3 ? (capture(stripped, match, 3) ?? 0) : 0
            if stripped.contains("°") || stripped.contains("度") || stripped.contains(":") || stripped.contains("'") || stripped.contains("′") {
                return sign * (degrees + minutes / 60 + seconds / 3600)
            }
        }
        return nil
    }

    private static func capture(_ text: String, _ match: NSTextCheckingResult, _ index: Int) -> Double? {
        let range = match.range(at: index)
        guard range.location != NSNotFound, let swift = Range(range, in: text) else { return nil }
        let token = text[swift]
        if token.isEmpty { return nil }
        return Double(token)
    }
}

enum PointTextEncoding {
    struct Decoded {
        var text: String
        var name: String
    }

    static func decode(_ data: Data) -> Decoded? {
        var payload = data
        if payload.count >= 3, payload[0] == 0xEF, payload[1] == 0xBB, payload[2] == 0xBF {
            payload = Data(payload.dropFirst(3))
            if let text = String(data: payload, encoding: .utf8) {
                return Decoded(text: text, name: "UTF-8")
            }
        }
        if let text = String(data: payload, encoding: .utf8) {
            return Decoded(text: text, name: "UTF-8")
        }
        if let text = ShiftJIS.decode(payload) {
            return Decoded(text: text, name: "Shift_JIS")
        }
        return nil
    }
}

/// CSV・タブ・空白、または用紙のマスを、同じ点の表にする。悪い行は残す。
public enum PointTableReader {
    public static let lowConfidence = 0.6
    public static let axisWarningText = "X 列の値が東向きの大きさです。X は北です。"

    public static func read(data: Data, fileName: String) -> PointTable? {
        guard let decoded = PointTextEncoding.decode(data) else { return nil }
        return read(text: decoded.text, encodingName: decoded.name, fileName: fileName)
    }

    public static func read(text: String, encodingName: String, fileName: String) -> PointTable? {
        let lines = sourceLines(text)
        guard !lines.isEmpty else { return nil }
        let delimiter = detectDelimiter(lines)
        let rows = lines.map { line in
            split(line, delimiter: delimiter).map { PointTableCell(text: PointTextRepair.repair($0)) }
        }
        return makeTable(rows: rows, delimiter: delimiter, encodingName: encodingName, fileName: fileName)
    }

    public static func table(from cells: [[PointTableCell]], fileName: String = "用紙") -> PointTable? {
        let repaired = cells.map { row in
            row.map { PointTableCell(text: PointTextRepair.repair($0.text), confidence: $0.confidence) }
        }
        return makeTable(rows: repaired, delimiter: .space, encodingName: "用紙", fileName: fileName)
    }

    /// 同じ高さの語を行にし、1行にまとまって読めた文字列はセルに分ける。
    public static func cells(from boxes: [PaperTextBox]) -> [[PointTableCell]] {
        let sorted = boxes.sorted { lhs, rhs in
            if abs(lhs.midY - rhs.midY) > 0.0001 { return lhs.midY > rhs.midY }
            return lhs.minX < rhs.minX
        }
        var grouped: [[PaperTextBox]] = []
        for box in sorted {
            if let index = grouped.indices.last {
                let anchor = grouped[index].map(\.midY).reduce(0, +) / Double(grouped[index].count)
                let height = max(grouped[index].map(\.height).max() ?? 0, box.height)
                if abs(anchor - box.midY) <= max(0.012, 0.6 * height) {
                    grouped[index].append(box)
                    continue
                }
            }
            grouped.append([box])
        }
        return grouped.map { row in
            let ordered = row.sorted { $0.minX < $1.minX }
            if ordered.count == 1, let only = ordered.first {
                let parts = splitLine(only.text)
                if parts.count >= 2 {
                    return parts.map { PointTableCell(text: PointTextRepair.repair($0), confidence: only.confidence) }
                }
            }
            return ordered.map { PointTableCell(text: PointTextRepair.repair($0.text), confidence: $0.confidence) }
        }
    }

    public static func containsCoordinates(_ text: String) -> Bool {
        guard let table = read(text: text, encodingName: "UTF-8", fileName: "") else { return false }
        return !assess(table, zone: FieldIntake.defaultZone).points.isEmpty
    }

    public static func evaluate(_ table: PointTable, zone: Int) -> PointTable {
        let outcome = assess(table, zone: zone)
        var copy = table
        copy.kind = outcome.kind
        copy.axisWarning = outcome.axisWarning
        copy.issues = outcome.issues
        return copy
    }

    public static func assess(_ table: PointTable, zone: Int) -> PointTableOutcome {
        let roles = padded(table.roles, width: table.columnCount)
        let kind = coordinateKind(roles: roles, rows: table.rows, hasHeader: table.hasHeader)
        var issues: [PointRowIssue] = []
        var points: [FieldPoint] = []
        var used: [String: Int] = [:]
        var northings: [Double] = []
        var eastings: [Double] = []
        let start = table.hasHeader ? 1 : 0
        if table.rows.count <= start {
            return PointTableOutcome(
                points: [],
                issues: [PointRowIssue(row: 0, message: "行がありません。")],
                kind: kind,
                axisWarning: nil
            )
        }
        for index in start..<table.rows.count {
            let row = table.rows[index]
            if row.allSatisfy({ $0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { continue }
            switch parsed(row, roles: roles, kind: kind, zone: zone) {
            case let .issue(message):
                issues.append(PointRowIssue(row: index, message: message))
            case let .point(draft):
                if kind == .plane {
                    northings.append(draft.northing)
                    eastings.append(draft.easting)
                }
                let sequence = index - start + 1
                let name = unique(draft.name.isEmpty ? "\(sequence)" : draft.name, used: &used)
                points.append(FieldPoint(
                    id: "list-\(sequence)-\(name)",
                    name: name,
                    northingMeters: draft.northing,
                    eastingMeters: draft.easting,
                    zone: zone,
                    latitudeDegrees: draft.latitude,
                    longitudeDegrees: draft.longitude,
                    groundLevelMeters: draft.ground ?? draft.height,
                    formationHeightMeters: draft.formation,
                    heightMeters: draft.height,
                    origin: .list,
                    anchor: kind == .plane ? .grid : .geographic,
                    snapLabel: draft.note
                ))
            }
        }
        let warning = kind == .plane ? axisWarning(northings: northings, eastings: eastings, zone: zone) : nil
        return PointTableOutcome(points: points, issues: issues, kind: kind, axisWarning: warning)
    }

    private struct Draft {
        var name: String
        var northing: Double
        var easting: Double
        var latitude: Double
        var longitude: Double
        var height: Double?
        var ground: Double?
        var formation: Double?
        var note: String?
    }

    private enum Parsed {
        case point(Draft)
        case issue(String)
    }

    private static func parsed(_ row: [PointTableCell], roles: [PointColumnRole], kind: PointCoordinateKind, zone: Int) -> Parsed {
        switch kind {
        case .geographic:
            guard roles.contains(.latitude), roles.contains(.longitude) else {
                return .issue("緯度と経度の列がありません。")
            }
            guard let latitude = required(row, roles, .latitude, missing: "緯度が読めません。", out: "緯度が範囲外です。", limit: 90) else {
                return .issue(lastRequiredMessage(row, roles, .latitude, missing: "緯度が読めません。", out: "緯度が範囲外です。", limit: 90))
            }
            guard let longitude = required(row, roles, .longitude, missing: "経度が読めません。", out: "経度が範囲外です。", limit: 180) else {
                return .issue(lastRequiredMessage(row, roles, .longitude, missing: "経度が読めません。", out: "経度が範囲外です。", limit: 180))
            }
            guard let fix = ManualPoint.geographic(latitude: latitude, longitude: longitude, zone: zone) else {
                return .issue("平面直角にできません。")
            }
            switch heights(row, roles: roles) {
            case let .issue(message):
                return .issue(message)
            case let .values(height, ground, formation, note, name):
                return .point(Draft(
                    name: name,
                    northing: fix.northingMeters,
                    easting: fix.eastingMeters,
                    latitude: latitude,
                    longitude: longitude,
                    height: height,
                    ground: ground,
                    formation: formation,
                    note: note
                ))
            }
        case .plane:
            guard roles.contains(.northing), roles.contains(.easting) else {
                return .issue("XとYの列がありません。")
            }
            guard let northing = required(row, roles, .northing, missing: "Xが読めません。", out: "Xが遠すぎます。", limit: 500_000) else {
                return .issue(lastRequiredMessage(row, roles, .northing, missing: "Xが読めません。", out: "Xが遠すぎます。", limit: 500_000))
            }
            guard let easting = required(row, roles, .easting, missing: "Yが読めません。", out: "Yが遠すぎます。", limit: 500_000) else {
                return .issue(lastRequiredMessage(row, roles, .easting, missing: "Yが読めません。", out: "Yが遠すぎます。", limit: 500_000))
            }
            guard let fix = ManualPoint.plane(northing: northing, easting: easting, zone: zone) else {
                return .issue("平面直角にできません。")
            }
            switch heights(row, roles: roles) {
            case let .issue(message):
                return .issue(message)
            case let .values(height, ground, formation, note, name):
                return .point(Draft(
                    name: name,
                    northing: northing,
                    easting: easting,
                    latitude: fix.latitudeDegrees,
                    longitude: fix.longitudeDegrees,
                    height: height,
                    ground: ground,
                    formation: formation,
                    note: note
                ))
            }
        }
    }

    private enum HeightRead {
        case values(Double?, Double?, Double?, String?, String)
        case issue(String)
    }

    private static func heights(_ row: [PointTableCell], roles: [PointColumnRole]) -> HeightRead {
        let name = text(row, roles, .name).trimmingCharacters(in: .whitespacesAndNewlines)
        let noteText = text(row, roles, .note).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = noteText.isEmpty ? nil : noteText
        switch optionalNumber(row, roles, .height) {
        case .bad:
            return .issue("標高が読めません。")
        case let .value(height):
            switch optionalNumber(row, roles, .ground) {
            case .bad:
                return .issue("GLが読めません。")
            case let .value(ground):
                switch optionalNumber(row, roles, .formation) {
                case .bad:
                    return .issue("FHが読めません。")
                case let .value(formation):
                    return .values(height, ground, formation, note, name)
                }
            }
        }
    }

    private enum OptionalNumber {
        case value(Double?)
        case bad
    }

    private static func optionalNumber(_ row: [PointTableCell], _ roles: [PointColumnRole], _ role: PointColumnRole) -> OptionalNumber {
        guard let column = roles.firstIndex(of: role), row.indices.contains(column) else { return .value(nil) }
        let token = row[column].text.trimmingCharacters(in: .whitespacesAndNewlines)
        if token.isEmpty { return .value(nil) }
        guard let value = PointTextRepair.number(token) else { return .bad }
        return .value(value)
    }

    private static func required(
        _ row: [PointTableCell],
        _ roles: [PointColumnRole],
        _ role: PointColumnRole,
        missing: String,
        out: String,
        limit: Double
    ) -> Double? {
        guard let column = roles.firstIndex(of: role), row.indices.contains(column) else { return nil }
        guard let value = PointTextRepair.number(row[column].text) else { return nil }
        guard abs(value) <= limit else { return nil }
        return value
    }

    private static func lastRequiredMessage(
        _ row: [PointTableCell],
        _ roles: [PointColumnRole],
        _ role: PointColumnRole,
        missing: String,
        out: String,
        limit: Double
    ) -> String {
        guard let column = roles.firstIndex(of: role), row.indices.contains(column) else { return missing }
        guard let value = PointTextRepair.number(row[column].text) else { return missing }
        if abs(value) > limit { return out }
        return missing
    }

    private static func text(_ row: [PointTableCell], _ roles: [PointColumnRole], _ role: PointColumnRole) -> String {
        guard let column = roles.firstIndex(of: role), row.indices.contains(column) else { return "" }
        return row[column].text
    }

    private static func axisWarning(northings: [Double], eastings: [Double], zone: Int) -> String? {
        guard let spec = PlaneRectangular.zone(zone) else { return nil }
        let count = min(northings.count, eastings.count, 24)
        guard count > 0 else { return nil }
        var direct = 0.0
        var swapped = 0.0
        var used = 0
        for index in 0..<count {
            guard let asIs = PlaneRectangular.inverse(northingMeters: northings[index], eastingMeters: eastings[index], zone: zone),
                  let flip = PlaneRectangular.inverse(northingMeters: eastings[index], eastingMeters: northings[index], zone: zone) else { continue }
            direct += score(asIs, spec)
            swapped += score(flip, spec)
            used += 1
        }
        guard used > 0 else { return nil }
        direct /= Double(used)
        swapped /= Double(used)
        guard swapped + 0.35 < direct else { return nil }
        return axisWarningText
    }

    private static func score(
        _ geo: (latitudeDegrees: Double, longitudeDegrees: Double),
        _ zone: PlaneZone
    ) -> Double {
        abs(geo.longitudeDegrees - zone.originLongitudeDegrees) + 0.5 * abs(geo.latitudeDegrees - zone.originLatitudeDegrees)
    }

    private static func coordinateKind(
        roles: [PointColumnRole],
        rows: [[PointTableCell]],
        hasHeader: Bool
    ) -> PointCoordinateKind {
        let geographic = roles.contains(.latitude) && roles.contains(.longitude)
        let plane = roles.contains(.northing) && roles.contains(.easting)
        if geographic && !plane { return .geographic }
        if plane && !geographic { return .plane }
        let body = hasHeader && rows.count > 1 ? Array(rows.dropFirst()) : rows
        return inferKind(body)
    }

    private static func makeTable(
        rows: [[PointTableCell]],
        delimiter: PointDelimiter,
        encodingName: String,
        fileName: String
    ) -> PointTable? {
        let usable = rows.filter { row in
            row.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        let width = usable.map(\.count).max() ?? 0
        guard usable.count >= 1, width >= 2 else { return nil }
        let header = looksLikeHeader(usable[0].map(\.text))
        let body = header ? Array(usable.dropFirst()) : usable
        let roles = header ? rolesFromHeader(usable[0].map(\.text), width: width) : inferRoles(body.isEmpty ? usable : body)
        return PointTable(
            fileName: fileName,
            encodingName: encodingName,
            delimiter: delimiter,
            hasHeader: header,
            roles: padded(roles, width: width),
            rows: usable
        )
    }

    private static func rolesFromHeader(_ cells: [String], width: Int) -> [PointColumnRole] {
        var roles = cells.map { role(forHeader: $0) ?? .ignore }
        if roles.count < width { roles.append(contentsOf: Array(repeating: .ignore, count: width - roles.count)) }
        return Array(roles.prefix(width))
    }

    private static func inferRoles(_ rows: [[PointTableCell]]) -> [PointColumnRole] {
        let width = rows.map(\.count).max() ?? 0
        guard width > 0 else { return [] }
        var numeric = Array(repeating: false, count: width)
        var medians: [Double?] = Array(repeating: nil, count: width)
        for column in 0..<width {
            var values: [Double] = []
            var filled = 0
            for row in rows {
                guard row.indices.contains(column) else { continue }
                let token = row[column].text.trimmingCharacters(in: .whitespacesAndNewlines)
                if token.isEmpty { continue }
                filled += 1
                if let value = PointTextRepair.number(token) { values.append(value) }
            }
            numeric[column] = filled > 0 && values.count * 2 >= filled
            medians[column] = median(values)
        }
        var roles = Array(repeating: PointColumnRole.ignore, count: width)
        if let nameIndex = (0..<width).first(where: { column in
            !numeric[column] && hasText(rows, column: column)
        }) {
            roles[nameIndex] = .name
        }
        let numericIndexes = numeric.indices.filter { numeric[$0] }
        let coords = Array(numericIndexes.prefix(2))
        if coords.count == 2 {
            let samples = coords.map { medians[$0] ?? 0 }
            if planePair(samples[0], samples[1]) {
                roles[coords[0]] = .northing
                roles[coords[1]] = .easting
            } else {
                roles[coords[0]] = .latitude
                roles[coords[1]] = .longitude
            }
        }
        let extras = numericIndexes.dropFirst(min(coords.count, 2))
        if extras.count == 1, let column = extras.first {
            roles[column] = .height
        } else {
            for (offset, column) in extras.enumerated() {
                if offset == 0 { roles[column] = .ground }
                else if offset == 1 { roles[column] = .formation }
                else if offset == 2 { roles[column] = .height }
            }
        }
        if let noteIndex = (0..<width).first(where: { roles[$0] == .ignore && !numeric[$0] && hasText(rows, column: $0) }) {
            roles[noteIndex] = .note
        }
        return roles
    }

    private static func inferKind(_ rows: [[PointTableCell]]) -> PointCoordinateKind {
        let roles = inferRoles(rows)
        if roles.contains(.northing) && roles.contains(.easting) { return .plane }
        return .geographic
    }

    private static func planePair(_ first: Double, _ second: Double) -> Bool {
        let a = abs(first)
        let b = abs(second)
        return a > 180 || b > 180 || (a > 90 && b > 90)
    }

    private static func hasText(_ rows: [[PointTableCell]], column: Int) -> Bool {
        rows.contains { row in
            guard row.indices.contains(column) else { return false }
            return !row[column].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) { return (sorted[mid - 1] + sorted[mid]) / 2 }
        return sorted[mid]
    }

    static func looksLikeHeader(_ cells: [String]) -> Bool {
        let roles = cells.map { role(forHeader: $0) }
        let known = roles.compactMap { $0 }.count
        guard known > 0 else { return false }
        let numeric = cells.filter { PointTextRepair.number($0) != nil }.count
        if numeric > 0 { return false }
        if known >= 2 { return true }
        return roles.contains { $0 == .latitude || $0 == .longitude || $0 == .northing || $0 == .easting }
    }

    static func role(forHeader raw: String) -> PointColumnRole? {
        let key = headerKey(raw)
        if key.isEmpty { return nil }
        switch key {
        case "点名", "名称", "NAME", "名", "測点", "点番", "点番号", "NO", "番号", "ポイント", "POINT":
            return .name
        case "緯度", "LAT", "LATITUDE":
            return .latitude
        case "経度", "LON", "LNG", "LONG", "LONGITUDE":
            return .longitude
        case "標高", "高さ", "HEIGHT", "H", "Z", "EL", "ELV", "ELEVATION":
            return .height
        case "GL", "地盤", "地盤高", "現況", "現況高":
            return .ground
        case "FH", "FL", "計画", "計画高", "仕上", "仕上高", "仕上がり", "仕上がり高":
            return .formation
        case "備考", "メモ", "NOTE", "記事", "摘要", "REMARK":
            return .note
        default:
            break
        }
        if key.contains("北"), !key.contains("東") { return .northing }
        if key.contains("東"), !key.contains("北") { return .easting }
        if key.contains("緯度") { return .latitude }
        if key.contains("経度") { return .longitude }
        if key.contains("点名") || key.contains("測点") { return .name }
        if key.contains("標高") { return .height }
        if key.contains("備考") { return .note }
        if key == "X" || key == "X座標" || key == "NORTHING" { return .northing }
        if key == "Y" || key == "Y座標" || key == "EASTING" { return .easting }
        return nil
    }

    private static func headerKey(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            if scalar.value == 0x20 || scalar.value == 0x3000 { return false }
            return !"()（）[]［］・._/\\-‐−".unicodeScalars.contains(scalar)
        }
        return String(String.UnicodeScalarView(scalars)).uppercased()
    }

    private static func padded(_ roles: [PointColumnRole], width: Int) -> [PointColumnRole] {
        if roles.count >= width { return Array(roles.prefix(width)) }
        return roles + Array(repeating: .ignore, count: width - roles.count)
    }

    private static func unique(_ name: String, used: inout [String: Int]) -> String {
        let base = name.isEmpty ? "点" : name
        let seen = used[base, default: 0]
        used[base] = seen + 1
        return seen == 0 ? base : "\(base)-\(seen + 1)"
    }

    private static func sourceLines(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("*")
            }
    }

    private static func detectDelimiter(_ lines: [String]) -> PointDelimiter {
        let sample = Array(lines.prefix(30))
        func score(_ delimiter: PointDelimiter) -> (width: Int, stable: Int) {
            let widths = sample.map { split($0, delimiter: delimiter).filter { !$0.isEmpty }.count }.filter { $0 >= 2 }
            guard !widths.isEmpty else { return (0, 0) }
            let counted = Dictionary(grouping: widths, by: { $0 }).mapValues(\.count)
            guard let best = counted.max(by: { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value < rhs.value }
                return lhs.key < rhs.key
            }) else { return (0, 0) }
            return (best.key, best.value)
        }
        let order: [PointDelimiter] = [.comma, .tab, .space]
        let ranked = order.map { delimiter -> (PointDelimiter, Int, Int) in
            let value = score(delimiter)
            return (delimiter, value.width, value.stable)
        }
        let winner = ranked.max { lhs, rhs in
            if lhs.2 != rhs.2 { return lhs.2 < rhs.2 }
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return preference(lhs.0) < preference(rhs.0)
        }
        return winner?.0 ?? .comma
    }

    private static func preference(_ delimiter: PointDelimiter) -> Int {
        switch delimiter {
        case .comma: return 3
        case .tab: return 2
        case .space: return 1
        }
    }

    private static func splitLine(_ line: String) -> [String] {
        let delimiter = detectDelimiter([line])
        let cells = split(line, delimiter: delimiter).filter { !$0.isEmpty }
        return cells.count >= 2 ? cells : [line]
    }

    static func split(_ line: String, delimiter: PointDelimiter) -> [String] {
        switch delimiter {
        case .comma:
            return splitDelimited(line, separator: ",")
        case .tab:
            return splitDelimited(line, separator: "\t")
        case .space:
            return splitWhitespace(line)
        }
    }

    private static func splitDelimited(_ line: String, separator: Character) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if character == "\"" {
                if quoted, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\"")
                    index += 2
                    continue
                }
                if quoted || current.trimmingCharacters(in: .whitespaces).isEmpty {
                    quoted.toggle()
                    index += 1
                    continue
                }
                current.append(character)
                index += 1
                continue
            }
            if character == separator, !quoted {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func splitWhitespace(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var quoted = false
        for character in line {
            if character == "\"" {
                quoted.toggle()
                continue
            }
            if !quoted, character.isWhitespace {
                if !current.isEmpty {
                    cells.append(current)
                    current = ""
                }
                continue
            }
            current.append(character)
        }
        if !current.isEmpty { cells.append(current) }
        return cells
    }
}
