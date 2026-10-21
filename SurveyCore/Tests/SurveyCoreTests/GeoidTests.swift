import XCTest
@testable import SurveyCore

final class GeoidTests: XCTestCase {
    func testFieldPointUsesJapanGeoid2011() {
        let latitude = 36.77450
        let longitude = 139.20081
        let undulation = JapanGeoid.undulationMeters(latitudeDegrees: latitude, longitudeDegrees: longitude)
        XCTAssertEqual(undulation ?? 0, 43.587, accuracy: 0.02)

        let height = SurveyHeight.resolve(
            ellipsoidalMeters: 987.44,
            latitudeDegrees: latitude,
            longitudeDegrees: longitude
        )
        XCTAssertEqual(height.orthometricMeters ?? 0, 987.44 - (undulation ?? 0), accuracy: 1e-9)
        XCTAssertEqual(height.orthometricMeters ?? 0, 943.85, accuracy: 0.02)
        XCTAssertEqual(height.ellipsoidalMeters ?? 0, 987.44, accuracy: 1e-9)
        XCTAssertEqual(height.model, JapanGeoid.modelName)
        XCTAssertTrue(height.primaryLine.hasPrefix("標高"))
        XCTAssertTrue(height.detailLines.contains("楕円体高 987.44m"))
        XCTAssertTrue(height.detailLines.contains(JapanGeoid.modelName))
    }

    func testOutsideTheGridFallsBackToMeanSeaLevel() {
        XCTAssertNil(JapanGeoid.undulationMeters(latitudeDegrees: 0, longitudeDegrees: 0))
        let shifted = SurveyHeight.resolve(
            ellipsoidalMeters: 48,
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            meanSeaLevelMeters: 10,
            deviceEllipsoidalMeters: 50
        )
        XCTAssertEqual(shifted.orthometricMeters ?? 0, 8, accuracy: 1e-9)
        XCTAssertEqual(shifted.model, JapanGeoid.fallbackModelName)
        XCTAssertNil(shifted.geoidMeters)

        let plain = SurveyHeight.resolve(
            ellipsoidalMeters: nil,
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            meanSeaLevelMeters: 10
        )
        XCTAssertEqual(plain.orthometricMeters ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(plain.model, JapanGeoid.fallbackModelName)
    }

    func testSimaWritesOrthometricHeightAndKeepsTheEllipsoidInTheDetail() {
        let position = samplePosition(
            latitude: 36.77450,
            longitude: 139.20081,
            height: 987.44,
            stage: .rtk,
            quality: .rtkFix,
            receiver: .rtk
        )
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: .rtk,
            durationSeconds: 1,
            epochCount: 1
        )
        let lines = condition.reportLines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("標高"))
        XCTAssertTrue(lines.contains("楕円体高 987.44m"))
        XCTAssertTrue(lines.contains(JapanGeoid.modelName))
        XCTAssertFalse(lines.contains("地盤高"))

        let observation = FieldObservation(name: "GL1", workID: "preview", captured: position, condition: condition)
        let entry = CoordinateBookIndex.entry(from: observation, kind: "下見")
        XCTAssertEqual(entry.ellipsoidalHeightMeters ?? 0, 987.44, accuracy: 1e-6)
        XCTAssertEqual(entry.orthometricHeightMeters ?? 0, condition.orthometricHeightMeters ?? 0, accuracy: 1e-9)
        let sima = CoordinateDelivery.sima([entry], zone: 9)
        let written = String(format: "%.3f", entry.deliveredHeightMeters ?? 0)
        XCTAssertTrue(sima.contains(written))
        XCTAssertFalse(sima.contains("987.440"))
        XCTAssertTrue(CoordinateDelivery.csv([entry], zone: 9).contains("標高"))
    }

    func testStatureCorrectionStaysAheadOfTheGeoid() {
        let position = samplePosition(latitude: 36.77450, longitude: 139.20081, height: 987.44)
        let profile = StatureProfile(statureMeters: 1.70, style: .eye)
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: .iphone,
            durationSeconds: 1,
            epochCount: 1,
            stature: profile
        )
        let ground = 987.44 - (StatureMath.holdMeters(profile: profile) ?? 0)
        XCTAssertEqual(condition.stature?.groundHeightMeters ?? 0, ground, accuracy: 1e-9)
        XCTAssertEqual(condition.surveyEllipsoidalMeters ?? 0, ground, accuracy: 1e-6)
        let undulation = JapanGeoid.undulationMeters(latitudeDegrees: 36.77450, longitudeDegrees: 139.20081) ?? 0
        XCTAssertEqual(condition.orthometricHeightMeters ?? 0, ground - undulation, accuracy: 1e-6)
    }
}
