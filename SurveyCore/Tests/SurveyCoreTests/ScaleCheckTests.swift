import XCTest
@testable import SurveyCore

final class ScaleCheckTests: XCTestCase {
    func testScalePassesOnlyInsideBothLimits() {
        let close = ScaleCheck.compare(drawingMeters: 100, measuredMeters: 100.001)
        XCTAssertEqual(close?.passed, true)
        XCTAssertEqual(close?.differenceMeters ?? 0, 0.001, accuracy: 1e-12)

        let twoCentimetresOnAShortLine = ScaleCheck.compare(drawingMeters: 10, measuredMeters: 10.02)
        XCTAssertEqual(twoCentimetresOnAShortLine?.passed, false)

        let overAbsolute = ScaleCheck.compare(drawingMeters: 10_000, measuredMeters: 10_000.03)
        XCTAssertEqual(overAbsolute?.passed, false)
        XCTAssertNil(ScaleCheck.compare(drawingMeters: 0, measuredMeters: 1))
    }

    func testLocalizeRefusesFewerThanThreePairs() {
        let one = (source: PlanarPoint(x: 0, y: 0), target: PlanarPoint(x: 1, y: 1))
        XCTAssertNil(SiteLocalize.fit([one, one, one].dropLast()))
        let fit = SiteLocalize.fit([
            (source: PlanarPoint(x: 0, y: 0), target: PlanarPoint(x: 10, y: 20)),
            (source: PlanarPoint(x: 10, y: 0), target: PlanarPoint(x: 20, y: 20)),
            (source: PlanarPoint(x: 0, y: 10), target: PlanarPoint(x: 10, y: 30))
        ])
        XCTAssertNotNil(fit)
        XCTAssertEqual(fit?.transform.scale ?? 0, 1, accuracy: 1e-9)
        XCTAssertLessThan(fit?.rmsMeters ?? 1, 1e-6)
    }
}
