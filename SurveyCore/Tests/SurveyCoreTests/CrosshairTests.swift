import XCTest
@testable import SurveyCore

final class CrosshairTests: XCTestCase {
    func testLevelUsesGroundPlusEyeAndStaffReading() {
        let shot = CrosshairMath.level(ground: 10, eye: 1.60, staff: 1.20)
        XCTAssertEqual(shot?.instrumentHeightMeters ?? 0, 11.60, accuracy: 1e-12)
        XCTAssertEqual(shot?.heightDifferenceMeters ?? 0, 0.40, accuracy: 1e-12)
        XCTAssertEqual(shot?.targetHeightMeters ?? 0, 10.40, accuracy: 1e-12)

        let levelGround = CrosshairMath.level(ground: 10, eye: 1.60, staff: 1.60)
        XCTAssertEqual(levelGround?.heightDifferenceMeters ?? 1, 0, accuracy: 1e-12)
        XCTAssertNil(CrosshairMath.level(ground: 10, eye: 1.60, staff: -0.1))
        XCTAssertNil(CrosshairMath.level(ground: .nan, eye: 1.60, staff: 1))
    }

    func testHorizontalLockIsATenthOfADegree() {
        let band = CrosshairMath.levelToleranceRadians
        XCTAssertTrue(CrosshairMath.isLevel(0))
        XCTAssertTrue(CrosshairMath.isLevel(band))
        XCTAssertTrue(CrosshairMath.isLevel(-band))
        XCTAssertFalse(CrosshairMath.isLevel(band + 0.02 * .pi / 180))
        XCTAssertFalse(CrosshairMath.isLevel(.nan))
    }

    func testReversalZerosTheBias() {
        let bias = TiltZero.reversal(firstRadians: 0.004, reversedRadians: 0.002)
        XCTAssertEqual(bias ?? 0, 0.003, accuracy: 1e-12)
        let zero = TiltZero(biasRadians: bias ?? 0, calibrated: true)
        XCTAssertEqual(zero.corrected(0.004) ?? 0, 0.001, accuracy: 1e-12)
        XCTAssertNil(TiltZero.reversal(firstRadians: .nan, reversedRadians: 0))

        let name = "crosshair-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        XCTAssertFalse(TiltZero.load(from: defaults).calibrated)
        zero.save(to: defaults)
        let loaded = TiltZero.load(from: defaults)
        XCTAssertTrue(loaded.calibrated)
        XCTAssertEqual(loaded.biasRadians, 0.003, accuracy: 1e-12)
    }

    func testTargetUsesDistanceSineAndRegistersStageZero() {
        let elevation = Double.pi / 6
        let distance = 20.0
        let shot = CrosshairMath.target(
            originLatitude: 35,
            originLongitude: 139,
            originHeight: 40,
            distance: distance,
            elevationRadians: elevation,
            azimuthDegrees: 90,
            angleSigmaRadians: CrosshairMath.angleSigmaRadians(calibrated: true),
            distanceSigma: CrosshairMath.distanceSigma(range: .lidar, distance: distance)
        )
        XCTAssertEqual(shot?.heightDifferenceMeters ?? 0, 10, accuracy: 1e-9)
        XCTAssertEqual(shot?.horizontalMeters ?? 0, 10 * 3.0.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(shot?.targetHeightMeters ?? 0, 50, accuracy: 1e-9)
        let direct = GRS80Geodesic.direct(
            latitude: 35,
            longitude: 139,
            azimuthDegrees: 90,
            distanceMeters: shot?.horizontalMeters ?? 0
        )
        XCTAssertEqual(shot?.latitudeDegrees ?? 0, direct?.latitude ?? -1, accuracy: 1e-9)
        XCTAssertEqual(shot?.longitudeDegrees ?? 0, direct?.longitude ?? -1, accuracy: 1e-9)

        let down = CrosshairMath.target(
            originLatitude: nil,
            originLongitude: nil,
            originHeight: 40,
            distance: 10,
            elevationRadians: -.pi / 6,
            azimuthDegrees: nil,
            angleSigmaRadians: 0,
            distanceSigma: 0
        )
        XCTAssertEqual(down?.heightDifferenceMeters ?? 0, -5, accuracy: 1e-9)
        XCTAssertNil(down?.latitudeDegrees)
        XCTAssertNil(CrosshairMath.target(
            originLatitude: 35,
            originLongitude: 139,
            originHeight: 1,
            distance: -1,
            elevationRadians: 0,
            azimuthDegrees: 0,
            angleSigmaRadians: 0,
            distanceSigma: 0
        ))
    }

    func testErrorAtTwentyMetersAndTheStageZeroBadge() {
        let calibrated = CrosshairMath.heightSigma(
            distance: 20,
            elevationRadians: 0,
            angleSigmaRadians: CrosshairMath.angleSigmaRadians(calibrated: true),
            distanceSigma: 0
        )
        XCTAssertEqual(calibrated, 20 * 0.1 * .pi / 180, accuracy: 1e-12)
        XCTAssertEqual(CrosshairMath.exampleLabel(calibrated: true), "20mで ±3.5cm")
        let raw = CrosshairMath.heightSigma(
            distance: 20,
            elevationRadians: 0,
            angleSigmaRadians: CrosshairMath.angleSigmaRadians(calibrated: false),
            distanceSigma: 0
        )
        XCTAssertEqual(raw, 20 * .pi / 180, accuracy: 1e-12)
        XCTAssertGreaterThan(raw, calibrated)
        print("SURVEY CROSSHAIR \(CrosshairMath.exampleLabel(calibrated: true))")

        let stored = CrosshairMath.storedAccuracy(
            originHorizontal: 5,
            originVertical: 8,
            aimHorizontal: 0.03,
            aimVertical: calibrated
        )
        XCTAssertEqual(stored.horizontal, (25 + 0.03 * 0.03).squareRoot(), accuracy: 1e-9)
        let position = CrosshairMath.position(
            latitude: 35,
            longitude: 139,
            height: 50,
            horizontalAccuracy: stored.horizontal,
            verticalAccuracy: stored.vertical,
            at: Date(timeIntervalSince1970: 0)
        )
        XCTAssertEqual(position.stage, .iphone)
        XCTAssertEqual(position.receiver, .iphoneGPS)
        XCTAssertEqual(position.fixQuality, .standalone)
        XCTAssertFalse(position.isTrustedRTKFix)
        let badge = AccuracyPolicy.badge(
            for: PositionReading(position: position, availability: .available),
            operatingStage: .iphone
        )
        XCTAssertFalse(badge.isStakeoutGrade)
        XCTAssertTrue(badge.isPhoneSelfEstimate)
        XCTAssertTrue(badge.accessibilityText.contains(AccuracyFormat.phoneEstimateNote))
        XCTAssertFalse(badge.accessibilityText.contains("段階0"))
        XCTAssertEqual(CrosshairMath.kind, "簡易ターゲット")
    }
}
