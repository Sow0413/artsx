import Foundation

/// 地理院タイルの種類。このスライスで取るのは標準地図だけ。ほかは現場パック用の枠。
public enum BaseMapStyle: String, Sendable, Codable, Equatable, CaseIterable {
    case gsiStandard = "std"
    case gsiPale = "pale"
    case gsiPhoto = "seamlessphoto"
    case gsiRelief = "relief"
}

public struct TileID: Hashable, Sendable, Codable, Equatable {
    public var style: BaseMapStyle
    public var z: Int
    public var x: Int
    public var y: Int

    public init(style: BaseMapStyle, z: Int, x: Int, y: Int) {
        self.style = style
        self.z = z
        self.x = x
        self.y = y
    }
}

public struct GeoBounds: Equatable, Sendable, Codable {
    public var south: Double
    public var west: Double
    public var north: Double
    public var east: Double

    public init(south: Double, west: Double, north: Double, east: Double) {
        self.south = south
        self.west = west
        self.north = north
        self.east = east
    }

    public func contains(latitude: Double, longitude: Double) -> Bool {
        latitude >= south && latitude <= north && longitude >= west && longitude <= east
    }

    /// 日付変更線をまたぐ範囲は扱わない。日本の現場では不要。
    public func intersects(_ other: GeoBounds) -> Bool {
        south <= other.north && north >= other.south && west <= other.east && east >= other.west
    }
}

public enum TileMath {
    public static let maximumLatitude = 85.05112878

    public static func tileID(
        latitude: Double,
        longitude: Double,
        zoom: Int,
        style: BaseMapStyle = .gsiStandard
    ) -> TileID {
        let z = min(max(zoom, 0), 22)
        let n = Double(1 << z)
        let clampedLatitude = min(max(latitude, -maximumLatitude), maximumLatitude)
        var wrappedLongitude = longitude
        while wrappedLongitude < -180 { wrappedLongitude += 360 }
        while wrappedLongitude > 180 { wrappedLongitude -= 360 }
        var x = Int(floor((wrappedLongitude + 180) / 360 * n))
        let limit = (1 << z) - 1
        if x < 0 { x = 0 }
        if x > limit { x = limit }
        let latitudeRadians = GeoMath.radians(fromDegrees: clampedLatitude)
        let sineGuard = max(abs(GeoMath.cosine(latitudeRadians)), 1e-12)
        let mercator = GeoMath.naturalLog(GeoMath.tangent(latitudeRadians) + 1 / sineGuard)
        var y = Int(floor((1 - mercator / .pi) / 2 * n))
        if y < 0 { y = 0 }
        if y > limit { y = limit }
        return TileID(style: style, z: z, x: x, y: y)
    }

    /// タイル内の割合。xFraction は西から東、yFraction は北から南（ベクトルタイルの Y は下向き）。
    public static func unproject(
        tileX: Int,
        tileY: Int,
        zoom: Int,
        xFraction: Double,
        yFraction: Double
    ) -> GeoCoord {
        let z = min(max(zoom, 0), 22)
        let n = Double(1 << z)
        let longitude = (Double(tileX) + xFraction) / n * 360 - 180
        let latitude = latitude(mercatorY: Double(tileY) + yFraction, n: n)
        return GeoCoord(latitudeDegrees: latitude, longitudeDegrees: longitude)
    }

    public static func bounds(of tile: TileID) -> GeoBounds {
        let z = min(max(tile.z, 0), 22)
        let n = Double(1 << z)
        let west = Double(tile.x) / n * 360 - 180
        let east = Double(tile.x + 1) / n * 360 - 180
        let north = latitude(mercatorY: Double(tile.y), n: n)
        let south = latitude(mercatorY: Double(tile.y + 1), n: n)
        return GeoBounds(south: south, west: west, north: north, east: east)
    }

