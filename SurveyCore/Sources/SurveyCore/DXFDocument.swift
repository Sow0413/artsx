import Foundation

public struct DrawingColor: Sendable, Equatable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let white = DrawingColor(red: 1, green: 1, blue: 1)

    /// ACI 1〜9 は AutoCAD の標準色。250〜255 は灰色。7 と 255 は白で、明るい地では後から暗くする。
    public static func aci(_ index: Int) -> DrawingColor {
        switch abs(index) {
        case 1: return DrawingColor(red: 1, green: 0, blue: 0)
        case 2: return DrawingColor(red: 1, green: 1, blue: 0)
        case 3: return DrawingColor(red: 0, green: 1, blue: 0)
        case 4: return DrawingColor(red: 0, green: 1, blue: 1)
        case 5: return DrawingColor(red: 0, green: 0, blue: 1)
        case 6: return DrawingColor(red: 1, green: 0, blue: 1)
        case 7: return white
        case 8: return DrawingColor(red: 0.5, green: 0.5, blue: 0.5)
        case 9: return DrawingColor(red: 0.75, green: 0.75, blue: 0.75)
        case 250: return gray(51)
        case 251: return gray(91)
        case 252: return gray(132)
        case 253: return gray(173)
        case 254: return gray(214)
        case 255: return white
        default:
            let hue = Double(abs(index) % 24) / 24
            return hsv(hue)
        }
    }

    /// 白や薄い色は、地理院の明るい地図の上では黒に近い色にする。
    public func onLightMap() -> DrawingColor {
        let y = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        if y < 0.70 { return self }
        if min(red, min(green, blue)) >= 0.80 {
            return DrawingColor(red: 0.12, green: 0.12, blue: 0.12)
        }
        let scale = 0.28 / max(y, 0.01)
        return DrawingColor(red: min(1, red * scale), green: min(1, green * scale), blue: min(1, blue * scale))
    }

    private static func gray(_ byte: Double) -> DrawingColor {
        let channel = byte / 255
        return DrawingColor(red: channel, green: channel, blue: channel)
    }

    public static func trueColor(_ value: Int) -> DrawingColor {
        DrawingColor(
            red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255
        )
    }

    private static func hsv(_ hue: Double) -> DrawingColor {
        let sector = hue * 6
        let index = Int(sector) % 6
        let fraction = sector - Double(Int(sector))
        switch index {
        case 0: return DrawingColor(red: 1, green: fraction, blue: 0)
        case 1: return DrawingColor(red: 1 - fraction, green: 1, blue: 0)
        case 2: return DrawingColor(red: 0, green: 1, blue: fraction)
        case 3: return DrawingColor(red: 0, green: 1 - fraction, blue: 1)
        case 4: return DrawingColor(red: fraction, green: 0, blue: 1)
        default: return DrawingColor(red: 1, green: 0, blue: 1 - fraction)
        }
    }
}

