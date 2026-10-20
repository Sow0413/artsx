import XCTest
@testable import SurveyCore

final class PersonalProfileTests: XCTestCase {
    func testOneHeightSetsHoldAndInitialStride() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let adopted = PersonalProfile.adopt(
            statureMeters: 1.70,
            stature: StatureProfile(),
            pace: PaceProfile(),
            at: at
        )
        let stature = adopted?.stature
        let pace = adopted?.pace
        XCTAssertEqual(stature?.style, .sight)
        XCTAssertEqual(stature?.statureMeters ?? 0, 1.70, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.eyeHeight(stature!) ?? 0, 1.60, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.holdMeters(profile: StatureProfile(statureMeters: 1.70, style: .elbow)) ?? 0, 1.19, accuracy: 1e-12)
        XCTAssertEqual(pace?.strideMeters ?? 0, 1.70 * 0.45, accuracy: 1e-12)
        XCTAssertEqual(pace?.strideOrigin, .stature)
        XCTAssertEqual(pace?.strideSetAt, at)
        XCTAssertNil(pace?.calibratedSteps)
        let again = PersonalProfile.adopt(statureMeters: 1.70, stature: stature!, pace: pace!, at: at.addingTimeInterval(100))
        XCTAssertEqual(again?.pace.strideSetAt, at)
        XCTAssertEqual(PersonalProfile.dayText(at), "2023-11-15")
        XCTAssertTrue(PersonalProfile.strideLine(pace!).contains("身長×0.45"))
        print("SURVEY PROFILE 身長×0.45")
    }

    func testWalkedStrideSurvivesALaterHeightAndStatureStrideUpdates() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let seeded = PersonalProfile.adopt(statureMeters: 1.70, stature: StatureProfile(), pace: PaceProfile(), at: at)
        let grown = PersonalProfile.adopt(
            statureMeters: 1.80,
            stature: seeded!.stature,
            pace: seeded!.pace,
            at: at.addingTimeInterval(86_400)
        )
        XCTAssertEqual(grown?.stature.statureMeters ?? 0, 1.80, accuracy: 1e-12)
        XCTAssertEqual(grown?.pace.strideMeters ?? 0, 1.80 * 0.45, accuracy: 1e-12)
        XCTAssertEqual(grown?.pace.strideOrigin, .stature)

        let walked = PaceProfile(
            strideMeters: 0.80,
            calibratedDistanceMeters: 50,
            calibratedSteps: 70,
            strideOrigin: .walked,
            strideSetAt: at
        )
        let kept = PersonalProfile.adopt(statureMeters: 1.90, stature: grown!.stature, pace: walked, at: at.addingTimeInterval(10))
        XCTAssertEqual(kept?.pace.strideMeters ?? 0, 0.80, accuracy: 1e-12)
        XCTAssertEqual(kept?.pace.strideOrigin, .walked)
        XCTAssertEqual(kept?.pace.strideSetAt, at)
        XCTAssertEqual(kept?.stature.statureMeters ?? 0, 1.90, accuracy: 1e-12)

        let legacy = PaceProfile(strideMeters: 0.71, calibratedDistanceMeters: 50, calibratedSteps: 70)
        XCTAssertTrue(legacy.keepsWalkedStride)
        let legacyKept = PersonalProfile.adopt(statureMeters: 1.70, stature: StatureProfile(), pace: legacy, at: at)
        XCTAssertEqual(legacyKept?.pace.strideMeters ?? 0, 0.71, accuracy: 1e-12)
        XCTAssertNil(PersonalProfile.adopt(statureMeters: 0, stature: StatureProfile(), pace: PaceProfile(), at: at))
        XCTAssertNil(PaceMath.initialStride(statureMeters: 0.50))
        let short = PersonalProfile.adopt(statureMeters: 0.50, stature: StatureProfile(), pace: PaceProfile(), at: at)
        XCTAssertEqual(short?.stature.statureMeters ?? 0, 0.50, accuracy: 1e-12)
        XCTAssertNil(short?.pace.strideMeters)
    }

    func testCalibrationDatesStayOnTheDevice() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let calibration = StatureMath.calibrate(deviceHeight: 12.4, knownGround: 11.2, stature: 1.70)
        let applied = StatureMath.applying(calibration!, to: StatureProfile(statureMeters: 1.70), at: at)
        XCTAssertEqual(applied.holdCalibration?.at, at)
        XCTAssertEqual(applied.holdCalibration?.holdMeters ?? 0, 1.2, accuracy: 1e-12)
        XCTAssertEqual(applied.holdCalibration?.knownGroundMeters ?? 0, 11.2, accuracy: 1e-12)
        XCTAssertEqual(applied.style, .elbow)

        var pace = PaceProfile()
        pace.strideMeters = 50.0 / 70.0
        pace.calibratedDistanceMeters = 50
        pace.calibratedSteps = 70
        pace.strideOrigin = .walked
        pace.strideSetAt = at

        let name = "body-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        applied.save(to: defaults)
        pace.save(to: defaults)
        let loadedStature = StatureProfile.load(from: defaults)
        let loadedPace = PaceProfile.load(from: defaults)
        XCTAssertEqual(loadedStature.holdCalibration?.at, at)
        XCTAssertEqual(loadedStature.holdCalibration?.elbowFactor ?? 0, applied.coefficients.elbowFactor, accuracy: 1e-12)
        XCTAssertEqual(loadedPace.strideOrigin, .walked)
        XCTAssertEqual(loadedPace.strideSetAt, at)
        XCTAssertEqual(loadedPace.calibratedSteps, 70)
        XCTAssertNil(PoleHeight.load(from: defaults).meters)
        XCTAssertNil(defaults.data(forKey: "survey.share.body"))
        XCTAssertEqual(PersonalProfile.deviceKeys, [StatureProfile.storageKey, PaceProfile.storageKey])
        XCTAssertNotEqual(StatureProfile.storageKey, PaceProfile.storageKey)
        let lines = PersonalProfile.recordLines(stature: loadedStature, pace: loadedPace)
        XCTAssertTrue(lines.contains { $0.contains("2023-11-15") && $0.contains("持ち高さ") })
        XCTAssertTrue(lines.contains { $0.contains("2023-11-15") && $0.hasPrefix("歩幅") })
        XCTAssertFalse(lines.joined().contains("survey.stature"))
    }
}
