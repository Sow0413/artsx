#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

/// GRS80。日本の測地成果が載る楕円体。WGS84 とは扁平率がわずかに違う。
public enum GRS80 {
    public static let equatorialRadiusMeters = 6_378_137.0
    public static let inverseFlattening = 298.257222101

    public static var flattening: Double { 1 / inverseFlattening }

    public static var polarRadiusMeters: Double {
        equatorialRadiusMeters * (1 - flattening)
    }
}

/// 点1から点2への測地線。方位は北から時計回り、度。
public struct GeodesicInverse: Equatable, Sendable {
    public var distanceMeters: Double
    public var azimuthDegrees: Double

    public init(distanceMeters: Double, azimuthDegrees: Double) {
        self.distanceMeters = distanceMeters
        self.azimuthDegrees = azimuthDegrees
    }

    public var eastMeters: Double {
        distanceMeters * GeoMath.sine(GeoMath.radians(fromDegrees: azimuthDegrees))
    }

    public var northMeters: Double {
        distanceMeters * GeoMath.cosine(GeoMath.radians(fromDegrees: azimuthDegrees))
    }
}

/// Vincenty の逆・順問題。式は公開されているもの。対蹠点で収束しなければ nil。
/// 現場の距離（数十kmまで）では 0.1mm より細かい。Karney の式は対蹠点用で、ここには移植していない。
public enum GRS80Geodesic {
    public static func inverse(
        latitude1: Double,
        longitude1: Double,
        latitude2: Double,
        longitude2: Double
    ) -> GeodesicInverse? {
        guard latitude1.isFinite, longitude1.isFinite, latitude2.isFinite, longitude2.isFinite else { return nil }
        guard abs(latitude1) <= 90, abs(latitude2) <= 90 else { return nil }
        let f = GRS80.flattening
        let a = GRS80.equatorialRadiusMeters
        let b = GRS80.polarRadiusMeters
        let phi1 = GeoMath.radians(fromDegrees: latitude1)
        let phi2 = GeoMath.radians(fromDegrees: latitude2)
        let longitudeDelta = wrapPi(GeoMath.radians(fromDegrees: longitude2 - longitude1))
        if abs(phi1 - phi2) < 1e-15, abs(longitudeDelta) < 1e-15 {
            return GeodesicInverse(distanceMeters: 0, azimuthDegrees: 0)
        }

        let reduced1 = GeoMath.arctangent((1 - f) * GeoMath.tangent(phi1))
        let reduced2 = GeoMath.arctangent((1 - f) * GeoMath.tangent(phi2))
        let sine1 = GeoMath.sine(reduced1)
        let cosine1 = GeoMath.cosine(reduced1)
        let sine2 = GeoMath.sine(reduced2)
        let cosine2 = GeoMath.cosine(reduced2)
        var lambda = longitudeDelta
        var cosineSquaredAlpha = 0.0
        var cosineTwoSigmaMid = 0.0
        var sigma = 0.0
        var sineSigma = 0.0
        var sineAlpha = 0.0
        var converged = false

        for _ in 0..<100 {
            let sineLambda = GeoMath.sine(lambda)
            let cosineLambda = GeoMath.cosine(lambda)
            sineSigma = GeoMath.squareRoot(
                square(cosine2 * sineLambda)
                    + square(cosine1 * sine2 - sine1 * cosine2 * cosineLambda)
            )
            let cosineSigma = sine1 * sine2 + cosine1 * cosine2 * cosineLambda
            if sineSigma == 0, cosineSigma > 0 {
                return GeodesicInverse(distanceMeters: 0, azimuthDegrees: 0)
            }
            if sineSigma == 0 {
                return nil
            }
            sigma = GeoMath.arctangent(sineSigma, cosineSigma)
            sineAlpha = cosine1 * cosine2 * sineLambda / sineSigma
            cosineSquaredAlpha = 1 - square(sineAlpha)
            if abs(cosineSquaredAlpha) < 1e-15 {
                cosineTwoSigmaMid = 0
            } else {
                cosineTwoSigmaMid = cosineSigma - 2 * sine1 * sine2 / cosineSquaredAlpha
            }
            let c = f / 16 * cosineSquaredAlpha * (4 + f * (4 - 3 * cosineSquaredAlpha))
            let next = longitudeDelta + (1 - c) * f * sineAlpha * (
                sigma + c * sineSigma * (
                    cosineTwoSigmaMid + c * cosineSigma * (-1 + 2 * square(cosineTwoSigmaMid))
                )
            )
            if abs(next - lambda) < 1e-12 {
                lambda = next
                converged = true
                break
            }
            lambda = next
        }
        guard converged else { return nil }

        let uSquared = cosineSquaredAlpha * (square(a) - square(b)) / square(b)
        let aFactor = 1 + uSquared / 16_384 * (4_096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)))
        let bFactor = uSquared / 1_024 * (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)))
        let deltaSigma = bFactor * sineSigma * (
            cosineTwoSigmaMid + bFactor / 4 * (
                GeoMath.cosine(sigma) * (-1 + 2 * square(cosineTwoSigmaMid))
                    - bFactor / 6 * cosineTwoSigmaMid * (-3 + 4 * square(sineSigma)) * (-3 + 4 * square(cosineTwoSigmaMid))
            )
        )
        let distance = b * aFactor * (sigma - deltaSigma)
        let azimuth = GeoMath.arctangent(
            cosine2 * GeoMath.sine(lambda),
            cosine1 * sine2 - sine1 * cosine2 * GeoMath.cosine(lambda)
        )
        return GeodesicInverse(
            distanceMeters: distance,
            azimuthDegrees: GeoMath.degrees(fromRadians: azimuth)
        )
    }

    /// 方位は北から時計回り、度。距離はメートル。
    public static func direct(
        latitude: Double,
        longitude: Double,
        azimuthDegrees: Double,
        distanceMeters: Double
    ) -> (latitude: Double, longitude: Double)? {
        guard latitude.isFinite, longitude.isFinite, azimuthDegrees.isFinite, distanceMeters.isFinite else { return nil }
        guard abs(latitude) <= 90, distanceMeters >= 0 else { return nil }
        if distanceMeters == 0 {
            return (latitude, longitude)
        }
        let f = GRS80.flattening
        let a = GRS80.equatorialRadiusMeters
        let b = GRS80.polarRadiusMeters
        let phi1 = GeoMath.radians(fromDegrees: latitude)
        let azimuth = GeoMath.radians(fromDegrees: azimuthDegrees)
        let reduced1 = GeoMath.arctangent((1 - f) * GeoMath.tangent(phi1))
        let sine1 = GeoMath.sine(reduced1)
        let cosine1 = GeoMath.cosine(reduced1)
        let sigma1 = GeoMath.arctangent(GeoMath.tangent(reduced1), GeoMath.cosine(azimuth))
        let sineAlpha = cosine1 * GeoMath.sine(azimuth)
        let cosineSquaredAlpha = 1 - square(sineAlpha)
        let uSquared = cosineSquaredAlpha * (square(a) - square(b)) / square(b)
        let aFactor = 1 + uSquared / 16_384 * (4_096 + uSquared * (-768 + uSquared * (320 - 175 * uSquared)))
        let bFactor = uSquared / 1_024 * (256 + uSquared * (-128 + uSquared * (74 - 47 * uSquared)))
        var sigma = distanceMeters / (b * aFactor)
        for _ in 0..<100 {
            let twoSigmaMid = GeoMath.cosine(2 * sigma1 + sigma)
            let sineSigma = GeoMath.sine(sigma)
            let cosineSigma = GeoMath.cosine(sigma)
            let deltaSigma = bFactor * sineSigma * (
                twoSigmaMid + bFactor / 4 * (
                    cosineSigma * (-1 + 2 * square(twoSigmaMid))
                        - bFactor / 6 * twoSigmaMid * (-3 + 4 * square(sineSigma)) * (-3 + 4 * square(twoSigmaMid))
                )
            )
            let next = distanceMeters / (b * aFactor) + deltaSigma
            if abs(next - sigma) < 1e-12 {
                sigma = next
                break
            }
            sigma = next
        }
        let twoSigmaMid = GeoMath.cosine(2 * sigma1 + sigma)
        let sineSigma = GeoMath.sine(sigma)
        let cosineSigma = GeoMath.cosine(sigma)
        let latitude2 = GeoMath.arctangent(
            sine1 * cosineSigma + cosine1 * sineSigma * GeoMath.cosine(azimuth),
            (1 - f) * GeoMath.squareRoot(
                square(sineAlpha) + square(sine1 * sineSigma - cosine1 * cosineSigma * GeoMath.cosine(azimuth))
            )
        )
        let lambda = GeoMath.arctangent(
            sineSigma * GeoMath.sine(azimuth),
            cosine1 * cosineSigma - sine1 * sineSigma * GeoMath.cosine(azimuth)
        )
        let c = f / 16 * cosineSquaredAlpha * (4 + f * (4 - 3 * cosineSquaredAlpha))
        let longitudeDelta = lambda - (1 - c) * f * sineAlpha * (
            sigma + c * sineSigma * (
                twoSigmaMid + c * cosineSigma * (-1 + 2 * square(twoSigmaMid))
            )
        )
        return (
            GeoMath.degrees(fromRadians: latitude2),
            longitude + GeoMath.degrees(fromRadians: longitudeDelta)
        )
    }

    private static func square(_ value: Double) -> Double { value * value }

    private static func wrapPi(_ radians: Double) -> Double {
        var value = radians
        let turn = 2 * Double.pi
        while value > Double.pi { value -= turn }
        while value < -Double.pi { value += turn }
        return value
    }
}
