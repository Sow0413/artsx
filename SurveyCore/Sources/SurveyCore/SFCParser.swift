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

public struct SFCPartialFigure: Equatable, Sendable {
    public var name: String
    public var figureCount: Int
    public var scale: String
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double
    public var isOn: Bool
}

public struct SFCBookPoint: Equatable, Sendable {
    public var name: String
    /// 座標表の X。北。
    public var northing: Double
    /// 座標表の Y。東。
    public var easting: Double
    public var zone: Int?
}

public struct SFCSurvey: Equatable, Sendable {
    public var figures: [SFCPartialFigure]
    /// オンの部分図だけ。いちばん図形の多いものを既定にする。
    public var document: DrawingDocument
    public var book: [SFCBookPoint]
    public var placementNote: String
}

public struct SFCAlignment: Equatable, Sendable {
    public var transform: Similarity2D
    public var rmsMeters: Double
    public var names: [String]
}

public enum SFCPointFit {
    /// 点名が座標表と合う組を先に使う。残差が 3 cm を超えるときは、先頭の2点だけで合わせる。
    public static func align(document: DrawingDocument, book: [SFCBookPoint]) -> SFCAlignment? {
        let markers = document.entities.compactMap { entity -> PlanarPoint? in
            if case let .point(point) = entity.primitive { return point }
            return nil
        }
        var pairs: [(PlanarPoint, PlanarPoint)] = []
        var names: [String] = []
        for item in book {
            guard let label = document.entities.first(where: { entity in
                if case let .text(_, string, _, _) = entity.primitive { return string == item.name }
                return false
            }), case let .text(origin, _, _, _) = label.primitive else { continue }
            guard let marker = markers.min(by: { origin.distance(to: $0) < origin.distance(to: $1) }) else { continue }
            pairs.append((marker, PlanarPoint(x: item.easting, y: item.northing)))
            names.append(item.name)
        }
        guard pairs.count >= 2 else { return nil }
        if let fit = SimilaritySolver.fit(pairs, lockScale: true), fit.rmsMeters <= 0.03 {
            return SFCAlignment(transform: fit.transform, rmsMeters: fit.rmsMeters, names: names)
        }
        let two = Array(pairs.prefix(2))
        guard let fit = SimilaritySolver.fit(two, lockScale: true) else { return nil }
        return SFCAlignment(transform: fit.transform, rmsMeters: fit.rmsMeters, names: Array(names.prefix(2)))
    }
}

public struct SFCPlacementRecord: Codable, Equatable, Sendable {
    public var fileName: String
    public var enabled: [String]
    public var eastingOrigin: Double?
    public var northingOrigin: Double?
    public var rmsMeters: Double?
}

public enum SFCPlacementStore {
    public static func save(_ record: SFCPlacementRecord, in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        let safe = record.fileName.replacingOccurrences(of: "/", with: "_")
        try data.write(to: directory.appendingPathComponent(safe + ".placement.json"), options: .atomic)
    }

    public static func load(fileName: String, in directory: URL) -> SFCPlacementRecord? {
        let safe = fileName.replacingOccurrences(of: "/", with: "_")
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(safe + ".placement.json")) else { return nil }
        return try? JSONDecoder().decode(SFCPlacementRecord.self, from: data)
    }
}

/// SXF Ver.2 / Ver.3 のテキスト形式（SFC）。ISO-10303-21 の注釈 `/*SXF … SXF*/` に入ったフィーチャを読む。
/// 公共座標の数値はそのまま残す。系は読み込んだ側で選ぶ。原本のバイト列は書き換えない。
public enum SFCParser {
    public static func parse(_ data: Data) throws -> DrawingDocument {
        try open(data).document
    }

