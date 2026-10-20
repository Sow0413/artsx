import Foundation

/// 背景レイヤの線を、すでに同じ平面（東・北、メートル）にある参照線と比べる。
public enum BackgroundOutcome: Sendable, Equatable {
    /// 数値そのままで地理院ベクトルに載る。
    case usableAsIs
    /// 平行移動・回転で載る。translation は図面を参照へ動かす量。
    case shifted(distanceMeters: Double, azimuthDegrees: Double, transform: Similarity2D, rmsMeters: Double)
    /// 合わない図面。手で合わせる。
    case unmatched
    case insufficient
}

public struct BackgroundVerdict: Sendable, Equatable {
    public var outcome: BackgroundOutcome
    public var axis: DrawingAxis
    public var medianMeters: Double
    public var withinFiveRatio: Double
    public var message: String

    public init(
        outcome: BackgroundOutcome,
        axis: DrawingAxis,
        medianMeters: Double,
        withinFiveRatio: Double,
        message: String
    ) {
        self.outcome = outcome
        self.axis = axis
        self.medianMeters = medianMeters
        self.withinFiveRatio = withinFiveRatio
        self.message = message
    }

    public var suggestsShift: Bool {
        if case .shifted = outcome { return true }
        return false
    }
}

public enum DrawingGeometry {
    /// 背景レイヤの線を、軸の読み方で東・北（メートル）にする。非表示でも照合には使う。
    public static func backgroundPlaneSegments(document: DrawingDocument, axis: DrawingAxis) -> [Segment2D] {
        let names = Set(document.layers.filter { $0.role == .background }.map(\.name))
        var segments: [Segment2D] = []
        for entity in document.entities where names.contains(entity.layer) {
            let stroke = entity.stroke
            guard stroke.count >= 2 else { continue }
            let step = max(1, stroke.count / 48)
            var previous: PlanarPoint?
            for (index, point) in stroke.enumerated() where index % step == 0 || index == stroke.count - 1 {
                let plane = axis.plane(drawingX: point.x, drawingY: point.y)
                let placed = PlanarPoint(x: plane.easting, y: plane.northing)
                if let previous, previous.distance(to: placed) > 0.05 {
                    segments.append(Segment2D(start: previous, end: placed))
                }
                previous = placed
                if segments.count >= 1_500 { return segments }
            }
        }
        return segments
    }

    public static func geoBounds(segments: [Segment2D], zone: Int) -> GeoBounds? {
        var south = Double.greatestFiniteMagnitude
        var north = -Double.greatestFiniteMagnitude
        var west = Double.greatestFiniteMagnitude
        var east = -Double.greatestFiniteMagnitude
        var count = 0
        for segment in segments {
            for point in [segment.start, segment.end] {
                guard let geo = PlaneRectangular.inverse(
                    northingMeters: point.y,
                    eastingMeters: point.x,
                    zone: zone
                ) else { continue }
                south = min(south, geo.latitudeDegrees)
                north = max(north, geo.latitudeDegrees)
                west = min(west, geo.longitudeDegrees)
                east = max(east, geo.longitudeDegrees)
                count += 1
            }
        }
        guard count >= 2, south <= north, west <= east else { return nil }
        return GeoBounds(south: south - 0.002, west: west - 0.002, north: north + 0.002, east: east + 0.002)
    }
}

public enum BackgroundChecker {
    public static let matchMedianMeters = 2.0
    public static let matchWithinMeters = 5.0
    public static let matchRatio = 0.60

    /// 変換が無いときは両方の軸を試し、よく合う方を残す。合わない図面はそのまま unmatched。
    public static func judge(
        document: DrawingDocument,
        reference: [Segment2D],
        currentAxis: DrawingAxis
    ) -> BackgroundVerdict {
        let axes: [DrawingAxis] = currentAxis == .cadEastNorth
            ? [.cadEastNorth, .surveyNorthEast]
            : [.surveyNorthEast, .cadEastNorth]
        var best: BackgroundVerdict?
        for axis in axes {
            let source = DrawingGeometry.backgroundPlaneSegments(document: document, axis: axis)
            let verdict = compare(drawing: source, reference: reference, axis: axis)
            if best == nil || rank(verdict) < rank(best!) {
                best = verdict
            }
        }
        guard var verdict = best else {
            return insufficient(axis: currentAxis)
        }
        if verdict.axis != currentAxis, verdict.outcome != .insufficient {
            verdict.message = "軸は「\(verdict.axis.label)」の方が合います。" + verdict.message
        }
        return verdict
    }

