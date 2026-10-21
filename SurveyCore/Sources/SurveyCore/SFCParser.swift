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
        let headEnd = text.range(of: "DATA;")?.lowerBound ?? text.endIndex
        let head = String(text[..<headEnd])
        if head.contains("SCADEC_API_Ver3") || head.contains("$$3") { return "3" }
        if head.contains("SCADEC_API_Ver2") || head.contains("$$2") { return "2" }
        if head.contains("level2") { return "3" }
        return "不明"
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
        let rawBounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let divisor = fileUnitsPerMeter(rawBounds)
        if divisor != 1 {
            let factor = 1 / divisor
            entities = entities.map { scaled($0, by: factor) }
        }
        let bounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let label = "SFC Ver\(version) \(codePage)"
        let unit = divisor == 1000
            ? "座標はミリメートルだったので、メートルに直しました。公共座標として読みました。系を選ぶと、そのまま地図に載ります。"
            : "公共座標として読みました。系を選ぶと、そのまま地図に載ります。"
        return DrawingDocument(
            layers: layers,
            entities: entities,
            bounds: bounds,
            unsupportedCounts: unsupported,
            codePage: label,
            unitWarning: unit,
            index: DrawingSpatialIndex(entities: entities)
        )
    }

    /// 平面直角のメートルなら、絶対値はおおむね 40 万より小さい。それを超える地図はミリメートル。
    static func fileUnitsPerMeter(_ bounds: DrawingBounds) -> Double {
        guard !bounds.isEmpty else { return 1 }
        let span = max(bounds.width, bounds.height)
        let magnitude = max(abs(bounds.minX), abs(bounds.maxX), abs(bounds.minY), abs(bounds.maxY))
        guard magnitude >= 1_000_000, span >= 1_000 else { return 1 }
        let meters = span / 1000
        guard meters >= 1, meters <= 300_000 else { return 1 }
        return 1000
    }

    private static func scaled(_ entity: DrawingEntity, by factor: Double) -> DrawingEntity {
        func point(_ value: PlanarPoint) -> PlanarPoint {
            PlanarPoint(x: value.x * factor, y: value.y * factor)
        }
        let primitive: DrawingPrimitive
        switch entity.primitive {
        case let .line(start, end):
            primitive = .line(point(start), point(end))
        case let .polyline(vertices, closed, display):
            primitive = .polyline(vertices: vertices.map(point), closed: closed, display: display.map(point))
        case let .circle(center, radius):
            primitive = .circle(center: point(center), radius: radius * factor)
        case let .arc(center, radius, startDegrees, endDegrees, display):
            primitive = .arc(
                center: point(center),
                radius: radius * factor,
                startDegrees: startDegrees,
                endDegrees: endDegrees,
                display: display.map(point)
            )
        case let .text(origin, string, height, rotation):
            primitive = .text(origin: point(origin), string: string, height: height * factor, rotationDegrees: rotation)
        case let .point(value):
            primitive = .point(point(value))
        }
        let bounds = DrawingBounds(
            minX: entity.bounds.minX * factor,
            minY: entity.bounds.minY * factor,
            maxX: entity.bounds.maxX * factor,
            maxY: entity.bounds.maxY * factor
        )
        return DrawingEntity(
            id: entity.id,
            layer: entity.layer,
            color: entity.color,
            primitive: primitive,
            bounds: bounds,
            lineWeight: entity.lineWeight
        )
    }

    /// sfig_locate_feature は図郭を用紙へ置く配置（挿入点と縮尺）なので、座標には掛けない。
    /// 公共座標はポリライン側のミリメートルをメートルにした値。紙の配置では 2点合わせにしない。
    private static let supported: Set<String> = [
        "line_feature", "polyline_feature", "circle_feature", "arc_feature",
        "text_string_feature", "point_feature", "point_marker_feature"
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
                bounds: DrawingBounds(enclosing: [start, end]),
                lineWeight: widthCode(call.args)
            )
        case "polyline_feature":
            let vertices = polylineVertices(call.args)
            guard vertices.count >= 2 else { return nil }
            let closed = vertices.first?.distance(to: vertices[vertices.count - 1]) ?? 1 < 1e-8
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .polyline(vertices: vertices, closed: closed, display: vertices),
                bounds: DrawingBounds(enclosing: vertices),
                lineWeight: widthCode(call.args)
            )
        case "circle_feature":
            guard call.args.count >= 7,
                  let cx = call.args[4].number, let cy = call.args[5].number, let radius = call.args[6].number,
                  radius > 0 else { return nil }
            let center = PlanarPoint(x: cx, y: cy)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .circle(center: center, radius: radius),
                bounds: DrawingBounds(minX: cx - radius, minY: cy - radius, maxX: cx + radius, maxY: cy + radius),
                lineWeight: widthCode(call.args)
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
                bounds: DrawingBounds(enclosing: display),
                lineWeight: widthCode(call.args)
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
            let marker = PlanarPoint(x: x, y: y)
            return DrawingEntity(
                id: id, layer: layer, color: color,
                primitive: .point(marker),
                bounds: DrawingBounds(enclosing: [marker])
            )
        case "point_marker_feature":
            guard call.args.count >= 4, let x = call.args[2].number, let y = call.args[3].number else { return nil }
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

    /// 線種の次が線幅。無いときは 1。画面では 0.5〜1 pt の相対にする。
    private static func widthCode(_ args: [SFCValue]) -> Double {
        guard args.count > 3, let number = args[3].number, number > 0 else { return 1 }
        return number
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

    private static func isEscape(_ character: Character) -> Bool {
        character == "\\" || character == "\u{00A5}"
    }

    private static func parseArguments(in text: String, open: String.Index) -> (values: [SFCValue], end: String.Index) {
        var values: [SFCValue] = []
        var cursor = text.index(after: open)
        var token = ""
        func flush() {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            token = ""
            if !trimmed.isEmpty { values.append(SFCValue(decodeStep(trimmed))) }
        }
        while cursor < text.endIndex {
            let character = text[cursor]
            if isEscape(character) {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "'" {
                    flush()
                    let read = readDelimited(in: text, from: text.index(after: next), closingEscape: true)
                    values.append(SFCValue(decodeStep(read.string), quoted: true))
                    cursor = read.end
                    continue
                }
                if let step = readStepCode(in: text, from: cursor) {
                    token.append(step.string)
                    cursor = step.end
                    continue
                }
            }
            if character == "'" {
                flush()
                let read = readDelimited(in: text, from: text.index(after: cursor), closingEscape: false)
                values.append(SFCValue(decodeStep(read.string), quoted: true))
                cursor = read.end
                continue
            }
            if character == "(" {
                flush()
                let grouped = readGroup(in: text, open: cursor)
                values.append(SFCValue(decodeStep(grouped.text), grouped: true))
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

    /// `'` で囲む普通の文字列と、SCADEC が書く `\'...\'`。中の `\'` と `''` は引用符一つ。
    private static func readDelimited(
        in text: String,
        from start: String.Index,
        closingEscape: Bool
    ) -> (string: String, end: String.Index) {
        var string = ""
        var cursor = start
        while cursor < text.endIndex {
            let character = text[cursor]
            if isEscape(character) {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "'" {
                    if closingEscape {
                        return (string, text.index(after: next))
                    }
                    string.append("'")
                    cursor = text.index(after: next)
                    continue
                }
            }
            if character == "'" {
                let next = text.index(after: cursor)
                if next < text.endIndex, text[next] == "'" {
                    string.append("'")
                    cursor = text.index(after: next)
                    continue
                }
                if !closingEscape {
                    return (string, next)
                }
            }
            string.append(character)
            cursor = text.index(after: cursor)
        }
        return (string, cursor)
    }

    /// ISO-10303-21 の `\X2\hhhh\X0\`。ファイル名の『基盤地図プロジェクト』がこれ。
    private static func readStepCode(in text: String, from start: String.Index) -> (string: String, end: String.Index)? {
        let rest = text[start...]
        guard rest.hasPrefix("\\X2\\") || rest.hasPrefix("\u{00A5}X2\\") || rest.hasPrefix("\\X2\u{00A5}") || rest.hasPrefix("\u{00A5}X2\u{00A5}") else {
            return nil
        }
        var cursor = start
        var skips = 0
        while skips < 4, cursor < text.endIndex {
            cursor = text.index(after: cursor)
            skips += 1
        }
        var hex = ""
        while cursor < text.endIndex, text[cursor].isHexDigit {
            hex.append(text[cursor])
            cursor = text.index(after: cursor)
        }
        guard hex.count >= 4, hex.count.isMultiple(of: 4) else { return nil }
        guard cursor < text.endIndex, isEscape(text[cursor]) else { return nil }
        let afterSlash = text.index(after: cursor)
        guard text[afterSlash...].hasPrefix("X0") else { return nil }
        var end = afterSlash
        var left = 2
        while left > 0, end < text.endIndex {
            end = text.index(after: end)
            left -= 1
        }
        if end < text.endIndex, isEscape(text[end]) {
            end = text.index(after: end)
        }
        var units: [UInt16] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 4)
            guard let unit = UInt16(hex[index..<next], radix: 16) else { return nil }
            units.append(unit)
            index = next
        }
        return (String(utf16CodeUnits: units, count: units.count), end)
    }

    static func decodeStep(_ raw: String) -> String {
        var result = ""
        var index = raw.startIndex
        while index < raw.endIndex {
            if isEscape(raw[index]), let step = readStepCode(in: raw, from: index) {
                result.append(step.string)
                index = step.end
                continue
            }
            result.append(raw[index])
            index = raw.index(after: index)
        }
        return result
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