public struct DrawingBounds: Sendable, Equatable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    /// 点が一つも無い範囲。0,0 は図面の原点なので、空の印には使わない。
    public static let empty = DrawingBounds(
        minX: .infinity,
        minY: .infinity,
        maxX: -.infinity,
        maxY: -.infinity
    )

    public var isEmpty: Bool { minX > maxX || minY > maxY }

    public var midX: Double { (minX + maxX) / 2 }
    public var midY: Double { (minY + maxY) / 2 }
    public var width: Double { max(0, maxX - minX) }
    public var height: Double { max(0, maxY - minY) }

    public init(minX: Double, minY: Double, maxX: Double, maxY: Double) {
        self.minX = minX
        self.minY = minY
        self.maxX = maxX
        self.maxY = maxY
    }

    public init(enclosing points: [PlanarPoint]) {
        guard let first = points.first else {
            self = .empty
            return
        }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points.dropFirst() {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        self.init(minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    public func contains(_ point: PlanarPoint) -> Bool {
        !isEmpty && point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersects(_ other: DrawingBounds) -> Bool {
        !isEmpty && !other.isEmpty && minX <= other.maxX && maxX >= other.minX && minY <= other.maxY && maxY >= other.minY
    }

    public func padded(_ amount: Double) -> DrawingBounds {
        DrawingBounds(minX: minX - amount, minY: minY - amount, maxX: maxX + amount, maxY: maxY + amount)
    }

    public func union(_ other: DrawingBounds) -> DrawingBounds {
        if isEmpty { return other }
        if other.isEmpty { return self }
        return DrawingBounds(
            minX: min(minX, other.minX),
            minY: min(minY, other.minY),
            maxX: max(maxX, other.maxX),
            maxY: max(maxY, other.maxY)
        )
    }
}

public enum DrawingPrimitive: Sendable, Equatable {
    case line(PlanarPoint, PlanarPoint)
    case polyline(vertices: [PlanarPoint], closed: Bool, display: [PlanarPoint])
    case circle(center: PlanarPoint, radius: Double)
    case arc(center: PlanarPoint, radius: Double, startDegrees: Double, endDegrees: Double, display: [PlanarPoint])
    case text(origin: PlanarPoint, string: String, height: Double, rotationDegrees: Double)
    case point(PlanarPoint)
}

public struct DrawingEntity: Sendable, Equatable, Identifiable {
    public var id: Int
    public var layer: String
    public var color: DrawingColor
    public var primitive: DrawingPrimitive
    public var bounds: DrawingBounds

    public init(id: Int, layer: String, color: DrawingColor, primitive: DrawingPrimitive, bounds: DrawingBounds) {
        self.id = id
        self.layer = layer
        self.color = color
        self.primitive = primitive
        self.bounds = bounds
    }

    public var samplePoints: [PlanarPoint] {
        switch primitive {
        case let .line(start, end):
            return [start, end]
        case let .polyline(vertices, _, _):
            return vertices
        case let .circle(center, radius):
            return [
                center,
                PlanarPoint(x: center.x + radius, y: center.y),
                PlanarPoint(x: center.x, y: center.y + radius),
                PlanarPoint(x: center.x - radius, y: center.y),
                PlanarPoint(x: center.x, y: center.y - radius)
            ]
        case let .arc(center, _, _, _, display):
            return [center] + display
        case let .text(origin, _, _, _):
            return [origin]
        case let .point(point):
            return [point]
        }
    }

    public var stroke: [PlanarPoint] {
        switch primitive {
        case let .line(start, end):
            return [start, end]
        case let .polyline(_, closed, display):
            guard closed, let first = display.first else { return display }
            return display + [first]
        case let .circle(center, radius):
            return DrawingCurve.circle(center: center, radius: radius)
        case let .arc(_, _, _, _, display):
            return display
        case .text, .point:
            return []
        }
    }
}

/// 図面のレイヤを、地形図などの背景と、設計の線に分ける。
public enum DrawingLayerRole: String, Codable, Sendable, Equatable {
    case background
    case design

    public var label: String {
        switch self {
        case .background: return "背景"
        case .design: return "設計"
        }
    }

    /// SFC の地形図レイヤに多い名前。DXF は既定で設計のまま。
    public static func classify(layerName: String) -> DrawingLayerRole {
        let folded = layerName.uppercased()
        let markers = [
            "BGD", "TOPO", "地形図", "地形", "背景", "現況", "2500", "基盤", "等高", "DM",
            "建築物", "水涯", "道路縁", "道路構成", "標高", "軌道", "行政界", "海岸線"
        ]
        for marker in markers where folded.contains(marker.uppercased()) {
            return .background
        }
        return .design
    }
}

public struct DrawingLayer: Sendable, Equatable, Identifiable {
    public var name: String
    public var color: DrawingColor
    public var isVisible: Bool
    public var role: DrawingLayerRole

    public var id: String { name }

    public init(name: String, color: DrawingColor, isVisible: Bool, role: DrawingLayerRole = .design) {
        self.name = name
        self.color = color
        self.isVisible = isVisible
        self.role = role
    }
}

public struct DrawingHit: Sendable, Equatable {
    public var entityID: Int
    public var point: PlanarPoint
    public var distance: Double

    public init(entityID: Int, point: PlanarPoint, distance: Double) {
        self.entityID = entityID
        self.point = point
        self.distance = distance
    }
}

public struct DrawingDocument: Sendable, Equatable {
    public var layers: [DrawingLayer]
    public var entities: [DrawingEntity]
    public var bounds: DrawingBounds
    public var unsupportedCounts: [String: Int]
    public var codePage: String
    public var unitWarning: String?
    /// $INSUNITS。0 は無指定、4 はミリ、6 はメートル。
    public var unitCode: Int
    /// 部分図の一覧や、位置合わせが要るときの一文。
    public var readNotice: String?
    public internal(set) var index: DrawingSpatialIndex

    /// 読み込んだ図形の数。線は LINE、折線、円、弧、スプライン、楕円、ハッチの外形。
    public var importCensus: String {
        var lines = 0
        var texts = 0
        var points = 0
        for entity in entities {
            switch entity.primitive {
            case .text: texts += 1
            case .point: points += 1
            default: lines += 1
            }
        }
        return "線 \(Self.grouped(lines)) / 文字 \(Self.grouped(texts)) / 点 \(Self.grouped(points))"
    }

    private static func grouped(_ value: Int) -> String {
        let digits = String(value)
        var out = ""
        for (offset, character) in digits.reversed().enumerated() {
            if offset > 0, offset % 3 == 0 { out.append(",") }
            out.append(character)
        }
        return String(out.reversed())
    }

    public init(
        layers: [DrawingLayer],
        entities: [DrawingEntity],
        bounds: DrawingBounds,
        unsupportedCounts: [String: Int],
        codePage: String,
        unitWarning: String?,
        index: DrawingSpatialIndex,
        unitCode: Int = 0,
        readNotice: String? = nil
    ) {
        self.layers = layers
        self.entities = entities
        self.bounds = bounds
        self.unsupportedCounts = unsupportedCounts
        self.codePage = codePage
        self.unitWarning = unitWarning
        self.unitCode = unitCode
        self.readNotice = readNotice
        self.index = index
    }

    /// ファイルの 1 単位をメートルにする倍率。ミリは 0.001。数値そのものは変えない。
    public var metersPerUnit: Double {
        switch unitCode {
        case 1: return 0.0254
        case 2: return 0.3048
        case 4: return 0.001
        case 5: return 0.01
        default: return 1
        }
    }

    public var unsupportedSummary: String {
        unsupportedCounts.keys.sorted().map { "\($0) \(unsupportedCounts[$0] ?? 0)" }.joined(separator: "、")
    }

    public func entities(in query: DrawingBounds) -> [DrawingEntity] {
        let visible = Set(layers.filter(\.isVisible).map(\.name))
        return index.entityIDs(in: query).compactMap { id in
            guard entities.indices.contains(id), visible.contains(entities[id].layer) else { return nil }
            return entities[id]
        }
    }

    public func nearestVertex(to point: PlanarPoint, tolerance: Double) -> DrawingHit? {
        let visible = Set(layers.filter(\.isVisible).map(\.name))
        var best: DrawingHit?
        for id in index.entityIDs(in: DrawingBounds(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y).padded(tolerance)) {
            guard entities.indices.contains(id), visible.contains(entities[id].layer) else { continue }
            for sample in entities[id].samplePoints {
                let distance = sample.distance(to: point)
                if distance <= tolerance, best == nil || distance < best!.distance {
                    best = DrawingHit(entityID: id, point: sample, distance: distance)
                }
            }
        }
        return best
    }

    public func settingLayer(_ name: String, visible: Bool) -> DrawingDocument {
        var copy = self
        copy.layers = layers.map { layer in
            guard layer.name == name else { return layer }
            return DrawingLayer(name: layer.name, color: layer.color, isVisible: visible, role: layer.role)
        }
        return copy
    }

    /// 背景だけ、または設計だけをまとめて出す・消す。
    public func settingRole(_ role: DrawingLayerRole, visible: Bool) -> DrawingDocument {
        var copy = self
        copy.layers = layers.map { layer in
            guard layer.role == role else { return layer }
            return DrawingLayer(name: layer.name, color: layer.color, isVisible: visible, role: layer.role)
        }
        return copy
    }

    public func shows(_ role: DrawingLayerRole) -> Bool {
        layers.contains { $0.role == role && $0.isVisible }
    }

    public func has(_ role: DrawingLayerRole) -> Bool {
        layers.contains { $0.role == role }
    }
}

public struct DrawingSpatialIndex: Sendable, Equatable {
    var cell: Double
    var buckets: [Int64: [Int]]
    /// 何マスもまたぐ線。全マスに複製しない。
    var wide: [(id: Int, bounds: DrawingBounds)]

    public init(entities: [DrawingEntity]) {
        let bounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let span = bounds.isEmpty ? 1 : max(bounds.width, bounds.height, 1)
        cell = max(span / 32, 1e-6)
        buckets = [:]
        wide = []
        for entity in entities {
            guard !entity.bounds.isEmpty else { continue }
            let x0 = Int(floor(entity.bounds.minX / cell))
            let x1 = Int(floor(entity.bounds.maxX / cell))
            let y0 = Int(floor(entity.bounds.minY / cell))
            let y1 = Int(floor(entity.bounds.maxY / cell))
            if x1 - x0 > 4 || y1 - y0 > 4 {
                wide.append((entity.id, entity.bounds))
                continue
            }
            for ix in x0...x1 {
                for iy in y0...y1 {
                    buckets[Self.key(ix, iy), default: []].append(entity.id)
                }
            }
        }
    }

    public func entityIDs(in query: DrawingBounds) -> [Int] {
        guard cell > 0, !query.isEmpty else { return [] }
        let x0 = Int(floor(query.minX / cell))
        let x1 = Int(floor(query.maxX / cell))
        let y0 = Int(floor(query.minY / cell))
        let y1 = Int(floor(query.maxY / cell))
        let spanX = x1 >= x0 ? x1 - x0 + 1 : 0
        let spanY = y1 >= y0 ? y1 - y0 + 1 : 0
        if spanX > 64 || spanY > 64 {
            return everyID()
        }
        var seen = Set<Int>()
        var result: [Int] = []
        for ix in x0...x1 {
            for iy in y0...y1 {
                guard let bucket = buckets[Self.key(ix, iy)] else { continue }
                for id in bucket where seen.insert(id).inserted {
                    result.append(id)
                }
            }
        }
        for item in wide where item.bounds.intersects(query) && seen.insert(item.id).inserted {
            result.append(item.id)
        }
        return result
    }

    private func everyID() -> [Int] {
        var seen = Set<Int>()
        var result: [Int] = []
        for ids in buckets.values {
            for id in ids where seen.insert(id).inserted {
                result.append(id)
            }
        }
        for item in wide where seen.insert(item.id).inserted {
            result.append(item.id)
        }
        return result
    }

    static func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(x) &* 73856093 ^ Int64(y) &* 19349663
    }

    public static func == (lhs: DrawingSpatialIndex, rhs: DrawingSpatialIndex) -> Bool {
        lhs.cell == rhs.cell && lhs.buckets == rhs.buckets && lhs.wide.elementsEqual(rhs.wide, by: { $0.id == $1.id && $0.bounds == $1.bounds })
    }
}

public enum DXFError: Error, Equatable, CustomStringConvertible {
    case binary
    case undecodable
    case notDXF
    case truncated

    public var description: String {
        switch self {
        case .binary: return "バイナリ DXF は読めません。ASCII で書き出してください。"
        case .undecodable: return "文字コードを判定できませんでした。"
        case .notDXF: return "DXF の形になっていません。"
        case .truncated: return "DXF が途中で切れています。"
        }
    }
}

public enum DrawingReadiness {
    /// 落ちずに伝える文。問題がなければ nil。
    public static func notice(_ document: DrawingDocument) -> String? {
        if document.entities.isEmpty {
            return "図形がありません。"
        }
        let bounds = document.bounds
        if bounds.isEmpty {
            return "座標が読めません。"
        }
        if bounds.minX == 0, bounds.minY == 0, bounds.maxX == 0, bounds.maxY == 0 {
            return "座標がすべて原点です。位置を決められません。"
        }
        return nil
    }
}

public enum DXFParser {
    public static let supportedTypes: Set<String> = [
        "LINE", "LWPOLYLINE", "POLYLINE", "CIRCLE", "ARC", "SPLINE", "ELLIPSE", "HATCH",
        "TEXT", "MTEXT", "POINT", "INSERT"
    ]

    public static func parse(_ data: Data) throws -> DrawingDocument {
        if data.starts(with: Data("AutoCAD Binary DXF".utf8)) { throw DXFError.binary }
        if data.contains(0) { throw DXFError.truncated }
        let decoded = try decode(data)
        guard decoded.text.contains("SECTION") else { throw DXFError.notDXF }
        let pairs = pairLines(decoded.text)
        return assemble(pairs, codePage: decoded.codePage)
    }

    static func decode(_ data: Data) throws -> (text: String, codePage: String) {
        var body = data
        if body.starts(with: Data([0xEF, 0xBB, 0xBF])) {
            body.removeFirst(3)
            guard let text = String(data: body, encoding: .utf8) else { throw DXFError.undecodable }
            return (text, "UTF-8")
        }
        let codePage = scanCodePage(data)
        let acad = scanGroupValue(data, name: "$ACADVER")
        if SiteDXF.prefersUTF8(acadVersion: acad) || isShiftJIS(codePage) {
            if let text = String(data: data, encoding: .utf8),
               SiteDXF.prefersUTF8(acadVersion: acad) || text.contains("測設") || text.contains("IRB-") {
                return (text, "UTF-8")
            }
        }
        if isShiftJIS(codePage) {
            guard let text = String(data: data, encoding: .shiftJIS) else { throw DXFError.undecodable }
            return (text, codePage ?? "Shift_JIS")
        }
        if let text = String(data: data, encoding: .utf8) {
            return (text, codePage ?? "UTF-8")
        }
        if let text = String(data: data, encoding: .shiftJIS) {
            return (text, "Shift_JIS")
        }
        throw DXFError.undecodable
    }

    private static func isShiftJIS(_ codePage: String?) -> Bool {
        guard let codePage else { return false }
        let folded = codePage.uppercased().replacingOccurrences(of: "-", with: "_")
        return folded.contains("932") || folded.contains("SHIFT_JIS") || folded.contains("CP932")
    }

    private static func scanGroupValue(_ data: Data, name: String) -> String? {
        guard let token = data.range(of: Data(name.utf8)) else { return nil }
        let tail = data[token.upperBound...].prefix(200)
        let text = String(tail.map { $0 < 128 ? Character(UnicodeScalar($0)) : "?" })
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty && Int($0) == nil }
    }

    private static func scanCodePage(_ data: Data) -> String? {
        scanGroupValue(data, name: "$DWGCODEPAGE")
    }

    private static func pairLines(_ text: String) -> [(Int, String)] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var pairs: [(Int, String)] = []
        var index = 0
        while index + 1 < lines.count {
            let codeLine = lines[index].trimmingCharacters(in: .whitespaces)
            let value = lines[index + 1].trimmingCharacters(in: .whitespaces)
            index += 2
            guard let code = Int(codeLine) else { continue }
            pairs.append((code, value))
        }
        return pairs
    }

    private static func assemble(_ pairs: [(Int, String)], codePage: String) -> DrawingDocument {
        var section = ""
        var table = ""
        var layers: [String: DrawingLayer] = [:]
        var blocks: [String: BlockDefinition] = [:]
        var entities: [RawEntity] = []
        var unsupported: [String: Int] = [:]
        var unitWarning: String?
        var unitCode = 0
        var index = 0
        while index < pairs.count {
            let (code, value) = pairs[index]
            if code == 0, value == "SECTION" {
                section = string(pairs, after: index, code: 2) ?? ""
                index += 1
                continue
            }
            if code == 0, value == "ENDSEC" {
                section = ""
                index += 1
                continue
            }
            if code == 0, value == "TABLE" {
                table = string(pairs, after: index, code: 2) ?? ""
                index += 1
                continue
            }
            if code == 0, value == "ENDTAB" {
                table = ""
                index += 1
                continue
            }
            if code == 9, value == "$INSUNITS" {
                if let units = int(pairs, after: index, code: 70) {
                    unitCode = units
                    unitWarning = unitWarningText(units)
                }
                index += 1
                continue
            }
            if section == "TABLES", table == "LAYER", code == 0, value == "LAYER" {
                let record = takeRecord(pairs, from: index)
                if let name = first(record.pairs, 2) {
                    let aci = abs(firstInt(record.pairs, 62) ?? 7)
                    let color = firstInt(record.pairs, 420).map(DrawingColor.trueColor) ?? DrawingColor.aci(aci == 0 ? 7 : aci)
                    layers[name] = DrawingLayer(name: name, color: color, isVisible: true)
                }
                index = record.next
                continue
            }
            if section == "BLOCKS", code == 0, value == "BLOCK" {
                let block = takeBlock(pairs, from: index)
                blocks[block.name] = block.definition
                unsupported = merge(unsupported, block.unsupported)
                index = block.next
                continue
            }
            if section == "ENTITIES", code == 0 {
                if value == "POLYLINE" {
                    let polyline = takePolyline(pairs, from: index)
                    if let raw = polyline.entity {
                        entities.append(raw)
                    }
                    unsupported = merge(unsupported, polyline.unsupported)
                    index = polyline.next
                    continue
                }
                if value == "VERTEX" || value == "SEQEND" {
                    index += 1
                    continue
                }
                let record = takeRecord(pairs, from: index)
                if isPaperSpace(record.pairs) {
                    unsupported["PAPER", default: 0] += 1
                } else if let raw = rawEntity(type: value, pairs: record.pairs) {
                    entities.append(raw)
                } else if value != "ENDSEC" {
                    unsupported[value, default: 0] += 1
                }
                index = record.next
                continue
            }
            index += 1
        }

        if entities.isEmpty, let model = blocks.first(where: { $0.key.caseInsensitiveCompare("*Model_Space") == .orderedSame })?.value {
            entities = model.entities
        }

        var expanded = expand(entities, blocks: blocks, layers: layers, unsupported: &unsupported)
        for offset in expanded.indices {
            expanded[offset].id = offset
        }
        var known = Set(layers.keys)
        for entity in expanded where !known.contains(entity.layer) {
            layers[entity.layer] = DrawingLayer(name: entity.layer, color: entity.color, isVisible: true)
            known.insert(entity.layer)
        }
        let bounds = expanded.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let orderedLayers = layers.values.sorted { $0.name < $1.name }
        return DrawingDocument(
            layers: orderedLayers,
            entities: expanded,
            bounds: bounds,
            unsupportedCounts: unsupported,
            codePage: codePage,
            unitWarning: unitWarning,
            index: DrawingSpatialIndex(entities: expanded),
            unitCode: unitCode
        )
    }
}