    public static func compare(drawing: [Segment2D], reference: [Segment2D], axis: DrawingAxis) -> BackgroundVerdict {
        guard drawing.count >= 1, reference.count >= 1 else { return insufficient(axis: axis) }
        let samples = sample(drawing, spacing: 2, limit: 240)
        guard samples.count >= 2 else { return insufficient(axis: axis) }
        let index = SegmentGrid(segments: reference, cell: 40)
        var distances: [Double] = []
        var within = 0
        for point in samples {
            guard let nearest = index.nearest(to: point, within: 80) else {
                distances.append(80)
                continue
            }
            let distance = point.distance(to: nearest)
            distances.append(distance)
            if distance <= matchWithinMeters { within += 1 }
        }
        let median = medianOf(distances)
        let ratio = Double(within) / Double(samples.count)
        if median <= matchMedianMeters && ratio >= matchRatio {
            return BackgroundVerdict(
                outcome: .usableAsIs,
                axis: axis,
                medianMeters: median,
                withinFiveRatio: ratio,
                message: "座標あり・そのまま使える。背景の線は地理院ベクトルに載っています。"
            )
        }
        let request = ICP2DRequest(
            source: drawing,
            target: reference,
            initial: .identity,
            lockScale: true,
            maxIterations: 25,
            sampleSpacingMeters: 2,
            outlierMeters: 30
        )
        guard let aligned = ICP2D.align(request) else {
            return unmatched(axis: axis, median: median, ratio: ratio)
        }
        let east = aligned.transform.translationEasting
        let north = aligned.transform.translationNorthing
        let shift = GeoMath.hypotenuse(east, north)
        var rotation = aligned.transform.rotationDegrees
        while rotation > 180 { rotation -= 360 }
        while rotation < -180 { rotation += 360 }
        if aligned.rmsMeters <= 2, shift < 0.5, abs(rotation) <= 5 {
            return BackgroundVerdict(
                outcome: .usableAsIs,
                axis: axis,
                medianMeters: median,
                withinFiveRatio: ratio,
                message: "座標あり・そのまま使える。背景の線は地理院ベクトルに載っています。"
            )
        }
        if aligned.rmsMeters <= 3, shift >= 0.5 || abs(rotation) > 5 {
            var azimuth = GeoMath.degrees(fromRadians: GeoMath.arctangent(east, north))
            while azimuth < 0 { azimuth += 360 }
            while azimuth >= 360 { azimuth -= 360 }
            var message = "ずれ \(formatMeters(shift))、北から時計回り \(String(format: "%.0f", azimuth))°。図面をその向きに動かすと載ります。"
            if abs(rotation) > 5 {
                message += "回転 \(String(format: "%.1f", rotation))°。"
            }
            message += "ICP の残差 \(formatMeters(aligned.rmsMeters))。"
            return BackgroundVerdict(
                outcome: .shifted(
                    distanceMeters: shift,
                    azimuthDegrees: azimuth,
                    transform: aligned.transform,
                    rmsMeters: aligned.rmsMeters
                ),
                axis: axis,
                medianMeters: median,
                withinFiveRatio: ratio,
                message: message
            )
        }
        return unmatched(axis: axis, median: median, ratio: ratio)
    }

    private static func unmatched(axis: DrawingAxis, median: Double, ratio: Double) -> BackgroundVerdict {
        BackgroundVerdict(
            outcome: .unmatched,
            axis: axis,
            medianMeters: median,
            withinFiveRatio: ratio,
            message: "背景の線が地理院ベクトルと合いません。合わない図面として、手で合わせてください。"
        )
    }

