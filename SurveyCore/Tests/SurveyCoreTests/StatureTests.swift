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
