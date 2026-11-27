import Foundation

/// 読み込み時に一度だけ作る、経緯度の格子索引。地図は見えている範囲だけをここから取る。
public struct DrawingMapIndex: Sendable {
    public static let vertexBudget = 60_000
    public static let empty = DrawingMapIndex()

    public struct Query: Sendable {
        public var paths: [GeographicPath]
        public var capped: Bool
    }

    public var bounds: GeoBounds?
    private var cell = 1.0
    private var buckets: [Int64: [Int]] = [:]
    private var wide: [Int] = []
    private var strokes: [Stroke] = []

    private struct Stroke {
        var coordinates: [GeoCoord]
        var red: Double
        var green: Double
        var blue: Double
        var south: Double
        var west: Double
        var north: Double
        var east: Double
    }

    public static func build(
        document: DrawingDocument,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool = false
    ) -> DrawingMapIndex {
        let visible = Set(document.layers.filter(\.isVisible).map(\.name))
        var placed: [Stroke] = []
        placed.reserveCapacity(min(document.entities.count, 200_000))
        var south = Double.greatestFiniteMagnitude
        var north = -Double.greatestFiniteMagnitude
        var west = Double.greatestFiniteMagnitude
        var east = -Double.greatestFiniteMagnitude
        for entity in document.entities where visible.contains(entity.layer) {
            let source = entity.stroke
            guard source.count >= 2 else { continue }
            let simplified = source.count > 48 ? Self.samplePlanar(source, count: 48) : source
            var coordinates: [GeoCoord] = []
            coordinates.reserveCapacity(simplified.count)
            for point in simplified {
                guard let geo = DrawingPlacement.geographic(
                    point,
                    zone: zone,
                    axis: axis,
                    transform: transform,
                    composesAxis: composesAxis
                ) else { continue }
                coordinates.append(geo)
            }
            guard coordinates.count >= 2 else { continue }
            var strokeSouth = coordinates[0].latitudeDegrees
            var strokeNorth = strokeSouth
            var strokeWest = coordinates[0].longitudeDegrees
            var strokeEast = strokeWest
            for coordinate in coordinates.dropFirst() {
                strokeSouth = min(strokeSouth, coordinate.latitudeDegrees)
                strokeNorth = max(strokeNorth, coordinate.latitudeDegrees)
                strokeWest = min(strokeWest, coordinate.longitudeDegrees)
                strokeEast = max(strokeEast, coordinate.longitudeDegrees)
            }
            south = min(south, strokeSouth)
            north = max(north, strokeNorth)
            west = min(west, strokeWest)
            east = max(east, strokeEast)
            placed.append(Stroke(
                coordinates: coordinates,
                red: entity.color.red,
                green: entity.color.green,
                blue: entity.color.blue,
                south: strokeSouth,
                west: strokeWest,
                north: strokeNorth,
                east: strokeEast
            ))
        }
        var index = DrawingMapIndex()
        guard !placed.isEmpty else { return index }
        index.bounds = GeoBounds(south: south, west: west, north: north, east: east)
        let span = max(north - south, east - west, 1e-8)
        index.cell = max(span / 48, 1e-8)
        index.strokes = placed
        for (id, stroke) in placed.enumerated() {
            let x0 = Int(floor(stroke.west / index.cell))
            let x1 = Int(floor(stroke.east / index.cell))
            let y0 = Int(floor(stroke.south / index.cell))
            let y1 = Int(floor(stroke.north / index.cell))
            if x1 - x0 > 4 || y1 - y0 > 4 {
                index.wide.append(id)
                continue
            }
            if x0 > x1 || y0 > y1 { continue }
            for ix in x0...x1 {
                for iy in y0...y1 {
                    index.buckets[key(ix, iy), default: []].append(id)
                }
            }
        }
        return index
    }

    /// 読み込んだ直後の全体。画面に対して 1pt 未満の線は省き、頂点は予算まで。
    public func fitted(screenPoints: Double = 390) -> Query {
        guard let bounds else { return Query(paths: [], capped: false) }
        let span = max(meters(bounds.south, bounds.west, bounds.north, bounds.east), 1)
        let metersPerPixel = span / max(screenPoints, 1)
        return paths(
            south: bounds.south,
            west: bounds.west,
            north: bounds.north,
            east: bounds.east,
            metersPerPixel: metersPerPixel,
            vertexBudget: Self.vertexBudget
        )
    }