    private static func insufficient(axis: DrawingAxis) -> BackgroundVerdict {
        BackgroundVerdict(
            outcome: .insufficient,
            axis: axis,
            medianMeters: .greatestFiniteMagnitude,
            withinFiveRatio: 0,
            message: "照合できる背景の線が足りません。"
        )
    }

    private static func rank(_ verdict: BackgroundVerdict) -> (Int, Double) {
        let kind: Int
        switch verdict.outcome {
        case .usableAsIs: kind = 0
        case .shifted: kind = 1
        case .unmatched: kind = 2
        case .insufficient: kind = 3
        }
        return (kind, verdict.medianMeters)
    }

    private static func medianOf(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func sample(_ segments: [Segment2D], spacing: Double, limit: Int) -> [PlanarPoint] {
        var points: [PlanarPoint] = []
        for segment in segments {
            let length = segment.length
            if length < 1e-9 {
                points.append(segment.start)
            } else {
                let steps = min(16, max(1, Int(ceil(length / spacing))))
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    points.append(PlanarPoint(
                        x: segment.start.x + (segment.end.x - segment.start.x) * t,
                        y: segment.start.y + (segment.end.y - segment.start.y) * t
                    ))
                }
            }
            if points.count >= limit { break }
        }
        return points
    }

    private static func formatMeters(_ meters: Double) -> String {
        if meters >= 1000 { return String(format: "%.1f km", meters / 1000) }
        if meters >= 100 { return String(format: "%.0f m", meters) }
        return String(format: "%.1f m", meters)
    }
}

/// 地理院ベクトルタイル（基盤地図情報の実験的ベクトルタイル）を、自前の protobuf で線にする。
public enum GSIVectorTile {
    public static let urlTemplate = "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/{z}/{x}/{y}.pbf"
    public static let layerNames: Set<String> = ["RdEdg", "BldL", "WL", "Cstline", "RdCompt", "BldA"]

    public static func url(z: Int, x: Int, y: Int) -> URL? {
        URL(string: "https://cyberjapandata.gsi.go.jp/xyz/experimental_bvmap/\(z)/\(x)/\(y).pbf")
    }

    /// z=16 から始め、9枚を超えるあいだは z=12 まで下げる。まだ多ければ先頭9枚。
    public static func cappedTiles(covering bounds: GeoBounds, startZoom: Int = 16, maxTiles: Int = 9, minimumZoom: Int = 12) -> [TileID] {
        var zoom = startZoom
        var tiles = TileMath.tiles(intersecting: bounds, zoom: zoom, style: .gsiStandard)
        while tiles.count > maxTiles && zoom > minimumZoom {
            zoom -= 1
            tiles = TileMath.tiles(intersecting: bounds, zoom: zoom, style: .gsiStandard)
        }
        if tiles.count > maxTiles {
            return Array(tiles.prefix(maxTiles))
        }
        return tiles
    }

    /// 道路縁・建物外周などの線を、指定した系の東・北（メートル）にする。
    public static func segments(protobuf data: Data, tile: TileID, zone: Int) -> [Segment2D] {
        var segments: [Segment2D] = []
        for layer in Protobuf.layers(in: data) where layerNames.contains(layer.name) {
            let extent = Double(layer.extent > 0 ? layer.extent : 4096)
            for feature in layer.features {
                let rings = Protobuf.rings(geometry: feature.geometry)
                for ring in rings {
                    guard ring.count >= 2 else { continue }
                    for index in 0..<(ring.count - 1) {
                        let start = plane(ring[index], tile: tile, extent: extent, zone: zone)
                        let end = plane(ring[index + 1], tile: tile, extent: extent, zone: zone)
                        guard let start, let end, start.distance(to: end) > 0.05 else { continue }
                        segments.append(Segment2D(start: start, end: end))
                        if segments.count >= 4_000 { return segments }
                    }
                }
            }
        }
        return segments
    }

    private static func plane(_ local: (x: Int, y: Int), tile: TileID, extent: Double, zone: Int) -> PlanarPoint? {
        let geo = TileMath.unproject(
            tileX: tile.x,
            tileY: tile.y,
            zoom: tile.z,
            xFraction: Double(local.x) / extent,
            yFraction: Double(local.y) / extent
        )
        guard let projected = PlaneRectangular.forward(
            latitudeDegrees: geo.latitudeDegrees,
            longitudeDegrees: geo.longitudeDegrees,
            zone: zone
        ) else { return nil }
        return PlanarPoint(x: projected.eastingMeters, y: projected.northingMeters)
    }
}

