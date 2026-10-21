import Foundation

/// 1枚の地理院タイルを、図面の座標へ置いた位置。
/// 画像の (0, 0) が北西、(1, 0) が北東、(0, 1) が南西。画面への回転は図面カメラがやる。
public struct DrawingMapFrame: Equatable, Sendable {
    public var tile: TileID
    public var northWest: PlanarPoint
    public var northEast: PlanarPoint
    public var southWest: PlanarPoint

    public init(tile: TileID, northWest: PlanarPoint, northEast: PlanarPoint, southWest: PlanarPoint) {
        self.tile = tile
        self.northWest = northWest
        self.northEast = northEast
        self.southWest = southWest
    }
}

/// 図面の見える範囲に、地理院タイルを図面座標で敷く。
public enum DrawingBaseMap {
    /// Web メルカトル z=0 の赤道での1ピクセル。メートル。
    public static let equatorialMetersPerPixel = 156543.03392804097

    public static func metersPerPixel(scale: Double, pointsPerUnit: Double) -> Double {
        let metres = scale.isFinite && abs(scale) > 1e-15 ? abs(scale) : 1
        let points = pointsPerUnit.isFinite && pointsPerUnit > 1e-12 ? pointsPerUnit : 1e-12
        return metres / points
    }

    /// 画面の1ピクセルが図面の何メートルかに近いズーム。種類の実在範囲で切る。
    public static func zoom(latitudeDegrees: Double, metersPerPixel: Double, style: BaseMapStyle) -> Int {
        let range = GSITileCatalog.sourceZoomRange(for: style)
        let metres = metersPerPixel.isFinite && metersPerPixel > 1e-9 ? metersPerPixel : 1e-9
        let latitude = min(max(latitudeDegrees, -TileMath.maximumLatitude), TileMath.maximumLatitude)
        let cosine = max(0.2, abs(GeoMath.cosine(GeoMath.radians(fromDegrees: latitude))))
        let raw = GeoMath.log2(equatorialMetersPerPixel * cosine / metres)
        guard raw.isFinite else { return range.lowerBound }
        return min(max(Int(raw.rounded()), range.lowerBound), range.upperBound)
    }

    /// 画面四隅（図面座標）を覆うタイル。多すぎるときはズームを下げ、下限でも多いときは中央に近い枚だけ残す。
    public static func frames(
        viewCorners: [PlanarPoint],
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool,
        style: BaseMapStyle,
        pointsPerUnit: Double,
        maxTiles: Int = 20
    ) -> [DrawingMapFrame] {
        let limit = max(1, maxTiles)
        var south = Double.greatestFiniteMagnitude
        var north = -Double.greatestFiniteMagnitude
        var west = Double.greatestFiniteMagnitude
        var east = -Double.greatestFiniteMagnitude
        var count = 0
        for corner in viewCorners {
            guard let geo = DrawingPlacement.geographic(
                corner,
                zone: zone,
                axis: axis,
                transform: transform,
                composesAxis: composesAxis
            ) else { continue }
            south = min(south, geo.latitudeDegrees)
            north = max(north, geo.latitudeDegrees)
            west = min(west, geo.longitudeDegrees)
            east = max(east, geo.longitudeDegrees)
            count += 1
        }
        guard count > 0, south.isFinite, north.isFinite, west.isFinite, east.isFinite else { return [] }

        let latitude = (south + north) / 2
        let longitude = (west + east) / 2
        let padded = pad(GeoBounds(south: south, west: west, north: north, east: east))
        let range = GSITileCatalog.sourceZoomRange(for: style)
        var level = Self.zoom(
            latitudeDegrees: latitude,
            metersPerPixel: metersPerPixel(scale: transform?.scale ?? 1, pointsPerUnit: pointsPerUnit),
            style: style
        )
        while tileCount(intersecting: padded, zoom: level) > limit, level > range.lowerBound {
            level -= 1
        }
        var tiles = TileMath.tiles(intersecting: padded, zoom: level, style: style)
        if tiles.count > limit {
            tiles = nearest(tiles, latitude: latitude, longitude: longitude, limit: limit)
        }
        return tiles.compactMap { frame(for: $0, zone: zone, axis: axis, transform: transform, composesAxis: composesAxis) }
    }

    /// TileMath.tiles と同じ枚数。広い範囲の深いズームで配列を作らない。
    private static func tileCount(intersecting bounds: GeoBounds, zoom: Int) -> Int {
        let z = min(max(zoom, 0), 22)
        let east = max(bounds.west, bounds.east - 1e-8)
        let south = min(bounds.north, bounds.south + 1e-8)
        let northWest = TileMath.tileID(latitude: bounds.north, longitude: bounds.west, zoom: z)
        let southEast = TileMath.tileID(latitude: south, longitude: east, zoom: z)
        let countX = abs(southEast.x - northWest.x) + 1
        let countY = abs(southEast.y - northWest.y) + 1
        return countX * countY
    }

    private static func pad(_ bounds: GeoBounds) -> GeoBounds {
        let latPad = max((bounds.north - bounds.south) * 0.15, 0.0002)
        let lonPad = max((bounds.east - bounds.west) * 0.15, 0.0002)
        return GeoBounds(
            south: max(-TileMath.maximumLatitude, bounds.south - latPad),
            west: max(-180, bounds.west - lonPad),
            north: min(TileMath.maximumLatitude, bounds.north + latPad),
            east: min(180, bounds.east + lonPad)
        )
    }

    private static func nearest(_ tiles: [TileID], latitude: Double, longitude: Double, limit: Int) -> [TileID] {
        let ranked = tiles.map { tile -> (tile: TileID, distance: Double) in
            let bounds = TileMath.bounds(of: tile)
            let dLat = (bounds.south + bounds.north) / 2 - latitude
            let dLon = (bounds.west + bounds.east) / 2 - longitude
            return (tile, dLat * dLat + dLon * dLon)
        }
        .sorted { lhs, rhs in
            if lhs.distance == rhs.distance {
                return lhs.tile.y < rhs.tile.y || (lhs.tile.y == rhs.tile.y && lhs.tile.x < rhs.tile.x)
            }
            return lhs.distance < rhs.distance
        }
        return ranked.prefix(limit).map(\.tile).sorted { lhs, rhs in
            lhs.y < rhs.y || (lhs.y == rhs.y && lhs.x < rhs.x)
        }
    }

    private static func frame(
        for tile: TileID,
        zone: Int,
        axis: DrawingAxis,
        transform: Similarity2D?,
        composesAxis: Bool
    ) -> DrawingMapFrame? {
        func place(xFraction: Double, yFraction: Double) -> PlanarPoint? {
            let geo = TileMath.unproject(
                tileX: tile.x,
                tileY: tile.y,
                zoom: tile.z,
                xFraction: xFraction,
                yFraction: yFraction
            )
            return DrawingPlacement.point(
                latitudeDegrees: geo.latitudeDegrees,
                longitudeDegrees: geo.longitudeDegrees,
                zone: zone,
                axis: axis,
                transform: transform,
                composesAxis: composesAxis
            )
        }
        guard let northWest = place(xFraction: 0, yFraction: 0),
              let northEast = place(xFraction: 1, yFraction: 0),
              let southWest = place(xFraction: 0, yFraction: 1) else { return nil }
        return DrawingMapFrame(tile: tile, northWest: northWest, northEast: northEast, southWest: southWest)
    }
}
