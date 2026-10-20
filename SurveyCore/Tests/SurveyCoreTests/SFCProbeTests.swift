import XCTest
@testable import SurveyCore

final class SFCProbeTests: XCTestCase {
    func testProbeUploadedSFC() throws {
        let path = "/home/ubuntu/.cursor/projects/workspace/uploads/ec487e3498fffba09f465c5596c63f3daa23862b25e96390a3dd775e71039ce6_c6f1.sfc"
        guard let data = FileManager.default.contents(atPath: path) else {
            throw XCTSkip("実物の SFC が無い")
        }
        let document = try SFCParser.parse(data)
        print("CODEPAGE \(document.codePage)")
        print("ENTITIES \(document.entities.count)")
        print("BOUNDS \(document.bounds)")
        print("UNIT \(document.unitWarning ?? "")")
        var kinds: [String: Int] = [:]
        for entity in document.entities {
            let key: String
            switch entity.primitive {
            case .line: key = "line"
            case .polyline: key = "polyline"
            case .circle: key = "circle"
            case .arc: key = "arc"
            case .text: key = "text"
            case .point: key = "point"
            }
            kinds[key, default: 0] += 1
        }
        print("KINDS \(kinds)")
        for layer in document.layers {
            let count = document.entities.filter { $0.layer == layer.name }.count
            print("LAYER \(layer.role.rawValue) vis=\(layer.isVisible) n=\(count) [\(layer.name)]")
        }
        print("UNSUPPORTED \(document.unsupportedCounts)")
        let centerX = (document.bounds.minX + document.bounds.maxX) / 2
        let centerY = (document.bounds.minY + document.bounds.maxY) / 2
        print("CENTER \(centerX) \(centerY)")
        for zone in 1...19 {
            for axis in DrawingAxis.allCases {
                let plane = axis.plane(drawingX: centerX, drawingY: centerY)
                guard let geo = PlaneRectangular.inverse(
                    northingMeters: plane.northing,
                    eastingMeters: plane.easting,
                    zone: zone
                ) else { continue }
                let origin = GeoMath.hypotenuse(plane.northing, plane.easting)
                let japan = geo.latitudeDegrees > 24 && geo.latitudeDegrees < 46 && geo.longitudeDegrees > 122 && geo.longitudeDegrees < 154
                if japan && origin < 250_000 {
                    print(String(format: "HIT z=%d axis=%@ lat=%.6f lon=%.6f origin=%.0f N=%.1f E=%.1f",
                                 zone, axis.rawValue, geo.latitudeDegrees, geo.longitudeDegrees, origin, plane.northing, plane.easting))
                }
            }
        }
        if let text = document.entities.first(where: { if case .text = $0.primitive { return true }; return false }) {
            print("TEXT \(text)")
        }
    }
}
