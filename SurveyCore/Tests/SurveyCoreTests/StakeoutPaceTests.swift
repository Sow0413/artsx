import XCTest
@testable import SurveyCore

final class StakeoutPaceTests: XCTestCase {
    func testStepsUseBodyFacingAndPersonalStride() {
        let guide = StakeoutPace.guide(
            distanceMeters: 12.8,
            azimuthDegrees: 45,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(guide?.speech, "右まえ 16歩")
        XCTAssertEqual(guide?.steps, 16)
        XCTAssertEqual(guide?.close, false)
        XCTAssertNil(guide?.detail)
        let ahead = StakeoutPace.guide(
            distanceMeters: 2.4,
            azimuthDegrees: 10,
            facingDegrees: 10,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(ahead?.speech, "前 3歩")
        XCTAssertEqual(ahead?.close, false)
        print("SURVEY STAKEOUT 右まえ 16歩")
    }

    func testUnderThreeStepsSwitchesToCentimetersAndAxes() {
        let straight = StakeoutPace.guide(
            distanceMeters: 0.35,
            azimuthDegrees: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(straight?.speech, "あと35cm前")
        XCTAssertEqual(straight?.detail, "前 35cm")
        XCTAssertEqual(straight?.close, true)

        let distance = (0.35 * 0.35 + 0.12 * 0.12).squareRoot()
        let relative = GeoMath.degrees(fromRadians: GeoMath.arctangent(0.12, 0.35))
        let split = StakeoutPace.guide(
            distanceMeters: distance,
            azimuthDegrees: relative,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(split?.speech, "あと35cm前")
        XCTAssertEqual(split?.detail, "前 35cm　右 12cm")
        XCTAssertLessThan(distance / 0.8, StakeoutPace.closeSteps)

        let almost = StakeoutPace.guide(
            distanceMeters: 2.399,
            azimuthDegrees: 0,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(almost?.close, true)
        XCTAssertTrue(almost?.speech.hasPrefix("あと") == true)
    }

    func testMetersStayMetersAndOperatorStationIsUntouched() {
        let meters = StakeoutPace.guide(
            distanceMeters: 12.4,
            azimuthDegrees: 90,
            facingDegrees: 0,
            strideMeters: 0.8,
            unit: .meters
        )
        XCTAssertEqual(meters?.speech, "現在地から 12 m、北から時計回り 90.0°")
        XCTAssertNil(meters?.detail)
        XCTAssertFalse(meters?.speech.contains("歩") == true)

        let missing = StakeoutPace.guide(
            distanceMeters: 12.8,
            azimuthDegrees: 0,
            facingDegrees: 0,
            strideMeters: nil,
            unit: .steps
        )
        XCTAssertTrue(missing?.speech.contains("歩幅が無いので、メートルで出します。") == true)
        XCTAssertTrue(missing?.speech.contains("現在地から") == true)

        let blind = StakeoutPace.guide(
            distanceMeters: 12.8,
            azimuthDegrees: 90,
            facingDegrees: nil,
            strideMeters: 0.8,
            unit: .steps
        )
        XCTAssertEqual(blind?.speech, "16歩。向きが無いので、方向は出せません。")

        let station = OperatorStation.format(
            chainage: 465,
            geometricAlong: 465,
            geometricTotal: 1000,
            offset: -3.2,
            interval: 20
        )
        XCTAssertTrue(station.contains("m"))
        XCTAssertFalse(station.contains("歩"))
    }

    func testPreferenceDefaultsToStepsAndStaysOnTheDevice() {
        XCTAssertEqual(StakeoutPacePreference().unit, .steps)
        let name = "stakeout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        StakeoutPacePreference(unit: .meters).save(to: defaults)
        XCTAssertEqual(StakeoutPacePreference.load(from: defaults).unit, .meters)
        XCTAssertNil(defaults.data(forKey: StatureProfile.storageKey))
        XCTAssertNil(defaults.data(forKey: PaceProfile.storageKey))
        XCTAssertNil(StakeoutPace.guide(distanceMeters: -1, azimuthDegrees: 0, facingDegrees: 0, strideMeters: 0.8, unit: .steps))
    }
}