struct RawEntity {
    var type: String
    var pairs: [(Int, String)]
}

struct BlockDefinition {
    var baseX: Double
    var baseY: Double
    var entities: [RawEntity]
}

private struct Taken {
    var pairs: [(Int, String)]
    var next: Int
}

private func takeRecord(_ pairs: [(Int, String)], from start: Int) -> Taken {
    var body: [(Int, String)] = []
    var index = start + 1
    while index < pairs.count {
        if pairs[index].0 == 0 { break }
        body.append(pairs[index])
        index += 1
    }
    return Taken(pairs: body, next: index)
}

private func takeBlock(_ pairs: [(Int, String)], from start: Int) -> (name: String, definition: BlockDefinition, unsupported: [String: Int], next: Int) {
    let header = takeRecord(pairs, from: start)
    let name = (first(header.pairs, 2) ?? "").trimmingCharacters(in: .whitespaces)
    var index = header.next
    var entities: [RawEntity] = []
    var unsupported: [String: Int] = [:]
    while index < pairs.count {
        let (code, value) = pairs[index]
        if code == 0, value == "ENDBLK" {
            index += 1
            break
        }
        if code == 0, value == "POLYLINE" {
            let polyline = takePolyline(pairs, from: index)
            if let entity = polyline.entity { entities.append(entity) }
            unsupported = merge(unsupported, polyline.unsupported)
            index = polyline.next
            continue
        }
        if code == 0 {
            let record = takeRecord(pairs, from: index)
            if isPaperSpace(record.pairs) {
                unsupported["PAPER", default: 0] += 1
            } else if let raw = rawEntity(type: value, pairs: record.pairs) {
                entities.append(raw)
            } else if value != "ENDBLK" {
                unsupported[value, default: 0] += 1
            }
            index = record.next
            continue
        }
        index += 1
    }
    let definition = BlockDefinition(
        baseX: firstDouble(header.pairs, 10) ?? 0,
        baseY: firstDouble(header.pairs, 20) ?? 0,
        entities: entities
    )
    return (name, definition, unsupported, index)
}

