import Foundation

/// 平面直角座標系（平成14年国土交通省告示第9号）。1〜19系。
/// 換算は国土地理院の測量計算サイトが公開しているガウス・クリューゲルの級数
/// （河瀬 2011、国土地理院時報121号）。PROJ や GPL の実装は使っていない。
/// X は北を正、Y は東を正。原点で X = Y = 0。X 軸上の縮尺係数は 0.9999。
/// 偽東距（500 km を足す書き方）は加えない。楕円体は GRS80。
public struct PlaneZone: Sendable, Equatable, Identifiable {
    public var number: Int
    public var originLatitudeDegrees: Double
    public var originLongitudeDegrees: Double
    public var roman: String

    public var id: Int { number }

    public var label: String { "\(number)系" }
}

public struct PlaneCoordinate: Sendable, Equatable {
    /// 北を正。告示の X。
    public var northingMeters: Double
    /// 東を正。告示の Y。
    public var eastingMeters: Double

    public init(northingMeters: Double, eastingMeters: Double) {
        self.northingMeters = northingMeters
        self.eastingMeters = eastingMeters
    }
}

public enum PlaneRectangular {
    public static let zones: [PlaneZone] = {
        let roman = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX"]
        let origins: [(lat: Double, lon: Double)] = [
            (33, 129.5),
            (33, 131),
            (36, 132 + 10.0 / 60),
            (33, 133.5),
            (36, 134 + 20.0 / 60),
            (36, 136),
            (36, 137 + 10.0 / 60),
            (36, 138.5),
            (36, 139 + 50.0 / 60),
            (40, 140 + 50.0 / 60),
            (44, 140.25),
            (44, 142.25),
            (44, 144.25),
            (26, 142),
            (26, 127.5),
            (26, 124),
            (26, 131),
            (20, 136),
            (26, 154)
        ]
        return zip(roman, origins).enumerated().map { index, item in
            PlaneZone(
                number: index + 1,
                originLatitudeDegrees: item.1.lat,
                originLongitudeDegrees: item.1.lon,
                roman: item.0
            )
        }
    }()

    public static func zone(_ number: Int) -> PlaneZone? {
        guard number >= 1, number <= 19 else { return nil }
        return zones[number - 1]
    }

    /// 緯度経度を、指定した系の平面直角座標にする。範囲外の系番号は nil。
    public static func forward(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        zone number: Int
    ) -> PlaneCoordinate? {
        guard let zone = zone(number) else { return nil }
        guard latitudeDegrees.isFinite, longitudeDegrees.isFinite, abs(latitudeDegrees) < 90 else { return nil }
        let projected = GaussKruger.forward(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            originLatitude: zone.originLatitudeDegrees,
            originLongitude: zone.originLongitudeDegrees
        )
        return PlaneCoordinate(northingMeters: projected.northing, eastingMeters: projected.easting)
    }

    /// 平面直角座標を緯度経度に戻す。
    public static func inverse(
        northingMeters: Double,
        eastingMeters: Double,
        zone number: Int
    ) -> (latitudeDegrees: Double, longitudeDegrees: Double)? {
        guard let zone = zone(number) else { return nil }
        guard northingMeters.isFinite, eastingMeters.isFinite else { return nil }
        return GaussKruger.inverse(
            northing: northingMeters,
            easting: eastingMeters,
            originLatitude: zone.originLatitudeDegrees,
            originLongitude: zone.originLongitudeDegrees
        )
    }
}

/// 測量計算サイト「平面直角座標への換算　計算式」と同じ級数。
enum GaussKruger {
    private static let scale = 0.9999

    private static var n: Double { 1 / (2 * GRS80.inverseFlattening - 1) }

    static func forward(
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        originLatitude: Double,
        originLongitude: Double
    ) -> (northing: Double, easting: Double) {
        let n = n
        let n2 = n * n
        let n3 = n2 * n
        let n4 = n2 * n2
        let n5 = n4 * n
        let phi = GeoMath.radians(fromDegrees: latitudeDegrees)
        let lambda = GeoMath.radians(fromDegrees: longitudeDegrees)
        let phi0 = GeoMath.radians(fromDegrees: originLatitude)
        let lambda0 = GeoMath.radians(fromDegrees: originLongitude)
        let root = 2 * GeoMath.squareRoot(n) / (1 + n)
        let conformal = GeoMath.artanh(GeoMath.sine(phi)) - root * GeoMath.artanh(root * GeoMath.sine(phi))
        let t = GeoMath.hyperbolicSine(conformal)
        let tBar = GeoMath.squareRoot(1 + t * t)
        let lambdaCos = GeoMath.cosine(lambda - lambda0)
        let lambdaSin = GeoMath.sine(lambda - lambda0)
        let xi = GeoMath.arctangent(t, lambdaCos)
        let ratio = tBar == 0 ? 0 : lambdaSin / tBar
        let eta = GeoMath.artanh(ratio)
        let alpha = alphas(n: n, n2: n2, n3: n3, n4: n4, n5: n5)
        var xiSum = xi
        var etaSum = eta
        for j in 1...5 {
            let angle = Double(2 * j)
            xiSum += alpha[j - 1] * GeoMath.sine(angle * xi) * GeoMath.hyperbolicCosine(angle * eta)
            etaSum += alpha[j - 1] * GeoMath.cosine(angle * xi) * GeoMath.hyperbolicSine(angle * eta)
        }
        let radius = barA(n: n, n2: n2, n4: n4)
        let northing = radius * xiSum - meridianConstant(phi0: phi0, n: n, n2: n2, n3: n3, n4: n4, n5: n5, radius: radius)
        return (northing, radius * etaSum)
    }

