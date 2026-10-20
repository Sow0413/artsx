import XCTest
@testable import SurveyCore

final class StatureTests: XCTestCase {
    func testChestEyeGroundCabAndManual() {
        let chest = StatureProfile(statureMeters: 1.71, style: .chest)
        let chestHold = StatureMath.holdMeters(profile: chest) ?? -1
        XCTAssertEqual(chestHold, 1.71 * 0.72, accuracy: 1e-12)
        let chestRecord = StatureMath.correction(for: chest, stage: .iphone, receiver: .iphoneGPS)
        XCTAssertEqual(chestRecord?.screenLabel, "身長補正 −1.23m")
        print("SURVEY STATURE \(chestRecord?.screenLabel ?? "")")

        let eye = StatureProfile(statureMeters: 1.80, style: .eye)
        XCTAssertEqual(StatureMath.holdMeters(profile: eye) ?? -1, 1.70, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.correction(for: eye, stage: .iphone, receiver: .iphoneGPS)?.screenLabel, "身長補正 −1.70m")

        let ground = StatureProfile(style: .ground)
        XCTAssertEqual(StatureMath.holdMeters(profile: ground), 0)
        XCTAssertEqual(StatureMath.correction(for: ground, stage: .iphone, receiver: .iphoneGPS)?.screenLabel, "身長補正 −0.00m")

        let cab = StatureProfile(style: .cab)
        XCTAssertEqual(StatureCoefficients.standard.cabMeters, 2)
        XCTAssertEqual(StatureMath.holdMeters(profile: cab), 2)
        XCTAssertNil(cab.statureMeters)

        let manual = StatureProfile(style: .manual, manualMeters: 1.23)
        XCTAssertEqual(StatureMath.correction(for: manual, stage: .iphone, receiver: .iphoneGPS)?.screenLabel, "身長補正 −1.23m")
    }

    func testCoefficientsAndMissingStature() {
        var profile = StatureProfile(statureMeters: 1.70, style: .chest, coefficients: StatureCoefficients(chestFactor: 0.70, eyeDropMeters: 0.10, cabMeters: 2))
        XCTAssertEqual(StatureMath.holdMeters(profile: profile) ?? -1, 1.19, accuracy: 1e-12)
        profile.style = .eye
        profile.coefficients.eyeDropMeters = 2
        XCTAssertEqual(StatureMath.holdMeters(profile: profile), 0)
        profile.statureMeters = nil
        profile.style = .chest
        XCTAssertNil(StatureMath.holdMeters(profile: profile))
        XCTAssertEqual(StatureMath.notice(profile: profile, stage: .iphone, receiver: .iphoneGPS), "身長が未登録です")
    }

    func testStageZeroIPhoneOnlyAndPoleHeightStaysSeparate() {
        let profile = StatureProfile(statureMeters: 1.71, style: .chest)
        XCTAssertNil(StatureMath.correction(for: profile, stage: .rtk, receiver: .rtk))
        XCTAssertNil(StatureMath.correction(for: profile, stage: .iphone, receiver: .rtk))
        XCTAssertNil(StatureMath.correction(for: profile, stage: .clas, receiver: .iphoneGPS))
        XCTAssertNotNil(StatureMath.correction(for: profile, stage: .iphone, receiver: .iphoneGPS))

        let name = "stature-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        profile.save(to: defaults)
        PoleHeight(meters: 2.0).save(to: defaults)
        let loaded = StatureProfile.load(from: defaults)
        XCTAssertEqual(loaded.statureMeters ?? 0, 1.71, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.holdMeters(profile: loaded) ?? 0, 1.71 * 0.72, accuracy: 1e-12)
        XCTAssertEqual(PoleHeight.load(from: defaults).meters ?? 0, 2)
        XCTAssertNotEqual(PoleHeight.storageKey, StatureProfile.storageKey)
    }

    func testCaptureKeepsDeviceHeightAndCanReapply() throws {
        let position = samplePosition(height: 12.4)
        var profile = StatureProfile(statureMeters: 1.71, style: .chest)
        let condition = ObservationCondition.snapshot(
            position: position,
            stage: .iphone,
            durationSeconds: 1,
            epochCount: 1,
            stature: profile
        )
        XCTAssertEqual(condition.stature?.style, .chest)
        XCTAssertEqual(condition.stature?.offsetMeters ?? 0, -(1.71 * 0.72), accuracy: 1e-12)
        let observation = FieldObservation(name: "T1", workID: "preview", captured: position, condition: condition)
        XCTAssertEqual(observation.captured.ellipsoidalHeightMeters ?? 0, 12.4, accuracy: 1e-12)
        let ground = 12.4 - (1.71 * 0.72)
        XCTAssertEqual(observation.condition?.stature?.groundHeightMeters ?? 0, ground, accuracy: 1e-9)
        let entry = CoordinateBookIndex.entry(from: observation, kind: "下見")
        XCTAssertEqual(entry.ellipsoidalHeightMeters ?? 0, ground, accuracy: 1e-9)
        let lines = condition.reportLines.joined(separator: "\n")
        XCTAssertTrue(lines.contains("身長補正 −1.23m（胸の前）"))
        XCTAssertTrue(lines.contains("地盤高"))

        profile.statureMeters = 1.80
        profile.style = .eye
        let redone = observation.applying(profile)
        XCTAssertEqual(redone.captured.ellipsoidalHeightMeters ?? 0, 12.4, accuracy: 1e-12)
        XCTAssertEqual(redone.condition?.stature?.style, .eye)
        XCTAssertEqual(redone.condition?.stature?.holdMeters ?? 0, 1.70, accuracy: 1e-12)
        XCTAssertEqual(redone.condition?.stature?.groundHeightMeters ?? 0, 12.4 - 1.70, accuracy: 1e-9)
        XCTAssertEqual(redone.condition?.stature?.statureMeters ?? 0, 1.80, accuracy: 1e-12)

        let external = FieldObservation(
            name: "K1",
            workID: "boundary",
            captured: samplePosition(height: 40, stage: .rtk, quality: .rtkFix, receiver: .rtk),
            condition: nil
        )
        XCTAssertEqual(external.applying(profile).captured.ellipsoidalHeightMeters ?? 0, 40, accuracy: 1e-12)
        XCTAssertNil(external.applying(profile).condition?.stature)
    }