private func takePolyline(_ pairs: [(Int, String)], from start: Int) -> (entity: RawEntity?, unsupported: [String: Int], next: Int) {
    let header = takeRecord(pairs, from: start)
    var index = header.next
    var vertices: [(Int, String)] = []
    while index < pairs.count {
        let (code, value) = pairs[index]
        if code == 0, value == "VERTEX" {
            let vertex = takeRecord(pairs, from: index)
            vertices.append(contentsOf: vertex.pairs)
            index = vertex.next
            continue
        }
        if code == 0, value == "SEQEND" {
            index += 1
            break
        }
        break
    }
    if isPaperSpace(header.pairs) {
        return (nil, ["PAPER": 1], index)
    }
    var kept: [(point: PlanarPoint, bulge: Double, flag: Int)] = []
    var pendingX: Double?
    var pendingY: Double?
    var bulge = 0.0
    var flag = 0
    func flushVertex() {
        if let pendingX, let pendingY {
            kept.append((PlanarPoint(x: pendingX, y: pendingY), bulge, flag))
        }
        pendingX = nil
        pendingY = nil
        bulge = 0
        flag = 0
    }
    for pair in vertices {
        if pair.0 == 10, let x = Double(pair.1) {
            if pendingY != nil { flushVertex() }
            pendingX = x
        } else if pair.0 == 20, let y = Double(pair.1) {
            pendingY = y
        } else if pair.0 == 42, let value = Double(pair.1) {
            bulge = value
        } else if pair.0 == 70, let bits = Int(pair.1) {
            flag = bits
        }
    }
    flushVertex()
    let fitted = kept.contains { $0.flag & 8 != 0 }
    let chosen = fitted ? kept.filter { $0.flag & 8 != 0 } : kept.filter { $0.flag & 16 == 0 }
    let used = chosen.isEmpty ? kept : chosen
    var body = header.pairs.filter { $0.0 != 10 && $0.0 != 20 && $0.0 != 30 }
    for vertex in used {
        body.append((10, String(vertex.point.x)))
        body.append((20, String(vertex.point.y)))
        if abs(vertex.bulge) > 1e-12 { body.append((42, String(vertex.bulge))) }
    }
    return (RawEntity(type: "POLYLINE", pairs: body), [:], index)
}

private func isPaperSpace(_ pairs: [(Int, String)]) -> Bool {
    firstInt(pairs, 67) == 1
}

private func blockNamed(_ name: String, in blocks: [String: BlockDefinition]) -> BlockDefinition? {
    if let exact = blocks[name] { return exact }
    let trimmed = name.trimmingCharacters(in: .whitespaces)
    if let exact = blocks[trimmed] { return exact }
    return blocks.first { $0.key.caseInsensitiveCompare(trimmed) == .orderedSame }?.value
}

private func rawEntity(type: String, pairs: [(Int, String)]) -> RawEntity? {
    guard DXFParser.supportedTypes.contains(type) else { return nil }
    return RawEntity(type: type, pairs: pairs)
}