    static func inverse(
        northing: Double,
        easting: Double,
        originLatitude: Double,
        originLongitude: Double
    ) -> (latitudeDegrees: Double, longitudeDegrees: Double) {
        let n = n
        let n2 = n * n
        let n3 = n2 * n
        let n4 = n2 * n2
        let n5 = n4 * n
        let phi0 = GeoMath.radians(fromDegrees: originLatitude)
        let lambda0 = GeoMath.radians(fromDegrees: originLongitude)
        let radius = barA(n: n, n2: n2, n4: n4)
        let meridian = meridianConstant(phi0: phi0, n: n, n2: n2, n3: n3, n4: n4, n5: n5, radius: radius)
        let xi = (northing + meridian) / radius
        let eta = easting / radius
        let beta = betas(n: n, n2: n2, n3: n3, n4: n4, n5: n5)
        var xiPrime = xi
        var etaPrime = eta
        for j in 1...5 {
            let angle = Double(2 * j)
            xiPrime -= beta[j - 1] * GeoMath.sine(angle * xi) * GeoMath.hyperbolicCosine(angle * eta)
            etaPrime -= beta[j - 1] * GeoMath.cosine(angle * xi) * GeoMath.hyperbolicSine(angle * eta)
        }
        let chi = GeoMath.arcsine(GeoMath.sine(xiPrime) / GeoMath.hyperbolicCosine(etaPrime))
        let delta = deltas(n2: n2, n3: n3, n4: n4, n5: n5)
        var inner = chi
        for j in 1...5 {
            inner += delta[j - 1] * GeoMath.sine(Double(2 * j) * chi)
        }
        let factor = (1 + n) / (1 - n)
        let tPsi = factor * GeoMath.tangent(inner)
        let latitude = GeoMath.arctangent(factor * tPsi)
        let longitude = lambda0 + GeoMath.arctangent(GeoMath.hyperbolicSine(etaPrime), GeoMath.cosine(xiPrime))
        return (GeoMath.degrees(fromRadians: latitude), GeoMath.degrees(fromRadians: longitude))
    }

    private static func barA(n: Double, n2: Double, n4: Double) -> Double {
        let a0 = 1 + n2 / 4 + n4 / 64
        return scale * GRS80.equatorialRadiusMeters / (1 + n) * a0
    }

    private static func meridianConstant(
        phi0: Double,
        n: Double,
        n2: Double,
        n3: Double,
        n4: Double,
        n5: Double,
        radius: Double
    ) -> Double {
        let a1 = -1.5 * (n - n3 / 8 - n5 / 64)
        let a2 = 15.0 / 16 * (n2 - n4 / 4)
        let a3 = -35.0 / 48 * (n3 - 5.0 / 16 * n5)
        let a4 = 315.0 / 512 * n4
        let a5 = -693.0 / 1280 * n5
        let coefficients = [a1, a2, a3, a4, a5]
        let factor = scale * GRS80.equatorialRadiusMeters / (1 + n)
        var sum = radius * phi0
        for j in 1...5 {
            sum += factor * coefficients[j - 1] * GeoMath.sine(Double(2 * j) * phi0)
        }
        return sum
    }

    private static func alphas(n: Double, n2: Double, n3: Double, n4: Double, n5: Double) -> [Double] {
        [
            0.5 * n - 2.0 / 3 * n2 + 5.0 / 16 * n3 + 41.0 / 180 * n4 - 127.0 / 288 * n5,
            13.0 / 48 * n2 - 0.6 * n3 + 557.0 / 1440 * n4 + 281.0 / 630 * n5,
            61.0 / 240 * n3 - 103.0 / 140 * n4 + 15_061.0 / 26_880 * n5,
            49_561.0 / 161_280 * n4 - 179.0 / 168 * n5,
            34_729.0 / 80_640 * n5
        ]
    }

    private static func betas(n: Double, n2: Double, n3: Double, n4: Double, n5: Double) -> [Double] {
        [
            0.5 * n - 2.0 / 3 * n2 + 37.0 / 96 * n3 - n4 / 360 - 81.0 / 512 * n5,
            n2 / 48 + n3 / 15 - 437.0 / 1440 * n4 + 46.0 / 105 * n5,
            17.0 / 480 * n3 - 37.0 / 840 * n4 - 209.0 / 4480 * n5,
            4_397.0 / 161_280 * n4 - 11.0 / 504 * n5,
            4_583.0 / 161_280 * n5
        ]
    }

    private static func deltas(n2: Double, n3: Double, n4: Double, n5: Double) -> [Double] {
        [
            -2.0 / 3 * n2 - 2.0 / 3 * n3 + 4.0 / 9 * n4 + 2.0 / 9 * n5,
            n2 / 3 - 4.0 / 15 * n3 - 23.0 / 45 * n4 + 68.0 / 45 * n5,
            0.4 * n3 - 24.0 / 35 * n4 - 46.0 / 35 * n5,
            83.0 / 126 * n4 - 80.0 / 63 * n5,
            52.0 / 45 * n5
        ]
    }
}
