import Foundation

public struct MapViewport: Equatable, Sendable {
    public var centerLatitude: Double
    public var centerLongitude: Double
    public var latitudeDelta: Double
    public var longitudeDelta: Double

    public init(centerLatitude: Double, centerLongitude: Double, latitudeDelta: Double, longitudeDelta: Double) {
        self.centerLatitude = centerLatitude
        self.centerLongitude = centerLongitude
        self.latitudeDelta = latitudeDelta
        self.longitudeDelta = longitudeDelta
    }

    /// 画面の縦方向のおおよその長さ（m）。カメラの追従判定にだけ使う。
    public var groundSpanMeters: Double {
        latitudeDelta * 111_320
    }

    public var bounds: GeoBounds {
        GeoBounds(
            south: centerLatitude - latitudeDelta / 2,
            west: centerLongitude - longitudeDelta / 2,
            north: centerLatitude + latitudeDelta / 2,
            east: centerLongitude + longitudeDelta / 2
        )
    }
}

public enum MapViewportPolicy {
    public static let minimumSpanMeters = 80.0
    public static let maximumSpanMeters = 8_000.0
    public static let accuracyPadding = 8.0
    /// 地理院の標準地図は z18 まで。これより寄るとタイルが無く、下の地図も隠れる。
    public static let basemapMaximumZoom = 18
    /// iPhone の幅より少し広く取り、追従しても z18 を超えないようにする。
    public static let basemapScreenWidthPoints = 480.0

    public static let japanOverview = MapViewport(
        centerLatitude: 36.2,
        centerLongitude: 138.25,
        latitudeDelta: 14,
        longitudeDelta: 14
    )

    public static func spanMeters(forHorizontalAccuracy accuracy: Double) -> Double {
        let usable = accuracy.isFinite && accuracy >= 0 ? accuracy : 50
        return min(max(usable * accuracyPadding, minimumSpanMeters), maximumSpanMeters)
    }

    /// 現在地を画面の中央に大きく置く。精度円が収まり、かつ周辺も見える。
    public static func following(_ position: GeodeticPosition) -> MapViewport {
        let meters = spanMeters(forHorizontalAccuracy: position.horizontalAccuracyMeters)
        var latitudeDelta = meters / 111_320
        let cosine = max(abs(GeoMath.cosine(GeoMath.radians(fromDegrees: position.latitudeDegrees))), 0.01)
        var longitudeDelta = meters / (111_320 * cosine)
        let floorLongitude = minimumLongitudeDelta(screenWidthPoints: basemapScreenWidthPoints)
        if longitudeDelta < floorLongitude {
            longitudeDelta = floorLongitude
            latitudeDelta = floorLongitude * cosine
        }
        return MapViewport(
            centerLatitude: position.latitudeDegrees,
            centerLongitude: position.longitudeDegrees,
            latitudeDelta: latitudeDelta,
            longitudeDelta: longitudeDelta
        )
    }

    /// `MapZoom.level` が `basemapMaximumZoom` を超えない経度幅。
    public static func minimumLongitudeDelta(screenWidthPoints: Double, maxZoom: Int = basemapMaximumZoom) -> Double {
        guard screenWidthPoints > 0, maxZoom >= 0 else { return 0 }
        return 360 * screenWidthPoints / (256 * pow(2, Double(maxZoom)))
    }
}

public enum MapZoom {
    /// 表示中の経度幅と画面幅から、地理院タイルのズームを概算する。
    public static func level(longitudeDelta: Double, screenWidthPoints: Double, tileSize: Double = 256) -> Int {
        guard longitudeDelta > 0, screenWidthPoints > 0, tileSize > 0 else { return 0 }
        let raw = GeoMath.log2(360 * screenWidthPoints / (tileSize * longitudeDelta))
        guard raw.isFinite else { return 0 }
        let zoom = Int((raw + 1e-6).rounded(.down))
        return min(max(zoom, 0), MapTileOverzoom.appMaxZoom)
    }

    /// 画面幅がこのズームになる経度の幅。z19 以上も、最後のタイルを拡大して出す。
    public static func longitudeDelta(forZoom zoom: Int, screenWidthPoints: Double, tileSize: Double = 256) -> Double {
        let z = min(max(zoom, 0), MapTileOverzoom.appMaxZoom)
        guard screenWidthPoints > 0, tileSize > 0 else { return 360 }
        return 360 * screenWidthPoints / (tileSize * pow(2, Double(z)))
    }
}

/// 追従中は、少し動いただけではカメラを動かさない。
public struct MapCameraFollow: Equatable, Sendable {
    public private(set) var viewport: MapViewport
    private var locked: Bool
    private var lockedAccuracy: Double?

    public init(viewport: MapViewport = MapViewportPolicy.japanOverview) {
        self.viewport = viewport
        self.locked = false
        self.lockedAccuracy = nil
    }

    public mutating func update(for position: GeodeticPosition) -> MapViewport {
        let proposed = MapViewportPolicy.following(position)
        let accuracy = position.hasValidHorizontalAccuracy ? position.horizontalAccuracyMeters : 0
        if !locked {
            locked = true
            lockedAccuracy = accuracy
            viewport = proposed
            return viewport
        }
        let moved = GeoDistance.meters(
            latitude1: viewport.centerLatitude,
            longitude1: viewport.centerLongitude,
            latitude2: position.latitudeDegrees,
            longitude2: position.longitudeDegrees
        )
        let previous = lockedAccuracy ?? accuracy
        let ratio = previous > 0 ? accuracy / previous : 1
        let shiftLimit = max(viewport.groundSpanMeters * 0.25, 30)
        if moved >= shiftLimit || ratio >= 2 || ratio <= 0.5 {
            lockedAccuracy = accuracy
            viewport = proposed
        }
        return viewport
    }
}

public enum GeoDistance {
    public static func meters(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> Double {
        let earth = 6_371_000.0
        let phi1 = GeoMath.radians(fromDegrees: latitude1)
        let phi2 = GeoMath.radians(fromDegrees: latitude2)
        let dPhi = GeoMath.radians(fromDegrees: latitude2 - latitude1)
        let dLambda = GeoMath.radians(fromDegrees: longitude2 - longitude1)
        let a = GeoMath.sine(dPhi / 2) * GeoMath.sine(dPhi / 2)
            + GeoMath.cosine(phi1) * GeoMath.cosine(phi2) * GeoMath.sine(dLambda / 2) * GeoMath.sine(dLambda / 2)
        let c = 2 * GeoMath.arctangent(GeoMath.squareRoot(a), GeoMath.squareRoot(max(0, 1 - a)))
        return earth * c
    }
}