private func expand(
    _ entities: [RawEntity],
    blocks: [String: BlockDefinition],
    layers: [String: DrawingLayer],
    unsupported: inout [String: Int]
) -> [DrawingEntity] {
    var output: [DrawingEntity] = []
    func append(_ raw: RawEntity, transform: ((PlanarPoint) -> PlanarPoint)?, depth: Int, stack: Set<String>, byblock: DrawingColor?) {
        if raw.type == "INSERT" {
            if isPaperSpace(raw.pairs) {
                unsupported["PAPER", default: 0] += 1
                return
            }
            let name = (first(raw.pairs, 2) ?? "").trimmingCharacters(in: .whitespaces)
            if name.uppercased().hasPrefix("*PAPER_SPACE") { return }
            guard depth < 8, !stack.contains(name), let block = blockNamed(name, in: blocks) else {
                unsupported["INSERT(未定義)"] = (unsupported["INSERT(未定義)"] ?? 0) + 1
                return
            }
            let insert = PlanarPoint(x: firstDouble(raw.pairs, 10) ?? 0, y: firstDouble(raw.pairs, 20) ?? 0)
            let scaleX = firstDouble(raw.pairs, 41) ?? 1
            let scaleY = firstDouble(raw.pairs, 42) ?? scaleX
            let rotation = GeoMath.radians(fromDegrees: firstDouble(raw.pairs, 50) ?? 0)
            let cosR = GeoMath.cosine(rotation)
            let sinR = GeoMath.sine(rotation)
            let local: (PlanarPoint) -> PlanarPoint = { point in
                let x = point.x - block.baseX
                let y = point.y - block.baseY
                let moved = PlanarPoint(
                    x: insert.x + scaleX * (cosR * x - sinR * y),
                    y: insert.y + scaleY * (sinR * x + cosR * y)
                )
                return transform?(moved) ?? moved
            }
            var nextStack = stack
            nextStack.insert(name)
            let insertLayerName = first(raw.pairs, 8) ?? "0"
            let insertLayer = layers[insertLayerName] ?? DrawingLayer(name: insertLayerName, color: .white, isVisible: true)
            let insertColor = resolveColor(raw.pairs, layer: insertLayer, byblock: byblock)
            for child in block.entities {
                var nested = child
                if (first(nested.pairs, 8) ?? "0") == "0" {
                    nested.pairs.removeAll { $0.0 == 8 }
                    nested.pairs.insert((8, insertLayerName), at: 0)
                }
                append(nested, transform: local, depth: depth + 1, stack: nextStack, byblock: insertColor)
            }
            return
        }
        if isPaperSpace(raw.pairs) {
            unsupported["PAPER", default: 0] += 1
            return
        }
        if raw.type == "HATCH" {
            let transformed = transform.map { mapRaw(raw, $0) } ?? raw
            let outlines = hatchOutlines(transformed.pairs).filter { $0.count >= 2 }
            if outlines.isEmpty {
                unsupported["HATCH", default: 0] += 1
            }
            let layerName = first(transformed.pairs, 8) ?? "0"
            let layer = layers[layerName] ?? DrawingLayer(name: layerName, color: .white, isVisible: true)
            for outline in outlines {
                output.append(entity(
                    id: output.count,
                    layer: layer.name,
                    color: resolveColor(transformed.pairs, layer: layer, byblock: byblock),
                    primitive: .polyline(vertices: outline, closed: false, display: outline),
                    points: outline
                ))
            }
            return
        }
        let transformed = transform.map { mapRaw(raw, $0) } ?? raw
        if let entity = makeEntity(transformed, id: output.count, layers: layers, byblock: byblock) {
            output.append(entity)
        } else if raw.type != "INSERT" {
            unsupported[raw.type, default: 0] += 1
        }
    }
    for entity in entities {
        append(entity, transform: nil, depth: 0, stack: [], byblock: nil)
    }
    return output
}

private func mapRaw(_ raw: RawEntity, _ transform: (PlanarPoint) -> PlanarPoint) -> RawEntity {
    if raw.type == "ELLIPSE" { return mapEllipse(raw, transform) }
    var pairs = raw.pairs
    var index = 0
    var pendingX: Double?
    while index < pairs.count {
        let code = pairs[index].0
        if code == 10, let x = Double(pairs[index].1) {
            pendingX = x
        } else if code == 20, let y = Double(pairs[index].1), let x = pendingX {
            let moved = transform(PlanarPoint(x: x, y: y))
            if let xIndex = pairs[..<index].lastIndex(where: { $0.0 == 10 }) {
                pairs[xIndex].1 = String(moved.x)
            }
            pairs[index].1 = String(moved.y)
            pendingX = nil
        } else if code == 11, let x = Double(pairs[index].1), index + 1 < pairs.count, pairs[index + 1].0 == 21, let y = Double(pairs[index + 1].1) {
            let moved = transform(PlanarPoint(x: x, y: y))
            pairs[index].1 = String(moved.x)
            pairs[index + 1].1 = String(moved.y)
        }
        index += 1
    }
    if raw.type == "CIRCLE" || raw.type == "ARC" {
        let center = point(raw.pairs, x: 10, y: 20) ?? PlanarPoint(x: 0, y: 0)
        let radius = firstDouble(raw.pairs, 40) ?? 1
        let movedCenter = transform(center)
        let scaled = movedCenter.distance(to: transform(PlanarPoint(x: center.x + radius, y: center.y)))
        pairs.removeAll { $0.0 == 40 || $0.0 == 50 || $0.0 == 51 }
        pairs.append((40, String(scaled)))
        if raw.type == "ARC" {
            let start = firstDouble(raw.pairs, 50) ?? 0
            let end = firstDouble(raw.pairs, 51) ?? start
            pairs.append((50, String(mappedAngle(start, center: center, radius: radius, transform: transform, movedCenter: movedCenter))))
            pairs.append((51, String(mappedAngle(end, center: center, radius: radius, transform: transform, movedCenter: movedCenter))))
        }
    }
    return RawEntity(type: raw.type, pairs: pairs)
}

private func mapEllipse(_ raw: RawEntity, _ transform: (PlanarPoint) -> PlanarPoint) -> RawEntity {
    let center = point(raw.pairs, x: 10, y: 20) ?? PlanarPoint(x: 0, y: 0)
    let major = point(raw.pairs, x: 11, y: 21) ?? PlanarPoint(x: 1, y: 0)
    let movedCenter = transform(center)
    let movedEnd = transform(PlanarPoint(x: center.x + major.x, y: center.y + major.y))
    let vector = PlanarPoint(x: movedEnd.x - movedCenter.x, y: movedEnd.y - movedCenter.y)
    var pairs = raw.pairs.filter { $0.0 != 10 && $0.0 != 20 && $0.0 != 11 && $0.0 != 21 }
    pairs.append((10, String(movedCenter.x)))
    pairs.append((20, String(movedCenter.y)))
    pairs.append((11, String(vector.x)))
    pairs.append((21, String(vector.y)))
    return RawEntity(type: raw.type, pairs: pairs)
}

private func mappedAngle(
    _ degrees: Double,
    center: PlanarPoint,
    radius: Double,
    transform: (PlanarPoint) -> PlanarPoint,
    movedCenter: PlanarPoint
) -> Double {
    let radians = GeoMath.radians(fromDegrees: degrees)
    let moved = transform(PlanarPoint(
        x: center.x + radius * GeoMath.cosine(radians),
        y: center.y + radius * GeoMath.sine(radians)
    ))
    return GeoMath.degrees(fromRadians: GeoMath.arctangent(moved.y - movedCenter.y, moved.x - movedCenter.x))
}