    public static func tiles(intersecting bounds: GeoBounds, zoom: Int, style: BaseMapStyle) -> [TileID] {
        let z = min(max(zoom, 0), 22)
        // 東端と南端がタイル境界ちょうどだと、隣のタイルまで数えてしまう。
        let east = max(bounds.west, bounds.east - 1e-8)
        let south = min(bounds.north, bounds.south + 1e-8)
        let northWest = tileID(latitude: bounds.north, longitude: bounds.west, zoom: z, style: style)
        let southEast = tileID(latitude: south, longitude: east, zoom: z, style: style)
        let x0 = min(northWest.x, southEast.x)
        let x1 = max(northWest.x, southEast.x)
        let y0 = min(northWest.y, southEast.y)
        let y1 = max(northWest.y, southEast.y)
        var result: [TileID] = []
        result.reserveCapacity((x1 - x0 + 1) * (y1 - y0 + 1))
        for y in y0...y1 {
            for x in x0...x1 {
                result.append(TileID(style: style, z: z, x: x, y: y))
            }
        }
        return result
    }

    private static func latitude(mercatorY y: Double, n: Double) -> Double {
        let radians = GeoMath.arctangent(GeoMath.hyperbolicSine(.pi * (1 - 2 * y / n)))
        return GeoMath.degrees(fromRadians: radians)
    }
}

public enum GSITileCatalog {
    public static let attribution = "地理院タイル"
    public static let sourceCredit = "出典：国土地理院"
    public static let standardHost = "https://cyberjapandata.gsi.go.jp/xyz"
    public static let standardZoomRange: ClosedRange<Int> = 0...18
    public static let userAgent = "SurveyField/0.1 (iOS; GSI tile cache)"

    public static func url(for tile: TileID) -> URL {
        let string = "\(standardHost)/\(tile.style.rawValue)/\(tile.z)/\(tile.x)/\(tile.y).png"
        guard let url = URL(string: string) else {
            preconditionFailure("地理院タイルの URL を作れません")
        }
        return url
    }

    public static func urlTemplate(for style: BaseMapStyle) -> String {
        "\(standardHost)/\(style.rawValue)/{z}/{x}/{y}.png"
    }
}

public enum TileError: Error, Equatable {
    case notFound(TileID)
    case empty(TileID)
    case badResponse(TileID, status: Int)
    case transport(String)
}

public protocol TileFetching: Sendable {
    func fetch(_ tile: TileID) async throws -> Data
}

/// あとから入れる現場パック。1フォルダが1範囲。
public struct BaseMapPackManifest: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var style: BaseMapStyle
    public var minZoom: Int
    public var maxZoom: Int
    public var bounds: GeoBounds

    public init(
        id: String,
        title: String,
        style: BaseMapStyle,
        minZoom: Int,
        maxZoom: Int,
        bounds: GeoBounds
    ) {
        self.id = id
        self.title = title
        self.style = style
        self.minZoom = minZoom
        self.maxZoom = maxZoom
        self.bounds = bounds
    }
}

public struct LocalBaseMapPack: TileFetching, Equatable, Sendable {
    public let root: URL
    public let manifest: BaseMapPackManifest

    public init(root: URL) throws {
        let url = root.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        self.manifest = try JSONDecoder().decode(BaseMapPackManifest.self, from: data)
        self.root = root
    }

    public func fetch(_ tile: TileID) async throws -> Data {
        guard tile.style == manifest.style else { throw TileError.notFound(tile) }
        guard tile.z >= manifest.minZoom, tile.z <= manifest.maxZoom else { throw TileError.notFound(tile) }
        guard TileMath.bounds(of: tile).intersects(manifest.bounds) else { throw TileError.notFound(tile) }
        let url = TileFiles.packFile(root: root, tile: tile)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            throw TileError.notFound(tile)
        }
        return data
    }
}

public enum LocalPackDirectory {
    /// 直下の各フォルダに manifest.json があるものを読む。壊れたフォルダは飛ばす。
    public static func load(in root: URL) -> [LocalBaseMapPack] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(atPath: root.path) else { return [] }
        return names.sorted().compactMap { name in
            let folder = root.appendingPathComponent(name, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard manager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return nil
            }
            return try? LocalBaseMapPack(root: folder)
        }
    }
}

enum TileFiles {
    static func packFile(root: URL, tile: TileID) -> URL {
        root
            .appendingPathComponent(String(tile.z), isDirectory: true)
            .appendingPathComponent(String(tile.x), isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
    }

    static func cacheFile(root: URL, tile: TileID) -> URL {
        root
            .appendingPathComponent(tile.style.rawValue, isDirectory: true)
            .appendingPathComponent(String(tile.z), isDirectory: true)
            .appendingPathComponent(String(tile.x), isDirectory: true)
            .appendingPathComponent("\(tile.y).png")
    }
}