    /// 部分図に分けて読む。sfig_org が無いファイルは、いままでどおり1枚。
    public static func open(_ data: Data) throws -> SFCSurvey {
        let decoded = try decode(data)
        guard decoded.text.contains("SXF") || decoded.text.contains("ISO-10303-21") else {
            throw SFCError.notSFC
        }
        let calls = featureCalls(in: decoded.text)
        guard !calls.isEmpty else { throw SFCError.notSFC }
        let version = version(in: decoded.text)
        if calls.contains(where: { $0.name == "sfig_org_feature" }) {
            return assemblePartial(calls, codePage: decoded.codePage, version: version)
        }
        let document = assemble(calls, codePage: decoded.codePage, version: version)
        return SFCSurvey(figures: [], document: document, book: book(in: document), placementNote: document.unitWarning ?? "")
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

    private static func assemblePartial(_ calls: [FeatureCall], codePage: String, version: String) -> SFCSurvey {
        let layers = layerList(calls)
        var unsupported: [String: Int] = [:]
        var locates: [String: Double] = [:]
        var groups: [(name: String, calls: [FeatureCall])] = []
        var bucket: [FeatureCall] = []
        for call in calls {
            switch call.name {
            case "layer_feature":
                break
            case "sfig_org_feature":
                let name = call.args.first?.text ?? "図\(groups.count + 1)"
                groups.append((name, bucket))
                bucket = []
                unsupported["sfig_org_feature", default: 0] += 1
            case "sfig_locate_feature":
                let name = call.args.count > 1 ? call.args[1].text : ""
                let scale = call.args.count > 5 ? (call.args[5].number ?? 1) : 1
                if !name.isEmpty { locates[name] = scale }
                unsupported["sfig_locate_feature", default: 0] += 1
            case "drawing_sheet_feature":
                unsupported["drawing_sheet_feature", default: 0] += 1
            default:
                bucket.append(call)
            }
        }
        let counted = groups.map { group -> (name: String, calls: [FeatureCall], count: Int) in
            let count = group.calls.filter { supported.contains($0.name) }.count
            return (group.name, group.calls, count)
        }
        let activeIndex = counted.enumerated().max { $0.element.count < $1.element.count }?.offset ?? 0
        var figures: [SFCPartialFigure] = []
        var built: [DrawingDocument] = []
        for (index, group) in counted.enumerated() {
            let document = figureDocument(
                group.calls,
                layers: layers,
                codePage: codePage,
                version: version,
                unsupported: &unsupported
            )
            built.append(document)
            let on = index == activeIndex
            figures.append(SFCPartialFigure(
                name: group.name,
                figureCount: group.count,
                scale: scaleLabel(locates[group.name]),
                minX: document.bounds.minX,
                minY: document.bounds.minY,
                maxX: document.bounds.maxX,
                maxY: document.bounds.maxY,
                isOn: on
            ))
        }
        let active = built.indices.contains(activeIndex) ? built[activeIndex] : DrawingDocument(
            layers: layers,
            entities: [],
            bounds: .empty,
            unsupportedCounts: unsupported,
            codePage: "SFC Ver\(version) \(codePage)",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: [])
        )
        let local = isSiteLocal(active.bounds)
        let scaled = active.unitCode == 1000
        var warning = ""
        if scaled {
            warning += "座標はミリメートルだったので、メートルに直しました。"
        }
        warning += local
            ? "位置合わせが必要。"
            : "公共座標として読みました。系を選ぶと、そのまま地図に載ります。"
        let notice = figures.map { figure in
            let state = figure.isOn ? "オン" : "オフ"
            return "\(figure.name) は\(state)。\(figure.figureCount)図形、縮尺 \(figure.scale)、範囲 X \(format(figure.minX))〜\(format(figure.maxX)) Y \(format(figure.minY))〜\(format(figure.maxY))。"
        }.joined()
        var document = active
        document.unitWarning = warning
        document.readNotice = notice
        document.unsupportedCounts = unsupported
        let whole = DrawingDocument(
            layers: layers,
            entities: built.flatMap(\.entities),
            bounds: built.reduce(DrawingBounds.empty) { $0.union($1.bounds) },
            unsupportedCounts: unsupported,
            codePage: document.codePage,
            unitWarning: warning,
            index: DrawingSpatialIndex(entities: built.flatMap(\.entities))
        )
        return SFCSurvey(
            figures: figures,
            document: document,
            book: book(in: whole),
            placementNote: warning
        )
    }