private func makeEntity(_ raw: RawEntity, id: Int, layers: [String: DrawingLayer], byblock: DrawingColor?) -> DrawingEntity? {
    let layerName = first(raw.pairs, 8) ?? "0"
    let layer = layers[layerName] ?? DrawingLayer(name: layerName, color: .white, isVisible: true)
    let color = resolveColor(raw.pairs, layer: layer, byblock: byblock)
    switch raw.type {
    case "LINE":
        guard let start = point(raw.pairs, x: 10, y: 20), let end = point(raw.pairs, x: 11, y: 21) else { return nil }
        return entity(id: id, layer: layer.name, color: color, primitive: .line(start, end), points: [start, end])
    case "POINT":
        guard let origin = point(raw.pairs, x: 10, y: 20) else { return nil }
        return entity(id: id, layer: layer.name, color: color, primitive: .point(origin), points: [origin])
    case "CIRCLE":
        guard let center = point(raw.pairs, x: 10, y: 20), let radius = firstDouble(raw.pairs, 40), radius > 0 else { return nil }
        let bounds = DrawingBounds(minX: center.x - radius, minY: center.y - radius, maxX: center.x + radius, maxY: center.y + radius)
        return DrawingEntity(id: id, layer: layer.name, color: color, primitive: .circle(center: center, radius: radius), bounds: bounds)
    case "ARC":
        guard let center = point(raw.pairs, x: 10, y: 20), let radius = firstDouble(raw.pairs, 40), radius > 0 else { return nil }
        let start = firstDouble(raw.pairs, 50) ?? 0
        let end = firstDouble(raw.pairs, 51) ?? start
        let display = DrawingCurve.arc(center: center, radius: radius, startDegrees: start, endDegrees: end)
        return entity(id: id, layer: layer.name, color: color, primitive: .arc(center: center, radius: radius, startDegrees: start, endDegrees: end, display: display), points: display)
    case "TEXT":
        guard let origin = point(raw.pairs, x: 10, y: 20) else { return nil }
        let primitive = DrawingPrimitive.text(
            origin: origin,
            string: first(raw.pairs, 1) ?? "",
            height: firstDouble(raw.pairs, 40) ?? 1,
            rotationDegrees: firstDouble(raw.pairs, 50) ?? 0
        )
        return entity(id: id, layer: layer.name, color: color, primitive: primitive, points: [origin])
    case "MTEXT":
        guard let origin = point(raw.pairs, x: 10, y: 20) else { return nil }
        let string = mtext(raw.pairs)
        let primitive = DrawingPrimitive.text(
            origin: origin,
            string: string,
            height: firstDouble(raw.pairs, 40) ?? 1,
            rotationDegrees: firstDouble(raw.pairs, 50) ?? 0
        )
        return entity(id: id, layer: layer.name, color: color, primitive: primitive, points: [origin])
    case "LWPOLYLINE", "POLYLINE":
        let built = polyline(raw.pairs, closedBit: (firstInt(raw.pairs, 70) ?? 0) & 1 == 1)
        guard built.vertices.count >= 2 else { return nil }
        return entity(
            id: id,
            layer: layer.name,
            color: color,
            primitive: .polyline(vertices: built.vertices, closed: built.closed, display: built.display),
            points: built.display
        )
    case "SPLINE":
        let fit = coordinatePairs(raw.pairs, x: 11, y: 21)
        let controls = coordinatePairs(raw.pairs, x: 10, y: 20)
        let vertices = fit.count >= 2 ? fit : controls
        guard vertices.count >= 2 else { return nil }
        return entity(
            id: id,
            layer: layer.name,
            color: color,
            primitive: .polyline(vertices: vertices, closed: false, display: vertices),
            points: vertices
        )
    case "ELLIPSE":
        guard let center = point(raw.pairs, x: 10, y: 20), let major = point(raw.pairs, x: 11, y: 21) else { return nil }
        let ratio = firstDouble(raw.pairs, 40) ?? 1
        let start = firstDouble(raw.pairs, 41) ?? 0
        let end = firstDouble(raw.pairs, 42) ?? (2 * Double.pi)
        let display = ellipsePoints(center: center, major: major, ratio: ratio, start: start, end: end)
        guard display.count >= 2 else { return nil }
        return entity(
            id: id,
            layer: layer.name,
            color: color,
            primitive: .polyline(vertices: display, closed: false, display: display),
            points: display
        )
    default:
        return nil
    }
}

private func coordinatePairs(_ pairs: [(Int, String)], x: Int, y: Int) -> [PlanarPoint] {
    var points: [PlanarPoint] = []
    var pending: Double?
    for pair in pairs {
        if pair.0 == x, let value = Double(pair.1) {
            pending = value
        } else if pair.0 == y, let north = Double(pair.1), let east = pending {
            points.append(PlanarPoint(x: east, y: north))
            pending = nil
        }
    }
    return points
}

private func ellipsePoints(center: PlanarPoint, major: PlanarPoint, ratio: Double, start: Double, end: Double) -> [PlanarPoint] {
    let minor = PlanarPoint(x: -major.y * ratio, y: major.x * ratio)
    var sweep = end - start
    if sweep < 1e-9 { sweep += 2 * Double.pi }
    let steps = max(16, Int(ceil(abs(sweep) / (Double.pi / 12))))
    return (0...steps).map { step in
        let t = start + sweep * Double(step) / Double(steps)
        return PlanarPoint(
            x: center.x + major.x * GeoMath.cosine(t) + minor.x * GeoMath.sine(t),
            y: center.y + major.y * GeoMath.cosine(t) + minor.y * GeoMath.sine(t)
        )
    }
}

private func hatchOutlines(_ pairs: [(Int, String)]) -> [[PlanarPoint]] {
    guard let start = pairs.firstIndex(where: { $0.0 == 91 }) else { return [] }
    let paths = Int(pairs[start].1) ?? 0
    var index = start + 1
    var outlines: [[PlanarPoint]] = []
    for _ in 0..<paths {
        while index < pairs.count, pairs[index].0 != 92 { index += 1 }
        guard index < pairs.count, let flag = Int(pairs[index].1) else { break }
        index += 1
        if flag & 2 != 0 {
            var closed = false
            var count = 0
            while index < pairs.count, pairs[index].0 != 10, pairs[index].0 != 93 {
                if pairs[index].0 == 73 { closed = Int(pairs[index].1) == 1 }
                index += 1
            }
            if index < pairs.count, pairs[index].0 == 93 {
                count = Int(pairs[index].1) ?? 0
                index += 1
            }
            var vertices: [PlanarPoint] = []
            var pending: Double?
            var got = 0
            while index < pairs.count, got < max(count, 1) || (count == 0 && pairs[index].0 == 10) {
                if pairs[index].0 == 10, let x = Double(pairs[index].1) {
                    pending = x
                } else if pairs[index].0 == 20, let y = Double(pairs[index].1), let x = pending {
                    vertices.append(PlanarPoint(x: x, y: y))
                    pending = nil
                    got += 1
                    if count > 0, got >= count { index += 1; break }
                } else if pairs[index].0 == 92 || pairs[index].0 == 97 || pairs[index].0 == 75 {
                    break
                }
                index += 1
            }
            if closed, let first = vertices.first, vertices.last?.distance(to: first) ?? 1 > 1e-9 {
                vertices.append(first)
            }
            if vertices.count >= 2 { outlines.append(vertices) }
        } else {
            while index < pairs.count, pairs[index].0 != 93 { index += 1 }
            let edges = index < pairs.count ? Int(pairs[index].1) ?? 0 : 0
            if index < pairs.count { index += 1 }
            var vertices: [PlanarPoint] = []
            for _ in 0..<edges {
                while index < pairs.count, pairs[index].0 != 72 { index += 1 }
                guard index < pairs.count else { break }
                let kind = Int(pairs[index].1) ?? 1
                index += 1
                if kind == 1 {
                    let line = coordinatePairs(Array(pairs[index...].prefix(8)), x: 10, y: 20)
                    let ends = coordinatePairs(Array(pairs[index...].prefix(8)), x: 11, y: 21)
                    if let start = line.first { vertices.append(start) }
                    if let end = ends.first { vertices.append(end) }
                    while index < pairs.count, pairs[index].0 != 72, pairs[index].0 != 97, pairs[index].0 != 92 {
                        index += 1
                        if pairs[index - 1].0 == 21 { break }
                    }
                } else {
                    while index < pairs.count, pairs[index].0 != 72, pairs[index].0 != 97, pairs[index].0 != 92 { index += 1 }
                }
            }
            if vertices.count >= 2 { outlines.append(vertices) }
        }
        while index < pairs.count, pairs[index].0 != 92, pairs[index].0 != 75 {
            index += 1
        }
        if index < pairs.count, pairs[index].0 == 75 { break }
    }
    return outlines
}