    func testElbowIsDefaultAndFirstPreset() {
        let fresh = StatureProfile()
        XCTAssertEqual(fresh.style, .elbow)
        XCTAssertEqual(fresh.coefficients.elbowFactor, 0.70, accuracy: 1e-12)
        XCTAssertEqual(fresh.coefficients.chestFactor, 0.72, accuracy: 1e-12)
        XCTAssertNil(fresh.statureMeters)
        XCTAssertEqual(HoldStyle.allCases.first, .elbow)
        XCTAssertEqual(HoldStyle.elbow.menuTitle(coefficients: .standard), "肘より上（身長×0.70）")

        let profile = StatureProfile(statureMeters: 1.70)
        XCTAssertEqual(StatureMath.holdMeters(profile: profile) ?? -1, 1.19, accuracy: 1e-12)
        let label = StatureMath.correction(for: profile, stage: .iphone, receiver: .iphoneGPS)?.screenLabel
        XCTAssertEqual(label, "身長補正 −1.19m")
        print("SURVEY STATURE \(label ?? "")")
    }

    func testOldProfilesKeepChestWhenElbowFactorIsMissing() throws {
        let coefficients = try JSONDecoder().decode(
            StatureCoefficients.self,
            from: Data(#"{"chestFactor":0.72,"eyeDropMeters":0.1,"cabMeters":2}"#.utf8)
        )
        XCTAssertEqual(coefficients.elbowFactor, 0.70, accuracy: 1e-12)
        XCTAssertEqual(coefficients.chestFactor, 0.72, accuracy: 1e-12)

        let profileJSON = #"{"statureMeters":1.71,"style":"chest","manualMeters":1.2,"coefficients":{"chestFactor":0.72,"eyeDropMeters":0.1,"cabMeters":2}}"#
        let name = "stature-old-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(Data(profileJSON.utf8), forKey: StatureProfile.storageKey)
        let loaded = StatureProfile.load(from: defaults)
        XCTAssertEqual(loaded.style, .chest)
        XCTAssertEqual(loaded.coefficients.elbowFactor, 0.70, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.holdMeters(profile: loaded) ?? 0, 1.71 * 0.72, accuracy: 1e-12)

        let record = try JSONDecoder().decode(
            StatureRecord.self,
            from: Data(#"{"style":"chest","offsetMeters":-1.2312,"holdMeters":1.2312,"statureMeters":1.71,"chestFactor":0.72,"eyeDropMeters":0.1,"cabMeters":2,"groundHeightMeters":11.1688}"#.utf8)
        )
        XCTAssertEqual(record.style, .chest)
        XCTAssertEqual(record.elbowFactor, 0.70, accuracy: 1e-12)
        XCTAssertEqual(record.screenLabel, "身長補正 −1.23m")
    }

    func testCalibrationSetsElbowFactorFromOneKnownPoint() {
        let calibration = StatureMath.calibrate(deviceHeight: 12.4, knownGround: 11.2, stature: 1.70)
        let hold = 12.4 - 11.2
        XCTAssertEqual(calibration?.holdMeters ?? -1, hold, accuracy: 1e-12)
        XCTAssertEqual(calibration?.elbowFactor ?? -1, hold / 1.70, accuracy: 1e-12)
        let applied = StatureMath.applying(calibration!, to: StatureProfile(statureMeters: 1.70, style: .chest))
        XCTAssertEqual(applied.style, .elbow)
        XCTAssertEqual(applied.statureMeters ?? 0, 1.70, accuracy: 1e-12)
        XCTAssertEqual(StatureMath.holdMeters(profile: applied) ?? -1, hold, accuracy: 1e-9)
        XCTAssertNil(StatureMath.calibrate(deviceHeight: 10, knownGround: 12, stature: 1.70))
        XCTAssertNil(StatureMath.calibrate(deviceHeight: 12, knownGround: 11, stature: 0))
        XCTAssertNil(StatureMath.calibrate(deviceHeight: .nan, knownGround: 1, stature: 1.7))
    }

    func testOldConditionWithoutStatureStillLoads() throws {
        let position = samplePosition()
        let condition = ObservationCondition.snapshot(position: position, stage: .iphone, durationSeconds: nil, epochCount: nil)
        let data = try JSONEncoder().encode(condition)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object.removeValue(forKey: "stature")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(ObservationCondition.self, from: stripped)
        XCTAssertEqual(decoded.stage, .iphone)
        XCTAssertNil(decoded.stature)
        XCTAssertFalse(decoded.reportLines.joined(separator: "\n").contains("身長補正"))
    }
}
