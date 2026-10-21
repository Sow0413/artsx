import XCTest
@testable import SurveyCore

final class ManualPointTests: XCTestCase {
    func testPasteReadsDecimalDegreesAndShowsPlane() throws {
        let fix = try XCTUnwrap(ManualPoint.parse("36.77450, 139.20081", zone: 9))
        XCTAssertEqual(fix.kind, .geographic)
        XCTAssertEqual(fix.latitudeDegrees, 36.77450, accuracy: 1e-8)
        XCTAssertEqual(fix.longitudeDegrees, 139.20081, accuracy: 1e-8)
        XCTAssertTrue(fix.counterpart.contains("X "))
        XCTAssertTrue(fix.counterpart.contains("Y "))
        let round = try XCTUnwrap(PlaneRectangular.forward(latitudeDegrees: 36.77450, longitudeDegrees: 139.20081, zone: 9))
        XCTAssertEqual(fix.northingMeters, round.northingMeters, accuracy: 1e-4)
        XCTAssertEqual(fix.eastingMeters, round.eastingMeters, accuracy: 1e-4)
        let again = try XCTUnwrap(ManualPoint.parse(fix.counterpart, zone: 9))
        XCTAssertEqual(again.kind, .plane)
        XCTAssertEqual(again.latitudeDegrees, 36.77450, accuracy: 1e-6)
        XCTAssertEqual(again.longitudeDegrees, 139.20081, accuracy: 1e-6)
    }

    func testDegreeMinuteSecondAndFullwidthComma() throws {
        let dms = try XCTUnwrap(ManualPoint.parse("36°46'28\", 139°12'03\"", zone: 9))
        XCTAssertEqual(dms.latitudeDegrees, 36 + 46.0 / 60 + 28.0 / 3600, accuracy: 1e-8)
        XCTAssertEqual(dms.longitudeDegrees, 139 + 12.0 / 60 + 3.0 / 3600, accuracy: 1e-8)
        let wide = try XCTUnwrap(ManualPoint.parse("36.77450，139.20081", zone: 9))
        XCTAssertEqual(wide.latitudeDegrees, 36.77450, accuracy: 1e-8)
        let spaced = try XCTUnwrap(ManualPoint.parse("36° 46' 28.2\" 139° 12' 2.916\"", zone: 9))
        XCTAssertEqual(spaced.latitudeDegrees, 36.77450, accuracy: 1e-6)
        XCTAssertEqual(spaced.longitudeDegrees, 139.20081, accuracy: 1e-6)
    }

    func testPlaneXYOfTheProjectZoneShowsLatitude() throws {
        let source = try XCTUnwrap(ManualPoint.parse("36.77450, 139.20081", zone: 9))
        let text = "X \(ManualPointFix.meters(source.northingMeters)) Y \(ManualPointFix.meters(source.eastingMeters))"
        let plane = try XCTUnwrap(ManualPoint.parse(text, zone: 9))
        XCTAssertEqual(plane.kind, .plane)
        XCTAssertEqual(plane.latitudeDegrees, source.latitudeDegrees, accuracy: 1e-5)
        XCTAssertEqual(plane.longitudeDegrees, source.longitudeDegrees, accuracy: 1e-5)
        XCTAssertTrue(plane.counterpart.contains(","))
        XCTAssertNil(ManualPoint.parse("36.77450", zone: 9))
        XCTAssertNil(ManualPoint.parse("ここ", zone: 9))
        XCTAssertNil(ManualPoint.parse("900000, 900000", zone: 9))
        XCTAssertEqual(try XCTUnwrap(ManualPoint.height(" 946.2m ")), 946.2, accuracy: 1e-9)
        XCTAssertNil(ManualPoint.height(""))
    }

    func testManualOriginRoundTrips() throws {
        let point = FieldPoint(
            id: "m",
            name: "ここ",
            northingMeters: 1,
            eastingMeters: 2,
            zone: 9,
            latitudeDegrees: 36,
            longitudeDegrees: 139,
            heightMeters: 10,
            origin: .manual,
            anchor: .geographic
        )
        let data = try JSONEncoder().encode(point)
        let decoded = try JSONDecoder().decode(FieldPoint.self, from: data)
        XCTAssertEqual(decoded.origin, .manual)
        XCTAssertEqual(decoded.heightMeters ?? 0, 10, accuracy: 1e-9)
    }
}