private func entity(id: Int, layer: String, color: DrawingColor, primitive: DrawingPrimitive, points: [PlanarPoint]) -> DrawingEntity {
    DrawingEntity(id: id, layer: layer, color: color, primitive: primitive, bounds: DrawingBounds(enclosing: points))
}

private func polyline(_ pairs: [(Int, String)], closedBit: Bool) -> (vertices: [PlanarPoint], closed: Bool, display: [PlanarPoint]) {
    var vertices: [PlanarPoint] = []
    var bulges: [Double] = []
    var pendingX: Double?
    for pair in pairs {
        if pair.0 == 10, let x = Double(pair.1) {
            pendingX = x
        } else if pair.0 == 20, let y = Double(pair.1), let x = pendingX {
            vertices.append(PlanarPoint(x: x, y: y))
            bulges.append(0)
            pendingX = nil
        } else if pair.0 == 42, let bulge = Double(pair.1), !bulges.isEmpty {
            bulges[bulges.count - 1] = bulge
        }
    }
    var display: [PlanarPoint] = []
    guard !vertices.isEmpty else { return ([], closedBit, []) }
    let segments = closedBit ? vertices.count : vertices.count - 1
    if segments <= 0 { return (vertices, closedBit, vertices) }
    for index in 0..<segments {
        let start = vertices[index]
        let end = vertices[(index + 1) % vertices.count]
        let bulge = index < bulges.count ? bulges[index] : 0
        let piece = DrawingCurve.bulge(from: start, to: end, bulge: bulge)
        if display.isEmpty {
            display.append(contentsOf: piece)
        } else {
            display.append(contentsOf: piece.dropFirst())
        }
    }
    return (vertices, closedBit, display)
}

private func mtext(_ pairs: [(Int, String)]) -> String {
    var prefix = ""
    var body = ""
    for pair in pairs {
        if pair.0 == 3 { prefix += pair.1 }
        if pair.0 == 1 { body += pair.1 }
    }
    return (prefix + body).replacingOccurrences(of: "\\P", with: "\n")
}

private func resolveColor(_ pairs: [(Int, String)], layer: DrawingLayer, byblock: DrawingColor?) -> DrawingColor {
    if let trueColor = firstInt(pairs, 420) { return DrawingColor.trueColor(trueColor).onLightMap() }
    let aci = abs(firstInt(pairs, 62) ?? 256)
    if aci == 0 { return (byblock ?? DrawingColor.aci(7)).onLightMap() }
    if aci == 256 { return layer.color.onLightMap() }
    return DrawingColor.aci(aci).onLightMap()
}

private func point(_ pairs: [(Int, String)], x: Int, y: Int) -> PlanarPoint? {
    guard let x = firstDouble(pairs, x), let y = firstDouble(pairs, y) else { return nil }
    return PlanarPoint(x: x, y: y)
}

private func first(_ pairs: [(Int, String)], _ code: Int) -> String? {
    pairs.first { $0.0 == code }?.1
}

private func firstDouble(_ pairs: [(Int, String)], _ code: Int) -> Double? {
    guard let text = first(pairs, code) else { return nil }
    return Double(text)
}

private func firstInt(_ pairs: [(Int, String)], _ code: Int) -> Int? {
    guard let text = first(pairs, code) else { return nil }
    return Int(text)
}

private func string(_ pairs: [(Int, String)], after index: Int, code: Int) -> String? {
    var cursor = index + 1
    while cursor < pairs.count, pairs[cursor].0 != 0 {
        if pairs[cursor].0 == code { return pairs[cursor].1 }
        cursor += 1
    }
    return nil
}

private func int(_ pairs: [(Int, String)], after index: Int, code: Int) -> Int? {
    guard let text = string(pairs, after: index, code: code) else { return nil }
    return Int(text)
}

private func unitWarningText(_ units: Int) -> String? {
    switch units {
    case 0, 6: return nil
    case 1: return "DXF の単位はインチです。数値はそのまま読み、メートルへの縮尺は合わせで付きます。"
    case 2: return "DXF の単位はフィートです。数値はそのまま読み、メートルへの縮尺は合わせで付きます。"
    case 4: return "DXF の単位はミリです。数値はそのまま読み、メートルへの縮尺は合わせで付きます。"
    case 5: return "DXF の単位はセンチです。数値はそのまま読み、メートルへの縮尺は合わせで付きます。"
    default: return "DXF の単位コードは \(units) です。数値はそのまま読みます。"
    }
}

private func merge(_ left: [String: Int], _ right: [String: Int]) -> [String: Int] {
    var result = left
    for (key, value) in right { result[key, default: 0] += value }
    return result
}

enum DrawingCurve {
    static func circle(center: PlanarPoint, radius: Double) -> [PlanarPoint] {
        arc(center: center, radius: radius, startDegrees: 0, endDegrees: 360)
    }

    static func arc(center: PlanarPoint, radius: Double, startDegrees: Double, endDegrees: Double) -> [PlanarPoint] {
        var sweep = endDegrees - startDegrees
        while sweep <= 0 { sweep += 360 }
        if sweep > 360 { sweep = 360 }
        let steps = max(8, Int(ceil(sweep / 12)))
        return (0...steps).map { step in
            let degrees = startDegrees + sweep * Double(step) / Double(steps)
            let radians = GeoMath.radians(fromDegrees: degrees)
            return PlanarPoint(
                x: center.x + radius * GeoMath.cosine(radians),
                y: center.y + radius * GeoMath.sine(radians)
            )
        }
    }

    /// 正のバルジは始点から終点へ反時計回り。
    static func bulge(from start: PlanarPoint, to end: PlanarPoint, bulge: Double) -> [PlanarPoint] {
        if abs(bulge) < 1e-12 { return [start, end] }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let chord = GeoMath.hypotenuse(dx, dy)
        if chord < 1e-12 { return [start] }
        let theta = 4 * GeoMath.arctangent(bulge)
        let sine = GeoMath.sine(theta / 2)
        if abs(sine) < 1e-12 { return [start, end] }
        let radius = chord / (2 * sine)
        let mid = PlanarPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let leftX = -dy / chord
        let leftY = dx / chord
        let half = chord / 2
        let offset = GeoMath.squareRoot(max(0, radius * radius - half * half))
        let major: Double = abs(theta) > .pi ? -1 : 1
        let direction: Double = theta >= 0 ? 1 : -1
        let center = PlanarPoint(
            x: mid.x + direction * major * offset * leftX,
            y: mid.y + direction * major * offset * leftY
        )
        let startAngle = GeoMath.arctangent(start.y - center.y, start.x - center.x)
        let steps = max(6, Int(ceil(abs(theta) / (Double.pi / 12))))
        return (0...steps).map { step in
            let angle = startAngle + theta * Double(step) / Double(steps)
            return PlanarPoint(
                x: center.x + abs(radius) * GeoMath.cosine(angle),
                y: center.y + abs(radius) * GeoMath.sine(angle)
            )
        }
    }
}

public struct GeoCoord: Sendable, Equatable {
    public var latitudeDegrees: Double
    public var longitudeDegrees: Double

    public init(latitudeDegrees: Double, longitudeDegrees: Double) {
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
    }
}

public struct GeographicPath: Sendable, Equatable {
    public var coordinates: [GeoCoord]
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(coordinates: [GeoCoord], color: DrawingColor = DrawingColor(red: 0.12, green: 0.12, blue: 0.12)) {
        self.coordinates = coordinates
        self.red = color.red
        self.green = color.green
        self.blue = color.blue
    }
}