    /// 見えている範囲。呼び出し側が約 1.5 倍に広げた矩形を渡す。
    public func paths(
        south: Double,
        west: Double,
        north: Double,
        east: Double,
        metersPerPixel: Double,
        vertexBudget: Int = vertexBudget
    ) -> Query {
        let ids = lookup(south: south, west: west, north: north, east: east)
        let pixel = max(metersPerPixel, 1e-6)
        var chosen: [(id: Int, weight: Double)] = []
        chosen.reserveCapacity(ids.count)
        for id in ids {
            let stroke = strokes[id]
            guard stroke.south <= north, stroke.north >= south, stroke.west <= east, stroke.east >= west else { continue }
            let size = meters(stroke.south, stroke.west, stroke.north, stroke.east)
            if size < pixel { continue }
            chosen.append((id, size))
        }
        var budget = max(vertexBudget, 2)
        var pointCap = 24
        var estimate = chosen.reduce(0) { $0 + min(strokes[$1.id].coordinates.count, pointCap) }
        if estimate > budget {
            pointCap = 2
            estimate = chosen.count * 2
        }
        if estimate > budget {
            chosen.sort { $0.weight > $1.weight }
        }
        var paths: [GeographicPath] = []
        var used = 0
        var capped = false
        for item in chosen {
            let source = strokes[item.id].coordinates
            let count = min(source.count, pointCap)
            if used + count > budget {
                capped = true
                if budget - used < 2 { break }
            }
            let coordinates = count >= source.count ? source : Self.sample(source, count: max(2, budget - used))
            guard coordinates.count >= 2 else { continue }
            if used + coordinates.count > budget {
                capped = true
                break
            }
            let stroke = strokes[item.id]
            paths.append(GeographicPath(
                coordinates: coordinates,
                color: DrawingColor(red: stroke.red, green: stroke.green, blue: stroke.blue)
            ))
            used += coordinates.count
        }
        return Query(paths: paths, capped: capped)
    }

    /// 画面の縦横を 1.5 倍にした範囲。パンしても、ここを出るまで描き直さない。
    public static func buffer(south: Double, west: Double, north: Double, east: Double) -> GeoBounds {
        let lat = max(north - south, 1e-8)
        let lon = max(east - west, 1e-8)
        let midLat = (south + north) / 2
        let midLon = (west + east) / 2
        return GeoBounds(
            south: midLat - lat * 0.75,
            west: midLon - lon * 0.75,
            north: midLat + lat * 0.75,
            east: midLon + lon * 0.75
        )
    }

    public static func contains(inner: GeoBounds, in outer: GeoBounds) -> Bool {
        inner.south >= outer.south && inner.north <= outer.north && inner.west >= outer.west && inner.east <= outer.east
    }

    private func lookup(south: Double, west: Double, north: Double, east: Double) -> [Int] {
        guard cell > 0 else { return [] }
        let x0 = Int(floor(west / cell))
        let x1 = Int(floor(east / cell))
        let y0 = Int(floor(south / cell))
        let y1 = Int(floor(north / cell))
        if x1 < x0 || y1 < y0 { return wide }
        if x1 - x0 > 64 || y1 - y0 > 64 {
            return Array(strokes.indices)
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
        for id in wide where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    private func meters(_ south: Double, _ west: Double, _ north: Double, _ east: Double) -> Double {
        let latitude = (north - south) * 111_320
        let radians = (south + north) * 0.5 * .pi / 180
        let longitude = (east - west) * 111_320 * max(0.2, abs(GeoMath.cosine(radians)))
        return max(latitude, longitude)
    }

    private static func samplePlanar(_ points: [PlanarPoint], count: Int) -> [PlanarPoint] {
        guard count >= 2, let last = points.last else { return points }
        if points.count <= count { return points }
        var kept: [PlanarPoint] = []
        let steps = count - 1
        for step in 0..<steps {
            let index = min(points.count - 1, Int((Double(step) * Double(points.count - 1) / Double(steps)).rounded()))
            kept.append(points[index])
        }
        kept.append(last)
        return kept
    }

    private static func sample(_ points: [GeoCoord], count: Int) -> [GeoCoord] {
        guard count >= 2, let last = points.last else { return points }
        if points.count <= count { return points }
        var kept: [GeoCoord] = []
        let steps = count - 1
        for step in 0..<steps {
            let index = min(points.count - 1, Int((Double(step) * Double(points.count - 1) / Double(steps)).rounded()))
            kept.append(points[index])
        }
        kept.append(last)
        return kept
    }

    private static func key(_ x: Int, _ y: Int) -> Int64 {
        Int64(x) &* 73856093 ^ Int64(y) &* 19349663
    }
}
