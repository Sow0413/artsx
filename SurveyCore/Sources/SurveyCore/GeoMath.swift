#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#else
import Darwin
#endif

enum GeoMath {
    static func radians(fromDegrees degrees: Double) -> Double {
        degrees * .pi / 180
    }

    static func degrees(fromRadians radians: Double) -> Double {
        radians * 180 / .pi
    }

    static func cosine(_ radians: Double) -> Double { cos(radians) }
    static func sine(_ radians: Double) -> Double { sin(radians) }
    static func tangent(_ radians: Double) -> Double { tan(radians) }
    static func arctangent(_ value: Double) -> Double { atan(value) }
    static func arctangent(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
    static func naturalLog(_ value: Double) -> Double { log(value) }
    static func hyperbolicSine(_ value: Double) -> Double { sinh(value) }
    static func squareRoot(_ value: Double) -> Double { sqrt(value) }
    static func log2(_ value: Double) -> Double { log(value) / log(2) }
}
