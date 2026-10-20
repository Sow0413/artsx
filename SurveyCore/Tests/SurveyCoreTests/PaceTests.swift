import XCTest
@testable import SurveyCore

final class PaceTests: XCTestCase {
    func testCalibrationAndSlopeFactor() {
        let stride = PaceMath.stride(distanceMeters: 50, steps: 70)
        XCTAssertEqual(stride ?? 0, 50.0 / 70.0, accuracy: 1e-12)
        XCTAssertNil(PaceMath.stride(distanceMeters: 50, steps: 2))
        XCTAssertNil(PaceMath.stride(distanceMeters: 1, steps: 10))
        XCTAssertEqual(PaceMath.slopeFactor(0) ?? 0, 1, accuracy: 1e-12)
        XCTAssertEqual(PaceMath.slopeFactor(1) ?? 0, 1 / 2.squareRoot(), accuracy: 1e-12)
        let flat = PaceMath.distance(steps: 100, strideMeters: 0.7, slope: 0)
        XCTAssertEqual(flat ?? 0, 70, accuracy: 1e-12)
        let slope = PaceMath.distance(steps: 100, strideMeters: 0.7, slope: 1)
        XCTAssertEqual(slope ?? 0, 70 / 2.squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(PaceMath.distance(steps: 10, strideMeters: 0.8, slope: 1, factorOverride: 0.5) ?? 0, 4, accuracy: 1e-12)
        XCTAssertEqual(PaceMath.paceSigma(distanceMeters: 50), 1.5, accuracy: 1e-12)
        print("SURVEY PACE 50m")
    }

    func testPaceBadgeIsStageZero() {
        let badge = PaceMath.badge(distanceMeters: 48.2, sigmaMeters: 1.5)
        XCTAssertEqual(PaceBadge.label, "歩測")
        XCTAssertEqual(PaceMath.kind, "歩測")
        XCTAssertTrue(badge.accessibilityText.contains("歩測"))
        XCTAssertTrue(badge.accessibilityText.contains("段階0"))
        XCTAssertFalse(badge.isStakeoutGrade)
        let position = IPhonePosition.make(
            latitudeDegrees: 35,
            longitudeDegrees: 139,
            ellipsoidalHeightMeters: 40,
            horizontalAccuracyMeters: 1.5,
            verticalAccuracyMeters: nil,
            timestamp: Date()
        )
        XCTAssertEqual(position.stage, .iphone)
        XCTAssertFalse(position.isTrustedRTKFix)
    }

    func testStepsAndHeadingPlaceTheEnd() {
        var bridge = WalkBridge(originLatitude: 35, originLongitude: 139, strideMeters: 0.8, slope: 0)
        bridge.add(totalSteps: 10, headingDegrees: nil)
        XCTAssertEqual(bridge.steps, 0)
        bridge.add(totalSteps: 10, headingDegrees: 90)
        XCTAssertEqual(bridge.pathMeters, 8, accuracy: 1e-12)
        XCTAssertEqual(bridge.eastMeters, 8, accuracy: 1e-9)
        let fix = bridge.place()
        XCTAssertEqual(fix?.steps, 10)
        XCTAssertEqual(fix?.usedVisual, false)
        XCTAssertEqual(fix?.sigmaMeters ?? 0, PaceMath.bridgeSigma(pathMeters: 8, disagreementMeters: 0), accuracy: 1e-12)
        let back = GRS80Geodesic.inverse(
            latitude1: 35, longitude1: 139,
            latitude2: fix?.latitudeDegrees ?? 0, longitude2: fix?.longitudeDegrees ?? 0
        )
        XCTAssertEqual(back?.distanceMeters ?? 0, 8, accuracy: 0.05)
        XCTAssertEqual(back?.azimuthDegrees ?? 0, 90, accuracy: 0.2)
    }

    func testVisualDisagreementWidensTheErrorAndGNSSReturns() {
        var bridge = WalkBridge(originLatitude: 35, originLongitude: 139, strideMeters: 0.7, slope: 0)
        bridge.add(totalSteps: 100, headingDegrees: 0)
        bridge.setVisual(east: 0, north: 60)
        let fix = bridge.place()
        XCTAssertEqual(fix?.usedVisual, true)
        XCTAssertGreaterThan(fix?.sigmaMeters ?? 0, PaceMath.bridgeSigma(pathMeters: 70, disagreementMeters: 0))
        let north = GRS80Geodesic.inverse(
            latitude1: 35, longitude1: 139,
            latitude2: fix?.latitudeDegrees ?? 0, longitude2: fix?.longitudeDegrees ?? 0
        )
        XCTAssertEqual(north?.distanceMeters ?? 0, 65, accuracy: 0.2)

        XCTAssertEqual(PaceMath.nextMode(current: .gnss, accuracyMeters: 40), .bridge)
        XCTAssertEqual(PaceMath.nextMode(current: .bridge, accuracyMeters: 10), .bridge)
        XCTAssertEqual(PaceMath.nextMode(current: .bridge, accuracyMeters: 5), .gnss)
        XCTAssertEqual(PaceMath.nextMode(current: .gnss, accuracyMeters: nil), .bridge)
        XCTAssertEqual(PaceMath.sharedAccuracy(gnssMeters: 40, bridgeSigmaMeters: 2.5, mode: .bridge), 2.5)
        XCTAssertEqual(PaceMath.sharedAccuracy(gnssMeters: 4, bridgeSigmaMeters: 2.5, mode: .gnss), 4)
    }

    func testYawTurnsVisualAxesIntoEastAndNorth() {
        let forward = PaceMath.forwardFromPlusZ(x: 0, z: 1)
        XCTAssertEqual(forward ?? 1, 0, accuracy: 1e-12)
        let yaw = PaceMath.yawOfPlusZ(headingDegrees: 90, forwardFromPlusZDegrees: 0)
        XCTAssertEqual(yaw ?? 0, 90, accuracy: 1e-12)
        let east = PaceMath.horizontal(dx: 0, dz: 10, yawDegrees: 90)
        XCTAssertEqual(east?.east ?? 0, 10, accuracy: 1e-12)
        XCTAssertEqual(east?.north ?? 1, 0, accuracy: 1e-9)
        let north = PaceMath.horizontal(dx: 0, dz: 10, yawDegrees: 0)
        XCTAssertEqual(north?.north ?? 0, 10, accuracy: 1e-12)
        XCTAssertEqual(north?.east ?? 1, 0, accuracy: 1e-9)
    }

    func testProfileRoundTripDoesNotTouchStature() {
        let name = "pace-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let profile = PaceProfile(strideMeters: 50.0 / 70.0, slope: 0.1, calibratedDistanceMeters: 50, calibratedSteps: 70)
        profile.save(to: defaults)
        let loaded = PaceProfile.load(from: defaults)
        XCTAssertEqual(loaded.strideMeters ?? 0, 50.0 / 70.0, accuracy: 1e-12)
        XCTAssertEqual(loaded.calibratedDistanceMeters ?? 0, 50, accuracy: 1e-12)
        XCTAssertEqual(loaded.calibratedSteps, 70)
        XCTAssertNotEqual(PaceProfile.storageKey, StatureProfile.storageKey)
        XCTAssertNil(StatureProfile.load(from: defaults).statureMeters)
    }
}