public struct DrawingInspect: Sendable, Equatable {
    public var drawingX: Double
    public var drawingY: Double
    public var eastingMeters: Double?
    public var northingMeters: Double?
    public var latitudeDegrees: Double?
    public var longitudeDegrees: Double?
    public var distanceMeters: Double?
    public var azimuthDegrees: Double?
    /// 測設で吸いついた種類。端点、交点、点。
    public var snapLabel: String?

    public init(
        drawingX: Double,
        drawingY: Double,
        eastingMeters: Double?,
        northingMeters: Double?,
        latitudeDegrees: Double?,
        longitudeDegrees: Double?,
        distanceMeters: Double?,
        azimuthDegrees: Double?,
        snapLabel: String? = nil
    ) {
        self.drawingX = drawingX
        self.drawingY = drawingY
        self.eastingMeters = eastingMeters
        self.northingMeters = northingMeters
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.distanceMeters = distanceMeters
        self.azimuthDegrees = azimuthDegrees
        self.snapLabel = snapLabel
    }
}

public struct OverlayBuild: Sendable, Equatable {
    public var paths: [GeographicPath]
    public var capped: Bool

    public init(paths: [GeographicPath], capped: Bool) {
        self.paths = paths
        self.capped = capped
    }
}

public struct UserOnDrawing: Sendable, Equatable {
    public var point: PlanarPoint
    /// 図面の単位での精度円。合わせの縮尺でメートルから戻す。
    public var accuracyRadius: Double

    public init(point: PlanarPoint, accuracyRadius: Double) {
        self.point = point
        self.accuracyRadius = accuracyRadius
    }
}

public enum DrawingPlacement {
    /// 頂点を捨てて図形ごと消さない。長い折線だけ間引き、上限までは全部載せる。
    public static let vertexLimit = 800_000
    private static let pointsPerStroke = 48

    public static func overlay(
        document: DrawingDocument,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool = false
    ) -> OverlayBuild {
        var paths: [GeographicPath] = []
        var count = 0
        var capped = false
        let visible = Set(document.layers.filter(\.isVisible).map(\.name))
        for entity in document.entities where visible.contains(entity.layer) {
            var stroke = entity.stroke
            guard stroke.count >= 2 else { continue }
            if stroke.count > pointsPerStroke {
                stroke = sample(stroke, count: pointsPerStroke)
                capped = true
            }
            let room = vertexLimit - count
            if room < 2 {
                capped = true
                break
            }
            if stroke.count > room {
                stroke = sample(stroke, count: room)
                capped = true
            }
            var coordinates: [GeoCoord] = []
            for point in stroke {
                guard let geo = geographic(point, zone: zone, axis: axis, transform: transform, composesAxis: composesAxis) else { continue }
                coordinates.append(geo)
            }
            if coordinates.count >= 2 {
                paths.append(GeographicPath(coordinates: coordinates, color: entity.color))
                count += coordinates.count
            }
        }
        return OverlayBuild(paths: paths, capped: capped)
    }

    private static func sample(_ points: [PlanarPoint], count: Int) -> [PlanarPoint] {
        guard count >= 2, let first = points.first, let last = points.last else { return points }
        if points.count <= count { return points }
        var kept: [PlanarPoint] = []
        kept.reserveCapacity(count)
        let steps = count - 1
        for step in 0..<steps {
            let index = Int((Double(step) * Double(points.count - 1) / Double(steps)).rounded())
            let point = points[min(index, points.count - 1)]
            if kept.last.map({ $0.distance(to: point) > 1e-9 }) ?? true {
                kept.append(point)
            }
        }
        if kept.last?.distance(to: last) ?? 1 > 1e-9 {
            kept.append(last)
        }
        return kept.isEmpty ? [first, last] : kept
    }

    public static func geographic(
        _ point: PlanarPoint,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool = false
    ) -> GeoCoord? {
        let plane = eastNorth(point, axis: axis, transform: transform, composesAxis: composesAxis)
        guard let geo = PlaneRectangular.inverse(
            northingMeters: plane.northing,
            eastingMeters: plane.easting,
            zone: zone
        ) else { return nil }
        return GeoCoord(latitudeDegrees: geo.latitudeDegrees, longitudeDegrees: geo.longitudeDegrees)
    }

    public static func user(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        horizontalAccuracyMeters: Double,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool = false
    ) -> UserOnDrawing? {
        guard let plane = PlaneRectangular.forward(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            zone: zone
        ) else { return nil }
        let drawing = drawingPoint(
            easting: plane.eastingMeters,
            northing: plane.northingMeters,
            axis: axis,
            transform: transform,
            composesAxis: composesAxis
        )
        guard let drawing else { return nil }
        let scale = abs(transform?.scale ?? 1)
        let radius = scale > 1e-15 ? horizontalAccuracyMeters / scale : horizontalAccuracyMeters
        return UserOnDrawing(point: drawing, accuracyRadius: radius)
    }

    public static func inspect(
        point: PlanarPoint,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        fromLatitude: Double?,
        fromLongitude: Double?,
        composesAxis: Bool = false,
        snapLabel: String? = nil
    ) -> DrawingInspect {
        let plane = eastNorth(point, axis: axis, transform: transform, composesAxis: composesAxis)
        let geo = PlaneRectangular.inverse(northingMeters: plane.northing, eastingMeters: plane.easting, zone: zone)
        var distance: Double?
        var azimuth: Double?
        if let geo, let fromLatitude, let fromLongitude,
           let inverse = GRS80Geodesic.inverse(
            latitude1: fromLatitude,
            longitude1: fromLongitude,
            latitude2: geo.latitudeDegrees,
            longitude2: geo.longitudeDegrees
           ) {
            distance = inverse.distanceMeters
            var degrees = inverse.azimuthDegrees
            while degrees < 0 { degrees += 360 }
            while degrees >= 360 { degrees -= 360 }
            azimuth = degrees
        }
        return DrawingInspect(
            drawingX: point.x,
            drawingY: point.y,
            eastingMeters: plane.easting,
            northingMeters: plane.northing,
            latitudeDegrees: geo?.latitudeDegrees,
            longitudeDegrees: geo?.longitudeDegrees,
            distanceMeters: distance,
            azimuthDegrees: azimuth,
            snapLabel: snapLabel
        )
    }

    /// 手合わせの変換は、図面の X Y をそのまま東・北へ写す。
    /// 背景の自動合わせは、先に軸で公共座標へ読んでから、その上で移動・回転する。
    private static func eastNorth(
        _ point: PlanarPoint,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool
    ) -> (easting: Double, northing: Double) {
        if let transform, composesAxis {
            let read = axis.plane(drawingX: point.x, drawingY: point.y)
            let placed = transform.apply(PlanarPoint(x: read.easting, y: read.northing))
            return (placed.x, placed.y)
        }
        if let transform {
            let placed = transform.apply(point)
            return (placed.x, placed.y)
        }
        return axis.plane(drawingX: point.x, drawingY: point.y)
    }

    private static func drawingPoint(
        easting: Double,
        northing: Double,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool
    ) -> PlanarPoint? {
        if let transform, composesAxis {
            guard let interpreted = transform.inverse(PlanarPoint(x: easting, y: northing)) else { return nil }
            return axis.drawing(easting: interpreted.x, northing: interpreted.y)
        }
        if let transform {
            return transform.inverse(PlanarPoint(x: easting, y: northing))
        }
        return axis.drawing(easting: easting, northing: northing)
    }
}
