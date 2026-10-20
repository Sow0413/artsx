import Foundation

public enum SFCError: Error, Equatable, CustomStringConvertible {
    case undecodable
    case notSFC

    public var description: String {
        switch self {
        case .undecodable: return "SFC の文字コードを判定できませんでした。"
        case .notSFC: return "SXF のテキスト（SFC）ではありません。"
        }
    }
}

/// SXF Ver.2 / Ver.3 のテキスト形式（SFC）。ISO-10303-21 の注釈 `/*SXF … SXF*/` に入ったフィーチャを読む。
/// 公共座標の数値はそのまま残す。系は読み込んだ側で選ぶ。原本のバイト列は書き換えない。
public enum SFCParser {
    public static func parse(_ data: Data) throws -> DrawingDocument {
        let decoded = try decode(data)
        guard decoded.text.contains("SXF") || decoded.text.contains("ISO-10303-21") else {
            throw SFCError.notSFC
        }
        let calls = featureCalls(in: decoded.text)
        guard !calls.isEmpty else { throw SFCError.notSFC }
        return assemble(calls, codePage: decoded.codePage, version: version(in: decoded.text))
    }

    static func decode(_ data: Data) throws -> (text: String, codePage: String) {
        var body = data
        if body.starts(with: Data([0xEF, 0xBB, 0xBF])) {
            body.removeFirst(3)
            guard let text = String(data: body, encoding: .utf8) else { throw SFCError.undecodable }
            return (text, "UTF-8")
        }
        if let text = String(data: data, encoding: .utf8), isPlausibleUTF8(data) {
            return (text, "UTF-8")
        }
        if let text = String(data: data, encoding: .shiftJIS) {
            return (text, "Shift_JIS")
        }
        throw SFCError.undecodable
    }

    /// 不正な UTF-8 は nil になる。Shift_JIS の日本語が偶然 UTF-8 に通ることは稀なので、通ったものは UTF-8 とする。
    private static func isPlausibleUTF8(_ data: Data) -> Bool {
        String(data: data, encoding: .utf8) != nil
    }

    static func version(in text: String) -> String {
        guard let marker = text.range(of: "$$") else { return "不明" }
        var digits = ""
        var index = marker.upperBound
        while index < text.endIndex {
            let character = text[index]
            if character.isNumber || character == "." {
                digits.append(character)
                index = text.index(after: index)
            } else {
                break
            }
        }
        if digits.hasPrefix("2") { return "2" }
        if digits.hasPrefix("3") { return "3" }
        return digits.isEmpty ? "不明" : digits
    }

    private static func assemble(_ calls: [FeatureCall], codePage: String, version: String) -> DrawingDocument {
        var layerNames: [String] = []
        var layerVisible: [Bool] = []
        var raw: [FeatureCall] = []
        var unsupported: [String: Int] = [:]
        for call in calls {
            if call.name == "layer_feature" {
                let name = call.args.first?.text ?? "レイヤ\(layerNames.count + 1)"
                let flag = call.args.dropFirst().first?.text ?? "1"
                layerNames.append(name)
                layerVisible.append(flag != "0")
            } else if supported.contains(call.name) {
                raw.append(call)
            } else {
                unsupported[call.name, default: 0] += 1
            }
        }
        if layerNames.isEmpty {
            layerNames = ["0"]
            layerVisible = [true]
        }
        var layers = layerNames.enumerated().map { index, name in
            DrawingLayer(
                name: name,
                color: .white,
                isVisible: layerVisible[index],
                role: DrawingLayerRole.classify(layerName: name)
            )
        }
        var entities: [DrawingEntity] = []
        for call in raw {
            guard let entity = entity(from: call, id: entities.count, layers: layers) else {
                unsupported[call.name, default: 0] += 1
                continue
            }
            if !layers.contains(where: { $0.name == entity.layer }) {
                layers.append(DrawingLayer(name: entity.layer, color: entity.color, isVisible: true, role: .design))
            }
            entities.append(entity)
        }
        let bounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let label = "SFC Ver\(version) \(codePage)"
        return DrawingDocument(
            layers: layers,
            entities: entities,
            bounds: bounds,
            unsupportedCounts: unsupported,
            codePage: label,
            unitWarning: "公共座標として読みました。系を選ぶと、そのまま地図に載ります。",
            index: DrawingSpatialIndex(entities: entities)
        )
    }

    private static let supported: Set<String> = [
        "line_feature", "polyline_feature", "circle_feature", "arc_feature", "text_string_feature", "point_feature"
    ]