    private static func figureDocument(
        _ calls: [FeatureCall],
        layers: [DrawingLayer],
        codePage: String,
        version: String,
        unsupported: inout [String: Int]
    ) -> DrawingDocument {
        var entities: [DrawingEntity] = []
        var used = layers
        for call in calls where supported.contains(call.name) {
            guard let entity = entity(from: call, id: entities.count, layers: used) else {
                unsupported[call.name, default: 0] += 1
                continue
            }
            if !used.contains(where: { $0.name == entity.layer }) {
                used.append(DrawingLayer(name: entity.layer, color: entity.color, isVisible: true, role: .design))
            }
            entities.append(entity)
        }
        let rawBounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        let divisor = partialUnitsPerMeter(rawBounds)
        if divisor != 1 {
            entities = entities.map { scaled($0, by: 1 / divisor) }
        }
        let bounds = entities.reduce(DrawingBounds.empty) { $0.union($1.bounds) }
        return DrawingDocument(
            layers: used,
            entities: entities,
            bounds: bounds,
            unsupportedCounts: [:],
            codePage: "SFC Ver\(version) \(codePage)",
            unitWarning: nil,
            index: DrawingSpatialIndex(entities: entities),
            unitCode: Int(divisor)
        )
    }

    /// 部分図の中は、10 m を超える数値をミリメートルとみる。紙の上の表はそのまま。
    private static func partialUnitsPerMeter(_ bounds: DrawingBounds) -> Double {
        guard !bounds.isEmpty else { return 1 }
        let magnitude = max(abs(bounds.minX), abs(bounds.maxX), abs(bounds.minY), abs(bounds.maxY))
        if magnitude >= 1_000 { return 1000 }
        return 1
    }

    private static func isSiteLocal(_ bounds: DrawingBounds) -> Bool {
        guard !bounds.isEmpty else { return true }
        let magnitude = max(abs(bounds.minX), abs(bounds.maxX), abs(bounds.minY), abs(bounds.maxY))
        let span = max(bounds.width, bounds.height)
        if magnitude >= 10_000 && span >= 50 { return false }
        return true
    }

    private static func scaleLabel(_ scale: Double?) -> String {
        guard let scale, scale > 0 else { return "不明" }
        let denom = (1 / scale).rounded()
        if abs((1 / scale) - denom) < 0.05, denom >= 1 { return "1/\(Int(denom))" }
        return String(format: "%.4f", scale)
    }

    private static func format(_ value: Double) -> String {
        if value.isNaN || !value.isFinite { return "—" }
        return String(format: "%.0f", value)
    }

    private static func layerList(_ calls: [FeatureCall]) -> [DrawingLayer] {
        var names: [String] = []
        var visible: [Bool] = []
        for call in calls where call.name == "layer_feature" {
            names.append(call.args.first?.text ?? "レイヤ\(names.count + 1)")
            visible.append((call.args.dropFirst().first?.text ?? "1") != "0")
        }
        if names.isEmpty {
            names = ["0"]
            visible = [true]
        }
        return names.enumerated().map { index, name in
            DrawingLayer(
                name: name,
                color: .white,
                isVisible: visible[index],
                role: DrawingLayerRole.classify(layerName: name)
            )
        }
    }

    private static func book(in document: DrawingDocument) -> [SFCBookPoint] {
        var zone: Int?
        var points: [SFCBookPoint] = []
        for entity in document.entities {
            guard case let .text(_, string, _, _) = entity.primitive else { continue }
            if zone == nil { zone = zoneNumber(in: string) }
            let parts = string.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }).map(String.init)
            guard parts.count >= 3,
                  parts[0].range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil,
                  let north = Double(parts[1]),
                  let east = Double(parts[2]) else { continue }
            points.append(SFCBookPoint(name: parts[0], northing: north, easting: east, zone: zone))
        }
        if let zone {
            points = points.map { SFCBookPoint(name: $0.name, northing: $0.northing, easting: $0.easting, zone: zone) }
        }
        return points
    }

    private static func zoneNumber(in text: String) -> Int? {
        let romans = ["XIX", "XVIII", "XVII", "XVI", "XV", "XIV", "XIII", "XII", "XI", "X", "IX", "VIII", "VII", "VI", "V", "IV", "III", "II", "I"]
        for (offset, roman) in romans.enumerated() {
            if text.contains("第\(roman)系") || text.contains("\(roman)系") {
                return romans.count - offset
            }
        }
        return nil
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
        return DrawingEntity(id: entity.id, layer: entity.layer, color: entity.color, primitive: primitive, bounds: bounds)
    }

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