enum Protobuf {
    struct Feature {
        var geometry: [UInt64] = []
    }

    struct Layer {
        var name = ""
        var extent = 4096
        var features: [Feature] = []
    }

    static func layers(in data: Data) -> [Layer] {
        var layers: [Layer] = []
        for field in fields(in: data) where field.number == 3 && field.wire == 2 {
            layers.append(layer(field.bytes))
        }
        return layers
    }

    static func rings(geometry: [UInt64]) -> [[(x: Int, y: Int)]] {
        var rings: [[(x: Int, y: Int)]] = []
        var ring: [(x: Int, y: Int)] = []
        var cursorX = 0
        var cursorY = 0
        var index = 0
        func close() {
            if ring.count >= 2 { rings.append(ring) }
            ring = []
        }
        while index < geometry.count {
            let command = Int(geometry[index])
            index += 1
            let id = command & 7
            let count = command >> 3
            if id == 1 || id == 2 {
                if id == 1 { close() }
                for _ in 0..<count {
                    guard index + 1 < geometry.count else { return rings }
                    cursorX += zigzag(geometry[index])
                    cursorY += zigzag(geometry[index + 1])
                    index += 2
                    ring.append((cursorX, cursorY))
                }
            } else if id == 7 {
                if let first = ring.first, ring.last.map({ $0.x != first.x || $0.y != first.y }) ?? false {
                    ring.append(first)
                }
                close()
            } else {
                break
            }
        }
        close()
        return rings
    }

    private static func layer(_ data: Data) -> Layer {
        var layer = Layer()
        for field in fields(in: data) {
            switch (field.number, field.wire) {
            case (1, 2):
                layer.name = String(data: field.bytes, encoding: .utf8) ?? ""
            case (2, 2):
                layer.features.append(feature(field.bytes))
            case (5, 0):
                layer.extent = Int(field.varint)
            default:
                break
            }
        }
        return layer
    }

    private static func feature(_ data: Data) -> Feature {
        var feature = Feature()
        for field in fields(in: data) where field.number == 4 {
            if field.wire == 2 {
                feature.geometry.append(contentsOf: varints(in: field.bytes))
            } else if field.wire == 0 {
                feature.geometry.append(field.varint)
            }
        }
        return feature
    }

    struct Field {
        var number: Int
        var wire: Int
        var varint: UInt64 = 0
        var bytes = Data()
    }

    private static func fields(in data: Data) -> [Field] {
        var result: [Field] = []
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            guard let key = readVarint(bytes, index: &index) else { break }
            let wire = Int(key & 7)
            let number = Int(key >> 3)
            var field = Field(number: number, wire: wire)
            switch wire {
            case 0:
                guard let value = readVarint(bytes, index: &index) else { return result }
                field.varint = value
            case 1:
                guard index + 8 <= bytes.count else { return result }
                index += 8
            case 2:
                guard let length = readVarint(bytes, index: &index) else { return result }
                let count = Int(length)
                guard index + count <= bytes.count else { return result }
                field.bytes = Data(bytes[index..<(index + count)])
                index += count
            case 5:
                guard index + 4 <= bytes.count else { return result }
                index += 4
            default:
                return result
            }
            result.append(field)
        }
        return result
    }

    private static func varints(in data: Data) -> [UInt64] {
        var values: [UInt64] = []
        var index = 0
        let bytes = [UInt8](data)
        while index < bytes.count {
            guard let value = readVarint(bytes, index: &index) else { break }
            values.append(value)
        }
        return values
    }

    private static func readVarint(_ bytes: [UInt8], index: inout Int) -> UInt64? {
        var value: UInt64 = 0
        var shift = 0
        while index < bytes.count, shift <= 63 {
            let byte = bytes[index]
            index += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    private static func zigzag(_ value: UInt64) -> Int {
        let n = Int(value)
        return (n >> 1) ^ -(n & 1)
    }
}