    private static func entity(from call: FeatureCall, id: Int, layers: [DrawingLayer]) -> DrawingEntity? {
        let layerCode = Int(call.args.first?.text ?? "") ?? 1
        let layer = layers.indices.contains(layerCode - 1) ? layers[layerCode - 1].name : (layers.first?.name ?? "0")
        let colorCode = Int(call.args.dropFirst().first?.text ?? "") ?? 1
        let color = sxfColor(colorCode)
        switch call.name {
        case "line_feature":
            guard call.args.count >= 8,
                  let x1 = call.args[4].number, let y1 = call.args[5].number,
                  let x2 = call.args[6].number, let y2 = call.args[7].number else { return nil }
            let start = PlanarPoint(x: x1, y: y1)
            let end = PlanarPoint(x: x2, y: y2)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .line(start, end),
                bounds: DrawingBounds(enclosing: [start, end])
            )
        case "polyline_feature":
            let vertices = polylineVertices(call.args)
            guard vertices.count >= 2 else { return nil }
            let closed = vertices.first?.distance(to: vertices[vertices.count - 1]) ?? 1 < 1e-8
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .polyline(vertices: vertices, closed: closed, display: vertices),
                bounds: DrawingBounds(enclosing: vertices)
            )
        case "circle_feature":
            guard call.args.count >= 7,
                  let cx = call.args[4].number, let cy = call.args[5].number, let radius = call.args[6].number,
                  radius > 0 else { return nil }
            let center = PlanarPoint(x: cx, y: cy)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .circle(center: center, radius: radius),
                bounds: DrawingBounds(minX: cx - radius, minY: cy - radius, maxX: cx + radius, maxY: cy + radius)
            )
        case "arc_feature":
            guard call.args.count >= 10,
                  let cx = call.args[4].number, let cy = call.args[5].number, let radius = call.args[6].number,
                  let direction = call.args[7].number,
                  let start = call.args[8].number, let end = call.args[9].number,
                  radius > 0 else { return nil }
            let clockwise = Int(direction.rounded()) == 1
            let startDegrees = clockwise ? end : start
            let endDegrees = clockwise ? start : end
            let center = PlanarPoint(x: cx, y: cy)
            let display = DrawingCurve.arc(center: center, radius: radius, startDegrees: startDegrees, endDegrees: endDegrees)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .arc(center: center, radius: radius, startDegrees: startDegrees, endDegrees: endDegrees, display: display),
                bounds: DrawingBounds(enclosing: display)
            )
        case "text_string_feature":
            guard call.args.count >= 8,
                  let x = call.args[4].number, let y = call.args[5].number else { return nil }
            let height = call.args.count > 6 ? (call.args[6].number ?? 1) : 1
            let rotation = call.args.count > 8 ? (call.args[8].number ?? 0) : 0
            let origin = PlanarPoint(x: x, y: y)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .text(origin: origin, string: call.args[3].text, height: height, rotationDegrees: rotation),
                bounds: DrawingBounds(enclosing: [origin])
            )
        case "point_feature":
            guard call.args.count >= 6, let x = call.args[4].number, let y = call.args[5].number else { return nil }
            let point = PlanarPoint(x: x, y: y)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .point(point),
                bounds: DrawingBounds(enclosing: [point])
            )
        default:
            return nil
        }
    }

    /// 色番号は SXF。1 は紙の上の黒なので、暗い画面では白にする。
    static func sxfColor(_ code: Int) -> DrawingColor {
        switch code {
        case 1: return .white
        case 2: return DrawingColor(red: 1, green: 0, blue: 0)
        case 3: return DrawingColor(red: 0, green: 1, blue: 0)
        case 4: return DrawingColor(red: 0, green: 0, blue: 1)
        case 5: return DrawingColor(red: 1, green: 1, blue: 0)
        case 6: return DrawingColor(red: 1, green: 0, blue: 1)
        case 7: return DrawingColor(red: 0, green: 1, blue: 1)
        case 8: return .white
        default: return .white
        }
    }

    private static func polylineVertices(_ args: [SFCValue]) -> [PlanarPoint] {
        guard args.count >= 5 else { return [] }
        let tail = Array(args.dropFirst(4))
        if tail.count >= 3, let xs = tail[1].list, let ys = tail[2].list {
            return zip(xs, ys).map { PlanarPoint(x: $0, y: $1) }
        }
        if tail.count >= 2, let xs = tail[0].list, let ys = tail[1].list, tail[0].number == nil {
            return zip(xs, ys).map { PlanarPoint(x: $0, y: $1) }
        }
        let numbers = tail.compactMap(\.number)
        guard numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return [] }
        var points: [PlanarPoint] = []
        var index = 0
        while index + 1 < numbers.count {
            points.append(PlanarPoint(x: numbers[index], y: numbers[index + 1]))
            index += 2
        }
        return points
    }

    private struct FeatureCall {
        var name: String
        var args: [SFCValue]
    }

    private static func featureCalls(in text: String) -> [FeatureCall] {
        let source = sxfBodies(in: text) ?? text
        var calls: [FeatureCall] = []
        var index = source.startIndex
        while index < source.endIndex {
            guard let nameStart = identifierStart(in: source, from: index) else { break }
            let nameEnd = readIdentifier(in: source, from: nameStart)
            let name = String(source[nameStart..<nameEnd])
            var cursor = nameEnd
            while cursor < source.endIndex, source[cursor].isWhitespace { cursor = source.index(after: cursor) }
            guard cursor < source.endIndex, source[cursor] == "(" else {
                index = source.index(after: nameStart)
                continue
            }
            let parsed = parseArguments(in: source, open: cursor)
            if name == "layer_feature" || name.hasSuffix("_feature") {
                calls.append(FeatureCall(name: name, args: parsed.values))
            }
            index = parsed.end
        }
        return calls
    }

    /// `/*SXF` から `SXF*/` まで。注釈が無ければ全体を見る。
    private static func sxfBodies(in text: String) -> String? {
        var bodies: [String] = []
        var rest = text[...]
        while let start = rest.range(of: "/*SXF") {
            rest = rest[start.upperBound...]
            guard let end = rest.range(of: "SXF*/") else { break }
            bodies.append(String(rest[..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        if bodies.isEmpty { return nil }
        return bodies.joined(separator: "\n")
    }

    private static func identifierStart(in text: String, from index: String.Index) -> String.Index? {
        var cursor = index
        while cursor < text.endIndex {
            let character = text[cursor]
            let previous = cursor == text.startIndex ? nil : text[text.index(before: cursor)]
            let boundary = previous == nil || !(previous!.isLetter || previous!.isNumber || previous == "_")
            if boundary, character.isLetter || character == "_" {
                return cursor
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }

    private static func readIdentifier(in text: String, from index: String.Index) -> String.Index {
        var cursor = index
        while cursor < text.endIndex {
            let character = text[cursor]
            if character.isLetter || character.isNumber || character == "_" {
                cursor = text.index(after: cursor)
            } else {
                break
            }
        }
        return cursor
    }

    private static func parseArguments(in text: String, open: String.Index) -> (values: [SFCValue], end: String.Index) {
        var values: [SFCValue] = []
        var cursor = text.index(after: open)
        var token = ""
        func flush() {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            token = ""
            if !trimmed.isEmpty { values.append(SFCValue(trimmed)) }
        }
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "'" {
                var string = ""
                cursor = text.index(after: cursor)
                while cursor < text.endIndex {
                    if text[cursor] == "'" {
                        let next = text.index(after: cursor)
                        if next < text.endIndex, text[next] == "'" {
                            string.append("'")
                            cursor = text.index(after: next)
                            continue
                        }
                        cursor = next
                        break
                    }
                    string.append(text[cursor])
                    cursor = text.index(after: cursor)
                }
                values.append(SFCValue(string, quoted: true))
                continue
            }
            if character == "(" {
                let grouped = readGroup(in: text, open: cursor)
                values.append(SFCValue(grouped.text, grouped: true))
                cursor = grouped.end
                continue
            }
            if character == "," {
                flush()
                cursor = text.index(after: cursor)
                continue
            }
            if character == ")" {
                flush()
                return (values, text.index(after: cursor))
            }
            token.append(character)
            cursor = text.index(after: cursor)
        }
        flush()
        return (values, cursor)
    }

    private static func readGroup(in text: String, open: String.Index) -> (text: String, end: String.Index) {
        var depth = 0
        var cursor = open
        var body = ""
        while cursor < text.endIndex {
            let character = text[cursor]
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 {
                    return (body, text.index(after: cursor))
                }
            }
            if depth > 1 || (depth == 1 && character != "(") {
                body.append(character)
            }
            cursor = text.index(after: cursor)
        }
        return (body, cursor)
    }
}

private struct SFCValue: Equatable {
    var text: String
    var list: [Double]?

    var number: Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(cleaned)
    }

    init(_ raw: String, quoted: Bool = false, grouped: Bool = false) {
        text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if grouped || text.contains(",") {
            let body = text.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
            let parts = body.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 2 { list = parts }
        }
        if quoted, list == nil, text.contains(",") {
            let parts = text.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count >= 2 { list = parts }
        }
    }
}
